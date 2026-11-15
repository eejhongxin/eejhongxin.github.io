#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SOURCE="$ROOT/testcase_linux/minimum_system_test/ddr_test/p5"
BASE="$ROOT/out/ddr-build/x6-integration-patch/ddr_p5/SHA256SUMS"
BASE_HASH=556eaab661d9a8cd46fe54062b03ca7208409bdca4dc3ba4c40ca57ceb705814
echo "$BASE_HASH  $BASE" | sha256sum -c -
STAGE=$(mktemp -d "$ROOT/out/ddr-build/progress-patch.XXXXXX")
trap 'rm -rf -- "$STAGE"' EXIT
PKG="$STAGE/ddr_p5"
mkdir -p "$PKG"
install -m 755 "$ROOT/tools/install-ddr-progress.sh" "$STAGE/"
install -m 755 "$SOURCE/ddr_test.sh" "$SOURCE/ddr_progress.sh" "$PKG/"
install -m 644 "$SOURCE/README.md" "$PKG/"
(
    cd "$PKG"
    # Keep the deployed tools/fixtures, including their original binary hashes.
    {
        while read -r digest file; do
            case "$file" in
                ./ddr_test.sh|./ddr_progress.sh|./README.md) continue ;;
            esac
            printf '%s  %s\n' "$digest" "$file"
        done < "$BASE"
        sha256sum ./ddr_test.sh ./ddr_progress.sh ./README.md
    } | LC_ALL=C sort -k2 > SHA256SUMS
    sha256sum ./ddr_test.sh ./ddr_progress.sh ./README.md ./SHA256SUMS > PATCH_SHA256SUMS
    sha256sum -c PATCH_SHA256SUMS
)
OUTPUT="$ROOT/out/ddr-p5-progress.tar.gz"
tar -czf "$OUTPUT" -C "$STAGE" install-ddr-progress.sh ddr_p5
sha256sum "$OUTPUT"
printf 'Built %s; not transferred or installed on a board.\n' "$OUTPUT"
