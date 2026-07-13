import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:agriculture_pest_system/core/errors/app_exception.dart';
import 'package:agriculture_pest_system/core/config/feature_flags.dart';
import 'package:agriculture_pest_system/features/ai_detection/domain/detection_job.dart';

class AiDetectionService {
  static const endpoint = String.fromEnvironment('AI_API_URL');
  static const token = String.fromEnvironment('AI_API_TOKEN');
  final Dio dio;
  final FirebaseStorage storage;
  AiDetectionService(this.dio, this.storage);

  bool get isConfigured => endpoint.trim().isNotEmpty;

  Future<Uint8List> compress(Uint8List bytes) async {
    final result = await FlutterImageCompress.compressWithList(
      bytes,
      minWidth: 1600,
      minHeight: 1600,
      quality: 82,
      format: CompressFormat.jpeg,
    );
    if (result.isEmpty) {
      throw const DataAccessException('Image compression failed.');
    }
    return result;
  }

  Future<AiPrediction> predict({
    required Uint8List bytes,
    required String filename,
    required String crop,
    CancelToken? cancelToken,
  }) async {
    if (!FeatureFlags.instance.aiDetectionEnabled) {
      throw const DataAccessException(
        'AI detection is temporarily disabled by the system administrator.',
      );
    }
    if (!isConfigured) {
      throw const DataAccessException(
        'AI_API_URL is not configured. Run with --dart-define=AI_API_URL=https://your-api/predict.',
      );
    }
    try {
      final response = await dio.post<Map<String, dynamic>>(
        endpoint,
        data: FormData.fromMap({
          'crop': crop,
          'image': MultipartFile.fromBytes(bytes, filename: filename),
        }),
        options: Options(
          headers: token.isEmpty ? null : {'Authorization': 'Bearer $token'},
        ),
        cancelToken: cancelToken,
      );
      final body = response.data;
      if (body == null) {
        throw const DataAccessException(
          'The AI service returned an empty response.',
        );
      }
      return AiPrediction.fromJson(
        body['prediction'] is Map<String, dynamic>
            ? body['prediction'] as Map<String, dynamic>
            : body,
      );
    } on DioException catch (e) {
      throw DataAccessException(
        e.response?.data?.toString() ?? 'AI prediction request failed.',
        e,
      );
    }
  }

  Stream<double> upload({
    required Uint8List bytes,
    required String uid,
    required String id,
    required void Function(String url) onComplete,
  }) async* {
    if (!FeatureFlags.instance.uploadsEnabled) {
      throw const DataAccessException(
        'Image uploads are temporarily disabled by the system administrator.',
      );
    }
    final ref = storage.ref('detections/$uid/$id.jpg');
    final task = ref.putData(
      bytes,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    await for (final event in task.snapshotEvents) {
      yield event.totalBytes == 0
          ? 0
          : event.bytesTransferred / event.totalBytes;
      if (event.state == TaskState.success) {
        onComplete(await ref.getDownloadURL());
      }
    }
  }
}
