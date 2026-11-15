# X6 Fixture Transfer And Single-Unpack Verification

Board verification completed on 2026-10-21 (Asia/Shanghai), using the FTDI
/dev/ttyUSB0 serial console. The board was not rebooted or flashed.

## Files Installed

Independent eMMC directory: /mnt/ddr_work/x6_fixture_20201225/

- x6_v2.1.2.4B560lcyT_b20201225.bin (19687144 bytes)
- md5_update_x6_v2.1.2_b20201127.txt (254 bytes, original repository manifest)
- ddr-x6-fixture.tar.gz (received archive, 19209116 bytes)
- unpack.log and md5-check.log (single-run verification evidence)

Archive transferred using host lrzsz via ZMODEM at temporarily configured
921600 baud; sender exit status 0, elapsed 220.2 seconds. SHA256 matched
between host and board for both the archive and extracted BIN:

    archive 4e0dac0512b651762d4e29b0ab2ef674cf14192fa5e0d8195c96921270c0eb77
    BIN     586e80bb27162e4e9fa3b41231da3afcabb6ffbe2660a9146c696ec72b793025

## Runtime Test

With the previous six eMMC mounts still present, copied the BIN and original
MD5 manifest into a fresh /tmp/ddr-x6-once.3RRBG3 directory and ran only:

    /data/sbin/checkupdate --unpack x6_v2.1.2.4B560lcyT_b20201225.bin
    md5sum -c md5_update_x6_v2.1.2_b20201127.txt

Both exit statuses were 0. Actual output confirmed "Udisk partition normal",
five extracted files, and "unpack success". All independent expected hashes
passed: update/app.bin, update/dtb.bin, update/install.sh, update/kernel.bin,
update/rootfs.bin. The install.sh file was never executed. Neither --update
nor no-argument checkupdate was invoked. No 1000-loop/full-suite pass claimed.

Copied the two evidence logs into the eMMC fixture directory, then deleted
only this session's fresh temporary directory. The older user-created
/tmp/ddr-bin-diag.cwGaE0 directory was left unchanged.

## Unchanged State And Handoff

- No edits to rcS, fstab, DDR test/helper scripts, original fixtures or manifests.
- Original full package still selects the incompatible 2025 BIN; this transfer
  alone does NOT configure the DDR script to use the new fixture.
- Existing checkupdate SHA256 unchanged:
  889d9f79745e68644904a442198affd820d6b2c565b7462051466efc6721cc00.
- Watchdog worker remained running as PID 285 from
  /mnt/ddr_work/ddr_p5/wtd_feed.sh.
- No long-running DDR workload started. Prior runtime read-only mounts retained.
- Restored UART to 115200, verified a command round trip, returned shell to
  /root, and closed the host serial connection without signalling the board.
- Host serial transcript: out/serial_logs/serial-x6-fixture-transfer.log.
