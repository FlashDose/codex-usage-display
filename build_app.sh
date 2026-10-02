#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$PROJECT_DIR/dist/Codex Usage Bar.app"
BUILD_DIR="$PROJECT_DIR/.build"

if [[ -n "${MACOS_SDK_PATH:-}" ]]; then
    SDK_PATH="$MACOS_SDK_PATH"
else
    DEVELOPER_DIR="$(xcode-select -p)"
    if [[ "$DEVELOPER_DIR" == *CommandLineTools ]]; then
        SDK_DIR="$DEVELOPER_DIR/SDKs"
    else
        SDK_DIR="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs"
    fi
    if [[ -d "$SDK_DIR/MacOSX26.5.sdk" ]]; then
        SDK_PATH="$SDK_DIR/MacOSX26.5.sdk"
    else
        SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
    fi
fi

cd "$PROJECT_DIR"
mkdir -p "$BUILD_DIR/module-cache" "$APP_DIR/Contents/MacOS"
cp "$PROJECT_DIR/Sources/CodexUsageBar/main.swift" "$BUILD_DIR/main.swift"
swiftc \
    -parse-as-library \
    -sdk "$SDK_PATH" \
    -target "$(uname -m)-apple-macosx13.0" \
    -swift-version 5 \
    -module-cache-path "$BUILD_DIR/module-cache" \
    "$BUILD_DIR/main.swift" \
    -o "$BUILD_DIR/CodexUsageBar"

cp "$BUILD_DIR/CodexUsageBar" "$APP_DIR/Contents/MacOS/CodexUsageBar"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Codex Usage Bar</string>
    <key>CFBundleDisplayName</key>
    <string>Codex Usage Bar</string>
    <key>CFBundleIdentifier</key>
    <string>io.github.flashdose.codex-usage-display</string>
    <key>CFBundleExecutable</key>
    <string>CodexUsageBar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>MacOSX</string>
    </array>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"
echo "Created: $APP_DIR"
