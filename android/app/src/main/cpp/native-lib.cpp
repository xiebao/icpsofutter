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
#include <media/NdkMediaCodec.h>
#include <media/NdkMediaFormat.h>
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

static AMediaCodec* g_mediaCodec = nullptr;
static ANativeWindow* g_nativeWindow = nullptr;
static std::mutex g_codecMutex;
static bool g_isCodecInitialized = false;
static int g_videoWidth = 1280;  // 默认视频宽度
static int g_videoHeight = 720;  // 默认视频高度
static bool g_mqttInitialized = false;

static bool initializeCodec() {
    std::lock_guard<std::mutex> lock(g_codecMutex);
    
    if (g_isCodecInitialized) {
        return true;
    }

    // 创建 MediaCodec
    g_mediaCodec = AMediaCodec_createDecoderByType("video/avc");
    if (!g_mediaCodec) {
        LOGE("Failed to create MediaCodec");
        return false;
    }

    // 配置 MediaCodec
    AMediaFormat* format = AMediaFormat_new();
    AMediaFormat_setInt32(format, AMEDIAFORMAT_KEY_WIDTH, g_videoWidth);
    AMediaFormat_setInt32(format, AMEDIAFORMAT_KEY_HEIGHT, g_videoHeight);
    AMediaFormat_setString(format, AMEDIAFORMAT_KEY_MIME, "video/avc");
    AMediaFormat_setInt32(format, AMEDIAFORMAT_KEY_COLOR_FORMAT, 0x7F000789);  // COLOR_FormatYUV420Flexible
    AMediaFormat_setInt32(format, AMEDIAFORMAT_KEY_BIT_RATE, 2000000);  // 2Mbps
    AMediaFormat_setInt32(format, AMEDIAFORMAT_KEY_FRAME_RATE, 30);
    AMediaFormat_setInt32(format, AMEDIAFORMAT_KEY_I_FRAME_INTERVAL, 1);

    // 配置解码器
    media_status_t status = AMediaCodec_configure(g_mediaCodec, format, nullptr, nullptr, 0);
    AMediaFormat_delete(format);
    
    if (status != AMEDIA_OK) {
        LOGE("Failed to configure MediaCodec");
        AMediaCodec_delete(g_mediaCodec);
        g_mediaCodec = nullptr;
        return false;
    }

    // 启动解码器
    status = AMediaCodec_start(g_mediaCodec);
    if (status != AMEDIA_OK) {
        LOGE("Failed to start MediaCodec");
        AMediaCodec_delete(g_mediaCodec);
        g_mediaCodec = nullptr;
        return false;
    }

    g_isCodecInitialized = true;
    LOGI("MediaCodec initialized successfully");
    return true;
}

static void releaseCodec() {
    std::lock_guard<std::mutex> lock(g_codecMutex);
    
    if (g_mediaCodec) {
        AMediaCodec_stop(g_mediaCodec);
        AMediaCodec_delete(g_mediaCodec);
        g_mediaCodec = nullptr;
    }
    
    if (g_nativeWindow) {
        ANativeWindow_release(g_nativeWindow);
        g_nativeWindow = nullptr;
    }
    
    g_isCodecInitialized = false;
}

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

// 保存 JNI 环境
static JNIEnv* getJNIEnv() {
    JNIEnv* env = nullptr;
    if (g_vm->GetEnv((void**)&env, JNI_VERSION_1_6) != JNI_OK) {
        LOGE("Failed to get JNIEnv");
        return nullptr;
    }
    return env;
}

