#!/usr/bin/env bash
# Build the zaia framework packages (core, shared, web, server) as a z42 workspace.
# Requires the nightly z42 SDK on PATH.
#
#   ./scripts/build.sh
#
# Output: packages/dist/dist/zaia.*.zpkg
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here/packages"
z42 build --workspace --release
echo "✓ zaia packages built → packages/dist/dist/"
