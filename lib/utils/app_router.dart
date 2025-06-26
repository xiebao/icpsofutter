import 'package:flutter/material.dart';
import '../pages/home_page.dart';
import '../pages/login_page.dart';
import '../pages/root_page.dart';
import '../pages/settings_page.dart';
import '../pages/profile_page.dart';
import '../pages/privacy_policy_page.dart';
import '../pages/device_settings_page.dart';
import '../pages/p2p_video_simple_page.dart';
import '../pages/test_update_page.dart';

class AppRouter {
  static const String root = '/';
  static const String home = '/home';
  static const String login = '/login';
  static const String settings = '/settings';
  static const String profile = '/profile';
  static const String privacy = '/privacy';
  static const String p2pVideoSimple = '/p2p_video_simple';
  static const String testUpdate = '/test_update';
  // 需要参数的页面不在routes里注册

  static final Map<String, WidgetBuilder> routes = {
    root: (context) => RootPage(),
    home: (context) => HomePage(),
    login: (context) => LoginPage(),
    settings: (context) => SettingsPage(),
    profile: (context) => ProfilePage(),
    privacy: (context) => PrivacyPolicyPage(),
    p2pVideoSimple: (context) => P2pVideoSimplePage(devId: '', deviceName: ''),
    testUpdate: (context) => TestUpdatePage(),
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
        builder: (_) => DeviceSettingsPage(devId: devId, deviceName: deviceName),
      );
    }
    // 可扩展更多需要参数的页面
    return null;
  }
} 