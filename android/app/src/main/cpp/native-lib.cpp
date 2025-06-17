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

// Forward declarations
static void notifyError(const char* message);

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

static char* g_phoneId = nullptr;
static char* g_devId = nullptr;

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
    // 使用 Surface 颜色格式
    AMediaFormat_setInt32(format, AMEDIAFORMAT_KEY_COLOR_FORMAT, 0x7F000789);
    AMediaFormat_setInt32(format, AMEDIAFORMAT_KEY_BIT_RATE, 2000000);
    AMediaFormat_setInt32(format, AMEDIAFORMAT_KEY_FRAME_RATE, 30);
    AMediaFormat_setInt32(format, AMEDIAFORMAT_KEY_I_FRAME_INTERVAL, 1);
    // 添加 H264 特定配置
    uint8_t csd0[] = { 0x00, 0x00, 0x00, 0x01, 0x67, 0x42, 0x00, 0x0a, 0x96, 0x54, 0x0b, 0x6c, 0x8c, 0x8c };
    uint8_t csd1[] = { 0x00, 0x00, 0x00, 0x01, 0x68, 0xce, 0x38, 0x80 };
    AMediaFormat_setBuffer(format, "csd-0", csd0, sizeof(csd0));
    AMediaFormat_setBuffer(format, "csd-1", csd1, sizeof(csd1));

    // 配置解码器
    media_status_t status = AMediaCodec_configure(g_mediaCodec, format, g_nativeWindow, nullptr, 0);
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
Java_com_mainipc_xiebaoxin_P2pVideoView_bindNative(
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
    if (g_onVideoFrameMethod == nullptr) {
        LOGE("Failed to get onVideoFrame method");
        notifyError("Failed to get onVideoFrame method");
        return;
    }

    g_onTextureFrameMethod = env->GetMethodID(clazz, "onTextureFrame", "(JII)V");
    if (g_onTextureFrameMethod == nullptr) {
        LOGE("Failed to get onTextureFrame method");
        notifyError("Failed to get onTextureFrame method");
        return;
    }

    g_onErrorMethod = env->GetMethodID(clazz, "onError", "(Ljava/lang/String;)V");
    if (g_onErrorMethod == nullptr) {
        LOGE("Failed to get onError method");
        return;
    }

    LOGI("Native bind successful");
}

extern "C" JNIEXPORT void JNICALL
Java_com_mainipc_xiebaoxin_P2pVideoView_setDisplayMode(
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
Java_com_mainipc_xiebaoxin_P2pVideoView_setTextureId(
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

// 处理 H264 帧数据
void RecbVideoData(void* data, int length) {
    if (g_isDisposed || !g_vm || !g_p2pVideoView || !g_onVideoFrameMethod) {
        return;
    }

    JNIEnv* env;
    if (g_vm->AttachCurrentThread(&env, nullptr) != JNI_OK) {
        return;
    }

    // 检查是否是 H264 NAL 单元
    uint8_t* h264Data = static_cast<uint8_t*>(data);
    if (length < 4) {
        return;
    }

    // 查找 NAL 起始码
    int startCode = (h264Data[0] << 24) | (h264Data[1] << 16) | (h264Data[2] << 8) | h264Data[3];
    if (startCode != 0x00000001 && (startCode >> 8) != 0x000001) {
        // 添加起始码
        jbyteArray frameData = env->NewByteArray(length + 4);
        uint8_t startCode[] = {0x00, 0x00, 0x00, 0x01};
        env->SetByteArrayRegion(frameData, 0, 4, reinterpret_cast<jbyte*>(startCode));
        env->SetByteArrayRegion(frameData, 4, length, reinterpret_cast<jbyte*>(data));
        env->CallVoidMethod(g_p2pVideoView, g_onVideoFrameMethod, frameData);
        env->DeleteLocalRef(frameData);
    } else {
        // 直接发送帧数据
        jbyteArray frameData = env->NewByteArray(length);
        env->SetByteArrayRegion(frameData, 0, length, reinterpret_cast<jbyte*>(data));
        env->CallVoidMethod(g_p2pVideoView, g_onVideoFrameMethod, frameData);
        env->DeleteLocalRef(frameData);
    }

    g_frameCount++;
    g_vm->DetachCurrentThread();
}

extern "C" JNIEXPORT void JNICALL
Java_com_mainipc_xiebaoxin_P2pVideoView_startP2pVideo(JNIEnv* env, jobject thiz) {
    if (g_isDisposed || !g_vm || !g_p2pVideoView) {
        LOGE("[自检] startP2pVideo: Invalid state - disposed: %d, vm: %p, view: %p",
             g_isDisposed.load(), g_vm, g_p2pVideoView);
        return;
    }
    LOGI("[自检] JNI startP2pVideo called");
    StartP2pVideo(RecbVideoData);
}

extern "C" JNIEXPORT void JNICALL
Java_com_mainipc_xiebaoxin_P2pVideoView_stopP2pVideo(
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
            auto start = std::chrono::steady_clock::now();
            StopP2pVideo();
            auto end = std::chrono::steady_clock::now();
            auto duration = std::chrono::duration_cast<std::chrono::seconds>(end - start).count();
            if (duration > 5) {
                LOGE("StopP2pVideo took too long: %lld seconds", (long long)duration);
                notifyError("StopP2pVideo timeout");
            } else {
                LOGI("P2P video stopped successfully");
            }
        } catch (const std::exception& e) {
            LOGE("Error stopping P2P video: %s", e.what());
            notifyError(e.what());
        }
        g_isStopping.store(false);
    }).detach();
}

