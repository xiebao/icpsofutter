import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:developer';
import '../providers/message_monitor.dart';
import '../providers/device_event_notifier.dart';

class MqttService {
  static const MethodChannel _channel = MethodChannel('p2p_video_channel');
  static MethodChannel get channel => _channel;
  static MqttService? _instance;
  static bool _isInitialized = false;
  static String? _currentUserId;
  static bool _isAppActive = true;
  static const MethodChannel videoFrameChannel =
      MethodChannel('video_frame_channel');
  static MethodChannel get videoChannel => videoFrameChannel;

  // 单例模式
  factory MqttService() {
    _instance ??= MqttService._internal();
    return _instance!;
  }

  MqttService._internal();

  // 获取实例
  static MqttService get instance => MqttService();

  // 初始化 MQTT 服务
  Future<void> init() async {
    log('[MQTT Service] 初始化 MQTT 服务');
    _setupMethodChannel();
  }

  // 设置方法通道
  void _setupMethodChannel() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onMqttMessage':
          print(
              '[DEBUG][MQTT Service] onMqttMessage call.arguments: \\${call.arguments}');
          String msg = '';
          if (call.arguments is Map && call.arguments['data'] != null) {
            msg = call.arguments['data'].toString();
          } else {
            msg = call.arguments?.toString() ?? '';
          }
          print('[DEBUG][MQTT Service] parsed msg: \\${msg}');
          messageMonitor.addMqttMessage(msg);
          final messageData = msg;
          final length =
              call.arguments is Map && call.arguments['length'] != null
                  ? call.arguments['length'] as int
                  : msg.length;
          print("[MQTT Service]<<<==" + messageData);
          log('[MQTT Service] 收到 MQTT 消息: $messageData (长度: $length)');
          // 新增：收到MQTT消息时，推送设备事件（默认devId='camId123'）
          deviceEventNotifier.addEvent(DeviceEvent(
            DeviceEventType.online,
            'camId123',
            messageData,
          ));
          // 这里可以添加全局的消息处理逻辑，比如显示通知等

          // if(call.arguments['data']['online']==1)
          //   DeviceEventType.
          break;
      }
    });
  }

  // 启动 MQTT 连接
  Future<bool> startMqtt(String userId) async {
    log('[MQTT Service] startMqtt called for user: $userId');
    if (_isInitialized && _currentUserId == userId) {
      log('[MQTT Service] MQTT 已经为用户 $userId 初始化，跳过重复初始化');
      return true;
    }

    try {
      log('[MQTT Service] 开始为用户 $userId 初始化 MQTT 连接...');
      await _channel.invokeMethod('initMqtt', {'phoneId': userId});
      _isInitialized = true;
      _currentUserId = userId;
      log('[MQTT Service] ✅ MQTT 连接初始化成功，用户: $userId');
      return true;
    } catch (e) {
      log('[MQTT Service] ❌ MQTT 连接初始化失败: $e');
      return false;
    }
  }

  // 停止 MQTT 连接
  Future<void> stopMqtt() async {
    log('[MQTT Service] stopMqtt called');
    if (!_isInitialized) {
      log('[MQTT Service] MQTT 未初始化，跳过停止操作');
      return;
    }

    try {
      log('[MQTT Service] 开始停止 MQTT 连接...');
      await _channel.invokeMethod('deinitMqtt');
      _isInitialized = false;
      _currentUserId = null;
      log('[MQTT Service] ✅ MQTT 连接已停止');
    } catch (e) {
      log('[MQTT Service] ❌ 停止 MQTT 连接失败: $e');
    }
  }

  // 应用进入前台
  Future<void> onAppResumed(String userId) async {
    log('[MQTT Service] onAppResumed called, user: $userId');
    _isAppActive = true;

    if (!_isInitialized || _currentUserId != userId) {
      await startMqtt(userId);
    } else {
      log('[MQTT Service] MQTT 连接已存在，无需重新初始化');
    }
  }

  // 应用进入后台
  Future<void> onAppPaused() async {
    log('[MQTT Service] onAppPaused called');
    _isAppActive = false;

    // 可以选择是否在后台停止 MQTT
    // 如果需要在后台保持连接，可以注释掉下面的代码
    await stopMqtt();
  }

  // 应用被销毁
  Future<void> onAppDestroyed() async {
    log('[MQTT Service] onAppDestroyed called');
    await stopMqtt();
  }

  // 检查 MQTT 状态
  bool get isInitialized => _isInitialized;
  String? get currentUserId => _currentUserId;
  bool get isAppActive => _isAppActive;

  // 新增：通过 so 库发送 json 消息到指定 topic
  Future<int> sendJsonMsg(String json, String topic) async {
    try {
      final ret = await _channel
          .invokeMethod('sendJsonMsg', {'json': json, 'topic': topic});
      messageMonitor.addSendMessage('topic: $topic, json: $json');
      print("[MQTT Service]==>>" + topic + ",json:" + json.toString());
      log('[MQTT Service] sendJsonMsg 返回: $ret');
      return ret as int;
    } catch (e) {
      log('[MQTT Service] sendJsonMsg 调用失败: $e');
      return -1;
    }
  }

  // 测试方法：发送一条测试消息
  //await MqttService.instance.sendJsonMsg('{"type":"test","data":"hello"}', '/yyt/test/topic');
  Future<void> testSendJsonMsg() async {
    final testJson = '{"type":"test","data":"hello from Dart"}';
    final testTopic = '/yyt/phoneId123/msg';
    final ret = await sendJsonMsg(testJson, testTopic);
    log('[MQTT Service] testSendJsonMsg 返回: $ret');
  }
}
