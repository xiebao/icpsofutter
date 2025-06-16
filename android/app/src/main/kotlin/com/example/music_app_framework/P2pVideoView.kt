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

    init {
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
            
            Log.d(TAG, "Creating MediaCodec decoder")
            mediaCodec = MediaCodec.createDecoderByType(mimeType)
            Log.d(TAG, "Configuring MediaCodec")
            mediaCodec?.configure(format, surfaceTexture?.let { Surface(it) }, null, 0)
            Log.d(TAG, "Starting MediaCodec")
            mediaCodec?.start()
            
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
            Log.d(TAG, "Processing frame for texture, size=${frame.remaining()}")
            val inputBufferId = mediaCodec?.dequeueInputBuffer(10000) ?: -1
            if (inputBufferId >= 0) {
                Log.d(TAG, "Got input buffer $inputBufferId")
                val inputBuffer = mediaCodec?.getInputBuffer(inputBufferId)
                inputBuffer?.clear()
                inputBuffer?.put(frame)
                mediaCodec?.queueInputBuffer(inputBufferId, 0, frame.remaining(), System.nanoTime() / 1000, 0)
                Log.d(TAG, "Queued input buffer $inputBufferId")
            } else {
                Log.w(TAG, "No input buffer available")
            }

            val bufferInfo = MediaCodec.BufferInfo()
            val outputBufferId = mediaCodec?.dequeueOutputBuffer(bufferInfo, 10000) ?: -1
            
            when (outputBufferId) {
                MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    Log.d(TAG, "Output format changed: ${mediaCodec?.outputFormat}")
                }
                MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    Log.d(TAG, "No output buffer available")
                }
                else -> {
                    if (outputBufferId >= 0) {
                        Log.d(TAG, "Got output buffer $outputBufferId")
                        surfaceTexture?.updateTexImage()
                        Log.d(TAG, "Updated texture image")
                        
                        messenger.invokeMethod("onTextureFrame", mapOf(
                            "textureId" to textureId,
                            "width" to textureWidth,
                            "height" to textureHeight
                        ))
                        Log.d(TAG, "Notified Flutter about texture update")
                        
                        mediaCodec?.releaseOutputBuffer(outputBufferId, true)
                        Log.d(TAG, "Released output buffer $outputBufferId")
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error processing frame for texture", e)
            messenger.invokeMethod("onError", mapOf("message" to "Frame processing error: ${e.message}"))
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
        if (isProcessingFrames.get()) {
            Log.d(TAG, "Frame processing already started")
            return
        }

        isProcessingFrames.set(true)
        Thread {
            Log.d(TAG, "Frame processing thread started")
            var consecutiveErrors = 0
            val maxConsecutiveErrors = 5
            
            while (!isDisposed.get() && isProcessingFrames.get()) {
                try {
                    val frame = frameQueue.poll(100, TimeUnit.MILLISECONDS)
                    if (frame != null) {
                        Log.d(TAG, "Processing frame from queue: size=${frame.remaining()}")
                        processFrame(frame)
                        frameCount.incrementAndGet()
                        lastFrameTime = System.currentTimeMillis()
                        consecutiveErrors = 0 // 成功处理帧，重置错误计数
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error in frame processing thread", e)
                    errorCount.incrementAndGet()
                    consecutiveErrors++
                    
                    if (consecutiveErrors >= maxConsecutiveErrors) {
                        Log.e(TAG, "Too many consecutive errors ($consecutiveErrors), attempting to recover...")
                        messenger.invokeMethod("onError", mapOf("message" to "Too many consecutive errors, attempting to recover"))
                        
                        // 尝试恢复
                        try {
                            mediaCodec?.stop()
                            mediaCodec?.release()
                            mediaCodec = null
                            Thread.sleep(1000) // 等待1秒
                            if (surfaceTexture != null) {
                                if (textureWidth > 0 && textureHeight > 0) {
                                    initMediaCodec(textureWidth, textureHeight)
                                } else {
                                    initMediaCodec(640, 480)
                                }
                            } else {
                                initMediaCodec(640, 480)
                            }
                            consecutiveErrors = 0
                        } catch (recoveryError: Exception) {
                            Log.e(TAG, "Recovery failed", recoveryError)
                            messenger.invokeMethod("onError", mapOf("message" to "Recovery failed: ${recoveryError.message}"))
                            break // 恢复失败，退出处理线程
                        }
                    }
                }
            }
            Log.d(TAG, "Frame processing thread stopped")
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
} 