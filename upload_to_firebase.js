const fs = require('fs');
const path = require('path');
const https = require('https');
const readline = require('readline');

const PROJECT_ID = 'familylink-buddy';
const BUCKET_NAME = `${PROJECT_ID}.appspot.com`;

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

console.log('\x1b[35m%s\x1b[0m', '================================================================');
console.log('\x1b[35m%s\x1b[0m', '🔥 Firebase Self-Hosted Auto-Updater Upload Tool');
console.log('\x1b[35m%s\x1b[0m', '================================================================');
console.log('Dieses Tool lädt die APKs in Ihren Firebase Storage Bucket hoch');
console.log('und aktualisiert das App-Release-Dokument in Firestore.');
console.log('Es wird ein Google OAuth Access Token benötigt (Scope: cloud-platform).');
console.log('Erzeugung in wenigen Sekunden unter:');
console.log('👉 \x1b[34mhttps://developers.google.com/oauthplayground\x1b[0m');
console.log('Oder lokal im Terminal:');
console.log('👉 \x1b[32mgcloud auth print-access-token\x1b[0m');
console.log('\x1b[35m%s\x1b[0m', '================================================================');

// 1. Read local versions
function getChildVersion() {
  const gradlePath = path.join(__dirname, 'apps/child-android/app/build.gradle.kts');
  if (!fs.existsSync(gradlePath)) return { code: 1, name: '1.0.0' };
  const content = fs.readFileSync(gradlePath, 'utf8');
  const codeMatch = content.match(/versionCode\s*=\s*(\d+)/);
  const nameMatch = content.match(/versionName\s*=\s*"([^"]+)"/);
  return {
    code: codeMatch ? parseInt(codeMatch[1], 10) : 1,
    name: nameMatch ? nameMatch[1] : '1.0.0'
  };
}

function getParentVersion() {
  const pubspecPath = path.join(__dirname, 'apps/parent-flutter/pubspec.yaml');
  if (!fs.existsSync(pubspecPath)) return { code: 1, name: '1.0.0' };
  const content = fs.readFileSync(pubspecPath, 'utf8');
  const match = content.match(/version:\s*([^+]+)\+(\d+)/);
  return {
    code: match ? parseInt(match[2], 10) : 1,
    name: match ? match[1].trim() : '1.0.0'
  };
}

const childVer = getChildVersion();
const parentVer = getParentVersion();

console.log(`Auto-detektierte Versionen:`);
console.log(`📱 Child App:  Code ${childVer.code}, Name ${childVer.name}`);
console.log(`👨 Parent App: Code ${parentVer.code}, Name ${parentVer.name}\n`);

rl.question('Geben Sie Ihren Google Access Token ein: ', (token) => {
  token = token.trim();
  if (!token) {
    console.error('Ungültiger Token. Vorgang abgebrochen.');
    rl.close();
    process.exit(1);
  }

  const filesToUpload = [
    {
      path: path.join(__dirname, 'apps/child-android/app/build/outputs/apk/release/app-release.apk'),
      storageName: 'releases/child-app-release.apk',
      name: 'child',
      versionCode: childVer.code,
      versionName: childVer.name,
      mime: 'application/vnd.android.package-archive'
    },
    {
      path: path.join(__dirname, 'apps/parent-flutter/build/app/outputs/flutter-apk/app-release.apk'),
      storageName: 'releases/parent-app-release.apk',
      name: 'parent',
      versionCode: parentVer.code,
      versionName: parentVer.name,
      mime: 'application/vnd.android.package-archive'
    }
  ];

  runFlow(filesToUpload, token);
});

