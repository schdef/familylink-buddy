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
echo "Step 2: Starte Google Drive Upload..."
# 3. Trigger upload utility
node upload_to_drive.js
