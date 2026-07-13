import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart' hide Query;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:agriculture_pest_system/core/errors/app_exception.dart';
import 'package:agriculture_pest_system/core/data/query_limits.dart';
import 'package:agriculture_pest_system/core/models/app_models.dart';

class AuthProfileRepository {
  final FirebaseAuth auth;
  final FirebaseFirestore db;
  const AuthProfileRepository(this.auth, this.db);
  Stream<User?> watchUser() => auth.authStateChanges();
  Future<UserProfile?> profile(String uid) async {
    try {
      final d = await db.collection('users').doc(uid).get();
      return d.data() == null ? null : UserProfile.fromMap(d.data()!, uid: uid);
    } catch (e) {
      throw AppException.from(e);
    }
  }

  Future<UserCredential> register(String email, String password) async {
    try {
      return await auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      throw AppException.from(e);
    }
  }

  Future<UserCredential> login(String email, String password) async {
    try {
      return await auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      throw AppException.from(e);
    }
  }

  Future<void> save(UserProfile value, {bool merge = true}) async {
    try {
      await db
          .collection('users')
          .doc(value.uid)
          .set(value.toMap(), SetOptions(merge: merge));
    } catch (e) {
      throw AppException.from(e);
    }
  }

  Future<void> resetPassword(String email) =>
      auth.sendPasswordResetEmail(email: email);
  Future<void> logout() => auth.signOut();
}

class FarmCropRepository {
  final FirebaseFirestore db;
  const FarmCropRepository(this.db);
  Stream<List<FarmProfile>> farms(String uid) => db
      .collection('farms')
      .where('farmerId', isEqualTo: uid)
      .limit(QueryLimits.liveRecords)
      .snapshots()
      .map(
        (s) =>
            s.docs.map((d) => FarmProfile.fromMap(d.data(), id: d.id)).toList(),
      );
  Stream<List<CropRecord>> crops(String uid) => db
      .collection('cropRecords')
      .where('farmerId', isEqualTo: uid)
      .limit(QueryLimits.liveRecords)
      .snapshots()
      .map((s) => s.docs.map((d) => CropRecord.fromMap(d.data())).toList());
  Future<void> addFarm(FarmProfile value) async {
    try {
      await db.collection('farms').add(value.toMap());
    } catch (e) {
      throw AppException.from(e);
    }
  }

  Future<void> addCrop(CropRecord value) async {
    try {
      await db.collection('cropRecords').add(value.toMap());
    } catch (e) {
      throw AppException.from(e);
    }
  }
}

