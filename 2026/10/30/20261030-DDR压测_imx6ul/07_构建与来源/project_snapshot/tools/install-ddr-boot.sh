#!/bin/sh
set -eu

SELF=$(CDPATH= cd "$(dirname "$0")" && pwd)
RC=/etc/init.d/rcS
TARGET=/etc/init.d/ddr_boot_prepare.sh
HOOK='/bin/sh /etc/init.d/ddr_boot_prepare.sh > /tmp/ddr-boot.log 2>&1'
ANCHOR='^[ \t]*/sbin/mdev[ \t]+-s[ \t\r]*$'
TEMP=
TARGET_TEMP=
WORK=/mnt/ddr_work

cleanup() {
    [ -z "$TEMP" ] || rm -f "$TEMP"
    [ -z "$TARGET_TEMP" ] || rm -f "$TARGET_TEMP"
    :
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

[ "$(id -u)" = 0 ] || { echo "ERROR: Run as root" >&2; exit 1; }
[ -f "$RC" ] || { echo "ERROR: Missing $RC" >&2; exit 1; }
case "${1:-install}" in
    install|autostart)
        [ -f "$SELF/ddr_boot_prepare.sh" ] || {
            echo "ERROR: Extract both files into the same directory" >&2
            exit 1
        }
        sh -n "$SELF/ddr_boot_prepare.sh"
        if [ "${1:-install}" = autostart ]; then
            rounds=${2:-6}
            case "$rounds" in ''|*[!0-9]*|0*) echo "ERROR: Round count must be 1..1000" >&2; exit 1 ;; esac
            [ "${#rounds}" -le 4 ] && [ "$rounds" -le 1000 ] || exit 1
            [ -r "$SELF/ddr_autostart.sh" ] || { echo "ERROR: Missing ddr_autostart.sh" >&2; exit 1; }
            [ -r "$WORK/full/ddr_p5/ddr_test.sh" ] && [ -r "$WORK/full/ddr_p5/ddr_progress.sh" ] || {
                echo "ERROR: Full DDR package with progress is missing" >&2; exit 1;
            }
            sh -n "$SELF/ddr_autostart.sh"
        fi
        if ! grep -Fx "$HOOK" "$RC" >/dev/null; then
            matches=$(awk -v anchor="$ANCHOR" '$0 ~ anchor {n++} END {print n+0}' "$RC")
            [ "$matches" = 1 ] || {
                echo "ERROR: Expected exactly one /sbin/mdev -s command in rcS, found $matches; no changes made" >&2
                grep -n 'mdev' "$RC" >&2 || :
                exit 1
            }
            TEMP=$(mktemp "$RC.ddr.XXXXXX")
            awk -v hook="$HOOK" -v anchor="$ANCHOR" '{print} $0 ~ anchor {print hook}' "$RC" > "$TEMP"
            sh -n "$TEMP"
        fi
        if [ "${1:-install}" = autostart ]; then
            sh "$SELF/ddr_autostart.sh" backup || exit 1
            cp "$SELF/ddr_autostart.sh" "$WORK/ddr_autostart.sh" || exit 1
            chmod 755 "$WORK/ddr_autostart.sh" || exit 1
        fi
        TARGET_TEMP=$(mktemp "$TARGET.XXXXXX")
        if [ -f "$TARGET" ] && [ ! -e "$TARGET.before-autotest" ]; then
            cp -p "$TARGET" "$TARGET.before-autotest"
        fi
        cp "$SELF/ddr_boot_prepare.sh" "$TARGET_TEMP"
        chmod 755 "$TARGET_TEMP"
        mv "$TARGET_TEMP" "$TARGET"
        TARGET_TEMP=
        if [ -n "$TEMP" ]; then
            [ -e "$RC.before-ddr-boot" ] || cp -p "$RC" "$RC.before-ddr-boot"
            chmod "$(stat -c %a "$RC")" "$TEMP"
            mv "$TEMP" "$RC"
            TEMP=
        fi
        if [ "${1:-install}" = autostart ]; then
            count_temp=$(mktemp "$WORK/ddr_autostart.count.XXXXXX")
            printf '%s\n' "$rounds" > "$count_temp" || exit 1
            mv "$count_temp" "$WORK/ddr_autostart.count" || exit 1
            echo "Enabled: $rounds rounds on each boot; old data archived before each run."
        fi
        sync
        echo "Installed: automatic eMMC mount + watchdog feeding on next boot."
        echo "No tests started; no running feeder stopped. Log: /tmp/ddr-boot.log"
        ;;
    manual)
        awk '$2=="/mnt" {ok=($1=="/dev/mmcblk1p7" && $3=="vfat" && $4 ~ /(^|,)rw(,|$)/)}
             END {exit !ok}' /proc/mounts || { echo "ERROR: Mount eMMC vfat/rw first" >&2; exit 1; }
        rm -f "$WORK/ddr_autostart.count"
        sync
        echo "Future test autostart disabled; boot mounting and feeding kept. Current test unchanged."
        ;;
    disable)
        if grep -Fx "$HOOK" "$RC" >/dev/null; then
            TEMP=$(mktemp "$RC.ddr.XXXXXX")
            awk -v hook="$HOOK" '$0 != hook' "$RC" > "$TEMP"
            sh -n "$TEMP"
            chmod "$(stat -c %a "$RC")" "$TEMP"
            mv "$TEMP" "$RC"
            TEMP=
            sync
        fi
        echo "Disabled for future boots. Current feeder is NOT stopped."
        ;;
    *) echo "Usage: sh install-ddr-boot.sh [install|autostart ROUNDS|manual|disable]" >&2; exit 2 ;;
esac
