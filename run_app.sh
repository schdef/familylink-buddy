#!/bin/bash

# Detect Android SDK and platform tools
if [ -n "$ANDROID_HOME" ]; then
    SDK_DIR="$ANDROID_HOME"
elif [ -n "$ANDROID_SDK_ROOT" ]; then
    SDK_DIR="$ANDROID_SDK_ROOT"
elif [ -d "$HOME/Android/Sdk" ]; then
    SDK_DIR="$HOME/Android/Sdk"
elif [ -d "$HOME/Library/Android/sdk" ]; then
    SDK_DIR="$HOME/Library/Android/sdk"
elif [ -d "/usr/lib/android-sdk" ]; then
    SDK_DIR="/usr/lib/android-sdk"
else
    SDK_DIR=""
fi

if [ -n "$SDK_DIR" ] && [ -f "$SDK_DIR/platform-tools/adb" ]; then
    ADB="$SDK_DIR/platform-tools/adb"
    EMULATOR="$SDK_DIR/emulator/emulator"
else
    ADB="$(which adb 2>/dev/null || echo "adb")"
    EMULATOR="$(which emulator 2>/dev/null || echo "emulator")"
fi
APP_DIR="$(dirname "$0")/apps/child-android"

echo "=== Checking Android Environment ==="

# 1. Compile the app
echo "Building the app..."
(cd "$APP_DIR" && ./gradlew assembleDebug)
if [ $? -ne 0 ]; then
    echo "❌ Build failed!"
    exit 1
fi
echo "✅ Build successful!"

# 2. Check if emulator/device is already running
DEVICE=$($ADB devices | grep -v "List of devices attached" | grep "device" | awk '{print $1}' | head -n 1)

if [ -n "$DEVICE" ]; then
    echo "✅ Running device/emulator found: $DEVICE (reusing it)"
else
    echo "No running emulator found. Starting emulator..."
    
    # Get the first AVD name
    AVD=$($EMULATOR -list-avds | head -n 1)
    
    if [ -z "$AVD" ]; then
        echo "❌ Error: No Android Virtual Devices (AVD) configured!"
        exit 1
    fi
    
    echo "Starting emulator: $AVD"
    $EMULATOR -avd "$AVD" > /dev/null 2>&1 &
    
    # Wait for emulator to boot
    echo "Waiting for emulator to finish booting (this can take a minute)..."
    while true; do
        BOOT_STATUS=$($ADB shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
        if [ "$BOOT_STATUS" = "1" ]; then
            break
        fi
        printf "."
        sleep 3
    done
    echo ""
    echo "✅ Emulator is ready!"
fi

# 3. Install the app
echo "Installing APK..."
$ADB install -r "$APP_DIR/app/build/outputs/apk/debug/app-debug.apk"
if [ $? -ne 0 ]; then
    echo "❌ Installation failed!"
    exit 1
fi
echo "✅ App installed successfully!"

# 4. Launch the app
echo "Launching MainActivity..."
$ADB shell am start -n com.familylink.buddy.child/.MainActivity
echo "🎉 Done! The app is now open on the device."
