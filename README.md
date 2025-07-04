# music_app_framework

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

推流和解码器初始化顺序要严格：先Texture，再解码器，再推流。


要统一通过 RecbVideoData 回调来处理所有的H264视频流，
摄像头先模拟264视频流给RecbVideoData进行测试。
            摄像头采集 -> H264编码 ->    RecbVideoData回调 -> 解码 -> Texture显示。
原生so库的调用：initMqtt->setDevP2p-> startP2pVideo ->   RecbVideoData回调 -> 解码 -> Texture

设备端推流 → so库收到数据 → 调用 RecbVideoData → JNI 回调 Java/Kotlin → 通过 MethodChannel 回调 Dart/Flutter → UI 显示视频帧

 Flutter调用 → JNI startP2pVideo → StartP2pVideoWrapper → ::StartP2pVideo(pRecvVideoCB)

+----------------+       +-------------------+       +-----------------------+       +-----------------+
| Flutter (Dart) | <---> | Platform Channels | <---> | Android (Kotlin/Java) | <---> | JNI Interface   | <---> | C Library (.so) |
|                |       |                   |       |      (Native Code)    |       | (C/C++ .cpp/.c) |       | (Actual logic)  |
+----------------+       +-------------------+       +-----------------------+       +-----------------+
  invokeMethod()             MethodChannel              `external fun` methods   `JNIEXPORT JNICALL` functions
  receive result             setMethodCallHandler       `System.loadLibrary()`   call your_c_lib.h functions


NDK 必须用 26.3.11579264
CMake 用 3.22.1
build.gradle 里 ndkVersion、externalNativeBuild、abiFilters、arguments 必须和 IDE 配置一致