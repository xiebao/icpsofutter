package com.mainipc.xiebaoxin

import android.media.MediaCodec
import android.media.MediaFormat
import android.view.Surface
import java.nio.ByteBuffer
import android.util.Log

class H264Decoder {
    private var decoder: MediaCodec? = null
    private var isConfigured = false

    fun init(surface: Surface, width: Int, height: Int) {
        Log.d("H264Decoder", "init: surface=$surface, width=$width, height=$height")
        decoder = MediaCodec.createDecoderByType("video/avc")
        val format = MediaFormat.createVideoFormat("video/avc", width, height)
        decoder?.configure(format, surface, null, 0)
        decoder?.start()
        isConfigured = true
        Log.d("H264Decoder", "init: decoder started, isConfigured=$isConfigured")
    }

    fun queueInput(data: ByteArray, offset: Int, size: Int, pts: Long) {
        if (!isConfigured) {
            Log.w("H264Decoder", "queueInput: decoder not configured!")
            return
        }
        val inputBufferIndex = decoder?.dequeueInputBuffer(10_000) ?: -1
        if (inputBufferIndex >= 0) {
            val inputBuffer: ByteBuffer? = decoder?.getInputBuffer(inputBufferIndex)
            inputBuffer?.clear()
            inputBuffer?.put(data, offset, size)
            decoder?.queueInputBuffer(inputBufferIndex, 0, size, pts, 0)
            Log.d("H264Decoder", "queueInput: queued size=$size, pts=$pts, inputBufferIndex=$inputBufferIndex")
        } else {
            Log.w("H264Decoder", "queueInput: no available input buffer!")
        }
        // 输出buffer自动渲染到Surface
        val bufferInfo = MediaCodec.BufferInfo()
        var outputBufferIndex = decoder?.dequeueOutputBuffer(bufferInfo, 0) ?: -1
        while (outputBufferIndex >= 0) {
            decoder?.releaseOutputBuffer(outputBufferIndex, true)
            Log.d("H264Decoder", "releaseOutputBuffer: outputBufferIndex=$outputBufferIndex, size=${bufferInfo.size}, pts=${bufferInfo.presentationTimeUs}")
            outputBufferIndex = decoder?.dequeueOutputBuffer(bufferInfo, 0) ?: -1
        }
    }

    fun release() {
        Log.d("H264Decoder", "release: stopping and releasing decoder")
        decoder?.stop()
        decoder?.release()
        decoder = null
        isConfigured = false
    }
} 