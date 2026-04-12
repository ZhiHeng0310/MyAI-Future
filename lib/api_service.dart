import 'dart:convert';
import 'dart:typed_data';
import 'app_config.dart';
import 'package:http/http.dart' as http;
import 'package:http/http.dart' as http_parser;

class ApiService {
  static const String baseUrl = AppConfig.apiBaseUrl;

  /// TEXT CHAT (you already have something like this)
  static Future<Map<String, dynamic>> sendChat({
    required String message,
    required String role, // 'patient' or 'doctor'
    String? userId,
    List<Map<String, dynamic>>? conversationHistory,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/chat'),
      headers: {"Content-Type": "application/json"},
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
        "role": role, // Must be 'patient' or 'doctor'
      }),
    );

    if (res.statusCode != 200) {
      throw Exception('API Error: ${res.statusCode} - ${res.body}');
    }

    return jsonDecode(res.body);
  }

  /// ✅ IMAGE CHAT (NEW)
  static Future<Map<String, dynamic>> sendImageChat({
    required String message,
    required Uint8List imageBytes,
    required String mimeType,
    String? patientId,
  }) async {
    final request = http.MultipartRequest(
      "POST",
        Uri.parse('$baseUrl/api/chat/image')
    );

    request.fields["message"] = message;
    if (patientId != null) {
      request.fields["patientId"] = patientId;
    }

    request.files.add(
      http.MultipartFile.fromBytes(
        "image",
        imageBytes,
        filename: "upload.jpg",
        contentType: http_parser.MediaType.parse(mimeType),
      ),
    );

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    return jsonDecode(response.body);
  }
}