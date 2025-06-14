#include <jni.h>
#include <string>
#include "p2pInterface.h"
#include <android/log.h>
#include <fstream>
#include <errno.h>

#define LOG_TAG "JNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)

static JavaVM* g_vm = nullptr;
static jobject g_videoView = nullptr;

// 绑定 P2pVideoView 实例
extern "C" JNIEXPORT void JNICALL
Java_com_example_music_1app_1framework_P2pVideoView_bindNative(JNIEnv* env, jobject thiz) {
    env->GetJavaVM(&g_vm);
    if (g_videoView) env->DeleteGlobalRef(g_videoView);
    g_videoView = env->NewGlobalRef(thiz);
}

// 回调视频帧到 P2pVideoView
void RecbVideoData(void *pVideoData, int nLen) {
    LOGI("[native] Enter RecbVideoData, nLen=%d", nLen);
    static bool firstFrameSaved = false;
    if (!firstFrameSaved && nLen > 0) {
        FILE* fp = fopen("/data/data/com.example.music_app_framework/files/first_frame.h264", "wb");
        if (fp) {
            fwrite(pVideoData, 1, nLen, fp);
            fclose(fp);
            LOGI("[native] First frame saved to /data/data/com.example.music_app_framework/files/first_frame.h264, nLen=%d", nLen);
        } else {
            LOGI("[native] Failed to open /data/data/com.example.music_app_framework/files/first_frame.h264 for writing, errno=%d", errno);
        }
        firstFrameSaved = true;
    }
    // 追加写入 live.h264 供 ExoPlayer 播放
    FILE* fpLive = fopen("/data/data/com.example.music_app_framework/files/live.h264", "ab");
    if (fpLive) {
        fwrite(pVideoData, 1, nLen, fpLive);
        fclose(fpLive);
        LOGI("[native] Appended %d bytes to /data/data/com.example.music_app_framework/files/live.h264", nLen);
    } else {
        LOGI("[native] Failed to open /data/data/com.example.music_app_framework/files/live.h264 for writing, errno=%d", errno);
    }
    if (g_vm && g_videoView) {
        JNIEnv* env = nullptr;
        g_vm->AttachCurrentThread(&env, nullptr);
        jclass clazz = env->GetObjectClass(g_videoView);
        jmethodID onFrame = env->GetMethodID(clazz, "onVideoFrame", "([B)V");
        jbyteArray arr = env->NewByteArray(nLen);
        env->SetByteArrayRegion(arr, 0, nLen, (jbyte*)pVideoData);
        env->CallVoidMethod(g_videoView, onFrame, arr);
        env->DeleteLocalRef(arr);
        LOGI("[native] Called onVideoFrame in Java, nLen=%d", nLen);
    } else {
        LOGI("[native] g_vm or g_videoView is null, skip onVideoFrame");
    }
}

// 增加消息回调
void RecbMsgData(void *pMsgData, int nLen) {
    // 可根据需要处理消息，这里空实现防止崩溃
}

static bool g_mqttInited = false;

extern "C" JNIEXPORT void JNICALL
Java_com_example_music_1app_1framework_MainActivity_initMqtt(JNIEnv* env, jobject /* this */, jstring phoneId) {
    if (g_mqttInited) { LOGI("[native] initMqtt already inited"); return; }
    const char* c_phoneId = env->GetStringUTFChars(phoneId, nullptr);
    LOGI("[native] JNI initMqtt called: %s", c_phoneId);
    InitMqtt((char*)c_phoneId, RecbMsgData);
    g_mqttInited = true;
    env->ReleaseStringUTFChars(phoneId, c_phoneId);
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_music_1app_1framework_MainActivity_setDevP2p(JNIEnv* env, jobject /* this */, jstring devId) {
    const char* c_devId = env->GetStringUTFChars(devId, nullptr);
    LOGI("[native] JNI setDevP2p called: %s", c_devId);
    SetDevP2p((char*)c_devId);
    env->ReleaseStringUTFChars(devId, c_devId);
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_music_1app_1framework_MainActivity_startP2pVideo(JNIEnv* env, jobject thiz, jstring devId) {
    LOGI("[native] Enter startP2pVideo");
    Java_com_example_music_1app_1framework_MainActivity_setDevP2p(env, thiz, devId);
    LOGI("[native] JNI startP2pVideo called, will call StartP2pVideo");
    StartP2pVideo(RecbVideoData);
    LOGI("[native] StartP2pVideo called");
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_music_1app_1framework_MainActivity_stopP2pVideo(JNIEnv* env, jobject /* this */) {
    LOGI("[native] JNI stopP2pVideo called");
    StopP2pVideo();
    LOGI("[native] StopP2pVideo called");
} 