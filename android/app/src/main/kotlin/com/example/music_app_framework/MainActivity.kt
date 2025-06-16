package com.example.music_app_framework

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Context
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.common.BinaryMessenger
import android.util.Log

class MainActivity: FlutterActivity() {
    companion object {
        private const val TAG = "MainActivity"
        init {
            System.loadLibrary("native-lib")
        }
    }

    external fun setDevP2p(devId: String)
    external fun startP2pVideo(devId: String)
    external fun stopP2pVideo()
    external fun initMqtt(phoneId: String)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        var p2pView: P2pVideoView? = null
        val factory = P2pVideoViewFactory(flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "p2p_video_channel").setMethodCallHandler { call, result ->
            when (call.method) {
                "initMqtt" -> {
                    try {
                        val phoneId = call.argument<String>("phoneId") ?: "phoneId123"
                        Log.d(TAG, "Initializing MQTT with phoneId: $phoneId")
                        initMqtt(phoneId)
                        result.success(null)
                    } catch (e: Exception) {
                        Log.e(TAG, "MQTT initialization failed", e)
                        result.error("MQTT_INIT_ERROR", "MQTT initialization failed: ${e.message}", null)
                    }
                }
                "setDevP2p" -> {
                    try {
                        val devId = call.argument<String>("devId") ?: ""
                        setDevP2p(devId)
                        result.success(null)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to set device P2P", e)
                        result.error("P2P_SET_ERROR", "Failed to set device P2P: ${e.message}", null)
                    }
                }
                "startP2pVideo" -> {
                    try {
                        val devId = call.argument<String>("devId") ?: ""
                        startP2pVideo(devId)
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
                "setDecodeMode" -> {
                    try {
                        val mode = call.argument<Int>("mode") ?: 1
                        p2pView?.updateDecodeMode(mode)
                        result.success(null)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to set decode mode", e)
                        result.error("DECODE_MODE_ERROR", "Failed to set decode mode: ${e.message}", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        flutterEngine.platformViewsController.registry.registerViewFactory("p2p_video_view", factory)
    }
}
