import 'dart:typed_data';

enum DetectionJobStatus { queued, compressing, predicting, uploading, completed, failed, cancelled }

class AiPrediction {
  final String crop, disease, pest, severity, treatment, prevention, modelVersion;
  final double confidence;
  final Uint8List? processedImage;
  const AiPrediction({required this.crop, required this.disease, required this.pest, required this.severity, required this.treatment, required this.prevention, required this.modelVersion, required this.confidence, this.processedImage});
  factory AiPrediction.fromJson(Map<String, dynamic> json) => AiPrediction(
    crop: json['crop']?.toString() ?? '', disease: json['disease']?.toString() ?? 'Unknown', pest: json['pest']?.toString() ?? '', severity: json['severity']?.toString() ?? 'Pending review', treatment: json['treatment']?.toString() ?? '', prevention: json['prevention']?.toString() ?? '', modelVersion: json['modelVersion']?.toString() ?? 'unknown', confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
  );
}

class DetectionJob {
  final String id, name;
  final Uint8List originalBytes;
  final Uint8List? compressedBytes;
  final DetectionJobStatus status;
  final double progress;
  final AiPrediction? prediction;
  final String? imageUrl, error;
  final bool reviewRequested;
  const DetectionJob({required this.id, required this.name, required this.originalBytes, this.compressedBytes, this.status = DetectionJobStatus.queued, this.progress = 0, this.prediction, this.imageUrl, this.error, this.reviewRequested = false});
  DetectionJob copyWith({Uint8List? compressedBytes, DetectionJobStatus? status, double? progress, AiPrediction? prediction, String? imageUrl, String? error, bool? reviewRequested}) => DetectionJob(id: id, name: name, originalBytes: originalBytes, compressedBytes: compressedBytes ?? this.compressedBytes, status: status ?? this.status, progress: progress ?? this.progress, prediction: prediction ?? this.prediction, imageUrl: imageUrl ?? this.imageUrl, error: error, reviewRequested: reviewRequested ?? this.reviewRequested);
}
