import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";
import { encrypt } from "./crypto";

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

// 1. Child device requests a 6-digit pairing code
export const generatePairingCode = onCall(async (request) => {
  const data = request.data;
  const fcmToken = data.fcmToken;
  const deviceName = data.deviceName || "Kind-Gerät";

  if (!fcmToken) {
    throw new HttpsError("invalid-argument", "fcmToken is required");
  }

  // Generate 6-digit random code
  let code = "";
  let attempts = 0;
  while (attempts < 5) {
    code = Math.floor(100000 + Math.random() * 900000).toString();
    const doc = await db.collection("pairing_codes").doc(code).get();
    if (!doc.exists) break;
    attempts++;
  }

  await db.collection("pairing_codes").doc(code).set({
    fcmToken: fcmToken,
    deviceName: deviceName,
    createdAt: FieldValue.serverTimestamp()
  });

  return { code: code };
});

// 2. Parent app pairs using 6-digit code
export const pairWithCode = onCall(async (request) => {
  const data = request.data;
  const code = data.code;
  const parentId = request.auth?.uid || "mock-parent-uid"; // Fallback for local emulator testing without full auth
  const googleAuthCode = data.googleAuthCode || "mock-auth-code";

  if (!code) {
    throw new HttpsError("invalid-argument", "code is required");
  }

  const codeDocRef = db.collection("pairing_codes").doc(code);
  const codeDoc = await codeDocRef.get();

  if (!codeDoc.exists) {
    throw new HttpsError("not-found", "Der eingegebene Code ist ungültig oder abgelaufen.");
  }

  const codeData = codeDoc.data();
  if (!codeData) {
    throw new HttpsError("internal", "Code document data is empty");
  }

  const childToken = codeData.fcmToken;
  const childName = codeData.deviceName;

  // Create permanent pairing
  await db.collection("pairings").doc(childToken).set({
    parentId: parentId,
    deviceName: childName,
    lastSeen: FieldValue.serverTimestamp()
  });

  // Store encrypted refresh token (mock exchange or actual token encryption)
  const mockRefreshToken = `refresh-token-for-${parentId}-exchanged-via-${googleAuthCode}`;
  const encrypted = encrypt(mockRefreshToken);

  await db.collection("users").doc(parentId).set({
    encryptedTokens: encrypted,
    updatedAt: FieldValue.serverTimestamp()
  });

  // Delete the temporary pairing code
  await codeDocRef.delete();

  return { 
    status: "success", 
    childName: childName,
    childToken: childToken
  };
});
