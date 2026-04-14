import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'app_config.dart';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = AppConfig.apiBaseUrl;
  static const Duration timeout = Duration(seconds: 30);

  /// ✅ PATIENT/DOCTOR CHAT - With proper error handling
  /// ✅ PATIENT/DOCTOR CHAT - With proper error handling
  static Future<Map<String, dynamic>> sendChat({
    required String message,
    required String role, // 'patient' or 'doctor'
    String? userId,
    List<Map<String, dynamic>>? conversationHistory,
  }) async {
    try {
      print('📤 Sending to: $baseUrl/api/chat');
      print('   Role: $role, User: $userId');

      final response = await http
          .post(
        Uri.parse('$baseUrl/api/chat'),
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
        },
        body: jsonEncode({
          "messages": [
            ...(conversationHistory ?? []),
            {
              "role": "user",
              "content": message,
            }
          ],
          "userContext": {
            "userId": userId,
            "patientId": role == 'patient' ? userId : null,
            "doctorId": role == 'doctor' ? userId : null,
          },
          "role": role,
        }),
      )
          .timeout(const Duration(seconds: 30));

      print('📥 Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        // ✅ FIX: Safe substring that handles short messages
        final msg = result['message'] ?? 'no message';
        final preview = msg.length > 50 ? msg.substring(0, 50) + '...' : msg;
        print('✅ Success: $preview');
        return result;
      } else {
        print('❌ Error response: ${response.body}');
        throw Exception('Server error: ${response.statusCode}');
      }
    } on TimeoutException {
      print('❌ Request timeout');
      throw Exception('Request timed out. Please check your internet connection.');
    } catch (e) {
      print('❌ API call failed: $e');
      rethrow;
    }
  }

  /// ✅ IMAGE CHAT — sends base64 JSON to backend Gemini Vision endpoint
  static Future<Map<String, dynamic>> sendImageChat({
    required String message,
    required Uint8List imageBytes,
    required String mimeType,
    String? patientId,
  }) async {
    try {
      print('📤 Sending image chat...');
      final imageBase64 = base64Encode(imageBytes);
      print('   Image size: ${imageBytes.length} bytes, base64: ${imageBase64.length} chars');

      final response = await http
          .post(
        Uri.parse('$baseUrl/api/chat/image'),
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
        },
        body: jsonEncode({
          "message": message,
          "imageBase64": imageBase64,
          "role": "patient",
          "userId": patientId,
        }),
      )
          .timeout(const Duration(seconds: 60));

      print('📥 Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        print('✅ Image chat successful');
        return result;
      } else {
        print('❌ Error: ${response.body}');
        throw Exception('Image chat failed: ${response.statusCode}');
      }
    } on TimeoutException {
      print('❌ Image processing timeout');
      throw Exception('Image processing timed out. Please try with a smaller image.');
    } catch (e) {
      print('❌ sendImageChat failed: $e');
      rethrow;
    }
  }

  /// ✅ BILL ANALYSIS - Uses backend
  static Future<Map<String, dynamic>> analyzeBill({
    required String imageBase64,
    String? userId,
  }) async {
    try {
      print('📤 Sending bill to backend for analysis...');
      print('   Base64 length: ${imageBase64.length} chars');

      final response = await http
          .post(
        Uri.parse('$baseUrl/api/analyze-bill'),
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
        },
        body: jsonEncode({
          "imageBase64": imageBase64,
          "userId": userId,
        }),
      )
          .timeout(const Duration(seconds: 60));

      print('📥 Backend response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        print('✅ Bill analysis successful');
        print('   Items found: ${(result['items'] as List?)?.length ?? 0}');
        return result;
      } else {
        print('❌ Backend error: ${response.statusCode}');
        print('   Response: ${response.body}');

        // Try to parse error message
        try {
          final errorData = jsonDecode(response.body);
          throw Exception(errorData['message'] ?? 'Bill analysis failed');
        } catch (_) {
          throw Exception('Backend returned ${response.statusCode}');
        }
      }
    } on TimeoutException {
      print('❌ Bill analysis timeout');
      throw Exception('Analysis timed out. Please try with a clearer or smaller image.');
    } on http.ClientException catch (e) {
      print('❌ Connection failed: $e');
      throw Exception('Cannot connect to server. Please check your internet connection.');
    } catch (e) {
      print('❌ Bill analysis failed: $e');
      rethrow;
    }
  }

  /// ✅ HEALTH CHECK
  static Future<bool> checkHealth() async {
    try {
      print('🏥 Checking backend health...');

      final response = await http
          .get(Uri.parse('$baseUrl/api/health'))
          .timeout(const Duration(seconds: 10));

      print('   Health check: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('   Status: ${data['status']}');
        return data['status'] == 'healthy';
      }

      return false;
    } catch (e) {
      print('❌ Health check failed: $e');
      return false;
    }
  }
}