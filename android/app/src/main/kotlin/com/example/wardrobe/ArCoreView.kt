package com.example.wardrobe

import android.app.Activity
import android.content.Context
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.Surface
import android.view.View
import android.view.WindowManager
import com.google.ar.core.*
import com.google.ar.core.exceptions.*
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.util.concurrent.atomic.AtomicBoolean
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10

class ArCoreView(
    private val context: Context,
    private val messenger: BinaryMessenger,
    viewId: Int,
    private val activity: Activity,
) : PlatformView, GLSurfaceView.Renderer {

    companion object {
        private const val TAG = "ArCoreView"
        const val PLANES_CHANNEL = "wardrobe/arcore_planes"
        const val CONTROL_CHANNEL = "wardrobe/arcore_control"

        // Минимальный интервал между отправками данных плоскостей во Flutter (мс)
        private const val PLANE_REPORT_INTERVAL_MS = 300L

        // Интервал рендеринга ~30fps для стабильности ARCore на 90/120Hz дисплеях
        private const val RENDER_INTERVAL_MS = 33L

        private const val VERTEX_SHADER = """
            attribute vec4 a_Position;
            attribute vec2 a_TexCoord;
            varying vec2 v_TexCoord;
            void main() {
                gl_Position = a_Position;
                v_TexCoord = a_TexCoord;
            }
        """

        private const val FRAGMENT_SHADER = """
            #extension GL_OES_EGL_image_external : require
            precision mediump float;
            varying vec2 v_TexCoord;
            uniform samplerExternalOES u_Texture;
            void main() {
                gl_FragColor = texture2D(u_Texture, v_TexCoord);
            }
        """

        private val QUAD_COORDS = floatArrayOf(
            -1f, -1f,
             1f, -1f,
            -1f,  1f,
             1f,  1f,
        )
    }

    private val glSurfaceView: GLSurfaceView = GLSurfaceView(context)
    private var arSession: Session? = null
    private var sessionPaused = true

    // OpenGL объекты
    private var cameraTextureId = -1
    private var shaderProgram = -1
    private var positionHandle = -1
    private var texCoordHandle = -1
    private var textureUniformHandle = -1

    // Буферы аллоцируются один раз в onSurfaceCreated, переиспользуются каждый кадр
    private lateinit var quadCoordsBuffer: FloatBuffer
    private lateinit var texCoordsBuffer: FloatBuffer
    private val transformedUVs = FloatArray(8) // 4 вершины × 2 координаты

    private var viewportWidth = 0
    private var viewportHeight = 0

    // Throttling отправки плоскостей во Flutter
    private var lastPlaneReportMs = 0L

    // Флаг: предотвращает накопление post-задач в очереди GL-потока
    private val planePendingPost = AtomicBoolean(false)

    private val eventChannel = EventChannel(messenger, "$PLANES_CHANNEL/$viewId")
    private var eventSink: EventChannel.EventSink? = null
    private val controlChannel = MethodChannel(messenger, "$CONTROL_CHANNEL/$viewId")
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
        glSurfaceView.renderMode = GLSurfaceView.RENDERMODE_WHEN_DIRTY
    }

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        GLES20.glClearColor(0f, 0f, 0f, 1f)

        // Аллоцируем буферы один раз — переиспользуем каждый кадр
        quadCoordsBuffer = ByteBuffer
            .allocateDirect(QUAD_COORDS.size * 4)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
            .apply { put(QUAD_COORDS); position(0) }

        texCoordsBuffer = ByteBuffer
            .allocateDirect(transformedUVs.size * 4)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()

        createCameraTexture()
        createShaderProgram()
        initArSession()
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        GLES20.glViewport(0, 0, width, height)
        viewportWidth = width
        viewportHeight = height
        arSession?.setDisplayGeometry(getDisplayRotation(), width, height)
    }

    // Throttling рендеринга — не чаще 30fps для стабильности ARCore
    private var lastRenderMs = 0L

    private fun scheduleNextFrame() {
        Handler(Looper.getMainLooper()).postDelayed({
            glSurfaceView.requestRender()
        }, RENDER_INTERVAL_MS)
    }

    override fun onDrawFrame(gl: GL10?) {
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)

        val session = arSession ?: return
        if (sessionPaused) return

        try {
            session.setCameraTextureName(cameraTextureId)
            val frame = session.update()

            updateTransformedTexCoords(frame)
            drawCameraFrame()

            // Плоскости обрабатываем с throttling — не каждый кадр
            val now = System.currentTimeMillis()
            if (now - lastPlaneReportMs >= PLANE_REPORT_INTERVAL_MS) {
                lastPlaneReportMs = now
                processPlanes(frame)
            }
        } catch (e: CameraNotAvailableException) {
            Log.e(TAG, "Camera not available: ${e.message}")
            sendError("camera_unavailable", e.message ?: "Camera not available")
        } catch (e: Exception) {
            Log.w(TAG, "Frame update error: ${e.message}")
        }

        scheduleNextFrame()
    }

    // ── OpenGL ────────────────────────────────────────────────────────────────

    private fun createCameraTexture() {
        val textures = IntArray(1)
        GLES20.glGenTextures(1, textures, 0)
        cameraTextureId = textures[0]

        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, cameraTextureId)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
    }

    private fun createShaderProgram() {
        val vs = compileShader(GLES20.GL_VERTEX_SHADER, VERTEX_SHADER)
        val fs = compileShader(GLES20.GL_FRAGMENT_SHADER, FRAGMENT_SHADER)

        shaderProgram = GLES20.glCreateProgram().also {
            GLES20.glAttachShader(it, vs)
            GLES20.glAttachShader(it, fs)
            GLES20.glLinkProgram(it)
        }

        positionHandle       = GLES20.glGetAttribLocation(shaderProgram, "a_Position")
        texCoordHandle       = GLES20.glGetAttribLocation(shaderProgram, "a_TexCoord")
        textureUniformHandle = GLES20.glGetUniformLocation(shaderProgram, "u_Texture")
    }

    private fun compileShader(type: Int, source: String): Int {
        return GLES20.glCreateShader(type).also { shader ->
            GLES20.glShaderSource(shader, source)
            GLES20.glCompileShader(shader)
            val status = IntArray(1)
            GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, status, 0)
            if (status[0] == GLES20.GL_FALSE) {
                Log.e(TAG, "Shader error: ${GLES20.glGetShaderInfoLog(shader)}")
            }
        }
    }

    private fun updateTransformedTexCoords(frame: Frame) {
        // Переиспользуем transformedUVs и texCoordsBuffer — без аллокаций
        frame.transformCoordinates2d(
            Coordinates2d.OPENGL_NORMALIZED_DEVICE_COORDINATES,
            QUAD_COORDS,
            Coordinates2d.TEXTURE_NORMALIZED,
            transformedUVs,
        )
        texCoordsBuffer.position(0)
        texCoordsBuffer.put(transformedUVs)
        texCoordsBuffer.position(0)
    }

    private fun drawCameraFrame() {
        if (shaderProgram == -1 || cameraTextureId == -1) return

        GLES20.glUseProgram(shaderProgram)

        quadCoordsBuffer.position(0)
        GLES20.glVertexAttribPointer(positionHandle, 2, GLES20.GL_FLOAT, false, 0, quadCoordsBuffer)
        GLES20.glEnableVertexAttribArray(positionHandle)

        GLES20.glVertexAttribPointer(texCoordHandle, 2, GLES20.GL_FLOAT, false, 0, texCoordsBuffer)
        GLES20.glEnableVertexAttribArray(texCoordHandle)

        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, cameraTextureId)
        GLES20.glUniform1i(textureUniformHandle, 0)

        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)

        GLES20.glDisableVertexAttribArray(positionHandle)
        GLES20.glDisableVertexAttribArray(texCoordHandle)
    }

    // ── ARCore session ────────────────────────────────────────────────────────

    private fun initArSession() {
        try {
            when (ArCoreApk.getInstance().requestInstall(activity, true)) {
                ArCoreApk.InstallStatus.INSTALLED -> createSession()
                ArCoreApk.InstallStatus.INSTALL_REQUESTED ->
                    sendError("install_requested", "ARCore installation required")
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
            if (viewportWidth > 0 && viewportHeight > 0) {
                session.setDisplayGeometry(getDisplayRotation(), viewportWidth, viewportHeight)
            }
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
            glSurfaceView.requestRender()
        } catch (e: CameraNotAvailableException) {
            sendError("camera_unavailable", "Camera not available")
        }
    }

    private fun pauseSession() {
        arSession?.pause()
        sessionPaused = true
    }

    private fun getDisplayRotation(): Int {
        @Suppress("DEPRECATION")
        val rotation = (context.getSystemService(Context.WINDOW_SERVICE) as WindowManager)
            .defaultDisplay.rotation
        return when (rotation) {
            Surface.ROTATION_90  -> 1
            Surface.ROTATION_180 -> 2
            Surface.ROTATION_270 -> 3
            else                 -> 0
        }
    }

    // ── Plane processing ──────────────────────────────────────────────────────

    private fun processPlanes(frame: Frame) {
        val updatedPlanes = frame.getUpdatedTrackables(Plane::class.java)
        if (updatedPlanes.isEmpty()) return

        val toSend = mutableListOf<Map<String, Any>>()

        for (plane in updatedPlanes) {
            if (plane.trackingState != TrackingState.TRACKING) continue

            val id = plane.hashCode().toString()
            val type = when (plane.type) {
                Plane.Type.HORIZONTAL_DOWNWARD_FACING,
                Plane.Type.HORIZONTAL_UPWARD_FACING -> "horizontal"
                Plane.Type.VERTICAL -> "vertical"
                else -> "horizontal"
            }

            val planeData = mapOf(
                "id"      to id,
                "type"    to type,
                "extentX" to plane.extentX.toDouble(),
                "extentZ" to plane.extentZ.toDouble(),
                "centerX" to plane.centerPose.tx().toDouble(),
                "centerY" to plane.centerPose.ty().toDouble(),
                "centerZ" to plane.centerPose.tz().toDouble(),
            )

            val existing = reportedPlanes[id]
            val changed = existing == null ||
                    existing["extentX"] != planeData["extentX"] ||
                    existing["extentZ"] != planeData["extentZ"]

            if (changed) {
                reportedPlanes[id] = planeData
                toSend.add(planeData)
            }
        }

        // Удалённые плоскости
        frame.getUpdatedTrackables(Plane::class.java)
            .filter { it.trackingState == TrackingState.STOPPED }
            .map { it.hashCode().toString() }
            .forEach { removedId ->
                if (reportedPlanes.remove(removedId) != null) {
                    toSend.add(mapOf("id" to removedId, "removed" to true))
                }
            }

        if (toSend.isEmpty()) return

        // Один post на батч изменений; атомарный флаг исключает накопление задач
        if (planePendingPost.compareAndSet(false, true)) {
            val batch = toSend.toList()
            glSurfaceView.post {
                planePendingPost.set(false)
                batch.forEach { eventSink?.success(it) }
            }
        }
    }

    // ── Channels ──────────────────────────────────────────────────────────────

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
                    lastPlaneReportMs = 0L
                    result.success(null)
                }
                "pause"  -> { pauseSession(); result.success(null) }
                "reset"  -> {
                    reportedPlanes.clear()
                    lastPlaneReportMs = 0L
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun sendError(code: String, message: String) {
        glSurfaceView.post { eventSink?.error(code, message, null) }
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
        if (cameraTextureId != -1) {
            GLES20.glDeleteTextures(1, intArrayOf(cameraTextureId), 0)
            cameraTextureId = -1
        }
        if (shaderProgram != -1) {
            GLES20.glDeleteProgram(shaderProgram)
            shaderProgram = -1
        }
        eventChannel.setStreamHandler(null)
        controlChannel.setMethodCallHandler(null)
    }
}
