#!/bin/zsh
set -e

PROJECT_DIR="${0:A:h}"
cd "$PROJECT_DIR"

APP_NAME="Sunless"
BUILD_DIR="$PROJECT_DIR/build"
APP="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "Cleaning previous build..."
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS" "$RESOURCES"

echo "Building executable..."
swiftc *.swift -o "$MACOS/$APP_NAME"

echo "Copying resources..."
[[ -f sunless.png ]] && cp sunless.png "$RESOURCES/"
[[ -f sunny.png ]] && cp sunny.png "$RESOURCES/"

echo "Writing Info.plist..."
cat > "$CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>io.github.zorexsalvo.sunless</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "Ad-hoc signing..."
codesign --force --deep --sign - "$APP"

echo "Done: $APP"
echo "Drag it to /Applications or open it from Finder."
