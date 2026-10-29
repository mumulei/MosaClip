#!/usr/bin/env bash

set -euo pipefail

cat >&2 <<'EOF'
Automatic online publishing is disabled until distribution certification passes.
The inherited PasteMemo publisher intentionally cannot upload to the original
site, Homebrew tap, or release infrastructure. Build a local test DMG with:

  make package VERSION=<version>
EOF
exit 1
