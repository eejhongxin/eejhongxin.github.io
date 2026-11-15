# 板上 DDR 备份清点

2026-10-27（北京时间）现场通过三路串口只读检查。没有删除、移动数据，没有停止测试或喂狗。

全部路径位于各板 `/mnt/ddr_work/ddr_backup/`。

| 串口 / OTP CFG1 | 完整 8 轮，应保留 | 未完成，可作为清理候选 |
| --- | --- | --- |
| ttyUSB0 / 0x483699d4 | previous.XNsEnJ | previous.HBWIzK、previous.N2gjaL |
| ttyUSB1 / 0x3c3699d4 | previous.nBn65H | previous.BueXZI、previous.t6fNpK |
| ttyUSB2 / 0x0c3599d4 | previous.9xVApI | previous.dEbi4H、previous.fXOrPH |

每块板 3 份备份，没有空目录：完整备份每份约 3648 KiB，未完成备份每份约 160 KiB。

三份完整数据均含 8 次 stressapptest PASS、8 份 memtester Done、8 次 BIN Success、8 次 TAR Success 和总测试结束标记，runner_exit_code=0。每板 ddr_all_test 下 23 个日志及结果文件的 SHA256 清单摘要，与电脑 `out/ddr-saved-8round-cma0/usbN/ddr_all_test/` 一致：

- usb0：c18a3df9e764af3a48c5dc9ca376d5b988988974c5385a4a8c5d6f6b46f0a812
- usb1：6604f46bd9ed6d060e6360f7fa529566ad04065e9d0a13dd3d4fcf17cfdf2aa9
- usb2：5f442055786f1f35b2cd4e451c6e7dc82adb88cba58ab4739cd156e892d7e132

六份未完成数据均仅开始第 1 轮 stressapptest，无该阶段 PASS、无 memtester 日志、无 BIN/TAR 成功标记、无总结束标记和 runner_exit_code。它们不能作为完成测试的证据；日志中断本身不说明 DDR 测试失败，也不能仅凭这些日志确定重启原因。

| 串口 | 备份 | 最后一条 stressapptest 日志（板端开机时间） | 阶段剩余秒数 |
| --- | --- | --- | --- |
| ttyUSB0 | previous.HBWIzK | 00:10:36 | 2970 |
| ttyUSB0 | previous.N2gjaL | 00:36:36 | 1410 |
| ttyUSB1 | previous.BueXZI | 00:36:56 | 1390 |
| ttyUSB1 | previous.t6fNpK | 00:10:36 | 2970 |
| ttyUSB2 | previous.dEbi4H | 00:36:46 | 1400 |
| ttyUSB2 | previous.fXOrPH | 00:10:36 | 2970 |

当前 `/mnt/ddr_work/ddr_all_test` 不属于上述备份。本次重新连通时三板开机约 46 秒，均已重新自动启动 `-c 6`，正在第 1 轮 stressapptest；此次检查未启动新测试。

原始记录：`out/serial_logs/serial-ddr-backup-review-usb{0,1,2}.log`。其中前段含连接异常时的乱码和重复串口内容；判断依据为其后 BACKUP_LIST、BACKUP_DETAIL 和 FULL_DIGEST 标记间的有效输出。
