import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../auth/auth_provider.dart';
import '../pages/root_page.dart';
import '../pages/login_page.dart';

class OnboardingPage extends StatefulWidget {
  final VoidCallback? onFinish;
  const OnboardingPage({this.onFinish, Key? key}) : super(key: key);

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _controller = PageController();
  int _currentPage = 0;

  final List<String> _titles = ["欢迎使用App", "云存储安全可靠", "一键管理设备"];

  final List<String> _images = [
    "assets/images/guide1.png",
    "assets/images/guide2.png",
    "assets/images/guide3.png",
  ];

  void _finishOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_shown', true);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.isAuthenticated) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => RootPage()),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => LoginPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView.builder(
        controller: _controller,
        itemCount: 3,
        onPageChanged: (i) => setState(() => _currentPage = i),
        itemBuilder: (context, i) => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(_images[i], height: 300),
            SizedBox(height: 32),
            Text(_titles[i], style: TextStyle(fontSize: 24)),
            if (i == 2)
              Padding(
                padding: const EdgeInsets.only(top: 40.0),
                child: ElevatedButton(
                  onPressed: _finishOnboarding,
                  child: Text("开始使用"),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
            3,
            (i) => Container(
                  margin: EdgeInsets.all(4),
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _currentPage == i ? Colors.blue : Colors.grey,
                  ),
                )),
      ),
    );
  }
}
