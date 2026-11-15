# uMTPrd 升级使用说明

本流程使用 SDK 中的上游源码压缩包和异步上传补丁，交叉编译 `umtprd`，将其放入本地 rootfs，最后重新制作并烧录 `rootfs.img`。

## 解压源码

建议从空的 `source` 目录开始，避免在已打补丁的源码上重复应用补丁。

```bash
cd /home/jihongxin/Documents/RK3576/sdk
mkdir -p external/umtprd/source

tar -xzf external/umtprd/download/umtprd-93cca39673ed9e8c082df3002a6bf58ab8e492ad-br1.tar.gz \
  -C external/umtprd/source \
  --strip-components=1
```

## 打包 uMTPrd 改动补丁

以下命令供补丁维护者使用。独立开发仓库目前仅保存在本地，不是普通升级流程的必需输入。

```bash
cd /home/jihongxin/Documents/RK3576/uMTP-Responder-versioned
git diff a209835..HEAD > ../sdk/external/umtprd/patches/umtprd/mtp-async-upload.patch
```

普通升级只需要 SDK 中已有的压缩包和补丁，无须运行本节命令。

## 应用补丁

先检查，再应用；补丁只需应用一次。

```bash
cd /home/jihongxin/Documents/RK3576/sdk

git apply --check --directory=external/umtprd/source \
  external/umtprd/patches/umtprd/mtp-async-upload.patch

git apply --directory=external/umtprd/source \
  external/umtprd/patches/umtprd/mtp-async-upload.patch
```

如果检查失败，先确认 `source` 是否为从原始压缩包解出的、尚未打补丁的源码。
## 交叉编译并替换本地 rootfs 文件

`make install`会自动把生成的umtprd二进制文件同步到roofs的文件夹下面

```bash
cd /home/jihongxin/Documents/RK3576/sdk/external/umtprd
make install
```

`make install` 会先交叉编译，再执行 `strip`，最终替换：

```text
/home/jihongxin/Documents/RK3576/rootfs/usr/bin/umtprd
make 
```

如果只想编译、不替换 rootfs 中的文件，运行 `make` 即可。

## 配置文件（一般默认即可）

烧录前，在开发机修改：

```text
/home/jihongxin/Documents/RK3576/rootfs/etc/umtprd/umtprd.conf
```

板卡启动后，也可以在板端修改：

```bash
vi /etc/umtprd/umtprd.conf
```

板端修改后需要重启 MTP 服务或板卡，配置才会重新加载。当前主要配置如下：

```text
usb_max_rd_buffer_size 0x20000
usb_async_upload 0x1
usb_async_upload_depth 0x3
usb_max_wr_buffer_size 0x20000
```

参数说明：

- `usb_max_rd_buffer_size`：PC 向板卡传文件时，单次 USB 读取的缓冲大小。增大不保证速度持续提升；过大可能导致传输不稳定。当前使用 `0x20000`。
- `usb_async_upload`：`1` 表示启用异步上传，`0` 表示关闭。
- `usb_async_upload_depth`：同时排队的 FunctionFS USB 读请求数，**不是线程数**。支持 `1`～`4`，未配置时默认为 `2`；当前使用 `3`。
- `usb_max_wr_buffer_size`：主要对应板卡向 PC 发送数据，不是此次 PC 向板卡上传的主要调节项。

## 生成并烧录 rootfs 镜像

```bash
cd /home/jihongxin/Documents/RK3576/rootfs
./scripts/mkfs-rootfs.sh
```

生成的镜像路径为：

```text
/home/jihongxin/Documents/RK3576/rootfs.img
```

这一步只制作开发机上的镜像，还需要使用现有烧录流程将新镜像写入板卡，板卡才会运行新版本的 `umtprd`。

## 原理说明

### 运行程序与调用关系

板卡上的 MTP 功能由启动脚本、用户态程序和内核 USB 驱动共同完成：

```text
/etc/init.d/.usb_config 启用 MTP
  → /usr/bin/usb-gadget 的 mtp_prepare()
      → 挂载 FunctionFS：/dev/usb-ffs/mtp
      → 启动 /usr/bin/umtprd
  → umtprd.c：main_thread()
      → 读取 /etc/umtprd/umtprd.conf
      → 初始化 USB gadget
      → io_thread() 循环处理 MTP 数据
  → mtp.c：mtp_incoming_packet()
      → 从 FunctionFS OUT 端点读取数据
      → process_in_packet() 按 MTP 命令分发
  → mtp_op_sendobject.c：mtp_op_SendObject()
      → 接收 PC 上传的文件内容
      → 写入板卡文件系统
  → FunctionFS / DWC3 内核驱动
      → 负责底层 USB 请求和硬件传输
```

### 原始上传路径为什么较慢

PC 上传文件时，会先通过 `SendObjectInfo` 告知文件信息，再通过 `SendObject` 发送文件内容。原始 `mtp_op_SendObject()` 在接收后续数据时，主要按以下顺序循环执行：

```text
read_usb() 从 FunctionFS OUT 端点读取一块数据
  → write() 将这块数据写入文件
  → 再次调用 read_usb() 读取下一块
```

这条路径中，当前块的文件写入与下一块 USB 读取没有主动并行排队。

### MTP提速改动

将原本的同步上传更改为异步上传，通过usb_async_upload_depth控制同时排队的USB请求数。

- `inc/buildconf.h`：将默认 USB 读缓冲调整为 `0x20000`。
- `inc/mtp.h`、`src/mtp_cfg.c`：增加 `usb_async_upload` 开关和 `usb_async_upload_depth` 队列深度配置。
- `src/mtp_operations/mtp_op_sendobject.c`：在 `SendObject` 上传路径中选择异步接收或原有路径，处理首包、传输结果和错误，并记录上传统计日志。
- `inc/mtp_upload_aio.h`、`src/mtp_upload_aio.c`：新增 FunctionFS OUT 端点的 Linux AIO 读取实现。
