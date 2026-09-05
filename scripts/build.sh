#!/usr/bin/env bash
# Build the zaia workspace and run every example.
#
# The three build flags are all load-bearing — see docs/workflow/build.md:
#   rm -rf artifacts   a stale dist makes the analyzer demand a circular import
#   --release          debug emits indexed zpkgs that fail at runtime when moved
#   --no-incremental   incremental workspace builds report phantom type errors
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Locate the SDK: $Z42_HOME, else a z42 on PATH, else the sibling language repo.
if [[ -n "${Z42_HOME:-}" ]]; then
    SDK="$Z42_HOME"
elif command -v z42 >/dev/null 2>&1; then
    SDK="$(dirname "$(command -v z42)")"
elif [[ -d "$ROOT/../z42/.z42" ]]; then
    SDK="$ROOT/../z42/.z42"
else
    echo "error: no z42 SDK found. Set Z42_HOME, or put z42 on PATH." >&2
    exit 1
fi

Z42C="$SDK/bin/z42c"
Z42VM="$SDK/bin/z42vm"
DIST="$ROOT/artifacts/dist"

echo "==> SDK: $SDK"
rm -rf "$ROOT/artifacts"
( cd "$ROOT/src" && "$Z42C" build --workspace --release --no-incremental )

echo
echo "==> examples"
for zpkg in "$DIST"/example-*.zpkg; do
    [[ -e "$zpkg" ]] || continue
    name="$(basename "$zpkg" .zpkg)"
    # example-hello-server blocks on a socket; it is run by hand, not here.
    if [[ "$name" == "example-hello-server" ]]; then
        echo "--- $name (skipped: blocks on a socket; run it by hand)"
        continue
    fi
    echo "--- $name"
    Z42_LIBS="$SDK/libs:$DIST" "$Z42VM" "$zpkg"
done
