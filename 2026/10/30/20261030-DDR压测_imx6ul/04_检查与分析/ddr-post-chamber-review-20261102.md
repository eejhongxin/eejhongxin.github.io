# 三板高低温测试记录检查

日期：2026-11-02（北京时间）。通过串口只读查询。未修改板端数据、配置或喂狗，未发送启动测试或重启命令。本次上电后原有开机自启已开始新一批6轮；当前ddr_all_test不能与完成的温箱记录混用。

## 数据位置

下表目录均相对于各板 /mnt/ddr_work/ddr_backup/，内部ddr_all_test为实际测试日志。

| 芯片CFG1 | 串口识别说明 | 高温目录 | CPU温度C | 低温目录 | CPU温度C |
| --- | --- | --- | --- | --- | --- |
| 0x483699d4 | 初读ttyUSB1，重插后ttyUSB2 | previous.3GlTVI | 83.49 | previous.ZaOTYH | -20.00~-19.47 |
| 0x3c3699d4 | FTDI B002O5H8 / ttyUSB3 | previous.5f5VnI | 80.56 | previous.JOqVbI | -21.64~-21.06 |
| 0x0c3599d4 | 初读ttyUSB0，最终复核ttyUSB1 | previous.pObVAK | 78.95~79.52 | previous.1fozbK | -30.28~-29.72 |

六个批次均有6轮的总日志、SAT PASS、memtester Done、BIN/TAR每轮Success、总结束标记及runner_exit_code=0。全部36轮SAT均0errors/0hardware incidents，36份memtester均18项ok及Done；每批最终BIN/TAR计数各1000/100，保存的内核快照均未发现OOM、Killed process或内存分配失败。没有发现memtester FAILURE。

温度列来自CPU传感器，不能替代温箱设定温度、DDR封装温度或保温时间记录。板端时间1970不能作为实验日历日期。

## 本机保留内容

本次保存的是检查摘录与报告，尚未全量回传板端原始数据。报告见ddr-post-chamber-20261102-usb1.md、ddr-post-chamber-20261102-ftdi.md及后续usb0核验报告；原始查询记录保留在serial_logs/serial-ddr-post-chamber-20261102-*.log。

随后按用户要求已完整回传三板全部DDR备份与当前活动日志快照，保存于 `ddr-saved-post-chamber-20261102/`。三板各91个备份文件、合计273个文件的源清单前后相同，回传归档SHA256及逐文件校验均通过。目录内包括9份已完成归档（6份新高低温六轮、3份旧常温八轮）、12份中断归档及3份当前活动快照；详见该目录README、batch-review.json和各板verification.json。

历史常温8轮分别仍位于previous.XNsEnJ（483699d4）、previous.nBn65H（3c3699d4）、previous.9xVApI（0c3599d4）；原先电脑归档也保留。其他只有第1轮SAT的previous目录没有作为本次已完成高低温结果。


2026-11-02后续按用户要求精简本地数据：现在仅保留9份完整常温/高温/低温记录，统一位于ddr-saved-post-chamber-20261102/chip_芯片ID/{roomtemp,hightemp,lowtemp}/ddr_all_test；旧previous路径和完整回传包描述的是整理前状态，板上源数据未改动。
