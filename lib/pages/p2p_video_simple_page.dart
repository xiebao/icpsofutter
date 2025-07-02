import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:developer';
import '../services/mqtt_service.dart';

class P2pVideoSimplePage extends StatefulWidget {
  final String devId;
  final String deviceName;

  const P2pVideoSimplePage({
    Key? key,
    required this.devId,
    required this.deviceName,
  }) : super(key: key);

  @override
  State<P2pVideoSimplePage> createState() => _P2pVideoSimplePageState();
}

class _P2pVideoSimplePageState extends State<P2pVideoSimplePage> {
  static const MethodChannel _channel = MethodChannel('p2p_video_channel');
  final MqttService _mqttService = MqttService.instance;

  String _status = '初始化中...';
  String _mqttStatus = '未检查';
  String _lastMessage = '无消息';
  bool _isConnected = false;
  bool _videoStarted = false;
  int _frameCount = 0;

  @override
  void initState() {
    super.initState();
    _setupMethodChannel();
    _checkMqttStatus();
  }

  void _setupMethodChannel() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onMqttMessage':
          final messageData = call.arguments['data'] as String;
          final length = call.arguments['length'] as int;
          log('[P2P Simple] 收到 MQTT 消息: $messageData (长度: $length)');
          setState(() {
            _lastMessage = '收到消息: $messageData (长度: $length)';
          });
          break;
        case 'onVideoFrame':
          final Uint8List h264Frame = call.arguments;
          setState(() {
            _frameCount++;
            _status = '✅ 收到真实H264视频帧 #$_frameCount (${h264Frame.length} bytes)';
          });
          log('[P2P Simple] 收到真实H264视频帧 #$_frameCount: ${h264Frame.length} bytes');
          break;
      }
    });
  }

  Future<void> _checkMqttStatus() async {
    setState(() {
      _mqttStatus = '检查中...';
    });

    final isInitialized = _mqttService.isInitialized;
    final currentUserId = _mqttService.currentUserId;

    setState(() {
      _mqttStatus = 'MQTT: ${isInitialized ? "已初始化" : "未初始化"}';
      if (currentUserId != null) {
        _mqttStatus += ', 用户: $currentUserId';
      }
    });

    log('[P2P Simple] MQTT状态: isInitialized=$isInitialized, currentUserId=$currentUserId');
  }

  Future<void> _initMqtt() async {
    setState(() {
      _status = '正在初始化MQTT...';
    });

    try {
      final success = await _mqttService.startMqtt('phoneId123');
      setState(() {
        _status = success ? 'MQTT初始化成功' : 'MQTT初始化失败';
        _isConnected = success;
      });
      await _checkMqttStatus();
      log('[P2P Simple] MQTT初始化结果: $success');
    } catch (e) {
      setState(() {
        _status = 'MQTT初始化异常: $e';
        _isConnected = false;
      });
      log('[P2P Simple] MQTT初始化异常: $e');
    }
  }

  Future<void> _setDevP2p() async {
    if (!_isConnected) {
      setState(() {
        _status = '请先初始化MQTT';
      });
      return;
    }

    setState(() {
      _status = '正在设置设备P2P...';
    });

    try {
      await _channel.invokeMethod('setDevP2p', {'devId': widget.devId});
      setState(() {
        _status = '设备P2P设置成功: ${widget.devId}';
      });
      log('[P2P Simple] 设备P2P设置成功: ${widget.devId}');
    } catch (e) {
      setState(() {
        _status = '设备P2P设置失败: $e';
      });
      log('[P2P Simple] 设备P2P设置失败: $e');
    }
  }

  Future<void> _startP2pVideo() async {
    if (!_isConnected) {
      setState(() {
        _status = '请先初始化MQTT';
      });
      return;
    }

    setState(() {
      _status = '正在启动P2P视频...';
      _frameCount = 0;
    });

    try {
      await _channel.invokeMethod('startP2pVideo', {'devId': widget.devId});
      setState(() {
        _status = 'P2P视频启动成功，等待真实H264视频流...';
        _videoStarted = true;
      });
      log('[P2P Simple] P2P视频启动成功，等待真实视频流');
    } catch (e) {
      setState(() {
        _status = 'P2P视频启动失败: $e';
      });
      log('[P2P Simple] P2P视频启动失败: $e');
    }
  }

  Future<void> _stopP2pVideo() async {
    setState(() {
      _status = '正在停止P2P视频...';
    });

    try {
      await _channel.invokeMethod('stopP2pVideo');
      setState(() {
        _status = 'P2P视频已停止';
        _videoStarted = false;
      });
      log('[P2P Simple] P2P视频已停止');
    } catch (e) {
      setState(() {
        _status = '停止P2P视频失败: $e';
      });
      log('[P2P Simple] 停止P2P视频失败: $e');
    }
  }

  Future<void> _testMqttConnection() async {
    setState(() {
      _status = '测试MQTT连接...';
    });

    try {
      // 初始化MQTT
      final success = await _mqttService.startMqtt('phoneId123');
      if (!success) {
        setState(() {
          _status = 'MQTT连接失败';
        });
        return;
      }

      setState(() {
        _status = 'MQTT连接成功，等待消息...';
        _isConnected = true;
      });

      // 等待一段时间看是否有消息
      await Future.delayed(Duration(seconds: 5));

      if (_lastMessage == '无消息') {
        setState(() {
          _status = 'MQTT连接成功，但未收到消息（可能设备离线）';
        });
      } else {
        setState(() {
          _status = 'MQTT连接成功，已收到消息';
        });
      }

      await _checkMqttStatus();
    } catch (e) {
      setState(() {
        _status = 'MQTT连接测试失败: $e';
      });
      log('[P2P Simple] MQTT连接测试失败: $e');
    }
  }

  Future<void> _testFullFlow() async {
    setState(() {
      _status = '开始完整流程测试...';
      _frameCount = 0;
    });

    try {
      // 1. 初始化MQTT
      log('[P2P Simple] 步骤1: 初始化MQTT');
      final success = await _mqttService.startMqtt('phoneId123');
      if (!success) {
        setState(() {
          _status = 'MQTT初始化失败';
        });
        return;
      }

      // 等待一下确保MQTT连接建立
      await Future.delayed(Duration(seconds: 2));

      // 2. 设置设备P2P
      log('[P2P Simple] 步骤2: 设置设备P2P');
      await _channel.invokeMethod('setDevP2p', {'devId': widget.devId});

      // 等待一下确保设备设置完成
      await Future.delayed(Duration(seconds: 1));

      // 3. 启动P2P视频
      log('[P2P Simple] 步骤3: 启动P2P视频');
      await _channel.invokeMethod('startP2pVideo', {'devId': widget.devId});

      setState(() {
        _status = '完整流程测试完成，等待真实H264视频流...';
        _isConnected = true;
        _videoStarted = true;
      });
      await _checkMqttStatus();
      log('[P2P Simple] 完整流程测试完成');
    } catch (e) {
      setState(() {
        _status = '完整流程测试失败: $e';
      });
      log('[P2P Simple] 完整流程测试失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.deviceName} - P2P视频'),
        backgroundColor: _videoStarted ? Colors.green : Colors.orange,
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 设备信息
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('设备信息:', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('设备名称: ${widget.deviceName}'),
                  Text('设备ID: ${widget.devId}'),
                ],
              ),
            ),
            SizedBox(height: 16),

            // 状态显示
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color:
                    _isConnected ? Colors.green.shade50 : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _isConnected ? Colors.green : Colors.orange,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '连接状态: ${_isConnected ? "已连接" : "未连接"}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _isConnected ? Colors.green : Colors.orange,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text('MQTT状态: $_mqttStatus'),
                  Text('当前状态: $_status'),
                  if (_videoStarted) ...[
                    SizedBox(height: 8),
                    Text('视频帧数: $_frameCount',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ],
              ),
            ),
            SizedBox(height: 16),

            // 消息显示
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('最新消息:', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text(_lastMessage, style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
            SizedBox(height: 16),

            // 操作按钮
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: _checkMqttStatus,
                  child: Text('检查MQTT'),
                ),
                ElevatedButton(
                  onPressed: _testMqttConnection,
                  child: Text('测试MQTT连接'),
                ),
                ElevatedButton(
                  onPressed: _initMqtt,
                  child: Text('初始化MQTT'),
                ),
                ElevatedButton(
                  onPressed: _setDevP2p,
                  child: Text('设置设备P2P'),
                ),
                ElevatedButton(
                  onPressed: _startP2pVideo,
                  child: Text('启动P2P视频'),
                ),
                ElevatedButton(
                  onPressed: _stopP2pVideo,
                  child: Text('停止P2P视频'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    setState(() {
                      _status = '正在测试SendJsonMsg...';
                    });
                    await _mqttService.testSendJsonMsg();
                    setState(() {
                      _status = 'SendJsonMsg测试已触发，请查看日志';
                    });
                  },
                  child: Text('测试SendJsonMsg'),
                ),
              ],
            ),
            SizedBox(height: 16),

            // 一键测试
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _testFullFlow,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text('一键完整流程测试'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
