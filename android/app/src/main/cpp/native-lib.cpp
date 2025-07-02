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
#include "cJSON.h"

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
static jobject g_mainActivityRef = nullptr;

// 空实现的消息回调
void RecbMsgData(void* pMsgData, int nLen) {
    LOGI("[MQTT] >>>>>>>>>>>> RecbMsgData called! length: %d", nLen);
    if (!g_vm || !g_mainActivityRef || !pMsgData || nLen <= 0) {
        LOGI("[MQTT] 回调参数无效，忽略");
        return;
    }
    JNIEnv* env;
    bool needDetach = false;
    if (g_vm->GetEnv((void**)&env, JNI_VERSION_1_6) != JNI_OK) {
        if (g_vm->AttachCurrentThread(&env, nullptr) != JNI_OK) {
            LOGI("[MQTT] Failed to attach thread");
            return;
        }
        needDetach = true;
    }
    jclass clazz = env->GetObjectClass(g_mainActivityRef);
    jmethodID onMqttMsg = env->GetMethodID(clazz, "onMqttMessage", "([BI)V");
    if (onMqttMsg) {
        jbyteArray jMsg = env->NewByteArray(nLen);
        env->SetByteArrayRegion(jMsg, 0, nLen, reinterpret_cast<const jbyte*>(pMsgData));
        env->CallVoidMethod(g_mainActivityRef, onMqttMsg, jMsg, nLen);
        env->DeleteLocalRef(jMsg);
        LOGI("[MQTT] 已回调 Java 层 onMqttMessage");
    } else {
        LOGI("[MQTT] 未找到 onMqttMessage 方法");
    }
    if (needDetach) {
        g_vm->DetachCurrentThread();
    }
}

