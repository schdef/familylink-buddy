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
echo "Step 2: Google Drive Upload Methode wählen"
echo "----------------------------------------------------------"
echo "1) Drag & Drop (Kein Token nötig - Ordner & Finder öffnen sich)"
echo "2) Programmatischer API Upload (Google API Token benötigt)"
echo "----------------------------------------------------------"
read -p "Auswahl [1 oder 2]: " choice

if [ "$choice" = "1" ] || [ -z "$choice" ]; then
    echo "Öffne Google Drive Ordner im Browser..."
    open "https://drive.google.com/drive/folders/1HtkqM0q94wqDUy1TzOv9XAn7mL3BnYEz?usp=sharing"
    echo "Öffne Finder mit den erzeugten APKs..."
    open -R apps/child-android/app/build/outputs/apk/release/app-release.apk
    open -R apps/parent-flutter/build/app/outputs/flutter-apk/app-release.apk
    echo "👉 Ziehen Sie einfach die beiden APKs aus dem Finder in Ihren Browser-Tab!"
else
    # 3. Trigger upload utility
    node upload_to_drive.js
fi
