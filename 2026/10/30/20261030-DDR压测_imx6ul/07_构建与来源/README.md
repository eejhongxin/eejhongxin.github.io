# 构建和来源快照

`project_snapshot/` 按工程相对路径保存主机脚本源码、P5适配脚本、部分DDR初始化配置及主机串口工具；`适配前原始脚本/` 只作逻辑比较，不是当前板子的运行脚本。Git提交、分支、工作区状态见 repository-state.json，P5已跟踪文件的差异见 p5-worktree.patch；这些 Git 记录是原整理时的快照，不自动代表新增统一入口后的提交或工作区状态。

当前统一包构建入口为工程 `tools/build-ddr-unified.py`，运行入口源码为 `tools/ddr-run.sh`，开机安装与准备源码为 `tools/ddr-unified-install.sh`、`tools/ddr-unified-boot.sh`，说明为 `tools/DDR-P5-UNIFIED.md`。构建器使用已校验的原 full 包中的 ARM 二进制和素材，叠加统一入口并重建校验清单，不重新编译工具。新入口的阅读副本见 `../02_脚本/新统一入口/`。

这是本次压测相关文件的归档，不是完整SDK或完整可独立构建的工程。旧 `build-ddr-p5.sh`、`build-ddr-boot.sh`、`build-ddr-progress-patch.sh` 保留用于追溯，不作为当前统一包交付入口；旧完整构建仍依赖原工程rootfs、kernel、素材路径及 `/opt/imx6` SDK。构建输入保留上游SAT源码压缩包、主机lrzsz安装包和旧补丁所需基线清单；没有复制769MiB交叉工具链及无用编译中间文件。

`历史安装包/` 保存旧 tools、boot、progress 压缩包及 bundles 校验清单，旧 full 命名为 `ddr-p5-full-before-unified.tar.gz`。它们用于还原此前交付状态；当前只使用 `../01_安装包/ddr-p5-full.tar.gz`，无需叠加历史补丁。

`构建输入/checkupdate-board-20220528` 是先前板端工具诊断提取件，仅作版本追溯，不用于覆盖 `/data/sbin/checkupdate`。未采用的另一个checkupdate版本没有纳入。

U-Boot的imximage、P5板级代码及boot.sh是归档时工作区的源配置上下文，不代表重新核实了三块板Flash中的镜像身份。本次增加统一安装入口并在主机打包，保留原 DDR 测试逻辑，没有编译或刷写固件，也没有访问温箱中的板子。
