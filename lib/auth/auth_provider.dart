import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import '../api/dio_client.dart';
import '../models/user.dart';

class AuthProvider with ChangeNotifier {
  String? _token;
  User? _user;
  bool _isAuthenticated = false;

  String? get token => _token;
  User? get user => _user;
  bool get isAuthenticated => _isAuthenticated;

  // Initialize AuthProvider
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('jwt_token');
    
    if (_token != null) {
      _isAuthenticated = true;
      // You can also fetch user profile here if needed
      // For now, we'll just set a placeholder user
      _user = User(id: '1', name: 'Cached User', email: 'user@123.com');
      DioClient.setAuthToken(_token!);
    }
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    // 本地Mock账号（开发调试用）
    if (email == 'test@123.com' && password == '123456') {
      _token = 'mock_token';
      _user = User(id: '1', name: '测试用户', email: email, avatarUrl: null);
      _isAuthenticated = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('jwt_token', _token!);
      notifyListeners();
      return true;
    }
    try {
      // IMPORTANT: Replace with your actual login API endpoint
      final response = await DioClient.instance.post('/auth/login', data: {
        'email': email,
        'password': password,
      });

      if (response.statusCode == 200 && response.data['token'] != null) {
        _token = response.data['token'];
        _user = User.fromJson(response.data['user']);
        _isAuthenticated = true;
        
        DioClient.setAuthToken(_token!);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('jwt_token', _token!);
        
        notifyListeners();
        return true;
      }
      return false;
    } on DioException catch (e) {
      // Handle login error, e.g., show a message
      print('Login error: $e');
      return false;
    }
  }

  Future<void> logout() async {
    _token = null;
    _user = null;
    _isAuthenticated = false;
    
    DioClient.removeAuthToken();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    
    notifyListeners();
  }

  // You can add register method similarly
  Future<bool> register(String name, String email, String password) async {
    // 本地Mock注册（开发调试用）
    if (email.endsWith('@123.com')) {
      // 注册成功后自动登录
      return await login(email, password);
    }
    try {
      // IMPORTANT: Replace with your actual register API endpoint
      await DioClient.instance.post('/auth/register', data: {
        'name': name,
        'email': email,
        'password': password,
      });
      // After successful registration, you might want to log the user in automatically
      return await login(email, password);
    } on DioException catch (e) {
      print('Register error: $e');
      return false;
    }
  }
}
