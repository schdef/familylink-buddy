#!/bin/bash

# Set strict exit codes
set -e

echo "=========================================================="
echo "🚀 FamilyLink Buddy Build & Drive Upload Script"
echo "=========================================================="

# 1. Verify Node.js is installed
if ! command -v node &> /dev/null; then
    echo "❌ Node.js ist nicht installiert. Bitte installieren Sie Node.js, um fortzufahren."
    exit 1
fi

# 2. Compile APKs
echo "Step 1: Kompiliere APKs als Release..."
./build_release.sh

echo ""
echo "Step 2: Upload-Ziel wählen"
echo "----------------------------------------------------------"
echo "1) Google Drive: Drag & Drop (Kein Token nötig)"
echo "2) Google Drive: API Upload (API Token benötigt)"
echo "3) Firebase: Self-Hosted Auto-Updater Upload (API Token benötigt)"
echo "----------------------------------------------------------"
read -p "Auswahl [1, 2 oder 3]: " choice

if [ "$choice" = "1" ] || [ -z "$choice" ]; then
    echo "Öffne Google Drive Ordner im Browser..."
    open "https://drive.google.com/drive/folders/1HtkqM0q94wqDUy1TzOv9XAn7mL3BnYEz?usp=sharing"
    echo "Öffne Finder mit den erzeugten APKs..."
    open -R apps/child-android/app/build/outputs/apk/release/child-release.apk
    open -R apps/parent-flutter/build/app/outputs/flutter-apk/parent-release.apk
    echo "👉 Ziehen Sie einfach die beiden APKs aus dem Finder in Ihren Browser-Tab!"
elif [ "$choice" = "2" ]; then
    # Trigger GDrive upload utility
    node upload_to_drive.js
else
    # Trigger Firebase storage/firestore upload utility
    node upload_to_firebase.js
fi
