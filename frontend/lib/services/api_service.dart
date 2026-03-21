import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import '../models/question_model.dart';

class ApiService {
  static const String baseUrl = kDebugMode ? 'http://127.0.0.1:8000' : '';
  
  final Dio _dio = Dio(BaseOptions(baseUrl: baseUrl));
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  ApiService() {
    // 注入拦截器，每次请求自动附带 Authorization Token
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        String? token = await _storage.read(key: 'jwt_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
    ));
  }

  // ==========================================
  // 1. 登录服务
  // ==========================================
  Future<bool> login(String username, String password) async {
    try {
      // API 接收的是 Form data 形式表单
      final response = await _dio.post(
        '/api/v1/auth/login',
        data: FormData.fromMap({
          'username': username,
          'password': password,
        }),
      );
      
      if (response.statusCode == 200) {
         String token = response.data['access_token'];
         await _storage.write(key: 'jwt_token', value: token);
         return true;
      }
      return false;
    } catch (e) {
      print('Login error: $e');
      return false;
    }
  }

  // ==========================================
  // 2. 错题管理服务
  // ==========================================
  
  Future<List<QuestionModel>> fetchQuestions({String? knowledgePoint, String? tag, bool isDeleted = false}) async {
    try {
      final response = await _dio.get('/api/v1/questions/', queryParameters: {
        if (knowledgePoint != null) 'knowledge_point': knowledgePoint,
        if (tag != null) 'tag': tag,
        'is_deleted': isDeleted,
      });
      
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['questions'];
        return data.map((e) => QuestionModel.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      print('Fetch list error: $e');
      return [];
    }
  }

  Future<bool> uploadQuestion(Uint8List imageBytes, String fileName, {bool mirror = false}) async {
    try {
      FormData formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          imageBytes, 
          filename: fileName
        ),
        'mirror': mirror.toString(),
      });

      final response = await _dio.post('/api/v1/questions/upload', data: formData);
      return response.statusCode == 200;
    } catch (e) {
       print('Upload error: $e');
       return false;
    }
  }

  Future<bool> deleteQuestion(String questionId) async {
    try {
      final response = await _dio.delete('/api/v1/questions/$questionId');
      return response.statusCode == 200;
    } catch (e) {
      print('Delete error: $e');
      return false;
    }
  }

  Future<bool> restoreQuestion(String questionId) async {
    try {
      final response = await _dio.post('/api/v1/questions/$questionId/restore');
      return response.statusCode == 200;
    } catch (e) {
      print('Restore error: $e');
      return false;
    }
  }

  Future<bool> permanentDeleteQuestion(String questionId) async {
    try {
      final response = await _dio.delete('/api/v1/questions/$questionId/permanent');
      return response.statusCode == 200;
    } catch (e) {
      print('Permanent Delete error: $e');
      return false;
    }
  }

  // ==========================================
  // 3. 标签与分类管理服务 (Requirement 2)
  // ==========================================

  Future<List<String>> fetchTags() async {
    try {
      final response = await _dio.get('/api/v1/questions/tags/all');
      if (response.statusCode == 200) {
        return List<String>.from(response.data['tags']);
      }
      return [];
    } catch (e) {
      print('Fetch tags error: $e');
      return [];
    }
  }

  Future<bool> addTag(String tag) async {
    try {
      final response = await _dio.post(
        '/api/v1/questions/tags/add',
        queryParameters: {'tag': tag},
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Add tag error: $e');
      return false;
    }
  }

  Future<bool> updateQuestionTags(String questionId, List<String> tags) async {
    try {
      final response = await _dio.post(
        '/api/v1/questions/$questionId/tags',
        data: {'tags': tags},
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Update tags error: $e');
      return false;
    }
  }
}

// 单例模式提供全局访问
final apiService = ApiService();
