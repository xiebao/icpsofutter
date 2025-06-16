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
                    }
                    result.success(null)
                } else {
                    result.error("TEXTURE_NOT_AVAILABLE", "Texture is not available", null)
                }
            }
            "updateDecodeMode" -> {
                val mode = call.argument<Int>("mode")
                if (mode != null) {
                    updateDecodeMode(mode)
                    result.success(null)
                } else {
                    result.error("INVALID_ARGUMENT", "Mode parameter is required", null)
                }
            }
            else -> result.notImplemented()
        }
    }

    override fun onSurfaceTextureAvailable(texture: SurfaceTexture, width: Int, height: Int) {
        Log.d(TAG, "onSurfaceTextureAvailable: width=$width, height=$height")
        surfaceTexture = texture
        textureWidth = width
        textureHeight = height
        if (displayMode == 1 && !isDisposed.get()) {
            initMediaCodec(width, height)
        }
    }

    override fun onSurfaceTextureSizeChanged(texture: SurfaceTexture, width: Int, height: Int) {
        Log.d(TAG, "onSurfaceTextureSizeChanged: width=$width, height=$height")
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
            val mimeType = "video/avc"
            val format = MediaFormat.createVideoFormat(mimeType, width, height)
            format.setInteger(MediaFormat.KEY_BIT_RATE, 2000000)
            format.setInteger(MediaFormat.KEY_FRAME_RATE, 30)
            format.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            format.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            
            // 动态设置 SPS/PPS
            val sps = byteArrayOf(
                0x00.toByte(), 0x00.toByte(), 0x00.toByte(), 0x01.toByte(),
                0x67.toByte(), 0x42.toByte(), 0x80.toByte(), 0x1f.toByte(),
                0xda.toByte(), 0x01.toByte(), 0x40.toByte(), 0x16.toByte(),
                0xec.toByte(), 0x04.toByte(), 0x40.toByte(), 0x00.toByte(),
                0x00.toByte(), 0x03.toByte(), 0x00.toByte(), 0x40.toByte(),
                0x00.toByte(), 0x00.toByte(), 0x0f.toByte(), 0x03.toByte(),
                0xc5.toByte(), 0x8b.toByte(), 0xb8.toByte()
            )
            val pps = byteArrayOf(
                0x00.toByte(), 0x00.toByte(), 0x00.toByte(), 0x01.toByte(),
                0x68.toByte(), 0xce.toByte(), 0x38.toByte(), 0x80.toByte()
            )
            
            // 检查视频数据中是否包含 SPS/PPS
            if (frameQueue.isNotEmpty()) {
                val firstFrame = frameQueue.peek()
                if (firstFrame != null) {
                    val data = ByteArray(firstFrame.remaining())
                    firstFrame.get(data)
                    firstFrame.rewind()
                    
                    // 查找 SPS/PPS
                    var i = 0
                    while (i < data.size - 4) {
                        if (data[i] == 0x00.toByte() && data[i + 1] == 0x00.toByte() && 
                            data[i + 2] == 0x00.toByte() && data[i + 3] == 0x01.toByte()) {
                            val naluType = data[i + 4].toInt() and 0x1F
                            if (naluType == 7) { // SPS
                                var j = i + 4
                                while (j < data.size - 4) {
                                    if (data[j] == 0x00.toByte() && data[j + 1] == 0x00.toByte() && 
                                        data[j + 2] == 0x00.toByte() && data[j + 3] == 0x01.toByte()) {
                                        val spsData = data.copyOfRange(i, j)
                                        format.setByteBuffer("csd-0", ByteBuffer.wrap(spsData))
                                        break
                                    }
                                    j++
                                }
                            } else if (naluType == 8) { // PPS
                                var j = i + 4
                                while (j < data.size - 4) {
                                    if (data[j] == 0x00.toByte() && data[j + 1] == 0x00.toByte() && 
                                        data[j + 2] == 0x00.toByte() && data[j + 3] == 0x01.toByte()) {
                                        val ppsData = data.copyOfRange(i, j)
                                        format.setByteBuffer("csd-1", ByteBuffer.wrap(ppsData))
                                        break
                                    }
                                    j++
                                }
                            }
                        }
                        i++
                    }
                }
            }
            
            // 如果没有找到 SPS/PPS，使用默认值
            if (!format.containsKey("csd-0")) {
                format.setByteBuffer("csd-0", ByteBuffer.wrap(sps))
                format.setByteBuffer("csd-1", ByteBuffer.wrap(pps))
            }

            mediaCodec = MediaCodec.createDecoderByType(mimeType)
            mediaCodec?.configure(format, surface, null, 0)
            mediaCodec?.start()
            
            Log.d(TAG, "MediaCodec initialized successfully with width: $width, height: $height")
        } catch (e: Exception) {
            Log.e(TAG, "Error initializing MediaCodec", e)
            releaseMediaCodec()
        }
    }

    private fun releaseMediaCodec() {
        try {
            mediaCodec?.stop()
            mediaCodec?.release()
            mediaCodec = null
            Log.d(TAG, "MediaCodec released")
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing MediaCodec", e)
        }
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

    private fun processFrame(data: ByteBuffer) {
        if (isDisposed.get() || mediaCodec == null) {
            Log.d(TAG, "processFrame: disposed or mediaCodec is null")
            return
        }

        try {
            Log.d(TAG, "processFrame: processing frame of size ${data.remaining()}")
            val inputBufferId = mediaCodec?.dequeueInputBuffer(10000)
            if (inputBufferId != null && inputBufferId >= 0) {
                val inputBuffer = mediaCodec?.getInputBuffer(inputBufferId)
                if (inputBuffer != null) {
                    inputBuffer.clear()
                    inputBuffer.put(data)
                    mediaCodec?.queueInputBuffer(inputBufferId, 0, data.remaining(), System.nanoTime() / 1000, 0)
                    Log.d(TAG, "Frame queued to MediaCodec: size=${data.remaining()}")
                } else {
                    Log.e(TAG, "Failed to get input buffer")
                    throw Exception("Failed to get input buffer")
                }
            } else {
                Log.e(TAG, "Failed to dequeue input buffer: $inputBufferId")
                throw Exception("Failed to dequeue input buffer: $inputBufferId")
            }

            val bufferInfo = MediaCodec.BufferInfo()
            val outputBufferId = mediaCodec?.dequeueOutputBuffer(bufferInfo, 10000)
            if (outputBufferId != null) {
                when (outputBufferId) {
                    MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        Log.d(TAG, "Output format changed: ${mediaCodec?.outputFormat}")
                    }
                    MediaCodec.INFO_TRY_AGAIN_LATER -> {
                        Log.d(TAG, "No output buffer available yet")
                    }
                    else -> {
                        if (outputBufferId >= 0) {
                            mediaCodec?.releaseOutputBuffer(outputBufferId, true)
                            Log.d(TAG, "Frame rendered: size=${bufferInfo.size}")
                        }
                    }
                }
            } else {
                Log.e(TAG, "Failed to dequeue output buffer")
                throw Exception("Failed to dequeue output buffer")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error processing frame", e)
            messenger.invokeMethod("onError", mapOf("message" to "Error processing frame: ${e.message}"))
            throw e // 重新抛出异常，让上层处理
        }
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
            val errorResetThreshold = 1000 // 1秒内无错误则重置错误计数
            
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
                            releaseMediaCodec()
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

    private fun checkFrameStatus() {
        val currentTime = System.currentTimeMillis()
        val timeSinceLastFrame = currentTime - lastFrameTime
        Log.d(TAG, "Frame status: count=${frameCount.get()}, errors=${errorCount.get()}, timeSinceLastFrame=$timeSinceLastFrame")
        
        if (timeSinceLastFrame > 5000) {
            Log.w(TAG, "No frames received for more than 5 seconds")
            messenger.invokeMethod("onError", mapOf("message" to "No frames received for more than 5 seconds"))
        }
    }

    private fun handleMediaCodecFrame(data: ByteArray) {
        if (mediaCodec == null) {
            Log.e(TAG, "MediaCodec not initialized")
            return
        }

        try {
            val inputBufferId = mediaCodec?.dequeueInputBuffer(10000) ?: -1
            if (inputBufferId >= 0) {
                val inputBuffer = mediaCodec?.getInputBuffer(inputBufferId)
                inputBuffer?.clear()
                inputBuffer?.put(data)
                mediaCodec?.queueInputBuffer(inputBufferId, 0, data.size, System.nanoTime() / 1000, 0)
                Log.d(TAG, "Queued input buffer: $inputBufferId, size: ${data.size}")
            } else {
                Log.w(TAG, "No input buffer available, inputBufferId: $inputBufferId")
            }

            val bufferInfo = MediaCodec.BufferInfo()
            val outputBufferId = mediaCodec?.dequeueOutputBuffer(bufferInfo, 10000) ?: -1
            if (outputBufferId >= 0) {
                Log.d(TAG, "Got output buffer: $outputBufferId, size: ${bufferInfo.size}, flags: ${bufferInfo.flags}")
                mediaCodec?.releaseOutputBuffer(outputBufferId, true)
                Log.d(TAG, "Released output buffer: $outputBufferId")
            } else {
                Log.w(TAG, "No output buffer available, outputBufferId: $outputBufferId")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in MediaCodec frame processing", e)
            throw e
        }
    }

    private fun handleExoPlayerFrame(data: ByteArray) {
        if (exoPlayer == null) {
            Log.d(TAG, "Initializing ExoPlayer")
            exoPlayer = ExoPlayer.Builder(context).build()
            exoPlayer?.setVideoSurfaceView(surfaceView)
            exoPlayer?.addListener(object : Player.Listener {
                override fun onPlayerError(error: PlaybackException) {
                    Log.e(TAG, "ExoPlayer error", error)
                    statusTextView.text = "播放器错误: ${error.message}"
                }
                
                override fun onPlaybackStateChanged(state: Int) {
                    Log.d(TAG, "ExoPlayer state changed: $state")
                }
            })
        }

        try {
            val tempFile = File(context.cacheDir, "temp_video_${System.currentTimeMillis()}.h264")
            FileOutputStream(tempFile).use { it.write(data) }
            Log.d(TAG, "Wrote video data to temp file: ${tempFile.absolutePath}, size: ${data.size}")
            
            val mediaItem = MediaItem.fromUri(android.net.Uri.fromFile(tempFile))
            exoPlayer?.setMediaItem(mediaItem)
            exoPlayer?.prepare()
            exoPlayer?.play()
            
            Log.d(TAG, "ExoPlayer playing video from temp file: ${tempFile.absolutePath}")
        } catch (e: Exception) {
            Log.e(TAG, "Error in ExoPlayer frame processing", e)
            throw e
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

    override fun getView(): View {
        return frameLayout
    }

    override fun dispose() {
        isDisposed.set(true)
        stopFrameCheck()
        exoPlayer?.release()
        mediaCodec?.stop()
        mediaCodec?.release()
        surface?.release()
        surfaceTexture?.release()
        frameQueue.clear()
        frameHandler.removeCallbacksAndMessages(null)
        frameCheckHandler.removeCallbacksAndMessages(null)
    }

    fun updateDecodeMode(mode: Int) {
        if (isDisposed.get()) {
            Log.w(TAG, "View is disposed, ignoring updateDecodeMode request")
            return
        }
        useExoPlayer = mode == 1
        Log.d(TAG, "Decode mode updated to: ${if (useExoPlayer) "ExoPlayer" else "MediaCodec"}")
    }
} 