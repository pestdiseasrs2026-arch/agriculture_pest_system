import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:agriculture_pest_system/core/errors/app_exception.dart';
import 'package:agriculture_pest_system/features/dashboard/domain/dashboard_metric.dart';

abstract interface class DashboardRepository {
  Stream<DashboardMetric> watchMetric(DashboardMetricType type);
}

class FirestoreDashboardRepository implements DashboardRepository {
  final FirebaseFirestore firestore;

  const FirestoreDashboardRepository(this.firestore);

  @override
  Stream<DashboardMetric> watchMetric(DashboardMetricType type) async* {
    while (true) {
      try {
        final snapshot = await firestore
            .collection(type.collection)
            .count()
            .get();
        yield DashboardMetric(
          type: type,
          value: snapshot.count ?? 0,
          updatedAt: DateTime.now(),
        );
      } catch (error, stackTrace) {
        Error.throwWithStackTrace(AppException.from(error), stackTrace);
      }
      await Future<void>.delayed(const Duration(minutes: 1));
    }
  }
}
