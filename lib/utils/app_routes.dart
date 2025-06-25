import 'package:flutter/widgets.dart';
import '../pages/home_page.dart';
import '../pages/login_page.dart';
import '../pages/settings_page.dart';
import '../pages/profile_page.dart';
import '../pages/privacy_policy_page.dart'; // Placeholder for privacy policy
import '../pages/p2p_video_main_page.dart';

class AppRoutes {
  static const String home = '/';
  static const String login = '/login';
  static const String settings = '/settings';
  static const String profile = '/profile';
  static const String privacy = '/privacy';
  static const String p2pVideoMain = '/p2p_video_main';

  static final Map<String, WidgetBuilder> routes = {
    home: (context) => HomePage(),
    login: (context) => LoginPage(),
    settings: (context) => SettingsPage(),
    profile: (context) => ProfilePage(),
    privacy: (context) => PrivacyPolicyPage(),
    // P2P 视频页面需要参数，不在这里定义
  };
}