extern "C" JNIEXPORT void JNICALL
Java_com_mainipc_xiebaoxin_P2pVideoView_release(
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
Java_com_mainipc_xiebaoxin_MainActivity_initMqtt(JNIEnv* env, jobject thiz, jstring phoneId) {
    const char* cPhoneId = env->GetStringUTFChars(phoneId, nullptr);
    LOGI("[JNI] initMqtt called: %s", cPhoneId);
    
    if (!g_mqttInitialized) {
        if (g_phoneId) {
            free(g_phoneId);
        }
        g_phoneId = strdup(cPhoneId);
        InitMqtt(g_phoneId, RecbMsgData);
        g_mqttInitialized = true;
        LOGI("[JNI] MQTT initialized successfully");
    }
    
    env->ReleaseStringUTFChars(phoneId, cPhoneId);
}

extern "C" JNIEXPORT void JNICALL
Java_com_mainipc_xiebaoxin_MainActivity_setDevP2p(JNIEnv* env, jobject thiz, jstring devId) {
    const char* cDevId = env->GetStringUTFChars(devId, nullptr);
    LOGI("[JNI] setDevP2p called: %s", cDevId);
    
    if (g_devId) {
        free(g_devId);
    }
    g_devId = strdup(cDevId);
    SetDevP2p(g_devId);
    
    env->ReleaseStringUTFChars(devId, cDevId);
}

extern "C" JNIEXPORT void JNICALL
Java_com_mainipc_xiebaoxin_MainActivity_startP2pVideo(JNIEnv* env, jobject thiz, jstring devId) {
    if (!g_mqttInitialized) {
        LOGE("[JNI] MQTT not initialized, cannot start P2P video");
        return;
    }

    const char* cDevId = env->GetStringUTFChars(devId, nullptr);
    LOGI("[JNI] startP2pVideo called: %s", cDevId);
    
    if (g_devId) {
        free(g_devId);
    }
    g_devId = strdup(cDevId);
    SetDevP2p(g_devId);
    
    StartP2pVideo(RecbVideoData);
    
    env->ReleaseStringUTFChars(devId, cDevId);
}

extern "C" JNIEXPORT void JNICALL
Java_com_mainipc_xiebaoxin_MainActivity_stopP2pVideo(JNIEnv* env, jobject thiz) {
    LOGI("[JNI] stopP2pVideo called");
    StopP2pVideo();
}

extern "C"
JNIEXPORT void JNICALL
Java_com_mainipc_xiebaoxin_MainActivity_setFlutterTextureId(JNIEnv* env, jobject thiz, jlong textureId) {
    g_flutterTextureId = textureId;
    __android_log_print(ANDROID_LOG_INFO, "NativeLib", "setFlutterTextureId called: %lld", (long long)textureId);
    // TODO: 这里可以根据 textureId 获取/绑定 Surface/SurfaceTexture
}

// 添加P2P连接状态检查函数
extern "C" JNIEXPORT jint JNICALL
Java_com_mainipc_xiebaoxin_MainActivity_getP2pStatus(JNIEnv* env, jobject thiz) {
    LOGI("[自检] Checking P2P connection status...");
    // 这里应该调用实际的P2P状态检查函数
    // 临时返回1表示已连接
    return 1;
}

// 添加测试函数
extern "C" JNIEXPORT jboolean JNICALL
Java_com_mainipc_xiebaoxin_P2pTestActivity_testInitMqtt(JNIEnv* env, jobject thiz, jstring phoneId) {
    const char* pPhoneId = env->GetStringUTFChars(phoneId, nullptr);
    LOGI("[测试] 调用InitMqtt: %s", pPhoneId);
    
    InitMqtt((char*)pPhoneId, RecbMsgData);
    env->ReleaseStringUTFChars(phoneId, pPhoneId);
    
    return JNI_TRUE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_mainipc_xiebaoxin_P2pTestActivity_testSetDevP2p(JNIEnv* env, jobject thiz, jstring devId) {
    const char* pDevId = env->GetStringUTFChars(devId, nullptr);
    LOGI("[测试] 调用SetDevP2p: %s", pDevId);
    
    SetDevP2p((char*)pDevId);
    env->ReleaseStringUTFChars(devId, pDevId);
    
    return JNI_TRUE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_mainipc_xiebaoxin_P2pTestActivity_testStartP2pVideo(
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
Java_com_mainipc_xiebaoxin_P2pTestActivity_testStopP2pVideo(JNIEnv* env, jobject thiz) {
    LOGI("[测试] 调用StopP2pVideo");
    StopP2pVideo();
    return JNI_TRUE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_mainipc_xiebaoxin_MainActivity_deinitMqtt(JNIEnv* env, jobject thiz) {
    LOGI("[JNI] deinitMqtt called");
    StopP2pVideo();   // 必须先停视频
    DeinitMqtt();     // 再断MQTT
    g_mqttInitialized = false;

    // 清理字符串
    if (g_phoneId) {
        free(g_phoneId);
        g_phoneId = nullptr;
    }
    if (g_devId) {
        free(g_devId);
        g_devId = nullptr;
    }

    LOGI("[JNI] MQTT deinitialized");
}

extern "C" JNIEXPORT void JNICALL
Java_com_mainipc_xiebaoxin_MainActivity_nativeRecbVideoData(
        JNIEnv *env,
        jobject /* this */,
        jbyteArray data,
        jint length) {
    if (!g_p2pVideoView) {
        LOGE("[自检] RecbVideoData: Invalid state - disposed: %d, vm: %p, view: %p",
             g_isDisposed.load(), g_vm, g_p2pVideoView);
        return;
    }

    uint8_t *buffer = new uint8_t[length];
    env->GetByteArrayRegion(data, 0, length, reinterpret_cast<jbyte *>(buffer));

    LOGI("[自检] RecbVideoData called! length: %d", length);
    if (length > 16) {
        LOGI("[自检] NAL type: %d, isKeyFrame: %d, first bytes: %02X %02X %02X %02X %02X",
             buffer[4] & 0x1F, (buffer[4] & 0x1F) == 7,
             buffer[0], buffer[1], buffer[2], buffer[3], buffer[4]);
    }

    // 获取Java类和方法ID
    jclass viewClass = env->GetObjectClass(g_p2pVideoView);
    jmethodID onVideoFrameMethod = env->GetMethodID(viewClass, "onVideoFrame", "([B)V");
    if (!onVideoFrameMethod) {
        LOGE("[自检] Failed to get onVideoFrame method");
        delete[] buffer;
        env->DeleteLocalRef(viewClass);
        return;
    }

    // 创建Java字节数组
    jbyteArray frameData = env->NewByteArray(length);
    env->SetByteArrayRegion(frameData, 0, length, reinterpret_cast<jbyte *>(buffer));

    // 调用Java方法
    LOGI("[自检] 调用onVideoFrame方法");
    env->CallVoidMethod(g_p2pVideoView, onVideoFrameMethod, frameData);

    // 清理资源
    delete[] buffer;
    env->DeleteLocalRef(frameData);
    env->DeleteLocalRef(viewClass);
}

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void* reserved) {
    g_vm = vm;
    return JNI_VERSION_1_6;
}

JNIEXPORT void JNICALL JNI_OnUnload(JavaVM* vm, void* reserved) {
    g_vm = nullptr;
    if (g_p2pVideoView != nullptr) {
        JNIEnv* env = nullptr;
        if (vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) == JNI_OK) {
            env->DeleteGlobalRef(g_p2pVideoView);
        }
        g_p2pVideoView = nullptr;
    }
    
    // 清理字符串
    if (g_phoneId) {
        free(g_phoneId);
        g_phoneId = nullptr;
    }
    if (g_devId) {
        free(g_devId);
        g_devId = nullptr;
    }
} 