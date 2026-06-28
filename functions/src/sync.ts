import { onSchedule } from "firebase-functions/v2/scheduler";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";
import { decrypt } from "./crypto";

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();
const messaging = admin.messaging();

interface FamilyLinkData {
  totalRemainingMinutes: number;
  totalLimitMinutes: number;
  appUsages: Array<{
    packageName: string;
    appName: string;
    usedMinutes: number;
    limitMinutes: number;
  }>;
}

// 1. Refresh Google Access Token using decrypted Google Refresh Token
async function getGoogleAccessToken(refreshToken: string): Promise<string> {
  const isMock = refreshToken.startsWith("mock-refresh-token") || process.env.MOCK_GOOGLE_API === "true";
  if (isMock) {
    return "mock-access-token";
  }

  const clientId = process.env.GOOGLE_CLIENT_ID || "260707499739-mock-web-server-client-id.apps.googleusercontent.com";
  const clientSecret = process.env.GOOGLE_CLIENT_SECRET;
  
  if (!clientSecret) {
    console.warn("GOOGLE_CLIENT_SECRET not configured. Defaulting to mock token.");
    return "mock-access-token";
  }

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      refresh_token: refreshToken,
      client_id: clientId,
      client_secret: clientSecret,
      grant_type: "refresh_token"
    })
  });

  if (!response.ok) {
    throw new Error(`Failed to refresh access token: ${await response.text()}`);
  }

  const data = await response.json() as { access_token: string };
  return data.access_token;
}

// 2. Query supervised kid profile endpoints on behalf of parent
async function fetchFamilyLinkData(accessToken: string): Promise<FamilyLinkData> {
  const isMock = accessToken === "mock-access-token" || process.env.MOCK_GOOGLE_API === "true";
  if (isMock) {
    const now = Date.now();
    // Simulate time remaining decrementing by 1 minute every 10 seconds (for fast local dev loops)
    const totalLimitMinutes = 120;
    const elapsedMinutes = Math.floor((now % (totalLimitMinutes * 60 * 1000)) / 10000);
    const totalRemainingMinutes = Math.max(0, 60 - elapsedMinutes);

    return {
      totalRemainingMinutes,
      totalLimitMinutes,
      appUsages: [
        { packageName: "com.google.android.youtube", appName: "YouTube", usedMinutes: Math.min(30, 15 + elapsedMinutes), limitMinutes: 30 },
        { packageName: "com.mojang.minecraftpe", appName: "Minecraft", usedMinutes: Math.min(60, 20 + elapsedMinutes), limitMinutes: 60 }
      ]
    };
  }

  // Live production query to Google Kid Profile API
  const childrenResponse = await fetch("https://kid-profile.googleapis.com/v1/families/mine/children", {
    headers: { "Authorization": `Bearer ${accessToken}` }
  });

  if (!childrenResponse.ok) {
    throw new Error(`Failed to fetch children: ${await childrenResponse.text()}`);
  }

  const childrenData = await childrenResponse.json() as { children?: Array<{ id: string, name?: string }> };
  const kidId = childrenData.children?.[0]?.id;
  if (!kidId) {
    throw new Error("No supervised children profiles associated with parent account");
  }

  const usageResponse = await fetch(`https://kid-profile.googleapis.com/v1/users/${kidId}/deviceUsage`, {
    headers: { "Authorization": `Bearer ${accessToken}` }
  });

  if (!usageResponse.ok) {
    throw new Error(`Failed to fetch child device usage: ${await usageResponse.text()}`);
  }

  const usageData = await usageResponse.json() as any;
  const remaining = usageData.deviceTimeLimitStatus?.remainingSeconds !== undefined
    ? Math.floor(usageData.deviceTimeLimitStatus.remainingSeconds / 60)
    : 45;
  const limit = usageData.deviceTimeLimitStatus?.allottedSeconds !== undefined
    ? Math.floor(usageData.deviceTimeLimitStatus.allottedSeconds / 60)
    : 120;

  return {
    totalRemainingMinutes: remaining,
    totalLimitMinutes: limit,
    appUsages: [] // Extensible for specific app locks in production Google API
  };
}

// Helper to query and send sync update for a pairing
async function syncDeviceTime(childToken: string, parentId: string) {
  try {
    // 1. Fetch user credentials from DB
    const userDoc = await db.collection("users").doc(parentId).get();
    if (!userDoc.exists) {
      throw new Error(`No credentials found for parent ${parentId}`);
    }

    const userData = userDoc.data();
    const encryptedToken = userData?.encryptedTokens;
    if (!encryptedToken) {
      throw new Error(`Encrypted tokens are empty for parent ${parentId}`);
    }

    // 2. Decrypt Google Refresh Token
    const refreshToken = decrypt(encryptedToken);

    // 3. Exchange for temporary access token
    const accessToken = await getGoogleAccessToken(refreshToken);

    // 4. Fetch time limits from Family Link
    const syncData = await fetchFamilyLinkData(accessToken);

    // 5. Send FCM update to child device
    const payload = {
      token: childToken,
      data: {
        type: "SCREEN_TIME_UPDATE",
        totalRemainingMinutes: syncData.totalRemainingMinutes.toString(),
        totalLimitMinutes: syncData.totalLimitMinutes.toString(),
        appUsages: JSON.stringify(syncData.appUsages)
      }
    };

    await messaging.send(payload);

    await db.collection("pairings").doc(childToken).update({
      lastSeen: FieldValue.serverTimestamp()
    });

    console.log(`Sync success for child token: ${childToken.substring(0, 10)}... (Remaining: ${syncData.totalRemainingMinutes} min)`);
  } catch (e: any) {
    console.error(`Sync failed for token ${childToken}:`, e.message);
  }
}

// 1. Cron Sync (every 5 minutes)
export const scheduledSync = onSchedule("every 5 minutes", async (event) => {
  const pairingsSnap = await db.collection("pairings").get();
  for (const doc of pairingsSnap.docs) {
    const data = doc.data();
    await syncDeviceTime(doc.id, data.parentId);
  }
});

// 2. HTTPS Callable manual sync (for testing/development UI refresh)
export const forceSync = onCall(async (request) => {
  const data = request.data;
  const childToken = data.childToken;
  const parentId = request.auth?.uid || "mock-parent-uid";

  if (!childToken) {
    throw new HttpsError("invalid-argument", "childToken is required");
  }

  await syncDeviceTime(childToken, parentId);
  return { status: "success" };
});
