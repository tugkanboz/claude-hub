#!/usr/bin/env bash
set -euo pipefail

output_dir="${1:-dist}"
project_root="$(cd "$(dirname "$0")/.." && pwd)"
app_name="ClaudeHub"
app_version="${CLAUDE_HUB_VERSION:-$(tr -d '[:space:]' < "$project_root/VERSION")}"
app_path="$project_root/$output_dir/$app_name.app"

cd "$project_root"
swift build -c release --arch arm64
binary_dir="$(swift build -c release --arch arm64 --show-bin-path)"

rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$binary_dir/$app_name" "$app_path/Contents/MacOS/$app_name"
cp "$project_root/assets/AppIcon.png" "$app_path/Contents/Resources/AppIcon.png"

cat > "$app_path/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>tr</string>
  <key>CFBundleDisplayName</key><string>ClaudeHub</string>
  <key>CFBundleExecutable</key><string>ClaudeHub</string>
  <key>CFBundleIconFile</key><string>AppIcon.png</string>
  <key>CFBundleIdentifier</key><string>com.tugkanboz.claudehub</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>ClaudeHub</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$app_version</string>
  <key>CFBundleVersion</key><string>$app_version</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - \
  --entitlements "$project_root/scripts/entitlements.plist" \
  "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"
echo "$app_path"
