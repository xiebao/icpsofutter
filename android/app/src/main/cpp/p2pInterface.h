#ifndef P2PINTERFACE_H
#define P2PINTERFACE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef  void (*pFunRecvCB)(void* ,int );

//手机的id，需要唯一，用于标识手机
//pRecvMsgCB 回调函数，用于接收消息数据,设备或平台发过来的消息，都是json格式的数据
//功能：初始化mqtt，连接mqtt服务器，订阅消息主题，设置接收消息的回调函数
void InitMqtt( char* pPhoneId , pFunRecvCB pRecvMsgCB);

//设置P2P时设备ID号，只有设置后才可以进行P2P
void SetDevP2p( char* pDevId);

//pJsonMsg，消息数据，json格式的数据，不是字符串
// 如：
// {
//     "type":"login",
//     "data":"..."
// }
//mqtt主题，设备的id号，如：/yyt/pDevId/msg
//功能：给设备发送消息,消息格式为json格式
int SendJsonMsg(void* pJsonMsg,char* pPubtopic);


void DeinitMqtt();
//
//pRecvVideoCB 回调函数，用于接收视频数据

//功能：启动p2p视频
void StartP2pVideo(pFunRecvCB pRecvVideoCB);
//功能：停止p2p视频
void StopP2pVideo();

////  p2pInterface.h
#ifdef __cplusplus
}
#endif

#endif // P2PINTERFACE_H