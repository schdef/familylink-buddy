const fs = require('fs');
const path = require('path');
const https = require('https');
const readline = require('readline');

const FOLDER_ID = '1HtkqM0q94wqDUy1TzOv9XAn7mL3BnYEz';

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

console.log('\x1b[36m%s\x1b[0m', '================================================================');
console.log('\x1b[36m%s\x1b[0m', '💾 Google Drive Upload Tool');
console.log('\x1b[36m%s\x1b[0m', '================================================================');
console.log('Um die APKs in Ihren Google Drive Ordner hochzuladen, wird ein Access Token benötigt.');
console.log('Sie können in wenigen Sekunden einen Token erzeugen:');
console.log('1. Öffnen Sie: \x1b[34mhttps://developers.google.com/oauthplayground\x1b[0m');
console.log('2. Suchen Sie nach "Drive API v3" und wählen Sie den Scope:');
console.log('   👉 \x1b[32mhttps://www.googleapis.com/auth/drive\x1b[0m');
console.log('3. Klicken Sie "Authorize APIs" und melden Sie sich an.');
console.log('4. Klicken Sie auf "Exchange authorization code for tokens"');
console.log('5. Kopieren Sie den "Access Token" aus dem Feld.');
console.log('\x1b[36m%s\x1b[0m', '================================================================');

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
      mime: 'application/vnd.android.package-archive'
    },
    {
      path: path.join(__dirname, 'apps/parent-flutter/build/app/outputs/flutter-apk/app-release.apk'),
      name: 'parent-app-release.apk',
      mime: 'application/vnd.android.package-archive'
    }
  ];

  runUploads(filesToUpload, token);
});

async function runUploads(files, token) {
  for (const fileInfo of files) {
    if (!fs.existsSync(fileInfo.path)) {
      console.error(`Datei nicht gefunden: ${fileInfo.path}. Bitte führen Sie zuerst den Build aus.`);
      continue;
    }
    console.log(`\nStarte Upload für: ${fileInfo.name}...`);
    try {
      await uploadFile(fileInfo.path, fileInfo.name, fileInfo.mime, FOLDER_ID, token);
      console.log(`✅ ${fileInfo.name} erfolgreich hochgeladen!`);
    } catch (err) {
      console.error(`❌ Fehler beim Upload von ${fileInfo.name}:`, err);
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
    if (res.statusCode === 200 || res.statusCode === 201) {
      resolve();
    } else {
      let errData = '';
      res.on('data', (d) => errData += d);
      res.on('end', () => {
        reject(`Data upload failed (Status ${res.statusCode}): ${errData}`);
      });
    }
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
    console.log(''); // New line after progress complete
  });

  fileStream.pipe(uploadReq);
}