async function runFlow(files, token) {
  const results = {};
  
  for (const fileInfo of files) {
    if (!fs.existsSync(fileInfo.path)) {
      console.error(`❌ Datei nicht gefunden: ${fileInfo.path}. Bitte führen Sie zuerst den Build aus.`);
      continue;
    }
    
    console.log(`\n[GCS] Starte Upload für ${fileInfo.name} APK...`);
    try {
      await uploadToStorage(fileInfo.path, fileInfo.storageName, fileInfo.mime, token);
      console.log(`✅ Upload abgeschlossen: ${fileInfo.storageName}`);
      
      const publicUrl = `https://storage.googleapis.com/${BUCKET_NAME}/${fileInfo.storageName}`;
      results[fileInfo.name] = {
        code: fileInfo.versionCode,
        name: fileInfo.versionName,
        url: publicUrl
      };
    } catch (err) {
      console.error(`❌ Fehler beim Upload von ${fileInfo.name}:`, err);
      rl.close();
      process.exit(1);
    }
  }

  if (results.child || results.parent) {
    console.log(`\n[Firestore] Aktualisiere Metadaten in der Datenbank...`);
    try {
      await updateFirestoreMetadata(results, token);
      console.log(`✅ Firestore-Eintrag erfolgreich aktualisiert!`);
    } catch (err) {
      console.error(`❌ Fehler bei Firestore-Aktualisierung:`, err);
    }
  }

  rl.close();
}

function uploadToStorage(filePath, storageName, mimeType, token) {
  return new Promise((resolve, reject) => {
    const stats = fs.statSync(filePath);
    const fileSize = stats.size;
    
    const encodedName = encodeURIComponent(storageName);
    const options = {
      method: 'POST',
      hostname: 'storage.googleapis.com',
      path: `/upload/storage/v1/b/${BUCKET_NAME}/o?uploadType=media&name=${encodedName}&predefinedAcl=publicRead`,
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': mimeType,
        'Content-Length': fileSize.toString()
      }
    };

    const req = https.request(options, (res) => {
      let responseBody = '';
      res.on('data', (chunk) => responseBody += chunk);
      
      res.on('end', () => {
        if (res.statusCode === 200 || res.statusCode === 201) {
          resolve(JSON.parse(responseBody));
        } else {
          reject(new Error(`GCS upload failed (Status ${res.statusCode}): ${responseBody}`));
        }
      });
    });

    req.on('error', reject);

    const fileStream = fs.createReadStream(filePath);
    let bytesUploaded = 0;
    
    fileStream.on('data', (chunk) => {
      bytesUploaded += chunk.length;
      const progress = ((bytesUploaded / fileSize) * 100).toFixed(1);
      process.stdout.write(`\rFortschritt: ${progress}% (${(bytesUploaded / 1024 / 1024).toFixed(1)} / ${(fileSize / 1024 / 1024).toFixed(1)} MB)`);
    });

    fileStream.on('end', () => {
      console.log('');
    });

    fileStream.pipe(req);
  });
}

function updateFirestoreMetadata(data, token) {
  return new Promise((resolve, reject) => {
    const fields = {};
    
    if (data.child) {
      fields.child = {
        mapValue: {
          fields: {
            versionCode: { integerValue: data.child.code.toString() },
            versionName: { stringValue: data.child.name },
            downloadUrl: { stringValue: data.child.url }
          }
        }
      };
    }
    
    if (data.parent) {
      fields.parent = {
        mapValue: {
          fields: {
            versionCode: { integerValue: data.parent.code.toString() },
            versionName: { stringValue: data.parent.name },
            downloadUrl: { stringValue: data.parent.url }
          }
        }
      };
    }

    const payload = JSON.stringify({ fields });
    
    // Firestore REST URL for patching/creating a document
    const options = {
      method: 'PATCH',
      hostname: 'firestore.googleapis.com',
      path: `/v1/projects/${PROJECT_ID}/databases/(default)/documents/app_metadata/releases`,
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(payload)
      }
    };

    const req = https.request(options, (res) => {
      let body = '';
      res.on('data', (chunk) => body += chunk);
      res.on('end', () => {
        if (res.statusCode === 200) {
          resolve(JSON.parse(body));
        } else {
          reject(new Error(`Firestore patch failed (Status ${res.statusCode}): ${body}`));
        }
      });
    });

    req.on('error', reject);
    req.write(payload);
    req.end();
  });
}
