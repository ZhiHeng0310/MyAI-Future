import 'package:flutter/material.dart';

class AppointmentDetailsScreen extends StatelessWidget {
  final String appointmentId;

  const AppointmentDetailsScreen({
    super.key,
    required this.appointmentId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Appointment Details"),
      ),
      body: Center(
        child: Text("Appointment ID: $appointmentId"),
      ),
    );
  }
}