# 高低温完成后板端日志检查：CFG1=0x0c3599d4

北京时间 2026-11-02，通过 115200 串口只读检查。首次口名 ttyUSB0，重插后 ttyUSB1；以 OTP CFG1 确认同一块板，CFG0=0xe1998bf2。未修改配置、挂载、重启、删除数据，未启动/停止测试或喂狗。

当前启动 cma=0，首次读取开机约 163 秒，自动重新开始 -c 6 第 1 轮 stressapptest；喂狗仍运行，/mnt 为 mmcblk1p7 vfat/rw。当前新测试不是下表已完成批次。

全部备份位于 `/mnt/ddr_work/ddr_backup/`，每项内日志为 `ddr_all_test/`。

| 备份 | 已开始轮数 | SAT PASS | memtester Done | BIN/TAR成功 | 结束标记 | CPU温度摄氏度 | 判断 |
| --- | ---: | ---: | ---: | --- | --- | --- | --- |
| previous.pObVAK | 6 | 6 | 6 | 6/6 | 有，exit=0 | 78.95～79.52 | 新高温候选，完整 |
| previous.1fozbK | 6 | 6 | 6 | 6/6 | 有，exit=0 | -30.28～-29.72 | 新低温候选，完整 |
| previous.9xVApI | 8 | 8 | 8 | 8/8 | 有，exit=0 | 42.73～43.86 | 已保存的旧常温八轮 |
| previous.dEbi4H | 1 | 0 | 0 | 0/0 | 无 | 无 | 旧中断批次 |
| previous.fXOrPH | 1 | 0 | 0 | 0/0 | 无 | 无 | 旧中断批次 |
| previous.rzDZnJ | 1 | 0 | 0 | 0/0 | 无 | 无 | 中断批次 |

两份新高低温候选已单独短命令复核：

- 12 次 stressapptest 全部 Status: PASS，Completed 行全部为 0 hardware incidents、0 errors。
- 12 份 memtester 各 18 个 ok、Done.，没有匹配到 FAILURE。
- 各批 kernel-before/after 快照没有匹配 invoked oom-killer、Out of memory、Killed process、page allocation failure。
- 两批最终保存 BIN 计数均 1000、TAR 均 100；逐轮 Success 均来自总日志。

温度为脚本记录的 CPU 测温，不代表独立核实温箱设定、保温时长或 DDR 壳温；板端日期为 1970，不能据此确定日历时间。此次仅检查，尚未全量导出新高低温日志或逐文件校验源内容。

原始串口输出：`serial_logs/serial-ddr-post-chamber-20261102-usb0.log`。首段 DATASETS 长命令因行长限制截断，其 OOM 段无有效结论；最后 SHORT_VERIFY 段短命令已对两批完整性补充验证。期间为结束该只读 grep 的标准输入发送过 EOF，没有触碰后台测试；连接最终已释放。
