import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class P2pVideoPage extends StatefulWidget {
  const P2pVideoPage({Key? key}) : super(key: key);

  @override
  _P2pVideoPageState createState() => _P2pVideoPageState();
}

class _P2pVideoPageState extends State<P2pVideoPage> {
  CameraController? _cameraController;
  bool _isCameraTest = false;
  int _displayMode = 0; // 0: AndroidView, 1: Texture
  int _decodeMode = 0; // 0: 软解码, 1: 硬解码

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    // Request camera permission
    var cameraStatus = await Permission.camera.request();
    if (cameraStatus.isDenied) {
      // Handle permission denied
      print('Camera permission denied');
      return;
    }

    // Request microphone permission
    var microphoneStatus = await Permission.microphone.request();
    if (microphoneStatus.isDenied) {
      // Handle permission denied
      print('Microphone permission denied');
      return;
    }

    // Request storage permissions
    var storageStatus = await Permission.storage.request();
    if (storageStatus.isDenied) {
      // Handle permission denied
      print('Storage permission denied');
      return;
    }

    // Initialize camera after permissions are granted
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      print('No cameras found');
      return;
    }

    _cameraController = CameraController(
      cameras.first,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await _cameraController!.initialize();
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('Error initializing camera: $e');
    }
  }

  void _toggleDisplayMode() {
    setState(() {
      _displayMode = _displayMode == 0 ? 1 : 0;
    });
  }

  void _toggleDecodeMode() {
    setState(() {
      _decodeMode = _decodeMode == 0 ? 1 : 0;
    });
  }

  void _toggleCameraTest() {
    setState(() {
      _isCameraTest = !_isCameraTest;
    });
  }

  Widget _buildVideoDisplay() {
    if (_isCameraTest) {
      return Container(
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.height * 0.7,
        child: _displayMode == 0
            ? AndroidView(
                viewType: 'camera_preview',
                creationParams: {
                  'decodeMode': _decodeMode,
                  'displayMode': _displayMode,
                },
                creationParamsCodec: StandardMessageCodec(),
              )
            : _cameraController != null && _cameraController!.value.isInitialized
                ? CameraPreview(_cameraController!)
                : Container(
                    color: Colors.black,
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
      );
    } else {
      return Container(
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.height * 0.7,
        child: _displayMode == 0
            ? AndroidView(
                viewType: 'camera_preview',
                creationParams: {
                  'decodeMode': _decodeMode,
                  'displayMode': _displayMode,
                },
                creationParamsCodec: StandardMessageCodec(),
              )
            : Container(
                color: Colors.black,
                child: Center(
                  child: Text(
                    '等待视频流...',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('P2P视频测试'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildVideoDisplay(),
            SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _toggleDisplayMode,
                    child: Text(_displayMode == 0 ? '切换到Texture' : '切换到AndroidView'),
                  ),
                ),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _toggleDecodeMode,
                    child: Text(_decodeMode == 0 ? '切换到硬解码' : '切换到软解码'),
                  ),
                ),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _toggleCameraTest,
                    child: Text(_isCameraTest ? '关闭摄像头测试' : '开启摄像头测试'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }
}