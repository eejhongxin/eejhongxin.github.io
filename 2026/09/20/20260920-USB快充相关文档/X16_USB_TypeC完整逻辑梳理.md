# X16 USB / Type-C 完整逻辑梳理

本文基于以下两份已有资料和当前 SDK 源码重新整理：

- [USB_TYPEC_DEVELOPER_GUIDE.md](<USB_TYPEC_DEVELOPER_GUIDE.md>)
- [SITE20 RV1126B USB虚拟网卡配置过程（Windows.txt](<SITE20 RV1126B USB虚拟网卡配置过程（Windows.txt>)
- SDK：`/home/jihongxin/Documents/rv1126/sdk`
- X16 内核设备树：`sdk/kernel/arch/arm64/boot/dts/rockchip/chcnav-rtk-x16.dts`
- X16 继承的公共配置：`sdk/kernel/arch/arm64/boot/dts/rockchip/chcnav-rtk-site20.dtsi`

本文把代码能确认的事实、根据原理图得到的结论以及尚需板测的内容分开说明。

## 1. 先区分五个不同概念

| 概念 | 负责模块 | X16 中的含义 |
| --- | --- | --- |
| Type-C 连接检测 | HUSB311、TCPCI、TCPM | 通过 CC1/CC2 判断插入、方向和对端 Rp/Rd |
| 供电角色 | TCPM、HUSB311、SGM41574 | Source 表示板卡向外供电；Sink 表示板卡从外部受电 |
| USB 数据角色 | TCPM、USB role-switch、DWC3 | Host 枚举 U 盘；Device 被 PC 枚举 |
| USB Gadget 功能 | configfs、RNDIS、ACM 等 | Device 模式下向 PC 呈现虚拟网卡、虚拟串口等功能 |
| PD 协商 | HUSB311、TCPCI、TCPM | 在 CC 线上协商输入电压和电流，不负责 USB D+/D- 数据枚举 |

典型组合如下：

- 插 U 盘：板卡通常是 `Source + Host`。
- 接 PC：板卡通常是 `Sink + Device`。
- 接 PD 充电器：板卡是 `Sink`，但对端没有 USB 数据通信时，Gadget 不会进入 `CONNECTED/CONFIGURED`。

不能把 Source/Sink 与 Host/Device 当成完全相同的概念，也不能把“检测到 VBUS”直接当成“PC 已经识别虚拟网卡”。

## 2. 硬件与设备树关系

### 2.1 HUSB311

HUSB311 位于 I2C4，地址 `0x4e`，中断脚为 GPIO6_A6。它负责：

- 检测 CC1/CC2 状态和插头方向；
- 收发 USB PD 报文；
- 向 Linux TCPM 状态机上报 CC、VBUS、PD 收发等事件；
- 接收 TCPM 的角色和 VBUS 控制请求。

设备树入口位于 `chcnav-rtk-site20.dtsi` 的 `i2c4/husb311@4e`。

### 2.2 SGM41574 与 OTG VBUS

SGM41574 地址为 `0x6b`。当前 Linux 没有把它注册为一个完整的专用 charger 驱动，而是由 HUSB311 驱动在需要 Host/Source 供电时直接通过 I2C 修改以下配置：

- `REG0x10[2:0] = 000`：开启 OTG 前关闭看门狗，避免约 40 秒后复位；
- `REG0x12[6] = 1`：开启 `EN_OTG`；
- `REG0x12[6] = 0`：关闭 `EN_OTG`。

对应代码为 `tcpci_husb311.c:husb311_set_vbus()`，参数来自设备树的 `otg-i2c-*` 和 `otg-pre-on-*` 属性。

这条路径的含义是让充电芯片进入 OTG 升压/反向供电模式。软件写寄存器成功并不等于接口一定已经稳定输出 5 V；实际电压、纹波和带载能力仍需在 Type-C VBUS 上测量。

U-Boot 的 site20 板级初始化还会先清除 `REG0x12[6]`，保证启动初期默认关闭 OTG 输出。代码位于外层仓库 `rv1126/uboot/board/rockchip/evb_rv1126b/rtk_site20.c:charger_ic_init()`。

### 2.3 GPIO6_B3：OTG/CHARGE_SET 数据开关

X16 设备树把 GPIO6_B3 配置为 `Otg_Charge_Set`，应用接口为：

```text
/sys/class/leds/Otg_Charge_Set/brightness
```

