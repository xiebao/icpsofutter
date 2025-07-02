import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

class P2pVideoMainPage extends StatefulWidget {
  final String devId;

  const P2pVideoMainPage({Key? key, required this.devId}) : super(key: key);

  @override
  State<P2pVideoMainPage> createState() => _P2pVideoMainPageState();
}

class _P2pVideoMainPageState extends State<P2pVideoMainPage> {
  static const MethodChannel _channel = MethodChannel('p2p_video_channel');
  static const MethodChannel _videoChannel =
      MethodChannel('video_frame_channel');
  String _status = 'Idle';
  late final TextEditingController _devIdController;
  bool _videoStarted = false;
  int _decodeMode = 0; // 默认使用硬解(MediaCodec)
  int _displayMode = 1; // 默认使用Texture模式
  bool _isDisposed = false;
  DateTime? _lastFrameTime; // 最后收到视频帧的时间
  bool _isHardwareDecodingFailed = false; // 硬解是否失败
  bool _decoderInitialized = false;
  String _decoderSource = '';
  String _statusDetail = '';
  int? _textureId;
  int? _platformViewId; // 新增：保存PlatformView的id
  bool _videoStreamAvailable = false;

  @override
  void initState() {
    super.initState();
    _devIdController = TextEditingController(text: widget.devId);
    _channel.setMethodCallHandler(_handleMethod);
    _requestPermissions();

    // 添加定时器检查视频流状态
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isDisposed) {
        timer.cancel();
        return;
      }
      if (_videoStarted) {
        if (_lastFrameTime != null) {
          final now = DateTime.now();
          final diff = now.difference(_lastFrameTime!);
          if (diff.inSeconds > 2 && _videoStreamAvailable) {
            setState(() {
              _videoStreamAvailable = false;
              _statusDetail = '超过2秒未收到视频帧，红点变红';
            });
            log('[Flutter] 超过2秒未收到视频帧，红点变红');
          }
        } else if (!_videoStreamAvailable) {
          setState(() {
            _videoStreamAvailable = false;
            _statusDetail = '尚未收到视频流，红点为红';
          });
        }
      }
    });

    _videoChannel.setMethodCallHandler((call) async {
      if (call.method == 'onVideoFrame') {
        final Uint8List h264Frame = call.arguments;
        print('[Flutter] onVideoFrame received, len=h264Frame.length}');
        // 只要收到帧，立即变绿
        if (!_videoStreamAvailable) {
          setState(() {
            _videoStreamAvailable = true;
            _statusDetail = '收到视频帧，红点变绿';
          });
          log('[Flutter] 收到 onVideoFrame，红点变绿');
        }
        _lastFrameTime = DateTime.now();
        if (!_decoderInitialized || _decoderSource != 'p2p') {
          await _initDecoder(640, 480, source: 'p2p');
          setState(() {
            _statusDetail = '收到onVideoFrame, 初始化解码器';
          });
        }
        await _videoChannel.invokeMethod('queueH264', {
          'data': h264Frame,
          'pts': DateTime.now().millisecondsSinceEpoch,
          'source': 'p2p',
        });
        setState(() {
          _statusDetail = 'queueH264已调用(p2p), len=${h264Frame.length}';
        });
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
                _statusDetail = '收到视频帧，红点变绿';
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

  Future<void> _setDevP2p() async {
    if (_isDisposed) return;

    try {
      log('[Flutter] 调用 setDevP2p: ${_devIdController.text}');
      await _channel
          .invokeMethod('setDevP2p', {'devId': _devIdController.text});
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
      setState(() {
        _statusDetail = '调用 _startP2pVideo';
      });
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
      if (!_decoderInitialized || _decoderSource != 'p2p') {
        await _initDecoder(640, 480, source: 'p2p');
        setState(() {
          _statusDetail = '已初始化解码器';
        });
      }
      log('[Flutter] 调用原生 startP2pVideo，等待 RecbVideoData 回调...');
      setState(() {
        _statusDetail = '等待设备回调数据流...';
      });
      await _channel.invokeMethod('startP2pVideo', {
        'devId': _devIdController.text,
        'displayMode': _displayMode,
        'textureId': _textureId,
        'decodeMode': _decodeMode,
      });
      setState(() {
        _statusDetail = 'startP2pVideo已调用，等待第一帧...';
      });
      log('[Flutter] 一键启动完成，等待视频数据...');
    } catch (e) {
      log('[Flutter] startP2pVideo error: $e');
      setState(() {
        _statusDetail = '启动异常: $e';
      });
    }
  }

  Future<void> _stopP2pVideo() async {
    if (_isDisposed) return;
    try {
      log('[Flutter] 调用 stopP2pVideo');
      if (_platformViewId != null) {
        final channel = MethodChannel('p2p_video_view_$_platformViewId');
        await channel.invokeMethod('stopP2pVideo');
      } else {
        await _channel.invokeMethod('stopP2pVideo');
      }
      if (_textureId != null) {
        try {
          await _channel
              .invokeMethod('disposeTexture', {'textureId': _textureId});
        } catch (e) {
          log('[Flutter] disposeTexture error: $e');
        }
        _textureId = null;
      }
      if (mounted) {
        setState(() {
          _status = 'stopped';
          _lastFrameTime = null;
          _statusDetail = '已停止视频流，红点为红';
        });
        log('[Flutter] 已停止视频流，红点为红');
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

  Future<void> _startP2pVideoOnPlatformView() async {
    if (_platformViewId == null) return;
    final channel = MethodChannel('p2p_video_view_$_platformViewId');
    await channel.invokeMethod('startP2pVideo', {
      'devId': _devIdController.text,
      'displayMode': _displayMode,
      'textureId': _textureId,
      'decodeMode': _decodeMode,
    });
  }

  Future<void> _startP2pVideoFull() async {
    if (_isDisposed) return;
    try {
      log('[Flutter] 一键启动开始');
      await _setDevP2p();
      setState(() {
        _videoStarted = true;
      }); // 先显示AndroidView
      // AndroidView创建后会自动回调onPlatformViewCreated
      // _startP2pVideoOnPlatformView会在onPlatformViewCreated里调用
      if (mounted) {
        setState(() {
          _status = '一键启动完成';
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
      setState(() {
        _decodeMode = mode;
      });
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

  Future<void> _initDecoder(int width, int height, {String source = ''}) async {
    await _channel.invokeMethod('initDecoder', {
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
    try {
      await _channel.invokeMethod('releaseDecoder', {'source': source});
      setState(() {
        _decoderInitialized = false;
        _decoderSource = '';
      });
      log('[Flutter] releaseDecoder: source=$source');
    } catch (e) {
      log('[Flutter] releaseDecoder error: $e');
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    if (_textureId != null) {
      _channel.invokeMethod('disposeTexture', {'textureId': _textureId});
    }
    _devIdController.dispose();
    _releaseDecoder();
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
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.device_hub, color: Colors.blue),
                      const SizedBox(width: 8),
                      const Text('设备ID: ',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(widget.devId, style: const TextStyle(fontSize: 16)),
                    ],
                  ),
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
                      isSelected: [_decodeMode == 1, _decodeMode == 0],
                      onPressed: (idx) => _setDecodeMode(idx == 0 ? 1 : 0),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                              '软解(ExoPlayer)${_isHardwareDecodingFailed ? " (当前)" : ""}'),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                              '硬解(MediaCodec)${!_isHardwareDecodingFailed ? " (当前)" : ""}'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    const Text('视频流显示区：'),
                    _videoStreamAvailable
                        ? const Icon(Icons.circle, color: Colors.green)
                        : const Icon(Icons.circle, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(_statusDetail,
                            style: TextStyle(
                                fontSize: 12, color: Colors.blueGrey))),
                  ],
                ),
                _buildVideoView(),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: () async {
                        await _channel.invokeMethod('startCameraH264Stream', {
                          'width': 640,
                          'height': 480,
                        });
                        setState(() {
                          _videoStarted = true;
                          _statusDetail = '开启摄像头H264推流测试...';
                        });
                      },
                      child: const Text('开启摄像头H264推流测试'),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: () async {
                        await _channel.invokeMethod('stopCameraH264Stream');
                        setState(() {
                          // _videoStarted = false; // 不要销毁AndroidView，保证回调链路
                          _statusDetail = '停止摄像头H264推流';
                        });
                      },
                      child: const Text('停止推流'),
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

  Widget _buildVideoView() {
    return SizedBox(
      width: 320,
      height: 240,
      child: _videoStarted
          ? AndroidView(
              viewType: 'p2p_video_view',
              onPlatformViewCreated: (int id) {
                _platformViewId = id;
                _startP2pVideoOnPlatformView();
              },
              creationParams: const {},
              creationParamsCodec: const StandardMessageCodec(),
            )
          : Container(
              color: Colors.black12,
              alignment: Alignment.center,
              child:
                  const Text('没有启动视频流', style: TextStyle(color: Colors.grey)),
            ),
    );
  }
}
