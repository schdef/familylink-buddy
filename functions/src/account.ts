import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

// GDPR Right to be Forgotten
export const deleteUserAccount = onCall(async (request) => {
  const parentId = request.auth?.uid;
  if (!parentId) {
    throw new HttpsError("unauthenticated", "User must be authenticated");
  }

  // 1. Delete parent credentials document
  await db.collection("users").doc(parentId).delete();

  // 2. Delete all pairings belonging to this parent
  const pairingsSnap = await db.collection("pairings")
    .where("parentId", "==", parentId)
    .get();

  const batch = db.batch();
  for (const doc of pairingsSnap.docs) {
    batch.delete(doc.ref);
  }
  await batch.commit();

  return { status: "success" };
});

// GDPR Data Portability
export const exportUserData = onCall(async (request) => {
  const parentId = request.auth?.uid;
  if (!parentId) {
    throw new HttpsError("unauthenticated", "User must be authenticated");
  }

  const userDoc = await db.collection("users").doc(parentId).get();
  const pairingsSnap = await db.collection("pairings")
    .where("parentId", "==", parentId)
    .get();

  const pairings = pairingsSnap.docs.map(doc => ({
    childToken: doc.id,
    ...doc.data()
  }));

  return {
    user: userDoc.exists ? userDoc.data() : null,
    pairings: pairings
  };
});
