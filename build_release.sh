#!/bin/bash

# Define paths
CHILD_DIR="$(dirname "$0")/apps/child-android"
PARENT_DIR="$(dirname "$0")/apps/parent-flutter"

# Detect JAVA_HOME
if [ -d "/usr/lib/jvm/java-17-openjdk-amd64" ]; then
    export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
elif [ -d "/Applications/Android Studio.app/Contents/jbr/Contents/Home" ]; then
    export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
fi

echo "=== FamilyLink Buddy Release Compiler ==="

# Default: Cloud mode
USE_EMULATOR="false"

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -l|--local) USE_EMULATOR="true" ;;
        -c|--cloud) USE_EMULATOR="false" ;;
        *) echo "Unknown parameter: $1. Use --local (-l) or --cloud (-c)."; exit 1 ;;
    esac
    shift
done

echo "Configured Connection Target: $([ "$USE_EMULATOR" = "true" ] && echo "LOCAL EMULATOR" || echo "PRODUCTION CLOUD")"
echo ""

# 1. Compile Child App
echo "Cleaning and compiling Child App (com.familylink.buddy.child)..."
(cd "$CHILD_DIR" && ./gradlew clean assembleRelease -PuseEmulator=$USE_EMULATOR)
if [ $? -ne 0 ]; then
    echo "❌ Child app build failed!"
    exit 1
fi
if [ -f "$CHILD_DIR/app/build/outputs/apk/release/app-release.apk" ]; then
    mv "$CHILD_DIR/app/build/outputs/apk/release/app-release.apk" "$CHILD_DIR/app/build/outputs/apk/release/child-release.apk"
fi
echo "✅ Child app build successful!"
echo ""

# 2. Compile Parent App
echo "Cleaning and compiling Parent App (com.familylink.buddy.parent)..."
(cd "$PARENT_DIR" && flutter clean && flutter build apk --release --target-platform android-arm64,android-x64 --dart-define=USE_EMULATOR=$USE_EMULATOR)
if [ $? -ne 0 ]; then
    echo "❌ Parent app build failed!"
    exit 1
fi
if [ -f "$PARENT_DIR/build/app/outputs/flutter-apk/app-release.apk" ]; then
    mv "$PARENT_DIR/build/app/outputs/flutter-apk/app-release.apk" "$PARENT_DIR/build/app/outputs/flutter-apk/parent-release.apk"
fi
echo "✅ Parent app build successful!"
echo ""

# Copy to root build/ directory
mkdir -p "$(dirname "$0")/build"
if [ -f "$CHILD_DIR/app/build/outputs/apk/release/child-release.apk" ]; then
    cp "$CHILD_DIR/app/build/outputs/apk/release/child-release.apk" "$(dirname "$0")/build/child-app-release.apk"
fi
if [ -f "$PARENT_DIR/build/app/outputs/flutter-apk/parent-release.apk" ]; then
    cp "$PARENT_DIR/build/app/outputs/flutter-apk/parent-release.apk" "$(dirname "$0")/build/parent-app-release.apk"
fi

# 3. Print Output Summary
CHILD_APK="$CHILD_DIR/app/build/outputs/apk/release/child-release.apk"
PARENT_APK="$PARENT_DIR/build/app/outputs/flutter-apk/parent-release.apk"

echo "==========================================="
echo "🎉 Compilation Complete! Optimized APKs:"
echo "==========================================="
if [ -f "$CHILD_APK" ]; then
    echo "📱 Child App Release APK: $CHILD_APK ($(du -sh "$CHILD_APK" | cut -f1))"
else
    echo "⚠️ Child App APK not found at expected path: $CHILD_APK"
fi

if [ -f "$PARENT_APK" ]; then
    echo "👨‍👩‍👧‍👦 Parent App Release APK: $PARENT_APK ($(du -sh "$PARENT_APK" | cut -f1))"
else
    echo "⚠️ Parent App APK not found at expected path: $PARENT_APK"
fi
echo "==========================================="
