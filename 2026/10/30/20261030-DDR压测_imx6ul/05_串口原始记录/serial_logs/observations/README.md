# 复位与喂狗观察记录

以下文件从 out 外层移入，内容保持原样，用于追溯当时的故障排查，不参与测试运行或打包。

- `ddr-idle-reset-observation.log`：空闲时读取 uptime 的观察记录。
- `ddr-intermittent-observation.log` 及 `.summary.json`：未临时喂狗的间歇压测，记录到 1 次复位。
- `ddr-feed-intermittent-observation.log` 及 `.summary.json`：第一次喂狗尝试及启动问题；feeding_requested 不等于喂狗成功，不作为有效喂狗对照。
- `ddr-feed-intermittent-observation-2.log` 及 `.summary.json`：后续喂狗观察期间，4 次短测退出码为 0，未记录到复位；结束时保留了临时喂狗进程。

这些是历史短时观察，不代替后来完整的八轮测试，也不能单凭对照确认所有复位原因。
JSON 的 log 字段及原日志内的绝对路径仍保留采集时旧位置，当前文件位置以本目录为准。
