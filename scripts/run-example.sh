#!/usr/bin/env bash
# Run a built example zpkg. Requires the nightly z42 SDK on PATH and a prior
# ./scripts/build.sh (so packages/dist/dist/<name>.zpkg exists).
#
#   ./scripts/run-example.sh counter-ssr      # → renders a Component to HTML and exits
#   ./scripts/run-example.sh hello-server      # → HTTP server on :8080 (Ctrl-C to stop)
#
# The example's framework dependencies (zaia.*) resolve from the dist dir (the entry
# zpkg's directory); the stdlib resolves from the SDK's libs/ via Z42_LIBS.
set -euo pipefail
name="${1:?usage: run-example.sh <example-name>}"
here="$(cd "$(dirname "$0")/.." && pwd)"
sdk_bin="$(dirname "$(command -v z42)")"
zpkg="$here/packages/dist/dist/${name}.zpkg"
[ -f "$zpkg" ] || { echo "not built: $zpkg (run ./scripts/build.sh first)" >&2; exit 1; }
Z42_LIBS="$sdk_bin/libs" exec "$sdk_bin/bin/z42vm" "$zpkg"
