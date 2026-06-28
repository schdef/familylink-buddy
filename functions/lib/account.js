"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.exportUserData = exports.deleteUserAccount = void 0;
const https_1 = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
if (!admin.apps.length) {
    admin.initializeApp();
}
const db = admin.firestore();
// GDPR Right to be Forgotten
exports.deleteUserAccount = (0, https_1.onCall)(async (request) => {
    const parentId = request.auth?.uid;
    if (!parentId) {
        throw new https_1.HttpsError("unauthenticated", "User must be authenticated");
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
exports.exportUserData = (0, https_1.onCall)(async (request) => {
    const parentId = request.auth?.uid;
    if (!parentId) {
        throw new https_1.HttpsError("unauthenticated", "User must be authenticated");
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
//# sourceMappingURL=account.js.map