// services/ai_service.dart
// Service for AI report generation and summarization

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/ai_report_model.dart';
import '../models/ai_summary_model.dart';
import '../app_config.dart';

class AIService {
  static const String baseUrl = AppConfig.apiBaseUrl;

  /// Generate AI body check report
  static Future<Map<String, dynamic>> generateBodyCheckReport({
    required Map<String, dynamic> vitalData,
    required Map<String, dynamic> patientInfo,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/api/ai/generate-report');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'vitalData': vitalData,
          'patientInfo': patientInfo,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'reportId': data['reportId'],
          'report': AIReport.fromJson(data['report']),
          'message': data['message'],
        };
      } else {
        final error = jsonDecode(response.body);
        return {
          'success': false,
          'error': error['message'] ?? 'Failed to generate report',
        };
      }
    } catch (e) {
      print('❌ Generate report error: $e');
      return {
        'success': false,
        'error': 'Network error: ${e.toString()}',
      };
    }
  }

  /// Summarize report for patient
  static Future<Map<String, dynamic>> summarizeReport({
    String? reportId,
    required Map<String, dynamic> reportData,
    required Map<String, dynamic> patientInfo,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/api/ai/summarize-report');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'reportId': reportId,
          'reportData': reportData,
          'patientInfo': patientInfo,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'summaryId': data['summaryId'],
          'summary': AISummary.fromJson(data['summary']),
          'message': data['message'],
        };
      } else {
        final error = jsonDecode(response.body);
        return {
          'success': false,
          'error': error['message'] ?? 'Failed to summarize report',
        };
      }
    } catch (e) {
      print('❌ Summarize report error: $e');
      return {
        'success': false,
        'error': 'Network error: ${e.toString()}',
      };
    }
  }

  /// Send summary to patient inbox
  static Future<Map<String, dynamic>> sendSummaryToPatient({
    required String summaryId,
    required String patientId,
    String? doctorId,
    required Map<String, dynamic> summaryData,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/api/ai/send-summary-to-patient');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'summaryId': summaryId,
          'patientId': patientId,
          'doctorId': doctorId,
          'summaryData': summaryData,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'inboxMessageId': data['inboxMessageId'],
          'message': data['message'],
        };
      } else {
        final error = jsonDecode(response.body);
        return {
          'success': false,
          'error': error['message'] ?? 'Failed to send summary',
        };
      }
    } catch (e) {
      print('❌ Send summary error: $e');
      return {
        'success': false,
        'error': 'Network error: ${e.toString()}',
      };
    }
  }

  /// Get reports for patient
  static Future<Map<String, dynamic>> getPatientReports(String patientId) async {
    try {
      final url = Uri.parse('$baseUrl/api/ai/reports/$patientId');

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final reports = (data['reports'] as List<dynamic>)
            .map((r) => AIReport.fromJson(r['reportData']))
            .toList();

        return {
          'success': true,
          'reports': reports,
          'count': data['count'],
        };
      } else {
        final error = jsonDecode(response.body);
        return {
          'success': false,
          'error': error['message'] ?? 'Failed to fetch reports',
        };
      }
    } catch (e) {
      print('❌ Get reports error: $e');
      return {
        'success': false,
        'error': 'Network error: ${e.toString()}',
      };
    }
  }

  /// Get summaries for patient
  static Future<Map<String, dynamic>> getPatientSummaries(String patientId) async {
    try {
      final url = Uri.parse('$baseUrl/api/ai/summaries/$patientId');

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final summaries = (data['summaries'] as List<dynamic>)
            .map((s) => AISummary.fromJson(s['summaryData']))
            .toList();

        return {
          'success': true,
          'summaries': summaries,
          'count': data['count'],
        };
      } else {
        final error = jsonDecode(response.body);
        return {
          'success': false,
          'error': error['message'] ?? 'Failed to fetch summaries',
        };
      }
    } catch (e) {
      print('❌ Get summaries error: $e');
      return {
        'success': false,
        'error': 'Network error: ${e.toString()}',
      };
    }
  }
}