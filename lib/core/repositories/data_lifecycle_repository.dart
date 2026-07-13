import 'package:cloud_firestore/cloud_firestore.dart';

import '../errors/app_exception.dart';

abstract final class DataLifecyclePolicy {
  static const deletionGracePeriod = Duration(days: 7);
  static const diagnosticRetention = Duration(days: 90);
  static const auditLogRetention = Duration(days: 365);
}

class DataLifecycleRepository {
  final FirebaseFirestore db;
  const DataLifecycleRepository(this.db);

  Stream<Map<String, dynamic>?> watchDeletionRequest(String uid) => db
      .collection('deletion_requests')
      .doc(uid)
      .snapshots()
      .map((snapshot) => snapshot.data());

  Future<void> requestAccountDeletion(String uid) async {
    try {
      final batch = db.batch();
      batch.set(db.collection('deletion_requests').doc(uid), {
        'userId': uid,
        'status': 'pending',
        'requestedAt': FieldValue.serverTimestamp(),
        'executeAfter': Timestamp.fromDate(
          DateTime.now().toUtc().add(DataLifecyclePolicy.deletionGracePeriod),
        ),
      });
      batch.set(db.collection('users').doc(uid), {
        'accountStatus': 'pending_deletion',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await batch.commit();
    } catch (error) {
      throw AppException.from(error);
    }
  }

  Future<void> cancelAccountDeletion(String uid) async {
    try {
      final batch = db.batch();
      batch.delete(db.collection('deletion_requests').doc(uid));
      batch.set(db.collection('users').doc(uid), {
        'accountStatus': 'active',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await batch.commit();
    } catch (error) {
      throw AppException.from(error);
    }
  }
}
