package com.example.music_app_framework

import android.content.Context
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.view.Surface
import android.view.TextureView
import android.view.View
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.nio.ByteBuffer

class CameraPreviewView(
    context: Context,
    id: Int,
    creationParams: Map<String?, Any?>?
) : PlatformView {
    private val textureView: TextureView
    private var encoder: MediaCodec? = null
    private var decoder: MediaCodec? = null
    private var isEncoding = false
    private val decodeMode: Int = (creationParams?.get("decodeMode") as? Number)?.toInt() ?: 0
    private val displayMode: Int = (creationParams?.get("displayMode") as? Number)?.toInt() ?: 0
    private var inputSurface: Surface? = null
    private var outputSurface: Surface? = null
    private var surfaceTexture: android.graphics.SurfaceTexture? = null
    private var isDisposed = false

    init {
        textureView = TextureView(context)
        setupH264Encoder()
        textureView.surfaceTextureListener = object : TextureView.SurfaceTextureListener {
            override fun onSurfaceTextureAvailable(surface: android.graphics.SurfaceTexture, width: Int, height: Int) {
                surfaceTexture = surface
                if (decoder == null) {
                    setupH264Decoder(surface, width, height)
                }
            }
            override fun onSurfaceTextureSizeChanged(surface: android.graphics.SurfaceTexture, width: Int, height: Int) {
                surfaceTexture = surface
                if (decoder == null) {
                    setupH264Decoder(surface, width, height)
                }
            }
            override fun onSurfaceTextureDestroyed(surface: android.graphics.SurfaceTexture): Boolean {
                surfaceTexture = null
                return true
            }
            override fun onSurfaceTextureUpdated(surface: android.graphics.SurfaceTexture) {}
        }
    }

    private fun setupH264Encoder() {
        try {
            val mimeType = "video/avc"
            val width = 640
            val height = 480
            val frameRate = 30
            val iFrameInterval = 1

            val format = MediaFormat.createVideoFormat(mimeType, width, height)
            format.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            format.setInteger(MediaFormat.KEY_BIT_RATE, 2000000)
            format.setInteger(MediaFormat.KEY_FRAME_RATE, frameRate)
            format.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, iFrameInterval)

            encoder = MediaCodec.createEncoderByType(mimeType)
            encoder?.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            
            inputSurface = encoder?.createInputSurface()
            encoder?.start()
            
            startEncodingThread()
            
            println("H264 encoder initialized successfully")
        } catch (e: Exception) {
            println("Error initializing H264 encoder: ${e.message}")
            e.printStackTrace()
        }
    }

    private fun setupH264Decoder(surface: android.graphics.SurfaceTexture, width: Int, height: Int) {
        try {
            val mimeType = "video/avc"
            val format = MediaFormat.createVideoFormat(mimeType, width, height)
            format.setInteger(MediaFormat.KEY_WIDTH, width)
            format.setInteger(MediaFormat.KEY_HEIGHT, height)

            // 添加 SPS/PPS
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
            format.setByteBuffer("csd-0", ByteBuffer.wrap(sps))
            format.setByteBuffer("csd-1", ByteBuffer.wrap(pps))

            decoder = MediaCodec.createDecoderByType(mimeType)
            outputSurface = Surface(surface)
            decoder?.configure(format, outputSurface, null, 0)
            decoder?.start()

            println("H264 decoder initialized successfully with width: $width, height: $height")
        } catch (e: Exception) {
            println("Error initializing H264 decoder: ${e.message}")
            e.printStackTrace()
        }
    }

    private fun startEncodingThread() {
        Thread {
            isEncoding = true
            val bufferInfo = MediaCodec.BufferInfo()
            
            while (isEncoding && !isDisposed) {
                try {
                    val outputBufferId = encoder?.dequeueOutputBuffer(bufferInfo, 10000) ?: -1
                    when (outputBufferId) {
                        MediaCodec.INFO_TRY_AGAIN_LATER -> {
                            // No output available yet
                            Thread.sleep(10)
                        }
                        MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                            // Format changed, handle if needed
                            println("Encoder output format changed: ${encoder?.outputFormat}")
                        }
                        MediaCodec.INFO_OUTPUT_BUFFERS_CHANGED -> {
                            // Output buffers changed, handle if needed
                            println("Encoder output buffers changed")
                        }
                        else -> {
                            if (outputBufferId >= 0) {
                                val outputBuffer = encoder?.getOutputBuffer(outputBufferId)
                                if (outputBuffer != null) {
                                    val data = ByteArray(bufferInfo.size)
                                    outputBuffer.get(data)
                                    println("Encoded H264 frame: ${data.size} bytes")
                                    
                                    if (decodeMode == 0) {
                                        softDecodeAndDisplay(data)
                                    } else {
                                        hardDecodeAndDisplay(data)
                                    }
                                }
                                encoder?.releaseOutputBuffer(outputBufferId, false)
                            }
                        }
                    }
                } catch (e: Exception) {
                    if (!isDisposed) {
                        println("Error in encoding thread: ${e.message}")
                        e.printStackTrace()
                    }
                    break
                }
            }
        }.start()
    }

    private fun softDecodeAndDisplay(data: ByteArray) {
        if (isDisposed || decoder == null) return
        
        try {
            val inputBufferId = decoder?.dequeueInputBuffer(10000) ?: -1
            if (inputBufferId >= 0) {
                val inputBuffer = decoder?.getInputBuffer(inputBufferId)
                inputBuffer?.clear()
                inputBuffer?.put(data)
                decoder?.queueInputBuffer(inputBufferId, 0, data.size, System.nanoTime() / 1000, 0)
            }

            val bufferInfo = MediaCodec.BufferInfo()
            val outputBufferId = decoder?.dequeueOutputBuffer(bufferInfo, 10000) ?: -1
            if (outputBufferId >= 0) {
                decoder?.releaseOutputBuffer(outputBufferId, true)
                println("Soft decoded and displayed H264 frame")
            }
        } catch (e: Exception) {
            if (!isDisposed) {
                println("Error in soft decoding: ${e.message}")
                e.printStackTrace()
            }
        }
    }

    private fun hardDecodeAndDisplay(data: ByteArray) {
        if (isDisposed || decoder == null) return
        
        try {
            val inputBufferId = decoder?.dequeueInputBuffer(10000) ?: -1
            if (inputBufferId >= 0) {
                val inputBuffer = decoder?.getInputBuffer(inputBufferId)
                inputBuffer?.clear()
                inputBuffer?.put(data)
                decoder?.queueInputBuffer(inputBufferId, 0, data.size, System.nanoTime() / 1000, 0)
            }

            val bufferInfo = MediaCodec.BufferInfo()
            val outputBufferId = decoder?.dequeueOutputBuffer(bufferInfo, 10000) ?: -1
            if (outputBufferId >= 0) {
                decoder?.releaseOutputBuffer(outputBufferId, true)
                println("Hard decoded and displayed H264 frame")
            }
        } catch (e: Exception) {
            if (!isDisposed) {
                println("Error in hard decoding: ${e.message}")
                e.printStackTrace()
            }
        }
    }

    override fun getView(): View {
        return textureView
    }

    override fun dispose() {
        isDisposed = true
        isEncoding = false
        try {
            encoder?.stop()
            encoder?.release()
            encoder = null
            decoder?.stop()
            decoder?.release()
            decoder = null
            inputSurface?.release()
            outputSurface?.release()
            surfaceTexture?.release()
        } catch (e: Exception) {
            println("Error disposing resources: ${e.message}")
            e.printStackTrace()
        }
    }
}

class CameraPreviewViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, id: Int, args: Any?): PlatformView {
        val creationParams = args as? Map<String?, Any?>
        return CameraPreviewView(context, id, creationParams)
    }
} 