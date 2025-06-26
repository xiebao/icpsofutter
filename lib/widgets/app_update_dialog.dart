import 'dart:io';
import 'package:flutter/material.dart';
import '../services/app_update_service.dart';
import 'package:ipcso_main/gen_l10n/app_localizations.dart';

class AppUpdateDialog extends StatefulWidget {
  final AppVersion appVersion;
  final VoidCallback? onDismiss;

  const AppUpdateDialog({
    Key? key,
    required this.appVersion,
    this.onDismiss,
  }) : super(key: key);

  @override
  _AppUpdateDialogState createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  final AppUpdateService _updateService = AppUpdateService();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isForceUpdate = widget.appVersion.forceUpdate;
    
    return WillPopScope(
      onWillPop: () async => !isForceUpdate,
      child: AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(
              Icons.system_update,
              color: Theme.of(context).primaryColor,
              size: 28,
            ),
            SizedBox(width: 12),
            Text(
              '发现新版本',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 版本信息
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Theme.of(context).primaryColor,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '新版本: ${widget.appVersion.version} (${widget.appVersion.buildNumber})',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '当前版本: ${_updateService.getCurrentVersion()} (${_updateService.getCurrentBuildNumber()})',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            
            // 更新说明
            Text(
              '更新内容:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            SizedBox(height: 8),
            Text(
              widget.appVersion.description,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
                height: 1.4,
              ),
            ),
            SizedBox(height: 16),
            
            // 下载进度
            if (_isDownloading) ...[
              LinearProgressIndicator(
                value: _downloadProgress,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).primaryColor,
                ),
              ),
              SizedBox(height: 8),
              Text(
                '下载进度: ${(_downloadProgress * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              SizedBox(height: 16),
            ],
            
            // 更新类型提示
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isForceUpdate 
                    ? Colors.red.withOpacity(0.1)
                    : Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isForceUpdate ? Colors.red : Colors.orange,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isForceUpdate ? Icons.warning : Icons.info,
                    color: isForceUpdate ? Colors.red : Colors.orange,
                    size: 16,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isForceUpdate 
                          ? '此更新为强制更新，必须立即安装'
                          : '建议更新以获得更好的体验',
                      style: TextStyle(
                        fontSize: 12,
                        color: isForceUpdate ? Colors.red : Colors.orange,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (!isForceUpdate && !_isDownloading)
            TextButton(
              onPressed: () {
                widget.onDismiss?.call();
                Navigator.of(context).pop();
              },
              child: Text(
                '稍后再说',
                style: TextStyle(
                  color: Colors.grey[600],
                ),
              ),
            ),
          if (!_isDownloading)
            ElevatedButton(
              onPressed: _isDownloading ? null : _handleUpdate,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                _isDownloading ? '下载中...' : '立即更新',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _handleUpdate() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });

    try {
      if (Platform.isAndroid) {
        // Android: 下载并安装APK
        await _downloadApk();
      } else if (Platform.isIOS) {
        // iOS: 跳转到App Store
        await _openAppStore();
      }
    } catch (e) {
      _showErrorDialog('更新失败: $e');
    } finally {
      setState(() {
        _isDownloading = false;
      });
    }
  }

  Future<void> _downloadApk() async {
    // 模拟下载进度
    for (int i = 0; i <= 100; i += 10) {
      await Future.delayed(Duration(milliseconds: 200));
      setState(() {
        _downloadProgress = i / 100;
      });
    }

    // 实际下载APK
    bool success = await _updateService.downloadAndInstallApk(
      widget.appVersion.downloadUrl,
    );

    if (success) {
      _showSuccessDialog('APK下载完成，请手动安装');
    } else {
      _showErrorDialog('APK下载失败');
    }
  }

  Future<void> _openAppStore() async {
    bool success = await _updateService.openAppStore(
      widget.appVersion.downloadUrl,
    );

    if (success) {
      _showSuccessDialog('已跳转到App Store，请在App Store中完成更新');
    } else {
      _showErrorDialog('无法打开App Store');
    }
  }

  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('更新提示'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (!widget.appVersion.forceUpdate) {
                Navigator.of(context).pop();
              }
            },
            child: Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('更新失败'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (!widget.appVersion.forceUpdate) {
                Navigator.of(context).pop();
              }
            },
            child: Text('确定'),
          ),
        ],
      ),
    );
  }
} 