import 'package:dio/dio.dart';

class DioClient {
  // Private constructor
  DioClient._();

  // Singleton instance
  static final Dio _dio = Dio(BaseOptions(
    // IMPORTANT: Replace with your actual API base URL
    baseUrl: 'https://api.yourdomain.com/v1',
    connectTimeout: Duration(seconds: 5),
    receiveTimeout: Duration(seconds: 3),
  ))
    ..interceptors.add(LogInterceptor(responseBody: true, requestBody: true))
    ..interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        // You can add dynamic headers here, like an auth token
        return handler.next(options);
      },
      onError: (DioException e, handler) {
        // Handle global errors, e.g., network errors, 401, etc.
        print('Dio Error: ${e.message}');
        // You could check for 401 and trigger a logout
        // if (e.response?.statusCode == 401) { ... }
        return handler.next(e);
      },
    ));

  static Dio get instance => _dio;

  // Method to update Authorization header
  static void setAuthToken(String token) {
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  // Method to remove Authorization header
  static void removeAuthToken() {
    _dio.options.headers.remove('Authorization');
  }

  // Method to add custom interceptor
  static void addInterceptor(Interceptor interceptor) {
    _dio.interceptors.add(interceptor);
  }

  Future<Response> post(String path, {dynamic data}) async {
    return await _dio!.post(path, data: data);
  }

  Future<Response> get(String path, {dynamic data}) async {
    return await _dio!.get(path, data: data);
  }

  Future<Response> update(String path, {dynamic data}) async {
    return await _dio!.put(path, data: data);
  }

  Future<Response> delete(String path, {dynamic data}) async {
    return await _dio!.delete(path, data: data);
  }
}
