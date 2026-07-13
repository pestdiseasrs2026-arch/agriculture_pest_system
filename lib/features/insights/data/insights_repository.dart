import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:agriculture_pest_system/core/errors/app_exception.dart';
import 'package:agriculture_pest_system/core/data/query_limits.dart';
import 'package:agriculture_pest_system/core/models/app_models.dart';

class InsightsRepository {
  final FirebaseFirestore db;
  final FirebaseStorage storage;
  final FirebaseMessaging messaging;
  const InsightsRepository(this.db, this.storage, this.messaging);
  Stream<List<DetectionRecord>> detections(String uid) => db
      .collection('detections')
      .where('farmerId', isEqualTo: uid)
      .limit(QueryLimits.liveRecords)
      .snapshots()
      .map(
        (s) => s.docs.map((d) => DetectionRecord.fromMap(d.data())).toList(),
      );
  Stream<List<CropRecord>> crops(String uid) => db
      .collection('cropRecords')
      .where('farmerId', isEqualTo: uid)
      .limit(QueryLimits.liveRecords)
      .snapshots()
      .map((s) => s.docs.map((d) => CropRecord.fromMap(d.data())).toList());
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
  Future<void> updateNotification(String id, Map<String, dynamic> data) =>
      db.collection('notifications').doc(id).update(data);
  Future<void> deleteNotification(String id) =>
      db.collection('notifications').doc(id).delete();
  Future<void> savePreferences(String uid, Map<String, dynamic> data) => db
      .collection('notification_preferences')
      .doc(uid)
      .set(data, SetOptions(merge: true));
  Future<void> initializeFcm(String uid) async {
    try {
      await messaging.requestPermission();
      final token = await messaging.getToken();
      if (token != null) {
        await db.collection('users').doc(uid).set({
          'fcmTokens': FieldValue.arrayUnion([token]),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      throw AppException.from(e);
    }
  }

  Stream<RemoteMessage> get foregroundMessages => FirebaseMessaging.onMessage;
  Future<String> uploadReport(
    String uid,
    String id,
    String extension,
    Uint8List bytes,
    String contentType,
  ) async {
    final ref = storage.ref('reports/$uid/$id.$extension');
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    return ref.getDownloadURL();
  }

  Future<void> saveReportMetadata(Map<String, dynamic> data) => db
      .collection('reports')
      .add({...data, 'createdAt': FieldValue.serverTimestamp()});
}
