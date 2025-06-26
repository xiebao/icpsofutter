// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get home => 'Home';

  @override
  String get profile => 'Profile';

  @override
  String get settings => 'Settings';

  @override
  String get login => 'Login';

  @override
  String get logout => 'Logout';

  @override
  String get email => 'Email';

  @override
  String get username => 'username';

  @override
  String get password => 'Password';

  @override
  String get emailRequired => 'Email is required';

  @override
  String get passwordRequired => 'Password is required';

  @override
  String get loginFailed => 'Login failed. Please check your credentials.';

  @override
  String get dontHaveAccount => 'Don\'t have an account? Sign up';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get displayStyle => 'Display Style';

  @override
  String get themeSystem => 'System Default';

  @override
  String get themeLight => 'Light Mode';

  @override
  String get themeDark => 'Dark Mode';

  @override
  String get changePassword => 'Change Password';

  @override
  String get clearCache => 'Clear Cache';

  @override
  String get pleaseLogin => 'Please log in to view your profile.';

  @override
  String welcome(String userName) {
    return 'Welcome, $userName!';
  }
}
