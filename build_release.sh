#!/bin/bash
set -e

# Define root and component paths
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHILD_DIR="$ROOT_DIR/apps/child-android"
PARENT_DIR="$ROOT_DIR/apps/parent-flutter"

BUILD_CHILD=true
BUILD_PARENT=true
BUILD_WEB=true

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --parent-only|parent|-p)
            BUILD_CHILD=false
            BUILD_PARENT=true
            BUILD_WEB=false
            ;;
        --child-only|child|-c)
            BUILD_CHILD=true
            BUILD_PARENT=false
            BUILD_WEB=false
            ;;
        --web-only|web|-w)
            BUILD_CHILD=false
            BUILD_PARENT=false
            BUILD_WEB=true
            ;;
        --all|all)
            BUILD_CHILD=true
            BUILD_PARENT=true
            BUILD_WEB=true
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --parent-only, parent    Build only the Parent Flutter Android app"
            echo "  --child-only, child      Build only the Child Android app"
            echo "  --web-only, web          Build only the Parent Web PWA"
            echo "  --all                    Build both apps and Web PWA (default)"
            echo "  -h, --help               Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg"
            echo "Run '$0 --help' for usage."
            exit 1
            ;;
    esac
done

# Detect JAVA_HOME
if [ -d "/usr/lib/jvm/java-17-openjdk-amd64" ]; then
    export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
elif [ -d "/Applications/Android Studio.app/Contents/jbr/Contents/Home" ]; then
    export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
fi

# Detect Flutter
if ! command -v flutter &> /dev/null && [ -d "$HOME/flutter/bin" ]; then
    export PATH="$HOME/flutter/bin:$PATH"
fi

mkdir -p "$ROOT_DIR/build"

echo "=== FamilyLink Buddy Local-First Release Compiler ==="
if [ "$BUILD_CHILD" = true ] && [ "$BUILD_PARENT" = true ] && [ "$BUILD_WEB" = true ]; then
    echo "Target: Child (Android), Parent (Android APK), and Parent Web PWA"
elif [ "$BUILD_PARENT" = true ]; then
    echo "Target: Parent (Flutter Android APK) app only"
elif [ "$BUILD_CHILD" = true ]; then
    echo "Target: Child (Android APK) app only"
elif [ "$BUILD_WEB" = true ]; then
    echo "Target: Parent Web PWA only"
fi
echo ""

# 1. Compile Child App
if [ "$BUILD_CHILD" = true ]; then
    echo "Cleaning and compiling Child App (com.familylink.buddy.child)..."
    (cd "$CHILD_DIR" && ./gradlew clean assembleRelease)
    if [ $? -ne 0 ]; then
        echo "❌ Child app build failed!"
        exit 1
    fi
    if [ -f "$CHILD_DIR/app/build/outputs/apk/release/app-release.apk" ]; then
        cp "$CHILD_DIR/app/build/outputs/apk/release/app-release.apk" "$CHILD_DIR/app/build/outputs/apk/release/child-release.apk"
        cp "$CHILD_DIR/app/build/outputs/apk/release/child-release.apk" "$ROOT_DIR/build/child-app-release.apk"
    fi
    (cd "$CHILD_DIR" && ./gradlew --stop > /dev/null 2>&1 || true)
    echo "✅ Child app build successful!"
    echo ""
fi

# 2. Compile Parent App (Android APK)
if [ "$BUILD_PARENT" = true ]; then
    echo "Cleaning and compiling Parent App APK (com.familylink.buddy.parent)..."
    (cd "$PARENT_DIR" && flutter clean && flutter build apk --release --target-platform android-arm64,android-x64 --android-skip-build-dependency-validation)
    if [ $? -ne 0 ]; then
        echo "❌ Parent app build failed!"
        exit 1
    fi
    if [ -f "$PARENT_DIR/build/app/outputs/flutter-apk/app-release.apk" ]; then
        cp "$PARENT_DIR/build/app/outputs/flutter-apk/app-release.apk" "$PARENT_DIR/build/app/outputs/flutter-apk/parent-release.apk"
        cp "$PARENT_DIR/build/app/outputs/flutter-apk/parent-release.apk" "$ROOT_DIR/build/parent-app-release.apk"
    fi
    echo "✅ Parent app APK build successful!"
    echo ""
fi

# 3. Compile Parent Web PWA
if [ "$BUILD_WEB" = true ]; then
    echo "Compiling Parent Progressive Web App (PWA)..."
    (cd "$PARENT_DIR" && flutter build web --release)
    if [ $? -ne 0 ]; then
        echo "❌ Parent Web PWA build failed!"
        exit 1
    fi
    mkdir -p "$ROOT_DIR/build/parent-app-web"
    rm -rf "$ROOT_DIR/build/parent-app-web"/*
    cp -r "$PARENT_DIR/build/web"/* "$ROOT_DIR/build/parent-app-web/"
    echo "✅ Parent Web PWA build successful!"
    echo ""
fi

# 4. Print Output Summary
CHILD_APK="$ROOT_DIR/build/child-app-release.apk"
PARENT_APK="$ROOT_DIR/build/parent-app-release.apk"
WEB_DIR="$ROOT_DIR/build/parent-app-web"

echo "==========================================="
echo "🎉 Compilation Complete! Artifact Summary:"
echo "==========================================="
if [ "$BUILD_CHILD" = true ]; then
    if [ -f "$CHILD_APK" ]; then
        echo "📱 Child App Release APK: $CHILD_APK ($(du -sh "$CHILD_APK" | cut -f1))"
    else
        echo "⚠️ Child App APK not found at expected path: $CHILD_APK"
    fi
fi

if [ "$BUILD_PARENT" = true ]; then
    if [ -f "$PARENT_APK" ]; then
        echo "👨‍👩‍👧‍👦 Parent App Release APK: $PARENT_APK ($(du -sh "$PARENT_APK" | cut -f1))"
    else
        echo "⚠️ Parent App APK not found at expected path: $PARENT_APK"
    fi
fi

if [ "$BUILD_WEB" = true ]; then
    if [ -d "$WEB_DIR" ] && [ -f "$WEB_DIR/index.html" ]; then
        echo "🌐 Parent Web PWA: $WEB_DIR ($(du -sh "$WEB_DIR" | cut -f1))"
    else
        echo "⚠️ Parent Web PWA not found at expected path: $WEB_DIR"
    fi
fi
echo "==========================================="
