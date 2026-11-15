# RK3576 uMTPrd 异步上传：源码、编译与验证

本文对应 `uMTP-Responder-versioned` 中的 MTP 上传优化。方向是 **PC → 板卡**，主要优化对象是用户态 `/usr/bin/umtprd`，不是 MCU 固件。本项目另有一项先前做过的 DWC3 TRB 环改动；调整本文新增的队列深度和读缓冲本身不要求再次编译 kernel。本文命令在 RK3576 开发主机执行，标明“板端”的命令除外。

## 1. 代码与运行位置

| 位置 | 职责 |
| --- | --- |
| `uMTP-Responder-versioned/` | 带 Git 提交记录的 uMTPrd 源码；此次编译应从这里取源码。 |
| `rootfs/etc/umtprd/umtprd.conf` | 板端读取的配置：`usb_max_rd_buffer_size 0x20000`、`usb_async_upload 0x1`、`usb_async_upload_depth 0x3`。 |
| `rootfs/usr/bin/umtprd` | 交叉编译、strip 后放入 rootfs 树的 ARM64 可执行文件。 |
| `rootfs/scripts/mkfs-rootfs.sh` | 从 rootfs 树制作 512 MiB ext4 镜像，输出到 RK3576 目录下的 `rootfs.img`。 |
| `sdk/kernel/drivers/usb/gadget/function/f_fs.c` | 内核 FunctionFS：接受异步读请求并把 OUT 端点 USB 请求交给 UDC。此次没有在该文件中改代码。 |
| `sdk/kernel/drivers/usb/dwc3/{core.h,gadget.c,trace.h}` | 之前已提交的独立改动：TRB 环由 256 调到 512，并把相关索引和 trace 字段由 `u8` 改为 `u16`；不是当前队列深度的配置入口。 |

板端 `/etc/init.d/.usb_config` 启用 `usb_mtp_en` 后，`/usr/bin/usb-gadget` 的 `mtp_prepare()` 挂载 `/dev/usb-ffs/mtp`，启动 `/usr/bin/umtprd`。进程从 `/etc/umtprd/umtprd.conf` 读取配置，打开 `ep0` 和 OUT 端点 `ep2`；板上运行的是 rootfs 中的二进制，不会直接运行开发主机上的 `.c` 文件。

原始 rootfs 配置里 `usb_max_rd_buffer_size` 和 `read_buffer_cache_size` 都只是被 `#` 注释的示例；最初这份 uMTPrd 源码的 USB 读缓冲默认实际是 `0x2000`（8 KiB），文件读缓存默认是 `0x100000`（1 MiB），`usb_max_wr_buffer_size 0x20000` 是显式配置。原配置里不存在 `usb_async_upload` 或 `usb_async_upload_depth`；它们是本次优化引入的。曾尝试 1 MiB USB 读缓冲，后因板端 DMA 映射失败把出厂配置和源码默认读缓冲调整为 `0x20000`。

`sdk/buildroot/package/umtprd/umtprd.mk` 目前仍指向固定的上游 GitHub 版本。**直接重新执行 SDK 的 Buildroot 构建，不会自动采用此目录的源码**。下面的流程是独立编译当前目录中的源码，再把生成的二进制安装进本地 rootfs 树。这两个构建入口不要混淆。

## 2. PC 上传文件时的调用链

```text
PC 发起 MTP SendObjectInfo，随后发送 SendObject 数据
  → usb-gadget 挂载 FunctionFS 并启动 umtprd
  → umtprd.c: main_thread() 加载配置、初始化 USB；io_thread() 处理传输
  → mtp.c: mtp_incoming_packet() 从 ep2 读首包、process_in_packet() 分发
  → mtp.c: SendObjectInfo 保存文件大小/对象句柄；SendObject 调用 mtp_op_SendObject()
  → mtp_op_sendobject.c: 写入首包数据，判断能否使用异步路径
  → mtp_upload_aio.c: ep2 异步读 → 按传输顺序 write() 写入 /userdata 文件
  → 生成 MTP 响应、记录 MTP upload profile
```

主要改动如下：

