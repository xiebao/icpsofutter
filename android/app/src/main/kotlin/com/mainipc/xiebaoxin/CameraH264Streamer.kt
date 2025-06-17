package com.mainipc.xiebaoxin

import android.content.Context
import android.graphics.ImageFormat
import android.hardware.camera2.*
import android.media.ImageReader
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.os.Handler
import android.os.HandlerThread
import android.util.Size
import android.view.Surface
import android.media.MediaCodecList
import android.os.Looper
import android.util.Log

class CameraH264Streamer(
    private val context: Context,
    private val callback: OnH264DataCallback
) {
    interface OnH264DataCallback {
        fun onH264Data(data: ByteArray)
    }

    companion object {
        private const val TAG = "CameraH264Streamer"
        private const val TIMEOUT_US = 10000L
        private const val WIDTH = 640
        private const val HEIGHT = 480
        private const val FRAME_RATE = 30
        private const val BIT_RATE = 2_000_000
        private const val I_FRAME_INTERVAL = 1
    }

    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var mediaCodec: MediaCodec? = null
    private var encoderInputSurface: Surface? = null
    private var cameraThread: HandlerThread? = null
    private var cameraHandler: Handler? = null
    private var isStreaming = false
    private val lock = Object()

    fun startStreaming() {
        synchronized(lock) {
            if (isStreaming) return
            isStreaming = true
        }

        initCamera()
    }

    private fun initCamera() {
        try {
            // 初始化相机线程
            cameraThread = HandlerThread("CameraThread").apply { start() }
            cameraHandler = Handler(cameraThread!!.looper)

            // 初始化编码器
            initEncoder()

            // 打开相机
            val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val cameraId = manager.cameraIdList[0] // 使用第一个相机
            
            manager.openCamera(cameraId, object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    cameraDevice = camera
                    createCaptureSession()
                }

                override fun onDisconnected(camera: CameraDevice) {
                    stopStreaming()
                }

                override fun onError(camera: CameraDevice, error: Int) {
                    Log.e(TAG, "Camera error: $error")
                    stopStreaming()
                }
            }, cameraHandler)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to init camera", e)
            stopStreaming()
        }
    }

    private fun initEncoder() {
        try {
            val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, WIDTH, HEIGHT).apply {
                setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
                setInteger(MediaFormat.KEY_BIT_RATE, BIT_RATE)
                setInteger(MediaFormat.KEY_FRAME_RATE, FRAME_RATE)
                setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, I_FRAME_INTERVAL)
            }

            mediaCodec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC).apply {
                configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                encoderInputSurface = createInputSurface()
                start()
            }

            // 启动编码输出线程
            startEncoderThread()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to init encoder", e)
            stopStreaming()
        }
    }

    private fun createCaptureSession() {
        try {
            val surfaces = listOf(encoderInputSurface!!)
            
            cameraDevice?.createCaptureSession(surfaces, object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(session: CameraCaptureSession) {
                    if (!isStreaming) return
                    
                    captureSession = session
                    val builder = cameraDevice?.createCaptureRequest(CameraDevice.TEMPLATE_RECORD)
                    builder?.addTarget(encoderInputSurface!!)
                    builder?.set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, android.util.Range(FRAME_RATE, FRAME_RATE))
                    
                    session.setRepeatingRequest(builder!!.build(), null, cameraHandler)
                }

                override fun onConfigureFailed(session: CameraCaptureSession) {
                    Log.e(TAG, "Failed to configure camera session")
                    stopStreaming()
                }
            }, cameraHandler)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create capture session", e)
            stopStreaming()
        }
    }

    private fun startEncoderThread() {
        Thread {
            val bufferInfo = MediaCodec.BufferInfo()
            while (isStreaming) {
                if (mediaCodec == null) break
                
                val outputBufferId = mediaCodec!!.dequeueOutputBuffer(bufferInfo, TIMEOUT_US)
                if (outputBufferId >= 0) {
                    val outputBuffer = mediaCodec!!.getOutputBuffer(outputBufferId)
                    outputBuffer?.let {
                        val data = ByteArray(bufferInfo.size)
                        it.get(data)
                        callback.onH264Data(data)
                    }
                    mediaCodec!!.releaseOutputBuffer(outputBufferId, false)
                }
            }
        }.start()
    }

    fun stopStreaming() {
        synchronized(lock) {
            if (!isStreaming) return
            isStreaming = false
        }

        try {
            captureSession?.close()
            captureSession = null

            cameraDevice?.close()
            cameraDevice = null

            mediaCodec?.stop()
            mediaCodec?.release()
            mediaCodec = null

            encoderInputSurface?.release()
            encoderInputSurface = null

            cameraThread?.quitSafely()
            cameraThread = null
            cameraHandler = null
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping streaming", e)
        }
    }

    fun release() {
        stopStreaming()
    }
} 