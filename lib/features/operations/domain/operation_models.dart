class SoilSample {
  final String id, name, status, notes;
  final double? ph, nitrogen, phosphorus, potassium, organicMatter, moisture;
  final DateTime? createdAt;
  const SoilSample({required this.id, required this.name, required this.status, required this.notes, this.ph, this.nitrogen, this.phosphorus, this.potassium, this.organicMatter, this.moisture, this.createdAt});
  factory SoilSample.fromMap(String id, Map<String, dynamic> d) => SoilSample(id: id, name: d['sampleName']?.toString() ?? 'Sample', status: d['status']?.toString() ?? 'Pending', notes: d['notes']?.toString() ?? '', ph: double.tryParse('${d['ph'] ?? ''}'), nitrogen: double.tryParse('${d['nitrogen'] ?? ''}'), phosphorus: double.tryParse('${d['phosphorus'] ?? ''}'), potassium: double.tryParse('${d['potassium'] ?? ''}'), organicMatter: double.tryParse('${d['organicMatter'] ?? ''}'), moisture: double.tryParse('${d['moisture'] ?? ''}'), createdAt: DateTime.tryParse(d['createdAt']?.toString() ?? ''));
  String get interpretation => ph == null ? 'Awaiting laboratory values' : ph! < 5.5 ? 'Strongly acidic soil' : ph! > 7.5 ? 'Alkaline soil' : 'pH within common crop range';
}

class FertilizerStock {
  final String id, name, category, supplier, usage;
  final double quantity, reorderLevel;
  final DateTime? expiryDate, createdAt;
  const FertilizerStock({required this.id, required this.name, required this.category, required this.supplier, required this.usage, required this.quantity, required this.reorderLevel, this.expiryDate, this.createdAt});
  factory FertilizerStock.fromMap(String id, Map<String, dynamic> d) => FertilizerStock(id: id, name: d['name']?.toString() ?? 'Fertilizer', category: d['category']?.toString() ?? '', supplier: d['supplier']?.toString() ?? '', usage: d['usage']?.toString() ?? '', quantity: double.tryParse('${d['stock'] ?? d['quantity'] ?? 0}') ?? 0, reorderLevel: double.tryParse('${d['reorderLevel'] ?? 10}') ?? 10, expiryDate: DateTime.tryParse(d['expiryDate']?.toString() ?? ''), createdAt: DateTime.tryParse(d['createdAt']?.toString() ?? ''));
  bool get lowStock => quantity <= reorderLevel;
  bool get expiringSoon => expiryDate != null && expiryDate!.isBefore(DateTime.now().add(const Duration(days: 30)));
}

class SensorReading {
  final String id, deviceName, location, status;
  final double? soilMoisture, soilTemperature, airTemperature, airHumidity, soilPh, rainfall, lightIntensity, waterLevel, battery, signalStrength;
  final DateTime? timestamp;
  const SensorReading({required this.id, required this.deviceName, required this.location, required this.status, this.soilMoisture, this.soilTemperature, this.airTemperature, this.airHumidity, this.soilPh, this.rainfall, this.lightIntensity, this.waterLevel, this.battery, this.signalStrength, this.timestamp});
  factory SensorReading.fromMap(String id, Map<String, dynamic> d) => SensorReading(id: id, deviceName: d['deviceName']?.toString() ?? 'Sensor Unit', location: d['location']?.toString() ?? '', status: d['status']?.toString() ?? 'Unknown', soilMoisture: double.tryParse('${d['soilMoisture'] ?? ''}'), soilTemperature: double.tryParse('${d['soilTemperature'] ?? ''}'), airTemperature: double.tryParse('${d['airTemperature'] ?? ''}'), airHumidity: double.tryParse('${d['airHumidity'] ?? ''}'), soilPh: double.tryParse('${d['soilPh'] ?? ''}'), rainfall: double.tryParse('${d['rainfall'] ?? ''}'), lightIntensity: double.tryParse('${d['lightIntensity'] ?? ''}'), waterLevel: double.tryParse('${d['waterLevel'] ?? ''}'), battery: double.tryParse('${d['battery'] ?? ''}'), signalStrength: double.tryParse('${d['signalStrength'] ?? ''}'), timestamp: DateTime.tryParse(d['timestamp']?.toString() ?? ''));
  bool get stale => timestamp == null || DateTime.now().difference(timestamp!).inMinutes > 30;
  bool get lowBattery => battery != null && battery! < 20;
  bool get weakSignal => signalStrength != null && signalStrength! < 30;
  bool get thresholdAlert => (soilMoisture != null && soilMoisture! < 25) || (airTemperature != null && airTemperature! > 38) || (soilPh != null && (soilPh! < 5 || soilPh! > 8));
}

class MapLocationRecord {
  final String id, label, layer, address, notes;
  final double latitude, longitude;
  const MapLocationRecord({required this.id, required this.label, required this.layer, required this.address, required this.notes, required this.latitude, required this.longitude});
  factory MapLocationRecord.fromMap(String id, Map<String, dynamic> d) => MapLocationRecord(id: id, label: d['label']?.toString() ?? 'Mapped location', layer: d['layer']?.toString() ?? 'farm', address: d['address']?.toString() ?? '', notes: d['notes']?.toString() ?? '', latitude: (d['latitude'] as num?)?.toDouble() ?? 0, longitude: (d['longitude'] as num?)?.toDouble() ?? 0);
}
