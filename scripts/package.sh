#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# Fail-closed signing policy shared with .github/scripts/ci-build-dmg.sh.
source "$ROOT_DIR/scripts/release-lib.sh"
source "$ROOT_DIR/scripts/appintents-metadata.sh"

APP_NAME="MosaClip"
DMG_BASENAME="MosaClip"
EXECUTABLE_NAME="MosaClip"
# SwiftPM 产物名(Package.swift 内部符号,本轮更名有意不改,见
# docs/RENAME_CHECKLIST.md);与 EXECUTABLE_NAME 解耦:前者定位构建产物,
# 后者决定 .app 内二进制名。
SWIFTPM_PRODUCT_NAME="PasteMemo"
MCP_EXECUTABLE_NAME="pastememo-mcp"
DEFAULT_BUNDLE_ID="com.mumulei.mosaclip"
MIN_SYSTEM_VERSION="14.0"
VERSION_FILE="$ROOT_DIR/VERSION"

ARCH="${ARCH:-$(uname -m)}"
CONFIGURATION="${CONFIGURATION:-release}"
BUNDLE_ID="${BUNDLE_ID:-$DEFAULT_BUNDLE_ID}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
ICON_FILE="$ROOT_DIR/Sources/Resources/AppIcon.icns"
ENTITLEMENTS_FILE="$ROOT_DIR/.github/scripts/release-entitlements.plist"
LICENSE_FILE="$ROOT_DIR/LICENSE"
NOTICES_FILE="$ROOT_DIR/THIRD_PARTY_NOTICES.md"

# --- Signing policy --------------------------------------------------------
# SIGNING_MODE selects the trust level of the produced artifact:
#
#   adhoc         Local QA build (default). Uses an ad-hoc signature ("-") or,
#                 if explicitly provided, any local development identity.
#                 Artifacts from this mode MUST NOT ship outside the dev machine.
#
#   developer-id  Production build. Requires a genuine
#                 "Developer ID Application: ..." identity (auto-detected from
#                 the keychain, or pinned via CODESIGN_IDENTITY), hardened
#                 runtime, a secure timestamp and the release entitlements.
#                 Fails closed on "-", Apple Development / Mac Developer /
#                 Apple Distribution identities, or ambiguous keychains.
#
# See docs/MOSACLIP_DISTRIBUTION.md for the full trust-chain documentation.
SIGNING_MODE="${SIGNING_MODE:-adhoc}"
REQUESTED_CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"

resolve_version() {
  if [[ -n "${VERSION:-}" ]]; then
    printf '%s\n' "$VERSION"
    return 0
  fi

  if [[ -f "$VERSION_FILE" ]]; then
    local file_version
    file_version="$(tr -d '[:space:]' < "$VERSION_FILE")"
    if [[ -n "$file_version" ]]; then
      printf '%s\n' "$file_version"
      return 0
    fi
  fi

  if git -C "$ROOT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    local tag
    tag="$(git -C "$ROOT_DIR" describe --tags --abbrev=0 2>/dev/null || true)"
    tag="${tag#v}"
    if [[ -n "$tag" ]]; then
      printf '%s\n' "$tag"
      return 0
    fi
  fi

  echo "VERSION is not set, VERSION file is empty or missing, and no git tag was found." >&2
  echo "Use: make package VERSION=1.2.3" >&2
  exit 1
}

print_metadata() {
  cat <<EOF
APP_NAME=${APP_NAME}
DMG_BASENAME=${DMG_BASENAME}
EXECUTABLE_NAME=${EXECUTABLE_NAME}
SWIFTPM_PRODUCT_NAME=${SWIFTPM_PRODUCT_NAME}
MCP_EXECUTABLE_NAME=${MCP_EXECUTABLE_NAME}
BUNDLE_ID=${BUNDLE_ID}
MIN_SYSTEM_VERSION=${MIN_SYSTEM_VERSION}
VERSION=${VERSION}
ENTITLEMENTS_FILE=${ENTITLEMENTS_FILE}
EOF
}

