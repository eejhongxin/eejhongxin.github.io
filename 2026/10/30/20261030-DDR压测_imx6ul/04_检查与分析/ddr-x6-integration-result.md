# P5 DDR X6 Fixture Integration

## Changes

- Build selection: tools/build-ddr-p5.sh now takes the BIN and matching MD5
  manifest from emmc_test/check_update/check_update_bin, selecting
  x6_v2.1.2.4B560lcyT_b20201225.bin. The packaged BIN helper substitutes only
  its executable path and input filename. Original shared helpers are unchanged.
- P5 runner preparation additionally mounts missing p1/p2/p3 as vfat/ro at
  /recovery, /firmware, /reserve and p6 as ext4/ro,noload at /data/app/log.
  Existing correct mounts are reused, incorrect mounts rejected. This satisfies
  the existing checkupdate's startup requirement for six eMMC mounts.
- README and isolated preparation tests updated. Original workload parameters,
  sequence, logging and result logic retained, including their existing limits.

## Board Deployment

Updated only /mnt/ddr_work/full/ddr_p5/: runner, README, BIN helper, BIN fixture,
BIN MD5 manifest and SHA256SUMS. The previous package passed all its checksums
before backup. Backup directory:

    /mnt/ddr_work/x6-before-change.x3JPPU

It retains the previous runner, README, SHA256SUMS and complete BIN directory.
The incompatible 2025 BIN was removed from the active package into that backup.
The separately transferred X6 fixture remains untouched in its original folder.

Board staging archive and evidence:

    /mnt/ddr_work/x6-integration.5hcZyc/
    /mnt/ddr_work/x6-integration.5hcZyc/evidence/helper-once.log
    /mnt/ddr_work/x6-integration.5hcZyc/evidence/check_result

Only a 7.2 KiB patch was transferred at 115200 baud; the X6 BIN was copied
locally on eMMC. All updated package SHA256 checks passed. Board stressapptest
was deliberately retained, not replaced by the new host rebuild, so its board
manifest entry retains bc04c6cb30e8d5df82e71aa73d1846b1d3c8a8d89afc1666e7ec13055b622d16.
Host full/tools bundles have their own matching newly generated manifests.

## Verification

- Host: 31 syntax/parity/tool/watchdog/mount tests passed; build succeeded;
  extracted full bundle passed every SHA256 check.
- Board: extracted and ran only the new runner's mount-preparation block,
  successfully reusing the six existing mounts. No applications were stopped.
- Copied the updated BIN helper directory into a fresh /tmp directory and ran
  sh check_update.sh 1 with the package tool PATH. Actual unpack succeeded;
  all five payload MD5 checks were OK; check_result contained exactly 1.
  Logs persisted to the evidence directory, then only this session's temporary
  verification directory was removed. No install.sh was executed.
- Existing /data/sbin/checkupdate SHA256 remained
  889d9f79745e68644904a442198affd820d6b2c565b7462051466efc6721cc00.
- Watchdog remained Running: PID=285 from /mnt/ddr_work/ddr_p5/wtd_feed.sh.
- No reboot, flash, formatting, filesystem repair, boot/rootfs configuration
  edits, long DDR run or 1000-iteration success claim.
- Older user diagnostics in /tmp retained (32.1 MiB used, 89.1 MiB available).
  No old test logs were cleared. UART remains 115200; serial released afterward.

## Manual Run

    cd /mnt/ddr_work/full/ddr_p5
    sh ddr_test.sh -c 1

Use -c 12 for twelve complete rounds, not exactly twelve elapsed hours.
Each round retains SAT 3600s, memtester once, BIN x1000 and TAR x500.
Results remain /mnt/ddr_work/ddr_all_test/ddr_log.log; logs append/reuse the
original names. The separately running feeder must remain active.
