# 脚本与板端路径

本目录分成两组，均供阅读；实际部署使用 `../01_安装包/ddr-p5-full.tar.gz`，其中包含完整的 ARM 工具、动态库和素材。

- `新统一入口/`：`run.sh`、`boot/install.sh`、`boot/prepare.sh`、`README.md`。这是新增的主机验证入口，尚未部署到板子。
- `板端已验证脚本/`：此前三板现场版本及其配套测试脚本的快照，保留为来源证据，没有用新入口覆盖。

## 新统一入口

支持 `/mnt/ddr_work/ddr_p5` 或 `/mnt/ddr_work/full/ddr_p5` 两个安装位置。先确认 `/mnt` 挂载到实际块设备再解压，执行 `sh run.sh 6` 会准备挂载、复用或启动喂狗、校验包和板端 checkupdate、归档旧日志，再后台运行原测试脚本。`status` 查看状态，`progress` 打印一次进度。

日志目录为 `/mnt/ddr_work/ddr_all_test`；已有日志移到 `/mnt/ddr_work/ddr_backup/previous.XXXXXX/ddr_all_test`。普通启动不会修改 rootfs。`autostart 6` 才安装 rcS 钩子并记录当前包的准确路径，启动关系为 `rcS → /etc/init.d/ddr_boot_prepare.sh → 所选包/run.sh --boot`。`manual` 只关闭未来开机测试，不停止当前测试或喂狗。

## 此前板端现场版本

| 文件 | 此前三板检查时实际路径 | 来源 |
| --- | --- | --- |
| ddr_test.sh、ddr_progress.sh、ddr_mem_usage.sh | /mnt/ddr_work/full/ddr_p5/ | 当前 full 包；测试和进度脚本与三板现场 SHA256 一致 |
| wtd_feed.sh | /mnt/ddr_work/ddr_p5/wtd_feed.sh（启动脚本优先选择的路径） | 当前 full/tools 包内相同脚本；此副本不是重新读取板端文件 |
| check_update/check_update_bin/check_update.sh | /mnt/ddr_work/full/ddr_p5/check_update/check_update_bin/ | full 包已适配版本，调用既有 /data/sbin/checkupdate |
| check_update/check_update_tar/check_update.sh | /mnt/ddr_work/full/ddr_p5/check_update/check_update_tar/ | 当前 full 包 |
| ddr_boot_prepare.sh | /etc/init.d/ddr_boot_prepare.sh | 主机文件与三板现场 SHA256 一致 |
| ddr_autostart.sh | /mnt/ddr_work/ddr_autostart.sh；boot_setup 内应相同 | 从已有 usb0 串口完整原文重建，并匹配三板已记录 SHA256 |

旧板端自启脚本 SHA256：`8d35eebd8437f69e59935eb9c5d154776eefdeabffe1707390716643dfa31076`，3889 字节。此次没有访问温箱中的板子。

旧启动关系：`/etc/inittab → rcS → /etc/init.d/ddr_boot_prepare.sh → 挂载 /mnt、启动/确认 wtd_feed.sh → ddr_autostart.sh → sh ddr_test.sh -c 6`。

轮数保存在 `/mnt/ddr_work/ddr_autostart.count`；上次现场确认三板为 6，此处未重新读取板子。历史八轮数据目录里的 `.count` 是当时的 8，不能当作当前配置。更改轮数不会改变已启动进程的参数。

板端已部署自启版本在每次新启动前建立 `ddr_backup/previous.XXXXXX/`，归档旧 `ddr_all_test` 并保存辅助信息；每次重启从第1轮重新开始，不会续跑上次轮次。手动直接运行 ddr_test.sh 则没有这个自动归档步骤。

板端已验证部署版与旧主机源码、旧 boot 包中的自启版本不同，见 [版本说明](<../01_安装包/版本说明.md>)。历史源码保存在 `../07_构建与来源/project_snapshot/`，新统一入口的阅读副本单独存放。
