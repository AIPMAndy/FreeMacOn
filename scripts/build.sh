#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $(uname -s) == Darwin ]] || { echo 'Build requires macOS and Xcode Command Line Tools.' >&2; exit 1; }
command -v swift >/dev/null || { echo 'Install Xcode Command Line Tools: xcode-select --install' >&2; exit 1; }
APP="$PWD/build/FreeMacOn.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
install -m 644 "$PWD/Resources/FreeMacOn.icns" "$APP/Contents/Resources/FreeMacOn.icns"
if [[ "${UNIVERSAL:-0}" == 1 ]]; then
  bins=()
  for arch in arm64 x86_64; do
    scratch="$PWD/.build/$arch"
    swift build --scratch-path "$scratch" --arch "$arch" -c release
    bins+=("$(swift build --scratch-path "$scratch" --arch "$arch" -c release --show-bin-path)/FreeMacOn")
  done
  /usr/bin/lipo -create "${bins[@]}" -output "$APP/Contents/MacOS/FreeMacOn"
  /usr/bin/lipo "$APP/Contents/MacOS/FreeMacOn" -verify_arch arm64
  /usr/bin/lipo "$APP/Contents/MacOS/FreeMacOn" -verify_arch x86_64
  chmod 755 "$APP/Contents/MacOS/FreeMacOn"
else
  swift build -c release
  BIN=$(swift build -c release --show-bin-path)/FreeMacOn
  install -m 755 "$BIN" "$APP/Contents/MacOS/FreeMacOn"
fi
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>FreeMacOn</string>
<key>CFBundleDisplayName</key><string>FreeMacOn</string>
<key>CFBundleIdentifier</key><string>vip.metaver.freemacon</string>
<key>CFBundleExecutable</key><string>FreeMacOn</string>
<key>CFBundleIconFile</key><string>FreeMacOn.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
/usr/bin/plutil -lint "$APP/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$APP"
/usr/bin/codesign --verify --strict --verbose=2 "$APP"
"$APP/Contents/MacOS/FreeMacOn" --version
"$APP/Contents/MacOS/FreeMacOn" --self-test
printf '\nBuilt: %s\n' "$APP"
