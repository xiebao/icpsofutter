import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:developer';
import 'dart:async';

class P2pVideoSimplePage extends StatefulWidget {
  final String devId;
  final String deviceName;
  const P2pVideoSimplePage({Key? key, required this.devId, required this.deviceName}) : super(key: key);

  @override
  State<P2pVideoSimplePage> createState() => _P2pVideoSimplePageState();
}

class _P2pVideoSimplePageState extends State<P2pVideoSimplePage> {
  static const MethodChannel _channel = MethodChannel('p2p_video_channel');
  static const MethodChannel _videoChannel = MethodChannel('p2p_video_channel');
  String _status = 'Idle';
  bool _videoStarted = false;
  int _decodeMode = 0; // 只保留硬解(MediaCodec)
  bool _isDisposed = false;
  DateTime? _lastFrameTime;
  String _statusDetail = '';
  int? _textureId;
  int? _platformViewId;
  String _bitrate = '-- kb/s';

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleMethod);
    _videoChannel.setMethodCallHandler(_handleVideoMethod);
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
            await _channel.invokeMethod('updateTexture', {
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
      if (!_statusDetail.contains('已接收')) {
        setState(() {
          _statusDetail = '收到视频帧，红点变绿';
        });
      }
      setState(() {
        _bitrate = '25 kb/s'; // TODO: 可根据实际数据动态更新
      });
    }
  }

  Future<void> _setDevP2p() async {
    if (_isDisposed) return;
    try {
      await _channel.invokeMethod('setDevP2p', {'devId': widget.devId});
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
        _textureId = await _channel.invokeMethod('createTexture');
      }
      await _channel.invokeMethod('startP2pVideo', {
        'devId': widget.devId,
        'displayMode': 1,
        'textureId': _textureId,
        'decodeMode': _decodeMode,
      });
      setState(() {
        _videoStarted = true;
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
      await _channel.invokeMethod('stopP2pVideo');
      if (_textureId != null) {
        try {
          await _channel.invokeMethod('disposeTexture', {'textureId': _textureId});
        } catch (e) {}
        _textureId = null;
      }
      if (mounted) {
        setState(() {
          _status = 'stopped';
          _lastFrameTime = null;
          _statusDetail = '已停止视频流';
          _videoStarted = false;
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
    _stopP2pVideo();
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
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 320,
              height: 240,
              child: _videoStarted
                  ? AndroidView(
                      viewType: 'p2p_video_view',
                      onPlatformViewCreated: (int id) {
                        _platformViewId = id;
                      },
                      creationParams: const {},
                      creationParamsCodec: const StandardMessageCodec(),
                    )
                  : Container(
                      color: Colors.black12,
                      alignment: Alignment.center,
                      child: const Text('没有启动视频流', style: TextStyle(color: Colors.grey)),
                    ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('视频流状态：'),
                  _statusDetail.contains('已接收') ? const Icon(Icons.circle, color: Colors.green) : const Icon(Icons.circle, color: Colors.red),
                      ],
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child:  Text(_statusDetail, style: const TextStyle(fontSize: 12)),  
              
            ),
            
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child:
               SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child:Container(
                  width: MediaQuery.of(context).size.width,
                child:  Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _BottomIconButton(icon: Icons.power_settings_new, label: ''),
                    _BottomIconButton(icon: Icons.volume_off, label: ''),
                    _BottomIconButton(icon: Icons.cut, label: ''),
                    _BottomIconButton(icon: Icons.videocam, label: ''),
                    _BottomIconButton(icon: Icons.auto_mode, label: ''),
                    _BottomIconButton(icon: Icons.open_in_full, label: ''),
                  ],
                ),
              ),
              ),
            ),
          ],
        ),
      ),
    );
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
          Icon(icon, size: 24,color: Colors.grey,)
        else
          Text(label, style: TextStyle(fontSize: 16)),
      ],
    );
  }
} 