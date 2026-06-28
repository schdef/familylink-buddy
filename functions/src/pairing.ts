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

async function exchangeAuthCodeForTokens(authCode: string): Promise<{ refreshToken: string, accessToken?: string }> {
  const isMock = authCode === "mock-auth-code" || process.env.MOCK_GOOGLE_API === "true";
  if (isMock) {
    console.log("Mock Google API: Bypassing real OAuth exchange");
    return { refreshToken: `mock-refresh-token-for-code-${authCode}` };
  }

  const clientId = process.env.GOOGLE_CLIENT_ID || "260707499739-mock-web-server-client-id.apps.googleusercontent.com";
  const clientSecret = process.env.GOOGLE_CLIENT_SECRET;
  
  if (!clientSecret) {
    console.warn("GOOGLE_CLIENT_SECRET is not configured. Falling back to mock token.");
    return { refreshToken: `mock-refresh-token-for-code-${authCode}` };
  }

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      code: authCode,
      client_id: clientId,
      client_secret: clientSecret,
      grant_type: "authorization_code",
      redirect_uri: ""
    })
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Google OAuth exchange failed: ${errorText}`);
  }

  const data = await response.json() as { refresh_token: string, access_token: string };
  return { 
    refreshToken: data.refresh_token,
    accessToken: data.access_token 
  };
}

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

  // Exchange authorization code for refresh tokens
  let refreshToken = "";
  try {
    const tokens = await exchangeAuthCodeForTokens(googleAuthCode);
    refreshToken = tokens.refreshToken;
  } catch (err: any) {
    throw new HttpsError("internal", `OAuth exchange failed: ${err.message}`);
  }

  const encrypted = encrypt(refreshToken);

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
