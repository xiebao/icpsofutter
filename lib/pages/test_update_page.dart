import 'package:flutter/material.dart';
import '../services/app_update_service.dart';
import '../widgets/app_update_dialog.dart';

class TestUpdatePage extends StatefulWidget {
  @override
  _TestUpdatePageState createState() => _TestUpdatePageState();
}

class _TestUpdatePageState extends State<TestUpdatePage> {
  final AppUpdateService _updateService = AppUpdateService();
  String _currentVersion = 'Unknown';
  String _currentBuildNumber = 'Unknown';
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentVersion();
  }

  Future<void> _loadCurrentVersion() async {
    await _updateService.init();
    setState(() {
      _currentVersion = _updateService.getCurrentVersion();
      _currentBuildNumber = _updateService.getCurrentBuildNumber();
    });
  }

  Future<void> _checkForUpdate() async {
    setState(() {
      _isChecking = true;
    });

    try {
      final appVersion = await _updateService.checkForUpdate();
      
      if (mounted) {
        setState(() {
          _isChecking = false;
        });

        if (appVersion != null) {
          showDialog(
            context: context,
            barrierDismissible: !appVersion.forceUpdate,
            builder: (context) => AppUpdateDialog(
              appVersion: appVersion,
              onDismiss: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('用户选择稍后更新')),
                );
              },
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('当前已是最新版本')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isChecking = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('检查更新失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('App升级测试'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '当前版本信息',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    SizedBox(height: 8),
                    Text('版本号: $_currentVersion'),
                    Text('构建号: $_currentBuildNumber'),
                    Text('平台: ${Theme.of(context).platform.name}'),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),
            Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '升级测试',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _isChecking ? null : _checkForUpdate,
                      icon: _isChecking 
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(Icons.system_update),
                      label: Text(_isChecking ? '检查中...' : '检查更新'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: Size(double.infinity, 48),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),
            Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '说明',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    SizedBox(height: 8),
                    Text('• 当前应用版本: 1.0.0+1'),
                    Text('• 模拟服务器版本: 1.0.2+3'),
                    Text('• 点击"检查更新"会触发升级对话框'),
                    Text('• Android: 模拟下载APK文件'),
                    Text('• iOS: 跳转到App Store'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
} 