// 视频数据回调
void RecbVideoData(void* data, int length) {
    LOGI("[自检] RecbVideoData called! length: %d", length);
    
    if (g_isDisposed || !g_vm || !g_p2pVideoView) {
        LOGE("[自检] RecbVideoData: Invalid state - disposed: %d, vm: %p, view: %p", 
             g_isDisposed.load(), g_vm, g_p2pVideoView);
        return;
    }

    if (!data || length <= 0) {
        LOGE("[自检] Invalid video data received");
        return;
    }

    // 检查H.264数据格式
    uint8_t* h264Data = static_cast<uint8_t*>(data);
    bool isKeyFrame = false;
    if (length > 4) {
        // 检查NAL单元类型
        uint8_t nalType = h264Data[4] & 0x1F;
        isKeyFrame = (nalType == 5); // IDR帧
        LOGI("[自检] NAL type: %d, isKeyFrame: %d", nalType, isKeyFrame);
    }

    JNIEnv* env;
    if (g_vm->AttachCurrentThread(&env, nullptr) != JNI_OK) {
        LOGE("[自检] Failed to attach thread");
        return;
    }

    try {
        if (!g_onVideoFrameMethod) {
            LOGE("[自检] g_onVideoFrameMethod is null");
            return;
        }
        jbyteArray jData = env->NewByteArray(length);
        if (!jData) {
            LOGE("[自检] Failed to create byte array");
            return;
        }
        env->SetByteArrayRegion(jData, 0, length, reinterpret_cast<const jbyte*>(data));
        env->CallVoidMethod(g_p2pVideoView, g_onVideoFrameMethod, jData);
        if (env->ExceptionCheck()) {
            env->ExceptionDescribe();
            env->ExceptionClear();
            LOGE("[自检] Exception occurred during onVideoFrame call");
        }
        env->DeleteLocalRef(jData);
        g_frameCount++;
        if (isKeyFrame) {
            LOGI("[自检] Key frame processed, total frames: %d", g_frameCount.load());
        }
    } catch (const std::exception& e) {
        g_errorCount++;
        LOGE("[自检] Exception in video data callback: %s", e.what());
        notifyError(e.what());
    }

    g_vm->DetachCurrentThread();
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_music_1app_1framework_P2pVideoView_startP2pVideo(JNIEnv* env, jobject thiz) {
    LOGI("[自检] JNI startP2pVideo called");
    StartP2pVideo(RecbVideoData);
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
    
    // 释放解码器资源
    releaseCodec();
    
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
Java_com_example_music_1app_1framework_MainActivity_startP2pVideo(
        JNIEnv* env,
        jobject thiz,
        jstring devId) {
    const char* devIdStr = env->GetStringUTFChars(devId, nullptr);
    if (!devIdStr) {
        return;
    }

    if (!&RecbVideoData) {
        LOGE("RecbVideoData callback is not set");
        env->ReleaseStringUTFChars(devId, devIdStr);
        return;
    }

    try {
        g_frameCount.store(0);
        g_errorCount.store(0);
        
        StartP2pVideo(RecbVideoData);
        
    } catch (const std::exception& e) {
        notifyError(e.what());
    } catch (...) {
        notifyError("Unknown exception in startP2pVideo");
    }

    env->ReleaseStringUTFChars(devId, devIdStr);
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
Java_com_example_music_1app_1framework_P2pTestActivity_testStartP2pVideo(
        JNIEnv* env,
        jobject thiz) {
    if (!&RecbVideoData) {
        LOGE("RecbVideoData callback is not set");
        return JNI_FALSE;
    }

    try {
        StartP2pVideo(RecbVideoData);
        LOGI("[测试] StartP2pVideo调用完成");
        return JNI_TRUE;
    } catch (const std::exception& e) {
        LOGE("Error starting P2P video: %s", e.what());
        return JNI_FALSE;
    }
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_music_1app_1framework_P2pTestActivity_testStopP2pVideo(JNIEnv* env, jobject thiz) {
    LOGI("[测试] 调用StopP2pVideo");
    StopP2pVideo();
    return JNI_TRUE;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_example_music_1app_1framework_MainActivity_nativeInitMqtt(JNIEnv* env, jobject thiz, jstring phoneId) {
    const char* cPhoneId = env->GetStringUTFChars(phoneId, nullptr);
    LOGI("[JNI] nativeInitMqtt called: %s", cPhoneId);
    
    // 初始化 MQTT
    if (!g_mqttInitialized) {
        char* phoneIdCopy = strdup(cPhoneId);  // 创建可修改的副本
        InitMqtt(phoneIdCopy, RecbMsgData);
        free(phoneIdCopy);  // 释放副本
        g_mqttInitialized = true;
        LOGI("[JNI] MQTT initialized successfully");
    }
    
    env->ReleaseStringUTFChars(phoneId, cPhoneId);
    return g_mqttInitialized ? 0 : -1;
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_music_1app_1framework_MainActivity_nativeSetDevP2p(JNIEnv* env, jobject thiz, jstring devId) {
    const char* cDevId = env->GetStringUTFChars(devId, nullptr);
    LOGI("[JNI] nativeSetDevP2p called: %s", cDevId);
    env->ReleaseStringUTFChars(devId, cDevId);
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_music_1app_1framework_MainActivity_nativeStartP2pVideo(JNIEnv* env, jobject thiz, jstring devId) {
    if (!g_mqttInitialized) {
        LOGE("[JNI] MQTT not initialized, cannot start P2P video");
        return;
    }

    const char* cDevId = env->GetStringUTFChars(devId, nullptr);
    LOGI("[JNI] nativeStartP2pVideo called: %s", cDevId);
    
    // 设置设备 ID
    char* devIdCopy = strdup(cDevId);  // 创建可修改的副本
    SetDevP2p(devIdCopy);
    free(devIdCopy);  // 释放副本
    
    // 启动 P2P 视频
    StartP2pVideo(RecbVideoData);
    
    env->ReleaseStringUTFChars(devId, cDevId);
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_music_1app_1framework_MainActivity_nativeStopP2pVideo(JNIEnv* env, jobject thiz) {
    LOGI("[JNI] nativeStopP2pVideo called");
    StopP2pVideo();
}

extern "C" JNIEXPORT jint JNICALL
Java_com_example_music_1app_1framework_MainActivity_nativeGetP2pStatus(JNIEnv* env, jobject thiz) {
    LOGI("[JNI] nativeGetP2pStatus called");
    return g_mqttInitialized ? 1 : 0;
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_music_1app_1framework_MainActivityKt_startP2pVideo(JNIEnv* env, jobject thiz, jstring devId) {
    Java_com_example_music_1app_1framework_MainActivity_startP2pVideo(env, thiz, devId);
}

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void* reserved) {
    g_vm = vm;
    return JNI_VERSION_1_6;
}

JNIEXPORT void JNICALL JNI_OnUnload(JavaVM* vm, void* reserved) {
    g_vm = nullptr;
    if (g_p2pVideoView != nullptr) {
        JNIEnv* env = getJNIEnv();
        if (env) {
            env->DeleteGlobalRef(g_p2pVideoView);
        }
        g_p2pVideoView = nullptr;
    }
} 