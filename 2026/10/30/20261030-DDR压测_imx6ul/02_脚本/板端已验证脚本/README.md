# P5 DDR Test: Minimal Path Adaptation

p5/ddr_test.sh is the original ../ddr_test.sh with these path changes and
a mount-preparation block before the original system_test_init actions:

- Add the package bin directory and /data/sbin to PATH.
- Logs: /userdata/ddr_all_test -> /mnt/ddr_work/ddr_all_test.
- Fixtures: /userdata/ddr_test/check_update -> this package's check_update.
- CPU temperature: thermal_zone0/temp -> thermal_zone1/temp (confirmed on P5).
- Packaged BIN helper: checkupdate -> /data/sbin/checkupdate, using the compatible
  x6_v2.1.2.4B560lcyT_b20201225.bin fixture and its matching MD5 manifest.

The progress additions source ddr_progress.sh, duplicate native SAT and
memtester output to the console, and observe BIN/TAR counters without changing
the original helper scripts. TAR iterations and the matching success threshold
are reduced from 500 to 100 at the user's request; the progress total is 100 too.

The original script and original check_update sources are not edited.
The BIN helper's command-path and input-filename substitutions are applied
during packaging. Its fixture and MD5 manifest come from emmc_test/check_update/
check_update_bin. The TAR helper and fixture are unchanged. Manifests retain
the previous packaging normalization of CRLF to LF.

Test sequence, free-memory-minus-10-MiB calculation, 8 copy threads, 3600
seconds, one memtester loop, 1000 BIN iterations, delays, round numbering,
summary format and pass/fail logic are all ORIGINAL, except the requested
TAR loop count and matching success threshold of 100 instead of 500.
This intentionally restores the original limitations in result checking:
a zero shell exit status is NOT sufficient evidence that every test passed.
No test-result fail-fast policy, unique run directory or test lock is added.
Only preparation failure stops the run before the original tests start.
No --check, --memory, --seconds or --no-unpack option is added.

## Build And Packages

From /home/jihongxin/Documents/imx6ul:

```sh
bash tools/build-ddr-p5.sh
```

- out/ddr-p5-full.tar.gz: tools, scripts, BIN/TAR fixtures; use for a fresh install.
- out/ddr-p5-tools.tar.gz: tools and scripts only, no large fixtures.
- out/ddr-p5-bundles.sha256: archive checksums.

Tools and the separate watchdog/memory-sampling helpers are unchanged from
the previous package. No checkupdate binary or wrapper is included. Nothing
is installed into the board's /bin, /lib or /data/sbin. No firmware is flashed.

## Board Preparation

Do not overwrite an active test or feeder. Confirm eMMC is mounted before
transferring files under /mnt; an unmounted /mnt is on the NOR root filesystem.
On sh ddr_test.sh -c N, the preparation block automatically creates missing
mount points and mounts /dev/mmcblk1p7 as vfat/rw on /mnt and /dev/mmcblk1p5
as ext4/ro,noload on /data. Existing correct mounts are reused unchanged,
including an already read-write /data. Wrong or read-only /mnt mounts, wrong
/data mounts, mount failures and a missing existing checkupdate stop before
the original tests start. No formatting, repair, forced remount or tool
replacement is performed.

The existing P5 checkupdate also checks for six mounted eMMC partitions before
processing --unpack. Preparation mounts missing p1/p2/p3 on /recovery, /firmware,
/reserve as vfat/ro, and p6 on /data/app/log as ext4/ro,noload. Existing correct
mounts are reused; incorrect mounts stop preparation. These runtime mounts do
not change rcS, fstab or any boot configuration.

For the INITIAL transfer/extraction, /mnt must still be mounted before
putting the package there. If the script itself lives on an unmounted eMMC
partition, it cannot be started until that partition is mounted. The commands
below are only for this bootstrap case; the running test prepares its mounts:

```sh
if ! grep -q ' /mnt ' /proc/mounts; then
    mkdir -p /mnt
    mount -t vfat -o rw /dev/mmcblk1p7 /mnt
fi
if ! grep -q ' /data ' /proc/mounts; then
    mkdir -p /data
    mount -t ext4 -o ro,noload /dev/mmcblk1p5 /data
fi
cat /proc/mounts | grep -E ' /(mnt|data) '
ls -l /data/sbin/checkupdate
mkdir -p /mnt/ddr_work
cd /mnt/ddr_work
```

Use the full archive for a new installation, then:

```sh
tar -xzf ddr-p5-full.tar.gz
cd ddr_p5
sha256sum -c SHA256SUMS
```

The tools archive contains no fixtures. Do not reuse the incompatible 2025
BIN from an earlier full package. On the board with the separately verified
X6 fixture, these commands supply the BIN and its matching MD5 (relative to
ddr_p5). TAR fixtures must also be supplied from the full package:

```sh
cp /mnt/ddr_work/x6_fixture_20201225/x6_v2.1.2.4B560lcyT_b20201225.bin check_update/check_update_bin/
cp /mnt/ddr_work/x6_fixture_20201225/md5_update_x6_v2.1.2_b20201127.txt check_update/check_update_bin/
```

## Run And Results

The X6 fixture was verified on this P5 with the existing 2022 checkupdate:
one --unpack completed and all five payload MD5 checks passed. This is fixture
compatibility evidence, not a full DDR test. Recheck on boards with other tools.
Never use --update or invoke checkupdate without arguments for these tests.

Start temporary external watchdog feeding separately:

```sh
sh wtd_feed.sh start
sh wtd_feed.sh status
sh ddr_test.sh -c 12
```

-c 12 runs twelve COMPLETE rounds. Stressapptest alone totals 12 hours;
memtester, unpack tests and delays make total duration longer than 12 hours.
Keep the serial terminal connected. The test itself does not manage feeding.
The feeder survives terminal disconnection but disappears after reboot.
Stopping feeding does not disable the external watchdog and can cause a reset.

Logs are fixed files, appended/reused like the original, not run.XXXXXX:

```sh
cat /mnt/ddr_work/ddr_all_test/ddr_log.log
tail -f /mnt/ddr_work/ddr_all_test/stressapptest_0.log
cat /mnt/ddr_work/ddr_all_test/memtester_0.log
```

Temperature and CPU frequency are recorded in ddr_log.log after each round.
Console progress shows one-based round/stage banners and elapsed time. SAT's
native "Seconds remaining" appears every 10 seconds; this covers only its
3600-second workload, not the complete round. Memtester displays its native
subtests; its remaining time is unknown. BIN/TAR counters are sampled every
10 seconds with an estimated remaining time based on completed iterations.
Estimates can vary and are not test results. No exact whole-round ETA is given.
The counter observer is stopped and reaped when its stage finishes or the
runner exits. Progress messages do not change the original summary log format.

The original clean command deletes this test log directory. Back up logs
before using it. Original S080_application stop commands are also retained;
if that init script is absent on P5, they print errors and do not stop P5 apps.
Only 10 MiB memory is reserved. OOM, missing tools, incompatible fixtures,
watchdog resets and incomplete tests must not be reported as DDR failures.

Host syntax/parity tests are not board DDR validation. After stopping tests,
finish storage access with sync and unmount only when no process uses it.