case "${1:-}" in
  --print-version)
    resolve_version
    exit 0
    ;;
  --print-metadata)
    VERSION="$(resolve_version)"
    print_metadata
    exit 0
    ;;
  --resolve-signing)
    rs_mode="${2:-}"
    if [[ -z "$rs_mode" ]]; then
      echo "usage: package.sh --resolve-signing <adhoc|developer-id>" >&2
      exit 64
    fi
    rs_resolved="$(release_resolve_codesign_identity "$rs_mode" "$REQUESTED_CODESIGN_IDENTITY")" || exit 1
    printf '%s\n' "$rs_resolved"
    exit 0
    ;;
esac

VERSION="$(resolve_version)"

# Resolve the signing identity up front so an unusable production environment
# fails before any minutes-long build work happens.
CODESIGN_IDENTITY="$(release_resolve_codesign_identity "$SIGNING_MODE" "$REQUESTED_CODESIGN_IDENTITY")" || {
  echo "[package] refusing to package (SIGNING_MODE=$SIGNING_MODE)." >&2
  exit 1
}
IS_PRODUCTION_SIGNING=false
if [[ "$SIGNING_MODE" == "developer-id" ]]; then
  IS_PRODUCTION_SIGNING=true
fi

APP_DIR="$DIST_DIR/${APP_NAME}.app"
DMG_PATH="$DIST_DIR/${DMG_BASENAME}-${VERSION}-${ARCH}.dmg"
STAGING_DIR="$DIST_DIR/.dmg-staging"

# Xcode 27 / Swift 6.4 may place products under the native build backend's
# Products directory instead of the legacy .build/<triple>/<configuration>
# path. Ask SwiftPM for the real path so a stale binary can never be packaged.
SWIFT_BUILD=(swift build -c "$CONFIGURATION" --arch "$ARCH" --build-system native "${APPINTENTS_SWIFTC_FLAGS[@]}")
if [[ -n "${SWIFT_SCRATCH_PATH:-}" ]]; then
  SWIFT_BUILD+=(--scratch-path "$SWIFT_SCRATCH_PATH")
fi
BUILD_DIR="$("${SWIFT_BUILD[@]}" --show-bin-path)"
PRODUCT_BINARY="$BUILD_DIR/$SWIFTPM_PRODUCT_NAME"
MCP_BINARY="$BUILD_DIR/$MCP_EXECUTABLE_NAME"

printf '[package] building %s %s (%s, signing mode: %s)\n' "$APP_NAME" "$VERSION" "$ARCH" "$SIGNING_MODE"
# Remove old products first: if the build produces nothing, the existence
# checks below must fail instead of silently shipping yesterday's executable.
rm -f "$PRODUCT_BINARY" "$MCP_BINARY"
"${SWIFT_BUILD[@]}" --product "$SWIFTPM_PRODUCT_NAME"
"${SWIFT_BUILD[@]}" --product "$MCP_EXECUTABLE_NAME"

if [[ ! -x "$PRODUCT_BINARY" ]]; then
  echo "Built binary not found: $PRODUCT_BINARY" >&2
  exit 1
fi
if [[ ! -x "$MCP_BINARY" ]]; then
  echo "Built MCP helper not found: $MCP_BINARY" >&2
  exit 1
fi

for binary in "$PRODUCT_BINARY" "$MCP_BINARY"; do
  if ! lipo -archs "$binary" | tr ' ' '\n' | grep -qx "$ARCH"; then
    echo "Built binary is $(lipo -archs "$binary"), expected $ARCH: $binary" >&2
    exit 1
  fi
done

