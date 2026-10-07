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
DEPLOYMENT_TARGET="12.0"

echo "Cleaning previous build..."
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS" "$RESOURCES"

echo "Building universal executable (arm64 + x86_64)..."
swiftc -target arm64-apple-macos$DEPLOYMENT_TARGET *.swift -o "$BUILD_DIR/$APP_NAME-arm64"
swiftc -target x86_64-apple-macos$DEPLOYMENT_TARGET *.swift -o "$BUILD_DIR/$APP_NAME-x86_64"
lipo -create "$BUILD_DIR/$APP_NAME-arm64" "$BUILD_DIR/$APP_NAME-x86_64" -output "$MACOS/$APP_NAME"
rm "$BUILD_DIR/$APP_NAME-arm64" "$BUILD_DIR/$APP_NAME-x86_64"

echo "Copying resources..."
[[ -f sunless.png ]] && cp sunless.png "$RESOURCES/"
[[ -f sunny.png ]] && cp sunny.png "$RESOURCES/"

if [[ -f sunless.png ]]; then
    echo "Generating app icon..."
    ICONSET="$BUILD_DIR/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for size in 16 32 128 256 512; do
        sips -z $size $size sunless.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null 2>&1
        sips -z $((size * 2)) $((size * 2)) sunless.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null 2>&1
    done
    iconutil -c icns "$ICONSET" -o "$RESOURCES/AppIcon.icns"
fi

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
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>$DEPLOYMENT_TARGET</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "Ad-hoc signing..."
codesign --force --deep --sign - "$APP"

echo "Done: $APP"
echo "Drag it to /Applications or open it from Finder."
