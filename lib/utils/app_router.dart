import 'package:flutter/material.dart';
import '../pages/home_page.dart';
import '../pages/login_page.dart';
import '../pages/settings_page.dart';
import '../pages/profile_page.dart';
import '../pages/privacy_policy_page.dart';
import '../pages/device_settings_page.dart';
import '../pages/p2p_video_page.dart';
import '../pages/test_update_page.dart';
import '../pages/wifi_config_page.dart';
import '../pages/root_page.dart'; // Added import for RootPage

class AppRouter {
  static const String login = '/login';
  static const String home = '/home';
  static const String settings = '/settings';
  static const String profile = '/profile';
  static const String privacy = '/privacy';
  static const String p2pVideo = '/p2p_video';
  static const String testUpdate = '/test_update';
  static const String wifiConfig = '/wifi_config';
  static const String root = '/root';
  // 需要参数的页面不在routes里注册

  static final Map<String, WidgetBuilder> routes = {
    root: (context) => RootPage(), // Changed from HomePage to RootPage
    home: (context) => HomePage(),
    login: (context) => LoginPage(),
    settings: (context) => SettingsPage(),
    profile: (context) => ProfilePage(),
    privacy: (context) => PrivacyPolicyPage(),
    p2pVideo: (context) => P2pVideoPage(devId: '', deviceName: ''),
    testUpdate: (context) => TestUpdatePage(),
    wifiConfig: (context) => WifiConfigPage(),
  };

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    if (settings.name == '/device_settings') {
      final args = settings.arguments;
      String devId = '';
      String deviceName = '';
      if (args is Map) {
        devId = args['devId'] ?? '';
        deviceName = args['deviceName'] ?? '';
      } else if (args is String) {
        devId = args;
      }
      return MaterialPageRoute(
        builder: (_) =>
            DeviceSettingsPage(devId: devId, deviceName: deviceName),
      );
    }
    // 可扩展更多需要参数的页面
    return null;
  }
}
