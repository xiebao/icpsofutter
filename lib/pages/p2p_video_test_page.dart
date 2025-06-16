import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:developer';
import 'dart:io';
import 'package:flutter/foundation.dart';

class P2pVideoTestPage extends StatefulWidget {
  const P2pVideoTestPage({Key? key}) : super(key: key);

  @override
  State<P2pVideoTestPage> createState() => _P2pVideoTestPageState();
}

class _P2pVideoTestPageState extends State<P2pVideoTestPage> {
  static const MethodChannel _channel = MethodChannel('p2p_video_channel');
  String _status = 'Idle';
  final TextEditingController _devIdController = TextEditingController(text: 'camId123');
  final TextEditingController _phoneIdController = TextEditingController(text: 'phoneId123');
  bool _videoStarted = false;
  int _decodeMode = 1; // 1:软解, 0:硬解
  int _displayMode = 0; // 0: AndroidView, 1: Texture
  int? _textureId;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleMethod);
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    if (_isDisposed) return;
    
    switch (call.method) {
      case 'onTextureFrame':
        if (_textureId != null) {
          try {
            // 通知 Flutter 引擎更新纹理
            await _channel.invokeMethod('updateTexture', {
              'textureId': _textureId,
              'width': call.arguments['width'],
              'height': call.arguments['height'],
            });
          } catch (e) {
            log('[Flutter] updateTexture error: $e');
          }
        }
        break;
      case 'onError':
        if (mounted) {
          setState(() {
            _status = 'Error: ${call.arguments['message']}';
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
      log('[Flutter] 调用 startP2pVideo: '+_devIdController.text);
      if (_displayMode == 1) {
        // Texture 模式
        _textureId = await _channel.invokeMethod('createTexture');
        if (_textureId == null) {
          throw Exception('Failed to create texture');
        }
        log('[Flutter] Texture created with ID: $_textureId');
      }
      
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
      await _initMqtt();
      await _setDevP2p();
      await _startP2pVideo();
      if (mounted) {
        setState(() {
          _status = 'initMqtt + setDevP2p + startP2pVideo called';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('P2P Video Test')),
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
                const Text('视频流显示区：'),
                SizedBox(
                  width: 320,
                  height: 240,
                  child: _videoStarted
                      ? _displayMode == 0
                          ? AndroidView(
                              viewType: 'p2p_video_view',
                              creationParams: {'decodeMode': _decodeMode},
                              creationParamsCodec: const StandardMessageCodec(),
                            )
                          : _textureId != null
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

  @override
  void dispose() {
    _isDisposed = true;
    _cleanupResources();
    super.dispose();
  }
} 