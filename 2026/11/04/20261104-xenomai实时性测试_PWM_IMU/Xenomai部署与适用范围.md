# RK3588 Xenomai 部署与适用范围

本文面向当前 RK3588 工程：`/home/jihongxin/Documents/RK3588`。
源码与配置核对结果：Linux 6.1.141、Xenomai 3.2.5、Cobalt 双内核、ARM64/SMP。
源码配置、镜像生成、板上启动和实时性能验证是不同阶段，需要分别确认。

## 1. 部署组成

Xenomai Cobalt 部署需要配套的内核和用户态环境：

- 内核：Dovetail 中断管线与 Cobalt 实时内核。
- rootfs：libcobalt、需要的 API 库、测试程序及业务程序。
- 应用：使用 Xenomai 头文件和链接参数编译，关键操作需要对应的 Cobalt 接口或实时驱动。

当前 RK3588 的常规集成流程涉及 kernel 和 rootfs；本次查阅的指南没有要求 RK3588 为此修改 U-Boot。指南里的 RT BL31、RT DDR 要求分别针对 RK3568、RK3506，不能直接套用。

## 2. 内核与用户态准备

### 2.1 内核

新环境按内核版本选择 `sdk/docs/Patches/Real-Time-Performance/XENOMAI/` 下匹配的补丁，并核对开发指南末尾的基准提交。不能只看内核版本号就强行应用补丁。

以 6.1.141 为例，补丁目录为：

```text
sdk/docs/Patches/Real-Time-Performance/XENOMAI/kernel-6.1/6.1.141/
```

官方流程为：应用 Dovetail 补丁 → 准备 Xenomai 源码 → 执行 `prepare-kernel.sh` → 配置并编译内核。
在已应用补丁、已集成 Cobalt 的当前工程中，不重复执行打补丁。

准备全新内核树时，ARM64 集成命令为：

```sh
cd /home/jihongxin/Documents/RK3588/sdk/kernel
../buildroot/output/rockchip_rk3588/build/xenomai-3.2.5/scripts/prepare-kernel.sh --arch=arm64
```

确认配置包含：

```text
CONFIG_IRQ_PIPELINE=y
CONFIG_DOVETAIL=y
CONFIG_XENOMAI=y
```

随后使用本板的内核配置、DTS 和既有镜像构建流程生成 boot.img。文档中的 EVB 示例不能直接替代当前 OSB 板的 DTS。修改 `.config` 后应同步到工程使用的 defconfig/config fragment，避免下次构建被覆盖。

### 2.2 Buildroot 用户态

当前配置：

```text
BR2_PACKAGE_XENOMAI=y
BR2_PACKAGE_XENOMAI_LATEST_VERSION=y
BR2_PACKAGE_XENOMAI_VERSION="3.2.5"
BR2_PACKAGE_XENOMAI_COBALT=y
BR2_PACKAGE_XENOMAI_ENABLE_SMP=y
BR2_PACKAGE_XENOMAI_TESTSUITE=y
BR2_PACKAGE_XENOMAI_ADDITIONAL_CONF_OPTS="--enable-demo"
```

新环境需要在 Buildroot 配置中启用并保存这些选项，然后编译。当前输出配置已经启用，可在工作目录执行包构建：

```sh
cd /home/jihongxin/Documents/RK3588
make -C sdk/buildroot O="$PWD/sdk/buildroot/output/rockchip_rk3588" xenomai
```

若修改过已完成构建的包源码，需要使用相应 rebuild 目标；普通包构建可能因为 stamp 已存在而不重新编译。

## 3. 迁入当前 rootfs 并打包

本工程使用独立的 `rootfs/`。Buildroot 安装结果在 `sdk/buildroot/output/rockchip_rk3588/target/`，不会因为编译包就自动进入独立 rootfs。

在开发机工作目录执行：

```sh
cd /home/jihongxin/Documents/RK3588
XENOMAI_DIR=sdk/buildroot/output/rockchip_rk3588/build/xenomai-3.2.5
bash "$XENOMAI_DIR/migrate-xenomai.sh" --check
bash "$XENOMAI_DIR/migrate-xenomai.sh"
bash rootfs/mkfs-rootfs.sh
```

这里的 `migrate-xenomai.sh` 是当前工程定制的迁移工具，不是 Xenomai 上游或 Rockchip 通用部署步骤。新环境需要单独保存和恢复它；Buildroot 清理 output 后，其中自定义源码和脚本也可能丢失。

脚本按清单迁移运行库和程序，清除编译机 RPATH，并自动调用新增独立 demo 的 Makefile/install。`--check` 也可能构建 demo，但不会更新独立 rootfs。已有不同内容的同名文件会导致迁移停止，应核对后按相应程序的更新流程处理。

缺少 patchelf 时，先执行：

```sh
make -C sdk/buildroot O="$PWD/sdk/buildroot/output/rockchip_rk3588" host-patchelf
```

迁移还要求 rootfs 已存在 `xenomai` 组。不要整棵覆盖 Buildroot target 到当前 rootfs，以免替换原有 libc、加载器和系统配置。

完成后按当前板卡既有烧录流程部署匹配的 boot.img 和 rootfs.img。仅更新开发机文件或完成打包，不等于板子已更新。分区、镜像路径和烧录方式应以本板实际配置为准。

## 4. 板上确认

```sh
uname -a
ls /proc/xenomai
dmesg | grep -Ei 'xenomai|cobalt|dovetail'
/usr/demo/hello
```

