package com.example.music_app_framework

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Context
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.common.BinaryMessenger
import android.util.Log
import androidx.annotation.NonNull

class MainActivity: FlutterActivity() {
    private val TAG = "MainActivity"
    
    init {
        System.loadLibrary("native-lib")
    }

    private external fun initMqtt(phoneId: String)
    private external fun setDevP2p(devId: String)
    private external fun startP2pVideo(devId: String)
    private external fun stopP2pVideo()
    private external fun setFlutterTextureId(textureId: Long)
    private external fun getP2pStatus(): Int

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        var p2pView: P2pVideoView? = null
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        p2pView = P2pVideoView(this, MethodChannel(messenger, "p2p_video_view_manual"), 0, null)
        val factory = P2pVideoViewFactory(messenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "p2p_video_channel").setMethodCallHandler { call, result ->
            when (call.method) {
                "initMqtt" -> {
                    try {
                        val phoneId = call.argument<String>("phoneId") ?: ""
                        Log.d(TAG, "Initializing MQTT with phoneId: $phoneId")
                        initMqtt(phoneId)
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
                        setDevP2p(devId)
                        result.success(null)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to set device P2P", e)
                        result.error("P2P_SET_ERROR", "Failed to set device P2P: ${e.message}", null)
                    }
                }
                "startP2pVideo" -> {
                    try {
                        Log.d(TAG, "MainActivity 通过 p2pView 调用 callStartP2pVideoWithLog() (无参数)")
                        p2pView?.callStartP2pVideoWithLog()
                        Log.d(TAG, "MainActivity 调用 p2pView.callStartP2pVideoWithLog() (无参数) 后")
                        result.success(null)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to start P2P video", e)
                        result.error("P2P_START_ERROR", "Failed to start P2P video: ${e.message}", null)
                    }
                }
                "stopP2pVideo" -> {
                    try {
                        stopP2pVideo()
                        result.success(null)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to stop P2P video", e)
                        result.error("P2P_STOP_ERROR", "Failed to stop P2P video: ${e.message}", null)
                    }
                }
                "createTexture" -> {
                    val textureId = System.nanoTime()
                    result.success(textureId)
                }
                "checkFrameStatus" -> {
                    // 可在此处实现帧状态检查逻辑，当前直接返回 success
                    result.success(null)
                }
                "setDecodeMode" -> {
                    // TODO: 可在此处实现解码模式切换逻辑
                    result.success(null)
                }
                "disposeTexture" -> {
                    // TODO: 可在此处实现 Texture 资源释放逻辑
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        flutterEngine.platformViewsController.registry.registerViewFactory("p2p_video_view", factory)
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory("camera_preview", CameraPreviewViewFactory())
    }
}
