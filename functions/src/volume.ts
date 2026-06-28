import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();
const messaging = admin.messaging();

export const setVolume = onCall(async (request) => {
  const data = request.data;
  const childToken = data.childToken;
  const stream = data.stream || "MEDIA"; // MEDIA | RINGTONE | ALARM | ALL
  const level = data.level;
  const parentId = request.auth?.uid || "mock-parent-uid"; // Fallback for emulator testing

  if (!childToken || level === undefined) {
    throw new HttpsError("invalid-argument", "childToken and level are required");
  }

  // 1. Verify parent owns this pairing
  const pairingDoc = await db.collection("pairings").doc(childToken).get();
  if (!pairingDoc.exists) {
    throw new HttpsError("not-found", "Gerät nicht gefunden.");
  }

  const pairingData = pairingDoc.data();
  if (pairingData?.parentId !== parentId) {
    throw new HttpsError("permission-denied", "Keine Zugriffsberechtigung für dieses Gerät.");
  }

  // 2. Send FCM data message to child device
  const message = {
    token: childToken,
    data: {
      type: "SET_VOLUME",
      stream: stream,
      level: level.toString(),
      parentToken: "backend-fcm" // FCM token not needed for direct function command callbacks
    }
  };

  try {
    const response = await messaging.send(message);
    return { status: "success", messageId: response };
  } catch (e: any) {
    throw new HttpsError("internal", `FCM delivery failed: ${e.message}`);
  }
});
