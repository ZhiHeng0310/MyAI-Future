// models/ai_summary_model.dart
// Model for patient-friendly report summaries

class AISummary {
  final String summaryId;
  final String patientName;
  final String patientId;
  final DateTime date;
  final String overallStatus;
  final String riskLevel;
  final String riskExplanation;
  final List<KeyFinding> keyFindings;
  final String whatThisMeans;
  final List<String> thingsToWatch;
  final List<NextStep> nextSteps;
  final List<String> questionsToAskDoctor;
  final List<String> positiveNotes;
  final DateTime generatedAt;
  final String? originalReportId;

  AISummary({
    required this.summaryId,
    required this.patientName,
    required this.patientId,
    required this.date,
    required this.overallStatus,
    required this.riskLevel,
    required this.riskExplanation,
    required this.keyFindings,
    required this.whatThisMeans,
    required this.thingsToWatch,
    required this.nextSteps,
    required this.questionsToAskDoctor,
    required this.positiveNotes,
    required this.generatedAt,
    this.originalReportId,
  });

  factory AISummary.fromJson(Map<String, dynamic> json) {
    return AISummary(
      summaryId: json['summary_id'] ?? '',
      patientName: json['patient_name'] ?? '',
      patientId: json['patient_id'] ?? '',
      date: json['date'] != null ? DateTime.parse(json['date']) : DateTime.now(),
      overallStatus: json['overall_status'] ?? '',
      riskLevel: json['risk_level'] ?? 'low',
      riskExplanation: json['risk_explanation'] ?? '',
      keyFindings: (json['key_findings'] as List<dynamic>?)
          ?.map((finding) => KeyFinding.fromJson(finding))
          .toList() ?? [],
      whatThisMeans: json['what_this_means'] ?? '',
      thingsToWatch: List<String>.from(json['things_to_watch'] ?? []),
      nextSteps: (json['next_steps'] as List<dynamic>?)
          ?.map((step) => NextStep.fromJson(step))
          .toList() ?? [],
      questionsToAskDoctor: List<String>.from(json['questions_to_ask_doctor'] ?? []),
      positiveNotes: List<String>.from(json['positive_notes'] ?? []),
      generatedAt: json['generated_at'] != null
          ? DateTime.parse(json['generated_at'])
          : DateTime.now(),
      originalReportId: json['original_report_id'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'summary_id': summaryId,
      'patient_name': patientName,
      'patient_id': patientId,
      'date': date.toIso8601String(),
      'overall_status': overallStatus,
      'risk_level': riskLevel,
      'risk_explanation': riskExplanation,
      'key_findings': keyFindings.map((f) => f.toJson()).toList(),
      'what_this_means': whatThisMeans,
      'things_to_watch': thingsToWatch,
      'next_steps': nextSteps.map((s) => s.toJson()).toList(),
      'questions_to_ask_doctor': questionsToAskDoctor,
      'positive_notes': positiveNotes,
      'generated_at': generatedAt.toIso8601String(),
      'original_report_id': originalReportId,
    };
  }
}

class KeyFinding {
  final String title;
  final String status;
  final String explanation;
  final String icon;

  KeyFinding({
    required this.title,
    required this.status,
    required this.explanation,
    required this.icon,
  });

  factory KeyFinding.fromJson(Map<String, dynamic> json) {
    return KeyFinding(
      title: json['title'] ?? '',
      status: json['status'] ?? 'good',
      explanation: json['explanation'] ?? '',
      icon: json['icon'] ?? '✓',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'status': status,
      'explanation': explanation,
      'icon': icon,
    };
  }
}

class NextStep {
  final String action;
  final String urgency;
  final String reason;

  NextStep({
    required this.action,
    required this.urgency,
    required this.reason,
  });

  factory NextStep.fromJson(Map<String, dynamic> json) {
    return NextStep(
      action: json['action'] ?? '',
      urgency: json['urgency'] ?? 'routine',
      reason: json['reason'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'action': action,
      'urgency': urgency,
      'reason': reason,
    };
  }
}