class DetectionRecommendationRepository {
  final FirebaseFirestore db;
  final FirebaseStorage storage;
  const DetectionRecommendationRepository(this.db, this.storage);
  Stream<List<DetectionRecord>> detections(String uid) => db
      .collection('detections')
      .where('farmerId', isEqualTo: uid)
      .limit(QueryLimits.liveRecords)
      .snapshots()
      .map(
        (s) => s.docs.map((d) => DetectionRecord.fromMap(d.data())).toList(),
      );
  Stream<List<RecommendationRecord>> recommendations(String uid) => db
      .collection('recommendations')
      .where('farmerId', isEqualTo: uid)
      .limit(QueryLimits.liveRecords)
      .snapshots()
      .map(
        (s) =>
            s.docs.map((d) => RecommendationRecord.fromMap(d.data())).toList(),
      );
  Future<String> upload(File file, String uid) async {
    try {
      final ref = storage.ref(
        'detections/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await ref.putFile(file);
      return ref.getDownloadURL();
    } catch (e) {
      throw AppException.from(e);
    }
  }

  Future<void> saveDetection(DetectionRecord value) async {
    try {
      await db.collection('detections').add(value.toMap());
    } catch (e) {
      throw AppException.from(e);
    }
  }

  Future<void> saveRecommendation(Map<String, dynamic> value) async {
    try {
      await db.collection('recommendations').add({
        ...value,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw AppException.from(e);
    }
  }
}

class OperationsRepository {
  final FirebaseFirestore db;
  final FirebaseDatabase realtime;
  const OperationsRepository(this.db, this.realtime);
  Stream<QuerySnapshot<Map<String, dynamic>>> watch(
    String collection, {
    String? ownerId,
  }) {
    var q = db.collection(collection) as Query<Map<String, dynamic>>;
    if (ownerId != null) q = q.where('farmerId', isEqualTo: ownerId);
    return q.limit(QueryLimits.liveRecords).snapshots();
  }

  Future<DocumentReference<Map<String, dynamic>>> add(
    String collection,
    Map<String, dynamic> data,
  ) async {
    try {
      return await db.collection(collection).add({
        ...data,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw AppException.from(e);
    }
  }

  Future<void> writeSensor(String path, Map<String, dynamic> data) async {
    try {
      await realtime.ref(path).set(data);
    } catch (e) {
      throw AppException.from(e);
    }
  }

  Stream<Map<String, dynamic>> watchRealtimeMap(String path) => realtime
      .ref(path)
      .onValue
      .map(
        (event) => event.snapshot.value is Map
            ? Map<String, dynamic>.from(event.snapshot.value as Map)
            : <String, dynamic>{},
      );

  Future<void> saveSoilAnalysis(Map<String, dynamic> data) async {
    try {
      final write = db.batch();
      write.set(db.collection('soil_samples').doc(), data);
      write.set(db.collection('soil_tests').doc(), data);
      write.set(db.collection('soil_recommendations').doc(), {
        'farmerId': data['farmerId'],
        'sampleId': data['sampleId'],
        'recommendation': data['recommendation'],
        'createdAt': FieldValue.serverTimestamp(),
      });
      await write.commit();
    } catch (error) {
      throw AppException.from(error);
    }
  }

  Future<void> recordInventoryTransaction({
    required String uid,
    required String itemId,
    required String name,
    required double quantity,
    required double reorderLevel,
    required String transactionType,
    DateTime? expiryDate,
  }) async {
    final item = db.collection('fertilizers').doc(itemId);
    try {
      await db.runTransaction((transaction) async {
        final snapshot = await transaction.get(item);
        final current = (snapshot.data()?['stock'] as num?)?.toDouble() ?? 0;
        final next = transactionType == 'stock_out'
            ? current - quantity
            : current + quantity;
        if (next < 0) {
          throw const DataAccessException('Insufficient fertilizer stock.');
        }
        transaction.set(item, {
          'farmerId': uid,
          'name': name,
          'stock': next,
          'reorderLevel': reorderLevel,
          'expiryDate': expiryDate?.toIso8601String(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        transaction.set(db.collection('fertilizer_transactions').doc(), {
          'farmerId': uid,
          'fertilizerId': itemId,
          'type': transactionType,
          'quantity': quantity,
          'balance': next,
          'createdAt': FieldValue.serverTimestamp(),
        });
      });
    } catch (error) {
      if (error is AppException) rethrow;
      throw AppException.from(error);
    }
  }

  WriteBatch batch() => db.batch();
  DocumentReference<Map<String, dynamic>> document(
    String collection, [
    String? id,
  ]) => id == null
      ? db.collection(collection).doc()
      : db.collection(collection).doc(id);
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getOwned(
    String collection,
    String uid,
  ) async =>
      (await db
              .collection(collection)
              .where('farmerId', isEqualTo: uid)
              .limit(QueryLimits.batchRecords)
              .get())
          .docs;

  Future<void> saveRecommendationBundle({
    required Map<String, dynamic> recommendation,
    required Map<String, dynamic> disease,
    required Map<String, dynamic> pest,
    required Map<String, dynamic> treatment,
    required Map<String, dynamic> fertilizer,
  }) async {
    try {
      final write = db.batch();
      write.set(db.collection('recommendations').doc(), recommendation);
      write.set(db.collection('diseases').doc(), disease);
      write.set(db.collection('pests').doc(), pest);
      write.set(db.collection('treatments').doc(), treatment);
      write.set(db.collection('fertilizers').doc(), fertilizer);
      await write.commit();
    } catch (error) {
      throw AppException.from(error);
    }
  }

  Future<void> saveKnowledgeBundle(Map<String, dynamic> data) async {
    try {
      final write = db.batch();
      write.set(db.collection('crops').doc(), data);
      write.set(db.collection('diseases').doc(), data);
      write.set(db.collection('pests').doc(), data);
      await write.commit();
    } catch (error) {
      throw AppException.from(error);
    }
  }
}

class AdminReportingRepository extends OperationsRepository {
  const AdminReportingRepository(super.db, super.realtime);
  Stream<QuerySnapshot<Map<String, dynamic>>> notifications(String uid) => db
      .collection('notifications')
      .where('farmerId', isEqualTo: uid)
      .limit(QueryLimits.activityRecords)
      .snapshots();
  Stream<QuerySnapshot<Map<String, dynamic>>> reports(String uid) => db
      .collection('reports')
      .where('farmerId', isEqualTo: uid)
      .limit(QueryLimits.activityRecords)
      .snapshots();
  Stream<QuerySnapshot<Map<String, dynamic>>> systemLogs() => db
      .collection('systemLogs')
      .orderBy('timestamp', descending: true)
      .limit(QueryLimits.activityRecords)
      .snapshots();
}
