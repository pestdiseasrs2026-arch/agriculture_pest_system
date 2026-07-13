import {initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {FieldValue, getFirestore, Timestamp} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {onSchedule} from "firebase-functions/v2/scheduler";

initializeApp();

const db = getFirestore();
const ownedCollections = [
  "farms", "cropRecords", "detections", "recommendations", "soil_samples",
  "soil_tests", "soil_recommendations", "fertilizers",
  "fertilizer_transactions", "notifications", "reports",
];

async function deleteOwnedDocuments(uid: string): Promise<void> {
  for (const collection of ownedCollections) {
    for (const ownerField of ["farmerId", "userId", "ownerId", "uid"]) {
      while (true) {
        const snapshot = await db.collection(collection)
          .where(ownerField, "==", uid).limit(400).get();
        if (snapshot.empty) break;
        const writer = db.bulkWriter();
        snapshot.docs.forEach((document) => writer.delete(document.ref));
        await writer.close();
      }
    }
  }
}

async function deleteStoragePrefix(prefix: string): Promise<void> {
  const [files] = await getStorage().bucket().getFiles({prefix});
  await Promise.all(files.map((file) => file.delete({ignoreNotFound: true})));
}

export const processAccountDeletions = onSchedule(
  {schedule: "every day 02:00", timeZone: "UTC", region: "us-central1"},
  async () => {
    const due = await db.collection("deletion_requests")
      .where("status", "==", "pending")
      .where("executeAfter", "<=", Timestamp.now()).limit(50).get();
    for (const request of due.docs) {
      const uid = request.id;
      await request.ref.update({status: "processing", startedAt: FieldValue.serverTimestamp()});
      try {
        await deleteOwnedDocuments(uid);
        await Promise.all([
          deleteStoragePrefix(`users/${uid}/`),
          deleteStoragePrefix(`detections/${uid}/`),
          deleteStoragePrefix(`reports/${uid}/`),
        ]);
        await db.collection("users").doc(uid).delete();
        await getAuth().deleteUser(uid).catch((error: unknown) => {
          if ((error as {code?: string}).code !== "auth/user-not-found") throw error;
        });
        await request.ref.delete();
      } catch (error) {
        await request.ref.update({
          status: "failed",
          failedAt: FieldValue.serverTimestamp(),
          errorType: error instanceof Error ? error.name : "UnknownError",
        });
      }
    }
  },
);

export const enforceDataRetention = onSchedule(
  {schedule: "every day 03:00", timeZone: "UTC", region: "us-central1"},
  async () => {
    const policies = [
      {collection: "diagnostic_events", days: 90},
      {collection: "systemLogs", days: 365},
    ];
    for (const policy of policies) {
      const cutoff = Timestamp.fromMillis(Date.now() - policy.days * 86400000);
      while (true) {
        const expired = await db.collection(policy.collection)
          .where("timestamp", "<", cutoff).limit(400).get();
        if (expired.empty) break;
        const writer = db.bulkWriter();
        expired.docs.forEach((document) => writer.delete(document.ref));
        await writer.close();
      }
    }
  },
);
