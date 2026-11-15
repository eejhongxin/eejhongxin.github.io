# 高低温回收后只读检查：FTDI 板

2026-11-02（北京时间）通过 FTDI B002O5H8、115200 串口读取。该设备重插后由 ttyUSB2 变成 ttyUSB3；芯片 HW_OCOTP_CFG1=0x3c3699d4，之前称为 usb1 的板子。未启动/停止测试或喂狗，未修改配置、删除数据或重启。

检查时开机约97秒，cma=0，/mnt已是mmcblk1p7可写VFAT；系统自动开始新的6轮测试，处于第1轮SAT。当前ddr_all_test不算刚完成的温箱数据。

两批完整数据位于板端 /mnt/ddr_work/ddr_backup/：

| 条件候选 | 目录（内含ddr_all_test） | 轮数 | CPU温度 | 耗时 |
| --- | --- | --- | --- | --- |
| 高温 | previous.5f5VnI | 6 | 六次均80.56 C | 14:50:50 |
| 低温 | previous.JOqVbI | 6 | -21.64~-21.06 C | 14:51:15 |

两批12轮SAT全部Status PASS，明确记录0 hardware incidents、0 errors；12份memtester均18项ok及Done，未匹配到FAILURE/Killed/failed。每批BIN和TAR在总日志中各有6次Success，留存最终计数为1000和100。两批均有总结束标记及runner_exit_code=0；保存的kernel-before/after日志未匹配到OOM、Killed process、allocation failure、I/O error或Corrupted。

温度只是CPU传感器读数，应与温箱设定记录核对，不代替DDR器件温度。板端时钟为1970，耗时来自启动/结束标记之差。

其他备份：previous.nBn65H为此前常温8轮完整数据；previous.BueXZI、previous.t6fNpK、previous.NK1RvI、previous.pWVsTI只有第1轮开始，缺少完整结束记录，未作为已完成批次。

本次只保存查询摘录，尚未全量回传原始测试数据。原始串口记录：serial_logs/serial-ddr-post-chamber-20261102-ftdi.log。串口已退出释放。