它控制原理图中 USB 模拟开关 U6 的 `S` 选择脚，只负责选择 USB D+/D- 数据通路，不是 SGM41574 的 OTG 供电使能。

```bash
echo 0 > /sys/class/leds/Otg_Charge_Set/brightness
echo 1 > /sys/class/leds/Otg_Charge_Set/brightness
```

根据 U6 真值表：`S=0` 选择 D1，`S=1` 选择 D2。结合当前原理图网络名，D1 为 `OTG_DP/DM`，D2 为 `USB_DP_2/DM_2`，公共端为 SoC 的 `USB_1_DP/DM`。最终哪个物理插座对应“U盘”和“Type-C/PD”，应以整机原理图和实际板测为最终依据。

当前代码中没有发现 TCPM 在 Host/Device 角色切换时自动修改 GPIO6_B3。它由 `gpio-leds` 导出，设备树默认 `off`，因此上电后默认为低电平。若产品要求不同场景自动切换数据通路，需要另行定义高低电平与业务场景的对应关系和切换时序，再增加联动逻辑。

### 2.4 GPIO5_D7：OTG_ID

X16 把 GPIO5_D7 配置为低有效输入 `Otg_Id`：

```text
/sys/class/misc/gpio-misc/Otg_Id/value
```

当前代码只导出该输入，没有发现它参与 TCPM 或 DWC3 自动角色决策。Type-C 口的实际 Host/Device 决策来自 HUSB311 的 CC 检测，而不是这个 GPIO。

## 3. 板卡作为主设备：插入 U 盘

这里的“主设备”包含两个同时发生的角色：

- 供电角色：板卡为 Source，给 U 盘提供 VBUS；
- 数据角色：板卡为 Host，由 xHCI 枚举 U 盘。

本节描述的是 Linux 已启动后识别、挂载 U 盘。如果“U盘启动”指让 BootROM/U-Boot 从 U 盘加载系统，则属于另一条启动链路；当前设备树和本文分析不能证明该能力已经实现。

### 3.1 完整代码调用链

```text
U 盘/转接线在 CC 上呈现 Rd
  ↓
HUSB311 产生低电平中断
  ↓
tcpci_husb311.c: husb311_irq()
  ↓
tcpci.c: tcpci_irq()
  ├─ CC_STATUS → tcpm_cc_change()
  └─ POWER_STATUS → tcpm_vbus_change()
  ↓
tcpm.c 状态机进入 Attached.SRC
  ↓
tcpm_src_attach()
  ├─ tcpm_set_roles(... TYPEC_SOURCE, TYPEC_HOST ...)
  │    └─ tcpm_mux_set()
  │         └─ usb_role_switch_set_role(USB_ROLE_HOST)
  │              └─ dwc3_usb_role_switch_set()
  │                   └─ DWC3 切换为 Host
  └─ tcpm_set_vbus(true)
       └─ tcpci_set_vbus(source=true, sink=false)
            └─ husb311_set_vbus(on=true)
                 ├─ I2C: SGM41574 REG0x10 关闭 watchdog
                 └─ I2C: SGM41574 REG0x12[6] = 1
  ↓
VBUS 输出约 5 V，xHCI 检测并枚举 USB 设备
  ↓
usb-storage → SCSI → /dev/sdX → /dev/sdX1 → 挂载文件系统
```

`source-pdos` 当前声明的是固定 5 V、最大 3 A。它是 Type-C/PD 能力声明，实际输出还受 SGM41574 配置、硬件限流和电池状态限制。

### 3.2 U 盘拔出

CC 断开后 TCPM 执行 detach/reset 流程：

- USB role-switch 离开 Host；
- `tcpm_set_vbus(false)` 最终使 `husb311_set_vbus(false)` 清除 `REG0x12[6]`；
- xHCI/USB core 移除设备；
- 存储设备节点消失。

拔 U 盘前仍应先卸载文件系统，避免数据损坏：

```bash
sync
umount /mnt/usb
```

### 3.3 主设备模式验证

```bash
cat /sys/class/typec/port0/power_role 2>/dev/null
cat /sys/class/typec/port0/data_role 2>/dev/null
cat /sys/kernel/debug/usb/21500000.usb/mode
dmesg -w
lsusb
lsblk
```

期望看到 `source`、`host`，以及 USB 新设备、SCSI 磁盘和分区日志。还应使用万用表在 VBUS 对 GND 测量约 5 V；仅看到 `REG0x12[6]` 写入成功不能替代电压测量。

