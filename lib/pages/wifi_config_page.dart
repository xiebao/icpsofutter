import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../services/wifi_config_service.dart';

class WifiConfigPage extends StatefulWidget {
  @override
  State<WifiConfigPage> createState() => _WifiConfigPageState();
}

class _WifiConfigPageState extends State<WifiConfigPage> {
  final _formKey = GlobalKey<FormState>();
  final _pwdController = TextEditingController();
  final WifiConfigService _wifiService = WifiConfigService();
  final NetworkInfo _networkInfo = NetworkInfo();
  
  String _securityType = 'WPA';
  String? _qrData;
  bool _showQr = false;
  bool _configSuccess = false;
  bool _permissionsGranted = false;
  bool _isLoading = true;
  
  // WiFi信息
  String _currentWifiName = '';
  String _currentWifiBSSID = '';
  List<Map<String, dynamic>> _availableNetworks = [];
  bool _showNetworkList = false;

  @override
  void initState() {
    super.initState();
    _initializeWifiInfo();
  }

  @override
  void dispose() {
    _pwdController.dispose();
    super.dispose();
  }

  Future<void> _initializeWifiInfo() async {
    setState(() {
      _isLoading = true;
    });

    // 检查权限
    bool granted = await _wifiService.requestPermissions();
    setState(() {
      _permissionsGranted = granted;
    });
    
    if (!granted) {
      _showPermissionDialog();
      setState(() {
        _isLoading = false;
      });
      return;
    }

    // 获取当前WiFi信息
    await _getCurrentWifiInfo();
    
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _getCurrentWifiInfo() async {
    try {
      String? wifiName = await _networkInfo.getWifiName();
      String? wifiBSSID = await _networkInfo.getWifiBSSID();
      
      setState(() {
        _currentWifiName = wifiName?.replaceAll('"', '') ?? '';
        _currentWifiBSSID = wifiBSSID?.replaceAll('"', '') ?? '';
      });
      
      // 如果获取到WiFi名称，自动填充
      if (_currentWifiName.isNotEmpty) {
        debugPrint('当前WiFi: $_currentWifiName');
      } else {
        // 如果没有获取到WiFi信息，扫描可用网络
        await _scanAvailableNetworks();
      }
    } catch (e) {
      debugPrint('获取WiFi信息失败: $e');
      // 扫描可用网络作为备选
      await _scanAvailableNetworks();
    }
  }

  Future<void> _scanAvailableNetworks() async {
    try {
      // 模拟扫描网络（实际项目中需要使用原生插件）
      await Future.delayed(Duration(seconds: 2));
      
      setState(() {
        _availableNetworks = [
          {'ssid': 'TestWiFi_1', 'signal': -45, 'security': 'WPA2'},
          {'ssid': 'TestWiFi_2', 'signal': -52, 'security': 'WPA'},
          {'ssid': 'TestWiFi_3', 'signal': -65, 'security': 'Open'},
        ];
        _showNetworkList = true;
      });
    } catch (e) {
      debugPrint('扫描网络失败: $e');
    }
  }

  void _selectNetwork(String ssid) {
    setState(() {
      _currentWifiName = ssid;
      _showNetworkList = false;
    });
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('需要权限'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('WiFi配网功能需要以下权限：'),
            SizedBox(height: 8),
            Text('• 位置信息权限（用于获取WiFi信息）'),
            Text('• 网络状态权限'),
            SizedBox(height: 16),
            Text('请在设置中开启相关权限后重试。'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop(); // 返回上一页
            },
            child: Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await openAppSettings(); // 跳转到系统设置
            },
            child: Text('去设置'),
          ),
        ],
      ),
    );
  }

  Future<void> _checkPermissions() async {
    bool granted = await _wifiService.requestPermissions();
    setState(() {
      _permissionsGranted = granted;
    });
    
    if (!granted) {
      _showPermissionDialog();
    } else {
      await _getCurrentWifiInfo();
    }
  }

  void _generateQr() async {
    if (!_permissionsGranted) {
      _showPermissionDialog();
      return;
    }

    if (_currentWifiName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请选择WiFi网络')),
      );
      return;
    }

    if (_formKey.currentState?.validate() ?? false) {
      final config = WifiConfigInfo(
        ssid: _currentWifiName,
        password: _pwdController.text.trim(),
        securityType: _securityType,
      );
      setState(() {
        _qrData = config.toQrCodeData();
        _showQr = true;
        _configSuccess = false;
      });
    }
  }

  void _onConfigSuccess() {
    setState(() {
      _configSuccess = true;
    });
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('配网成功'),
        content: Text('设备已成功连接到WiFi！'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop(true); // 返回上一级
            },
            child: Text('完成'),
          ),
        ],
      ),
    );
  }

  void _onRetry() {
    setState(() {
      _showQr = false;
      _configSuccess = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('WiFi配网'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading 
        ? Center(child: CircularProgressIndicator())
        : Padding(
            padding: EdgeInsets.all(16.0),
            child: _showQr ? _buildQrView() : _buildInputView(),
          ),
    );
  }

  Widget _buildInputView() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_permissionsGranted) ...[
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '需要位置权限才能获取WiFi信息，请确保已开启相关权限。',
                      style: TextStyle(color: Colors.orange[800]),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
          ],
          
          // WiFi网络选择
          Text('WiFi网络', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SizedBox(height: 12),
          
          if (_currentWifiName.isNotEmpty) ...[
            // 显示当前WiFi
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).primaryColor),
              ),
              child: Row(
                children: [
                  Icon(Icons.wifi, color: Theme.of(context).primaryColor),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _currentWifiName,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_currentWifiBSSID.isNotEmpty)
                          Text(
                            'BSSID: $_currentWifiBSSID',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(Icons.check_circle, color: Colors.green),
                ],
              ),
            ),
            SizedBox(height: 16),
          ] else if (_showNetworkList) ...[
            // 显示可用网络列表
            Container(
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                itemCount: _availableNetworks.length,
                itemBuilder: (context, index) {
                  final network = _availableNetworks[index];
                  return ListTile(
                    leading: Icon(Icons.wifi),
                    title: Text(network['ssid']),
                    subtitle: Text('信号强度: ${network['signal']}dBm'),
                    trailing: Text(network['security']),
                    onTap: () => _selectNetwork(network['ssid']),
                  );
                },
              ),
            ),
            SizedBox(height: 16),
          ] else ...[
            // 没有网络信息时的提示
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.grey[600]),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '无法获取当前WiFi信息，请手动输入或重新扫描',
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
          ],
          
          // 手动输入WiFi名称（备选）
          if (_currentWifiName.isEmpty) ...[
            TextFormField(
              decoration: InputDecoration(
                labelText: 'WiFi名称 (SSID)',
                border: OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(Icons.refresh),
                  onPressed: _scanAvailableNetworks,
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _currentWifiName = value;
                });
              },
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '请输入WiFi名称';
                }
                return null;
              },
            ),
            SizedBox(height: 16),
          ],
          
          // WiFi密码
          TextFormField(
            controller: _pwdController,
            decoration: InputDecoration(
              labelText: 'WiFi密码',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return '请输入WiFi密码';
              }
              return null;
            },
          ),
          SizedBox(height: 16),
          
          // 加密方式
          DropdownButtonFormField<String>(
            value: _securityType,
            decoration: InputDecoration(
              labelText: '加密方式',
              border: OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem(value: 'WPA', child: Text('WPA/WPA2')),
              DropdownMenuItem(value: 'WEP', child: Text('WEP')),
              DropdownMenuItem(value: 'Open', child: Text('开放网络')),
            ],
            onChanged: (value) {
              setState(() {
                _securityType = value ?? 'WPA';
              });
            },
          ),
          SizedBox(height: 32),
          
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _permissionsGranted ? _generateQr : _checkPermissions,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(_permissionsGranted ? '生成配网二维码' : '检查权限'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQrView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'WiFi配网二维码',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 24),
        
        Container(
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              if (_qrData != null)
                QrImageView(
                  data: _qrData!,
                  version: QrVersions.auto,
                  size: 200,
                ),
              SizedBox(height: 16),
              Text(
                '扫描二维码连接WiFi',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 32),
        
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            OutlinedButton(
              onPressed: _onRetry,
              child: Text('重新生成'),
            ),
            ElevatedButton(
              onPressed: _onConfigSuccess,
              child: Text('配网成功'),
            ),
          ],
        ),
      ],
    );
  }
} 