- `inc/mtp.h`：在 `mtp_ctx` 增加 `usb_async_upload` 开关和 `usb_async_upload_depth` 深度。
- `inc/buildconf.h`：PC → 板卡的 USB 读缓冲默认设为 `0x20000`（128 KiB），即使没有配置覆盖也使用这个大小。
- `src/mtp_cfg.c`：解析 `usb_async_upload 0x1` 和 `usb_async_upload_depth 0x3`；异步开关未配置时默认关闭，深度未配置时默认 2，合法范围 1～4，越界则告警并保持原值。启动日志会显示深度。`usb_max_rd_buffer_size` 决定 PC → 板卡单次读取的缓冲大小。
- `src/mtp_operations/mtp_op_sendobject.c`：写入已有首包，选择异步或原双缓冲路径；汇总读写计数、耗时和错误码。只在普通 `SendObject`、大小已知且小于 `UINT32_MAX`、仍有数据、读取块大小符合条件等情况下尝试异步。`SendPartialObject` 和未知大小对象继续原有路径。
- `inc/mtp_upload_aio.h`、`src/mtp_upload_aio.c`：实现可配置深度（1～4）的 Linux AIO FunctionFS OUT 读取及统计结构。
- `tests/mtp_upload_test.c`、`tests/mtp_upload_aio_linux_test.c`：模拟异常/乱序场景，以及使用真实 Linux AIO 系统调用的宿主测试；不能代替真实板端 FunctionFS 测试。

异步路径按配置执行 `io_setup(depth)`，给 ep2 最多提交 `depth` 个 `IOCB_CMD_PREAD` 请求；通过 `io_getevents()` 收完成事件，即使完成顺序不同，也使用 `next` 按提交顺序把数据写入目标文件。写某一块时，其他 USB 读可以仍在进行，写完后复用空闲槽继续提交。每次按 `SendObjectInfo` 提供的剩余大小决定需要提交多少块，避免已知大小的文件结束后再预读下一条 MTP 命令。本地 rootfs 配置读块为 128 KiB，AIO 实现要求它是 1024 字节的整数倍；大小未知（例如 MTP 的 `0xffffffff` 哨兵）不进入这条路径。板端此前用 1 MiB 读块、深度 3 时多次看到 `swiotlb buffer is full` / `failed to map SGs`；改为 128 KiB 后用户反馈传输不再卡住，但仍需重复压测确认稳定性。

原路径主要是同步 `read_usb()` 配合写线程的双缓冲，能重叠一部分 USB 读取与文件写入，但任一时刻只有同步读取调用。新的多笔 USB 请求可同时排队，针对此前 DWC3 跟踪中反复出现的请求间空档；它并不保证所有文件都提速，也不是零拷贝。

`mtp_upload_aio_receive()` 的结果分三种：

| 结果 | 处理 |
| --- | --- |
| `MTP_UPLOAD_AIO_COMPLETE` | 剩余字节读完且写完；日志 `aio=1 aerr=0 err=0`。 |
| `MTP_UPLOAD_AIO_UNAVAILABLE` | 启动前不可用、尚未接收数据；回退到原 `read_usb()`/双缓冲路径。 |
| `MTP_UPLOAD_AIO_FAILED` | 请求已提交后发生短读、写入失败、取消等；清理请求并报告错误，**不再从同步路径重读**，以免错位或重复写入。 |

取消时会尝试 `io_cancel()`，并用 `io_destroy()` 回收 AIO 上下文。`aerr` 记录负 errno，例如 `-125` 是 `-ECANCELED`；仅凭取消日志不能断言是 PC 主动取消还是连接变化，需要结合主机和 USB 日志分析。`usb_max_packet_size 0x200` 在当前源码中传入 `mtp_ctx.max_packet_size`，用于部分 MTP 数据/ZLP 边界判断，**不决定**单次读取的 128 KiB 大小，也不直接修改端点描述符：`fill_ep_descriptor()` 分别把 FS/HS/SS bulk `wMaxPacketSize` 设置为 64/512/1024。`read_buffer_cache_size` 用于读本地文件发给 PC 的方向，不是本次 PC → 板卡上传优化开关。

### 为什么不能只把 USB 读块越调越大

之前的 3 队列 + 1 MiB 读块测试，板端抓到 `dwc3 ... swiotlb buffer is full (sz: 684032 bytes)`、`failed to map SGs`，同时传输线程等在 `read_events`（`io_getevents`），UDC 仍显示 `configured`。这里的 `full` 不等于总槽位用尽：当前内核 `IO_TLB_SEGSIZE=128`、`IO_TLB_SIZE=2048`，单段理论上限约为 256 KiB，实际还受对齐、连续槽等限制。日志中的 684032/319488/286720 字节请求超过这一边界；并发更高可能更容易触发，但仅凭这些日志还不能证明每次未枚举都是同一个原因。先用 128 KiB 做对照，再在固定深度下**一次只改读块大小**；192 KiB (`0x30000`) 只是待测候选值，256 KiB (`0x40000`) 贴着单段理论边界，不应直接当作稳定设置。

