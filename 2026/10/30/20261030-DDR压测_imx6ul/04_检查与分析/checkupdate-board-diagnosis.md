# P5 checkupdate diagnostic result

Inspected through /dev/ttyUSB0 (FTDI FT232R), 115200 baud, on 2026-10-21
Asia/Shanghai. No reboot, firmware update, format, repair or program replacement.

## Confirmed Board State

- External watchdog feeder remained PID 285 throughout the session:
  sh /mnt/ddr_work/ddr_p5/wtd_feed.sh --worker.
- /tmp/ddr-boot.log confirmed automatic vfat/rw /mnt mounting and feeding;
  DDR tests were not launched automatically. No DDR test was running.
- /mnt was already rw on mmcblk1p7; /data was already ro,noload on mmcblk1p5.
- Existing /data/sbin/checkupdate: 127955 bytes, version string 2.1.0,
  SHA256 889d9f79745e68644904a442198affd820d6b2c565b7462051466efc6721cc00.
  Hash matched before and after diagnostics. A read-only serial/base64 copy
  was saved as out/ddr-build/checkupdate-board-20220528 for local analysis.

## Failure 1: Startup Partition Check

strace confirmed that before option parsing checkupdate invokes:

    mount | grep mmcblk1p | awk '{print $1}'

Its main() counts occurrences of /dev/mmcblk1p and exits with
"Udisk partition failure" and exit status 0 if the count is <= 5.
The initial board had only two matching mounts, /mnt and /data.
The BIN had not yet been opened at this failure point.

## Failure 2: Incompatible Header Interpretation

Temporarily added the other original P5 mount locations, all read-only:

- mmcblk1p1 -> /recovery, vfat/ro
- mmcblk1p2 -> /firmware, vfat/ro
- mmcblk1p3 -> /reserve, vfat/ro
- mmcblk1p6 -> /data/app/log, ext4/ro,noload

The six-mount check then passed. Only --unpack was executed, in the user's
existing /tmp/ddr-bin-diag.cwGaE0 directory, never --update or no-argument mode.
The first untraced run and subsequent strace run both segfaulted without
creating update/. Trace shows failed ~360787968-byte mmap requests (ENOMEM)
followed by SIGSEGV at NULL after opening the supplied BIN.

Local disassembly of this exact board binary establishes the reason:
unpack_package at 0xe938 reads a fixed 60-byte header; at 0xea0c it loads
the 32-bit field at file offset 56, multiplies it by 12, allocates that
entry-table size, and passes the result to fread without a NULL check.
In update_13emmc_v1.0.0_b20250703.bin, bytes 56..59 are ASCII '(nul', i.e.
0x6c756e28 / 1819635240. Multiplying by 12 in 32 bits yields 360786400 bytes.
This is an invalid file-count interpretation, not evidence that this
fixture legitimately needs 344 MiB or that physical DDR has failed.
The current BIN and this board decoder are incompatible at the header level.

## Changes Left On The Board

- Four additional runtime read-only mounts above; not added to boot config.
- Diagnostic stdout/strace files in /tmp/checkupdate-*.
- Copies of those four files persisted in /mnt/ddr_work/checkupdate_diagnosis/.
- The user's pre-existing /tmp BIN copy was retained; it uses about 32 MiB
  of tmpfs and will disappear on reboot. No test data or old logs were deleted.
- Shell returned to /root. Feeder remained running. Serial connection closed.

No changes to rcS, fstab, ddr_test.sh, checkupdate, BIN/TAR fixtures,
partition contents, or kernel/U-Boot configuration were made in this session.
No full-suite or 12-hour pass is claimed. A compatible P5 BIN fixture with
matching expected hashes is needed to preserve the original BIN-test workflow.
Partition preparation must also cover the existing tool's six-mount condition.
