#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build/release"
DMG_DIR="$PROJECT_DIR/.build/dmg"
APP_NAME="Pikimin"
DMG_NAME="Pikimin.dmg"

echo "Building release binary..."
cd "$PROJECT_DIR"
swift build -c release

echo "Creating app bundle..."
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR/$APP_NAME.app/Contents/MacOS"
mkdir -p "$DMG_DIR/$APP_NAME.app/Contents/Resources"

# Copy binary
cp "$BUILD_DIR/$APP_NAME" "$DMG_DIR/$APP_NAME.app/Contents/MacOS/"

# Copy resources
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$DMG_DIR/$APP_NAME.app/Contents/Resources/"
cp "$PROJECT_DIR/Resources/ADBKeyboard.apk" "$DMG_DIR/$APP_NAME.app/Contents/Resources/"

# Create Info.plist
cat > "$DMG_DIR/$APP_NAME.app/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Pikimin</string>
    <key>CFBundleIdentifier</key>
    <string>com.pikimin.app</string>
    <key>CFBundleName</key>
    <string>Pikimin</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSArchitecturePriority</key>
    <array>
        <string>arm64</string>
    </array>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</dict>
</plist>
PLIST

# Ad-hoc sign
codesign --force --sign - "$DMG_DIR/$APP_NAME.app"

echo "Creating DMG..."
rm -f "$PROJECT_DIR/$DMG_NAME"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov \
    -format UDZO \
    "$PROJECT_DIR/$DMG_NAME"

echo ""
echo "Done! Created: $PROJECT_DIR/$DMG_NAME"
echo "Size: $(du -h "$PROJECT_DIR/$DMG_NAME" | cut -f1)"
echo ""
echo "To install: open DMG, drag Pikimin.app to Applications."
echo "First launch: right-click -> Open to bypass Gatekeeper."
