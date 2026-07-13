import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:agriculture_pest_system/core/providers/repository_providers.dart';
import 'package:agriculture_pest_system/features/operations/domain/operation_models.dart';

final soilSamplesProvider = StreamProvider.autoDispose.family<List<SoilSample>, String>((ref, uid) => ref.watch(operationsRepositoryProvider).watch('soil_samples', ownerId: uid).map((s) => s.docs.map((d) => SoilSample.fromMap(d.id, d.data())).toList()..sort((a,b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)))));
final fertilizerStockProvider = StreamProvider.autoDispose.family<List<FertilizerStock>, String>((ref, uid) => ref.watch(operationsRepositoryProvider).watch('fertilizers', ownerId: uid).map((s) => s.docs.map((d) => FertilizerStock.fromMap(d.id, d.data())).toList()));
final sensorReadingsProvider = StreamProvider.autoDispose.family<List<SensorReading>, String>((ref, uid) => ref.watch(operationsRepositoryProvider).watch('sensor_readings', ownerId: uid).map((s) => s.docs.map((d) => SensorReading.fromMap(d.id, d.data())).toList()..sort((a,b) => (b.timestamp ?? DateTime(0)).compareTo(a.timestamp ?? DateTime(0)))));
final liveSensorMapProvider = StreamProvider.autoDispose
    .family<Map<String, dynamic>, String>(
      (ref, uid) => ref
          .watch(operationsRepositoryProvider)
          .watchRealtimeMap('sensor_readings/$uid'),
    );
final mapLocationsProvider = StreamProvider.autoDispose.family<List<MapLocationRecord>, String>((ref, uid) async* { final repo = ref.watch(operationsRepositoryProvider); final streams = ['farm_locations','disease_locations','pest_locations'].map((c) => repo.watch(c, ownerId: uid)); for (final stream in streams) { await for (final s in stream) { yield s.docs.map((d) => MapLocationRecord.fromMap(d.id, d.data())).toList(); break; } } });