hello 应显示 `Hello Xenomai Cobalt!`、线程查询成功，并检查工作线程模式。再进行周期唤醒测试：

```sh
/usr/demo/hello --latency 60000 1000
/usr/demo/hello_linux --latency 60000 1000
```

正常约 60 秒；两个程序先后运行，保持负载和频率条件一致。需要固定 CPU 时，对两者使用相同的 taskset 设置。检查 Primary samples、secondary switch delta 等诊断，不能只凭链接 libcobalt 就认定业务全程在 Cobalt 执行。

Xenomai cyclictest 为 `/usr/demo/cyclictest`；原 Linux rt-tests 为 `/usr/bin/cyclictest`，二者不能混用来解释结果。

## 5. 当前 Xenomai 可迁移的功能

当前工程已集成 Xenomai 3.2.5 Cobalt 实时内核。应用可通过 POSIX 或 Alchemy 接口使用其功能。以下“可迁移”表示当前源码、配置和用户库具备相应支持；只有标注“板上已验证”的项目，才表示本次已有实际运行证据，不把接口存在等同于业务迁移验收。

| 功能 | 可迁移的业务内容 | 代表接口 |
| --- | --- | --- |
| 实时线程与优先级调度 | 创建实时工作线程，以 FIFO 优先级执行控制、采样、计算任务 | `pthread_create`、`pthread_setschedparam` |
| 周期唤醒与精确计时 | 周期任务、按绝对时间等待、测量时间间隔 | `clock_nanosleep`、`clock_gettime` |
| 互斥锁 | 多线程共享数据保护；按支持的属性配置优先级继承等行为 | `pthread_mutex_*` |
| 信号量 | 线程通知、资源计数、阻塞等待与超时 | `sem_init`、`sem_post`、`sem_wait`、`sem_timedwait` |
| 条件变量 | 等待数据或状态变化，唤醒一个或多个线程 | `pthread_cond_wait`、`pthread_cond_signal`、`pthread_cond_broadcast` |
| POSIX 消息队列 | 线程或进程之间发送、接收消息，支持优先级和超时 | `mq_open`、`mq_send`、`mq_receive` |
| POSIX 定时器 | 定时或周期到期通知 | `timer_create`、`timer_settime`、`timer_gettime` |
| Alchemy 任务、事件、队列和内存堆 | 使用 Xenomai 专用 API 组织周期任务、事件通知、消息传递及共享内存管理 | `rt_task_*`、`rt_event_*`、`rt_queue_*`、`rt_heap_*` |
| 实时状态诊断 | 查询线程状态、统计 Cobalt 系统调用和切回 Linux 的次数 | Cobalt 线程统计接口、`/proc/xenomai` |

因此，当前可以优先迁移的是：**实时线程、周期调度、线程间同步、消息通信，以及不依赖普通 Linux 阻塞服务的控制/计算逻辑。** 迁移时需要确认所用函数及属性受支持，再用真实业务负载验证；不能承诺任意 POSIX 程序只改 Makefile 就迁移成功。

UART、SPI、GPIO、CAN 等硬件收发不列入当前已完成的 Cobalt 实时适配范围。当前 UART/SPI 仍使用 Linux 驱动；普通文件和 Linux 网络服务也不能据此认定为 Cobalt 实时功能。需要它们全程由实时内核处理时，应另外核对并适配对应驱动。

## 6. 当前总线测试的解释

现有 hello 测试观察周期唤醒时延；IMU SPI 测试观察同步传输调用前后的耗时。线程唤醒更及时，不代表总线读操作更快。

SPI 仍有物理传输耗时，例如 15 字节在 500 kHz 下，仅移位就约 240 μs，另加驱动、片选等开销。Xenomai 不会直接缩短这个物理时间。

Linux SPI 驱动支持设备树 `rockchip,rt`，提高消息处理线程的 Linux 实时优先级；效果取决于实际传输路径，需要实测。Dovetail 补丁虽带 SPI OOB 框架，但当前 spi-rockchip 没有对应 OOB 实现。

普通 UART 可先优化 Linux 接收链路。Rockchip 串口延迟排障文档中的实时线程、IRQ 和 workqueue 优化属于 Linux 侧优化，不能作为已有 RK3588 Cobalt UART 驱动的证明。

## 7. 资料位置

相对工程根目录：

- `sdk/docs/Patches/Real-Time-Performance/Rockchip_Develop_Guide_Linux_RealTime_CN.md`：部署、补丁版本和基准提交。
- 同目录 `Rockchip_Developer_Guide_Linux_RealTime_Performance_Test_Report_CN.pdf` 第 8～9 页：RK3588 Linux 5.10 的 cyclictest 数据，不是当前 6.1.141 总线读取性能保证。
- 同目录 `Rockchip_Trouble_Shooting_Linux_Real-Time_Performance_CN.pdf` 第 4～18 页：RK3588 Linux 串口接收延迟排查。
- `sdk/docs/cn/Common/SPI/Rockchip_Developer_Guide_Linux_SPI_CN.pdf` 第 7 页：`rockchip,rt`。
- `rootfs/usr/share/xenomai/`：当前 hello、SPI 测试方法及 Cobalt 接口支持索引。

官方文档部分版本表和示例较旧，RK3588 示例使用 Linux 5.10；当前 Linux 6.1.141 的说明同时依据本地源码、配置和补丁目录，不将旧报告等同于当前板卡验收结果。
