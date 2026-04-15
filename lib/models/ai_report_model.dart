// models/ai_report_model.dart
// Model for AI-generated body check reports

class AIReport {
  final String reportId;
  final String patientName;
  final String patientId;
  final DateTime date;
  final String overallRiskLevel;
  final String summary;
  final VitalSignsAnalysis vitalSignsAnalysis;
  final List<RiskAlert> riskAlerts;
  final List<String> recommendations;
  final bool followUpRequired;
  final String followUpUrgency;
  final String followUpReason;
  final DateTime generatedAt;
  final String generatedBy;

  AIReport({
    required this.reportId,
    required this.patientName,
    required this.patientId,
    required this.date,
    required this.overallRiskLevel,
    required this.summary,
    required this.vitalSignsAnalysis,
    required this.riskAlerts,
    required this.recommendations,
    required this.followUpRequired,
    required this.followUpUrgency,
    required this.followUpReason,
    required this.generatedAt,
    required this.generatedBy,
  });

  factory AIReport.fromJson(Map<String, dynamic> json) {
    return AIReport(
      reportId: json['report_id'] ?? '',
      patientName: json['patient_name'] ?? '',
      patientId: json['patient_id'] ?? '',
      date: json['date'] != null ? DateTime.parse(json['date']) : DateTime.now(),
      overallRiskLevel: json['overall_risk_level'] ?? 'low',
      summary: json['summary'] ?? '',
      vitalSignsAnalysis: VitalSignsAnalysis.fromJson(json['vital_signs_analysis'] ?? {}),
      riskAlerts: (json['risk_alerts'] as List<dynamic>?)
          ?.map((alert) => RiskAlert.fromJson(alert))
          .toList() ?? [],
      recommendations: List<String>.from(json['recommendations'] ?? []),
      followUpRequired: json['follow_up_required'] ?? false,
      followUpUrgency: json['follow_up_urgency'] ?? 'none',
      followUpReason: json['follow_up_reason'] ?? '',
      generatedAt: json['generated_at'] != null
          ? DateTime.parse(json['generated_at'])
          : DateTime.now(),
      generatedBy: json['generated_by'] ?? 'AI Assistant',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'report_id': reportId,
      'patient_name': patientName,
      'patient_id': patientId,
      'date': date.toIso8601String(),
      'overall_risk_level': overallRiskLevel,
      'summary': summary,
      'vital_signs_analysis': vitalSignsAnalysis.toJson(),
      'risk_alerts': riskAlerts.map((alert) => alert.toJson()).toList(),
      'recommendations': recommendations,
      'follow_up_required': followUpRequired,
      'follow_up_urgency': followUpUrgency,
      'follow_up_reason': followUpReason,
      'generated_at': generatedAt.toIso8601String(),
      'generated_by': generatedBy,
    };
  }
}

class VitalSignsAnalysis {
  final VitalSign? bloodPressure;
  final VitalSign? heartRate;
  final VitalSign? temperature;
  final VitalSign? oxygenSaturation;
  final VitalSign? respiratoryRate;
  final VitalSign? bloodSugar;
  final VitalSign? bmi;

  VitalSignsAnalysis({
    this.bloodPressure,
    this.heartRate,
    this.temperature,
    this.oxygenSaturation,
    this.respiratoryRate,
    this.bloodSugar,
    this.bmi,
  });

  factory VitalSignsAnalysis.fromJson(Map<String, dynamic> json) {
    return VitalSignsAnalysis(
      bloodPressure: json['blood_pressure'] != null
          ? VitalSign.fromJson(json['blood_pressure'])
          : null,
      heartRate: json['heart_rate'] != null
          ? VitalSign.fromJson(json['heart_rate'])
          : null,
      temperature: json['temperature'] != null
          ? VitalSign.fromJson(json['temperature'])
          : null,
      oxygenSaturation: json['oxygen_saturation'] != null
          ? VitalSign.fromJson(json['oxygen_saturation'])
          : null,
      respiratoryRate: json['respiratory_rate'] != null
          ? VitalSign.fromJson(json['respiratory_rate'])
          : null,
      bloodSugar: json['blood_sugar'] != null
          ? VitalSign.fromJson(json['blood_sugar'])
          : null,
      bmi: json['bmi'] != null
          ? VitalSign.fromJson(json['bmi'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'blood_pressure': bloodPressure?.toJson(),
      'heart_rate': heartRate?.toJson(),
      'temperature': temperature?.toJson(),
      'oxygen_saturation': oxygenSaturation?.toJson(),
      'respiratory_rate': respiratoryRate?.toJson(),
      'blood_sugar': bloodSugar?.toJson(),
      'bmi': bmi?.toJson(),
    };
  }
}

class VitalSign {
  final String value;
  final String status;
  final String riskLevel;
  final String interpretation;
  final String recommendation;

  VitalSign({
    required this.value,
    required this.status,
    required this.riskLevel,
    required this.interpretation,
    required this.recommendation,
  });

  factory VitalSign.fromJson(Map<String, dynamic> json) {
    return VitalSign(
      value: json['value']?.toString() ?? '',
      status: json['status'] ?? 'normal',
      riskLevel: json['risk_level'] ?? 'low',
      interpretation: json['interpretation'] ?? '',
      recommendation: json['recommendation'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'value': value,
      'status': status,
      'risk_level': riskLevel,
      'interpretation': interpretation,
      'recommendation': recommendation,
    };
  }
}

class RiskAlert {
  final String title;
  final String severity;
  final String description;
  final List<String> affectedVitals;
  final String recommendedAction;

  RiskAlert({
    required this.title,
    required this.severity,
    required this.description,
    required this.affectedVitals,
    required this.recommendedAction,
  });

  factory RiskAlert.fromJson(Map<String, dynamic> json) {
    return RiskAlert(
      title: json['title'] ?? '',
      severity: json['severity'] ?? 'low',
      description: json['description'] ?? '',
      affectedVitals: List<String>.from(json['affected_vitals'] ?? []),
      recommendedAction: json['recommended_action'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'severity': severity,
      'description': description,
      'affected_vitals': affectedVitals,
      'recommended_action': recommendedAction,
    };
  }
}