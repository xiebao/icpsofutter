package com.example.music_app_framework

import android.content.Context
import android.graphics.SurfaceTexture
import android.util.Log
import android.view.Surface
import android.view.SurfaceView
import android.view.TextureView
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import androidx.annotation.NonNull
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import android.os.Handler
import android.os.Looper
import java.util.concurrent.atomic.AtomicBoolean
import android.media.MediaCodec
import android.media.MediaFormat
import android.view.SurfaceHolder
import com.google.android.exoplayer2.ExoPlayer
import com.google.android.exoplayer2.MediaItem
import com.google.android.exoplayer2.PlaybackException
import com.google.android.exoplayer2.Player
import com.google.android.exoplayer2.ui.StyledPlayerView
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import android.graphics.Matrix
import android.view.TextureView.SurfaceTextureListener
import java.util.concurrent.atomic.AtomicInteger
import android.media.MediaCodecInfo
import io.flutter.plugin.common.BinaryMessenger
import android.graphics.ImageFormat
import android.media.Image
import android.renderscript.*
import java.nio.ByteOrder
import android.graphics.Bitmap
import android.opengl.GLES20

class P2pVideoViewFactory(private val messenger: BinaryMessenger) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, id: Int, args: Any?): PlatformView {
        val creationParams = args as? Map<String?, Any?>
        return P2pVideoView(context, MethodChannel(messenger, "p2p_video_view_$id"), id, creationParams)
    }
}

