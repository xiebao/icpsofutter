import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth/auth_provider.dart';
import '../utils/app_routes.dart';
import 'package:ipcso_main/gen_l10n/app_localizations.dart';
import 'profile_page.dart';
import 'p2p_video_main_page.dart';
import 'cloud_storage_page.dart';
import 'home_page.dart';

class RootPage extends StatefulWidget {
  @override
  _RootPageState createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  int _currentIndex = 0;
  final List<Widget> _children = [
    HomePage(), // Main content for home
    CloudStoragePage(), // 新增云存页面
    ProfilePage(), // User profile page
  ];

  void onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: _children[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        onTap: onTabTapped,
        currentIndex: _currentIndex,
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: l10n.home,
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.cloud),
            label: '云存',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: l10n.profile,
          )
        ],
      ),
    );
  }
}
