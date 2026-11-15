#!/bin/sh

PATH=/sbin:/bin:/usr/sbin:/usr/bin
export PATH

die() { echo "ERROR: $*" >&2; exit 1; }

test_autostart() {
    if [ -f /mnt/ddr_work/ddr_autostart.count ]; then
        [ -r /mnt/ddr_work/ddr_autostart.sh ] || die "Autostart helper is missing"
        sh /mnt/ddr_work/ddr_autostart.sh start || die "DDR autostart failed"
    else
        echo "DDR tests are NOT started automatically."
    fi
}

# This script stays on the root filesystem, not on the initially unmounted eMMC.
if ! grep -q ' /mnt ' /proc/mounts; then
    tries=0
    while [ ! -b /dev/mmcblk1p7 ]; do
        [ "$tries" -lt 10 ] || die "Timed out waiting for /dev/mmcblk1p7"
        sleep 1
        tries=$((tries + 1))
    done
    mkdir -p /mnt || die "Cannot create /mnt"
    mount -t vfat -o rw /dev/mmcblk1p7 /mnt || die "Cannot mount eMMC on /mnt"
fi
awk '$2=="/mnt" {ok=($1=="/dev/mmcblk1p7" && $3=="vfat" && $4 ~ /(^|,)rw(,|$)/)}
     END {exit !ok}' /proc/mounts || die "/mnt must be /dev/mmcblk1p7 mounted vfat/rw"
echo "Ready: /dev/mmcblk1p7 mounted on /mnt (vfat/rw)"

FEEDER=
for directory in /mnt/ddr_work/ddr_p5 /mnt/ddr_bootstrap/ddr_p5 /mnt/ddr_work/full/ddr_p5; do
    candidate="$directory/wtd_feed.sh"
    [ -r "$candidate" ] || continue
    # Prefer a worker already running from any of the supported install paths.
    if sh "$candidate" status >/dev/null 2>&1; then
        sh "$candidate" status
        test_autostart
        exit 0
    fi
    [ -n "$FEEDER" ] || FEEDER="$candidate"
done
[ -n "$FEEDER" ] || die "No installed wtd_feed.sh found under /mnt/ddr_work or /mnt/ddr_bootstrap"
sh "$FEEDER" start || die "Watchdog feeder failed: $FEEDER"
sh "$FEEDER" status || die "Watchdog feeder is not running"
test_autostart
