package com.mainipc.xiebaoxin

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.view.TextureRegistry

class P2pTexturePlugin : FlutterPlugin {
    companion object {
        var textureRegistry: TextureRegistry? = null
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        textureRegistry = binding.textureRegistry
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        textureRegistry = null
    }
} 