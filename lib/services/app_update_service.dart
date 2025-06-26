import 'dart:io';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

enum UpdateType {
  none,      // 无需更新
  optional,  // 可选更新
  force      // 强制更新
}

class AppVersion {
  final String version;
  final String buildNumber;
  final String downloadUrl;
  final String description;
  final UpdateType updateType;
  final bool forceUpdate;

  AppVersion({
    required this.version,
    required this.buildNumber,
    required this.downloadUrl,
    required this.description,
    required this.updateType,
    this.forceUpdate = false,
  });

  factory AppVersion.fromJson(Map<String, dynamic> json) {
    return AppVersion(
      version: json['version'] ?? '',
      buildNumber: json['buildNumber'] ?? '',
      downloadUrl: json['downloadUrl'] ?? '',
      description: json['description'] ?? '',
      updateType: UpdateType.values.firstWhere(
        (e) => e.toString() == 'UpdateType.${json['updateType']}',
        orElse: () => UpdateType.none,
      ),
      forceUpdate: json['forceUpdate'] ?? false,
    );
  }
}

class AppUpdateService {
  static final AppUpdateService _instance = AppUpdateService._internal();
  factory AppUpdateService() => _instance;
  AppUpdateService._internal();

  final Dio _dio = Dio();
  String? _currentVersion;
  String? _currentBuildNumber;

  // 模拟API响应数据
  Map<String, dynamic> _mockApiResponse = {
    'android': {
      'version': '1.0.2',
      'buildNumber': '3',
      'downloadUrl': 'https://example.com/app-release.apk',
      'description': '修复了一些bug，提升了应用性能，新增了重要功能',
      'updateType': 'optional',
      'forceUpdate': false,
    },
    'ios': {
      'version': '1.0.2',
      'buildNumber': '3',
      'downloadUrl': 'https://apps.apple.com/app/id123456789',
      'description': '修复了一些bug，提升了应用性能，新增了重要功能',
      'updateType': 'optional',
      'forceUpdate': false,
    }
  };

  Future<void> init() async {
    try {
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      _currentVersion = packageInfo.version;
      _currentBuildNumber = packageInfo.buildNumber;
    } catch (e) {
      debugPrint('Failed to get package info: $e');
    }
  }

  Future<AppVersion?> checkForUpdate() async {
    try {
      // 模拟网络延迟
      await Future.delayed(Duration(milliseconds: 500));
      
      // 获取平台信息
      String platform = Platform.isAndroid ? 'android' : 'ios';
      
      // 模拟API调用
      Map<String, dynamic> response = _mockApiResponse[platform]!;
      
      // 检查是否需要更新
      if (_shouldUpdate(response['version'], response['buildNumber'])) {
        return AppVersion.fromJson(response);
      }
      
      return null;
    } catch (e) {
      debugPrint('Failed to check for update: $e');
      return null;
    }
  }

  bool _shouldUpdate(String newVersion, String newBuildNumber) {
    if (_currentVersion == null || _currentBuildNumber == null) {
      return false;
    }

    // 简单的版本比较逻辑
    List<int> currentVersionParts = _currentVersion!.split('.').map(int.parse).toList();
    List<int> newVersionParts = newVersion.split('.').map(int.parse).toList();
    
    // 比较版本号
    for (int i = 0; i < newVersionParts.length; i++) {
      if (i >= currentVersionParts.length) {
        return newVersionParts[i] > 0;
      }
      if (newVersionParts[i] > currentVersionParts[i]) {
        return true;
      }
      if (newVersionParts[i] < currentVersionParts[i]) {
        return false;
      }
    }
    
    // 如果版本号相同，比较构建号
    int currentBuild = int.tryParse(_currentBuildNumber!) ?? 0;
    int newBuild = int.tryParse(newBuildNumber) ?? 0;
    
    return newBuild > currentBuild;
  }

  Future<bool> downloadAndInstallApk(String downloadUrl) async {
    try {
      // 获取下载目录
      Directory? downloadDir = await getExternalStorageDirectory();
      if (downloadDir == null) {
        downloadDir = await getApplicationDocumentsDirectory();
      }
      
      String fileName = 'app-update.apk';
      String filePath = '${downloadDir.path}/$fileName';
      
      // 下载APK文件
      await _dio.download(downloadUrl, filePath);
      
      // 安装APK（需要适当的权限）
      // 这里只是模拟，实际需要调用原生方法或使用插件
      debugPrint('APK downloaded to: $filePath');
      
      return true;
    } catch (e) {
      debugPrint('Failed to download APK: $e');
      return false;
    }
  }

  Future<bool> openAppStore(String appStoreUrl) async {
    try {
      final Uri url = Uri.parse(appStoreUrl);
      if (await canLaunchUrl(url)) {
        return await launchUrl(url, mode: LaunchMode.externalApplication);
      }
      return false;
    } catch (e) {
      debugPrint('Failed to open App Store: $e');
      return false;
    }
  }

  String getCurrentVersion() {
    return _currentVersion ?? 'Unknown';
  }

  String getCurrentBuildNumber() {
    return _currentBuildNumber ?? 'Unknown';
  }
} 