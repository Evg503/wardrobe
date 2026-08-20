package com.example.wardrobe

import android.content.Context
import android.opengl.GLSurfaceView
import android.util.Log
import android.view.View
import com.google.ar.core.*
import com.google.ar.core.exceptions.*
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10

/**
 * Нативный ARCore-вид, встраиваемый в Flutter через PlatformView.
 *
 * Детектирует горизонтальные и вертикальные плоскости и отправляет
 * обновления во Flutter через EventChannel ("wardrobe/arcore_planes").
 */
class ArCoreView(
    private val context: Context,
    private val messenger: BinaryMessenger,
    viewId: Int
) : PlatformView, GLSurfaceView.Renderer {

    companion object {
        private const val TAG = "ArCoreView"
        const val PLANES_CHANNEL = "wardrobe/arcore_planes"
        const val CONTROL_CHANNEL = "wardrobe/arcore_control"
    }

    private val glSurfaceView: GLSurfaceView = GLSurfaceView(context)
    private var arSession: Session? = null
    private var sessionPaused = true

    // EventChannel для отправки плоскостей во Flutter
    private val eventChannel = EventChannel(messenger, "$PLANES_CHANNEL/$viewId")
    private var eventSink: EventChannel.EventSink? = null

    // MethodChannel для управления сканированием
    private val controlChannel = MethodChannel(messenger, "$CONTROL_CHANNEL/$viewId")

    // Уже отправленные плоскости (trackableId → данные) для дедупликации
    private val reportedPlanes = mutableMapOf<String, Map<String, Any>>()

    init {
        setupGLSurface()
        setupChannels()
    }

    // ── GLSurfaceView ─────────────────────────────────────────────────────────

    private fun setupGLSurface() {
        glSurfaceView.preserveEGLContextOnPause = true
        glSurfaceView.setEGLContextClientVersion(2)
        glSurfaceView.setRenderer(this)
        glSurfaceView.renderMode = GLSurfaceView.RENDERMODE_CONTINUOUSLY
    }

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        initArSession()
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        arSession?.setDisplayGeometry(0, width, height)
    }

    override fun onDrawFrame(gl: GL10?) {
        val session = arSession ?: return
        if (sessionPaused) return

        try {
            session.setCameraTextureName(0) // нет реального рендера — только трекинг
            val frame = session.update()
            processPlanes(frame)
        } catch (e: CameraNotAvailableException) {
            Log.e(TAG, "Camera not available: ${e.message}")
            sendError("camera_unavailable", e.message ?: "Camera not available")
        } catch (e: Exception) {
            Log.w(TAG, "Frame update error: ${e.message}")
        }
    }

    // ── ARCore session ────────────────────────────────────────────────────────

    private fun initArSession() {
        try {
            when (ArCoreApk.getInstance().requestInstall(
                requireActivity(), true
            )) {
                ArCoreApk.InstallStatus.INSTALLED -> {
                    createSession()
                }
                ArCoreApk.InstallStatus.INSTALL_REQUESTED -> {
                    // Пользователю предложено установить AR Services — ждём
                    sendError("install_requested", "ARCore installation required")
                }
            }
        } catch (e: UnavailableUserDeclinedInstallationException) {
            sendError("install_declined", "User declined ARCore installation")
        } catch (e: UnavailableArcoreNotInstalledException) {
            sendError("not_installed", "ARCore not installed")
        } catch (e: UnavailableDeviceNotCompatibleException) {
            sendError("not_compatible", "Device does not support ARCore")
        } catch (e: Exception) {
            sendError("init_error", e.message ?: "Unknown error")
        }
    }

    private fun createSession() {
        try {
            val session = Session(context)
            val config = Config(session).apply {
                planeFindingMode = Config.PlaneFindingMode.HORIZONTAL_AND_VERTICAL
                updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
                lightEstimationMode = Config.LightEstimationMode.DISABLED
            }
            session.configure(config)
            arSession = session
            resumeSession()
        } catch (e: Exception) {
            Log.e(TAG, "Session create error: ${e.message}")
            sendError("session_error", e.message ?: "Session creation failed")
        }
    }

    private fun resumeSession() {
        try {
            arSession?.resume()
            sessionPaused = false
        } catch (e: CameraNotAvailableException) {
            sendError("camera_unavailable", "Camera not available")
        }
    }

    private fun pauseSession() {
        arSession?.pause()
        sessionPaused = true
    }

    // ── Plane processing ──────────────────────────────────────────────────────

    private fun processPlanes(frame: Frame) {
        val updatedPlanes = frame.getUpdatedTrackables(Plane::class.java)
        if (updatedPlanes.isEmpty()) return

        for (plane in updatedPlanes) {
            if (plane.trackingState != TrackingState.TRACKING) continue

            val id = plane.hashCode().toString()
            val type = when (plane.type) {
                Plane.Type.HORIZONTAL_DOWNWARD_FACING,
                Plane.Type.HORIZONTAL_UPWARD_FACING -> "horizontal"
                Plane.Type.VERTICAL -> "vertical"
                else -> "horizontal"
            }

            val extentX = plane.extentX.toDouble()
            val extentZ = plane.extentZ.toDouble()
            val centerPose = plane.centerPose

            val planeData = mapOf(
                "id" to id,
                "type" to type,
                "extentX" to extentX,
                "extentZ" to extentZ,
                "centerX" to centerPose.tx().toDouble(),
                "centerY" to centerPose.ty().toDouble(),
                "centerZ" to centerPose.tz().toDouble(),
            )

            // Отправляем только если данные изменились
            val existing = reportedPlanes[id]
            val changed = existing == null ||
                    existing["extentX"] != planeData["extentX"] ||
                    existing["extentZ"] != planeData["extentZ"]

            if (changed) {
                reportedPlanes[id] = planeData
                glSurfaceView.post {
                    eventSink?.success(planeData)
                }
            }
        }

        // Удалённые плоскости
        val allIds = frame.getUpdatedTrackables(Plane::class.java)
            .filter { it.trackingState == TrackingState.STOPPED }
            .map { it.hashCode().toString() }
        for (removedId in allIds) {
            if (reportedPlanes.remove(removedId) != null) {
                glSurfaceView.post {
                    eventSink?.success(mapOf("id" to removedId, "removed" to true))
                }
            }
        }
    }

    // ── Channels setup ────────────────────────────────────────────────────────

    private fun setupChannels() {
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }
            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })

        controlChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "resume" -> {
                    resumeSession()
                    reportedPlanes.clear()
                    result.success(null)
                }
                "pause" -> {
                    pauseSession()
                    result.success(null)
                }
                "reset" -> {
                    reportedPlanes.clear()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun requireActivity(): android.app.Activity {
        return (context as? android.app.Activity)
            ?: throw IllegalStateException("Context is not an Activity")
    }

    private fun sendError(code: String, message: String) {
        glSurfaceView.post {
            eventSink?.error(code, message, null)
        }
    }

    // ── PlatformView lifecycle ────────────────────────────────────────────────

    override fun getView(): View = glSurfaceView

    override fun onFlutterViewAttached(flutterView: View) {
        glSurfaceView.onResume()
        if (arSession != null) resumeSession()
    }

    override fun onFlutterViewDetached() {
        pauseSession()
        glSurfaceView.onPause()
    }

    override fun dispose() {
        pauseSession()
        glSurfaceView.onPause()
        arSession?.close()
        arSession = null
        eventChannel.setStreamHandler(null)
        controlChannel.setMethodCallHandler(null)
    }
}
