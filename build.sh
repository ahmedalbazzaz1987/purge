#!/bin/bash
#
#  build.sh — builds Purge.app without Xcode.
#
#  Needs only the Command Line Tools (~200 MB), not the full Xcode app:
#      xcode-select --install
#
#  Usage:
#      ./build.sh              build into ./build/Purge.app
#      ./build.sh --install    build, then move it into /Applications and open it
#      ./build.sh --run        build and launch from ./build
#      ./build.sh --release    build and also produce a versioned .zip for GitHub
#

# macOS still ships bash 3.2, where `set -u` trips over empty arrays.
set -eo pipefail

cd "$(dirname "$0")"

APP_NAME="Purge"
BUNDLE_ID="com.novamira.purge"
VERSION="1.0.3"
MIN_MACOS="13.0"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"

bold()  { printf '\033[1m%s\033[0m\n' "$1"; }
ok()    { printf '  \033[32m✓\033[0m %s\n' "$1"; }
info()  { printf '  \033[36m•\033[0m %s\n' "$1"; }
fail()  { printf '  \033[31m✗\033[0m %s\n' "$1"; exit 1; }

bold "Building $APP_NAME $VERSION"

# ---------------------------------------------------------------- toolchain
if ! command -v swiftc >/dev/null 2>&1; then
  echo
  echo "  Swift compiler not found."
  echo "  Install Apple's Command Line Tools (about 200 MB, no Xcode needed):"
  echo
  echo "      xcode-select --install"
  echo
  exit 1
fi

if ! xcrun --show-sdk-path >/dev/null 2>&1; then
  fail "No macOS SDK found. Run: sudo xcode-select --reset"
fi

SDK="$(xcrun --show-sdk-path)"
ARCH="$(uname -m)"
case "$ARCH" in
  arm64) TARGET="arm64-apple-macos$MIN_MACOS" ;;
  x86_64) TARGET="x86_64-apple-macos$MIN_MACOS" ;;
  *) fail "Unsupported architecture: $ARCH" ;;
esac
ok "swiftc $(swiftc --version 2>/dev/null | head -1 | sed 's/.*version //;s/ .*//') · $ARCH"

# ---------------------------------------------------------------- macro plugins
#
# On recent SDKs several SwiftUI attributes (@State among them) are macros, not
# property wrappers. Xcode passes the macro plugin search paths for you; a bare
# swiftc does not, and the failure reads as "external macro implementation type
# 'SwiftUIMacros.StateMacro' could not be found". These flags are that missing
# piece. Everything is probed, so nothing breaks on an SDK without macros.

SWIFTC_BIN="$(xcrun -f swiftc)"
TOOLCHAIN="$(dirname "$(dirname "$(dirname "$SWIFTC_BIN")")")"
PLUGIN_SERVER="$TOOLCHAIN/usr/bin/swift-plugin-server"

PLUGIN_FLAGS=()

# Plugins that live in the toolchain load directly.
for d in "$TOOLCHAIN/usr/lib/swift/host/plugins" \
         "$TOOLCHAIN/usr/local/lib/swift/host/plugins"; do
  [ -d "$d" ] && PLUGIN_FLAGS+=(-plugin-path "$d")
done

# Plugins that ship inside the SDK are served by swift-plugin-server.
if [ -x "$PLUGIN_SERVER" ]; then
  for d in "$SDK/usr/lib/swift/host/plugins" \
           "$SDK/usr/local/lib/swift/host/plugins"; do
    [ -d "$d" ] && PLUGIN_FLAGS+=(-external-plugin-path "$d#$PLUGIN_SERVER")
  done
fi

