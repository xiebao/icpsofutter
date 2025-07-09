import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth/auth_provider.dart';

class AuthInterceptor extends Interceptor {
  final AuthProvider authProvider;
  final GlobalKey<NavigatorState> navigatorKey;

  AuthInterceptor(this.authProvider, this.navigatorKey);

  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    // 登录后自动加 token
    if (authProvider.isAuthenticated && authProvider.token != null) {
      options.headers['Authorization'] = 'Bearer ${authProvider.token}';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    // 判断 token 过期或无效（如 401/403/400...）
    if (err.response != null &&
        [400, 401, 403].contains(err.response?.statusCode)) {
      // 清除本地 token
      await authProvider.logout();

      // 跳转到登录页，并传递当前路由和请求信息
      final currentRoute = navigatorKey.currentState?.context != null
          ? ModalRoute.of(navigatorKey.currentState!.context!)?.settings.name
          : null;
      navigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/login',
        (route) => false,
        arguments: {
          'redirect': currentRoute,
          'originalRequest': err.requestOptions,
        },
      );
    }
    handler.next(err);
  }
}
