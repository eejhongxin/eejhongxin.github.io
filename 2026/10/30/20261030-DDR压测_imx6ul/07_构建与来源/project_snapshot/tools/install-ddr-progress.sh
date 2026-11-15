#!/bin/sh
set -eu

SELF=$(CDPATH= cd "$(dirname "$0")" && pwd)
TARGET=${1:-/mnt/ddr_work/full/ddr_p5}
BASE_HASH=556eaab661d9a8cd46fe54062b03ca7208409bdca4dc3ba4c40ca57ceb705814
PROGRESS_HASH=3e5a5e78cb742997d9776ead493293327a781086d83cbb41b84df01764e779ee

if ps | grep -q '[d]dr_test.sh'; then
    echo "ERROR: A DDR test is running; wait until it finishes before installing." >&2
    exit 1
fi
(
    cd "$SELF/ddr_p5"
    sha256sum -c PATCH_SHA256SUMS
)
(
    cd "$TARGET"
    CURRENT_HASH=$(sha256sum SHA256SUMS)
    CURRENT_HASH=${CURRENT_HASH%% *}
    if [ "$CURRENT_HASH" = "$PROGRESS_HASH" ]; then
        BASE_HASH=$PROGRESS_HASH
    fi
    echo "$BASE_HASH  SHA256SUMS" | sha256sum -c -
    sha256sum -c SHA256SUMS
)
BACKUP=$(mktemp -d "$(dirname "$TARGET")/progress-before-change.XXXXXX")
cp "$TARGET/ddr_test.sh" "$TARGET/README.md" "$TARGET/SHA256SUMS" "$BACKUP/"
cp "$SELF/ddr_p5/ddr_progress.sh" "$TARGET/"
cp "$SELF/ddr_p5/ddr_test.sh" "$SELF/ddr_p5/README.md" "$SELF/ddr_p5/SHA256SUMS" "$TARGET/"
(
    cd "$TARGET"
    sha256sum -c SHA256SUMS
)
sync
echo "Installed console progress and TAR=100 iterations. Backup: $BACKUP"
echo "No test started; watchdog and boot configuration unchanged."