// 独立的摄像头回调函数，避免与P2P回调冲突
void RecbCameraData(void* data, int length) {
    LOGI("[摄像头] >>>>>>>>>>>> RecbCameraData called! length: %d", length);
    
    if (g_isDisposed || !g_vm || !g_p2pVideoView) {
        LOGI("[摄像头] View is disposed or not available, ignoring camera data");
        return;
    }

    if (!data || length <= 0) {
        LOGI("[摄像头] Invalid camera data");
        return;
    }

    // 检查H.264格式特征
    const unsigned char* h264Data = reinterpret_cast<const unsigned char*>(data);
    bool hasNalStart = false;
    bool hasKeyFrame = false;
    
    // 检查NAL单元起始码 (0x00 0x00 0x01 或 0x00 0x00 0x00 0x01)
    for (int i = 0; i < length - 3; i++) {
        if (h264Data[i] == 0x00 && h264Data[i+1] == 0x00 && h264Data[i+2] == 0x01) {
            hasNalStart = true;
            unsigned char nalType = h264Data[i+3] & 0x1F;
            if (nalType == 5) { // IDR帧 (关键帧)
                hasKeyFrame = true;
                LOGI("[摄像头] 检测到H.264关键帧 (NAL type 5)");
            }
            break;
        }
    }
    
    if (hasNalStart) {
        LOGI("[摄像头] H.264格式验证通过: 检测到NAL起始码");
    } else {
        LOGI("[摄像头] H.264格式验证失败: 未检测到NAL起始码");
    }

    JNIEnv* env;
    bool needDetach = false;
    if (g_vm->GetEnv((void**)&env, JNI_VERSION_1_6) != JNI_OK) {
        if (g_vm->AttachCurrentThread(&env, nullptr) != JNI_OK) {
            LOGI("[摄像头] Failed to attach thread");
            return;
        }
        needDetach = true;
    }

    try {
        if (g_onVideoFrameMethod) {
            jbyteArray jData = env->NewByteArray(length);
            if (jData) {
                env->SetByteArrayRegion(jData, 0, length, reinterpret_cast<const jbyte*>(data));
                env->CallVoidMethod(g_p2pVideoView, g_onVideoFrameMethod, jData);
                env->DeleteLocalRef(jData);
                LOGI("[摄像头] Camera frame sent to Java layer successfully");
            }
        } else {
            LOGI("[摄像头] onVideoFrameMethod not available");
        }
    } catch (const std::exception& e) {
        LOGE("[摄像头] Error processing camera data: %s", e.what());
    }

    if (needDetach) {
        g_vm->DetachCurrentThread();
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_mainipc_xiebaoxin_MainActivity_bindNative(JNIEnv* env, jobject thiz) {
    if (g_mainActivityRef != nullptr) {
        env->DeleteGlobalRef(g_mainActivityRef);
    }
    g_mainActivityRef = env->NewGlobalRef(thiz);
    // 可选：env->GetJavaVM(&g_vm);
}

extern "C" JNIEXPORT void JNICALL
Java_com_xiebaoxin_MainActivity_P2pTestActivity_setDisplayMode(
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
Java_com_xiebaoxin_MainActivity_P2pTestActivity_setTextureId(
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
    bool needDetach = false;
    if (g_vm->GetEnv((void**)&env, JNI_VERSION_1_6) != JNI_OK) {
        if (g_vm->AttachCurrentThread(&env, nullptr) != JNI_OK) {
            return;
        }
        needDetach = true;
    }

        jstring jMessage = env->NewStringUTF(message);
        env->CallVoidMethod(g_p2pVideoView, g_onErrorMethod, jMessage);
        env->DeleteLocalRef(jMessage);

    if (needDetach) {
        g_vm->DetachCurrentThread();
    }
}

void RecbVideoData(void* data, int length) {
    LOGI("[自检] >>>>>>>>>>>> RecbVideoData called! length: %d", length);
    
    if (g_isDisposed || !g_vm || !g_p2pVideoView) {
        LOGI("[自检] View is disposed or not available, ignoring video data");
        return;
    }

    if (!data || length <= 0) {
        LOGI("[自检] Invalid video data");
        return;
    }

    // 检查H.264格式特征
    const unsigned char* h264Data = reinterpret_cast<const unsigned char*>(data);
    bool hasNalStart = false;
    bool hasKeyFrame = false;
    
    // 检查NAL单元起始码 (0x00 0x00 0x01 或 0x00 0x00 0x00 0x01)
    for (int i = 0; i < length - 3; i++) {
        if (h264Data[i] == 0x00 && h264Data[i+1] == 0x00 && h264Data[i+2] == 0x01) {
            hasNalStart = true;
            unsigned char nalType = h264Data[i+3] & 0x1F;
            if (nalType == 5) { // IDR帧 (关键帧)
                hasKeyFrame = true;
                LOGI("[自检] 检测到H.264关键帧 (NAL type 5)");
            }
            break;
        }
    }
    
    if (hasNalStart) {
        LOGI("[自检] H.264格式验证通过: 检测到NAL起始码");
    } else {
        LOGI("[自检] H.264格式验证失败: 未检测到NAL起始码");
    }

    JNIEnv* env;
    bool needDetach = false;
    if (g_vm->GetEnv((void**)&env, JNI_VERSION_1_6) != JNI_OK) {
    if (g_vm->AttachCurrentThread(&env, nullptr) != JNI_OK) {
            LOGI("[自检] Failed to attach thread");
        return;
        }
        needDetach = true;
    }

    try {
        if (g_isTextureMode) {
            if (g_onTextureFrameMethod && g_textureId.load() != 0) {
                jbyteArray jData = env->NewByteArray(length);
                if (jData) {
                    env->SetByteArrayRegion(jData, 0, length, reinterpret_cast<const jbyte*>(data));
                    env->CallVoidMethod(g_p2pVideoView, g_onTextureFrameMethod, 
                        g_textureId.load(), jData, length);
                    env->DeleteLocalRef(jData);
                    LOGI("[自检] Texture frame sent to Java layer successfully");
                }
            } else {
                LOGI("[自检] Texture mode but method not available or textureId is 0");
            }
        } else {
            if (g_onVideoFrameMethod) {
                jbyteArray jData = env->NewByteArray(length);
                if (jData) {
                    env->SetByteArrayRegion(jData, 0, length, reinterpret_cast<const jbyte*>(data));
                    env->CallVoidMethod(g_p2pVideoView, g_onVideoFrameMethod, jData);
                    env->DeleteLocalRef(jData);
                    LOGI("[自检] Video frame sent to Java layer successfully");
                }
            } else {
                LOGI("[自检] onVideoFrameMethod not available");
            }
        }
        g_frameCount++;
        LOGI("[自检] Frame count: %d", g_frameCount.load());
    } catch (const std::exception& e) {
        g_errorCount++;
        LOGE("[自检] Error processing video data: %s", e.what());
        notifyError(e.what());
    }

    if (needDetach) {
    g_vm->DetachCurrentThread();
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_xiebaoxin_MainActivity_P2pTestActivity_startP2pVideo(
        JNIEnv* env,
        jobject thiz) {
    if (g_isDisposed) {
        return;
    }

    try {
        g_frameCount.store(0);
        g_errorCount.store(0);
        
        if (!RecbVideoData) {
            notifyError("Video callback is null");
            return;
        }
        
        StartP2pVideo(RecbVideoData);
        
    } catch (const std::exception& e) {
        notifyError(e.what());
    } catch (...) {
        notifyError("Unknown exception in startP2pVideo");
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_xiebaoxin_MainActivity_P2pTestActivity_stopP2pVideo(
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
Java_com_xiebaoxin_MainActivity_P2pTestActivity_release(
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
Java_com_xiebaoxin_MainActivity_P2pTestActivity_initMqtt(JNIEnv* env, jobject thiz, jstring phoneId) {
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
Java_com_xiebaoxin_MainActivity_P2pTestActivity_setDevP2p(JNIEnv* env, jobject /* this */, jstring devId) {
    const char* pDevId = env->GetStringUTFChars(devId, nullptr);
    LOGI("[native] JNI setDevP2p called: %s", pDevId);
    SetDevP2p((char*)pDevId);
    env->ReleaseStringUTFChars(devId, pDevId);
    LOGI("[native] setDevP2p completed");
}

extern "C"
JNIEXPORT void JNICALL
Java_com_xiebaoxin_MainActivity_P2pTestActivity_setFlutterTextureId(JNIEnv* env, jobject thiz, jlong textureId) {
    g_flutterTextureId = textureId;
    __android_log_print(ANDROID_LOG_INFO, "NativeLib", "setFlutterTextureId called: %lld", (long long)textureId);
    // TODO: 这里可以根据 textureId 获取/绑定 Surface/SurfaceTexture
}

// 添加P2P连接状态检查函数
extern "C" JNIEXPORT jint JNICALL
Java_com_xiebaoxin_MainActivity_P2pTestActivity_getP2pStatus(JNIEnv* env, jobject thiz) {
    LOGI("[自检] Checking P2P connection status...");
    // 这里应该调用实际的P2P状态检查函数
    // 临时返回1表示已连接
    return 1;
}

// 添加测试函数
extern "C" JNIEXPORT jboolean JNICALL
Java_com_xiebaoxin_MainActivity_P2pTestActivity_testInitMqtt(JNIEnv* env, jobject thiz, jstring phoneId) {
    const char* pPhoneId = env->GetStringUTFChars(phoneId, nullptr);
    LOGI("[测试] 调用InitMqtt: %s", pPhoneId);
    
    InitMqtt((char*)pPhoneId, RecbMsgData);
    env->ReleaseStringUTFChars(phoneId, pPhoneId);
    
    return JNI_TRUE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_xiebaoxin_MainActivity_P2pTestActivity_testSetDevP2p(JNIEnv* env, jobject thiz, jstring devId) {
    const char* pDevId = env->GetStringUTFChars(devId, nullptr);
    LOGI("[测试] 调用SetDevP2p: %s", pDevId);
    
    SetDevP2p((char*)pDevId);
    env->ReleaseStringUTFChars(devId, pDevId);
    
    return JNI_TRUE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_xiebaoxin_MainActivity_P2pTestActivity_testStartP2pVideo(JNIEnv* env, jobject thiz) {
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
Java_com_xiebaoxin_MainActivity_P2pTestActivity_testStopP2pVideo(JNIEnv* env, jobject thiz) {
    LOGI("[测试] 调用StopP2pVideo");
    StopP2pVideo();
    return JNI_TRUE;
}

// P2pVideoView的JNI方法
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
    g_onTextureFrameMethod = env->GetMethodID(clazz, "onTextureFrame", "(JII)V");
    g_onErrorMethod = env->GetMethodID(clazz, "onError", "(Ljava/lang/String;)V");

    LOGI("P2pVideoView native bind successful");
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

extern "C" JNIEXPORT void JNICALL
Java_com_mainipc_xiebaoxin_P2pVideoView_startP2pVideo(
        JNIEnv* env,
        jobject thiz) {
    LOGI("[P2pVideoView] >>>>>>>>>>>> Enter P2pVideoView startP2pVideo");
    
    if (g_isDisposed) {
        LOGI("[P2pVideoView] View is disposed, ignoring startP2pVideo request");
        return;
    }

    // 检查回调函数指针
    if (!RecbVideoData) {
        LOGE("[P2pVideoView] RecbVideoData callback is null!");
        notifyError("Video callback is null");
        return;
    }
    
    LOGI("[P2pVideoView] About to call StartP2pVideo with callback: %p", (void*)RecbVideoData);
    
    // 检查so库函数指针
    if (!StartP2pVideo) {
        LOGE("[P2pVideoView] StartP2pVideo function pointer is null!");
        notifyError("StartP2pVideo function pointer is null");
        return;
    }
    
    LOGI("[P2pVideoView] StartP2pVideo function pointer: %p", (void*)StartP2pVideo);

    try {
        g_frameCount.store(0);
        g_errorCount.store(0);
        
        LOGI("[P2pVideoView] Calling StartP2pVideo...");
        
        // 在独立线程中调用，避免阻塞主线程
        std::thread([&]() {
            try {
                LOGI("[P2pVideoView] StartP2pVideo thread started");
                StartP2pVideo(RecbVideoData);
                LOGI("[P2pVideoView] StartP2pVideo called successfully, waiting for video data...");
                
                // 添加定时检查，看是否收到回调
                std::thread([&]() {
                    std::this_thread::sleep_for(std::chrono::seconds(5));
                    LOGI("[P2pVideoView] 5秒后检查：是否收到RecbVideoData回调？");
                    if (g_frameCount.load() == 0) {
                        LOGE("[P2pVideoView] 警告：5秒内没有收到任何视频帧！");
                        LOGE("[P2pVideoView] 可能原因：1.设备端没有响应 2.P2P连接失败 3.设备端没有发送视频流");
                        
                        // 尝试检查P2P连接状态
                        LOGI("[P2pVideoView] 尝试检查P2P连接状态...");
                        try {
                            // 这里可以调用so库的P2P状态检查函数
                            // 如果有的话，可以检查连接状态
                            LOGI("[P2pVideoView] P2P状态检查完成");
                        } catch (...) {
                            LOGI("[P2pVideoView] P2P状态检查失败");
                        }
                    } else {
                        LOGI("[P2pVideoView] 收到视频帧数量: %d", g_frameCount.load());
                    }
                }).detach();
                
            } catch (const std::exception& e) {
                LOGE("[P2pVideoView] Exception in StartP2pVideo thread: %s", e.what());
                notifyError(e.what());
            } catch (...) {
                LOGE("[P2pVideoView] Unknown exception in StartP2pVideo thread");
                notifyError("Unknown exception in StartP2pVideo thread");
            }
        }).detach();
        
        LOGI("[P2pVideoView] StartP2pVideo thread launched");
        
    } catch (const std::exception& e) {
        LOGE("[P2pVideoView] Exception in startP2pVideo: %s", e.what());
        notifyError(e.what());
    } catch (...) {
        LOGE("[P2pVideoView] Unknown exception in startP2pVideo");
        notifyError("Unknown exception in startP2pVideo");
    }
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
Java_com_mainipc_xiebaoxin_P2pVideoView_release(
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
    
    LOGI("P2pVideoView native resources released");
}

// MainActivity的JNI方法
extern "C" JNIEXPORT void JNICALL
Java_com_mainipc_xiebaoxin_MainActivity_initMqtt(
        JNIEnv* env,
        jobject thiz,
        jstring phoneId) {
    if (!phoneId) {
        LOGE("initMqtt: phoneId is null");
        return;
    }
    
    const char* phoneIdStr = env->GetStringUTFChars(phoneId, nullptr);
    if (!phoneIdStr) {
        LOGE("initMqtt: Failed to get phoneId string");
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
Java_com_mainipc_xiebaoxin_MainActivity_setDevP2p(
        JNIEnv* env,
        jobject thiz,
        jstring devId) {
    const char* pDevId = env->GetStringUTFChars(devId, nullptr);
    LOGI("[native] JNI setDevP2p called: %s", pDevId);
    SetDevP2p((char*)pDevId);
    env->ReleaseStringUTFChars(devId, pDevId);
    LOGI("[native] setDevP2p completed");
}

extern "C" JNIEXPORT void JNICALL
Java_com_mainipc_xiebaoxin_MainActivity_startP2pVideo(
        JNIEnv* env,
        jobject thiz) {
    LOGI("[自检] >>>>>>>>>>>> Enter startP2pVideo");
    
    // 检查回调函数指针
    if (!RecbVideoData) {
        LOGE("[自检] RecbVideoData callback is null!");
        return;
    }
    
    LOGI("[自检] About to call StartP2pVideo with callback: %p", (void*)RecbVideoData);
    
    // 添加信号处理
    signal(SIGSEGV, [](int sig) {
        LOGE("[自检] SIGSEGV caught in StartP2pVideo");
    });
    
    signal(SIGABRT, [](int sig) {
        LOGE("[自检] SIGABRT caught in StartP2pVideo");
    });
    
    // 检查so库函数指针
    if (!StartP2pVideo) {
        LOGE("[自检] StartP2pVideo function pointer is null!");
        return;
    }
    
    LOGI("[自检] StartP2pVideo function pointer: %p", (void*)StartP2pVideo);
    
    // 检查P2P连接状态
    LOGI("[自检] Checking P2P connection status before starting video...");
    
    try {
        LOGI("[自检] Calling StartP2pVideo...");
        
        // 在独立线程中调用，避免阻塞主线程
        std::thread([&]() {
            try {
                LOGI("[自检] StartP2pVideo thread started");
                StartP2pVideo(RecbVideoData);
                LOGI("[自检] StartP2pVideo called successfully, waiting for video data...");
                
                // 添加定时检查，看是否收到回调
                std::thread([&]() {
                    std::this_thread::sleep_for(std::chrono::seconds(5));
                    LOGI("[自检] 5秒后检查：是否收到RecbVideoData回调？");
                    if (g_frameCount.load() == 0) {
                        LOGE("[自检] 警告：5秒内没有收到任何视频帧！");
                        LOGE("[自检] 可能原因：1.设备端没有响应 2.P2P连接失败 3.设备端没有发送视频流");
                    } else {
                        LOGI("[自检] 收到视频帧数量: %d", g_frameCount.load());
                    }
                }).detach();
                
            } catch (const std::exception& e) {
                LOGE("[自检] Exception in StartP2pVideo thread: %s", e.what());
            } catch (...) {
                LOGE("[自检] Unknown exception in StartP2pVideo thread");
            }
        }).detach();
        
        LOGI("[自检] StartP2pVideo thread launched");
        
    } catch (const std::exception& e) {
        LOGE("[自检] Exception in startP2pVideo: %s", e.what());
    } catch (...) {
        LOGE("[自检] Unknown exception in startP2pVideo");
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_mainipc_xiebaoxin_MainActivity_stopP2pVideo(
        JNIEnv* env,
        jobject thiz) {
    LOGI("[native] JNI stopP2pVideo called");
    StopP2pVideo();
    LOGI("[native] StopP2pVideo called");
}

extern "C" JNIEXPORT void JNICALL
Java_com_mainipc_xiebaoxin_MainActivity_deinitMqtt(
        JNIEnv* env,
        jobject thiz) {
    LOGI("[native] JNI deinitMqtt called");
    DeinitMqtt();
    LOGI("[native] DeinitMqtt called");
}

extern "C" JNIEXPORT void JNICALL
Java_com_mainipc_xiebaoxin_MainActivity_nativeRecbVideoData(
        JNIEnv* env,
        jobject thiz,
        jbyteArray data,
        jint len) {
    LOGI("[摄像头] >>>>>>>>>>>> nativeRecbVideoData called! length: %d", len);
    
    if (!data || len <= 0) {
        LOGI("[摄像头] Invalid data received");
        return;
    }

    jbyte* dataPtr = env->GetByteArrayElements(data, nullptr);
    if (dataPtr) {
        // 使用独立的摄像头回调函数，避免与P2P回调冲突
        RecbCameraData(dataPtr, len);
        env->ReleaseByteArrayElements(data, dataPtr, JNI_ABORT);
        LOGI("[摄像头] Camera data processed successfully");
    } else {
        LOGI("[摄像头] Failed to get byte array elements");
    }
}

extern "C"
JNIEXPORT jint JNICALL
Java_com_mainipc_xiebaoxin_MainActivity_sendJsonMsg(JNIEnv *env, jobject thiz, jstring json, jstring topic) {
    const char *jsonStr = env->GetStringUTFChars(json, nullptr);
    const char *topicStr = env->GetStringUTFChars(topic, nullptr);

    cJSON *jsonObj = cJSON_Parse(jsonStr);
    int ret = -1;
    if (jsonObj) {
        ret = SendJsonMsg(jsonObj, (char*)topicStr);
        cJSON_Delete(jsonObj);
    }

    env->ReleaseStringUTFChars(json, jsonStr);
    env->ReleaseStringUTFChars(topic, topicStr);
    return ret;
} 