EXPECTED_SDK="$(xcrun --show-sdk-version)"
LINKED_SDK="$(otool -l "$PRODUCT_BINARY" | awk '/LC_BUILD_VERSION/{found=1} found && /sdk/{print $2; exit}')"
if [[ "$LINKED_SDK" != "$EXPECTED_SDK" ]]; then
  echo "LC_BUILD_VERSION sdk=$LINKED_SDK, expected $EXPECTED_SDK: $PRODUCT_BINARY" >&2
  exit 1
fi

# Glob every *.bundle produced by SwiftPM resource targets. Hard-coding names
# silently misses new SPM dependencies and crashes Bundle.module at runtime.
RESOURCE_BUNDLES=("$BUILD_DIR"/*.bundle)
if [[ ! -d "${RESOURCE_BUNDLES[0]}" ]]; then
  echo "No SwiftPM resource bundles found in $BUILD_DIR" >&2
  exit 1
fi

if [[ ! -f "$ICON_FILE" ]]; then
  echo "App icon not found: $ICON_FILE" >&2
  exit 1
fi

for required_file in "$ENTITLEMENTS_FILE" "$LICENSE_FILE" "$NOTICES_FILE"; do
  if [[ ! -f "$required_file" ]]; then
    echo "Required release file not found: $required_file" >&2
    exit 1
  fi
done

rm -rf "$APP_DIR" "$STAGING_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$DIST_DIR"

cp "$PRODUCT_BINARY" "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
cp "$MCP_BINARY" "$APP_DIR/Contents/MacOS/$MCP_EXECUTABLE_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$MCP_EXECUTABLE_NAME"
cp "$ICON_FILE" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$LICENSE_FILE" "$APP_DIR/Contents/Resources/LICENSE"
cp "$NOTICES_FILE" "$APP_DIR/Contents/Resources/THIRD_PARTY_NOTICES.md"
for bundle in "${RESOURCE_BUNDLES[@]}"; do
  cp -R "$bundle" "$APP_DIR/Contents/Resources/"
done

CURRENT_YEAR="$(date +%Y)"
appintents_install_strings "$APP_DIR"
appintents_install_metadata "$BUILD_DIR" "$ARCH" "$APP_DIR"

cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleExecutable</key>
  <string>${EXECUTABLE_NAME}</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key>
  <string>${MIN_SYSTEM_VERSION}</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © ${CURRENT_YEAR} lifedever and MosaClip contributors. Licensed under GPL-3.0.</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>MosaClip needs to communicate with Finder to save images to folders.</string>
</dict>
</plist>
EOF

# --- Post-signature verification -------------------------------------------
# Reads embedded entitlements (XML when available, DER normalized via plutil)
# and refuses bundles that enable get-task-allow: it would break notarization
# and exposes debuggability in shipped builds.
verify_entitlements_safety() {
  local bundle_path="$1"
  local raw=""
  raw="$(codesign -d --entitlements - --xml "$bundle_path" 2>/dev/null || true)"
  if [[ -z "$raw" ]]; then
    raw="$(codesign -d --entitlements :- "$bundle_path" 2>/dev/null || true)"
  fi
  if [[ -z "$raw" ]]; then
    echo "[package] ERROR: could not read embedded entitlements of $bundle_path" >&2
    return 1
  fi
  local normalized=""
  if normalized="$(plutil -convert xml1 -o - - <<<"$raw" 2>/dev/null)" && [[ -n "$normalized" ]]; then
    raw="$normalized"
  fi
  if grep -q 'com.apple.security.get-task-allow' <<<"$raw"; then
    if grep -A1 'com.apple.security.get-task-allow' <<<"$raw" | grep -q '<true/>'; then
      echo "[package] ERROR: com.apple.security.get-task-allow is true; refusing to ship a debuggable bundle." >&2
      return 1
    fi
  fi
}

# Production-only attributes: hardened runtime, secure timestamp and a real
# TeamIdentifier must all be present in the outer signature.
verify_production_signature_attributes() {
  local bundle_path="$1"
  local display=""
  display="$(codesign -dv "$bundle_path" 2>&1 || true)"
  local failed=0
  if ! grep -q 'Runtime Version=' <<<"$display"; then
    echo "[package] ERROR: hardened runtime flag missing from signature of $bundle_path" >&2
    failed=1
  fi
  if ! grep -q 'Timestamp=' <<<"$display"; then
    echo "[package] ERROR: secure timestamp missing from signature of $bundle_path" >&2
    failed=1
  fi
  if ! grep -Eq '^TeamIdentifier=[A-Z0-9]+' <<<"$display"; then
    echo "[package] ERROR: signature of $bundle_path has no TeamIdentifier (ad-hoc or untrusted identity?)" >&2
    failed=1
  fi
  if [[ -n "${APPLE_TEAM_ID:-}" ]]; then
    local detected
    detected="$(release_team_id_from_identity "$CODESIGN_IDENTITY")"
    if [[ -z "$detected" || "$detected" != "$APPLE_TEAM_ID" ]]; then
      echo "[package] ERROR: signing identity Team ID (${detected:-unknown}) does not match APPLE_TEAM_ID ($APPLE_TEAM_ID)" >&2
      failed=1
    fi
  fi
  return "$failed"
}

printf '[package] codesigning helper and app (%s mode) as %s\n' "$SIGNING_MODE" "$CODESIGN_IDENTITY"
# macOS 自带 bash 3.2 在 set -u 下展开空数组会报 unbound variable,
# 用 ${arr[@]+...} 条件展开兼容 ad-hoc 签名(CODESIGN_IDENTITY="-")路径。
if [[ "$CODESIGN_IDENTITY" != "-" ]]; then
  SIGN_TIMESTAMP=(--timestamp)
fi
# Inside-out signing: nested code first (helper here; SwiftPM resource bundles
# carry no executable code and are covered by the outer seal), then the app.
codesign --force ${SIGN_TIMESTAMP[@]+"${SIGN_TIMESTAMP[@]}"} --options runtime \
  --sign "$CODESIGN_IDENTITY" "$APP_DIR/Contents/MacOS/$MCP_EXECUTABLE_NAME"
codesign --force ${SIGN_TIMESTAMP[@]+"${SIGN_TIMESTAMP[@]}"} --options runtime \
  --entitlements "$ENTITLEMENTS_FILE" \
  --sign "$CODESIGN_IDENTITY" "$APP_DIR"

codesign --verify --deep --strict --verbose=4 "$APP_DIR"
codesign --verify --strict --verbose=4 "$APP_DIR/Contents/MacOS/$MCP_EXECUTABLE_NAME"
verify_entitlements_safety "$APP_DIR"
if [[ "$IS_PRODUCTION_SIGNING" == true ]]; then
  verify_production_signature_attributes "$APP_DIR"
  printf '[package] signature details:\n%s\n' "$(codesign -dv "$APP_DIR" 2>&1)"
fi

mkdir -p "$STAGING_DIR"
cp -R "$APP_DIR" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
rm -f "$DMG_PATH"

printf '[package] creating dmg %s\n' "$(basename "$DMG_PATH")"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

codesign --force ${SIGN_TIMESTAMP[@]+"${SIGN_TIMESTAMP[@]}"} --sign "$CODESIGN_IDENTITY" "$DMG_PATH"
codesign --verify --strict --verbose=4 "$DMG_PATH"

rm -rf "$STAGING_DIR"

printf '[package] mode: %s\n' "$SIGNING_MODE"
printf '[package] app: %s\n' "$APP_DIR"
printf '[package] dmg: %s\n' "$DMG_PATH"
if [[ "$IS_PRODUCTION_SIGNING" == true ]]; then
  printf '[package] next: notarize + staple via .github/scripts/ci-build-dmg.sh\n'
else
  printf '[package] NOTE: ad-hoc/local artifact — do not distribute outside this machine.\n'
fi
