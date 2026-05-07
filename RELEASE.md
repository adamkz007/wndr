# Release Process for Wndr

This document describes how to build, package, and release Wndr for macOS.

## Prerequisites

- macOS 14.0 (Sonoma) or later
- Xcode 15 or later
- Apple Developer account with a **Developer ID Application** certificate
- GitHub repository access
- App-specific password for notarization (`notarytool`)

## Important

Public macOS downloads must be **Developer ID signed and notarized**.

If you upload a DMG built from an ad-hoc or "Sign to Run Locally" archive, macOS Gatekeeper will reject it and users may see:

> "Check with the developer to make sure Wndr works with this version of macOS."

Do not publish unsigned or ad-hoc signed builds to GitHub Releases.

## Quick Release

For a local signed build, use the release script:

```bash
./build-release.sh 1.0.0
```

This will:
1. Build the app in Release configuration
2. Create an archive
3. Export a Developer ID signed app
4. Package it in a DMG file
5. Display checksums for verification

If the required signing identity is missing, the build should be treated as a local test build only and not uploaded publicly.

## Manual Release Process

### 1. Update Version Numbers

Update the version in:
- `Wndr.xcodeproj` → Target → General → Version
- `Wndr.xcodeproj` → Target → General → Build

### 2. Build the App

```bash
# Clean build folder
rm -rf build/

# Build archive
xcodebuild -project Wndr.xcodeproj \
    -scheme Wndr \
    -configuration Release \
    -archivePath build/Wndr.xcarchive \
    archive

# Export app
xcodebuild -exportArchive \
    -archivePath build/Wndr.xcarchive \
    -exportPath build/export \
    -exportOptionsPlist ExportOptions.plist
```

### 3. Create DMG

```bash
# Prepare DMG contents
mkdir -p build/dmg
cp -R build/export/Wndr.app build/dmg/

# Create DMG
hdiutil create -volname "Wndr" \
    -srcfolder build/dmg \
    -ov -format UDZO \
    build/Wndr-v1.0.0.dmg
```

### 4. Notarize the DMG

```bash
xcrun notarytool submit build/Wndr-v1.0.0.dmg \
  --apple-id "YOUR_APPLE_ID" \
  --password "YOUR_APP_SPECIFIC_PASSWORD" \
  --team-id "YOUR_TEAM_ID" \
  --wait

xcrun stapler staple build/Wndr-v1.0.0.dmg
xcrun stapler validate build/Wndr-v1.0.0.dmg
```

### 5. Create GitHub Release

```bash
# Tag the release
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0
```

Then:
1. Go to https://github.com/adamkz007/wndr/releases
2. Click "Create a new release"
3. Select the tag you just created
4. Upload the DMG file
5. Add release notes
6. Publish the release

## Automated Release via GitHub Actions

Push a version tag to trigger automatic builds:

```bash
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0
```

The GitHub Action will:
1. Import the Developer ID certificate from GitHub secrets
2. Build and export a signed app on macOS runners
3. Create and notarize the DMG package
4. Staple the notarization ticket
5. Create a GitHub release
6. Upload the DMG to the release

## Code Signing

### Local Signing

Update `ExportOptions.plist` with your team ID:
```xml
<key>teamID</key>
<string>YOUR_TEAM_ID</string>
```

Find your team ID:
```bash
security find-identity -v -p codesigning
```

### GitHub Actions Signing

For automated builds, add these secrets to your repository:
- `APPLE_CERTIFICATE`: Base64 encoded .p12 certificate
- `APPLE_CERTIFICATE_PASSWORD`: Certificate password
- `APPLE_TEAM_ID`: Your Apple Developer team ID
- `APPLE_ID`: Apple ID email used for notarization
- `APPLE_APP_SPECIFIC_PASSWORD`: App-specific password for notarization

## Testing the Release

Before releasing:

1. **Test the DMG**:
   ```bash
   # Mount the DMG
   hdiutil attach build/Wndr-v1.0.0.dmg

   # Copy to Applications
   cp -R /Volumes/Wndr/Wndr.app /Applications/

   # Unmount
   hdiutil detach /Volumes/Wndr
   ```

2. **Verify the app**:
   - Launch from Applications
   - Check all main features work
   - Verify version number in About panel

3. **Check code signing and Gatekeeper**:
   ```bash
   codesign -dv --verbose=4 /Applications/Wndr.app
   spctl -a -vvv /Applications/Wndr.app
   spctl -a -vvv --type open build/Wndr-v1.0.0.dmg
   ```

## User Workaround For Existing Unsigned Builds

If you already downloaded an older unsigned test build and trust its source, remove the quarantine flag after copying it to `Applications`:

```bash
xattr -dr com.apple.quarantine /Applications/Wndr.app
```

This is only a temporary workaround for local testing. The proper fix is to redistribute a notarized release.

## Landing Page Deployment

The landing page at `index.html` is automatically deployed to GitHub Pages when pushed to main:

```bash
git add index.html
git commit -m "Update landing page"
git push origin main
```

Access at: https://adamkz.github.io/wndr/

## Troubleshooting

### Build Fails

- Ensure Xcode is installed (not just Command Line Tools)
- Check that all Swift packages are resolved
- Clean build folder: `rm -rf ~/Library/Developer/Xcode/DerivedData/Wndr-*`

### Code Signing Issues

- Verify your signing certificate is valid: `security find-identity -v`
- Check keychain is unlocked: `security unlock-keychain`
- Ensure proper provisioning profile for Developer ID distribution

### DMG Creation Fails

- Ensure enough disk space (need ~3x app size)
- Check file permissions in build directory
- Try with simpler DMG format: `-format UDRO` instead of `-format UDZO`

## Version History

- v1.0.0 - Initial release
  - PDF viewing and highlighting
  - Markdown notes with live preview
  - Collections and tags
  - Full-text search
