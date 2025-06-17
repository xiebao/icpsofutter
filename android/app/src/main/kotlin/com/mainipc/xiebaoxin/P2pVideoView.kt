package com.mainipc.xiebaoxin

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
    private var textureView: TextureView
    private var statusTextView: TextView
    private var mediaCodec: MediaCodec? = null
    private var surface: Surface? = null
    private var surfaceTexture: SurfaceTexture? = null
    private var frameQueue = LinkedBlockingQueue<ByteBuffer>(30)
    private var isProcessingFrames = AtomicBoolean(false)
    private var frameHandler: Handler
    private var lastFrameTime: Long = 0
    private var frameCheckHandler: Handler
    private lateinit var frameCheckRunnable: Runnable
    private var isFrameCheckRunning = false
    private var isDisposed = AtomicBoolean(false)
    private var frameCount = AtomicInteger(0)
    private var errorCount = AtomicInteger(0)
    private var videoWidth = 1280  // 默认宽度
    private var videoHeight = 720  // 默认高度
    private var isCodecInitialized = false

    companion object {
        private var instance: P2pVideoView? = null
    }

    init {
        Log.d(TAG, "[自检] P2pVideoView init")
        instance = this
        frameLayout = FrameLayout(context)
        textureView = TextureView(context).apply {
            surfaceTextureListener = this@P2pVideoView
            keepScreenOn = true
        }
        statusTextView = TextView(context).apply {
            text = "等待视频流..."
            setTextColor(android.graphics.Color.WHITE)
            textSize = 16f
        }

        frameLayout.addView(textureView, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ))
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
                if (isFrameCheckRunning) {
                    val currentTime = System.currentTimeMillis()
                    val timeSinceLastFrame = currentTime - lastFrameTime
                    if (timeSinceLastFrame > 3000) {
                        statusTextView.text = "未收到视频帧 ${timeSinceLastFrame/1000}秒"
                    }
                    frameCheckHandler.postDelayed(this, 1000)
                }
            }
        }

        creationParams?.let {
            // Use the existing initialization logic
        }

        messenger.setMethodCallHandler(this)
        bindNative()
    }

    private fun initMediaCodec(width: Int, height: Int) {
        try {
            Log.d(TAG, "Initializing MediaCodec with width=$width, height=$height")
            val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
                setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, width * height)
                setInteger(MediaFormat.KEY_FRAME_RATE, 30)
            }
            
            mediaCodec = MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
            surfaceTexture = textureView.surfaceTexture
            surface = Surface(surfaceTexture)
            mediaCodec?.configure(format, surface, null, 0)
            mediaCodec?.start()
            
            startFrameProcessing()
            Log.d(TAG, "MediaCodec initialized successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Error initializing MediaCodec", e)
            errorCount.incrementAndGet()
            messenger.invokeMethod("onError", mapOf("message" to "Error initializing MediaCodec: ${e.message}"))
        }
    }

    private fun processFrame(frame: ByteBuffer) {
        if (isDisposed.get()) {
            Log.d(TAG, "processFrame: view is disposed")
            return
        }
        Log.d(TAG, "[流程] processFrame 被调用, frame.limit=${frame.limit()}")
        if (mediaCodec == null) {
            Log.e(TAG, "processFrame: MediaCodec is null")
            return
        }
        try {
            val inputBufferIndex = mediaCodec!!.dequeueInputBuffer(10000L)
            if (inputBufferIndex >= 0) {
                val inputBuffer = mediaCodec!!.getInputBuffer(inputBufferIndex)
                inputBuffer?.clear()
                frame.rewind()
                inputBuffer?.put(frame)
                Log.d(TAG, "[流程] 输入帧送入MediaCodec, inputBufferIndex=$inputBufferIndex, size=${frame.limit()}")
                mediaCodec!!.queueInputBuffer(
                    inputBufferIndex,
                    0,
                    frame.limit(),
                    System.nanoTime() / 1000,
                    0
                )
            } else {
                Log.d(TAG, "[流程] 没有可用inputBuffer, inputBufferIndex=$inputBufferIndex")
            }
            val bufferInfo = MediaCodec.BufferInfo()
            var outputBufferIndex = mediaCodec!!.dequeueOutputBuffer(bufferInfo, 0)
            var outputCount = 0
            while (outputBufferIndex >= 0) {
                Log.d(TAG, "[流程] 解码输出帧, outputBufferIndex=$outputBufferIndex, size=${bufferInfo.size}")
                mediaCodec!!.releaseOutputBuffer(outputBufferIndex, true)
                outputBufferIndex = mediaCodec!!.dequeueOutputBuffer(bufferInfo, 0)
                outputCount++
            }
            if (outputCount == 0) {
                Log.d(TAG, "[流程] 本帧无解码输出")
            }
            if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0) {
                Log.d(TAG, "Codec config changed")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error processing frame", e)
            onError("Error processing frame: ${e.message}")
        }
    }

    fun onVideoFrame(data: ByteArray) {
        if (isDisposed.get()) {
            Log.d(TAG, "onVideoFrame: view is disposed")
            return
        }
        Log.d(TAG, "[流程] onVideoFrame 被调用, data.length=${data.size}")
        try {
            val length = data.size
            val buffer = ByteBuffer.allocate(length)
            buffer.put(data, 0, length)
            buffer.flip()
            if (!frameQueue.offer(buffer)) {
                Log.w(TAG, "[流程] Frame queue is full, dropping frame")
            } else {
                Log.d(TAG, "[流程] Frame 入队成功, queue.size=${frameQueue.size}")
            }
            lastFrameTime = System.currentTimeMillis()
            frameCount.incrementAndGet()
            if (frameCount.get() == 1) {
                Handler(Looper.getMainLooper()).post {
                    statusTextView.text = "正在接收视频流..."
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in onVideoFrame", e)
            onError("Error processing video frame: ${e.message}")
        }
    }

    fun onError(message: String) {
        Handler(Looper.getMainLooper()).post {
            try {
                messenger.invokeMethod("onError", mapOf("message" to message))
            } catch (e: Exception) {
                Log.e(TAG, "onError invokeMethod exception", e)
            }
        }
    }

    fun onTextureFrame(textureId: Long, width: Int, height: Int) {
        Log.d(TAG, "onTextureFrame: textureId=$textureId, width=$width, height=$height")
        // 这里可以处理纹理帧
        // 由于我们使用 MediaCodec 进行解码，这个方法暂时可以为空
    }

    private fun startFrameProcessing() {
        if (isProcessingFrames.get()) return
        Log.d(TAG, "[流程] 启动帧处理线程 startFrameProcessing")
        isProcessingFrames.set(true)
        Thread {
            while (!isDisposed.get() && isProcessingFrames.get()) {
                try {
                    val frame = frameQueue.poll(100, TimeUnit.MILLISECONDS)
                    if (frame != null) {
                        Log.d(TAG, "[流程] 取出一帧, queue.size=${frameQueue.size}")
                        processFrame(frame)
                        lastFrameTime = System.currentTimeMillis()
                        val currentFrameCount = frameCount.get()
                        if (currentFrameCount % 30 == 0) {
                            frameHandler.post {
                                statusTextView.text = "已接收 $currentFrameCount 帧"
                            }
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error in frame processing loop", e)
                    onError("Error in frame processing: ${e.message}")
                }
            }
        }.start()
        isFrameCheckRunning = true
        frameCheckHandler.post(frameCheckRunnable)
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
        if (isDisposed.getAndSet(true)) {
            return
        }

        try {
            // 停止视频
            stopP2pVideo()
            
            // 清理其他资源
            frameCheckHandler.removeCallbacks(frameCheckRunnable)
            isFrameCheckRunning = false
            
            mediaCodec?.stop()
            mediaCodec?.release()
            mediaCodec = null
            
            surface?.release()
            surface = null
            
            surfaceTexture?.release()
            surfaceTexture = null
            
            frameQueue.clear()
            
            instance = null
            
            Log.d(TAG, "P2pVideoView disposed successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Error disposing P2pVideoView", e)
        }
    }

    override fun getView(): View = frameLayout

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (isDisposed.get()) {
            result.error("DISPOSED", "P2pVideoView is disposed", null)
            return
        }
        when (call.method) {
            "startP2pVideo" -> {
                Log.d(TAG, "[自检] onMethodCall: startP2pVideo")
                startP2pVideo()
                result.success(null)
            }
            "stopP2pVideo" -> {
                Log.d(TAG, "[自检] onMethodCall: stopP2pVideo")
                stopP2pVideo()
                result.success(null)
            }
            "setVideoSize" -> {
                videoWidth = call.argument<Int>("width") ?: 1280
                videoHeight = call.argument<Int>("height") ?: 720
                Log.d(TAG, "setVideoSize: width=$videoWidth, height=$videoHeight")
                if (isCodecInitialized) {
                    releaseMediaCodec()
                }
                initMediaCodecIfNeeded()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onSurfaceTextureAvailable(surfaceTexture: SurfaceTexture, width: Int, height: Int) {
        Log.d(TAG, "[自检] onSurfaceTextureAvailable: width=$width, height=$height")
        this.surfaceTexture = surfaceTexture
        initMediaCodecIfNeeded()
    }

    override fun onSurfaceTextureSizeChanged(surfaceTexture: SurfaceTexture, width: Int, height: Int) {
        Log.d(TAG, "onSurfaceTextureSizeChanged: width=$width, height=$height")
        // 可以在这里处理纹理大小变化
    }

    override fun onSurfaceTextureDestroyed(surfaceTexture: SurfaceTexture): Boolean {
        Log.d(TAG, "onSurfaceTextureDestroyed")
        releaseMediaCodec()
        return true
    }

    override fun onSurfaceTextureUpdated(surfaceTexture: SurfaceTexture) {
        // 纹理更新时的回调，这里不需要特别处理
    }

    private fun initMediaCodecIfNeeded() {
        Log.d(TAG, "[流程] initMediaCodecIfNeeded, isCodecInitialized=$isCodecInitialized, surfaceTexture=${surfaceTexture != null}")
        if (isCodecInitialized || surfaceTexture == null) {
            return
        }
        try {
            Log.d(TAG, "Initializing MediaCodec with width=$videoWidth, height=$videoHeight")
            val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, videoWidth, videoHeight).apply {
                setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, videoWidth * videoHeight)
                setInteger(MediaFormat.KEY_FRAME_RATE, 30)
                setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            }
            mediaCodec = MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
            surface = Surface(surfaceTexture)
            mediaCodec?.configure(format, surface, null, 0)
            mediaCodec?.start()
            Log.d(TAG, "[流程] MediaCodec 初始化完成")
            startFrameProcessing()
            isCodecInitialized = true
        } catch (e: Exception) {
            Log.e(TAG, "Error initializing MediaCodec", e)
            onError("Error initializing MediaCodec: ${e.message}")
        }
    }

    private fun releaseMediaCodec() {
        try {
            isProcessingFrames.set(false)
            mediaCodec?.stop()
            mediaCodec?.release()
            mediaCodec = null
            surface?.release()
            surface = null
            isCodecInitialized = false
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing MediaCodec", e)
        }
    }

    private external fun bindNative()
    private external fun stopP2pVideo()
    private external fun startP2pVideo()
} 