const fs = require('fs');
const path = require('path');
const https = require('https');
const readline = require('readline');

const PROJECT_ID = 'familylink-buddy';
const FOLDER_ID = '1HtkqM0q94wqDUy1TzOv9XAn7mL3BnYEz';

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

console.log('\x1b[36m%s\x1b[0m', '================================================================');
console.log('\x1b[36m%s\x1b[0m', '💾 Google Drive Upload & Auto-Updater Tool (Spark Plan Friendly)');
console.log('\x1b[36m%s\x1b[0m', '================================================================');
console.log('Dieses Tool lädt APKs auf Google Drive hoch, macht sie öffentlich');
console.log('und trägt die Download-Links in Ihr Firestore-Dokument ein.');
console.log('Sie können in wenigen Sekunden einen Token erzeugen:');
console.log('1. Öffnen Sie: \x1b[34mhttps://developers.google.com/oauthplayground\x1b[0m');
console.log('2. Fügen Sie die folgenden zwei Scopes getrennt durch ein Leerzeichen hinzu:');
console.log('   👉 \x1b[32mhttps://www.googleapis.com/auth/drive.file https://www.googleapis.com/auth/datastore\x1b[0m');
console.log('3. Klicken Sie "Authorize APIs" und melden Sie sich an.');
console.log('4. Klicken Sie "Exchange authorization code for tokens" und kopieren Sie den Token.');
console.log('\x1b[36m%s\x1b[0m', '================================================================');

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
      name: 'child-app-release.apk',
      key: 'child',
      versionCode: childVer.code,
      versionName: childVer.name,
      mime: 'application/vnd.android.package-archive'
    },
    {
      path: path.join(__dirname, 'apps/parent-flutter/build/app/outputs/flutter-apk/app-release.apk'),
      name: 'parent-app-release.apk',
      key: 'parent',
      versionCode: parentVer.code,
      versionName: parentVer.name,
      mime: 'application/vnd.android.package-archive'
    }
  ];

  runUploads(filesToUpload, token);
});

async function runUploads(files, token) {
  const results = {};

  for (const fileInfo of files) {
    if (!fs.existsSync(fileInfo.path)) {
      console.error(`❌ Datei nicht gefunden: ${fileInfo.path}. Bitte führen Sie zuerst den Build aus.`);
      continue;
    }
    console.log(`\nStarte Upload für: ${fileInfo.name}...`);
    try {
      const fileData = await uploadFile(fileInfo.path, fileInfo.name, fileInfo.mime, FOLDER_ID, token);
      console.log(`✅ ${fileInfo.name} hochgeladen! File ID: ${fileData.id}`);
      
      console.log(`  Mache Datei öffentlich für Downloads...`);
      await makeFilePublic(fileData.id, token);
      
      const directDownloadUrl = `https://drive.google.com/uc?export=download&id=${fileData.id}`;
      results[fileInfo.key] = {
        code: fileInfo.versionCode,
        name: fileInfo.versionName,
        url: directDownloadUrl
      };
    } catch (err) {
      console.error(`❌ Fehler beim Upload von ${fileInfo.name}:`, err);
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

function uploadFile(filePath, fileName, mimeType, folderId, token) {
  return new Promise((resolve, reject) => {
    const stats = fs.statSync(filePath);
    const fileSize = stats.size;

    // Phase 1: Initiate session
    const metadata = JSON.stringify({
      name: fileName,
      parents: [folderId]
    });

    const initOptions = {
      method: 'POST',
      hostname: 'www.googleapis.com',
      path: '/upload/drive/v3/files?uploadType=resumable&supportsAllDrives=true',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json; charset=UTF-8',
        'X-Upload-Content-Type': mimeType,
        'X-Upload-Content-Length': fileSize.toString(),
        'Content-Length': Buffer.byteLength(metadata)
      }
    };

    const req = https.request(initOptions, (res) => {
      if (res.statusCode !== 200) {
        let errData = '';
        res.on('data', (d) => errData += d);
        res.on('end', () => {
          reject(`Session initiation failed (Status ${res.statusCode}): ${errData}`);
        });
        return;
      }

      const location = res.headers.location;
      if (!location) {
        reject('No upload location header received from Google API.');
        return;
      }

      // Phase 2: Upload file contents to the location URL
      performUpload(location, filePath, fileSize, mimeType, resolve, reject);
    });

    req.on('error', reject);
    req.write(metadata);
    req.end();
  });
}

function performUpload(locationUrl, filePath, fileSize, mimeType, resolve, reject) {
  const urlObj = new URL(locationUrl);
  
  const uploadOptions = {
    method: 'PUT',
    hostname: urlObj.hostname,
    path: urlObj.pathname + urlObj.search,
    headers: {
      'Content-Length': fileSize.toString(),
      'Content-Type': mimeType
    }
  };

  const uploadReq = https.request(uploadOptions, (res) => {
    let body = '';
    res.on('data', (d) => body += d);
    res.on('end', () => {
      if (res.statusCode === 200 || res.statusCode === 201) {
        resolve(JSON.parse(body));
      } else {
        reject(`Data upload failed (Status ${res.statusCode}): ${body}`);
      }
    });
  });

  uploadReq.on('error', reject);

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

  fileStream.pipe(uploadReq);
}

function makeFilePublic(fileId, token) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({
      role: 'reader',
      type: 'anyone'
    });
    
    const options = {
      method: 'POST',
      hostname: 'www.googleapis.com',
      path: `/drive/v3/files/${fileId}/permissions`,
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body)
      }
    };

    const req = https.request(options, (res) => {
      let resBody = '';
      res.on('data', (d) => resBody += d);
      res.on('end', () => {
        if (res.statusCode === 200 || res.statusCode === 201) {
          resolve();
        } else {
          reject(new Error(`GCS permission set failed (Status ${res.statusCode}): ${resBody}`));
        }
      });
    });

    req.on('error', reject);
    req.write(body);
    req.end();
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
