import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:developer';
import 'mqtt_service.dart';

class AppLifecycleService with WidgetsBindingObserver {
  static AppLifecycleService? _instance;
  final MqttService _mqttService = MqttService.instance;
  String? _currentUserId;

  // 单例模式
  factory AppLifecycleService() {
    _instance ??= AppLifecycleService._internal();
    return _instance!;
  }

  AppLifecycleService._internal();

  // 获取实例
  static AppLifecycleService get instance => AppLifecycleService();

  // 初始化服务
  Future<void> init() async {
    log('[AppLifecycleService] 初始化应用生命周期服务');
    
    // 注册生命周期观察者
    WidgetsBinding.instance.addObserver(this);
    
    // 获取当前用户ID
    final prefs = await SharedPreferences.getInstance();
    _currentUserId = prefs.getString('userid');
    
    log('[AppLifecycleService] 当前用户ID: $_currentUserId');
  }

  // 应用状态变化回调
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (_currentUserId == null) {
      log('[AppLifecycleService] 用户未登录，跳过生命周期处理');
      return;
    }

    switch (state) {
      case AppLifecycleState.resumed:
        log('[AppLifecycleService] 应用进入前台');
        _mqttService.onAppResumed(_currentUserId!);
        break;
      case AppLifecycleState.paused:
        log('[AppLifecycleService] 应用进入后台');
        _mqttService.onAppPaused();
        break;
      case AppLifecycleState.detached:
        log('[AppLifecycleService] 应用被销毁');
        _mqttService.onAppDestroyed();
        break;
      case AppLifecycleState.inactive:
        log('[AppLifecycleService] 应用处于非活动状态');
        break;
      case AppLifecycleState.hidden:
        log('[AppLifecycleService] 应用被隐藏');
        break;
    }
  }

  // 更新当前用户ID
  Future<void> updateCurrentUserId(String userId) async {
    _currentUserId = userId;
    log('[AppLifecycleService] 更新当前用户ID: $userId');
    
    // 如果应用当前处于前台，立即启动 MQTT
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      await _mqttService.onAppResumed(userId);
    }
  }

  // 清除当前用户ID
  void clearCurrentUserId() {
    _currentUserId = null;
    log('[AppLifecycleService] 清除当前用户ID');
  }

  // 销毁服务
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    log('[AppLifecycleService] 销毁应用生命周期服务');
  }
} 