#!/usr/bin/env bash
# MosaClip production distribution pipeline (Developer ID + notarization).
#
# Replaces the former fail-closed placeholder. This is the single canonical
# entry point for producing a releasable DMG, both locally (when Apple
# credentials exist on this machine) and from GitHub Actions.
#
# Pipeline:
#   preflight (toolchain, Developer ID identity, notary credential)
#     -> swift build + package.sh SIGNING_MODE=developer-id (fail closed)
#     -> independent signature / Info.plist verification
#     -> notarytool submit --wait (Accepted only)
#     -> stapler staple + validate
#     -> Gatekeeper spctl assessments (app inside DMG, DMG itself)
#     -> quarantine simulation + spctl (+ optional github-hosted launch smoke)
#     -> SHA-256 computed AFTER stapling -> checksums.txt + verification report
#
# Credentials (never logged, never committed):
#   App Store Connect API key:
#     APPLE_API_KEY_ID, APPLE_API_ISSUER_ID and either APPLE_API_KEY_PATH or
#     APPLE_API_KEY_P8_BASE64 (contents base64-encoded .p8).
#   ...or a notarytool keychain profile named by NOTARY_KEYCHAIN_PROFILE
#   (default: MosaClipNotary), created once via
#     xcrun notarytool store-credentials MosaClipNotary ...
#
# Online publishing stays out of scope: this script never uploads a GitHub
# Release and never touches the updater (ReleaseIdentity.onlineUpdatesEnabled
# must remain false).
#
# Usage:
#   .github/scripts/ci-build-dmg.sh                # full pipeline
#   VERIFY_ONLY=<path.dmg> .github/scripts/ci-build-dmg.sh
#   MOSACLIP_LAUNCH_SMOKE=1 .github/scripts/ci-build-dmg.sh   # also launch-test
#       (GitHub-hosted Actions runners only; fails closed elsewhere)

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT_DIR/scripts/release-lib.sh"

PKG_SCRIPT="$ROOT_DIR/scripts/package.sh"
ENTITLEMENTS_FILE="$ROOT_DIR/.github/scripts/release-entitlements.plist"

ARCH="${ARCH:-$(uname -m)}"
CONFIGURATION="${CONFIGURATION:-release}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
NOTARY_KEYCHAIN_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-MosaClipNotary}"
LAUNCH_SMOKE="${MOSACLIP_LAUNCH_SMOKE:-0}"

log() { printf '[ci-release] %s\n' "$*"; }
die() { printf '[ci-release] ERROR: %s\n' "$*" >&2; exit 1; }

require_file() { [[ -f "$1" ]] || die "required file missing: $1"; }

plist_get_at() { plutil -extract "$1" raw -o - "$2/Contents/Info.plist" 2>/dev/null; }

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  [[ "$actual" == "$expected" ]] ||
    die "$label mismatch: expected '$expected', found '$actual'."
}

