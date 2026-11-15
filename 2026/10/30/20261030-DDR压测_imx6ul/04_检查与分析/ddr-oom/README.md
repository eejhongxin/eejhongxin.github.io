# OOM Context Export

Collected on 2026-10-26 (Asia/Shanghai), read-only, from saved board logs.
No test/boot scripts changed. Board terminal echo was temporarily disabled
for clean capture and restored before disconnecting both UART sessions.

## Exported Files

All rounds below are one-based; memtester file index is round minus one.

| File | Board / condition / round | Requested memory | Source dataset |
| --- | --- | --- | --- |
| usb0-hot-kernel-context.log | ttyUSB0 hot rounds 1, 2 | 217, 144 MiB | previous.ZymhTJ |
| usb0-cold-kernel-context.log | ttyUSB0 cold round 1 | 217 MiB | previous.rti0QJ |
| usb1-room-kernel-context.log | ttyUSB1 room round 3 | 141 MiB | previous.HlyopI |
| usb1-cold-kernel-context.log | ttyUSB1 cold round 4 | 140 MiB | previous.1hL4FI |

Source paths on each board:
/mnt/ddr_work/ddr_backup/DATASET/ddr_all_test/kernel-after.log

The files include kernel lines before/after the OOM report, the call stack,
Mem-Info, zone watermarks, free block lists, process tables and kill decision.
They are excerpts, not complete kernel logs. Source selections are noted in
each file. UART prompts and carriage returns were removed, not kernel data.
Requested sizes were freshly checked from the corresponding memtester logs;
each ended with "trying mlock ..." without completing a subtest.

## Memory At OOM

Values below are kB as printed by Linux (KiB). Non-CMA is calculated from
Normal free minus free_cma, not a claim that every remaining page is usable.

| Event | Normal free | free_cma | Free minus CMA | Normal min |
| --- | --- | --- | --- | --- |
| ttyUSB0 hot round 1 | 98708 | 97832 | 876 | 1988 |
| ttyUSB0 hot round 2 | 73220 | 71220 | 2000 | 1988 |
| ttyUSB0 cold round 1 | 98252 | 96332 | 1920 | 1988 |
| ttyUSB1 room round 3 | 96096 | 95452 | 644 | 1988 |
| ttyUSB1 cold round 4 | 91948 | 90672 | 1276 | 1988 |

Four events show SyS_mlock -> __mm_populate -> page fault handling ->
__pte_alloc -> __alloc_pages_nodemask -> OOM. In particular this includes a
failed page-table allocation, which cannot treat all free CMA pages as
ordinary allocatable memory. This does NOT mean all user anonymous pages or
all mlock operations are categorically forbidden from using CMA.

The ttyUSB1 cold event was triggered by kthreadd during copy_process with
order=1; memtester was selected as the OOM victim. The allocation trigger
and the killed process are not necessarily the same process.

All five reports have no swap. Later rounds show shmem=38168 kB (about
37.3 MiB); the first-round reports show only 8 kB. This demonstrates that
memory composition changes between rounds. The exact owner of all shmem
was not independently traced by this export.

## Third Board Limitation

ttyUSB2 was not present during this export, so its two full OOM contexts
could not be fetched. The prior inspection transcript retains the summary
for previous.f9QtrS, cold rounds 3 and 5:

```
[21823.193323] memtester invoked oom-killer: gfp_mask=0x2084d0, order=0, oom_score_adj=0
[21823.532453] Out of memory: Kill process 30721 (memtester) score 443 or sacrifice child
[21823.540413] Killed process 30721 (memtester) total-vm:145924kB, anon-rss:113196kB, file-rss:0kB
[38514.375150] memtester invoked oom-killer: gfp_mask=0x2084d0, order=0, oom_score_adj=0
[38514.714727] Out of memory: Kill process 25957 (memtester) score 400 or sacrifice child
[38514.722690] Killed process 25957 (memtester) total-vm:146948kB, anon-rss:102380kB, file-rss:0kB
```

The earlier UART transcript is ../serial_logs/serial-ddr-review-usb2.log; the full
source remains on that board under the dataset path stated above.
