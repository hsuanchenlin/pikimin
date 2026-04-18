#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build/release"
DMG_DIR="$PROJECT_DIR/.build/dmg"
APP_NAME="Pikimin"
DMG_NAME="Pikimin.dmg"
DMG_TMP="$PROJECT_DIR/.build/tmp.dmg"
VOL_NAME="$APP_NAME"

echo "Building release binary..."
cd "$PROJECT_DIR"
swift build -c release

echo "Creating app bundle..."
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR/$APP_NAME.app/Contents/MacOS"
mkdir -p "$DMG_DIR/$APP_NAME.app/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$DMG_DIR/$APP_NAME.app/Contents/MacOS/"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$DMG_DIR/$APP_NAME.app/Contents/Resources/"
cp "$PROJECT_DIR/Resources/ADBKeyboard.apk" "$DMG_DIR/$APP_NAME.app/Contents/Resources/"

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

codesign --force --sign - "$DMG_DIR/$APP_NAME.app"
ln -sf /Applications "$DMG_DIR/Applications"

echo "Creating DMG..."
rm -f "$DMG_TMP" "$PROJECT_DIR/$DMG_NAME"

hdiutil create \
    -volname "$VOL_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov \
    -format UDRW \
    -size 10m \
    "$DMG_TMP"

DEVICE=$(hdiutil attach "$DMG_TMP" -readwrite -noverify | grep "Apple_APFS\|Apple_HFS" | head -1 | awk '{print $1}')
sleep 3

# Set icon positions and window size
osascript << EOF
tell application "Finder"
    tell disk "$VOL_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 200, 680, 440}

        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 96

        set position of item "${APP_NAME}.app" of container window to {120, 120}
        set position of item "Applications" of container window to {360, 120}

        update without registering applications
        delay 2
        close
    end tell
end tell
EOF

sync
sleep 1
hdiutil detach "$DEVICE" -force 2>/dev/null || hdiutil detach "/Volumes/$VOL_NAME" -force 2>/dev/null || true
sleep 1

hdiutil convert "$DMG_TMP" -format UDZO -o "$PROJECT_DIR/$DMG_NAME"
rm -f "$DMG_TMP"

echo ""
echo "Done! Created: $PROJECT_DIR/$DMG_NAME"
echo "Size: $(du -h "$PROJECT_DIR/$DMG_NAME" | cut -f1)"
echo ""
echo "To install: open DMG, drag Pikimin.app to Applications."
