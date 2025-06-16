package com.example.music_app_framework;

import android.os.Bundle;
import android.util.Log;
import android.view.TextureView;
import android.widget.FrameLayout;
import androidx.annotation.NonNull;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugins.GeneratedPluginRegistrant;

public class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "p2p_video_channel";
    private static final String TAG = "MainActivity";
    private MethodChannel mChannel;
    private long mFlutterTextureId = 0;

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        
        // 设置方法通道
        mChannel = new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL);
        mChannel.setMethodCallHandler(this::handleMethod);
        
        // 注册平台视图工厂
        flutterEngine.getPlatformViewsController().getRegistry()
            .registerViewFactory("p2p_video_view", new P2pVideoViewFactory(flutterEngine.getDartExecutor().getBinaryMessenger()));
    }

    private void handleMethod(MethodCall call, MethodChannel.Result result) {
        switch (call.method) {
            case "initMqtt":
                String phoneId = call.argument("phoneId");
                Log.d(TAG, "Initializing MQTT with phoneId: " + phoneId);
                nativeInitMqtt(phoneId);
                result.success(null);
                break;
            case "setDevP2p":
                String devId = call.argument("devId");
                Log.d(TAG, "Setting device P2P: " + devId);
                nativeSetDevP2p(devId);
                result.success(null);
                break;
            case "startP2pVideo":
                String startDevId = call.argument("devId");
                int displayMode = call.argument("displayMode");
                long textureId = call.argument("textureId");
                int decodeMode = call.argument("decodeMode");
                Log.d(TAG, "Starting P2P video with devId: " + startDevId + ", displayMode: " + displayMode + ", textureId: " + textureId + ", decodeMode: " + decodeMode);
                nativeStartP2pVideo(startDevId);
                result.success(null);
                break;
            case "stopP2pVideo":
                Log.d(TAG, "Stopping P2P video");
                nativeStopP2pVideo();
                result.success(null);
                break;
            default:
                result.notImplemented();
                break;
        }
    }

    // Native 方法声明
    private native void nativeInitMqtt(String phoneId);
    private native void nativeSetDevP2p(String devId);
    private native void nativeStartP2pVideo(String devId);
    private native void nativeStopP2pVideo();

    static {
        System.loadLibrary("native-lib");
    }
} 