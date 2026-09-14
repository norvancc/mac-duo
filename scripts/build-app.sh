#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TASK_ROOT"
swift build -c release
APP="$TASK_ROOT/build/Mac Duo.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/MacDuo "$APP/Contents/MacOS/MacDuo"
cp Resources/Info.plist "$APP/Contents/Info.plist"
swift scripts/make-icon.swift "$TASK_ROOT/build/AppIcon.iconset"
iconutil -c icns "$TASK_ROOT/build/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
SIGNING_IDENTITY="${MAC_DUO_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning | awk '/"Apple Development:/{ print $2; exit }')"
fi
if [[ -z "$SIGNING_IDENTITY" || "$SIGNING_IDENTITY" == '-' ]]; then
    printf 'Mac Duo requires a stable Apple Development signing identity to preserve screen recording authorization. Set MAC_DUO_SIGNING_IDENTITY to its name or SHA-1.\n' >&2
    exit 1
fi
# Use the certificate's normal designated requirement. Do not replace it with
# a cdhash or identifier-only requirement; TCC must recognize later builds.
codesign --force --sign "$SIGNING_IDENTITY" --identifier app.norvan.MacDuo "$APP"
codesign --verify --strict "$APP"
plutil -lint "$APP/Contents/Info.plist"
printf 'Built: %s\n' "$APP"
