import 'package:dio/dio.dart';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:agriculture_pest_system/features/ai_detection/data/ai_detection_service.dart';
import 'package:agriculture_pest_system/features/ai_detection/domain/detection_job.dart';
final aiDetectionServiceProvider = Provider((ref) => AiDetectionService(Dio(BaseOptions(connectTimeout: const Duration(seconds: 20), receiveTimeout: const Duration(seconds: 90))), FirebaseStorage.instance));

class DetectionJobsController extends Notifier<List<DetectionJob>> {
  @override List<DetectionJob> build() => const [];
  final _cancels = <String, CancelToken>{};
  void add(String name, List<int> bytes) { final id = '${DateTime.now().microsecondsSinceEpoch}-${state.length}'; state = [...state, DetectionJob(id: id, name: name, originalBytes: Uint8List.fromList(bytes))]; }
  void remove(String id) => state = state.where((j) => j.id != id).toList();
  void cancel(String id) { _cancels.remove(id)?.cancel(); _set(id, (j) => j.copyWith(status: DetectionJobStatus.cancelled, progress: 0)); }
  Future<void> retry(String id, String crop, String uid) => process(id, crop, uid);
  Future<void> process(String id, String crop, String uid) async {
    final service = ref.read(aiDetectionServiceProvider); final token = CancelToken(); _cancels[id] = token;
    try {
      _set(id, (j) => j.copyWith(status: DetectionJobStatus.compressing, progress: .05, error: null));
      final source = state.firstWhere((j) => j.id == id); final compressed = await service.compress(source.originalBytes);
      _set(id, (j) => j.copyWith(compressedBytes: compressed, status: DetectionJobStatus.predicting, progress: .2));
      final prediction = await service.predict(bytes: compressed, filename: source.name, crop: crop, cancelToken: token);
      _set(id, (j) => j.copyWith(prediction: prediction, status: DetectionJobStatus.uploading, progress: .45));
      String? url;
      await for (final progress in service.upload(bytes: compressed, uid: uid, id: id, onComplete: (value) => url = value)) { _set(id, (j) => j.copyWith(status: DetectionJobStatus.uploading, progress: .45 + progress * .55)); }
      _set(id, (j) => j.copyWith(status: DetectionJobStatus.completed, progress: 1, imageUrl: url));
    } catch (error) { if (!token.isCancelled) _set(id, (j) => j.copyWith(status: DetectionJobStatus.failed, error: error.toString())); }
    finally { _cancels.remove(id); }
  }
  void markReviewRequested(String id) => _set(id, (j) => j.copyWith(reviewRequested: true));
  void _set(String id, DetectionJob Function(DetectionJob) update) => state = [for (final job in state) if (job.id == id) update(job) else job];
}
final detectionJobsProvider = NotifierProvider<DetectionJobsController, List<DetectionJob>>(DetectionJobsController.new);
