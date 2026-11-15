# P5 Boot Preparation

Automatically mount /dev/mmcblk1p7 on /mnt as vfat/rw and start the existing
external watchdog feeder. DDR tests remain manual unless explicitly enabled
with autostart. No formatting, repair, forced remount, firmware flashing or
checkupdate replacement. The original DDR runner prepares its own /data mounts.

## Automatic Six-Round Tests And Old-Data Archive

Build the same existing archive name on the host:

```sh
bash tools/build-ddr-boot.sh
```

On each board, wait until the current tests have completed and keep feeding
running. Confirm /mnt is /dev/mmcblk1p7 mounted vfat/rw, then receive the latest
out/ddr-p5-boot.tar.gz in /mnt/ddr_work. No full bundle transfer is required:

```sh
cd /mnt/ddr_work
lrz
mkdir -p boot_setup
cd boot_setup
tar -xzf ../ddr-p5-boot.tar.gz
sh install-ddr-boot.sh autostart 6
```

This command immediately archives the existing ddr_all_test directory under
/mnt/ddr_work/ddr_backup/ddr_all_test.XXXXXX/ddr_all_test. Only this directory is
archived; no additional board information, kernel snapshot or /tmp unpack
data is collected by the archive operation.
The unique directory name does not depend on the board's unset clock. The
archive operation refuses an active DDR test or an incorrect/read-only mount.
If archiving fails, the installer does not enable test autostart. Do not reboot
until the archive and successful installation messages have been checked.

The installer saves the previous boot helper as
/etc/init.d/ddr_boot_prepare.sh.before-autotest, preserves the existing rcS hook
and its original backup, installs ddr_autostart.sh under /mnt/ddr_work, and writes
6 to /mnt/ddr_work/ddr_autostart.count. It does not immediately start a test or
stop the watchdog. It changes installed startup scripts, not the firmware image.

On each subsequent boot: mount eMMC, confirm feeding, detach a test worker,
archive any previous ddr_all_test, then run the unchanged full DDR runner -c 6.
The lock under /mem prevents another automatic batch in the same boot even
after the first batch completes. A reboot permits a new six-round batch.
Serial disconnection does not terminate the detached worker. There is no
automatic reboot/retry when tests end or startup fails; feeding remains running.

The current batch uses these paths:

```text
/mnt/ddr_work/ddr_all_test/console.log         complete runner stdout/stderr
/mnt/ddr_work/ddr_all_test/ddr_log.log         original summary
/mnt/ddr_work/ddr_all_test/stressapptest_0.log ... stressapptest_5.log
/mnt/ddr_work/ddr_all_test/memtester_0.log     ... memtester_5.log
/mnt/ddr_work/ddr_all_test/kernel-before.log  startup kernel snapshot
/mnt/ddr_work/ddr_all_test/kernel-after.log   completion kernel snapshot
/mnt/ddr_work/ddr_all_test/unpack_bin/        final BIN evidence
/mnt/ddr_work/ddr_all_test/unpack_tar/        final TAR evidence
```

The last two folders are copied only when the runner returns; they do not
preserve each round's unpack evidence. On a crash/reboot, only data already
written to eMMC survives; /tmp results disappear. Progress is now persistent
in console.log for automatic runs. Early worker failures are in
/tmp/ddr-autotest-launch.log; the initial boot hook logs to /tmp/ddr-boot.log.
runner_exit_code is the original shell exit status, NOT an overall PASS verdict.
The original runner can continue after memtester is OOM-killed, and its memory
allocation/result-checking limitations have not been changed by this feature.

After installation, reboot only when ready. Before closing the chamber, check:

```sh
cat /tmp/ddr-boot.log
cat /tmp/ddr-autotest-launch.log
tail -n 20 /mnt/ddr_work/ddr_all_test/console.log
ps | grep '[d]dr_test.sh'
```

To disable only future test autostart, keeping mount/feeding preparation and
the current test untouched:

```sh
sh /mnt/ddr_work/boot_setup/install-ddr-boot.sh manual
```

Manual sh ddr_test.sh -c N still uses the original append/reuse behavior. Only
the automatic worker and installation archive old data before starting anew.
Archives have no automatic retention limit; monitor available eMMC space.

## Installation On The Board

Do not reboot or stop an active DDR test to install this. Transfer the small
out/ddr-p5-boot.tar.gz archive using lrz into the already mounted eMMC:

```sh
cd /mnt/ddr_work
df -h .
lrz
mkdir -p boot_setup
cd boot_setup
tar -xzf ../ddr-p5-boot.tar.gz
sh install-ddr-boot.sh
```

Before transfer, df must identify /dev/mmcblk1p7, not /dev/root. The installer
copies ddr_boot_prepare.sh to /etc/init.d and adds exactly one invocation
after /sbin/mdev -s in the existing rcS, before its udiskflg early exit.
It saves the original rcS as /etc/init.d/rcS.before-ddr-boot on first install.
Unexpected rcS structure aborts installation. Repeating installation does
not duplicate the hook. No currently running feeder is started or stopped.
The anchor accepts indentation, spaces/tabs between the command and -s,
and trailing spaces/tabs or CR. It still requires exactly one full
/sbin/mdev -s command; commented commands and extra arguments do not match.
All original rcS lines are retained byte-for-byte; no line-ending conversion
or whole-file replacement from a host template is performed.

The helper reuses a correctly mounted eMMC, rejects wrong/read-only mounts,
and waits at most ten seconds for the eMMC device if not yet present. It
looks for an existing package in these locations:

- /mnt/ddr_work/ddr_p5
- /mnt/ddr_bootstrap/ddr_p5
- /mnt/ddr_work/full/ddr_p5

It prefers a feeder already running from any of these paths. Otherwise it
starts the first installed feeder using that package's own tools. Keep the
chosen package intact; no copy of the feeder itself is installed into NOR.
No retry loop, watchdog disable or automatic reboot is added. Without an
autostart count file no test is launched.
Mount/preparation failure is logged and rcS continues; the external watchdog
may still reset the board if it is not being serviced.

## Verification

After the current test completes and logs are saved, use sync and a normal
reboot when ready. After boot, no manual /mnt mount should be needed:

```sh
cat /proc/mounts | grep ' /mnt '
ls /mnt/ddr_work
cat /tmp/ddr-boot.log
cat /mem/ddr-wtd-feed/feed.log
```

The boot log should identify vfat/rw and a running feeder. With no autostart
count file it states that DDR tests are not automatically started. /tmp and
/mem logs are runtime-only.
This is not proof of physical watchdog timing or board stability; observe
uptime and validate on the actual board.

Start DDR testing manually from the full package when desired:

```sh
cd /mnt/ddr_work/full/ddr_p5
sh ddr_test.sh -c 1
```

## Disable Future Autostart

```sh
cd /mnt/ddr_work/boot_setup
sh install-ddr-boot.sh disable
```

Only the exact added rcS line is removed; unrelated rcS edits are preserved.
This disables both mount and feeding preparation on subsequent boots. It
does not stop the current feeder. Stopping feeding does not disable the
external watchdog and may cause a reset. Do not restore an old complete rcS
backup over newer unrelated changes.

## Host Checks

```sh
unshare -Ur python3 -B tools/test-ddr-boot.py -v
python3 -B tools/test-ddr-autostart.py -v
```

Tests use fake mount tables, programs and GPIO-free feeders. They never
mount real filesystems, change host init, run DDR tests, or contact a board.
