import 'package:flutter/material.dart';

enum DashboardMetricType {
  farmers('users', 'Total Farmers', Icons.people_alt_rounded, Colors.green),
  farms('farms', 'Registered Farms', Icons.home_work_rounded, Colors.blue),
  detections(
    'detections',
    'AI Detections',
    Icons.bubble_chart_rounded,
    Colors.orange,
  ),
  diseases(
    'diseases',
    'Diseases Detected',
    Icons.coronavirus_rounded,
    Colors.red,
  ),
  pests(
    'pests',
    'Pests Detected',
    Icons.pest_control_rounded,
    Colors.deepPurple,
  ),
  crops('crop_records', 'Crop Records', Icons.eco_rounded, Colors.teal),
  sensors('iot_devices', 'IoT Sensors', Icons.sensors_rounded, Colors.indigo),
  soilTests(
    'soil_tests',
    'Soil Tests',
    Icons.science_rounded,
    Colors.lightGreen,
  );

  final String collection;
  final String label;
  final IconData icon;
  final Color color;

  const DashboardMetricType(this.collection, this.label, this.icon, this.color);
}

class DashboardMetric {
  final DashboardMetricType type;
  final int value;
  final DateTime updatedAt;

  const DashboardMetric({
    required this.type,
    required this.value,
    required this.updatedAt,
  });

  bool get isEmpty => value == 0;
}
