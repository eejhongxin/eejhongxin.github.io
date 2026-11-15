# 三板开机自启 6 轮检查

检查时间：2026-10-26 20:23–20:26 PDT（北京时间 2026-10-27）。通过三路 115200 串口现场只读检查；未修改板上文件、未启动新测试、未重启或停止喂狗。

| 串口 | OTP CFG1 | count 文件 | 本次启动 worker / 测试参数 | 喂狗 | 检查时阶段 |
| --- | --- | --- | --- | --- | --- |
| ttyUSB0 | 0x483699d4 | 6 | --worker 6 / -c 6 | PID 285，Running | 第 1/6 轮 stressapptest |
| ttyUSB1 | 0x3c3699d4 | 6 | --worker 6 / -c 6 | PID 285，Running | 第 1/6 轮 stressapptest |
| ttyUSB2 | 0x0c3599d4 | 6 | --worker 6 / -c 6 | PID 285，Running | 第 1/6 轮 stressapptest |

三板 `/etc/inittab` 均从 rcS 启动，rcS 第 224 行调用 `/etc/init.d/ddr_boot_prepare.sh`。本次 `/tmp/ddr-boot.log` 均明确记录 `Autotest scheduled: rounds=6`。启动日志记录旧数据已归档，本次新日志持续增长；检查结束时开机约 599 秒，stressapptest 剩余 3020 秒，无重启迹象。

三板以下脚本 SHA256 一致，并全部通过 `sh -n`：

- 外层和 boot_setup 内的 ddr_autostart.sh：`8d35eebd8437f69e59935eb9c5d154776eefdeabffe1707390716643dfa31076`
- ddr_boot_prepare.sh：`20de9120d63fa4e495eb81d3f9904886bacda73037d97513745efac72c53af2a`
- full/ddr_p5/ddr_test.sh：`b5f6ef0e3de0721db2d0bf569f5550dba9e8b32139c5f270c3aa0cd90508609a`
- full/ddr_p5/ddr_progress.sh：`abe2f6de1485ad8829ecc582d1df3f2a235a0a13a5afba180219dd9bf1585058`

测试脚本与本地源文件校验值相同：每外层轮包含 stressapptest 3600 秒、memtester 1 轮、BIN 解包 1000 次、TAR 解包 100 次。BIN/TAR 素材均存在，本次未全量校验素材内容。脚本按 thermal_zone1 读取 CPU 温度；现场读取三板分别约 52.34、49.02、46.13 摄氏度。

三板当前 cmdline 和已保存的 qspi_args 均为 `cma=0`。/mnt 均为 mmcblk1p7、vfat/rw，剩余约 28GiB；/data、/recovery、/firmware、/reserve、/data/app/log 均已按测试脚本要求挂载。

本次 dmesg 未发现 OOM、Killed process、allocation failure、Corrupted directory 或 I/O error。三板均存在启动时 FAT `Volume was not properly unmounted` 警告：当前挂载、自动归档和日志写入正常，但未离线运行 fsck，因此不能据此确认文件系统完全无损。测试运行中未执行修复。

本次仅确认自启 6 轮已实际生效及当前运行状态，尚未完成本次 6 轮，也不构成高低温测试通过结论。每次重启会重新从第 1 轮开始，并把旧 ddr_all_test 移到 ddr_backup/previous.XXXXXX/ddr_all_test。

原始串口记录：

- serial_logs/serial-ddr-pre-chamber-usb0.log
- serial_logs/serial-ddr-pre-chamber-usb1.log
- serial_logs/serial-ddr-pre-chamber-usb2.log