# Last resort: go looking for it rather than failing with a cryptic message.
if ! ls "$TOOLCHAIN"/usr/lib/swift/host/plugins/*SwiftUIMacros* >/dev/null 2>&1 \
   && ! ls "$SDK"/usr/lib/swift/host/plugins/*SwiftUIMacros* >/dev/null 2>&1; then
  FOUND="$(find "$TOOLCHAIN" "$SDK" -maxdepth 8 -name '*SwiftUIMacros*' 2>/dev/null | head -1 || true)"
  if [ -n "$FOUND" ]; then
    DIR="$(dirname "$FOUND")"
    if [ -x "$PLUGIN_SERVER" ]; then
      PLUGIN_FLAGS+=(-external-plugin-path "$DIR#$PLUGIN_SERVER")
    else
      PLUGIN_FLAGS+=(-plugin-path "$DIR")
    fi
    info "Found SwiftUI macros in $DIR"
  fi
fi

PLUGIN_COUNT=${#PLUGIN_FLAGS[@]}
if [ "$PLUGIN_COUNT" -eq 0 ]; then
  info "No macro plugin paths found — continuing without them"
else
  ok "Macro plugins wired up ($((PLUGIN_COUNT / 2)) paths)"
fi

# ---------------------------------------------------------------- layout
rm -rf "$BUILD_DIR"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

SOURCES=$(find Sources -name '*.swift' | sort)
COUNT=$(echo "$SOURCES" | wc -l | tr -d ' ')
info "$COUNT source files"

# ---------------------------------------------------------------- compile
# -parse-as-library is what lets @main live in a normally-named file.
# Whole-module optimisation keeps the binary small and fast.
swiftc \
  -target "$TARGET" \
  -sdk "$SDK" \
  -swift-version 5 \
  -O -whole-module-optimization \
  -parse-as-library \
  ${PLUGIN_FLAGS[@]+"${PLUGIN_FLAGS[@]}"} \
  -framework SwiftUI -framework AppKit -framework Foundation -framework CryptoKit \
  -o "$APP/Contents/MacOS/$APP_NAME" \
  $SOURCES

ok "Compiled $(du -h "$APP/Contents/MacOS/$APP_NAME" | cut -f1 | tr -d ' ') binary"

# ---------------------------------------------------------------- icon
if [ -f Resources/icon.png ]; then
  ICONSET="$BUILD_DIR/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z $size $size Resources/icon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null 2>&1
    double=$((size * 2))
    sips -z $double $double Resources/icon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null 2>&1
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null \
    && ok "Icon built" || info "Icon skipped"
  rm -rf "$ICONSET"
fi

# ---------------------------------------------------------------- Info.plist
sed -e "s/__VERSION__/$VERSION/g" \
    -e "s/__BUNDLE_ID__/$BUNDLE_ID/g" \
    -e "s/__MIN_MACOS__/$MIN_MACOS/g" \
    Resources/Info.plist > "$APP/Contents/Info.plist"

printf 'APPL????' > "$APP/Contents/PkgInfo"
ok "Bundle assembled"

# ---------------------------------------------------------------- signing
# Ad-hoc signature. It is what lets a locally built app launch cleanly; it is
# not a Developer ID signature and does not claim to be one.
codesign --force --deep --sign - --timestamp=none "$APP" >/dev/null 2>&1 \
  && ok "Signed ad-hoc" || info "Could not sign (the app will still run)"

xattr -cr "$APP" 2>/dev/null || true

SIZE=$(du -sh "$APP" | cut -f1 | tr -d ' ')
echo
bold "Done — $APP ($SIZE)"

# ---------------------------------------------------------------- options
for arg in "$@"; do
  case "$arg" in
    --install)
      DEST="/Applications/$APP_NAME.app"
      if [ -d "$DEST" ]; then
        info "Replacing the existing copy in /Applications"
        rm -rf "$DEST"
      fi
      cp -R "$APP" "$DEST"
      xattr -cr "$DEST" 2>/dev/null || true
      ok "Installed to $DEST"
      open "$DEST"
      ;;
    --run)
      open "$APP"
      ;;
    --release)
      ZIP="$BUILD_DIR/$APP_NAME-$VERSION-macOS-$ARCH.zip"
      ditto -c -k --keepParent "$APP" "$ZIP"
      ok "Release archive: $ZIP"
      ;;
  esac
done

echo
echo "  First launch: macOS may say the developer cannot be verified."
echo "  Right-click the app → Open → Open. You only do this once."
echo
