import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:ipcso_main/gen_l10n/app_localizations.dart';

import 'auth/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'utils/app_router.dart';
import 'pages/login_page.dart';
import 'pages/root_page.dart';
import 'services/app_lifecycle_service.dart';
import 'services/mqtt_service.dart';

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
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Listen to theme and auth providers
    final themeProvider = Provider.of<ThemeProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context);

    return MaterialApp(
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
        colorScheme: ColorScheme.fromSeed(seedColor: Color(0xFF00B86B), brightness: Brightness.dark),
        visualDensity: VisualDensity.adaptivePlatformDensity,
        useMaterial3: true,
      ),
      themeMode: themeProvider.themeMode,

      // --- Routing Setup ---
      routes: {
        ...AppRouter.routes,
      },
      onGenerateRoute: AppRouter.onGenerateRoute,

      // --- Home Screen Logic ---
      // If user is authenticated, show HomePage, otherwise show LoginPage.
      initialRoute: authProvider.isAuthenticated ? AppRouter.root : AppRouter.login,
    );
  }
}
