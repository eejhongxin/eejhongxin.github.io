#!/bin/sh
set -eu

SELF=$(CDPATH= cd "$(dirname "$0")" && pwd -P)
PACKAGE=$(CDPATH= cd "$SELF/.." && pwd -P)
PATH=/sbin:/bin:/usr/sbin:/usr/bin
export PATH

WORK=/mnt/ddr_work
RC=/etc/init.d/rcS
TARGET=/etc/init.d/ddr_boot_prepare.sh
COUNT_FILE="$WORK/ddr_autostart.count"
HOOK='/bin/sh /etc/init.d/ddr_boot_prepare.sh > /tmp/ddr-boot.log 2>&1'
ANCHOR='^[ \t]*/sbin/mdev[ \t]+-s[ \t\r]*$'
LOCK=/mem/ddr-unified-install.lock
LOCK_OWNED=0
RUN_LOCK=/mem/ddr-run.lock
RUN_LOCK_OWNED=0
RC_SNAPSHOT=
RC_TEMP=
TARGET_TEMP=
COUNT_TEMP=
CHANGES=

die() { echo "ERROR: $*" >&2; exit 1; }

cleanup() {
    result=$?
    trap - EXIT
    for temporary in "$RC_SNAPSHOT" "$RC_TEMP" "$TARGET_TEMP" "$COUNT_TEMP"; do
        [ -z "$temporary" ] || rm -f "$temporary" || :
    done
    if [ "$RUN_LOCK_OWNED" = 1 ]; then
        owner=
        if [ -r "$RUN_LOCK/installer.pid" ]; then
            read -r owner < "$RUN_LOCK/installer.pid" || :
        fi
        if [ "$owner" = "$$" ]; then
            rm -f "$RUN_LOCK/installer.pid" || :
            rmdir "$RUN_LOCK" 2>/dev/null || :
        elif [ ! -e "$RUN_LOCK/installer.pid" ]; then
            # PID creation itself may fail; remove only our still-empty lock.
            rmdir "$RUN_LOCK" 2>/dev/null || :
        fi
    fi
    if [ "$LOCK_OWNED" = 1 ]; then
        rmdir "$LOCK" 2>/dev/null || :
    fi
    if [ "$result" -ne 0 ] && [ -n "$CHANGES" ]; then
        echo "ERROR: Installation stopped after changing:$CHANGES" >&2
        echo "Do not reboot until the installed helper, rcS and round count are checked. No test or reboot was started." >&2
    fi
    exit "$result"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

mounted() {
    awk '$2=="/mnt" {ok=($1=="/dev/mmcblk1p7" && $3=="vfat" && $4 ~ /(^|,)rw(,|$)/)}
         END {exit !ok}' /proc/mounts || die "/mnt must be /dev/mmcblk1p7 mounted vfat/rw"
}

package_on_mount() {
    mount_device=$(stat -c %d /mnt) || die "Cannot identify the /mnt filesystem"
    package_device=$(stat -c %d "$PACKAGE") || die "Cannot identify the package filesystem"
    [ "$mount_device" = "$package_device" ] || die "Package is not on the mounted eMMC filesystem"
}

idle() {
    if ps | grep -E '[d]dr_test.sh|[s]tressapptest|[m]emtester|[c]heck_update|[r]un.sh --worker|[d]dr_autostart.sh --worker' >/dev/null; then
        die "A DDR test or worker is running; wait until it finishes before changing autostart"
    fi
}

rounds_valid() {
    case "$1" in ''|*[!0-9]*|0*) return 1 ;; esac
    [ "${#1}" -le 4 ] && [ "$1" -le 1000 ]
}

case "${1:-autostart}" in
    autostart)
        [ "$#" -le 2 ] || die "Usage: sh ddr-unified-install.sh [autostart [ROUNDS]|manual]"
        ROUNDS=${2:-6}
        rounds_valid "$ROUNDS" || die "Round count must be 1..1000"
        ACTION=autostart
        ;;
    manual)
        [ "$#" -eq 1 ] || die "Usage: sh ddr-unified-install.sh manual"
        ACTION=manual
        ;;
    *) die "Usage: sh ddr-unified-install.sh [autostart [ROUNDS]|manual]" ;;
esac

[ "$(id -u)" = 0 ] || die "Run as root"
mounted
case "$PACKAGE" in
    /mnt/ddr_work/ddr_p5|/mnt/ddr_work/full/ddr_p5) ;;
    *) die "Package must be /mnt/ddr_work/ddr_p5 or /mnt/ddr_work/full/ddr_p5"
esac
package_on_mount
for filename in run.sh ddr_test.sh ddr_progress.sh wtd_feed.sh; do
    [ -r "$PACKAGE/$filename" ] || die "Missing package file: $PACKAGE/$filename"
done
[ ! -L "$COUNT_FILE" ] || die "Round count must not be a symbolic link"

