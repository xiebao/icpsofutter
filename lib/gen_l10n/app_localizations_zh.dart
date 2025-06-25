// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get home => '首页';

  @override
  String get profile => '个人中心';

  @override
  String get settings => '设置';

  @override
  String get login => '登录';

  @override
  String get logout => '退出登录';

  @override
  String get email => '邮箱';

  @override
  String get password => '密码';

  @override
  String get emailRequired => '请输入邮箱';

  @override
  String get passwordRequired => '请输入密码';

  @override
  String get loginFailed => '登录失败，请检查您的凭据。';

  @override
  String get dontHaveAccount => '还没有账户？立即注册';

  @override
  String get privacyPolicy => '隐私政策';

  @override
  String get displayStyle => '显示风格';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get themeLight => '白天模式';

  @override
  String get themeDark => '黑夜模式';

  @override
  String get changePassword => '更改密码';

  @override
  String get clearCache => '清理缓存';

  @override
  String get pleaseLogin => '请登录以查看您的个人资料。';

  @override
  String welcome(String userName) {
    return '欢迎您, $userName!';
  }
}
