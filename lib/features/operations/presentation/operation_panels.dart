import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:agriculture_pest_system/features/operations/providers/operation_providers.dart';
import 'package:agriculture_pest_system/features/operations/domain/operation_models.dart';

class SoilHistoryPanel extends ConsumerWidget {
  final String uid;
  const SoilHistoryPanel({super.key, required this.uid});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(soilSamplesProvider(uid)).when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorState('$error'),
      data: (items) => items.isEmpty
          ? const _EmptyState('No soil samples yet.')
          : Column(
              children: items.map((sample) {
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.science_outlined),
                    title: Text(sample.name),
                    subtitle: Text(
                      'pH: ${sample.ph?.toStringAsFixed(1) ?? '—'} • ${sample.interpretation}',
                    ),
                    trailing: Chip(label: Text(sample.status)),
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class FertilizerHistoryPanel extends ConsumerWidget {
  final String uid;
  const FertilizerHistoryPanel({super.key, required this.uid});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(fertilizerStockProvider(uid)).when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorState('$error'),
      data: (items) => items.isEmpty
          ? const _EmptyState('No fertilizer stock yet.')
          : Column(
              children: items.map((stock) {
                final status = stock.expiringSoon
                    ? 'Expiring'
                    : stock.lowStock
                    ? 'Low stock'
                    : 'In stock';
                return Card(
                  child: ListTile(
                    leading: Icon(
                      stock.lowStock
                          ? Icons.warning_amber
                          : Icons.inventory_2_outlined,
                    ),
                    title: Text(stock.name),
                    subtitle: Text(
                      '${stock.category} • ${stock.quantity.toStringAsFixed(1)} available',
                    ),
                    trailing: Chip(label: Text(status)),
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class SensorOverviewPanel extends ConsumerWidget {
  final String uid;
  const SensorOverviewPanel({super.key, required this.uid});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final realtime = ref.watch(liveSensorMapProvider(uid));
    return realtime.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorState('$error'),
      data: (map) {
        if (map.isEmpty) {
          return const _EmptyState('No live sensor readings yet.');
        }
        final sensor = SensorReading.fromMap('live', map);
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [SizedBox(
              width: 280,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(sensor.deviceName,
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        Chip(label: Text(sensor.stale ? 'Offline' : sensor.status)),
                      ]),
                      Text(sensor.location),
                      const Divider(),
                      Text('Soil moisture: ${sensor.soilMoisture?.toStringAsFixed(1) ?? '—'}%'),
                      Text('Air temperature: ${sensor.airTemperature?.toStringAsFixed(1) ?? '—'}°C'),
                      Text('Humidity: ${sensor.airHumidity?.toStringAsFixed(1) ?? '—'}%'),
                      Text('Soil pH: ${sensor.soilPh?.toStringAsFixed(1) ?? '—'}'),
                      Text('Battery: ${sensor.battery?.toStringAsFixed(0) ?? '—'}%'),
                      Text('Signal: ${sensor.signalStrength?.toStringAsFixed(0) ?? '—'}%'),
                      if (sensor.lowBattery || sensor.weakSignal || sensor.thresholdAlert)
                        const ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.warning_amber),
                          title: Text('Device attention required'),
                          subtitle: Text('Check thresholds, battery, and signal quality.'),
                        ),
                    ],
                  ),
                ),
              ),
            )],
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState(this.message);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inbox_outlined),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
      );
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState(this.message);
  @override
  Widget build(BuildContext context) => Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: ListTile(
          leading: const Icon(Icons.error_outline),
          title: const Text('Unable to load data'),
          subtitle: Text(message),
        ),
      );
}
