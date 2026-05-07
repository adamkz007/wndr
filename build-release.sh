#!/bin/bash

# Build and package Wndr app for release
# Usage: ./build-release.sh [version]

set -e

VERSION=${1:-"1.0.0"}
BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/Wndr.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
DMG_PATH="$BUILD_DIR/Wndr-v$VERSION.dmg"

if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    echo "Error: No 'Developer ID Application' signing identity found."
    echo "Public releases must be Developer ID signed and notarized before upload."
    exit 1
fi

if grep -q "<string>YOUR_TEAM_ID</string>" ExportOptions.plist; then
    echo "Error: ExportOptions.plist still contains the placeholder team ID."
    echo "Set your real Apple Developer team ID before building a public release."
    exit 1
fi

echo "Building Wndr v$VERSION..."

# Clean build directory
echo "Cleaning build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Build archive
echo "Building archive..."
xcodebuild -project Wndr.xcodeproj \
    -scheme WndrApp \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    clean archive

# Export app
echo "Exporting app..."
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist ExportOptions.plist

# Create DMG
echo "Creating DMG..."
mkdir -p "$BUILD_DIR/dmg"
cp -R "$EXPORT_PATH/Wndr.app" "$BUILD_DIR/dmg/"

# Create a simple DMG with the app
hdiutil create -volname "Wndr" \
    -srcfolder "$BUILD_DIR/dmg" \
    -ov -format UDZO \
    "$DMG_PATH"

# Calculate file size and checksums
SIZE=$(du -h "$DMG_PATH" | cut -f1)
SHA256=$(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)

echo ""
echo "✅ Build complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Version:  v$VERSION"
echo "File:     $DMG_PATH"
echo "Size:     $SIZE"
echo "SHA-256:  $SHA256"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "To create a GitHub release:"
echo "1. git tag -a v$VERSION -m 'Release v$VERSION'"
echo "2. git push origin v$VERSION"
echo "3. Notarize and staple $DMG_PATH"
echo "4. Upload the notarized DMG to the GitHub release"
