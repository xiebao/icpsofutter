#include <android/log.h>
#include "p2pInterface.h"

#undef DEBUG_PRINT
#define LOG_TAG "P2P_SO"
#define DEBUG_PRINT(fmt, ...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, fmt, ##__VA_ARGS__)

#ifdef __cplusplus
extern "C" {
#endif

void InitMqtt(char* pPhoneId, pFunRecvCB pRecvMsgCB) {
    DEBUG_PRINT("[MQTT] InitMqtt called with phoneId: %s, pRecvMsgCB: %p", pPhoneId, pRecvMsgCB);
}

void SetDevP2p(char* pDevId) {
    DEBUG_PRINT("[P2P] SetDevP2p called with devId: %s", pDevId);
}

int SendJsonMsg(void* pJsonMsg, char* pPubtopic) {
    DEBUG_PRINT("SendJsonMsg called with topic: %s", pPubtopic);
    return 0;
}

void DeinitMqtt() {
    DEBUG_PRINT("DeinitMqtt called");
}

void StartP2pVideo(pFunRecvCB pRecvVideoCB) {
    DEBUG_PRINT("[P2P] StartP2pVideo called, pRecvVideoCB: %p", pRecvVideoCB);
}

void StopP2pVideo() {
    DEBUG_PRINT("StopP2pVideo called");
}

#ifdef __cplusplus
}
#endif 