## 4. 板卡作为从设备：连接 Windows PC

此时通常是：

- 板卡从 PC 的 VBUS 受电，因此供电角色为 Sink；
- 板卡被 PC 枚举，因此数据角色为 Device；
- Linux Gadget 决定向 PC 暴露虚拟网卡、虚拟串口或其他功能。

### 4.1 Type-C 到 DWC3 Device 的链路

```text
PC Type-C 口呈现 Rp 并提供 VBUS
  ↓
HUSB311 中断 → tcpci_irq()
  ↓
TCPM 状态机进入 Attached.SNK
  ↓
tcpm_snk_attach()
  ↓
tcpm_set_roles(... TYPEC_SINK, TYPEC_DEVICE ...)
  ↓
usb_role_switch_set_role(USB_ROLE_DEVICE)
  ↓
dwc3_usb_role_switch_set()
  ↓
DWC3 切换到 Device/UDC 模式
```

设备树设置了 `dr_mode = "otg"`、`usb-role-switch`，并通过 graph endpoint 将 HUSB311 connector 与 DWC3 role switch 连接起来。

### 4.2 Gadget 不是 DWC3 自动创建的

DWC3 进入 Device 模式只提供 UDC 控制器。虚拟网卡和虚拟串口必须由应用层通过 configfs 创建并绑定到 UDC。

SDK 的通用管理脚本是：

```text
device/rockchip/common/overlays/rootfs/usb-gadget/usr/bin/usb-gadget
```

其基本流程为：

```text
读取 /etc/profile.d/usb-gadget.sh 中的 USB_FUNCS
  ↓
挂载 configfs
  ↓
创建 /sys/kernel/config/usb_gadget/rockchip
  ↓
写入 VID/PID、manufacturer、product、serialnumber
  ↓
按 USB_FUNCS 创建 functions/rndis.0、functions/acm.0 等实例
  ↓
将函数软链接到 configs/b.1
  ↓
把 /sys/class/udc 下的控制器名写入 UDC
  ↓
PC 开始枚举复合 USB Gadget
```

内核配置已经启用 `CONFIG_USB_CONFIGFS`、`CONFIG_USB_CONFIGFS_RNDIS`、`CONFIG_USB_CONFIGFS_ACM`。这只表示内核具备功能，不代表当前根文件系统一定已经把 `rndis` 和 `acm` 加入 `USB_FUNCS`。

板上必须检查：

```bash
cat /etc/profile.d/usb-gadget.sh 2>/dev/null
cat /var/run/usb-gadget/funcs 2>/dev/null
find /sys/kernel/config/usb_gadget -maxdepth 3 -type d
cat /sys/kernel/config/usb_gadget/rockchip/UDC 2>/dev/null
ls /sys/class/udc
```

### 4.3 PC 插入识别状态

PC 开始发送 USB 控制请求后：

```text
configfs.c: android_setup()
  → gi->connected = 1
  → schedule_work(android_work)
  → 发送 USB_STATE=CONNECTED
  → hc_connect = 1

PC 发送 SET_CONFIGURATION 且配置生效
  → android_work()
  → 发送 USB_STATE=CONFIGURED

断开
  → configfs_composite_disconnect()
  → USB_STATE=DISCONNECTED
  → hc_connect = 0
```

`CONNECTED` 表示 PC 已经开始控制传输；`CONFIGURED` 才表示 PC 已完成 USB 配置。`hc_connect=1` 不能作为 CC 物理插入时间，也不能严格证明对端一定是 Windows PC。

建议检查：

```bash
cat /sys/class/udc/*/state
udevadm monitor --kernel --property 2>/dev/null
dmesg -w
```

## 5. 虚拟网卡 RNDIS

### 5.1 创建过程

当 `USB_FUNCS` 包含 `rndis` 时，usb-gadget 脚本创建：

```text
/sys/kernel/config/usb_gadget/rockchip/functions/rndis.0
```

绑定 UDC 并被 Windows 枚举后，板端出现 `usb0`；Windows 设备管理器中出现 RNDIS/USB Ethernet 设备。`usb0` 的 IP 不是内核自动固定配置的，需要启动脚本、网络配置文件或人工命令设置。

已有资料使用的地址为：

- 板卡：`192.168.253.1/24`
- Windows：`192.168.253.2/24`

板卡设置：

```bash
ip link show usb0
ip link set usb0 up
ip addr flush dev usb0
ip addr add 192.168.253.1/24 dev usb0
ip addr show usb0
```

