package com.example.music_app_framework

import android.content.Context
import android.media.MediaCodec
import android.media.MediaFormat
import android.os.Handler
import android.os.Looper
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import io.flutter.plugin.platform.PlatformView
import java.nio.ByteBuffer
import android.util.Log
import com.google.android.exoplayer2.SimpleExoPlayer
import com.google.android.exoplayer2.Player
import com.google.android.exoplayer2.ui.PlayerView
import com.google.android.exoplayer2.source.SampleStream
import com.google.android.exoplayer2.Format
import com.google.android.exoplayer2.C
import com.google.android.exoplayer2.util.MimeTypes

class P2pVideoView(context: Context) : PlatformView {
    private val context: Context = context
    private val surfaceView = SurfaceView(context).apply {
        setBackgroundColor(0xFFFF0000.toInt()) // 红色背景
    }
    private var mediaCodec: MediaCodec? = null
    private val width = 640 // 可根据实际流宽高调整
    private val height = 480
    private var surfaceReady = false
    private var exoPlayer: SimpleExoPlayer? = null
    private var playerView: PlayerView? = null
    private var useExoPlayer = true // 兜底方案，优先软解码

    external fun bindNative()

    init {
        if (useExoPlayer) {
            playerView = PlayerView(this.context)
            exoPlayer = SimpleExoPlayer.Builder(this.context).build()
            playerView?.player = exoPlayer
            // 播放 /sdcard/live.h264 文件
            val mediaItem = com.google.android.exoplayer2.MediaItem.fromUri("file:///data/data/com.example.music_app_framework/files/live.h264")
            exoPlayer?.setMediaItem(mediaItem)
            exoPlayer?.prepare()
            exoPlayer?.playWhenReady = true
        }
        surfaceView.holder.addCallback(object : SurfaceHolder.Callback {
            override fun surfaceCreated(holder: SurfaceHolder) {
                surfaceReady = true
                Log.d("P2pVideoView", "surfaceCreated, surfaceReady=$surfaceReady")
                val format = MediaFormat.createVideoFormat("video/avc", width, height)
                mediaCodec = MediaCodec.createDecoderByType("video/avc")
                mediaCodec?.configure(format, holder.surface, null, 0)
                mediaCodec?.start()
                // 绑定 native 回调
                try {
                    bindNative()
                } catch (_: Exception) {}
            }
            override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {}
            override fun surfaceDestroyed(holder: SurfaceHolder) {
                surfaceReady = false
                Log.d("P2pVideoView", "surfaceDestroyed, surfaceReady=$surfaceReady")
                mediaCodec?.stop()
                mediaCodec?.release()
                mediaCodec = null
            }
        })
    }

    // JNI 回调
    fun onVideoFrame(data: ByteArray) {
        Log.d("P2pVideoView", "onVideoFrame called, data.length=${data.size}, surfaceReady=$surfaceReady")
        if (useExoPlayer) {
            // ExoPlayer 自动播放 live.h264，无需手动送帧
            return
        }
        if (!surfaceReady) return
        Handler(Looper.getMainLooper()).post {
            mediaCodec?.let { codec ->
                try {
                    val inIndex = codec.dequeueInputBuffer(10000)
                    if (inIndex >= 0) {
                        val buffer: ByteBuffer? = codec.getInputBuffer(inIndex)
                        buffer?.clear()
                        buffer?.put(data)
                        codec.queueInputBuffer(inIndex, 0, data.size, System.currentTimeMillis(), 0)
                        Log.d("P2pVideoView", "queueInputBuffer success, size=${data.size}")
                    } else {
                        Log.w("P2pVideoView", "dequeueInputBuffer failed: $inIndex")
                    }
                } catch (e: Exception) {
                    Log.e("P2pVideoView", "MediaCodec error: ${e.message}", e)
                }
            } ?: Log.w("P2pVideoView", "mediaCodec is null")
        }
    }

    fun setDecodeMode(mode: Int) {
        // 0: 硬解，1: 软解
        if ((mode == 1 && useExoPlayer) || (mode == 0 && !useExoPlayer)) return
        useExoPlayer = (mode == 1)
        // 释放旧资源
        mediaCodec?.stop(); mediaCodec?.release(); mediaCodec = null
        exoPlayer?.release(); exoPlayer = null; playerView = null
        if (useExoPlayer) {
            playerView = PlayerView(this.context)
            exoPlayer = SimpleExoPlayer.Builder(this.context).build()
            playerView?.player = exoPlayer
            val mediaItem = com.google.android.exoplayer2.MediaItem.fromUri("file:///data/data/com.example.music_app_framework/files/live.h264")
            exoPlayer?.setMediaItem(mediaItem)
            exoPlayer?.prepare()
            exoPlayer?.playWhenReady = true
        }
    }

    override fun getView(): View = if (useExoPlayer) playerView!! else surfaceView
    override fun dispose() {
        mediaCodec?.stop()
        mediaCodec?.release()
        mediaCodec = null
    }
} 