#!/usr/bin/env bash
# Build the zaia workspace — framework libraries + example exes, all members of one
# z42 workspace (packages/). Requires the nightly z42 SDK on PATH.
#
#   ./scripts/build.sh
#
# Output: packages/dist/dist/*.zpkg  (zaia.* libraries + example exes)
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here/packages"
z42 build --workspace --release
echo "✓ zaia workspace built → packages/dist/dist/"