Windows 设置静态地址 `192.168.253.2`、掩码 `255.255.255.0`，随后双方互相 `ping`。

### 5.2 找不到 usb0 时的检查顺序

```bash
# 1. DWC3 是否为 Device
cat /sys/kernel/debug/usb/21500000.usb/mode

# 2. RNDIS function 是否创建
find /sys/kernel/config/usb_gadget -type d -name 'rndis*'

# 3. Gadget 是否绑定 UDC
cat /sys/kernel/config/usb_gadget/rockchip/UDC

# 4. 网卡是否出现
ip link show

# 5. PC 是否完成配置
cat /sys/class/udc/*/state
```

只有调试时才建议临时执行 `echo device > .../mode`；正常产品逻辑应由 Type-C/TCPM role-switch 自动切换，手工强制可能掩盖 CC 或角色切换问题。

## 6. 虚拟串口 ACM

当 `USB_FUNCS` 包含 `acm` 时，configfs 创建 `functions/acm.0`。绑定成功后：

- 板卡侧出现 `/dev/ttyGS0`；
- Windows 侧出现一个 USB Serial/COM 端口；
- 两端通过该字符设备传输数据。

板端验证：

```bash
find /sys/kernel/config/usb_gadget -type d -name 'acm*'
ls -l /dev/ttyGS*
stty -F /dev/ttyGS0 115200
echo 'hello from X16' > /dev/ttyGS0
```

Windows 可使用串口工具打开对应 COM 口进行收发测试。

必须纠正一个容易混淆的点：

```bash
fw_setenv kerneldebug yes
```

只会让 U-Boot 修改 FIQ debugger 和控制台相关设备树，影响调试串口 `/dev/ttyFIQ0`、启动日志和 quiet 状态；它不会创建 USB ACM Gadget，也不会生成 `/dev/ttyGS0`。USB 虚拟串口是否存在取决于 configfs 中是否创建 `acm.*` 并绑定 UDC。

## 7. PD 充电流程

### 7.1 PD 协商链路

连接 PD 充电器时，板卡为 Sink，充电器为 Source：

```text
充电器发送 Source_Capabilities
  ↓
HUSB311 置 TCPC_ALERT_RX_STATUS 并触发中断
  ↓
husb311_irq() → tcpci_irq()
  ↓
读取 RX_BYTE_CNT、RX_HDR、RX_DATA
  ↓
tcpm_pd_receive()
  ↓
tcpm_pd_rx_handler()
  ↓
tcpm_pd_data_request(PD_DATA_SOURCE_CAP)
  ↓
保存对端 source_caps
  ↓
SNK_NEGOTIATE_CAPABILITIES
  ↓
tcpm_pd_build_request() 比较对端能力和本端 sink-pdos
  ↓
tcpm_pd_send_request() 发送 Request
  ↓
接收 Accept、PS_RDY
  ↓
更新 TCPM 的协商电压/电流并进入 SNK_READY
```

设备树中本端 Sink 能力声明为：

- 5 V / 3 A；
- 9 V / 3 A；
- 12 V / 3 A。

这表示板卡允许协商这些档位，不表示任意充电器都会输出 9 V 或 12 V。最终结果由双方 PDO 的交集和 TCPM 策略决定。

### 7.2 慢充接口

HUSB311 驱动提供 `slow_charge` 属性。写 `1` 时把 Sink 能力缩减为一个 5 V PDO；写 `0` 时恢复设备树的 5/9/12 V PDO，并可能触发重新协商。

实际 sysfs 路径取决于 I2C 设备命名，可查找：

```bash
find /sys/bus/i2c/devices -name slow_charge -print
```

该接口只修改 PD 协商能力，不直接向 SGM41574 写“充电电压”。

### 7.3 如何读取协商结果

TCPM 注册的 power_supply 名称以 `tcpm-source-psy-` 开头：

```bash
for d in /sys/class/power_supply/tcpm-source-psy-*; do
    echo "[$d]"
    cat "$d/online" 2>/dev/null
    cat "$d/usb_type" 2>/dev/null
    cat "$d/voltage_now" 2>/dev/null
    cat "$d/current_max" 2>/dev/null
done
```

`voltage_now` 单位为微伏，`current_max` 单位为微安。例如 `9000000` 表示 TCPM 软件状态为 9 V。这里是协议状态机维护的协商值，并不是 ADC 对输入端的实时实测值。

### 7.4 当前充电控制边界

