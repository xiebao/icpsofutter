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

要统一通过 RecbVideoData 回调来处理所有的H264视频流，
摄像头先模拟264视频流给RecbVideoData进行测试。
            摄像头采集 -> H264编码 ->    RecbVideoData回调 -> 解码 -> Texture显示。
原生so库的调用：initMqtt->setDevP2p-> startP2pVideo ->   RecbVideoData回调 -> 解码 -> Texture