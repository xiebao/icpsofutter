import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:developer';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

class P2pVideoMainPage extends StatefulWidget {
  const P2pVideoMainPage({Key? key}) : super(key: key);

  @override
  State<P2pVideoMainPage> createState() => _P2pVideoMainPageState();
}

class _P2pVideoMainPageState extends State<P2pVideoMainPage> {
  static const MethodChannel _channel = MethodChannel('p2p_video_channel');
  String _status = 'Idle';
  final TextEditingController _devIdController = TextEditingController(text: 'camId123');
  final TextEditingController _phoneIdController = TextEditingController(text: 'phoneId123');
  bool _videoStarted = false;
  bool _videoStreamAvailable = false;  // 视频流状态
  int _decodeMode = 0; // 默认使用硬解(MediaCodec)
  int _displayMode = 1; // 默认使用Texture模式
  int? _textureId;
  bool _isDisposed = false;
  DateTime? _lastFrameTime;  // 最后收到视频帧的时间
  bool _isHardwareDecodingFailed = false;  // 硬解是否失败

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleMethod);
    _requestPermissions();
    
    // 添加定时器检查视频流状态
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isDisposed) {
        timer.cancel();
        return;
      }
      
      if (_videoStarted && _lastFrameTime != null) {
        final now = DateTime.now();
        final diff = now.difference(_lastFrameTime!);
        if (diff.inSeconds > 2) {  // 如果超过2秒没有收到新帧，认为视频流断开
          if (mounted) {
            setState(() {
              _videoStreamAvailable = false;
            });
          }
        }
      }
    });
  }

  Future<void> _requestPermissions() async {
    // Request camera permission
    var cameraStatus = await Permission.camera.request();
    if (cameraStatus.isDenied) {
      log('Camera permission denied');
      return;
    }

    // Request microphone permission
    var microphoneStatus = await Permission.microphone.request();
    if (microphoneStatus.isDenied) {
      log('Microphone permission denied');
      return;
    }

    // Request storage permissions
    var storageStatus = await Permission.storage.request();
    if (storageStatus.isDenied) {
      log('Storage permission denied');
      return;
    }
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    if (_isDisposed) return;
    
    switch (call.method) {
      case 'onTextureFrame':
        if (_textureId != null) {
          try {
            // 获取视频帧数据
            final yuvData = call.arguments['yuvData'] as List<int>;
            final width = call.arguments['width'] as int;
            final height = call.arguments['height'] as int;
            
            // 更新视频流状态
            if (mounted) {
              setState(() {
                _videoStreamAvailable = true;
                _lastFrameTime = DateTime.now();
              });
            }
            
            // 通知Texture更新
            await _channel.invokeMethod('updateTexture', {
              'textureId': _textureId,
              'yuvData': yuvData,
              'width': width,
              'height': height,
            });
            
            log('[Flutter] Received video frame: ${width}x${height}, data size: ${yuvData.length}');
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
            _videoStreamAvailable = false;
          });
          
          // 检查是否是硬解错误
          if (errorMsg.contains("MediaCodec") && _decodeMode == 0) {
            _isHardwareDecodingFailed = true;
            log('[Flutter] 硬解失败，切换到软解模式');
            // 自动重启视频流
            _stopP2pVideo().then((_) => _startP2pVideo());
          }
        }
        break;
    }
  }

  Future<void> _initMqtt() async {
    if (_isDisposed) return;
    
    try {
      log('[Flutter] 调用 initMqtt: ${_phoneIdController.text}');
      await _channel.invokeMethod('initMqtt', {'phoneId': _phoneIdController.text});
      if (mounted) {
        setState(() {
          _status = 'initMqtt called: ${_phoneIdController.text}';
        });
      }
    } catch (e) {
      log('[Flutter] initMqtt error: $e');
      if (mounted) {
        setState(() {
          _status = 'Error: $e';
        });
      }
    }
  }

  Future<void> _setDevP2p() async {
    if (_isDisposed) return;
    
    try {
      log('[Flutter] 调用 setDevP2p: ${_devIdController.text}');
      await _channel.invokeMethod('setDevP2p', {'devId': _devIdController.text});
      if (mounted) {
        setState(() {
          _status = 'setDevP2p called: ${_devIdController.text}';
        });
      }
    } catch (e) {
      log('[Flutter] setDevP2p error: $e');
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
      log('[Flutter] 开始启动 P2P 视频: ${_devIdController.text}');
      log('[Flutter] 调用 startP2pVideo 方法');
      
      // 如果硬解失败过，使用软解
      if (_isHardwareDecodingFailed) {
        _decodeMode = 1;
        log('[Flutter] 使用软解模式（硬解失败）');
      }
      
      if (_displayMode == 1) {
        log('[Flutter] 创建 Texture');
        _textureId = await _channel.invokeMethod('createTexture');
        if (_textureId == null) {
          throw Exception('Failed to create texture');
        }
        log('[Flutter] Texture 创建成功，ID: $_textureId');
      }
      
      log('[Flutter] 调用原生 startP2pVideo，等待 RecbVideoData 回调...');
      await _channel.invokeMethod('startP2pVideo', {
        'devId': _devIdController.text,
        'displayMode': _displayMode,
        'textureId': _textureId,
        'decodeMode': _decodeMode,
      });
      
      if (mounted) {
        setState(() {
          _status = 'startP2pVideo called: ${_devIdController.text}';
          _videoStarted = true;
          _videoStreamAvailable = false;  // 开始时设置为false，等待第一帧
          _lastFrameTime = null;  // 清除最后帧时间
        });
      }
      
      log('[Flutter] 一键启动完成，等待视频数据...');
    } catch (e) {
      log('[Flutter] startP2pVideo error: $e');
      if (mounted) {
        setState(() {
          _status = 'Error: $e';
          _videoStreamAvailable = false;
        });
      }
    }
  }

  Future<void> _stopP2pVideo() async {
    if (_isDisposed) return;
    
    try {
      log('[Flutter] 调用 stopP2pVideo');
      await _channel.invokeMethod('stopP2pVideo');
      
      if (_textureId != null) {
        try {
          await _channel.invokeMethod('disposeTexture', {'textureId': _textureId});
        } catch (e) {
          log('[Flutter] disposeTexture error: $e');
        }
        _textureId = null;
      }
      
      if (mounted) {
        setState(() {
          _status = 'stopped';
          _videoStarted = false;
          _videoStreamAvailable = false;  // 停止时重置视频流状态
          _lastFrameTime = null;  // 清除最后帧时间
        });
      }
    } catch (e) {
      log('[Flutter] stopP2pVideo error: $e');
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
      log('[Flutter] 一键启动开始');
      await _initMqtt();
      await _setDevP2p();
      await _startP2pVideo();
      if (mounted) {
        setState(() {
          _status = '一键启动完成';
          _videoStarted = true;
        });
      }
    } catch (e) {
      log('[Flutter] 一键启动 error: $e');
      if (mounted) {
        setState(() {
          _status = 'Error: $e';
        });
      }
    }
  }

  void _setDecodeMode(int mode) async {
    if (_isDisposed) return;
    
    try {
      setState(() { _decodeMode = mode; });
      await _channel.invokeMethod('setDecodeMode', {'mode': mode});
    } catch (e) {
      log('[Flutter] setDecodeMode error: $e');
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
    if (_textureId != null) {
      _channel.invokeMethod('disposeTexture', {'textureId': _textureId});
    }
    _devIdController.dispose();
    _phoneIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('P2P视频流')),
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _phoneIdController,
                        decoration: const InputDecoration(labelText: 'Phone ID'),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: TextField(
                        controller: _devIdController,
                        decoration: const InputDecoration(labelText: 'Device ID'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text('Status: $_status'),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: _initMqtt,
                      child: const Text('Init MQTT'),
                    ),
                    ElevatedButton(
                      onPressed: _setDevP2p,
                      child: const Text('Set DevP2p'),
                    ),
                    ElevatedButton(
                      onPressed: _startP2pVideoFull,
                      child: const Text('一键启动'),
                    ),
                    ElevatedButton(
                      onPressed: _stopP2pVideo,
                      child: const Text('Stop'),
                    ),
                    ToggleButtons(
                      isSelected: [_decodeMode==1, _decodeMode==0],
                      onPressed: (idx) => _setDecodeMode(idx==0?1:0),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text('软解(ExoPlayer)${_isHardwareDecodingFailed ? " (当前)" : ""}'),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text('硬解(MediaCodec)${!_isHardwareDecodingFailed ? " (当前)" : ""}'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(children: [
                  const Text('视频流显示区：'),
                  _videoStreamAvailable ? const Icon(Icons.circle, color: Colors.green) : const Icon(Icons.circle, color: Colors.red),
                ],),
                SizedBox(
                  width: 320,
                  height: 240,
                  child: _videoStarted
                      ? _textureId != null
                          ? Texture(textureId: _textureId!)
                          : Container(
                              color: Colors.black12,
                              alignment: Alignment.center,
                              child: const Text('Texture 初始化中...', style: TextStyle(color: Colors.grey)),
                            )
                      : Container(
                          color: Colors.black12,
                          alignment: Alignment.center,
                          child: const Text('请先点击一键启动', style: TextStyle(color: Colors.grey)),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
} 