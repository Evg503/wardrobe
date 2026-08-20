package com.example.wardrobe

import android.app.Activity
import android.content.Context
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.opengl.GLSurfaceView
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
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10

/**
 * Нативный ARCore-вид, встраиваемый в Flutter через PlatformView.
 *
 * Рендерит видеопоток камеры через OES-текстуру + GLSL шейдер с
 * корректной ориентацией (frame.transformCoordinates2d).
 * Параллельно детектирует плоскости и отправляет данные во Flutter.
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

        // Позиции вершин full-screen quad (NDC)
        private val QUAD_COORDS = floatArrayOf(
            -1f, -1f,
             1f, -1f,
            -1f,  1f,
             1f,  1f,
        )

        // UV-координаты до трансформации ARCore (нормализованные, portrait)
        private val QUAD_TEXCOORDS_UNTRANSFORMED = floatArrayOf(
            0f, 0f,
            1f, 0f,
            0f, 1f,
            1f, 1f,
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

    // Трансформированные UV от ARCore (корректная ориентация)
    private var transformedTexCoords: FloatBuffer? = null
    private var viewportWidth = 0
    private var viewportHeight = 0

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
        viewportWidth = width
        viewportHeight = height
        // Передаём реальный rotation дисплея — ARCore использует его для
        // корректной ориентации кадра камеры в OES-текстуре
        arSession?.setDisplayGeometry(getDisplayRotation(), width, height)
    }

    override fun onDrawFrame(gl: GL10?) {
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)

        val session = arSession ?: return
        if (sessionPaused) return

        try {
            session.setCameraTextureName(cameraTextureId)
            val frame = session.update()

            // Получаем трансформированные UV от ARCore для текущей ориентации
            updateTransformedTexCoords(frame)

            drawCameraFrame()
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
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
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

    /**
     * Запрашивает у ARCore трансформированные UV-координаты для текущей
     * ориентации дисплея. ARCore сам вычисляет нужный поворот/отражение.
     */
    private fun updateTransformedTexCoords(frame: Frame) {
        val transformed = FloatArray(QUAD_TEXCOORDS_UNTRANSFORMED.size)
        frame.transformCoordinates2d(
            Coordinates2d.OPENGL_NORMALIZED_DEVICE_COORDINATES,
            QUAD_COORDS,
            Coordinates2d.TEXTURE_NORMALIZED,
            transformed,
        )
        transformedTexCoords = ByteBuffer
            .allocateDirect(transformed.size * 4)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
            .apply { put(transformed); position(0) }
    }

    private fun drawCameraFrame() {
        val texCoords = transformedTexCoords ?: return
        if (shaderProgram == -1 || cameraTextureId == -1) return

        GLES20.glUseProgram(shaderProgram)

        val coordsBuffer = ByteBuffer
            .allocateDirect(QUAD_COORDS.size * 4)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
            .apply { put(QUAD_COORDS); position(0) }

        GLES20.glVertexAttribPointer(positionHandle, 2, GLES20.GL_FLOAT, false, 0, coordsBuffer)
        GLES20.glEnableVertexAttribArray(positionHandle)

        texCoords.position(0)
        GLES20.glVertexAttribPointer(texCoordHandle, 2, GLES20.GL_FLOAT, false, 0, texCoords)
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
            // Сразу выставляем геометрию если viewport уже известен
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
        } catch (e: CameraNotAvailableException) {
            sendError("camera_unavailable", "Camera not available")
        }
    }

    private fun pauseSession() {
        arSession?.pause()
        sessionPaused = true
    }

    /**
     * Возвращает rotation дисплея в формате, который ожидает ARCore:
     * 0 = ROTATION_0, 1 = ROTATION_90, 2 = ROTATION_180, 3 = ROTATION_270.
     */
    private fun getDisplayRotation(): Int {
        val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        return when (wm.defaultDisplay.rotation) {
            Surface.ROTATION_90  -> 1
            Surface.ROTATION_180 -> 2
            Surface.ROTATION_270 -> 3
            else                 -> 0  // ROTATION_0 / portrait
        }
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

            val planeData = mapOf(
                "id" to id,
                "type" to type,
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
                glSurfaceView.post { eventSink?.success(planeData) }
            }
        }

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
                "resume" -> { resumeSession(); reportedPlanes.clear(); result.success(null) }
                "pause"  -> { pauseSession(); result.success(null) }
                "reset"  -> { reportedPlanes.clear(); result.success(null) }
                else     -> result.notImplemented()
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
