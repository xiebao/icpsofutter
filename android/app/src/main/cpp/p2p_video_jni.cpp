static void RecbVideoData(void* data, int length) {
    JNIEnv* env = nullptr;
    if (g_javaVM->GetEnv((void**)&env, JNI_VERSION_1_6) != JNI_OK) {
        LOGE("Failed to get JNIEnv");
        return;
    }

    if (!g_p2pVideoView) {
        LOGE("g_p2pVideoView is null");
        return;
    }

    if (g_isTextureMode) {
        // Texture 模式
        if (g_onTextureFrameMethod && g_textureId.load() != 0) {
            // 传递实际的视频数据
            jbyteArray jData = env->NewByteArray(length);
            env->SetByteArrayRegion(jData, 0, length, reinterpret_cast<const jbyte*>(data));
            env->CallVoidMethod(g_p2pVideoView, g_onTextureFrameMethod, 
                g_textureId.load(), jData, length);
            env->DeleteLocalRef(jData);
            LOGI("Texture frame processed with data length: %d", length);
        } else {
            LOGE("Texture mode but method or textureId is invalid");
        }
    } else {
        // AndroidView 模式
        if (g_onVideoFrameMethod) {
            jbyteArray jData = env->NewByteArray(length);
            env->SetByteArrayRegion(jData, 0, length, reinterpret_cast<const jbyte*>(data));
            env->CallVoidMethod(g_p2pVideoView, g_onVideoFrameMethod, jData);
            env->DeleteLocalRef(jData);
            LOGI("AndroidView frame processed with data length: %d", length);
        } else {
            LOGE("AndroidView mode but method is invalid");
        }
    }
} 