class P2pVideoView(
    private val context: Context,
    private val messenger: MethodChannel,
    private val id: Int,
    creationParams: Map<String?, Any?>?
) : PlatformView, MethodChannel.MethodCallHandler, SurfaceTextureListener {
    private val TAG = "P2pVideoView"
    private var frameLayout: FrameLayout
    private var surfaceView: SurfaceView
    private var textureView: TextureView
    private var statusTextView: TextView
    private var exoPlayer: ExoPlayer? = null
    private var mediaCodec: MediaCodec? = null
    private var surface: Surface? = null
    private var surfaceTexture: SurfaceTexture? = null
    private var frameQueue = LinkedBlockingQueue<ByteBuffer>(30)
    private var isProcessingFrames = AtomicBoolean(false)
    private var useExoPlayer = false
    private var displayMode = 0 // 0: AndroidView, 1: Texture
    private var textureId: Long = 0
    private var frameHandler: Handler
    private var lastFrameTime: Long = 0
    private var frameCheckHandler: Handler
    private var frameCheckRunnable: Runnable
    private var isFrameCheckRunning = false
    private var isDisposed = AtomicBoolean(false)
    private var frameCount = AtomicInteger(0)
    private var errorCount = AtomicInteger(0)
    private var textureWidth: Int = 0
    private var textureHeight: Int = 0
    private var matrix: Matrix = Matrix()

    companion object {
        private var instance: P2pVideoView? = null
        
        @JvmStatic
        fun onTextureFrame(width: Int, height: Int, yuvData: ByteArray) {
            instance?.let { view ->
                if (!view.isDisposed.get()) {
                    view.messenger.invokeMethod("onTextureFrame", mapOf(
                        "width" to width,
                        "height" to height,
                        "yuvData" to yuvData
                    ))
                }
            }
        }
    }

    init {
        instance = this
        frameLayout = FrameLayout(context)
        surfaceView = SurfaceView(context)
        textureView = TextureView(context)
        statusTextView = TextView(context).apply {
            text = "等待视频流..."
            setTextColor(android.graphics.Color.WHITE)
            textSize = 16f
        }

        frameLayout.addView(surfaceView)
        frameLayout.addView(textureView)
        frameLayout.addView(statusTextView, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            gravity = android.view.Gravity.CENTER
        })

        frameHandler = Handler(Looper.getMainLooper())
        frameCheckHandler = Handler(Looper.getMainLooper())
        frameCheckRunnable = object : Runnable {
            override fun run() {
                checkFrameStatus()
                if (isFrameCheckRunning && !isDisposed.get()) {
                    frameCheckHandler.postDelayed(this, 3000)
                }
            }
        }

        textureView.surfaceTextureListener = this

        creationParams?.let {
            useExoPlayer = (it["decodeMode"] as? Int) == 1
            displayMode = (it["displayMode"] as? Int) ?: 0
            textureId = (it["textureId"] as? Long) ?: 0
        }

        updateDisplayMode()
        messenger.setMethodCallHandler(this)
    }

    private fun updateDisplayMode() {
        surfaceView.visibility = if (displayMode == 0) View.VISIBLE else View.GONE
        textureView.visibility = if (displayMode == 1) View.VISIBLE else View.GONE
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (isDisposed.get()) {
            result.error("DISPOSED", "View is disposed", null)
            return
        }

        when (call.method) {
            "setDecodeMode" -> {
                val mode = call.argument<Int>("mode")
                if (mode != null) {
                    useExoPlayer = mode == 1
                    result.success(null)
                } else {
                    result.error("INVALID_ARGUMENT", "Mode parameter is required", null)
                }
            }
            "setDisplayMode" -> {
                val mode = call.argument<Int>("mode")
                if (mode != null) {
                    displayMode = mode
                    updateDisplayMode()
                    result.success(null)
                } else {
                    result.error("INVALID_ARGUMENT", "Mode parameter is required", null)
                }
            }
            "createTexture" -> {
                if (textureView.isAvailable) {
                    textureId = System.nanoTime()
                    result.success(textureId)
                } else {
                    result.error("TEXTURE_NOT_AVAILABLE", "Texture view is not available", null)
                }
            }
            "disposeTexture" -> {
                textureId = 0
                result.success(null)
            }
            "updateTexture" -> {
                if (textureId != 0L && surfaceTexture != null) {
                    val width = call.argument<Int>("width") ?: 0
                    val height = call.argument<Int>("height") ?: 0
                    if (width > 0 && height > 0) {
                        surfaceTexture?.setDefaultBufferSize(width, height)
                        textureWidth = width
                        textureHeight = height
                        updateTextureMatrix()
                    }
                    result.success(null)
                } else {
                    result.error("TEXTURE_NOT_AVAILABLE", "Texture is not available", null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun updateTextureMatrix() {
        if (textureWidth == 0 || textureHeight == 0) return
        
        val viewWidth = textureView.width
        val viewHeight = textureView.height
        if (viewWidth == 0 || viewHeight == 0) return

        val scaleX = viewWidth.toFloat() / textureWidth
        val scaleY = viewHeight.toFloat() / textureHeight
        val scale = scaleX.coerceAtMost(scaleY)

        matrix.reset()
        matrix.postScale(scale, scale)
        matrix.postTranslate(
            (viewWidth - textureWidth * scale) / 2,
            (viewHeight - textureHeight * scale) / 2
        )
        textureView.setTransform(matrix)
    }

    override fun onSurfaceTextureAvailable(texture: SurfaceTexture, width: Int, height: Int) {
        Log.d(TAG, "onSurfaceTextureAvailable: width=$width, height=$height")
        surfaceTexture = texture
        if (displayMode == 1 && !isDisposed.get()) {
            initMediaCodec(width, height)
            startFrameProcessing()
            startFrameCheck()
        }
    }

    override fun onSurfaceTextureSizeChanged(texture: SurfaceTexture, width: Int, height: Int) {
        Log.d(TAG, "onSurfaceTextureSizeChanged: width=$width, height=$height")
        updateTextureMatrix()
    }

    override fun onSurfaceTextureDestroyed(texture: SurfaceTexture): Boolean {
        Log.d(TAG, "onSurfaceTextureDestroyed")
        surfaceTexture = null
        return true
    }

    override fun onSurfaceTextureUpdated(texture: SurfaceTexture) {
        // 不需要实现
    }

    private fun initMediaCodec(width: Int, height: Int) {
        try {
            Log.d(TAG, "Initializing MediaCodec with width=$width, height=$height")
            val mimeType = "video/avc"
            val format = MediaFormat.createVideoFormat(mimeType, width, height)
            format.setInteger(MediaFormat.KEY_BIT_RATE, 2000000)
            format.setInteger(MediaFormat.KEY_FRAME_RATE, 30)
            format.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            format.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            format.setInteger(MediaFormat.KEY_COMPLEXITY, MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR)
            
            Log.d(TAG, "Creating MediaCodec decoder")
            mediaCodec = MediaCodec.createDecoderByType(mimeType)
            Log.d(TAG, "Configuring MediaCodec")
            mediaCodec?.configure(format, surfaceTexture?.let { Surface(it) }, null, 0)
            Log.d(TAG, "Starting MediaCodec")
            mediaCodec?.start()
            
            // 启动帧处理线程
            startFrameProcessing()
            
            Log.d(TAG, "MediaCodec initialized successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Error initializing MediaCodec", e)
            messenger.invokeMethod("onError", mapOf("message" to "MediaCodec initialization failed: ${e.message}"))
        }
    }

    private fun processFrame(frame: ByteBuffer) {
        if (isDisposed.get()) return
        
        when (displayMode) {
            0 -> processFrameForSurfaceView(frame)
            1 -> processFrameForTexture(frame)
        }
    }

    private fun processFrameForTexture(frame: ByteBuffer) {
        if (surfaceTexture == null || textureId == 0L || mediaCodec == null) {
            Log.e(TAG, "Cannot process frame: surfaceTexture=${surfaceTexture != null}, textureId=$textureId, mediaCodec=${mediaCodec != null}")
            return
        }
        
        try {
            val inputBufferId = mediaCodec?.dequeueInputBuffer(10000) ?: -1
            if (inputBufferId >= 0) {
                val inputBuffer = mediaCodec?.getInputBuffer(inputBufferId)
                inputBuffer?.clear()
                inputBuffer?.put(frame)
                mediaCodec?.queueInputBuffer(inputBufferId, 0, frame.remaining(), System.nanoTime() / 1000, 0)
            }

            val bufferInfo = MediaCodec.BufferInfo()
            val outputBufferId = mediaCodec?.dequeueOutputBuffer(bufferInfo, 10000) ?: -1
            
            if (outputBufferId >= 0) {
                mediaCodec?.releaseOutputBuffer(outputBufferId, true)
            } else if (outputBufferId == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                val newFormat = mediaCodec?.outputFormat
                Log.d(TAG, "Output format changed: $newFormat")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error processing frame for texture", e)
            messenger.invokeMethod("onError", mapOf("message" to "Error processing frame: ${e.message}"))
        }
    }

    private fun processFrameForSurfaceView(frame: ByteBuffer) {
        // 原有的SurfaceView处理逻辑
        // ... existing code ...
    }

    override fun getView(): View {
        return frameLayout
    }

    private fun startFrameProcessing() {
        if (isProcessingFrames.get()) return
        
        isProcessingFrames.set(true)
        Thread {
            while (!isDisposed.get() && isProcessingFrames.get()) {
                try {
                    val frame = frameQueue.poll(100, TimeUnit.MILLISECONDS)
                    if (frame != null) {
                        processFrame(frame)
                        frameCount.incrementAndGet()
                        lastFrameTime = System.currentTimeMillis()
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error processing frame", e)
                    errorCount.incrementAndGet()
                }
            }
        }.start()
    }

    fun onVideoFrame(data: ByteArray) {
        if (isDisposed.get()) {
            Log.d(TAG, "onVideoFrame: view is disposed")
            return
        }

        try {
            Log.d(TAG, "onVideoFrame: received ${data.size} bytes")
            val buffer = ByteBuffer.allocate(data.size)
            buffer.put(data)
            buffer.flip()
            frameQueue.offer(buffer)
            Log.d(TAG, "onVideoFrame: frame queued, queue size=${frameQueue.size}")
        } catch (e: Exception) {
            Log.e(TAG, "Error in onVideoFrame", e)
            messenger.invokeMethod("onError", mapOf("message" to "Error in onVideoFrame: ${e.message}"))
        }
    }

    private fun startFrameCheck() {
        if (!isFrameCheckRunning && !isDisposed.get()) {
            isFrameCheckRunning = true
            frameCheckHandler.post(frameCheckRunnable)
        }
    }

    private fun stopFrameCheck() {
        isFrameCheckRunning = false
        frameCheckHandler.removeCallbacks(frameCheckRunnable)
    }

    override fun dispose() {
        instance = null
        isDisposed.set(true)
        stopFrameCheck()
        isProcessingFrames.set(false)
        frameQueue.clear()
        frameCheckHandler.removeCallbacks(frameCheckRunnable)
        frameHandler.removeCallbacksAndMessages(null)
        
        try {
            mediaCodec?.stop()
            mediaCodec?.release()
            mediaCodec = null
        } catch (e: Exception) {
            Log.e(TAG, "Error disposing MediaCodec", e)
        }
        
        surface?.release()
        surface = null
        surfaceTexture?.release()
        surfaceTexture = null
        
        exoPlayer?.release()
        exoPlayer = null
    }

    private fun checkFrameStatus() {
        if (isDisposed.get()) return
        
        val currentTime = System.currentTimeMillis()
        val currentFrameCount = frameCount.get()
        val currentErrorCount = errorCount.get()
        
        if (currentTime - lastFrameTime > 5000) {
            Log.w(TAG, "No frames received for 5 seconds")
            errorCount.incrementAndGet()
        }
        
        if (currentErrorCount > 3) {
            Log.e(TAG, "Too many errors, stopping video")
            messenger.invokeMethod("onError", mapOf("message" to "Too many errors, stopping video"))
        }
    }

    private fun updateTextureInternal(data: ByteArray, width: Int, height: Int) {
        Log.d(TAG, "updateTextureInternal: width=$width, height=$height, data size=${data.size}")
        
        if (data.isEmpty()) {
            Log.e(TAG, "updateTextureInternal: Empty data received")
            return
        }

        if (width <= 0 || height <= 0) {
            Log.e(TAG, "updateTextureInternal: Invalid dimensions - width=$width, height=$height")
            return
        }

        if (textureId == 0L) {
            Log.e(TAG, "updateTextureInternal: Texture not initialized")
            return
        }

        try {
            // 更新纹理数据
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, textureId.toInt())
            GLES20.glTexImage2D(
                GLES20.GL_TEXTURE_2D, 0, GLES20.GL_RGBA,
                width, height, 0, GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE,
                ByteBuffer.wrap(data)
            )
            
            // 检查OpenGL错误
            val error = GLES20.glGetError()
            if (error != GLES20.GL_NO_ERROR) {
                Log.e(TAG, "updateTextureInternal: OpenGL error: $error")
            } else {
                Log.d(TAG, "updateTextureInternal: Texture updated successfully")
            }
            
            // 请求重绘
            textureView.postInvalidate()
        } catch (e: Exception) {
            Log.e(TAG, "updateTextureInternal: Error updating texture", e)
        }
    }

    fun callStartP2pVideoWithLog() {
        Log.d(TAG, "P2pVideoView: 调用前 external fun startP2pVideo()")
        startP2pVideo()
        Log.d(TAG, "P2pVideoView: 调用后 external fun startP2pVideo()")
    }

    external fun startP2pVideo()
} 