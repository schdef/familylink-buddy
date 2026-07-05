/* src/engine/familyLinkSync.js */

/**
 * Sends a reward to the FamilyLink Buddy Firestore document.
 * Fetches the current document, increments totalRemainingMinutes, and patches it back.
 * 
 * @param {string} token The child pairing token (document ID)
 * @param {string} mode 'emulator' or 'production'
 * @param {number} minutes The number of minutes to add
 * @returns {Promise<number>} The new total remaining minutes
 */
export async function sendRewardToFamilyLink(token, mode, minutes) {
  if (!token) throw new Error('Token fehlt');
  
  const projectId = 'familylink-buddy';
  // Use 127.0.0.1 instead of localhost for reliability in some environments
  const baseUrl = mode === 'emulator' 
    ? 'http://127.0.0.1:8080' 
    : 'https://firestore.googleapis.com';
    
  const docUrl = `${baseUrl}/v1/projects/${projectId}/databases/(default)/documents/pairings/${token}`;
  
  // 1. Fetch current document to get the existing screenTime map
  const response = await fetch(docUrl);
  if (!response.ok) {
    if (response.status === 404) {
      throw new Error(
        mode === 'emulator'
          ? 'Token nicht gefunden. Läuft der Emulator und ist das Kind gekoppelt?'
          : 'Token nicht gefunden. Bitte überprüfe den Token.'
      );
    }
    throw new Error(`Dokument-Abruf fehlgeschlagen: Status ${response.status}`);
  }
  
  const docData = await response.json();
  
  // 2. Parse fields
  let currentRemaining = 60; // fallback default
  let limit = 120;
  let appUsagesJsonStr = '[]';
  
  const fields = docData.fields || {};
  if (fields.screenTime && fields.screenTime.mapValue && fields.screenTime.mapValue.fields) {
    const stFields = fields.screenTime.mapValue.fields;
    if (stFields.totalRemainingMinutes && stFields.totalRemainingMinutes.integerValue) {
      currentRemaining = parseInt(stFields.totalRemainingMinutes.integerValue, 10);
    }
    if (stFields.totalLimitMinutes && stFields.totalLimitMinutes.integerValue) {
      limit = parseInt(stFields.totalLimitMinutes.integerValue, 10);
    }
    if (stFields.appUsages && stFields.appUsages.stringValue) {
      appUsagesJsonStr = stFields.appUsages.stringValue;
    }
  }
  
  // Calculate new remaining minutes
  let newRemaining = currentRemaining + minutes;
  newRemaining = Math.max(0, Math.min(newRemaining, limit)); // Cap at limit, coerce >= 0
  
  // 3. Patch the updated totalRemainingMinutes back
  const patchData = {
    fields: {
      screenTime: {
        mapValue: {
          fields: {
            totalRemainingMinutes: {
              integerValue: newRemaining.toString()
            },
            totalLimitMinutes: {
              integerValue: limit.toString()
            },
            appUsages: {
              stringValue: appUsagesJsonStr
            }
          }
        }
      }
    }
  };
  
  const patchUrl = `${docUrl}?updateMask.fieldPaths=screenTime.totalRemainingMinutes`;
  const patchResponse = await fetch(patchUrl, {
    method: 'PATCH',
    headers: {
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(patchData)
  });
  
  if (!patchResponse.ok) {
    throw new Error(`Firestore Update failed: HTTP ${patchResponse.status}`);
  }
  
  return newRemaining;
}
