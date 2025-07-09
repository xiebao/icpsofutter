import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:ipcso_main/gen_l10n/app_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pages/root_page.dart';
import 'pages/onboarding_page.dart';
import 'pages/login_page.dart';

import 'auth/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'utils/app_router.dart';
import 'services/app_lifecycle_service.dart';
import 'services/mqtt_service.dart';
import 'api/dio_client.dart';
import 'api/auth_interceptor.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  // Ensure that Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化服务
  await MqttService.instance.init();
  await AppLifecycleService.instance.init();

  // Create providers
  final authProvider = AuthProvider();
  final themeProvider = ThemeProvider();

  // Initialize providers
  await authProvider.init();
  await themeProvider.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => authProvider),
        ChangeNotifierProvider(create: (_) => themeProvider),
      ],
      child: ScreenUtilInit(
        designSize: Size(390, 844), // 设计稿基准尺寸
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (context, child) => MyApp(),
      ),
    ),
  );
}

class MyApp extends StatelessWidget {
  Future<bool> _shouldShowOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool('onboarding_shown') ?? false);
  }

  @override
  Widget build(BuildContext context) {
    // Listen to theme and auth providers
    final themeProvider = Provider.of<ThemeProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context);

    // 注册拦截器（只注册一次）
    DioClient.addInterceptor(AuthInterceptor(authProvider, navigatorKey));

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Music App',
      debugShowCheckedModeBanner: false,

      // --- Internationalization Setup ---
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'), // English
        Locale('zh'), // Chinese
      ],

      // --- Theme Setup ---
      theme: ThemeData(
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(seedColor: Color(0xFF00B86B)),
        visualDensity: VisualDensity.adaptivePlatformDensity,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
            seedColor: Color(0xFF00B86B), brightness: Brightness.dark),
        visualDensity: VisualDensity.adaptivePlatformDensity,
        useMaterial3: true,
      ),
      themeMode: themeProvider.themeMode,

      // --- Routing Setup ---
      routes: {
        ...AppRouter.routes,
      },
      onGenerateRoute: AppRouter.onGenerateRoute,
      home: FutureBuilder<bool>(
        future: _shouldShowOnboarding(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return SizedBox();
          if (snapshot.data!) {
            return OnboardingPage(
              onFinish: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('onboarding_shown', true);
                (context as Element).reassemble();
              },
            );
          } else {
            final authProvider = Provider.of<AuthProvider>(context);
            if (authProvider.isAuthenticated) {
              return RootPage();
            } else {
              return LoginPage();
            }
          }
        },
      ),
    );
  }
}
