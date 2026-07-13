enum UserRole { farmer, admin, agriculturalOfficer;
  String get displayName => switch (this) { farmer => 'Farmer', admin => 'Admin', agriculturalOfficer => 'Agricultural Officer' };
}
enum AccountStatus { active, pending, suspended;
  String get displayName => switch (this) { active => 'Active', pending => 'Pending', suspended => 'Suspended' };
}

class FarmProfile {
  final String id, farmerId, name, location, size, crops;
  const FarmProfile({required this.id, required this.farmerId, required this.name, required this.location, required this.size, required this.crops});
  Map<String, dynamic> toMap() => {'id': id, 'farmerId': farmerId, 'name': name, 'location': location, 'size': size, 'crops': crops};
  factory FarmProfile.fromMap(Map<String, dynamic> data, {String? id}) => FarmProfile(id: id ?? data['id']?.toString() ?? '', farmerId: data['farmerId']?.toString() ?? '', name: data['name']?.toString() ?? '', location: data['location']?.toString() ?? '', size: data['size']?.toString() ?? '', crops: data['crops']?.toString() ?? '');
}

class CropRecord {
  final String id, farmerId, cropName, variety, plantingDate, harvestDate, notes;
  const CropRecord({required this.id, required this.farmerId, required this.cropName, required this.variety, required this.plantingDate, required this.harvestDate, required this.notes});
  Map<String, dynamic> toMap() => {'id': id, 'farmerId': farmerId, 'cropName': cropName, 'variety': variety, 'plantingDate': plantingDate, 'harvestDate': harvestDate, 'notes': notes};
  factory CropRecord.fromMap(Map<String, dynamic> data) => CropRecord(id: data['id']?.toString() ?? '', farmerId: data['farmerId']?.toString() ?? '', cropName: data['cropName']?.toString() ?? '', variety: data['variety']?.toString() ?? '', plantingDate: data['plantingDate']?.toString() ?? '', harvestDate: data['harvestDate']?.toString() ?? '', notes: data['notes']?.toString() ?? '');
}

class DetectionRecord {
  final String id, farmerId, cropType, diseaseName, confidenceScore, severity, imageURL, date;
  const DetectionRecord({required this.id, required this.farmerId, required this.cropType, required this.diseaseName, required this.confidenceScore, required this.severity, required this.imageURL, required this.date});
  Map<String, dynamic> toMap() => {'id': id, 'farmerId': farmerId, 'cropType': cropType, 'diseaseName': diseaseName, 'confidenceScore': confidenceScore, 'severity': severity, 'imageURL': imageURL, 'date': date};
  factory DetectionRecord.fromMap(Map<String, dynamic> data) => DetectionRecord(id: data['id']?.toString() ?? '', farmerId: data['farmerId']?.toString() ?? '', cropType: data['cropType']?.toString() ?? '', diseaseName: data['diseaseName']?.toString() ?? '', confidenceScore: data['confidenceScore']?.toString() ?? '0.00', severity: data['severity']?.toString() ?? 'Moderate', imageURL: data['imageURL']?.toString() ?? '', date: data['date']?.toString() ?? '');
}

class RecommendationRecord {
  final String id, farmerId, crop, issue, diseaseRecommendation, pestRecommendation, treatmentRecommendation, fertilizerRecommendation, createdAt;
  const RecommendationRecord({required this.id, required this.farmerId, required this.crop, required this.issue, required this.diseaseRecommendation, required this.pestRecommendation, required this.treatmentRecommendation, required this.fertilizerRecommendation, required this.createdAt});
  factory RecommendationRecord.fromMap(Map<String, dynamic> data) => RecommendationRecord(id: data['id']?.toString() ?? '', farmerId: data['farmerId']?.toString() ?? '', crop: data['crop']?.toString() ?? '', issue: data['issue']?.toString() ?? '', diseaseRecommendation: data['diseaseRecommendation']?.toString() ?? '', pestRecommendation: data['pestRecommendation']?.toString() ?? '', treatmentRecommendation: data['treatmentRecommendation']?.toString() ?? '', fertilizerRecommendation: data['fertilizerRecommendation']?.toString() ?? '', createdAt: data['createdAt']?.toString() ?? '');
}

class KnowledgeEntry {
  final String id, title, category, description, symptoms, causes, preventionMethods, treatmentMethods, imageUrl, createdAt;
  const KnowledgeEntry({required this.id, required this.title, required this.category, required this.description, required this.symptoms, required this.causes, required this.preventionMethods, required this.treatmentMethods, required this.imageUrl, required this.createdAt});
  factory KnowledgeEntry.fromMap(Map<String, dynamic> data) => KnowledgeEntry(id: data['id']?.toString() ?? '', title: data['title']?.toString() ?? '', category: data['category']?.toString() ?? '', description: data['description']?.toString() ?? '', symptoms: data['symptoms']?.toString() ?? '', causes: data['causes']?.toString() ?? '', preventionMethods: data['preventionMethods']?.toString() ?? '', treatmentMethods: data['treatmentMethods']?.toString() ?? '', imageUrl: data['imageUrl']?.toString() ?? '', createdAt: data['createdAt']?.toString() ?? '');
}

class FarmActivity {
  final String id, farmerId, title, description, timestamp;
  const FarmActivity({required this.id, required this.farmerId, required this.title, required this.description, required this.timestamp});
  Map<String, dynamic> toMap() => {'id': id, 'farmerId': farmerId, 'title': title, 'description': description, 'timestamp': timestamp};
  factory FarmActivity.fromMap(Map<String, dynamic> data) => FarmActivity(id: data['id']?.toString() ?? '', farmerId: data['farmerId']?.toString() ?? '', title: data['title']?.toString() ?? '', description: data['description']?.toString() ?? '', timestamp: data['timestamp']?.toString() ?? '');
}

class UserProfile {
  final String uid, fullName, email, phone, location, profileImage, authProvider;
  final UserRole role;
  final AccountStatus accountStatus;
  const UserProfile({required this.uid, required this.fullName, required this.email, required this.phone, required this.location, required this.profileImage, required this.authProvider, required this.role, required this.accountStatus});
  factory UserProfile.fromMap(Map<String, dynamic> data, {required String uid}) => UserProfile(uid: uid, fullName: data['name']?.toString() ?? 'User', email: data['email']?.toString() ?? '', phone: data['phone']?.toString() ?? '', location: data['location']?.toString() ?? '', profileImage: data['profileImage']?.toString() ?? '', authProvider: data['authProvider']?.toString() ?? 'email', role: UserRole.values.firstWhere((v) => v.name == data['role'], orElse: () => UserRole.farmer), accountStatus: AccountStatus.values.firstWhere((v) => v.name == data['accountStatus'], orElse: () => AccountStatus.active));
  Map<String, dynamic> toMap() => {'name': fullName, 'email': email, 'phone': phone, 'location': location, 'profileImage': profileImage, 'authProvider': authProvider, 'role': role.name, 'accountStatus': accountStatus.name};
  UserProfile copyWith({String? uid, String? fullName, String? email, String? phone, String? location, String? profileImage, String? authProvider, UserRole? role, AccountStatus? accountStatus}) => UserProfile(uid: uid ?? this.uid, fullName: fullName ?? this.fullName, email: email ?? this.email, phone: phone ?? this.phone, location: location ?? this.location, profileImage: profileImage ?? this.profileImage, authProvider: authProvider ?? this.authProvider, role: role ?? this.role, accountStatus: accountStatus ?? this.accountStatus);
}
