package com.example.wardrobe

import android.app.Activity
import android.content.Context
import android.opengl.GLES11Ext
import android.opengl.GLES20
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
 * Рендерит видеопоток камеры через OES-текстуру + GLSL шейдер,
 * параллельно детектирует плоскости и отправляет данные во Flutter
 * через EventChannel.
 */
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

        // Вершинный шейдер — full-screen quad
        private const val VERTEX_SHADER = """
            attribute vec4 a_Position;
            attribute vec2 a_TexCoord;
            varying vec2 v_TexCoord;
            void main() {
                gl_Position = a_Position;
                v_TexCoord = a_TexCoord;
            }
        """

        // Фрагментный шейдер — семплирует OES-текстуру (кадр камеры)
        private const val FRAGMENT_SHADER = """
            #extension GL_OES_EGL_image_external : require
            precision mediump float;
            varying vec2 v_TexCoord;
            uniform samplerExternalOES u_Texture;
            void main() {
                gl_FragColor = texture2D(u_Texture, v_TexCoord);
            }
        """

        // Координаты вершин full-screen quad
        private val QUAD_COORDS = floatArrayOf(
            -1f, -1f,   // bottom-left
             1f, -1f,   // bottom-right
            -1f,  1f,   // top-left
             1f,  1f,   // top-right
        )

        // UV-координаты (Y перевёрнут — OpenGL и Android отличаются)
        private val QUAD_TEXCOORDS = floatArrayOf(
            0f, 1f,
            1f, 1f,
            0f, 0f,
            1f, 0f,
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

    // EventChannel для отправки плоскостей во Flutter
    private val eventChannel = EventChannel(messenger, "$PLANES_CHANNEL/$viewId")
    private var eventSink: EventChannel.EventSink? = null

    // MethodChannel для управления сканированием
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
        glSurfaceView.renderMode = GLSurfaceView.RENDERMODE_CONTINUOUSLY
    }

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        GLES20.glClearColor(0f, 0f, 0f, 1f)
        createCameraTexture()
        createShaderProgram()
        initArSession()
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        GLES20.glViewport(0, 0, width, height)
        arSession?.setDisplayGeometry(0, width, height)
    }

    override fun onDrawFrame(gl: GL10?) {
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)

        val session = arSession ?: return
        if (sessionPaused) return

        try {
            session.setCameraTextureName(cameraTextureId)
            val frame = session.update()

            // Рисуем кадр камеры
            drawCameraFrame()

            // Обрабатываем плоскости
            processPlanes(frame)
        } catch (e: CameraNotAvailableException) {
            Log.e(TAG, "Camera not available: ${e.message}")
            sendError("camera_unavailable", e.message ?: "Camera not available")
        } catch (e: Exception) {
            Log.w(TAG, "Frame update error: ${e.message}")
        }
    }

    // ── OpenGL ────────────────────────────────────────────────────────────────

    private fun createCameraTexture() {
        val textures = IntArray(1)
        GLES20.glGenTextures(1, textures, 0)
        cameraTextureId = textures[0]

        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, cameraTextureId)
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_WRAP_S,
            GLES20.GL_CLAMP_TO_EDGE
        )
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_WRAP_T,
            GLES20.GL_CLAMP_TO_EDGE
        )
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_MIN_FILTER,
            GLES20.GL_LINEAR
        )
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_MAG_FILTER,
            GLES20.GL_LINEAR
        )
    }

    private fun createShaderProgram() {
        val vertexShader = compileShader(GLES20.GL_VERTEX_SHADER, VERTEX_SHADER)
        val fragmentShader = compileShader(GLES20.GL_FRAGMENT_SHADER, FRAGMENT_SHADER)

        shaderProgram = GLES20.glCreateProgram().also { program ->
            GLES20.glAttachShader(program, vertexShader)
            GLES20.glAttachShader(program, fragmentShader)
            GLES20.glLinkProgram(program)
        }

        positionHandle = GLES20.glGetAttribLocation(shaderProgram, "a_Position")
        texCoordHandle = GLES20.glGetAttribLocation(shaderProgram, "a_TexCoord")
        textureUniformHandle = GLES20.glGetUniformLocation(shaderProgram, "u_Texture")
    }

    private fun compileShader(type: Int, source: String): Int {
        return GLES20.glCreateShader(type).also { shader ->
            GLES20.glShaderSource(shader, source)
            GLES20.glCompileShader(shader)
            val status = IntArray(1)
            GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, status, 0)
            if (status[0] == GLES20.GL_FALSE) {
                Log.e(TAG, "Shader compile error: ${GLES20.glGetShaderInfoLog(shader)}")
            }
        }
    }

    private fun drawCameraFrame() {
        if (shaderProgram == -1 || cameraTextureId == -1) return

        GLES20.glUseProgram(shaderProgram)

        // Позиции вершин
        val coordsBuffer = java.nio.ByteBuffer
            .allocateDirect(QUAD_COORDS.size * 4)
            .order(java.nio.ByteOrder.nativeOrder())
            .asFloatBuffer()
            .apply { put(QUAD_COORDS); position(0) }

        GLES20.glVertexAttribPointer(positionHandle, 2, GLES20.GL_FLOAT, false, 0, coordsBuffer)
        GLES20.glEnableVertexAttribArray(positionHandle)

        // UV-координаты
        val texBuffer = java.nio.ByteBuffer
            .allocateDirect(QUAD_TEXCOORDS.size * 4)
            .order(java.nio.ByteOrder.nativeOrder())
            .asFloatBuffer()
            .apply { put(QUAD_TEXCOORDS); position(0) }

        GLES20.glVertexAttribPointer(texCoordHandle, 2, GLES20.GL_FLOAT, false, 0, texBuffer)
        GLES20.glEnableVertexAttribArray(texCoordHandle)

        // Текстура камеры
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

            val existing = reportedPlanes[id]
            val changed = existing == null ||
                    existing["extentX"] != planeData["extentX"] ||
                    existing["extentZ"] != planeData["extentZ"]

            if (changed) {
                reportedPlanes[id] = planeData
                glSurfaceView.post { eventSink?.success(planeData) }
            }
        }

        // Удалённые плоскости
        frame.getUpdatedTrackables(Plane::class.java)
            .filter { it.trackingState == TrackingState.STOPPED }
            .map { it.hashCode().toString() }
            .forEach { removedId ->
                if (reportedPlanes.remove(removedId) != null) {
                    glSurfaceView.post {
                        eventSink?.success(mapOf("id" to removedId, "removed" to true))
                    }
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
