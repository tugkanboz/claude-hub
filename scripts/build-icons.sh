#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"

if [[ "${1:-}" == "--render-svg" ]]; then
  command -v rsvg-convert >/dev/null 2>&1 || { echo "rsvg-convert is required" >&2; exit 1; }
  rsvg-convert -w 1024 -h 1024 "$root/assets/app-icon.svg" > "$root/assets/AppIcon.png"
fi

iconset="$root/dist/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$root/assets/AppIcon.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$root/assets/AppIcon.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$root/dist/AppIcon.icns"
