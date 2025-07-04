import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:developer';
import 'dart:async';
import '../providers/message_monitor.dart';
import '../providers/device_event_notifier.dart';
import '../services/mqtt_service.dart';

class P2pVideoPage extends StatefulWidget {
  final String devId;
  final String deviceName;
  const P2pVideoPage({Key? key, required this.devId, required this.deviceName})
      : super(key: key);

  @override
  State<P2pVideoPage> createState() => _P2pVideoPageState();
}

class _P2pVideoPageState extends State<P2pVideoPage> {
  String _status = 'Idle';
  bool _videoStarted = false;
  int _decodeMode = 0; // 只保留硬解(MediaCodec)
  int _displayMode = 1; // 只用Texture模式
  bool _isDisposed = false;
  DateTime? _lastFrameTime;
  String _statusDetail = '';
  int? _textureId;
  int? _platformViewId;
  String _bitrate = '-- kb/s';

  @override
  void initState() {
    super.initState();
    // 注册 handler，防止多页面冲突
    MqttService.channel.setMethodCallHandler(_handleMethod);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startP2pVideoFull();
    });
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isDisposed) {
        timer.cancel();
        return;
      }
      if (_videoStarted && _lastFrameTime != null) {
        final now = DateTime.now();
        final diff = now.difference(_lastFrameTime!);
        if (diff.inSeconds > 2 && _statusDetail.contains('已接收')) {
          setState(() {
            _statusDetail = '超过2秒未收到视频帧';
          });
        }
      }
    });
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    if (_isDisposed) return;
    switch (call.method) {
      case 'onTextureFrame':
        if (_textureId != null) {
          try {
            final yuvData = call.arguments['yuvData'] as List<int>;
            final width = call.arguments['width'] as int;
            final height = call.arguments['height'] as int;
            if (mounted) {
              setState(() {
                _statusDetail = '收到视频帧，红点变绿';
              });
            }
            await MqttService.channel.invokeMethod('updateTexture', {
              'textureId': _textureId,
              'yuvData': yuvData,
              'width': width,
              'height': height,
            });
          } catch (e) {
            log('[Flutter] updateTexture error: $e');
          }
        }
        break;
      case 'onError':
        if (mounted) {
          final errorMsg = call.arguments['message'] as String;
          setState(() {
            _status = 'Error: $errorMsg';
          });
        }
        break;
    }
  }

  Future<dynamic> _handleVideoMethod(MethodCall call) async {
    if (call.method == 'onVideoFrame') {
      final Uint8List h264Frame = call.arguments;
      _lastFrameTime = DateTime.now();
      if (!_videoStarted) {
        setState(() {
          _videoStarted = true;
        });
      }
      setState(() {
        _statusDetail = '收到视频帧，红点变绿';
        _bitrate = '25 kb/s'; // TODO: 可根据实际数据动态更新
      });
    }
  }

  Future<void> _setDevP2p() async {
    if (_isDisposed) return;
    try {
      await MqttService.channel
          .invokeMethod('setDevP2p', {'devId': widget.devId});
      if (mounted) {
        setState(() {
          _status = 'setDevP2p called: ${widget.devId}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'Error: $e';
        });
      }
    }
  }

  Future<void> _startP2pVideo() async {
    if (_isDisposed) return;
    try {
      if (_textureId == null) {
        _textureId = await MqttService.channel.invokeMethod('createTexture');
      }
      await MqttService.channel.invokeMethod('startP2pVideo', {
        'devId': widget.devId,
        'displayMode': _displayMode,
        'textureId': _textureId,
        'decodeMode': _decodeMode,
      });
      setState(() {
        _statusDetail = 'startP2pVideo已调用，等待第一帧...';
      });
    } catch (e) {
      setState(() {
        _statusDetail = '启动异常: $e';
      });
    }
  }

  Future<void> _stopP2pVideo() async {
    if (_isDisposed) return;
    try {
      log('[P2pVideoPage] 调用 stopP2pVideo');
      if (_platformViewId != null) {
        final channel = MethodChannel('p2p_video_view_$_platformViewId');
        await channel.invokeMethod('stopP2pVideo');
      } else {
        await MqttService.channel.invokeMethod('stopP2pVideo');
      }
      if (_displayMode == 1 && _textureId != null) {
        try {
          await MqttService.channel
              .invokeMethod('disposeTexture', {'textureId': _textureId});
        } catch (e) {
          log('[P2pVideoPage] disposeTexture error: $e');
        }
        _textureId = null;
      }
      if (mounted) {
        setState(() {
          _status = 'stopped';
          _lastFrameTime = null;
          _statusDetail = '已停止视频流';
          _videoStarted = false;
        });
        log('[P2pVideoPage] 已停止视频流');
      }
    } catch (e) {
      log('[P2pVideoPage] stopP2pVideo error: $e');
      if (mounted) {
        setState(() {
          _status = 'Error: $e';
        });
      }
    }
  }

  Future<void> _startP2pVideoFull() async {
    if (_isDisposed) return;
    try {
      await _setDevP2p();
      await _startP2pVideo();
      if (mounted) {
        setState(() {
          _status = '一键启动完成';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'Error: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    // 解绑 handler，防止页面切换冲突
    MqttService.channel.setMethodCallHandler(null);
    // 1. 停止视频流
    _stopP2pVideo();
    // 2. 释放 Texture
    if (_textureId != null) {
      try {
        MqttService.channel
            .invokeMethod('disposeTexture', {'textureId': _textureId});
      } catch (e) {
        log('[P2pVideoPage] disposeTexture error: $e');
      }
      _textureId = null;
    }
    // 3. 释放解码器
    try {
      MqttService.channel.invokeMethod('releaseDecoder', {});
    } catch (e) {
      log('[P2pVideoPage] releaseDecoder error: $e');
    }
    // 4. 其它资源
    _videoStarted = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: AppBar(
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.deviceName, style: const TextStyle(fontSize: 18)),
              Text(_bitrate, style: const TextStyle(fontSize: 12)),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () {
                Navigator.pushNamed(
                  context,
                  '/device_settings',
                  arguments: {
                    'devId': widget.devId,
                    'deviceName': widget.deviceName,
                  },
                );
              },
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildVideoView(),
                AnimatedBuilder(
                  animation: messageMonitor,
                  builder: (context, _) {
                    print(
                        '[DEBUG][UI] MQTT消息列表 rebuild: messages=${messageMonitor.messages.length}');
                    if (messageMonitor.messages.isEmpty)
                      return SizedBox.shrink();
                    return Container(
                      width: double.infinity,
                      color: Colors.black.withOpacity(0.05),
                      padding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('MQTT消息列表',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          ...messageMonitor.messages.reversed
                              .take(5)
                              .map((msg) => Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 2),
                                    child: Text(msg,
                                        style: const TextStyle(fontSize: 12)),
                                  )),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Version: 1.0.0'),
                      const Text('视频流状态：'),
                      _statusDetail.contains('已接收')
                          ? const Icon(Icons.circle, color: Colors.green)
                          : const Icon(Icons.circle, color: Colors.red),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child:
                      Text(_statusDetail, style: const TextStyle(fontSize: 12)),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Container(
                      width: MediaQuery.of(context).size.width,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton(
                            onPressed: () async {
                              setState(() {
                                _status = '正在测试SendJsonMsg...';
                              });
                              await MqttService.instance.testSendJsonMsg();
                              setState(() {
                                _status = 'SendJsonMsg测试已触发，请查看日志';
                              });
                            },
                            child: _BottomIconButton(
                                icon: Icons.power_settings_new, label: ''),
                          ),
                          _BottomIconButton(icon: Icons.volume_off, label: ''),
                          _BottomIconButton(icon: Icons.cut, label: ''),
                          _BottomIconButton(icon: Icons.videocam, label: ''),
                          _BottomIconButton(icon: Icons.auto_mode, label: ''),
                          _BottomIconButton(
                              icon: Icons.open_in_full, label: ''),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 浮动消息监控区域
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedBuilder(
              animation: messageMonitor,
              builder: (context, _) {
                print(
                    '[DEBUG][UI] AnimatedBuilder rebuild: messages=${messageMonitor.messages.length}');
                if (messageMonitor.messages.isEmpty) return SizedBox.shrink();
                return Dismissible(
                  key: const ValueKey('message_monitor'),
                  direction: DismissDirection.down,
                  onDismissed: (_) => messageMonitor.clear(),
                  child: Container(
                    margin: const EdgeInsets.all(12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('消息监控',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                            IconButton(
                              icon:
                                  const Icon(Icons.close, color: Colors.white),
                              onPressed: () => messageMonitor.clear(),
                              tooltip: '清空',
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: ListView(
                            reverse: true,
                            children: messageMonitor.messages.reversed
                                .map((msg) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 2),
                                      child: Text(msg,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12)),
                                    ))
                                .toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          // 全局设备事件通知区域
          Positioned(
            left: 0,
            right: 0,
            bottom: 200,
            child: AnimatedBuilder(
              animation: deviceEventNotifier,
              builder: (context, _) {
                final events = deviceEventNotifier.events
                    .where((e) =>
                        e.type == DeviceEventType.online ||
                        e.type == DeviceEventType.offline ||
                        e.type == DeviceEventType.statusChanged)
                    .toList();
                if (events.isEmpty) return SizedBox.shrink();
                return Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('设备事件',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => deviceEventNotifier.clear(),
                            tooltip: '清空',
                          ),
                        ],
                      ),
                      ...events.reversed.take(5).map((e) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              '[${e.type.name}] ${e.deviceId.isNotEmpty ? e.deviceId + ': ' : ''}${e.message}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13),
                            ),
                          )),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoView() {
    try {
      return SizedBox(
        width: 320,
        height: 240,
        child: (_videoStarted && _textureId != null)
            ? Texture(textureId: _textureId!)
            : Container(
                color: Colors.black12,
                alignment: Alignment.center,
                child:
                    const Text('没有启动视频流', style: TextStyle(color: Colors.grey)),
              ),
      );
    } catch (e) {
      log('[P2pVideoPage] _buildVideoView error: $e');
      return Container(
        width: 320,
        height: 240,
        color: Colors.black12,
        alignment: Alignment.center,
        child: const Text('视频流异常', style: TextStyle(color: Colors.red)),
      );
    }
  }
}

class _BottomIconButton extends StatelessWidget {
  final IconData? icon;
  final String label;
  const _BottomIconButton({this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null)
          Icon(
            icon,
            size: 24,
            color: Colors.grey,
          )
        else
          Text(label, style: TextStyle(fontSize: 16)),
      ],
    );
  }
}
