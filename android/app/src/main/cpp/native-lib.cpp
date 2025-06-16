#include <jni.h>
#include <string>
#include <android/log.h>
#include <android/native_window.h>
#include <android/native_window_jni.h>
#include <EGL/egl.h>
#include <GLES2/gl2.h>
#include <mutex>
#include <condition_variable>
#include <queue>
#include <atomic>
#include <chrono>
#include <thread>
#include "p2pInterface.h"

#define LOG_TAG "NativeLib"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

static JavaVM* g_vm = nullptr;
static jobject g_p2pVideoView = nullptr;
static jmethodID g_onVideoFrameMethod = nullptr;
static jmethodID g_onTextureFrameMethod = nullptr;
static jmethodID g_onErrorMethod = nullptr;
static std::atomic<bool> g_isStopping(false);
static std::atomic<bool> g_isTextureMode(false);
static std::atomic<long> g_textureId(0);
static std::atomic<int> g_frameCount(0);
static std::atomic<int> g_errorCount(0);
static std::atomic<bool> g_isDisposed(false);
static jlong g_flutterTextureId = 0;

// 空实现的消息回调
void RecbMsgData(void* pMsgData, int nLen) {
    // 完全空的实现，不做任何处理
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_music_1app_1framework_P2pVideoView_bindNative(
        JNIEnv* env,
        jobject thiz) {
    if (g_isDisposed) {
        LOGI("View is disposed, ignoring bind request");
        return;
    }

    // 保存 JavaVM 指针
    env->GetJavaVM(&g_vm);

    // 保存 P2pVideoView 实例的全局引用
    if (g_p2pVideoView != nullptr) {
        env->DeleteGlobalRef(g_p2pVideoView);
    }
    g_p2pVideoView = env->NewGlobalRef(thiz);

    // 获取方法 ID
    jclass clazz = env->GetObjectClass(thiz);
    g_onVideoFrameMethod = env->GetMethodID(clazz, "onVideoFrame", "([B)V");
    g_onTextureFrameMethod = env->GetMethodID(clazz, "onTextureFrame", "(JII)V");
    g_onErrorMethod = env->GetMethodID(clazz, "onError", "(Ljava/lang/String;)V");

    LOGI("Native bind successful");
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_music_1app_1framework_P2pVideoView_setDisplayMode(
        JNIEnv* env,
        jobject thiz,
        jint mode) {
    if (g_isDisposed) {
        LOGI("View is disposed, ignoring setDisplayMode request");
        return;
    }

    g_isTextureMode = (mode == 1);
    LOGI("Display mode set to: %s", g_isTextureMode ? "Texture" : "AndroidView");
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_music_1app_1framework_P2pVideoView_setTextureId(
        JNIEnv* env,
        jobject thiz,
        jlong textureId) {
    if (g_isDisposed) {
        LOGI("View is disposed, ignoring setTextureId request");
        return;
    }

    g_textureId.store(textureId);
    LOGI("Texture ID set to: %ld", g_textureId.load());
}

static void notifyError(const char* message) {
    if (g_isDisposed || !g_vm || !g_p2pVideoView || !g_onErrorMethod) {
        return;
    }

    JNIEnv* env;
    if (g_vm->AttachCurrentThread(&env, nullptr) == JNI_OK) {
        jstring jMessage = env->NewStringUTF(message);
        env->CallVoidMethod(g_p2pVideoView, g_onErrorMethod, jMessage);
        env->DeleteLocalRef(jMessage);
        g_vm->DetachCurrentThread();
    }
}

static void RecbVideoData(void* data, int length) {
    LOGI("[自检] >>>>>>>>>>>> RecbVideoData called! length: %d", length);
    
    if (g_isDisposed || !g_vm || !g_p2pVideoView) {
        LOGE("[自检] RecbVideoData: Invalid state - disposed: %d, vm: %p, view: %p", 
             g_isDisposed.load(), g_vm, g_p2pVideoView);
        return;
    }

    if (!data || length <= 0) {
        LOGE("[自检] Invalid video data received");
        notifyError("Invalid video data received");
        return;
    }

    // 打印前16个字节用于调试
    unsigned char* bytes = (unsigned char*)data;
    char hex[33] = {0};
    for(int i = 0; i < 16 && i < length; i++) {
        sprintf(hex + (i*2), "%02x", bytes[i]);
    }
    LOGI("[自检] First 16 bytes of video data: %s", hex);

    // 检查是否是H.264 NALU起始码
    if (length >= 4 && bytes[0] == 0x00 && bytes[1] == 0x00 && bytes[2] == 0x00 && bytes[3] == 0x01) {
        LOGI("[自检] Found H.264 NALU start code");
        // 检查NALU类型
        if (length >= 5) {
            int naluType = bytes[4] & 0x1F;
            LOGI("[自检] NALU type: %d", naluType);
            switch (naluType) {
                case 1:
                    LOGI("[自检] NALU type: Non-IDR slice");
                    break;
                case 5:
                    LOGI("[自检] NALU type: IDR slice");
                    break;
                case 7:
                    LOGI("[自检] NALU type: SPS");
                    break;
                case 8:
                    LOGI("[自检] NALU type: PPS");
                    break;
                default:
                    LOGI("[自检] NALU type: Other (%d)", naluType);
                    break;
            }
        }
    }

    JNIEnv* env;
    if (g_vm->AttachCurrentThread(&env, nullptr) != JNI_OK) {
        LOGE("[自检] Failed to attach thread");
        return;
    }

    try {
        if (g_isTextureMode) {
            LOGI("[自检] Processing video frame in Texture mode");
            // Texture 模式
            if (g_onTextureFrameMethod && g_textureId.load() != 0) {
                jbyteArray jData = env->NewByteArray(length);
                if (!jData) {
                    LOGE("[自检] Failed to create byte array");
                    return;
                }
                env->SetByteArrayRegion(jData, 0, length, reinterpret_cast<const jbyte*>(data));
                env->CallVoidMethod(g_p2pVideoView, g_onTextureFrameMethod, 
                    g_textureId.load(), jData, length);
                env->DeleteLocalRef(jData);
                LOGI("[自检] Texture frame processed with data length: %d", length);
            } else {
                LOGE("[自检] Texture mode but method or ID invalid - method: %p, id: %ld", 
                     g_onTextureFrameMethod, g_textureId.load());
            }
        } else {
            LOGI("[自检] Processing video frame in AndroidView mode");
            // AndroidView 模式
            if (g_onVideoFrameMethod) {
                jbyteArray jData = env->NewByteArray(length);
                if (!jData) {
                    LOGE("[自检] Failed to create byte array");
                    return;
                }
                env->SetByteArrayRegion(jData, 0, length, reinterpret_cast<const jbyte*>(data));
                env->CallVoidMethod(g_p2pVideoView, g_onVideoFrameMethod, jData);
                env->DeleteLocalRef(jData);
                LOGI("[自检] AndroidView frame processed");
            } else {
                LOGE("[自检] AndroidView mode but method invalid");
            }
        }
        g_frameCount++;
        LOGI("[自检] Frame processed successfully, total frames: %d", g_frameCount.load());
    } catch (const std::exception& e) {
        g_errorCount++;
        LOGE("[自检] Exception in video data callback: %s", e.what());
        notifyError(e.what());
    }

    g_vm->DetachCurrentThread();
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_music_1app_1framework_P2pVideoView_startP2pVideo(
        JNIEnv* env,
        jobject thiz) {
    if (g_isDisposed) {
        LOGI("View is disposed, ignoring startP2pVideo request");
        return;
    }

    try {
        LOGI("Starting P2P video...");
        LOGI("Current state - Texture mode: %d, Texture ID: %ld", 
             g_isTextureMode.load(), g_textureId.load());
        
        // 确保回调函数指针有效
        if (!RecbVideoData) {
            LOGE("RecbVideoData callback is null");
            return;
        }
        
        StartP2pVideo(RecbVideoData);
        LOGI("StartP2pVideo called with callback");
    } catch (const std::exception& e) {
        LOGE("Exception in startP2pVideo: %s", e.what());
        notifyError(e.what());
    } catch (...) {
        LOGE("Unknown exception in startP2pVideo");
        notifyError("Unknown exception in startP2pVideo");
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_music_1app_1framework_P2pVideoView_stopP2pVideo(
        JNIEnv* env,
        jobject thiz) {
    if (g_isDisposed) {
        LOGI("View is disposed, ignoring stopP2pVideo request");
        return;
    }

    if (g_isStopping.exchange(true)) {
        LOGI("Stop operation already in progress");
        return;
    }

    LOGI("Stopping P2P video...");
    std::thread([&]() {
        try {
            StopP2pVideo();
            LOGI("P2P video stopped successfully");
        } catch (const std::exception& e) {
            LOGE("Error stopping P2P video: %s", e.what());
            notifyError(e.what());
        }
        g_isStopping.store(false);
    }).detach();
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_music_1app_1framework_P2pVideoView_release(
        JNIEnv* env,
        jobject thiz) {
    g_isDisposed.store(true);
    
    if (g_p2pVideoView != nullptr) {
        env->DeleteGlobalRef(g_p2pVideoView);
        g_p2pVideoView = nullptr;
    }
    
    g_onVideoFrameMethod = nullptr;
    g_onTextureFrameMethod = nullptr;
    g_onErrorMethod = nullptr;
    
    LOGI("Native resources released");
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_music_1app_1framework_MainActivity_initMqtt(JNIEnv* env, jobject thiz, jstring phoneId) {
    if (!phoneId) {
        LOGE("initMqtt: phoneId is null");
        notifyError("MQTT initialization failed: phoneId is null");
        return;
    }
    
    const char* phoneIdStr = env->GetStringUTFChars(phoneId, nullptr);
    if (!phoneIdStr) {
        LOGE("initMqtt: Failed to get phoneId string");
        notifyError("MQTT initialization failed: Invalid phoneId");
        return;
    }
    
    LOGI("initMqtt: Initializing MQTT with phoneId: %s", phoneIdStr);
    
    // 检查是否已经初始化
    static bool isInitialized = false;
    if (isInitialized) {
        LOGI("initMqtt: MQTT already initialized");
        env->ReleaseStringUTFChars(phoneId, phoneIdStr);
        return;
    }
    
    // 初始化 MQTT
    InitMqtt(const_cast<char*>(phoneIdStr), RecbMsgData);
    isInitialized = true;
    
    LOGI("initMqtt: MQTT initialization completed successfully");
    env->ReleaseStringUTFChars(phoneId, phoneIdStr);
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_music_1app_1framework_MainActivity_setDevP2p(JNIEnv* env, jobject /* this */, jstring devId) {
    const char* pDevId = env->GetStringUTFChars(devId, nullptr);
    LOGI("[native] JNI setDevP2p called: %s", pDevId);
    SetDevP2p((char*)pDevId);
    env->ReleaseStringUTFChars(devId, pDevId);
    LOGI("[native] setDevP2p completed");
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_music_1app_1framework_MainActivity_startP2pVideo(JNIEnv* env, jobject thiz, jstring devId) {
    const char* pDevId = env->GetStringUTFChars(devId, nullptr);
    LOGI("[自检] >>>>>>>>>>>> Enter startP2pVideo");
    LOGI("[自检] JNI setDevP2p called: %s", pDevId);
    
    SetDevP2p((char*)pDevId);
    env->ReleaseStringUTFChars(devId, pDevId);
    
    LOGI("[自检] JNI startP2pVideo called, will call StartP2pVideo");
    LOGI("[自检] Registering RecbVideoData callback, waiting for frames...");
    
    // 检查回调函数指针
    if (!RecbVideoData) {
        LOGE("[自检] RecbVideoData callback is null!");
        return;
    }
    
    LOGI("[自检] About to call StartP2pVideo with callback: %p", (void*)RecbVideoData);
    StartP2pVideo(RecbVideoData);
    LOGI("[自检] StartP2pVideo called, waiting for video data...");
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_music_1app_1framework_MainActivity_stopP2pVideo(JNIEnv* env, jobject /* this */) {
    LOGI("[native] JNI stopP2pVideo called");
    StopP2pVideo();
    LOGI("[native] StopP2pVideo called");
}

extern "C"
JNIEXPORT void JNICALL
Java_com_example_music_1app_1framework_MainActivity_setFlutterTextureId(JNIEnv* env, jobject thiz, jlong textureId) {
    g_flutterTextureId = textureId;
    __android_log_print(ANDROID_LOG_INFO, "NativeLib", "setFlutterTextureId called: %lld", (long long)textureId);
    // TODO: 这里可以根据 textureId 获取/绑定 Surface/SurfaceTexture
}

// 添加P2P连接状态检查函数
extern "C" JNIEXPORT jint JNICALL
Java_com_example_music_1app_1framework_MainActivity_getP2pStatus(JNIEnv* env, jobject thiz) {
    LOGI("[自检] Checking P2P connection status...");
    // 这里应该调用实际的P2P状态检查函数
    // 临时返回1表示已连接
    return 1;
}

// 添加测试函数
extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_music_1app_1framework_P2pTestActivity_testInitMqtt(JNIEnv* env, jobject thiz, jstring phoneId) {
    const char* pPhoneId = env->GetStringUTFChars(phoneId, nullptr);
    LOGI("[测试] 调用InitMqtt: %s", pPhoneId);
    
    InitMqtt((char*)pPhoneId, RecbMsgData);
    env->ReleaseStringUTFChars(phoneId, pPhoneId);
    
    return JNI_TRUE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_music_1app_1framework_P2pTestActivity_testSetDevP2p(JNIEnv* env, jobject thiz, jstring devId) {
    const char* pDevId = env->GetStringUTFChars(devId, nullptr);
    LOGI("[测试] 调用SetDevP2p: %s", pDevId);
    
    SetDevP2p((char*)pDevId);
    env->ReleaseStringUTFChars(devId, pDevId);
    
    return JNI_TRUE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_music_1app_1framework_P2pTestActivity_testStartP2pVideo(JNIEnv* env, jobject thiz) {
    LOGI("[测试] 调用StartP2pVideo");
    LOGI("[测试] 注册RecbVideoData回调");
    
    if (!RecbVideoData) {
        LOGE("[测试] RecbVideoData回调为空");
        return JNI_FALSE;
    }
    
    StartP2pVideo(RecbVideoData);
    LOGI("[测试] StartP2pVideo调用完成");
    
    return JNI_TRUE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_music_1app_1framework_P2pTestActivity_testStopP2pVideo(JNIEnv* env, jobject thiz) {
    LOGI("[测试] 调用StopP2pVideo");
    StopP2pVideo();
    return JNI_TRUE;
} 