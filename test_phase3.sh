#!/bin/bash

# Define paths
SDK_DIR="/Users/stefanheintz/Library/Android/sdk"
ADB="$SDK_DIR/platform-tools/adb"
EMULATOR="$SDK_DIR/emulator/emulator"
CHILD_DIR="$(dirname "$0")/apps/child-android"
PARENT_DIR="$(dirname "$0")/apps/parent-flutter"

echo "=== FamilyLink Buddy Phase 3 Local Test Runner ==="

# 1. Compile both apps
echo "Building child app (com.familylink.buddy.child)..."
(cd "$CHILD_DIR" && ./gradlew assembleDebug)
if [ $? -ne 0 ]; then
    echo "❌ Child app build failed!"
    exit 1
fi
echo "✅ Child app build successful!"

echo "Building parent app (com.familylink.buddy.parent)..."
(cd "$PARENT_DIR" && flutter build apk --debug)
if [ $? -ne 0 ]; then
    echo "❌ Parent app build failed!"
    exit 1
fi
echo "✅ Parent app build successful!"

# 2. Configure and start emulators
echo "Checking running emulators..."
DEVICE1="emulator-5554"
DEVICE2="emulator-5556"

# Ensure AVDs exist
AVD1_NAME="Medium_Phone_API_36.1"
AVD2_NAME="Medium_Phone_API_36.2"
AVD1_DIR="/Users/stefanheintz/.android/avd/Medium_Phone.avd"
AVD2_DIR="/Users/stefanheintz/.android/avd/Medium_Phone_2.avd"

if [ ! -d "$AVD2_DIR" ]; then
    echo "Cloning AVD configuration to allow concurrent emulator runs..."
    mkdir -p "$AVD2_DIR"
    cp "$AVD1_DIR/config.ini" "$AVD2_DIR/"
    cp "$AVD1_DIR/user-settings.ini" "$AVD2_DIR/" 2>/dev/null || true
    
    cat <<EOF > "/Users/stefanheintz/.android/avd/$AVD2_NAME.ini"
avd.ini.encoding=UTF-8
path=$AVD2_DIR
path.rel=avd/Medium_Phone_2.avd
target=android-36.1
EOF
    echo "✅ Cloned AVD configuration created: $AVD2_NAME"
fi

# Check if emulator-5554 is running
$ADB -s $DEVICE1 get-state >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Starting first emulator (emulator-5554)..."
    $EMULATOR -avd "$AVD1_NAME" -port 5554 > /dev/null 2>&1 &
fi

# Check if emulator-5556 is running
$ADB -s $DEVICE2 get-state >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Starting second emulator (emulator-5556)..."
    $EMULATOR -avd "$AVD2_NAME" -port 5556 > /dev/null 2>&1 &
fi

# Wait for both to be online and booted
echo "Waiting for both emulators to boot..."
echo "Note: The second emulator does a cold boot on first launch and may take 1-2 minutes."
for DEVICE in "$DEVICE1" "$DEVICE2"; do
    echo "Waiting for $DEVICE..."
    while true; do
        BOOT_STATUS=$($ADB -s "$DEVICE" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
        if [ "$BOOT_STATUS" = "1" ]; then
            break
        fi
        printf "."
        sleep 3
    done
    echo ""
    echo "✅ $DEVICE is ready!"
done

# 3. Install Child App on Device 1
echo "Installing Child App on $DEVICE1..."
$ADB -s $DEVICE1 install -r "$CHILD_DIR/app/build/outputs/apk/debug/app-debug.apk"
if [ $? -ne 0 ]; then
    echo "❌ Child App installation failed!"
    exit 1
fi
echo "✅ Child App installed!"

# 4. Install Parent App on Device 2
echo "Installing Parent App on $DEVICE2..."
$ADB -s $DEVICE2 install -r "$PARENT_DIR/build/app/outputs/flutter-apk/app-debug.apk"
if [ $? -ne 0 ]; then
    echo "❌ Parent App installation failed!"
    exit 1
fi
echo "✅ Parent App installed!"

# 5. Launch both apps
echo "Setting up ADB port forwarding for local developer direct connection..."
$ADB -s $DEVICE1 forward tcp:8080 tcp:8080

echo "Launching Child app on $DEVICE1..."
$ADB -s $DEVICE1 shell am start -n com.familylink.buddy.child/.MainActivity

echo "Launching Parent app on $DEVICE2..."
$ADB -s $DEVICE2 shell am start -n com.familylink.buddy.parent/.MainActivity

echo "🎉 Done! Both emulators are running and the apps are launched."
echo "Child device: $DEVICE1"
echo "Parent device: $DEVICE2"
