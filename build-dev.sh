#!/bin/bash

# Quick development build for testing
# Usage: ./build-dev.sh

set -e

echo "Building Wndr (Debug)..."

# Build for running
xcodebuild -project Wndr.xcodeproj \
    -scheme WndrApp \
    -configuration Debug \
    -derivedDataPath build/DerivedData \
    build

APP_PATH="build/DerivedData/Build/Products/Debug/Wndr.app"

if [ -d "$APP_PATH" ]; then
    echo "✅ Build successful!"
    echo "App location: $APP_PATH"
    echo ""
    echo "To run the app:"
    echo "open '$APP_PATH'"
else
    echo "❌ Build failed - app not found at expected location"
    exit 1
fi
