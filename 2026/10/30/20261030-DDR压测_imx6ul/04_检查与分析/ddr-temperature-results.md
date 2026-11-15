# P5 DDR Temperature Test Review

Reviewed live over UART on 2026-10-26 (Asia/Shanghai). Read-only inspection:
no board files changed, no test started or stopped, no reboot command sent.
The user rebooted the boards during connection troubleshooting. Existing
autostart launched fresh five-round batches; those are NOT included below.

## Result

Three completed runner batches per board were found: nine five-round batches.
All 45 SAT runs have PASS status, zero hardware incidents and zero errors.
All nine summaries report BIN/TAR success in each round; final saved counters
are BIN=1000 and TAR=100. All nine runner exit codes are zero.

However, seven of the 45 memtester invocations were killed by the OOM killer.
Only 38 memtester invocations completed all 18 subtests and reached Done.
Consequently five of the nine batches cannot be accepted as full-suite PASS.
A zero runner exit code or a test-end marker does not prove memtester passed.
No memtester FAILURE report was found in the checked completed subtests;
OOM is not evidence of a DDR data mismatch.

## Locations And Evidence

Every directory below is relative to /mnt/ddr_work/ddr_backup/ on its board.
Each contains ddr_all_test/ with the actual logs. Round numbers are ONE-BASED;
the corresponding memtester file index is round minus one.

Temperature labels are inferred from CPU temperature readings, not a verified
chamber setpoint, DDR package temperature or soak-time record.

| UART | Condition | Directory | CPU readings (C) | Memtester completed | OOM rounds | Runner duration |
| --- | --- | --- | --- | --- | --- | --- |
| ttyUSB0 | Room | previous.rJ4wVI | 49.70 to 50.76 | 5/5 | None | 12:23:57 |
| ttyUSB0 | Hot | previous.ZymhTJ | 85.08 | 3/5 | 1, 2 | 11:44:21 |
| ttyUSB0 | Cold | previous.rti0QJ | -17.88 | 4/5 | 1 | 12:00:53 |
| ttyUSB1 | Room | previous.HlyopI | 47.27 to 47.85 | 4/5 | 3 | 12:08:27 |
| ttyUSB1 | Hot | previous.X1RFXJ | 80.56 | 5/5 | None | 12:23:49 |
| ttyUSB1 | Cold | previous.1hL4FI | -18.72 to -17.56 | 4/5 | 4 | 12:08:34 |
| ttyUSB2 | Room | previous.TZn2yH | 44.43 to 44.99 | 5/5 | None | 12:24:17 |
| ttyUSB2 | Hot | previous.JMpPAK | 78.39 to 78.95 | 5/5 | None | 12:24:42 |
| ttyUSB2 | Cold | previous.f9QtrS | -29.15 to -28.59 | 3/5 | 3, 5 | 11:52:22 |

Board serial mapping during this inspection:

- ttyUSB0: pci-0000:03:00.0-usb-0:2:1.0-port0 (Prolific)
- ttyUSB1: pci-0000:03:00.0-usb-0:3.1:1.0-port0 (Prolific)
- ttyUSB2: pci-0000:03:00.0-usb-0:3.2:1.0-port0 (FTDI B002O5H8)

These Linux names may change on reconnect. Windows COM mapping was not verified.

There is also an older room-temperature SIX-round batch on ttyUSB0:
room_temp/ddr_all_test/. Its six SAT statuses are PASS and every memtester log
has 18 successful subtests plus Done. Its summary reports BIN/TAR Success for
all six rounds. CPU readings are 48.64 to 50.76 C; duration is 14:45:32.
It has no kernel snapshots in ddr_all_test/, unlike the newer autostart batches.

## OOM Evidence

- ttyUSB0 hot kernel-after.log: killed memtester PIDs 2285 and 32121.
- ttyUSB0 cold kernel-after.log: killed memtester PID 2285.
- ttyUSB1 room kernel-after.log: killed memtester PID 30702.
- ttyUSB1 cold kernel-after.log: killed memtester PID 28577.
- ttyUSB2 cold kernel-after.log: killed memtester PIDs 30721 and 25957.

The corresponding memtester logs have zero completed subtests and no Done
marker. OOM occurred around allocation/mlock. The current runner calculates
memory from free RAM minus 10 MiB and does not propagate memtester failure;
neither behavior was changed in this review.

## Caveats

- Board dates are 1970; durations above are differences between runner markers,
  not trustworthy calendar timestamps.
- Other previous.* folders contain interrupted/fresh batches and were not
  mistaken for the three completed condition datasets.
- FAT improper-unmount warnings were present on boot/on saved kernel logs.
  No filesystem repair or deletion was performed during this review.
- Final BIN/TAR counters cover the final round. Per-round Success is taken
  from the runner summary, not independently reconstructed unpack payloads.
- Successful software tests do not establish full DDR electrical qualification.
- UART excerpts are saved locally in out/serial_logs/serial-ddr-review-usb0.log,
  out/serial_logs/serial-ddr-review-usb1.log and out/serial_logs/serial-ddr-review-usb2.log.
  These are inspection transcripts, NOT full backups of board logs.