当前源码能确认：

- HUSB311/TCPM 完成 Type-C 和 PD 协商；
- HUSB311 驱动直接控制 SGM41574 的 OTG 输出使能；
- U-Boot 启动时关闭 SGM41574 的 OTG 模式。

当前源码没有找到完整的 Linux SGM41574 charger 驱动节点，因此以下内容不能仅从现有代码断言：

- 9 V/12 V 输入后的 SGM41574 输入限流如何动态设置；
- 实际电池充电电流、充电阶段和终止条件；
- 热保护、NTC 和故障状态如何反馈给 Linux；
- PD 协商档位与充电芯片输入参数是否还有其他应用层联动。

这些部分需要结合 SGM41574 数据手册、完整原理图、U-Boot 初始化和板上寄存器/电压电流测试继续确认。

## 8. 三种场景对照

| 场景 | CC/PD | 供电角色 | 数据角色 | VBUS 来源 | Linux 数据功能 |
| --- | --- | --- | --- | --- | --- |
| 插 U 盘 | 对端呈现 Rd | Source | Host | SGM41574 OTG 输出 | xHCI + usb-storage |
| 接 Windows PC | 对端呈现 Rp | Sink | Device | PC 提供 VBUS | configfs + RNDIS/ACM |
| 接 PD 充电器 | Source Capabilities | Sink | 通常无有效数据枚举 | 充电器协商后提供 5/9/12 V | TCPM PD；通常无 RNDIS/ACM 连接 |

GPIO6_B3 的 USB 数据开关与 SGM41574 的 VBUS 开关是两条独立控制路径：前者选 D+/D-，后者决定板卡是否作为 Source 向外供电。

## 9. 推荐的板上验证顺序

### 9.1 基础配置

```bash
cat /proc/device-tree/model
cat /sys/class/leds/Otg_Charge_Set/brightness
cat /sys/class/misc/gpio-misc/Otg_Id/value 2>/dev/null
ls /sys/class/typec
ls /sys/class/udc
```

X16 的 model 应为：

```text
CHCNAV X16 (RV1126B site20)
```

### 9.2 U 盘测试

1. 开启 `dmesg -w`；
2. 按硬件要求设置 GPIO6_B3；
3. 插入 U 盘；
4. 检查 Type-C 的 `source/host`；
5. 测量 VBUS；
6. 检查 `lsusb`、`lsblk` 和 `/dev/sdX1`；
7. 挂载、读写、同步、卸载；
8. 拔出后确认 VBUS 关闭和设备移除。

### 9.3 PC 虚拟网卡/串口测试

1. 确认 GPIO6_B3 选择到实际 Type-C 数据路径；
2. 确认 DWC3 自动进入 Device；
3. 确认 configfs 的 `rndis.0`、`acm.0` 已创建；
4. 确认 Gadget 已绑定 UDC；
5. 确认 UDC 状态从 `not attached` 到 `powered/default/addressed/configured`；
6. 确认板端出现 `usb0`、`/dev/ttyGS0`；
7. 确认 Windows 出现 RNDIS 网卡和 COM 口；
8. 测试 ping 和双向串口收发。

### 9.4 PD 充电测试

1. 插入已知支持 5/9/12 V 的 PD 充电器；
2. 查看 Type-C power role 为 Sink；
3. 查看 TCPM power_supply 的 `online`、`usb_type`、`voltage_now`、`current_max`；
4. 使用 PD 分析仪或万用表确认实际 VBUS；
5. 切换 `slow_charge`，确认重新协商到 5 V；
6. 同时记录电池充电电流和 SGM41574 关键寄存器，验证充电链路。

## 10. 当前实现中需要继续确认的事项

1. GPIO6_B3 的高低电平与 X16 两个实际 USB 数据入口的最终对应关系。
2. GPIO6_B3 是否应随 TCPM Host/Device 状态自动切换；目前没有自动联动。
3. 产品根文件系统实际设置的 `USB_FUNCS` 是否同时包含 `rndis acm`。
4. Windows 是否需要额外 RNDIS/串口驱动，以及最终 VID/PID。
5. SGM41574 在 Sink/充电模式下的完整配置者、限流策略和故障处理。
6. `Otg_Id` 是否只是供应用读取，还是后续还需要参与非 Type-C 接口的角色选择。

在上述事项确认前，不应把“角色切换成功”“PD 协商成功”“VBUS 实测合格”“Windows Gadget 配置完成”视为同一个结果。
