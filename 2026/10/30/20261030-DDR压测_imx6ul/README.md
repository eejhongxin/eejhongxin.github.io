# i.MX6UL / P5 DDR压测资料归档

整理日期：2026-10-30（北京时间）。源工程：`/home/jihongxin/Documents/imx6ul`。
原始资料目录：`D:\Documents\任务文档记录\20261030-DDR压测_imx6ul`。

## 文件位置

| 目录 | 内容 |
| --- | --- |
| [01_安装包](<01_安装包/版本说明.md>) | 当前统一 ddr-p5-full.tar.gz 及其 SHA256；解压后使用 run.sh |
| [02_脚本](<02_脚本/README.md>) | 新统一入口的可读副本，以及此前板端已验证脚本，两组分别保存 |
| [03_测试数据](<03_测试数据/README.md>) | 仅保留三板常温8轮、高温6轮、低温6轮，共9份完整数据 |
| [04_检查与分析](<04_检查与分析/整理核对结果.md>) | 结果、OOM、开机自启、备份清点等检查报告，八轮速率CSV和包版本审计 |
| 05_串口原始记录 | 现场检查、部署、备份和复位观察原始记录，含历史连接异常的乱码 |
| 06_参考资料 | DDR配置/压测方法原始文档、DRAM指导PDF、FORESEE数据手册、P5引脚/图纸图片 |
| [07_构建与来源](<07_构建与来源/README.md>) | 主机源码快照、适配前原脚本、构建输入、历史安装包、Git版本和P5工作区差异 |

## 写文档时使用哪批数据

当前数据只保留 `03_测试数据/ddr-saved-post-chamber-20261102/` 中9份完整记录：三板各常温8轮、高温6轮、低温6轮，全部60轮SAT和memtester通过日志核查，保存内核日志未发现OOM。按芯片ID和roomtemp/hightemp/lowtemp分类。重复常温目录、早期5轮历史数据、未完成批次及当前活动快照已按要求清理；旧检查报告仍保留用于追溯。

三板常温8轮SAT Memory Copy总平均487.86 MB/s；该值是内存拷贝吞吐，不是纯读取速率。八轮参数：每外层轮SAT 3600秒、8个copy线程，memtester 1轮，BIN解包1000次、TAR解包100次。两类内存测试均保留原脚本“当前空闲内存减10MiB”的计算；每轮分配量不是固定值。

三板身份以芯片ID区分，串口号可能随插拔变化：usb0=0x483699d4、usb1=0x3c3699d4、usb2=0x0c3599d4。

## 版本和校验

当前交付改为一个统一 full 包。板上先确认 `/mnt` 已挂载到 `/dev/mmcblk1p7`，在 `/mnt/ddr_work` 解压，再执行 `sh ddr_p5/run.sh 6`；完整步骤见包内 README。入口会准备挂载、喂狗、校验、归档旧日志并后台启动测试，显式执行 `autostart 6` 才安装开机自启。

此次在主机增加统一入口并重新打包，原 DDR 测试逻辑和 ARM 工具保留；新入口尚未部署到任何板子，没有操作温箱中的板子。旧 full/tools/boot/progress 和 bundles 清单移到 `07_构建与来源/历史安装包/`，其中旧 full 改名 `ddr-p5-full-before-unified.tar.gz`。旧 boot 的主机版本与三板已验证部署版本不同，两者仍分别保留，见 [版本说明](<01_安装包/版本说明.md>)。历史数据、检查报告、Git状态快照保留各自生成时的含义。

原有 `文件来源清单.csv` 与 [原始归档校验清单](<原始归档_SHA256SUMS>) 保留最初交付时的来源及路径记录；其中图片的当前位置见 [图片索引](<image/README.md>)。本次整理重新生成 `SHA256SUMS`，记录当前归档文件的字节校验值（不含清单自身）。原始数据目录内部的校验文件保留原样。Linux/Git Bash 可在本目录执行 `sha256sum -c SHA256SUMS`。

原先为空的 [操作手册](<操作手册.md>) 已根据当前统一入口说明补齐；完整参数和环境要求仍以 [统一入口说明](<02_脚本/新统一入口/README.md>) 为准。没有复制交叉工具链、完整SDK、未核实固件镜像及编译中间产物。

## 本地资料索引

