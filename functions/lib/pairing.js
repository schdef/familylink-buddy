"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.pairWithCode = exports.generatePairingCode = void 0;
const https_1 = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const crypto_1 = require("./crypto");
if (!admin.apps.length) {
    admin.initializeApp();
}
const db = admin.firestore();
// 1. Child device requests a 6-digit pairing code
exports.generatePairingCode = (0, https_1.onCall)(async (request) => {
    const data = request.data;
    const fcmToken = data.fcmToken;
    const deviceName = data.deviceName || "Kind-Gerät";
    if (!fcmToken) {
        throw new https_1.HttpsError("invalid-argument", "fcmToken is required");
    }
    // Generate 6-digit random code
    let code = "";
    let attempts = 0;
    while (attempts < 5) {
        code = Math.floor(100000 + Math.random() * 900000).toString();
        const doc = await db.collection("pairing_codes").doc(code).get();
        if (!doc.exists)
            break;
        attempts++;
    }
    await db.collection("pairing_codes").doc(code).set({
        fcmToken: fcmToken,
        deviceName: deviceName,
        createdAt: admin.firestore.FieldValue.serverTimestamp()
    });
    return { code: code };
});
// 2. Parent app pairs using 6-digit code
exports.pairWithCode = (0, https_1.onCall)(async (request) => {
    const data = request.data;
    const code = data.code;
    const parentId = request.auth?.uid || "mock-parent-uid"; // Fallback for local emulator testing without full auth
    const googleAuthCode = data.googleAuthCode || "mock-auth-code";
    if (!code) {
        throw new https_1.HttpsError("invalid-argument", "code is required");
    }
    const codeDocRef = db.collection("pairing_codes").doc(code);
    const codeDoc = await codeDocRef.get();
    if (!codeDoc.exists) {
        throw new https_1.HttpsError("not-found", "Der eingegebene Code ist ungültig oder abgelaufen.");
    }
    const codeData = codeDoc.data();
    if (!codeData) {
        throw new https_1.HttpsError("internal", "Code document data is empty");
    }
    const childToken = codeData.fcmToken;
    const childName = codeData.deviceName;
    // Create permanent pairing
    await db.collection("pairings").doc(childToken).set({
        parentId: parentId,
        deviceName: childName,
        lastSeen: admin.firestore.FieldValue.serverTimestamp()
    });
    // Store encrypted refresh token (mock exchange or actual token encryption)
    const mockRefreshToken = `refresh-token-for-${parentId}-exchanged-via-${googleAuthCode}`;
    const encrypted = (0, crypto_1.encrypt)(mockRefreshToken);
    await db.collection("users").doc(parentId).set({
        encryptedTokens: encrypted,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });
    // Delete the temporary pairing code
    await codeDocRef.delete();
    return {
        status: "success",
        childName: childName,
        childToken: childToken
    };
});
//# sourceMappingURL=pairing.js.map