if [ "$ACTION" = autostart ]; then
    idle
    [ -f "$RC" ] && [ ! -L "$RC" ] || die "Expected regular rcS: $RC"
    [ ! -L "$TARGET" ] || die "Boot helper must not be a symbolic link"
    [ -r "$SELF/prepare.sh" ] || die "Missing boot helper template"
    # Accept the previous hook with either LF or CRLF, but never duplicate it.
    hooks=$(awk -v hook="$HOOK" '{sub(/\r$/, "")} $0==hook {n++} END {print n+0}' "$RC")
    case "$hooks" in
        1) ANCHOR_LINE= ;;
        0)
            anchors=$(awk -v anchor="$ANCHOR" '$0 ~ anchor {n++} END {print n+0}' "$RC")
            [ "$anchors" = 1 ] || die "Expected exactly one /sbin/mdev -s command in rcS, found $anchors; no changes made"
            ANCHOR_LINE=$(awk -v anchor="$ANCHOR" '$0 ~ anchor {print NR}' "$RC")
            ;;
        *) die "Multiple DDR boot hooks found in rcS; no changes made" ;;
    esac
fi

mkdir "$LOCK" 2>/dev/null || die "Another installation or stale install lock exists: $LOCK"
LOCK_OWNED=1
mounted
package_on_mount

if [ "$ACTION" = manual ]; then
    rm -f "$COUNT_FILE" || die "Cannot disable future test autostart"
    sync
    echo "Future DDR test autostart disabled. Current tests, boot mounting and watchdog feeding are unchanged."
    exit 0
fi

mkdir "$RUN_LOCK" 2>/dev/null || die "A DDR startup, test or stale run lock exists: $RUN_LOCK"
RUN_LOCK_OWNED=1
printf '%s\n' "$$" > "$RUN_LOCK/installer.pid" || die "Cannot record installation lock owner"
idle
sh "$PACKAGE/run.sh" --validate-autostart || die "Package or boot dependencies failed validation; no boot files installed"
RC_SNAPSHOT=$(mktemp "$RC.ddr-source.XXXXXX") || die "Cannot prepare rcS snapshot"
cp -p "$RC" "$RC_SNAPSHOT" || die "Cannot snapshot rcS"
TARGET_TEMP=$(mktemp "$TARGET.unified.XXXXXX") || die "Cannot prepare boot helper"
sed "s@__DDR_PACKAGE__@$PACKAGE@g" "$SELF/prepare.sh" > "$TARGET_TEMP" || die "Cannot generate boot helper"
chmod 755 "$TARGET_TEMP" || die "Cannot set helper permissions"
sh -n "$TARGET_TEMP" || die "Generated boot helper has invalid shell syntax"

if [ -n "$ANCHOR_LINE" ]; then
    RC_TEMP=$(mktemp "$RC.unified.XXXXXX") || die "Cannot prepare rcS"
    # Preserve every old line's bytes, including CRLF and a missing final LF.
    # Only the new hook and its required line separator are added.
    line_number=0
    while :; do
        line=
        if IFS= read -r line; then
            has_newline=1
        else
            [ -n "$line" ] || break
            has_newline=0
        fi
        line_number=$((line_number + 1))
        printf '%s' "$line"
        if [ "$has_newline" = 1 ]; then
            printf '\n'
        fi
        if [ "$line_number" = "$ANCHOR_LINE" ]; then
            [ "$has_newline" = 1 ] || printf '\n'
            printf '%s\n' "$HOOK"
        fi
    done < "$RC_SNAPSHOT" > "$RC_TEMP"
    chmod "$(stat -c %a "$RC_SNAPSHOT")" "$RC_TEMP" || die "Cannot retain rcS permissions"
    sh -n "$RC_TEMP" || die "Generated rcS has invalid shell syntax"
else
    sh -n "$RC_SNAPSHOT" || die "Existing rcS has invalid shell syntax"
fi

COUNT_TEMP=$(mktemp "$WORK/ddr_autostart.count.XXXXXX") || die "Cannot prepare round count"
printf '%s\n' "$ROUNDS" > "$COUNT_TEMP" || die "Cannot write prepared round count"
sh -n "$PACKAGE/run.sh" || die "Unified entry has invalid shell syntax"
cmp -s "$RC" "$RC_SNAPSHOT" || die "rcS changed during preparation; no boot files installed"
idle

# Preserve the first snapshots. Never overwrite a prior backup.
if [ ! -e "$RC.before-ddr-boot" ] && [ ! -L "$RC.before-ddr-boot" ]; then
    cp -p "$RC_SNAPSHOT" "$RC.before-ddr-boot" || die "Cannot back up rcS"
fi
if [ -f "$TARGET" ] && [ ! -e "$TARGET.before-unified-ddr" ] && [ ! -L "$TARGET.before-unified-ddr" ]; then
    cp -p "$TARGET" "$TARGET.before-unified-ddr" || die "Cannot back up the existing helper"
fi

mv "$TARGET_TEMP" "$TARGET" || die "Cannot install boot helper"
TARGET_TEMP=
CHANGES=" helper"
if [ -n "$RC_TEMP" ]; then
    mv "$RC_TEMP" "$RC" || die "Cannot install rcS hook"
    RC_TEMP=
    CHANGES="$CHANGES rcS"
fi
# The count is committed last: enabling future tests is the final installation step.
mv "$COUNT_TEMP" "$COUNT_FILE" || die "Cannot install round count"
COUNT_TEMP=
CHANGES="$CHANGES count"
sync
echo "Enabled: $ROUNDS DDR rounds on each future boot; package=$PACKAGE"
echo "Installed automatic eMMC mounting and watchdog preparation. Log: /tmp/ddr-boot.log"
echo "No old logs were moved, no test or reboot was started, and no running feeder was stopped."
