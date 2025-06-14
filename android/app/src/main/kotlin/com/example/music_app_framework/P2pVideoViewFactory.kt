package com.example.music_app_framework

import android.content.Context
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.plugin.common.StandardMessageCodec

class P2pVideoViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, id: Int, args: Any?): PlatformView {
        val mode = (args as? Map<*, *>)?.get("decodeMode") as? Int ?: 1
        val view = P2pVideoView(context)
        view.setDecodeMode(mode)
        return view
    }
} 