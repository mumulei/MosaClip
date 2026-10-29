#!/usr/bin/env bash
# Shared, fail-closed signing policy for MosaClip release packaging.
#
# Pure function library: sourcing this file must not build anything and must
# not mutate state. Both `scripts/package.sh` (local QA + production) and
# `.github/scripts/ci-build-dmg.sh` (notarized release pipeline) source it so
# identity classification rules cannot drift between entry points.
#
# Policy (see docs/MOSACLIP_DISTRIBUTION.md):
#   SIGNING_MODE=adhoc         -> local QA; "-" (ad-hoc) or any local identity.
#   SIGNING_MODE=developer-id  -> production; ONLY a valid
#                                 "Developer ID Application: ..." identity.
# Production never silently falls back to "-", "Apple Development",
# "Mac Developer", "Apple Distribution" or unknown identities.

# Classify a codesigning identity string.
# stdout: adhoc | development | distribution | developer-id | unknown
release_classify_identity() {
  local identity="${1-}"
  case "$identity" in
    -)
      printf 'adhoc\n'
      ;;
    "Developer ID Application:"*)
      printf 'developer-id\n'
      ;;
    "Apple Development:"*|"Mac Developer:"*)
      printf 'development\n'
      ;;
    "Apple Distribution:"*|"Mac App Distribution:"*|"3rd Party Mac Developer Application:"*)
      printf 'distribution\n'
      ;;
    "")
      printf 'unknown\n'
      ;;
    *)
      printf 'unknown\n'
      ;;
  esac
}

release_fatal() {
  printf '[signing-policy] ERROR: %s\n' "$*" >&2
  return 1
}

# Fail unless the given identity qualifies for production signing.
release_require_developer_id_identity() {
  local identity="${1-}"
  local kind
  kind="$(release_classify_identity "$identity")"
  if [[ "$kind" != "developer-id" ]]; then
    release_fatal "production signing (SIGNING_MODE=developer-id) requires an explicit 'Developer ID Application: ...' identity; got '$identity' (classified: ${kind:-empty}). Refusing to fall back to ad-hoc or a development certificate." || return 1
  fi
}

# List valid "Developer ID Application: ..." identities found in the user's
# keychains. One common name per line. Never prints key material.
release_detect_developer_id_identities() {
  security find-identity -v -p codesigning 2>/dev/null |
    sed -n 's/^[[:space:]]*[0-9][0-9]*)[[:space:]]*[0-9A-Fa-f]\{40\}[[:space:]]*"\(Developer ID Application:.*\)"$/\1/p'
}

# Resolve the codesign identity for a signing mode.
#   $1 = mode            (adhoc | developer-id)
#   $2 = explicit identity (may be empty; "-" means ad-hoc)
# On success prints the resolved identity to stdout.
# On policy violation prints reasons to stderr and returns non-zero.
release_resolve_codesign_identity() {
  local mode="${1-}"
  local explicit="${2-}"

  case "$mode" in
    adhoc)
      # Local QA: ad-hoc is the default; an explicitly provided local identity
      # (e.g. Apple Development) is also acceptable on a developer machine.
      if [[ -z "$explicit" ]]; then
        printf -- '-\n'
      else
        printf '%s\n' "$explicit"
      fi
      ;;
    developer-id)
      if [[ -n "$explicit" ]]; then
        release_require_developer_id_identity "$explicit" || return 1
        printf '%s\n' "$explicit"
      else
        local candidates=()
        local line
        while IFS= read -r line; do
          [[ -n "$line" ]] && candidates+=("$line")
        done < <(release_detect_developer_id_identities)

        if [[ ! ${candidates[@]+x} ]]; then
          release_fatal "no valid 'Developer ID Application' identity found in any keychain. Import one via Xcode > Settings > Accounts, or with: security import developerid.p12 -k login.keychain; then retry. For local QA only, use SIGNING_MODE=adhoc." || return 1
        elif [[ ${#candidates[@]} -eq 1 ]]; then
          printf '%s\n' "${candidates[0]}"
        else
          local c
          release_fatal "multiple 'Developer ID Application' identities found; set CODESIGN_IDENTITY explicitly to one of:" >&2 || return 1
          for c in ${candidates[@]+"${candidates[@]}"}; do
            printf '[signing-policy]   candidate: %s\n' "$c" >&2
          done
          return 1
        fi
      fi
      ;;
    *)
      release_fatal "unknown SIGNING_MODE '$mode' (expected: adhoc | developer-id)" || return 1
      ;;
  esac
}

# Extract the Team ID from a "Developer ID Application: Name (TEAMID)" common
# name. Prints the Team ID, or nothing when the name carries none.
release_team_id_from_identity() {
  local identity="${1-}"
  printf '%s' "$identity" | sed -n 's/.*(\([A-Z0-9]\{6,\}\))[[:space:]]*$/\1/p'
}
