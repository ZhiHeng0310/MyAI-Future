import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http/http.dart' as http_parser;

class ApiService {
  static const String baseUrl = "https://backend-362769739395.asia-southeast1.run.app";
  // e.g. https://careloop-backend.onrender.com

  /// TEXT CHAT (you already have something like this)
  static Future<Map<String, dynamic>> sendChat({
    required String message,
    String? patientId,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/chat'),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "message": message,
        "patientId": patientId,
      }),
    );

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