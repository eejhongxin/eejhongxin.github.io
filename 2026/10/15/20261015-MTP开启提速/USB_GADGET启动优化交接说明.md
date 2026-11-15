# RK3576 USB Gadget 改动说明

## 1. 涉及文件和提交

以下路径相对于开发工程顶层；运行在板端时，去掉路径开头的 `rootfs`。这些是源码位置说明，当前资料目录未包含对应 rootfs 源码。

| 文件 | 修改方向 |
|---|---|
| `rootfs/usr/bin/usb-gadget` | 命令轮询、日志辅助逻辑、配置读取、功能排序、PID 计算及软链接创建优化。 |
| `rootfs/etc/init.d/S50usbdevice.sh` | 初始化运行状态目录；按实际请求执行 start/restart，不再统一执行 restart。 |
| `rootfs/etc/init.d/app_start.conf` | 将 USB 启动项（S50usbdevice.sh）移到该列表第一项。 |
| `rootfs/etc/init.d/.usb_config` | 删除默认 RNDIS 使能项，保留 ACM 和 MTP。 |

## 2. 启动链路和优化位置

```text
rcS：完成前面的系统服务、挂载和更新检查
  → app_start.conf：优先调用 USB 启动脚本
    → S50usbdevice.sh start：提交 start，而不是固定 restart
      → /usr/bin/usbdevice start（软链接到 usb-gadget）
        → 后台 usb-service 读取命令：轮询参数调整从原本的1s为 50ms
          → usb_prepare：读取配置、排序、选择 UDC、设置产品编号
          → usb_start：逐个准备功能并加入配置
            → MTP/UMS 优先准备
            → 全部功能准备后绑定 UDC
            → 电脑枚举，内核报告 CONNECTED、CONFIGURED
```

## 3. 具体改动

### 3.1 usb_service()：缩短命令文件的轮询间隔（时间优化较大）

当前源码位置：`usb-gadget` 第 1085 行，`tail` 命令在第 1117 行。

原来：

```bash
tail -f $USB_CMD_FILE | while true; do
```

现在：

```bash
tail -f -s 0.05 "$USB_CMD_FILE" | while true; do
```

启动命令先写入命令文件，再由后台服务读取。原来没有指定轮询间隔，在轮询实现下通常使用约 1 秒的默认值；现在指定 0.05 秒，降低新命令等待被读取的时间。

### 3.2 S50usbdevice.sh：首次启动不再固定执行 restart

原来收到 start 或 restart 都调用：但是restart包含stop和start两个步骤容易产生耗时

```bash
while ! /usr/bin/usbdevice restart; do
```

![image-20261009160201812](<image/image-20261009160201812.png>)

现在按调用参数传递：

```bash
while ! /usr/bin/usbdevice "$1"; do
```

结果：

- 开机调用 `start`，实际提交 `start`。
- 人工调用 `restart`，仍然提交 `restart`，没有删除重启功能。
- 新建 `usb-service` 时本身会做初始清理，因此首次启动不再额外走一次 restart 的 stop/start 流程。

### 3.3 app_start.conf：先发起 USB 启动

USB 启动项从 SSH 后面移动到列表第一项：

```text
S50usbdevice.sh         start
S40network              start
S50telnet               start
S50sshd                 start
S70vsftpd               start
```

### 3.4 内部执行优化：合并减少外部程序调用和重复操作的改动

将简单的取值、字符串处理和列表整理改用 Bash 内置操作，缓存可复用的检查结果，并避免重复执行目录操作。减少启动辅助进程和重复查找的开销

| 涉及函数及源码位置 | 原来的处理方式 | 修改后的处理方式 |
|---|---|---|
| `usb_msg()`（第 137 行，缓存初始化从第 129 行开始）、`usb_daemon_prepare()`（第 171 行） | 日志输出反复检查 `logger`，调用 `basename`、`date`，并通过 `cut /proc/self/stat` 获取进程号。 | 脚本名用 `${0##*/}` 提取并缓存；启动时只检查一次 `logger`；两处取进程号都改用 `${BASHPID:-$$}`；时间优先使用 Bash 内置 `printf`，不支持时回退到 `date`。 |
| `usb_instances()`（第 314 行） | 用 `tr` 将功能名转大写，再通过 `eval` 读取实例变量。 | 用 `${func^^}` 转大写、`${!var}` 间接读取变量。 |
| `usb_load_config()`（第 449 行）、`ums_parse()`（第 466 行） | 每次使用 `find /tmp/ /etc/ ...` 加 `head` 查找配置；每个 UMS 参数通过 `grep`、`cut` 管道提取。 | 每次先查 `/tmp`，无临时配置时复用缓存的 `/etc` 配置路径；搜索使用 `find ... -print -quit`，命中即停止。UMS 参数用 Bash `read`、正则匹配和字符串截取解析。 |
| `usb_pid()`（第 267 行） | 通过 `xargs → sort → xargs → tr` 排序并拼接功能名，生成产品编号匹配键。 | 用 Bash 数组插入排序，再用 `-` 连接功能名；下方产品编号映射表不变。这里的 PID 是 USB Product ID，不是进程号。 |
| `usb_symlink()`（第 377 行） | 每次无条件执行两次 `mkdir -p`，并调用 `dirname` 获取链接父目录。 | 目录不存在才执行 `mkdir`；用 `${link%/*}` 提取父目录并处理无斜杠、根目录等情况；链接存在仍跳过创建，路径参数加引号和 `--`。 |
| `usb_prepare()`（第 885 行） | 用 `echo`、`tr` 管道处理分隔符，并在调用排序函数时传入不需要的输入管道。 | 用 `${USB_FUNCS//,/ }` 将逗号转空格，用 `${USB_FUNCS// /_}` 生成配置名称，并直接调用 `usb_funcs_sort()`。 |

### 3.5 usb_funcs_sort()：优先 MTP/UMS，取消外部排序管道

当前源码位置：第 862 行。

原来多次调用 `usb_funcs_grep()` 做排序和筛选，按 `rndis → uac → uvc → ntb → ums → mtp → acm → 其他 → adb` 的分组顺序组织功能。

中间版本先改成只排序去重一次，再用数组分组。当前最终版本进一步改成纯 Bash 处理：

1. 拆分功能列表并去重。
2. 有 MTP 时放在第一。
3. 有 UMS 时放在 MTP 后；只有 UMS 时，UMS 为第一。
4. 其他功能保留输入顺序，不再强制按原分组顺序排列。

例如：

```text
输入：rndis acm ums mtp acm
输出：mtp ums rndis acm
```

### 3.6 .usb_config：默认关闭 RNDIS

删除 `usb_rndis_en`，当前内容为：

```text
usb_acm_en
usb_mtp_en
```

