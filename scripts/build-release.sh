#!/bin/bash
# Build a universal, Developer ID signed and notarized distribution.
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TASK_ROOT"

: "${MAC_DUO_NOTARY_PROFILE:?Set MAC_DUO_NOTARY_PROFILE to a notarytool keychain profile}"
SIGNING_IDENTITY="${MAC_DUO_RELEASE_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning | awk '/"Developer ID Application:/{ print $2; exit }')"
fi
if [[ -z "$SIGNING_IDENTITY" || "$SIGNING_IDENTITY" == '-' ]]; then
    printf 'A Developer ID Application signing identity is required.\n' >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
OUTPUT="$TASK_ROOT/build/distribution/$VERSION"
SCRATCH="$TASK_ROOT/build/release-swiftpm"
APP="$OUTPUT/Mac Duo.app"
STEM="Mac-Duo-$VERSION-universal"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swift build -c release --arch arm64 --arch x86_64 --scratch-path "$SCRATCH"
BIN_PATH="$(swift build -c release --arch arm64 --arch x86_64 --scratch-path "$SCRATCH" --show-bin-path)"
cp "$BIN_PATH/MacDuo" "$APP/Contents/MacOS/MacDuo"
cp Resources/Info.plist "$APP/Contents/Info.plist"
swift scripts/make-icon.swift "$OUTPUT/AppIcon.iconset"
iconutil -c icns "$OUTPUT/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
lipo "$APP/Contents/MacOS/MacDuo" -verify_arch arm64 x86_64
plutil -lint "$APP/Contents/Info.plist"
codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$APP"
codesign --verify --strict --verbose=2 "$APP"

# Notarize the app first so both distribution formats include its offline ticket.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUTPUT/notarization.zip"
xcrun notarytool submit "$OUTPUT/notarization.zip" --keychain-profile "$MAC_DUO_NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUTPUT/$STEM.zip"

STAGE="$OUTPUT/dmg-content"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Mac Duo.app"
[[ -e "$STAGE/Applications" ]] || ln -s /Applications "$STAGE/Applications"
cp LICENSE "$STAGE/LICENSE.txt"
cat > "$STAGE/Read Me.txt" <<'EOF'
Mac Duo

Drag Mac Duo into Applications, then open it.
将 Mac Duo 拖入 Applications（应用程序），然后打开。

Allow Screen Recording when prompted. Screenshots stay in memory.
首次使用时允许屏幕录制。截图仅短暂保存在内存中。

macOS 14+. Universal app for Apple Silicon and Intel.
Automatic lid effects require a compatible hinge sensor.
自动合盖效果需要兼容的铰链传感器；也可点击「全屏试播」。

Website: https://norvancc.github.io/mac-duo/
Source: https://github.com/norvancc/mac-duo
MIT License
EOF
hdiutil create -volname 'Mac Duo' -srcfolder "$STAGE" -ov -format UDZO "$OUTPUT/$STEM.dmg"
codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$OUTPUT/$STEM.dmg"
xcrun notarytool submit "$OUTPUT/$STEM.dmg" --keychain-profile "$MAC_DUO_NOTARY_PROFILE" --wait
xcrun stapler staple "$OUTPUT/$STEM.dmg"
xcrun stapler validate "$OUTPUT/$STEM.dmg"
(cd "$OUTPUT" && shasum -a 256 "$STEM.dmg" "$STEM.zip" > SHA256SUMS.txt)
printf '\nRelease files: %s\n' "$OUTPUT"
