# 高低温回收后只读检查：当前 ttyUSB1

检查日期：2026-11-02（北京时间）；115200 串口。没有启动或停止测试/喂狗，没有重启、修改配置、挂载、修复或删除。

当前串口对应芯片 `HW_OCOTP_CFG1=0x483699d4`，是先前称为 usb0 的板子；串口编号发生变化。首次查询开机约 171 秒，cmdline 为 `cma=0`，eMMC 分区已经挂载。喂狗 PID285 正在运行，本次开机自动开始 `ddr_test.sh -c 6`，检查时处于第 1 轮 stressapptest。这份当前日志不作为刚完成的温箱批次。

## 全部候选批次

路径均相对于 `/mnt/ddr_work/ddr_backup/`，每个目录内为 `ddr_all_test/`。

| 目录 | 判断 | 轮数/CPU温度 |
| --- | --- | --- |
| previous.3GlTVI | 新高温候选，六轮完整 | 6轮，六次均 83.49 C |
| previous.ZaOTYH | 新低温候选，六轮完整 | 6轮，-20.00~-19.47 C |
| previous.XNsEnJ | 先前已经归档的常温数据 | 8轮，49.17~50.76 C |
| previous.HBWIzK | 旧中断数据 | 第1轮SAT，约10分36秒处中断 |
| previous.N2gjaL | 旧中断数据 | 第1轮SAT，约36分36秒处中断 |
| previous.dkjdZI | 新增短暂中断数据 | 第1轮SAT，约2分36秒处中断 |

温度来自 CPU thermal_zone 采样，不能替代温箱设定温度或DDR器件温度；温箱批次名称仍应与实际实验记录核对。

## 新两批完整性与异常

两批均有6次SAT PASS；每轮均明确记录 `0 hardware incidents, 0 errors`。两批12份memtester均有18项ok、成功mlock及Done，未匹配到FAILURE/killed/cannot/failed。每轮总日志的BIN和TAR均Success，最终留存的解包计数为1000和100。两批均有总结束标记、runner_exit_code=0，保存的kernel日志未发现OOM、Killed process、allocation failure、Corrupted或I/O error；当前dmesg同样未匹配这些异常。

| 批次 | 测试起止（板端时钟） | 用时 | SAT Memory Copy 六轮 MB/s |
| --- | --- | --- | --- |
| 高温 previous.3GlTVI | 00:00:05~14:51:41 | 14:51:36 | 489.72、490.72、491.05、489.60、490.22、489.33 |
| 低温 previous.ZaOTYH | 00:00:05~14:50:51 | 14:50:46 | 490.00、490.87、489.99、490.29、490.76、489.97 |

高温逐轮CPU温度原值：83.49、83.49、83.49、83.49、83.49、83.49 C。
低温逐轮CPU温度原值：-20.00、-20.00、-19.47、-20.00、-19.47、-20.00 C。
高温memtester分配217、141、141、140、140、139 MiB；低温217、141、141、141、140、139 MiB。

本次仅保存检查摘录，未进行完整原始数据回传。原始串口记录：`out/serial_logs/serial-ddr-post-chamber-20261102-usb1.log`。