## 3. 宿主机测试

在开发主机上运行；下面的测试程序放到 `/tmp`，不会覆盖板端文件：

```bash
cd /home/jihongxin/Documents/RK3576/uMTP-Responder-versioned
cc -O2 -Iinc -pthread -o /tmp/mtp_upload_test \
  tests/mtp_upload_test.c src/logs_out.c
/tmp/mtp_upload_test

cc -O2 -Iinc -o /tmp/mtp_upload_aio_linux_test \
  tests/mtp_upload_aio_linux_test.c src/mtp_upload_aio.c
/tmp/mtp_upload_aio_linux_test
```

第一项覆盖深度 1～4 的乱序完成、运行时关闭开关、AIO 不可用时回退、首包或整块文件边界、写入失败、短读与取消；第二项验证宿主 Linux AIO 系统调用读写。若需要额外排查内存/未定义行为，可把编译选项改为 `-O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer` 后重跑；这仍不是板端测试。

本地已通过上述两项宿主测试、ASan/UBSan、ARM64 完整交叉编译、`e2fsck` 和镜像内二进制 SHA-256 一致性检查。这些验证不能代替“新版队列配置在板上长期稳定”的结论。

## 4. ARM64 交叉编译与制作 rootfs.img

本机 SDK 工具链路径如下。使用 `make -B` 是为了强制重编全部目标文件（包括使用了 `mtp_ctx` 的目标文件），防止旧 `.o` 与改过的结构体布局混用；`CONFIG_USB_SS_SUPPORT=1` 启用 SuperSpeed 描述符；`USE_SYSLOG=1` 使 profile 日志进入板端 syslog；`-static` 生成静态链接二进制。`Makefile` 用通配符收集 `src/*.c`，会自动编进新增的 `mtp_upload_aio.c`。

```bash
cd /home/jihongxin/Documents/RK3576/sdk/external/umtprd/source

make -B -j4 \
  CC=/home/jihongxin/Documents/RK3576/sdk/prebuilts/gcc/linux-x86/aarch64/gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-gcc \
  CPPFLAGS=-DCONFIG_USB_SS_SUPPORT=1 \
  USE_SYSLOG=1 \
  LDFLAGS='-lpthread -lrt -static'

/home/jihongxin/Documents/RK3576/sdk/prebuilts/gcc/linux-x86/aarch64/gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-strip \
  --strip-unneeded -o /home/jihongxin/Documents/RK3576/rootfs/usr/bin/umtprd \
  /home/jihongxin/Documents/RK3576/sdk/external/umtprd/source/umtprd
chmod 0755 /home/jihongxin/Documents/RK3576/rootfs/usr/bin/umtprd
```

打包前核对 `rootfs/etc/umtprd/umtprd.conf` 保持需要的参数；重新打包会**覆盖本地主机已有的** `rootfs.img`，不会烧录板卡：

```bash
cd /home/jihongxin/Documents/RK3576
./rootfs/scripts/mkfs-rootfs.sh rootfs

sha256sum rootfs/usr/bin/umtprd rootfs.img
debugfs -R 'cat /usr/bin/umtprd' rootfs.img 2>/dev/null | sha256sum
debugfs -R 'cat /etc/umtprd/umtprd.conf' rootfs.img 2>/dev/null | \
  grep -E '^(usb_max_rd_buffer_size|usb_async_upload)'
```

两条二进制 SHA-256 应一致。脚本会创建临时 ext4 镜像、运行 `e2fsck`、成功后替换本地镜像；`rootfs.img` 是生成物，并非 Git 自动追踪的源文件。请沿现有 Maskrom 流程烧录，**不要在板上运行时向已挂载的 rootfs 分区写镜像**。

## 5. 板端验证、性能和回退

烧录完成后在板端执行：

```bash
pidof umtprd
cat /sys/class/udc/23000000.usb/current_speed
grep -E '^(usb_max_rd_buffer_size|usb_async_upload)' /etc/umtprd/umtprd.conf
grep 'MTP upload profile' /var/log/messages | tail -n 5
sha256sum /usr/bin/umtprd
```

