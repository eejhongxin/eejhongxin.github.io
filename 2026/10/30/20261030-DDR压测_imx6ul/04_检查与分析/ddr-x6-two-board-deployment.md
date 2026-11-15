# X6 DDR Delta Deployment To Two Additional P5 Boards

## Board Mapping And Final State

| Linux UART | USB physical path | Backup directory | Watchdog PID |
| --- | --- | --- | --- |
| ttyUSB0 | pci-0000:03:00.0-usb-0:2:1.0-port0 | /mnt/ddr_work/x6-before-change.wmolr2 | 281 |
| ttyUSB1 | pci-0000:03:00.0-usb-0:3.1:1.0-port0 | /mnt/ddr_work/x6-before-change.SNKwZz | 285 |

Both adapters are PL2303 with the same ID string; physical paths were used
instead of the conflicting by-id link. The user rebooted both boards during
the work. Final deployment and validation were completed after that reboot.
UARTs were restored to 115200, verified by shell round trips, and released.
Both watchdogs remained running; no stress workload was left running.

## Files Transferred

To each board:

- /mnt/ddr_work/full/ddr-x6-integration-patch.tar.gz (about 7.2 KiB)
  SHA256 a1670557cddf62faa261f26caaaf549b5caa578748a952680d70fec214c21da5
- /mnt/ddr_work/x6_fixture_20201225/ddr-x6-fixture.tar.gz (19209116 bytes)
  SHA256 4e0dac0512b651762d4e29b0ab2ef674cf14192fa5e0d8195c96921270c0eb77

Only these delta archives completed transfer; the earlier full-bundle attempts
were cancelled, not deployed. UART transfer used existing lrz/sz with a host
PTY relay to isolate sz terminal-mode changes from the physical serial device.
The script-only archives were verified at 115200, then BIN transfers completed
at 921600 in 297.8s / 324.1s. All received archive hashes matched the host.

Both fixture archives were extracted into x6_fixture_20201225/. The X6 BIN
was then copied locally into /mnt/ddr_work/full/ddr_p5/check_update/check_update_bin/.
The patch updated that package's runner, README, BIN helper, BIN MD5 manifest
and SHA256SUMS. Existing checkupdate, tools, TAR helper and test parameters
were not replaced by new implementations. Previous scripts were backed up.
On ttyUSB1 the incompatible 2025 BIN was retained in the backup BIN directory.

## ttyUSB0 Existing TAR Repair

The pre-existing /mnt/ddr_work/ddr-p5-full.tar.gz was truncated at 42106880
bytes and tar reported short read. Its tools section was unavailable, so
the existing tools directory was verified against its own SHA256SUMS and
copied locally to full/ddr_p5. The running feeder's original directory was
kept intact. Selected TAR entries were recovered under:

    /mnt/ddr_work/ddr-tar-recover.eIbGq0/ddr_p5/check_update/check_update_tar/

The recovered update.tar.bz2 prefix was exactly 17511936 bytes. Its SHA256
matched the host's same-length prefix:

    10446c9bec1bfe05c87e5e29a2394478a49d8dd65853f7e01574c564422cc688

With the user's approval, transferred only the missing 1847923-byte suffix:

    /mnt/ddr_work/ddr-tar-recover.eIbGq0/ddr-p5-tar-tail-17511936.bin
    SHA256 172bb1326d0da33ee9adebac1bd0fcceff8fe50e2da0c6c557bcc00afb103725

After checking the suffix hash, dd wrote it at byte offset 17511936 without
truncation. The full 19359859-byte TAR fixture then matched the host hash:

    c2951c4d96dd194500a411294df8cdaecef2ef2e74b260bcc9cb1c57e02cda02

The repaired TAR directory was copied locally into the active full package.
No tools or whole TAR fixture were re-transferred. On ttyUSB1 its complete
existing full archive was verified and extracted locally; no TAR transfer
was needed. Old full archives were preserved, not rewritten; do not extract
those old archives over the updated package.

## Verification On Both Boards

- Every active full/ddr_p5/SHA256SUMS entry passed after deployment.
- Executed only the runner's mount-preparation block, not application-stop
  or memory-test code. Missing p1/p2/p3 were mounted vfat/ro and p5/p6 were
  mounted ext4/ro,noload. Existing /mnt vfat/rw was reused. No boot config edits.
- Existing /data/sbin/checkupdate matched the original reference hash both
  before unpack and at final verification:
  889d9f79745e68644904a442198affd820d6b2c565b7462051466efc6721cc00
- In a fresh /tmp directory, copied the updated BIN helper directory and ran
  sh check_update.sh 1 with the active package tool PATH. Both boards reported
  Udisk partition normal, unpack success, five payload MD5 OK results and
  check_result exactly 1. No install.sh or --update operation was executed.
- Kept evidence on each board:
  /mnt/ddr_work/full/x6-package-sha.log
  /mnt/ddr_work/full/x6-verification/helper-once.log
  /mnt/ddr_work/full/x6-verification/check_result
- Removed only this session's fresh /tmp verification directories. Existing
  archives, logs, original tools and eMMC data were preserved. No flashing,
  formatting, filesystem repair command, rootfs/rcS edit or long DDR run.

Host transcripts: out/serial_logs/serial-x6-board-usb2.log and
out/serial_logs/serial-x6-board-usb3_1.log. Host tools/serial-fixture-console.py was updated
with explicit port/baud/log selection, cancellation and PTY-based ZMODEM relay.

## Manual Test

On either board:

    cd /mnt/ddr_work/full/ddr_p5
    sh ddr_test.sh -c 1

Logs remain /mnt/ddr_work/ddr_all_test/ddr_log.log. The original parameters
and their limitations are retained; single unpack verification does not
establish a complete round or DDR qualification pass.
