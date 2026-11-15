#!/bin/sh

# The installer substitutes one of the two supported eMMC package paths.
PACKAGE=__DDR_PACKAGE__
PATH=/sbin:/bin:/usr/sbin:/usr/bin
export PATH

die() { echo "ERROR: $*" >&2; exit 1; }

case "$PACKAGE" in
    /mnt/ddr_work/ddr_p5|/mnt/ddr_work/full/ddr_p5) ;;
    *) die "Invalid installed DDR package path: $PACKAGE" ;;
esac

if ! awk '$2=="/mnt" {found=1} END {exit !found}' /proc/mounts; then
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
[ -r "$PACKAGE/run.sh" ] || die "Missing unified DDR entry: $PACKAGE/run.sh"
mount_device=$(stat -c %d /mnt) || die "Cannot identify the /mnt filesystem"
package_device=$(stat -c %d "$PACKAGE") || die "Cannot identify the package filesystem"
[ "$mount_device" = "$package_device" ] || die "Package is not on the mounted eMMC filesystem"
echo "Ready: /dev/mmcblk1p7 mounted on /mnt (vfat/rw); package=$PACKAGE"
exec sh "$PACKAGE/run.sh" --boot
