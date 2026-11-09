#!/bin/bash

echo "==========================================="
echo "   Running All Automated Tests 🧪"
echo "==========================================="
echo ""

# 1. Run Child Android Tests
echo "--- Running Child Android Unit Tests ---"
(cd apps/child-android && ./gradlew test)
ANDROID_EXIT=$?

if [ $ANDROID_EXIT -eq 0 ]; then
    echo "✅ Child Android tests passed!"
else
    echo "❌ Child Android tests failed!"
fi

echo ""

# Detect Flutter binary
if command -v flutter &> /dev/null; then
    FLUTTER_BIN="flutter"
elif [ -f "$HOME/flutter/bin/flutter" ]; then
    FLUTTER_BIN="$HOME/flutter/bin/flutter"
else
    FLUTTER_BIN="flutter"
fi

# 2. Run Parent Flutter Tests
echo "--- Running Parent Flutter Unit Tests ---"
(cd apps/parent-flutter && $FLUTTER_BIN test)
FLUTTER_EXIT=$?

if [ $FLUTTER_EXIT -eq 0 ]; then
    echo "✅ Parent Flutter tests passed!"
else
    echo "❌ Parent Flutter tests failed!"
fi

echo ""
echo "==========================================="
if [ $ANDROID_EXIT -eq 0 ] && [ $FLUTTER_EXIT -eq 0 ]; then
    echo "🎉 ALL TESTS PASSED SUCCESSFULLY! ✅"
    exit 0
else
    echo "🚨 SOME TESTS FAILED! ❌"
    exit 1
fi
