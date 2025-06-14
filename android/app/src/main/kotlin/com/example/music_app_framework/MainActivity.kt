package com.example.music_app_framework

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Context
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.plugin.common.StandardMessageCodec

class MainActivity: FlutterActivity() {
    companion object {
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
        initMqtt("androidPhoneId")
        var p2pView: P2pVideoView? = null
        val factory = object : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
            override fun create(context: android.content.Context, id: Int, args: Any?): io.flutter.plugin.platform.PlatformView {
                val mode = (args as? Map<*, *>)?.get("decodeMode") as? Int ?: 1
                val view = P2pVideoView(context)
                view.setDecodeMode(mode)
                p2pView = view
                return view
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "p2p_video_channel").setMethodCallHandler { call, result ->
            when (call.method) {
                "initMqtt" -> {
                    val phoneId = call.argument<String>("phoneId") ?: "phoneId123"
                    initMqtt(phoneId)
                    result.success(null)
                }
                "setDevP2p" -> {
                    val devId = call.argument<String>("devId") ?: ""
                    setDevP2p(devId)
                    result.success(null)
                }
                "startP2pVideo" -> {
                    val devId = call.argument<String>("devId") ?: ""
                    startP2pVideo(devId)
                    result.success(null)
                }
                "stopP2pVideo" -> {
                    stopP2pVideo()
                    result.success(null)
                }
                "setDecodeMode" -> {
                    val mode = call.argument<Int>("mode") ?: 1
                    p2pView?.setDecodeMode(mode)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        flutterEngine.platformViewsController.registry.registerViewFactory("p2p_video_view", factory)
    }
}
