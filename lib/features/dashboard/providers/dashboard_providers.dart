import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:agriculture_pest_system/features/dashboard/data/dashboard_repository.dart';
import 'package:agriculture_pest_system/features/dashboard/domain/dashboard_metric.dart';

final firestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
);

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => FirestoreDashboardRepository(ref.watch(firestoreProvider)),
);

final dashboardMetricProvider = StreamProvider.autoDispose
    .family<DashboardMetric, DashboardMetricType>(
      (ref, type) => ref.watch(dashboardRepositoryProvider).watchMetric(type),
    );
