package com.mainipc.xiebaoxin

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Context
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.common.BinaryMessenger
import android.util.Log
import androidx.annotation.NonNull
import android.view.Surface
import io.flutter.view.TextureRegistry
import android.os.Handler
import android.os.Looper

class MainActivity: FlutterActivity() {
    private val TAG = "MainActivity"
    private val CHANNEL = "p2p_video_channel"
    
    private var h264DecoderP2p: H264Decoder? = null
    private var surfaceP2p: Surface? = null
    private var surfaceEntryP2p: TextureRegistry.SurfaceTextureEntry? = null
    private var cameraStreamer: CameraH264Streamer? = null
    private var methodChannel: MethodChannel? = null

    init {
        System.loadLibrary("native-lib")
    }

    private external fun initMqtt(phoneId: String)
    private external fun setDevP2p(devId: String)
    private external fun startP2pVideo()
    private external fun stopP2pVideo()
    private external fun deinitMqtt()
    external fun nativeRecbVideoData(data: ByteArray, len: Int)
    private external fun bindNative()
    private external fun sendJsonMsg(json: String, topic: String): Int

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        P2pTexturePlugin.textureRegistry = flutterEngine.renderer
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        flutterEngine.platformViewsController.registry.registerViewFactory("p2p_video_view", P2pVideoViewFactory(messenger))
        val factory = P2pVideoViewFactory(messenger)
        var p2pView: P2pVideoView? = null
        p2pView = P2pVideoView(this, messenger, MethodChannel(messenger, "p2p_video_view_manual"), 0, null)
        
        bindNative()
        
        methodChannel = MethodChannel(messenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "initMqtt" -> {
                    try {
                        val phoneId = call.argument<String>("phoneId") ?: ""
                        Log.d(TAG, "Initializing MQTT with phoneId: $phoneId")
                        Log.d(TAG, "[CALL] initMqtt 调用前")
                        initMqtt(phoneId)
                        Log.d(TAG, "[CALL] initMqtt 调用后")
                        result.success(null)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to initialize MQTT", e)
                        result.error("MQTT_INIT_ERROR", "Failed to initialize MQTT: ${e.message}", null)
                    }
                }
                "setDevP2p" -> {
                    try {
                        val devId = call.argument<String>("devId") ?: ""
                        Log.d(TAG, "Setting device P2P: $devId")
                        Log.d(TAG, "[CALL] setDevP2p 调用前")
                        setDevP2p(devId)
                        Log.d(TAG, "[CALL] setDevP2p 调用后")
                        result.success(null)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to set device P2P", e)
                        result.error("P2P_SET_ERROR", "Failed to set device P2P: ${e.message}", null)
                    }
                }
                "startP2pVideo" -> {
                    try {
                        Log.d(TAG, "Starting P2P video")
                        Log.d(TAG, "[CALL] startP2pVideo 调用前")
                        startP2pVideo()
                        Log.d(TAG, "[CALL] startP2pVideo 调用后")
                        result.success(null)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to start P2P video", e)
                        result.error("P2P_VIDEO_ERROR", "Failed to start P2P video: ${e.message}", null)
                    }
                }
                "stopP2pVideo" -> {
                    try {
                        Log.d(TAG, "Stopping P2P video")
                        Log.d(TAG, "[CALL] stopP2pVideo 调用前")
                        stopP2pVideo()
                        Log.d(TAG, "[CALL] stopP2pVideo 调用后")
                        result.success(null)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to stop P2P video", e)
                        result.error("P2P_VIDEO_ERROR", "Failed to stop P2P video: ${e.message}", null)
                    }
                }
                "startCameraH264Stream" -> {
                    try {
                        Log.d(TAG, "Starting camera H264 stream")
                        if (cameraStreamer == null) {
                            cameraStreamer = CameraH264Streamer(this, object : CameraH264Streamer.OnH264DataCallback {
                                override fun onH264Data(data: ByteArray) {
                                    // 使用相同的 RecbVideoData 回调处理摄像头数据
                                    nativeRecbVideoData(data, data.size)
                                }
                            })
                        }
                        cameraStreamer?.startStreaming()
                        result.success(null)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to start camera stream", e)
                        result.error("CAMERA_ERROR", "Failed to start camera stream: ${e.message}", null)
                    }
                }
                "stopCameraH264Stream" -> {
                    try {
                        Log.d(TAG, "Stopping camera H264 stream")
                        cameraStreamer?.stopStreaming()
                        result.success(null)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to stop camera stream", e)
                        result.error("CAMERA_ERROR", "Failed to stop camera stream: ${e.message}", null)
                    }
                }
                "deinitMqtt" -> {
                    try {
                        Log.d(TAG, "Deinitializing MQTT")
                        Log.d(TAG, "[CALL] deinitMqtt 调用前")
                        deinitMqtt()
                        Log.d(TAG, "[CALL] deinitMqtt 调用后")
                        result.success(null)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to deinitialize MQTT", e)
                        result.error("MQTT_DEINIT_ERROR", "Failed to deinitialize MQTT: ${e.message}", null)
                    }
                }
                "sendJsonMsg" -> {
                    val json = call.argument<String>("json") ?: ""
                    val topic = call.argument<String>("topic") ?: ""
                    val ret = sendJsonMsg(json, topic)
                    result.success(ret)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        cameraStreamer?.release()
        cameraStreamer = null
    }
    
    // MQTT 消息回调方法，由 C++ 调用
    fun onMqttMessage(data: ByteArray, length: Int) {
        Log.d(TAG, "Received MQTT message, length: $length")
        try {
            val messageString = String(data, 0, length, Charsets.UTF_8)
            Log.d(TAG, "MQTT message content: $messageString")
            // 切换到主线程
            Handler(Looper.getMainLooper()).post {
                methodChannel?.invokeMethod("onMqttMessage", mapOf(
                    "data" to messageString,
                    "length" to length
                ))
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error processing MQTT message", e)
        }
    }
}
