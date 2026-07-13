import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:agriculture_pest_system/core/repositories/feature_repositories.dart';
import 'package:agriculture_pest_system/core/repositories/data_lifecycle_repository.dart';

final authProfileRepositoryProvider = Provider(
  (ref) =>
      AuthProfileRepository(FirebaseAuth.instance, FirebaseFirestore.instance),
);
final farmCropRepositoryProvider = Provider(
  (ref) => FarmCropRepository(FirebaseFirestore.instance),
);
final detectionRepositoryProvider = Provider(
  (ref) => DetectionRecommendationRepository(
    FirebaseFirestore.instance,
    FirebaseStorage.instance,
  ),
);
final operationsRepositoryProvider = Provider(
  (ref) => OperationsRepository(
    FirebaseFirestore.instance,
    FirebaseDatabase.instance,
  ),
);
final adminReportingRepositoryProvider = Provider(
  (ref) => AdminReportingRepository(
    FirebaseFirestore.instance,
    FirebaseDatabase.instance,
  ),
);
final dataLifecycleRepositoryProvider = Provider(
  (ref) => DataLifecycleRepository(FirebaseFirestore.instance),
);
final deletionRequestProvider = StreamProvider.autoDispose.family(
  (ref, String uid) =>
      ref.watch(dataLifecycleRepositoryProvider).watchDeletionRequest(uid),
);

final farmsProvider = StreamProvider.autoDispose.family(
  (ref, String uid) => ref.watch(farmCropRepositoryProvider).farms(uid),
);
final cropsProvider = StreamProvider.autoDispose.family(
  (ref, String uid) => ref.watch(farmCropRepositoryProvider).crops(uid),
);
final detectionsProvider = StreamProvider.autoDispose.family(
  (ref, String uid) => ref.watch(detectionRepositoryProvider).detections(uid),
);
final recommendationsProvider = StreamProvider.autoDispose.family(
  (ref, String uid) =>
      ref.watch(detectionRepositoryProvider).recommendations(uid),
);

class OperationController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}
  Future<void> run(Future<void> Function() operation) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(operation);
  }
}

final operationControllerProvider =
    AsyncNotifierProvider<OperationController, void>(OperationController.new);
