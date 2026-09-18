#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "rsvg-convert is required to rebuild AppIcon.png" >&2
  exit 1
fi

rsvg-convert -w 1024 -h 1024 "$root/assets/app-icon.svg" > "$root/assets/AppIcon.png"
