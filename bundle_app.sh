#!/bin/bash
#
# Builds the release binary and wraps it in a .app bundle.
#   ./bundle_app.sh             -> 360 Video Stitcher.app
#   ./bundle_app.sh --install   -> also copies it to /Applications
#
set -euo pipefail

EXECUTABLE="360VideoStitcher"
APP_BUNDLE="360 Video Stitcher.app"
DISPLAY_NAME="360 Video Stitcher"
BUNDLE_IDENTIFIER="com.merajc.360VideoStitcher"
BUILD_DIR=".build/release"
RESOURCE_BUNDLE="360VideoStitcher_Stitcher360.bundle"

CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "🚀 Building $DISPLAY_NAME in release mode..."
swift build -c release

echo "📦 Creating app bundle structure..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS" "$RESOURCES"

if [[ ! -x "$BUILD_DIR/$EXECUTABLE" ]]; then
    echo "❌ Expected binary at $BUILD_DIR/$EXECUTABLE — build failed?" >&2
    exit 1
fi

cp "$BUILD_DIR/$EXECUTABLE" "$MACOS/"

# Copy the SwiftPM resource bundle (contains EACShader.msl).
if [[ -d "$BUILD_DIR/$RESOURCE_BUNDLE" ]]; then
    cp -R "$BUILD_DIR/$RESOURCE_BUNDLE" "$RESOURCES/"
else
    echo "⚠️  Resource bundle not found in $BUILD_DIR; the app will not render." >&2
fi

cat > "$CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_IDENTIFIER</string>
    <key>CFBundleName</key>
    <string>$DISPLAY_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$DISPLAY_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.video</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>MIT licensed. GoPro is a trademark of GoPro, Inc.</string>
</dict>
</plist>
EOF

# Ad-hoc signature so the app launches without the "damaged" Gatekeeper warning.
echo "🔏 Signing (ad-hoc)..."
codesign --force --sign - "$APP_BUNDLE" >/dev/null

echo "✨ App bundle created: $APP_BUNDLE"

if [[ "${1:-}" == "--install" ]]; then
    echo "📲 Installing to /Applications..."
    rm -rf "/Applications/$APP_BUNDLE"
    cp -R "$APP_BUNDLE" /Applications/
    echo "✅ Successfully installed to /Applications!"
fi
