"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.forceSync = exports.scheduledSync = void 0;
const scheduler_1 = require("firebase-functions/v2/scheduler");
const https_1 = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
if (!admin.apps.length) {
    admin.initializeApp();
}
const db = admin.firestore();
const messaging = admin.messaging();
// Helper to query and send sync update for a pairing
async function syncDeviceTime(childToken, parentId) {
    // 1. In production: decrypt token, call Google API
    // For MVP/Demo: we query the current local database state or simulate update
    const randomMinutes = Math.floor(30 + Math.random() * 90);
    const payload = {
        token: childToken,
        data: {
            type: "SCREEN_TIME_UPDATE",
            totalRemainingMinutes: randomMinutes.toString(),
            totalLimitMinutes: "120",
            appUsages: JSON.stringify([
                { packageName: "com.google.android.youtube", appName: "YouTube", usedMinutes: 15, limitMinutes: 30 },
                { packageName: "com.mojang.minecraftpe", appName: "Minecraft", usedMinutes: 20, limitMinutes: 60 }
            ])
        }
    };
    try {
        await messaging.send(payload);
        await db.collection("pairings").doc(childToken).update({
            lastSeen: admin.firestore.FieldValue.serverTimestamp()
        });
    }
    catch (e) {
        console.error(`Sync failed for token ${childToken}:`, e);
    }
}
// 1. Cron Sync (every 5 minutes)
exports.scheduledSync = (0, scheduler_1.onSchedule)("every 5 minutes", async (event) => {
    const pairingsSnap = await db.collection("pairings").get();
    for (const doc of pairingsSnap.docs) {
        const data = doc.data();
        await syncDeviceTime(doc.id, data.parentId);
    }
});
// 2. HTTPS Callable manual sync (for testing/development UI refresh)
exports.forceSync = (0, https_1.onCall)(async (request) => {
    const data = request.data;
    const childToken = data.childToken;
    const parentId = request.auth?.uid || "mock-parent-uid";
    if (!childToken) {
        throw new https_1.HttpsError("invalid-argument", "childToken is required");
    }
    await syncDeviceTime(childToken, parentId);
    return { status: "success" };
});
//# sourceMappingURL=sync.js.map