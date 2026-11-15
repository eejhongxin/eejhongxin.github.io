# CMA=0 后三板八轮测试检查

检查日期：2026-10-27（Asia/Shanghai）。通过三路 115200 串口只读检查，没有启动、停止测试或重启，没有修改板上文件。

## 结论

三块板均已执行完成 8 轮测试。测试前后保存的内核日志及当前 dmesg 均未发现 invoked oom-killer、Out of memory、Killed process 或 page allocation failure。
每块板均有 8 份 memtester 和 8 份 stressapptest 日志，轮次为索引 0..7；runner_exit_code 均为 0。

| 串口 | 芯片 CFG1 | 测试耗时 | memtester 完成 | stressapptest PASS | OOM |
| --- | --- | --- | --- | --- | --- |
| ttyUSB0 | 0x483699d4 | 19:48:06 | 8/8 | 8/8 | 未发现 |
| ttyUSB1 | 0x3c3699d4 | 19:47:28 | 8/8 | 8/8 | 未发现 |
| ttyUSB2 | 0x0c3599d4 | 19:48:26 | 8/8 | 8/8 | 未发现 |

三板 CFG0 均为 0xe1998bf2。串口按 USB 拓扑与芯片 ID 核对，编号可能随插拔变化。
耗时取自板上开始、结束标记之差；板上日期为 1970，不能作为真实日历时间。

## 检查依据

- 三板当前 /proc/cmdline 均包含 cma=0，CmaTotal 与 CmaFree 均为 0；开机轮数文件均为 8。
- 测试前后 kernel-before.log、kernel-after.log 均保留开机 0 秒起始记录；测试后内核快照中未匹配到 OOM、杀进程或页分配失败。
- 当前 dmesg 也未匹配到上述异常。
- 24 次 memtester 均显示 trying mlock ...locked.、18 个 ok 结果、1 个 Done.，未匹配到 FAILURE、failed、Killed、error、cannot、unable。
- memtester 第一轮均申请并锁定 217 MiB；后续各轮约 137..141 MiB。stressapptest 第一轮申请 218 MiB，两者计算时点不同。
- 24 次 stressapptest 均显示 Status: PASS、0 hardware incidents、0 errors，吞吐约 486..489 MB/s。
- 每轮总日志均记录 BIN 解包 Success、TAR 解包 Success；最终保存的 BIN/TAR 计数分别为 1000/100。计数只独立核实最终轮，其他轮依据总日志。
- 三板均已无 DDR 测试工作进程，喂狗 worker 仍运行。

console.log 最后一行 Inspect individual results and kernel logs for OOM/killed processes. 是固定提醒，不是检测出的 OOM。
原始 ': ok' 连续子串只能匹配部分对齐输出，最终使用 ok 标记数量加 Done、锁定成功及错误扫描交叉核对，每轮均为 18 项。

## 文件位置与限制

板上原始日志仍在各板 /mnt/ddr_work/ddr_all_test/，本次未移动或删除。
电脑上的检查记录（摘录，不是完整原始日志备份）：

- serial_logs/serial-ddr-8round-oom-check-usb0.log
- serial_logs/serial-ddr-8round-oom-check-usb1.log
- serial_logs/serial-ddr-8round-oom-check-usb2.log

这批数据支持关闭 CMA 后此次测试未再发生 OOM，不能保证其他负载或以后每次运行都不会 OOM。测试脚本依旧按瞬时空闲内存减 10 MiB 分配。
此次 CPU 温度范围约 42.73..50.76 C，不代表高低温复测已完成。