- [01_安装包/版本说明.md](<01_安装包/版本说明.md>)
- [02_脚本/README.md](<02_脚本/README.md>)
- [02_脚本/新统一入口/README.md](<02_脚本/新统一入口/README.md>)
- [02_脚本/板端已验证脚本/README.md](<02_脚本/板端已验证脚本/README.md>)
- [03_测试数据/README.md](<03_测试数据/README.md>)
- [03_测试数据/ddr-saved-post-chamber-20261102/README.md](<03_测试数据/ddr-saved-post-chamber-20261102/README.md>)
- [04_检查与分析/checkupdate-board-diagnosis.md](<04_检查与分析/checkupdate-board-diagnosis.md>)
- [04_检查与分析/ddr-8round-cma0-review.md](<04_检查与分析/ddr-8round-cma0-review.md>)
- [04_检查与分析/ddr-backup-review.md](<04_检查与分析/ddr-backup-review.md>)
- [04_检查与分析/ddr-oom/README.md](<04_检查与分析/ddr-oom/README.md>)
- [04_检查与分析/ddr-post-chamber-20261102-ftdi.md](<04_检查与分析/ddr-post-chamber-20261102-ftdi.md>)
- [04_检查与分析/ddr-post-chamber-20261102-usb0.md](<04_检查与分析/ddr-post-chamber-20261102-usb0.md>)
- [04_检查与分析/ddr-post-chamber-20261102-usb1.md](<04_检查与分析/ddr-post-chamber-20261102-usb1.md>)
- [04_检查与分析/ddr-post-chamber-review-20261102.md](<04_检查与分析/ddr-post-chamber-review-20261102.md>)
- [04_检查与分析/ddr-pre-chamber-review.md](<04_检查与分析/ddr-pre-chamber-review.md>)
- [04_检查与分析/ddr-temperature-results.md](<04_检查与分析/ddr-temperature-results.md>)
- [04_检查与分析/ddr-x6-integration-result.md](<04_检查与分析/ddr-x6-integration-result.md>)
- [04_检查与分析/ddr-x6-two-board-deployment.md](<04_检查与分析/ddr-x6-two-board-deployment.md>)
- [04_检查与分析/x6-fixture-board-verification.md](<04_检查与分析/x6-fixture-board-verification.md>)
- [04_检查与分析/整理核对结果.md](<04_检查与分析/整理核对结果.md>)
- [05_串口原始记录/serial_logs/observations/README.md](<05_串口原始记录/serial_logs/observations/README.md>)
- [06_参考资料/FORESEE_F60C1A0002-M6_Datasheet.pdf](<06_参考资料/FORESEE_F60C1A0002-M6_Datasheet.pdf>)
- [06_参考资料/IMX6UL DDR3配置测试步骤.doc](<06_参考资料/IMX6UL DDR3配置测试步骤.doc>)
- [06_参考资料/P5.pdf](<06_参考资料/P5.pdf>)
- [06_参考资料/嵌入式驱动平台DDR压力测试工具及方法介绍(1).doc](<06_参考资料/嵌入式驱动平台DDR压力测试工具及方法介绍(1).doc>)
- [06_参考资料/飞思卡尔i.MX6平台DRAM接口高阶应用指导-DDR3篇.pdf](<06_参考资料/飞思卡尔i.MX6平台DRAM接口高阶应用指导-DDR3篇.pdf>)
- [07_构建与来源/README.md](<07_构建与来源/README.md>)
- [操作手册.md](<操作手册.md>)

## 图片

- [图片索引](<image/README.md>)

图片统一保存在本任务的 `image/`，文档与附件保留在任务目录及其资料子目录。

## 原件读取说明

以下 6 个文件检测到 `%TSD-Header` 加密标记，已保留原始字节。是否可查看取决于本机配套环境；本次未转换这些文件或提取其内嵌图片。

- [04_检查与分析/八轮速率明细.csv](<04_检查与分析/八轮速率明细.csv>)
- [06_参考资料/FORESEE_F60C1A0002-M6_Datasheet.pdf](<06_参考资料/FORESEE_F60C1A0002-M6_Datasheet.pdf>)
- [06_参考资料/IMX6UL DDR3配置测试步骤.doc](<06_参考资料/IMX6UL DDR3配置测试步骤.doc>)
- [06_参考资料/P5.pdf](<06_参考资料/P5.pdf>)
- [06_参考资料/嵌入式驱动平台DDR压力测试工具及方法介绍(1).doc](<06_参考资料/嵌入式驱动平台DDR压力测试工具及方法介绍(1).doc>)
- [文件来源清单.csv](<文件来源清单.csv>)