对同一个文件连续测试并确认内容一致。成功记录中，`wall_us` 是服务端 `SendObject` 数据阶段经过的墙钟时间，`file_bytes` 含首包，`usb_bytes` 不含首包；`r`、`w` 分别为后续 USB 读完成次数和文件写调用次数，`i` 是首包数据字节数。`p=0 aio=1 aerr=0 err=0 depth=3` 表示使用深度 3 的异步路径成功；`aio=0` 表示未走通异步路径，应同时看 `aerr`/`err` 判断回退还是失败。异步路径的 `usb_read_us` 累计的是 `io_getevents()` 等待时间，文件写和 USB 收取互相重叠，**不要把 `usb_read_us + file_write_us` 相加或与旧版同步读耗时直接比较**。

实测有一次完整约 3,953,054,005 字节上传 `wall_us=22326430`，即约 22.33 秒、约 177 MB/s（十进制），而此前相同文件约 46 秒；这是一条板端结果，不代表所有主机/文件均如此。另一次 `aerr=-125 err=1` 在约 2 GB 处取消，不能计作成功样本。观察偶发中断时保留主机端现象和板端 USB 日志。

这条约 22 秒的成功日志来自**早期版本、1 MiB 读块、深度 2**，不能用于声称目前默认的 128 KiB + 深度 3 也达到同样速度；后者尚需同文件实测并记录 `depth=` 字段。当前本地已生成的镜像 SHA-256 为 `0db4fa53a72516350bebde27b82cf439a10c0e13355ec7ae5ac2fc7d77dddc06`，镜像内 `/usr/bin/umtprd` 的 SHA-256 为 `e7ac647b9f1ad2a7db97bfa8c29d700505e9197ba56f47d9066fb4de043534ad`；每次重新编译/制镜像后应重新计算，不能把这两个值当作永久版本号。

板端可在 `/etc/umtprd/umtprd.conf` 修改 `usb_async_upload_depth 0x1`～`0x4`，或将 `usb_async_upload 0x1` 改为 `usb_async_upload 0x0` 来关闭异步。修改后重启由 `/usr/bin/usb-gadget` 管理的 MTP 服务以重新加载配置；无需重编 `umtprd` 或内核。版本首次部署仍必须替换二进制/rootfs，旧版 `umtprd` 不识别深度参数。永久改变出厂值则修改本地主机 `rootfs/etc/umtprd/umtprd.conf`、重新生成并烧录 rootfs 镜像。

### 最近一次重启后 PC 看不到 MTP：尚未结案

最近一次板端输出显示：`usb_max_rd_buffer_size 0x30000` **与** `usb_async_upload_depth 0x4` 被同时设置（所以不是单独改变读缓冲的对照实验）；板端 `/usr/bin/umtprd` SHA-256 与上述新版本一致，`pidof umtprd` 返回 `6928`，UDC 状态为 `configured`，`/etc/init.d/.usb_config` 含 `usb_mtp_en`。然而 `configs/b.1` 中 **没有 `f-ffs.mtp`、`f-acm.0` 等任何功能软链接**；`/var/log/usb-gadget.log` 中旧的 `usbdevice` 和新的 `usb-gadget` 重启请求均停在 `Run stage: mtp_prepare`，未见 `Starting instance: ffs.mtp`，MTP daemon 输出日志为空。故 `configured` 不能证明 MTP 已成功挂入 gadget；当前更直接的现象是 gadget 准备阶段没有走完，**尚不能归因于队列深度或 SWIOTLB**（后者是在传文件时出现的映射错误）。

保留现场、不要连续重启，在板端通过 Wi-Fi 检查：

```bash
ps -ef | grep -E '[u]sbdevice|[u]sb-gadget|[u]mtprd'
grep -Ei 'umtprd|Async USB upload|USB Init|Already running|error' /var/log/messages | tail -n 60
mount | grep usb-ffs
fuser -vm /dev/usb-ffs/mtp
mtp_pid=$(pidof umtprd | awk '{print $1}')
ls -l /proc/"$mtp_pid"/fd | grep usb-ffs
cat /proc/"$mtp_pid"/wchan
```

核实端点是否打开、旧 `usbdevice` 与新 `usb-gadget` 是否同时管理同一 gadget，以及 `mtp_prepare()` 是否等待 FunctionFS 就绪；确认并保存日志后，先恢复此前可工作的 `0x20000` + 深度 `0x3` 对照，仅改变一个参数时再重新测试。若改了板端配置，必须让管理 MTP 的服务重新加载，且只有当 `configs/b.1/f-ffs.mtp` 出现、PC 重新识别后才开始测传输性能。不要把失败的枚举当作读块性能数据。

