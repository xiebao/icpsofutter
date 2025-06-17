import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:developer';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'dart:async';

class P2pVideoTestPage extends StatefulWidget {
  const P2pVideoTestPage({Key? key}) : super(key: key);

  @override
  State<P2pVideoTestPage> createState() => _P2pVideoTestPageState();
}

class _P2pVideoTestPageState extends State<P2pVideoTestPage> {
  static const MethodChannel _channel = MethodChannel('p2p_video_channel');
  static const MethodChannel _videoChannel = MethodChannel('p2p_video_channel');
  String _status = 'Idle';
  final TextEditingController _devIdController = TextEditingController(text: 'camId123');
  final TextEditingController _phoneIdController = TextEditingController(text: 'phoneId123');
  bool _videoStarted = false;
  bool _videoStreamAvailable = false;
  int _decodeMode = 1; // 1:软解, 0:硬解
  int _displayMode = 1; // 使用Texture模式
  int? _textureId;
  bool _isDisposed = false;
  DateTime? _lastFrameTime;
  bool _decoderInitialized = false;
  String _decoderSource = '';
  String _statusDetail = '';

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleMethod);
    
    // 添加定时器检查视频流状态
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isDisposed) {
        timer.cancel();
        return;
      }
      
      if (_videoStarted && _lastFrameTime != null) {
        final now = DateTime.now();
        final diff = now.difference(_lastFrameTime!);
        if (diff.inSeconds > 2) {
          if (mounted) {
            setState(() {
              _videoStreamAvailable = false;
              _statusDetail = '超过2秒未收到视频帧';
            });
          }
        }
      }
    });

    _videoChannel.setMethodCallHandler((call) async {
      if (call.method == 'onVideoFrame') {
        final Uint8List h264Frame = call.arguments;
        print('[Flutter] onVideoFrame received, len=${h264Frame.length}');
        setState(() {
          _videoStreamAvailable = true;
          _statusDetail = '收到一键启动回调数据流，红点变绿点';
          _lastFrameTime = DateTime.now();
        });
        if (!_decoderInitialized || _decoderSource != 'p2p') {
          await _initDecoder(640, 480, source: 'p2p');
          setState(() { _statusDetail = '收到onVideoFrame, 初始化解码器'; });
        }
        await _videoChannel.invokeMethod('queueH264', {
          'data': h264Frame,
          'pts': DateTime.now().millisecondsSinceEpoch,
          'source': 'p2p',
        });
        print('[Flutter] queueH264 called (p2p), len=${h264Frame.length}');
        setState(() { _statusDetail = 'queueH264已调用(p2p), len=${h264Frame.length}'; });
      } else if (call.method == 'onCameraH264Frame') {
        final Uint8List h264Frame = call.arguments;
        print('[Flutter] onCameraH264Frame received, len=${h264Frame.length}');
        setState(() {
          _videoStreamAvailable = true;
          _statusDetail = '收到摄像头H264数据流，红点变绿点';
          _lastFrameTime = DateTime.now();
        });
        if (!_decoderInitialized || _decoderSource != 'camera') {
          await _initDecoder(640, 480, source: 'camera');
          setState(() { _statusDetail = '收到onCameraH264Frame, 初始化解码器'; });
        }
        await _videoChannel.invokeMethod('queueH264', {
          'data': h264Frame,
          'pts': DateTime.now().millisecondsSinceEpoch,
          'source': 'camera',
        });
        print('[Flutter] queueH264 called (camera), len=${h264Frame.length}');
        setState(() { _statusDetail = 'queueH264已调用(camera), len=${h264Frame.length}'; });
      }
    });
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    if (_isDisposed) return;
    
    switch (call.method) {
      case 'RecbVideoData':  // 统一处理所有H264视频流的回调
        try {
          // 确保数据结构匹配native层
          final Uint8List h264Frame = call.arguments['data'] as Uint8List;
          final int length = h264Frame.length;
          final int width = call.arguments['width'] ?? 640;
          final int height = call.arguments['height'] ?? 480;
          
          print('[Flutter] RecbVideoData callback received, len=$length');
          setState(() {
            _videoStreamAvailable = true;
            _statusDetail = '收到H264数据，长度=$length';
            _lastFrameTime = DateTime.now();
          });

          // 确保解码器已初始化
          if (!_decoderInitialized) {
            await _initDecoder(width, height);
            setState(() { _statusDetail = '初始化解码器完成'; });
          }

          // 送帧给解码器
          await _channel.invokeMethod('queueH264', {
            'data': h264Frame,
            'pts': DateTime.now().millisecondsSinceEpoch,
          });
          print('[Flutter] H264 frame queued to decoder, len=$length');
          setState(() { _statusDetail = 'H264帧已送入解码器队列'; });
        } catch (e) {
          print('[Flutter] Error processing RecbVideoData: $e');
          setState(() { 
            _statusDetail = 'RecbVideoData处理错误: $e';
            _videoStreamAvailable = false;
          });
        }
        break;

      case 'onDecodedFrame':  // 处理解码后的帧
        if (_textureId != null) {
          try {
            final yuvData = call.arguments['yuvData'] as List<int>;
            final width = call.arguments['width'] as int;
            final height = call.arguments['height'] as int;
            
            // 更新Texture
            await _channel.invokeMethod('updateTexture', {
              'textureId': _textureId,
              'yuvData': yuvData,
              'width': width,
              'height': height,
            });
            
            setState(() { _statusDetail = '解码完成，已更新Texture显示'; });
            print('[Flutter] Texture updated with decoded frame: ${width}x${height}');
          } catch (e) {
            print('[Flutter] Error updating texture: $e');
            setState(() { _statusDetail = 'Texture更新错误: $e'; });
          }
        }
        break;

      case 'onError':
        if (mounted) {
          final errorMsg = call.arguments['message'] as String;
          setState(() {
            _status = 'Error: $errorMsg';
            _videoStreamAvailable = false;
            _statusDetail = '发生错误: $errorMsg';
          });
        }
        break;
    }
  }

  Future<void> _initMqtt() async {
    if (_isDisposed) return;
    
    try {
      log('[Flutter] 调用 initMqtt: "+_phoneIdController.text+"');
      await _channel.invokeMethod('initMqtt', {'phoneId': _phoneIdController.text});
      if (mounted) {
        setState(() {
          _status = 'initMqtt called: '+_phoneIdController.text;
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
      log('[Flutter] 调用 setDevP2p: "+_devIdController.text+"');
      await _channel.invokeMethod('setDevP2p', {'devId': _devIdController.text});
      if (mounted) {
        setState(() {
          _status = 'setDevP2p called: '+_devIdController.text;
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
      log('[Flutter] 开始启动 P2P 视频: '+_devIdController.text);
      if (_displayMode == 1) {
        // Texture 模式
        log('[Flutter] 创建 Texture');
        _textureId = await _channel.invokeMethod('createTexture');
        if (_textureId == null) {
          throw Exception('Failed to create texture');
        }
        log('[Flutter] Texture 创建成功，ID: $_textureId');
      }
      
      log('[Flutter] 调用 startP2pVideo 方法');
      await _channel.invokeMethod('startP2pVideo', {
        'devId': _devIdController.text,
        'displayMode': _displayMode,
        'textureId': _textureId,
      });
      
      if (mounted) {
        setState(() {
          _status = 'startP2pVideo called: '+_devIdController.text;
          _videoStarted = true;
        });
      }
      
      log('[Flutter] 启动帧检查');
      // 启动帧检查
      _startFrameCheck();
    } catch (e) {
      log('[Flutter] startP2pVideo error: $e');
      if (mounted) {
        setState(() {
          _status = 'Error: $e';
        });
      }
      // 清理资源
      await _cleanupResources();
    }
  }

  Future<void> _cleanupResources() async {
    if (_textureId != null) {
      try {
        await _channel.invokeMethod('disposeTexture', {'textureId': _textureId});
      } catch (e) {
        log('[Flutter] disposeTexture error: $e');
      }
      _textureId = null;
    }
    _videoStarted = false;
  }

  void _startFrameCheck() {
    if (!_isDisposed) {
      Future.delayed(const Duration(seconds: 3), () {
        if (!_isDisposed && mounted) {
          _channel.invokeMethod('checkFrameStatus');
          _startFrameCheck();
        }
      });
    }
  }

  Future<void> _stopP2pVideo() async {
    if (_isDisposed) return;
    
    try {
      log('[Flutter] 调用 stopP2pVideo');
      await _channel.invokeMethod('stopP2pVideo');
      await _cleanupResources();
      
      if (mounted) {
        setState(() {
          _status = 'stopped';
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
      log('[Flutter] 开始一键启动流程');
      log('[Flutter] 1. 初始化 MQTT');
      await _initMqtt();
      log('[Flutter] 2. 设置 P2P 设备');
      _channel.invokeMethod('setDevP2p', {'devId': _devIdController.text}); // fire-and-forget
      log('[Flutter] 3. 开始 P2P 视频');
      await _startP2pVideo();
      if (mounted) {
        setState(() {
          _status = 'initMqtt + setDevP2p + startP2pVideo called';
          _videoStarted = true;
        });
      }
      log('[Flutter] 一键启动完成');
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

  void _setDisplayMode(int mode) async {
    if (_isDisposed) return;
    
    try {
      if (_videoStarted) {
        await _stopP2pVideo();
      }
      setState(() { _displayMode = mode; });
      if (_videoStarted) {
        await _startP2pVideo();
      }
    } catch (e) {
      log('[Flutter] setDisplayMode error: $e');
      if (mounted) {
        setState(() {
          _status = 'Error: $e';
        });
      }
    }
  }

  Future<void> _initDecoder(int width, int height, {String source = ''}) async {
    if (_textureId == null) {
      final int textureId = await _videoChannel.invokeMethod('createTexture');
      setState(() { _textureId = textureId; });
    }
    await _videoChannel.invokeMethod('initDecoder', {
      'textureId': _textureId,
      'width': width,
      'height': height,
      'source': source,
    });
    setState(() {
      _decoderInitialized = true;
      _decoderSource = source;
    });
    log('[Flutter] initDecoder: source=$source, width=$width, height=$height, textureId=$_textureId');
  }

  Future<void> _releaseDecoder({String source = ''}) async {
    await _videoChannel.invokeMethod('releaseDecoder', {'source': source});
    setState(() {
      _decoderInitialized = false;
      _decoderSource = '';
    });
    log('[Flutter] releaseDecoder: source=$source');
  }

  Future<void> _startCameraTest() async {
    try {
      // 先确保之前的资源已释放
      await _releaseDecoder();
      
      // 启动摄像头H264流，数据会通过RecbVideoData回调返回
      await _channel.invokeMethod('startCameraH264Stream', {
        'width': 640,
        'height': 480,
      });
      
      setState(() {
        _videoStarted = true;
        _statusDetail = '开启摄像头H264推流，等待RecbVideoData回调...';
      });
      
      print('[Flutter] Started camera H264 stream test');
    } catch (e) {
      print('[Flutter] Error starting camera test: $e');
      setState(() {
        _statusDetail = '启动摄像头测试失败: $e';
        _videoStarted = false;
      });
    }
  }

  Future<void> _stopCameraTest() async {
    try {
      await _channel.invokeMethod('stopCameraH264Stream');
      await _releaseDecoder();
      setState(() {
        _videoStarted = false;
        _videoStreamAvailable = false;
        _statusDetail = '停止摄像头推流';
      });
      print('[Flutter] Stopped camera H264 stream test');
    } catch (e) {
      print('[Flutter] Error stopping camera test: $e');
      setState(() {
        _statusDetail = '停止摄像头测试失败: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('P2P视频解码测试')),
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
                Text('状态: $_status'),
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
                        Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('软解(ExoPlayer)')),
                        Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('硬解(MediaCodec)')),
                      ],
                    ),
                    ToggleButtons(
                      isSelected: [_displayMode==0, _displayMode==1],
                      onPressed: (idx) => _setDisplayMode(idx),
                      children: [
                        Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('AndroidView')),
                        Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('Texture')),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(children: [
                  const Text('视频流状态: '),
                  _videoStreamAvailable ? const Icon(Icons.circle, color: Colors.green) : const Icon(Icons.circle, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_statusDetail, style: TextStyle(fontSize: 12, color: Colors.blueGrey))),
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
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: _startCameraTest,
                      child: const Text('开启摄像头测试'),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: _stopCameraTest,
                      child: const Text('停止测试'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    _cleanupResources();
    _releaseDecoder();
    super.dispose();
  }
} 