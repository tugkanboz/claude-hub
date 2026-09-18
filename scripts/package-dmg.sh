#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app_path="${1:-$root/dist/ClaudeHub.app}"
dmg_path="${2:-$root/dist/ClaudeHub-macOS-arm64.dmg}"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

cp -R "$app_path" "$stage/ClaudeHub.app"
ln -s /Applications "$stage/Applications"
rm -f "$dmg_path"
hdiutil create -quiet -volname ClaudeHub -srcfolder "$stage" -ov -format UDZO "$dmg_path"
echo "$dmg_path"
