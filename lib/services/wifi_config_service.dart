import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

class WifiConfigInfo {
  final String ssid;
  final String password;
  final String securityType; // WPA, WEP, OPEN
  final String? ipAddress;
  final String? gateway;
  final String? subnetMask;

  WifiConfigInfo({
    required this.ssid,
    required this.password,
    required this.securityType,
    this.ipAddress,
    this.gateway,
    this.subnetMask,
  });

  Map<String, dynamic> toJson() {
    return {
      'ssid': ssid,
      'password': password,
      'securityType': securityType,
      'ipAddress': ipAddress,
      'gateway': gateway,
      'subnetMask': subnetMask,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }

  factory WifiConfigInfo.fromJson(Map<String, dynamic> json) {
    return WifiConfigInfo(
      ssid: json['ssid'] ?? '',
      password: json['password'] ?? '',
      securityType: json['securityType'] ?? 'WPA',
      ipAddress: json['ipAddress'],
      gateway: json['gateway'],
      subnetMask: json['subnetMask'],
    );
  }

  String toQrCodeData() {
    return jsonEncode(toJson());
  }
}

class WifiConfigService {
  static final WifiConfigService _instance = WifiConfigService._internal();
  factory WifiConfigService() => _instance;
  WifiConfigService._internal();

  final NetworkInfo _networkInfo = NetworkInfo();
  final WifiIoT _wifiIoT = WifiIoT();

  // 检查并请求权限
  Future<bool> requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.locationWhenInUse,
      Permission.locationAlways,
      if (Platform.isAndroid) Permission.accessFineLocation,
      if (Platform.isAndroid) Permission.accessCoarseLocation,
    ].request();

    bool allGranted = true;
    statuses.forEach((permission, status) {
      if (!status.isGranted) {
        allGranted = false;
        debugPrint('Permission $permission not granted: $status');
      }
    });

    return allGranted;
  }

  // 获取当前连接的WiFi信息
  Future<WifiConfigInfo?> getCurrentWifiInfo() async {
    try {
      if (!await requestPermissions()) {
        debugPrint('WiFi permissions not granted');
        return null;
      }

      // 获取当前WiFi SSID
      String? ssid;
      if (Platform.isAndroid) {
        ssid = await _wifiIoT.getSSID();
      } else {
        ssid = await _networkInfo.getWifiName();
      }

      if (ssid == null || ssid.isEmpty) {
        debugPrint('Could not get WiFi SSID');
        return null;
      }

      // 获取IP地址
      String? ipAddress = await _networkInfo.getWifiIP();
      
      // 获取网关地址
      String? gateway = await _networkInfo.getWifiGatewayIP();
      
      // 获取子网掩码
      String? subnetMask = await _networkInfo.getWifiSubmask();

      // 获取WiFi安全类型（简化版本）
      String securityType = 'WPA'; // 默认值，实际应用中需要更复杂的检测

      return WifiConfigInfo(
        ssid: ssid,
        password: '', // 出于安全考虑，不获取密码
        securityType: securityType,
        ipAddress: ipAddress,
        gateway: gateway,
        subnetMask: subnetMask,
      );
    } catch (e) {
      debugPrint('Error getting WiFi info: $e');
      return null;
    }
  }

  // 获取可用的WiFi网络列表
  Future<List<WifiNetwork>> getAvailableNetworks() async {
    try {
      if (!await requestPermissions()) {
        return [];
      }

      List<WifiNetwork> networks = await _wifiIoT.loadWifiList();
      return networks;
    } catch (e) {
      debugPrint('Error getting available networks: $e');
      return [];
    }
  }

  // 连接到指定的WiFi网络
  Future<bool> connectToWifi(String ssid, String password, {String security = 'WPA'}) async {
    try {
      if (!await requestPermissions()) {
        return false;
      }

      bool result = await _wifiIoT.connect(ssid, password: password, security: security);
      return result;
    } catch (e) {
      debugPrint('Error connecting to WiFi: $e');
      return false;
    }
  }

  // 生成配网二维码数据
  String generateConfigQrCode(WifiConfigInfo configInfo) {
    return configInfo.toQrCodeData();
  }

  // 解析配网二维码数据
  WifiConfigInfo? parseConfigQrCode(String qrCodeData) {
    try {
      Map<String, dynamic> jsonData = jsonDecode(qrCodeData);
      return WifiConfigInfo.fromJson(jsonData);
    } catch (e) {
      debugPrint('Error parsing QR code data: $e');
      return null;
    }
  }

  // 模拟设备配网过程
  Future<bool> configureDevice(WifiConfigInfo configInfo) async {
    try {
      debugPrint('Configuring device with WiFi: ${configInfo.ssid}');
      
      // 模拟配网过程
      await Future.delayed(Duration(seconds: 3));
      
      // 这里应该包含实际的设备配网逻辑
      // 例如：通过UDP广播、HTTP请求等方式与设备通信
      
      debugPrint('Device configuration completed');
      return true;
    } catch (e) {
      debugPrint('Error configuring device: $e');
      return false;
    }
  }

  // 检查设备是否已连接到网络
  Future<bool> checkDeviceConnection(String deviceIp) async {
    try {
      // 模拟ping设备
      await Future.delayed(Duration(milliseconds: 500));
      
      // 这里应该包含实际的设备连接检查逻辑
      // 例如：HTTP请求、UDP广播等
      
      return true; // 模拟成功
    } catch (e) {
      debugPrint('Error checking device connection: $e');
      return false;
    }
  }

  // 获取设备列表（已配网的设备）
  Future<List<Map<String, dynamic>>> getConfiguredDevices() async {
    try {
      // 模拟获取已配网设备列表
      await Future.delayed(Duration(milliseconds: 300));
      
      return [
        {
          'id': 'device_001',
          'name': '客厅摄像头',
          'ip': '192.168.1.100',
          'type': 'camera',
          'status': 'online',
        },
        {
          'id': 'device_002',
          'name': '卧室传感器',
          'ip': '192.168.1.101',
          'type': 'sensor',
          'status': 'online',
        },
      ];
    } catch (e) {
      debugPrint('Error getting configured devices: $e');
      return [];
    }
  }
}

// WiFi网络信息类
class WifiNetwork {
  final String ssid;
  final String bssid;
  final String capabilities;
  final int level;
  final int frequency;

  WifiNetwork({
    required this.ssid,
    required this.bssid,
    required this.capabilities,
    required this.level,
    required this.frequency,
  });

  factory WifiNetwork.fromMap(Map<String, dynamic> map) {
    return WifiNetwork(
      ssid: map['SSID'] ?? '',
      bssid: map['BSSID'] ?? '',
      capabilities: map['capabilities'] ?? '',
      level: map['level'] ?? 0,
      frequency: map['frequency'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'SSID': ssid,
      'BSSID': bssid,
      'capabilities': capabilities,
      'level': level,
      'frequency': frequency,
    };
  }
} 