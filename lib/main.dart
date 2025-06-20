import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'auth/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'utils/app_routes.dart';
import 'pages/login_page.dart';
import 'pages/home_page.dart';
import 'pages/p2p_video_test_page.dart';
import 'pages/p2p_video_page.dart';
import 'pages/p2p_video_main_page.dart';

void main() async {
  // Ensure that Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

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
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      themeMode: themeProvider.themeMode,

      // --- Routing Setup ---
      routes: {
        ...AppRoutes.routes..remove('/'),
        '/p2p_video_test': (context) => const P2pVideoTestPage(),
        '/p2p_video': (context) => const P2pVideoPage(),
      },

      // --- Home Screen Logic ---
      // If user is authenticated, show HomePage, otherwise show LoginPage.
      home: authProvider.isAuthenticated ? HomePage() : LoginPage(),
    );
  }
}
