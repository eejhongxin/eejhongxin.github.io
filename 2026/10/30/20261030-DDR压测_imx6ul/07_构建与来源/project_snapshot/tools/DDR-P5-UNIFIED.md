# P5 DDR 压测：一个完整包、一个入口

只需要 `ddr-p5-full.tar.gz`。包内已包含 ARM 测试工具、运行库、进度显示、喂狗、BIN/TAR 素材和可选的开机自启安装脚本；不需要再安装 tools、boot 或 progress 包。

## 解压和运行

首次上传、解压之前，必须确认 `/mnt` 是 eMMC 的可读写挂载。包内脚本尚未运行时，无法防止向未挂载的 `/mnt` 写入，未挂载时这里实际属于很小的 NOR 根文件系统。

在板子 root 串口终端执行：

```sh
if ! grep -q ' /mnt ' /proc/mounts; then
    mkdir -p /mnt
    mount -t vfat -o rw /dev/mmcblk1p7 /mnt
fi
cat /proc/mounts | grep ' /mnt '
df -h /mnt
mkdir -p /mnt/ddr_work
cd /mnt/ddr_work
```

确认输出是 `/dev/mmcblk1p7 /mnt vfat rw,...`，再把完整包传到此目录。不要覆盖仍在使用的运行包；已有测试或喂狗正在使用同路径文件时，先保持原状，等测试结束后安排更新。

```sh
tar -xzf ddr-p5-full.tar.gz
sh ddr_p5/run.sh 6
```

`run.sh 6` 准备挂载、复用或启动喂狗、归档旧日志，然后后台执行 6 轮。启动确认后可以关闭串口，后台测试继续运行。入口会拒绝重复启动正在运行的测试，不会主动停止已有喂狗进程。

解压后的标准目录是 `/mnt/ddr_work/ddr_p5/`。也支持已有 `/mnt/ddr_work/full/ddr_p5/` 布局；从哪一份 `run.sh` 启动，就使用哪份包。查看状态和进度：

```sh
sh /mnt/ddr_work/ddr_p5/run.sh status
sh /mnt/ddr_work/ddr_p5/run.sh progress
```

`progress` 查看当前进度；完整实时控制台日志也可以通过 `tail -f /mnt/ddr_work/ddr_all_test/console.log` 查看。

## 可选的开机自启

普通运行不改 rootfs 或开机配置。需要每次开机自动运行 6 轮时，等当前测试结束后显式执行：

```sh
sh /mnt/ddr_work/ddr_p5/run.sh autostart 6
```

此命令安装开机挂载、喂狗和测试入口，备份原启动文件，保存当前准确包路径，并把下一次开机轮数写入 `/mnt/ddr_work/ddr_autostart.count`。它不立即启动测试，也不自动重启。安装成功后，保留整个运行包目录；下次开机重新从第 1 轮开始，不续跑中断轮次。

只取消未来的测试自启，保留当前测试和喂狗：

```sh
sh /mnt/ddr_work/ddr_p5/run.sh manual
```

## 测试内容和日志

每个外层轮次保持原测试逻辑：

- stressapptest：8 个 copy 线程、3600 秒。
- memtester：1 轮；按运行时空闲内存减 10 MiB 计算申请量。
- BIN 解包和校验：1000 次。
- TAR 解包和校验：100 次。
- CPU 温度从 P5 已确认的 `thermal_zone1` 读取。

本次日志放在 `/mnt/ddr_work/ddr_all_test/`，包含 `console.log`、`ddr_log.log`、各轮 `stressapptest_N.log` 和 `memtester_N.log`、测试前后内核快照，以及正常结束后保存的最终 BIN/TAR 计数。旧数据在新一批运行前移到 `/mnt/ddr_work/ddr_backup/previous.XXXXXX/ddr_all_test/`，不会直接覆盖；没有自动清理旧备份的规则。

`runner_exit_code=0` 或总日志有结束标记，不足以证明全部测试通过。仍需核对 SAT 的 PASS、每轮 memtester 的 Done/各项结果、BIN/TAR Success 和内核 OOM 日志。异常断电时 `/tmp` 中尚未保存的解包结果会丢失。

## 仍使用板子的系统环境

测试继续使用板上既有 `/data/sbin/checkupdate`，完整包不替换它；系统的 ARM glibc 运行环境也仍需可用。BIN/TAR 文件只是解包校验输入，测试不执行其中的固件安装脚本。

入口不会自动修改 U-Boot 的 CMA 设置。三板上次已确认 `cma=0`；新板应检查 `cat /proc/cmdline`。历史 `cma=96M` 环境曾发生 memtester OOM，关闭 CMA 后的八轮测试未发现 OOM，但不能保证所有后续负载都不会发生。

本次整合只在主机侧验证打包、脚本语法和隔离测试，未操作温箱中的三块板；上板运行表现仍需实际验证。

## 包内目录

```text
ddr_p5/
├── run.sh                  统一入口
├── ddr_test.sh             原测试逻辑
├── ddr_progress.sh         进度显示
├── ddr_mem_usage.sh        内存采样工具
├── wtd_feed.sh             喂狗工具
├── boot/install.sh         可选自启安装
├── boot/prepare.sh         开机准备模板
├── bin/、libexec/、lib/     ARM工具及运行库
├── check_update/           BIN、TAR素材和测试脚本
├── licenses/               许可证
├── TOOLS.txt
└── SHA256SUMS              包内文件校验清单
```

解压后在包目录执行 `sha256sum -c SHA256SUMS` 可以核对文件。主机侧重新生成同名完整包：

```sh
python3 tools/build-ddr-unified.py
```

构建器复用已核验完整包中的 ARM 工具和素材，缓存为 `out/ddr-build/unified-base-full.tar.gz`，不重新编译工具。它校验基线和所有包内文件，再加入当前入口、启动脚本并生成新的清单，最后原子替换同名 `out/ddr-p5-full.tar.gz`，附带生成压缩包 `.sha256` 校验文件。