# Metadata gates applied to an app bundle. `expected_min` may be empty when
# re-verifying an artifact whose provenance pins its own minimum version.
assert_bundle_metadata() {
  local bundle="$1" expected_min="${2:-}"
  assert_eq "CFBundleDisplayName" "MosaClip" "$(plist_get_at CFBundleDisplayName "$bundle")"
  assert_eq "CFBundleExecutable" "MosaClip" "$(plist_get_at CFBundleExecutable "$bundle")"
  assert_eq "CFBundleIdentifier" "com.mumulei.mosaclip" "$(plist_get_at CFBundleIdentifier "$bundle")"
  assert_eq "CFBundleVersion vs ShortVersion" \
    "$(plist_get_at CFBundleVersion "$bundle")" \
    "$(plist_get_at CFBundleShortVersionString "$bundle")"
  if [[ -n "$expected_min" ]]; then
    assert_eq "LSMinimumSystemVersion" "$expected_min" "$(plist_get_at LSMinimumSystemVersion "$bundle")"
  fi
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild not found; run under a full Xcode toolchain."
command -v xcrun >/dev/null 2>&1 || die "xcrun not found."
command -v hdiutil >/dev/null 2>&1 || die "hdiutil not found (macOS only)."
command -v spctl >/dev/null 2>&1 || die "spctl not found (macOS only)."
xcodebuild -version >/dev/null 2>&1 || die "xcodebuild -version failed; Xcode license accepted?"
xcrun notarytool --version >/dev/null 2>&1 || die "notarytool unavailable; update Command Line Tools/Xcode."

for f in "$PKG_SCRIPT" "$ENTITLEMENTS_FILE" "$ROOT_DIR/Sources/Engine/ReleaseIdentity.swift"; do
  require_file "$f"
done

VERSION="${VERSION:-$(bash "$PKG_SCRIPT" --print-version)}"
APP_PATH="$DIST_DIR/MosaClip.app"
DMG_PATH="$DIST_DIR/MosaClip-${VERSION}-${ARCH}.dmg"

# VERIFY_ONLY re-validates an existing (presumably notarized + stapled) DMG:
# signature, staple ticket, Gatekeeper, quarantine and a fresh post-staple
# SHA-256 + report — with no rebuild, no re-signing and no re-notarization.
VERIFY_ONLY="${VERIFY_ONLY:-}"
if [[ -n "$VERIFY_ONLY" ]]; then
  DMG_PATH="$(cd "$(dirname "$VERIFY_ONLY")" && pwd)/$(basename "$VERIFY_ONLY")"
fi

if [[ -z "$VERIFY_ONLY" ]]; then

# --- Signing identity (fail closed, no ad-hoc fallback) --------------------
log "resolving Developer ID identity"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
RESOLVED_IDENTITY="$(bash "$PKG_SCRIPT" --resolve-signing developer-id "$CODESIGN_IDENTITY")" ||
  die "Developer ID identity resolution failed; see message above."
TEAM_ID="$(release_team_id_from_identity "$RESOLVED_IDENTITY")"
log "identity: $RESOLVED_IDENTITY"
log "team id: ${TEAM_ID:-unknown}"
if [[ -n "${APPLE_TEAM_ID:-}" && "$TEAM_ID" != "$APPLE_TEAM_ID" ]]; then
  die "certificate Team ID ($TEAM_ID) does not match APPLE_TEAM_ID (${APPLE_TEAM_ID})."
fi

# --- Notarization credential (existence probes only; never print secrets) --
API_KEY_MODE=0
PROFILE_MODE=0
API_KEY_FILE=""
API_KEY_TMPDIR=""
CLEANUP_API_KEY_FILE=""
if [[ -n "${APPLE_API_KEY_ID:-}" && -n "${APPLE_API_ISSUER_ID:-}" ]]; then
  API_KEY_MODE=1
  if [[ -n "${APPLE_API_KEY_PATH:-}" ]]; then
    API_KEY_FILE="$APPLE_API_KEY_PATH"
  elif [[ -n "${APPLE_API_KEY_P8_BASE64:-}" ]]; then
    API_KEY_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/mosaclip-apikey.XXXXXX")"
    API_KEY_FILE="$API_KEY_TMPDIR/AuthKey.p8"
    CLEANUP_API_KEY_FILE="$API_KEY_TMPDIR"
    printf '%s' "$APPLE_API_KEY_P8_BASE64" | base64 --decode > "$API_KEY_FILE"
    chmod 600 "$API_KEY_FILE"
  else
    die "APPLE_API_KEY_ID/APPLE_API_ISSUER_ID are set but neither APPLE_API_KEY_PATH nor APPLE_API_KEY_P8_BASE64 provides the .p8 key."
  fi
  [[ -s "$API_KEY_FILE" ]] || die "App Store Connect API key file is empty or missing: $API_KEY_FILE"
  NOTARY_ARGS=(--key "$API_KEY_FILE" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER_ID")
  log "notary credential: App Store Connect API key (${APPLE_API_KEY_ID})"
else
  PROFILE_MODE=1
  # Probe that the profile resolves without printing any credential material.
  xcrun notarytool history --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" >/dev/null 2>&1 ||
    die "no usable notarization credential: no App Store Connect API env vars and keychain profile '$NOTARY_KEYCHAIN_PROFILE' is not configured. Create it once with: xcrun notarytool store-credentials $NOTARY_KEYCHAIN_PROFILE ..."
  NOTARY_ARGS=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
  log "notary credential: keychain profile (${NOTARY_KEYCHAIN_PROFILE})"
fi

# ---------------------------------------------------------------------------
# Build + sign (delegates to package.sh which enforces the same policy)
# ---------------------------------------------------------------------------
log "building and signing (developer-id)"
SIGNING_MODE=developer-id \
  CODESIGN_IDENTITY="$RESOLVED_IDENTITY" \
  ARCH="$ARCH" CONFIGURATION="$CONFIGURATION" DIST_DIR="$DIST_DIR" \
  bash "$PKG_SCRIPT"

[[ -d "$APP_PATH" ]] || die "expected app bundle was not produced: $APP_PATH"
[[ -f "$DMG_PATH" ]] || die "expected DMG was not produced: $DMG_PATH"

# ---------------------------------------------------------------------------
# Independent post-build verification (does not trust package.sh internals)
# ---------------------------------------------------------------------------
log "verifying signatures independently"
codesign --verify --deep --strict --verbose=4 "$APP_PATH" ||
  die "deep strict codesign verify failed for app bundle."
HELPER="$APP_PATH/Contents/MacOS/pastememo-mcp"
[[ -x "$HELPER" ]] || die "MCP helper missing from bundle: $HELPER"
codesign --verify --strict --verbose=4 "$HELPER" ||
  die "helper signature verification failed."
codesign --verify --strict --verbose=4 "$DMG_PATH" ||
  die "DMG signature verification failed."

DISPLAY_OUT="$(codesign -dv "$APP_PATH" 2>&1)"
grep -q 'Runtime Version=' <<<"$DISPLAY_OUT" || die "hardened runtime not enabled on app signature."
grep -q 'Timestamp=' <<<"$DISPLAY_OUT" || die "secure timestamp missing from app signature."
grep -Eq '^TeamIdentifier=[A-Z0-9]+' <<<"$DISPLAY_OUT" || die "app signature has no TeamIdentifier."

# --- Info.plist metadata gates ---------------------------------------------
plist_get() { plutil -extract "$1" raw -o - "$APP_PATH/Contents/Info.plist" 2>/dev/null; }
META_MIN_SYSTEM="$(bash "$PKG_SCRIPT" --print-metadata | sed -n 's/^MIN_SYSTEM_VERSION=//p')"

assert_bundle_metadata "$APP_PATH" "$META_MIN_SYSTEM"
assert_eq "CFBundleShortVersionString" "$VERSION" "$(plist_get CFBundleShortVersionString)"

grep -q 'static let onlineUpdatesEnabled = false' "$ROOT_DIR/Sources/Engine/ReleaseIdentity.swift" ||
  die "ReleaseIdentity.onlineUpdatesEnabled must remain false; refusing to build a distribution artifact."

# ---------------------------------------------------------------------------
# Notarization (--wait; only status=Accepted proceeds)
# ---------------------------------------------------------------------------
log "submitting DMG to Apple notarization (this can take minutes)"
SUBMIT_JSON="$(xcrun notarytool submit "$DMG_PATH" "${NOTARY_ARGS[@]}" --wait --output-format json)" ||
  die "notarytool submit failed."
SUBMISSION_ID="$(awk -F'"' '/"id"/{print $4; exit}' <<<"$SUBMIT_JSON")"
STATUS="$(awk -F'"' '/"status"/{print $4; exit}' <<<"$SUBMIT_JSON")"
log "submission id: ${SUBMISSION_ID:-unknown}"
log "notarization status: ${STATUS:-unknown}"
if [[ "$STATUS" != "Accepted" ]]; then
  if [[ -n "$SUBMISSION_ID" ]]; then
    xcrun notarytool log "$SUBMISSION_ID" "${NOTARY_ARGS[@]}" >&2 || true
  fi
  die "notarization did not reach Accepted (status=${STATUS:-unknown}); see log above."
fi

# ---------------------------------------------------------------------------
# Staple + validate
# ---------------------------------------------------------------------------
log "stapling ticket to DMG"
xcrun stapler staple "$DMG_PATH" || die "stapler staple failed."
xcrun stapler validate "$DMG_PATH" || die "stapler validate failed."
log "staple validated"

else

# --- Re-verification of an existing DMG (no rebuild / no re-notarization) --
log "re-verification only: $DMG_PATH"
[[ -f "$DMG_PATH" ]] || die "VERIFY_ONLY DMG not found: $DMG_PATH"
codesign --verify --strict --verbose=4 "$DMG_PATH" ||
  die "DMG signature verification failed."
xcrun stapler validate "$DMG_PATH" ||
  die "stapler validate failed: this DMG does not carry a valid notarization ticket."
log "existing staple ticket validated"
SUBMISSION_ID="(pre-existing ticket; not re-submitted in VERIFY_ONLY mode)"
STATUS="StapleTicketValid"

fi

# ---------------------------------------------------------------------------
# Gatekeeper assessments
# ---------------------------------------------------------------------------
MNT_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mosaclip-verify.XXXXXX")"
MNT="$MNT_ROOT/mnt"
mkdir -p "$MNT"
cleanup_verify_dirs() {
  hdiutil detach "$MNT" >/dev/null 2>&1 || true
  rm -rf "$MNT_ROOT" 2>/dev/null || true
  [[ -z "$CLEANUP_API_KEY_FILE" ]] || rm -rf "$CLEANUP_API_KEY_FILE"
}
trap cleanup_verify_dirs EXIT

log "mounting DMG read-only for Gatekeeper assessment"
hdiutil attach -readonly -nobrowse -mountpoint "$MNT" "$DMG_PATH" >/dev/null ||
  die "could not mount DMG."
MOUNTED_APP="$MNT/MosaClip.app"
[[ -d "$MOUNTED_APP" ]] || die "mounted DMG does not contain MosaClip.app."

# The artifact actually being distributed must satisfy the same identity and
# metadata gates as the freshly built one — re-check from the mounted volume.
assert_bundle_metadata "$MOUNTED_APP" ""
DETECTED_VERSION="$(plist_get_at CFBundleShortVersionString "$MOUNTED_APP")"
[[ -n "$DETECTED_VERSION" ]] || die "mounted app has no CFBundleShortVersionString."
if [[ -z "$VERIFY_ONLY" ]]; then
  assert_eq "mounted CFBundleShortVersionString" "$VERSION" "$DETECTED_VERSION"
fi

SPCTL_APP_OUT="$(spctl --assess --type execute --verbose=4 "$MOUNTED_APP" 2>&1)" &&
  grep -q 'accepted' <<<"$SPCTL_APP_OUT" ||
  die "Gatekeeper rejected the app inside the DMG: $SPCTL_APP_OUT"
log "gatekeeper app assessment: accepted"

SPCTL_DMG_OUT="$(spctl --assess --verbose=4 "$DMG_PATH" 2>&1)" &&
  grep -q 'accepted' <<<"$SPCTL_DMG_OUT" ||
  die "Gatekeeper rejected the DMG: $SPCTL_DMG_OUT"
log "gatekeeper dmg assessment: accepted"

# ---------------------------------------------------------------------------
# Quarantine simulation (metadata + spctl; launch smoke optional locally)
# ---------------------------------------------------------------------------
TEST_ROOT="$MNT_ROOT/quarantine-check"
mkdir -p "$TEST_ROOT"
QUARANTINE_APP="$TEST_ROOT/MosaClip.app"
cp -R "$MOUNTED_APP" "$QUARANTINE_APP"
xattr -w com.apple.quarantine \
  "0081;$(date +%s);org.mumulei.mosaclip.releasecheck;$(uuidgen)" "$QUARANTINE_APP" ||
  die "failed to apply quarantine metadata to test copy."
SPCTL_QUARANTINE_OUT="$(spctl --assess --type execute --verbose=4 "$QUARANTINE_APP" 2>&1)" &&
  grep -q 'accepted' <<<"$SPCTL_QUARANTINE_OUT" ||
  die "quarantined copy failed Gatekeeper assessment: $SPCTL_QUARANTINE_OUT"
log "quarantine scenario: accepted"

if [[ "$LAUNCH_SMOKE" == "1" ]]; then
  # MosaClip resolves ALL user-domain storage (SwiftData store, Originals,
  # diagnostic log, UserDefaults domain, saved state) through Foundation's
  # passwd-based home resolution. Setting HOME does NOT redirect it — a probe
  # on current macOS shows NSHomeDirectory()/homeDirectoryForCurrentUser
  # ignore getenv("HOME"). A launch therefore writes into the invoking user's
  # real home, which is only acceptable where that home is disposable: a
  # GitHub-hosted Actions runner. Persistent machines fail closed; there is
  # no "isolated-home smoke" because no isolation mechanism exists.
  #
  # GITHUB_ACTIONS alone is also set on self-hosted runners, so the gate
  # additionally requires GitHub's RUNNER_ENVIRONMENT signal to report
  # "github-hosted". This is a safe-by-default guardrail against accidental
  # execution on persistent environments — not an anti-spoofing credential.
  if [[ "${GITHUB_ACTIONS:-}" != "true" ||
        "${RUNNER_ENVIRONMENT:-}" != "github-hosted" ]]; then
    die "launch smoke is allowed only on GitHub-hosted Actions runners. Local and self-hosted environments fail closed because MosaClip user-domain storage cannot currently be proven isolated."
  fi
  log "running launch smoke test (github-hosted-runner mode)"
  "$QUARANTINE_APP/Contents/MacOS/MosaClip" &
  SMOKE_PID=$!
  sleep 8
  if kill -0 "$SMOKE_PID" 2>/dev/null; then
    RSS_KB="$(ps -o rss= -p "$SMOKE_PID" | tr -d ' ')"
    CPU_PCT="$(ps -o %cpu= -p "$SMOKE_PID" | tr -d ' ')"
    log "launch smoke: process alive (pid $SMOKE_PID, rss ${RSS_KB}KB, cpu ${CPU_PCT}%)"
    kill "$SMOKE_PID" 2>/dev/null || true
    wait "$SMOKE_PID" 2>/dev/null || true
  else
    die "launch smoke failed: process exited within 8s of start."
  fi
fi

hdiutil detach "$MNT" >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# Final artifact identity — SHA-256 AFTER stapling (stapling mutates the DMG)
# ---------------------------------------------------------------------------
RESOLVED_IDENTITY="${RESOLVED_IDENTITY:-(n/a: VERIFY_ONLY mode)}"
TEAM_ID="${TEAM_ID:-(n/a: VERIFY_ONLY mode)}"
META_MIN_SYSTEM="${META_MIN_SYSTEM:-unknown}"
PIPELINE_MODE="full"
[[ -z "$VERIFY_ONLY" ]] || PIPELINE_MODE="verify-only"
REPORT_DIR="$DIST_DIR"
if [[ -n "$VERIFY_ONLY" ]]; then
  REPORT_DIR="$(dirname "$DMG_PATH")"
fi

DMG_FILENAME="$(basename "$DMG_PATH")"
DMG_SIZE_BYTES="$(stat -f%z "$DMG_PATH")"
DMG_SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
printf '%s  %s\n' "$DMG_SHA256" "$DMG_FILENAME" > "$REPORT_DIR/checksums.txt"

cat > "$REPORT_DIR/release-verification.txt" <<EOF
MosaClip release verification report
generated_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
pipeline_mode=$PIPELINE_MODE
version=${DETECTED_VERSION:-$VERSION}
arch=$ARCH
signing_mode=developer-id
codesign_identity=$RESOLVED_IDENTITY
team_id=$TEAM_ID
bundle_id=com.mumulei.mosaclip
min_system_version=${META_MIN_SYSTEM}
app_bundle=MosaClip.app (inside DMG)
dmg_filename=$DMG_FILENAME
dmg_size_bytes=$DMG_SIZE_BYTES
dmg_sha256=$DMG_SHA256
notarization_submission_id=${SUBMISSION_ID:-unknown}
notarization_status=${STATUS:-unknown}
stapler_staple=$( [[ "$PIPELINE_MODE" == "full" ]] && echo PASS || echo skipped-preexisting )
stapler_validate=PASS
gatekeeper_app_assessment=accepted
gatekeeper_dmg_assessment=accepted
quarantine_gatekeeper_assessment=accepted
online_updates_enabled=false
EOF

log "artifact: $DMG_PATH"
log "sha256:   $DMG_SHA256"
log "report:   $REPORT_DIR/release-verification.txt"
log "checksum: $REPORT_DIR/checksums.txt"
log "pipeline complete ($PIPELINE_MODE: stapled + gatekeeper-clean)"
