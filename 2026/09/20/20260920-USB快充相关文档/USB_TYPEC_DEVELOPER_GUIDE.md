# RV1126BJ X16：USB / Type-C 开发流程与接口说明


## 一、四个彼此独立的概念

| 概念 | 管理者 | 典型状态 
| --- | --- | --- 
| Type-C 连接和供电角色 | HUSB311、TCPCI、TCPM | CC 对端为 Rd/Rp；本端 Source/Sink | 
| USB 数据角色 | TCPM、USB role switch、DWC3 | Host/Device | 
| 充电协商 | HUSB311、TCPM、充电管理链路 | PD 请求、协商电压和电流 | 
| USB 数据连接 | Host 侧 xHCI/USB core；Device 侧 gadget/configfs | U 盘枚举；`CONNECTED`/`CONFIGURED` | 

注意：板卡连接 PC 时通常同时是 **Sink（受电方）+ Device（数据设备）**；连接 U 盘时通常是 **Source（供电方）+ Host（数据主机）**。


## 二、插 U 盘：CC → Host → OTG 供电 → 枚举

```text
Type-C 对端呈现 Rd
  → HUSB311 中断 husb311_irq()
  → tcpci_irq() 上报 CC 变化
  → TCPM 状态机稳定为 SRC_ATTACHED
  → tcpm_src_attach()
      → tcpm_set_roles(... SOURCE, HOST ...)
          → tcpm_mux_set() → usb_role_switch_set_role(HOST)
          → dwc3_usb_role_switch_set() → DWC3 进入 Host 模式
      → tcpm_set_vbus(port, true)
          → tcpci_set_vbus() → husb311_set_vbus()
          → I²C 对 SGM41574 寄存器读改写，开启 OTG
  → xHCI 注册并枚举外接设备
  → 若设备是 U 盘：usb-storage → SCSI 磁盘/分区 → 文件系统挂载
```

主要源码入口：`kernel/drivers/usb/typec/tcpm/tcpci_husb311.c` 的 `husb311_irq`、`husb311_set_vbus`；`kernel/drivers/usb/typec/tcpm/tcpci.c` 的 `tcpci_irq`、`tcpci_set_vbus`；`kernel/drivers/usb/typec/tcpm/tcpm.c` 的 `tcpm_src_attach`、`tcpm_set_roles`、`tcpm_set_vbus`；`kernel/drivers/usb/dwc3/drd.c` 的 `dwc3_usb_role_switch_set`。

函数指针的绑定关系是：HUSB311 probe 执行 `chip->data.set_vbus = husb311_set_vbus`；`tcpci_register_port()` 执行 `tcpci->tcpc.set_vbus = tcpci_set_vbus`；TCPM 调用 `port->tcpc->set_vbus(...)`，TCPCI 再调用 `tcpci->data->set_vbus(...)`。因此全文搜索直接调用 `husb311_set_vbus(...)` 不足以找到插入时的入口。TCPM 的初始化、拔出和角色交换也可能请求关/开 VBUS；不能假定只有插入才调用回调。

## 三、接 PC：CC → Device → USB 控制请求 → configfs

```text
PC 侧呈现 Rp，提供 VBUS
  → HUSB311/TCPCI 上报 CC 和供电状态
  → TCPM 稳定为 SNK_ATTACHED
  → tcpm_snk_attach() → tcpm_set_roles(... SINK, DEVICE ...)
  → USB role switch 请求 DWC3 进入 Device 模式
  → PC 发来 USB 控制请求
  → configfs android_setup(): gi->connected = 1，调度 android_work()
  → android_work(): hc_connect = 1，发送 USB_STATE=CONNECTED
  → PC 完成 SET_CONFIGURATION 且 cdev->config 成立
  → USB_STATE=CONFIGURED
```

`gi->connected` 是 gadget 软件状态，**不是** CC、VBUS 或物理插入检测寄存器。`android_setup()` 第一次收到控制请求时置 1；`configfs_composite_disconnect()` 在断开时置 0；`android_work()` 异步比较它和 `gi->sw_connected`，再更新 `hc_connect` 并发送事件。因异步调度和可能的状态合并，不能把 `hc_connect` 的更新时间戳当成物理插入时间。`CONNECTED` 与 `CONFIGURED` 不相同；即使已 `CONNECTED`，PC 也可能尚未完成配置。

对应代码：`kernel/drivers/usb/gadget/configfs.c` 的 `android_setup`、`android_work`、`configfs_composite_disconnect`。无 USB 数据交互的纯供电适配器通常不会让 gadget 进入 `CONNECTED`；但 `hc_connect=0` 也可能表示 gadget 未绑定、正在连接或已断开；`hc_connect=1` 表示对端有 Host 数据交互，无法凭此严格断言对端物理设备是“PC”。

## 四、PD 充电与电压字段的来源

PD 协商时板卡是 Sink、充电器是 Source。Source 在 CC 线上发 `Source_Capabilities` 消息，列出它实际支持的 PDO；板卡不能只凭设备树声明就要求对端输出 9 V/12 V。接收消息的具体路径：

```text
HUSB311 收到 PD 消息，置 TCPC_ALERT_RX_STATUS，触发中断
  → tcpci_husb311.c: husb311_irq() → tcpci.c: tcpci_irq()
  → 读 TCPC_RX_BYTE_CNT、TCPC_RX_HDR、TCPC_RX_DATA 寄存器
  → 清 RX_STATUS 告警 → tcpm_pd_receive()
  → TCPM 工作队列执行 tcpm_pd_rx_handler()
  → tcpm_pd_data_request() 的 PD_DATA_SOURCE_CAP 分支
  → 将 PDO 保存到 port->source_caps，转到 SNK_NEGOTIATE_CAPABILITIES
  → tcpm_pd_build_request() 比较 source_caps 和本端 snk_pdo
  → tcpm_pd_send_request() 发送 Request
  → 接收 Accept、PS_RDY，更新 TCPM 内部电压/电流限制并进入 SNK_READY
```

源码入口分别是 `kernel/drivers/usb/typec/tcpm/tcpci_husb311.c` 的 `husb311_irq`、`kernel/drivers/usb/typec/tcpm/tcpci.c` 的 `tcpci_irq`，以及 `kernel/drivers/usb/typec/tcpm/tcpm.c` 的 `tcpm_pd_receive`、`tcpm_pd_rx_handler`、`tcpm_pd_data_request`、`tcpm_pd_send_request`。`tcpci_set_pd_rx()` 写 TCPC 的 `RX_DETECT` 寄存器使能 PD 消息接收；TCPCI 初始化时通过 `ALERT_MASK` 使能 RX 告警。PD 消息走的是 HUSB311/TCPCI 的收发寄存器和中断，不是通过 SGM41574 的 OTG 寄存器收取。

软件配置有三层：设备树 `kernel/arch/arm64/boot/dts/rockchip/chcnav-rtk-site20.dtsi` 的 `usb-c-connector` 配置 `power-role = "dual"`、`sink-pdos`（当前声明 5/9/12 V，每档 3 A）和 `source-pdos`；内核需要启用 TCPM、TCPCI、HUSB311 驱动并保持 PD 未被 `pd-disable` 禁用；驱动还需要初始化 HUSB311 的滤波/DRP 等寄存器。
`kernel/drivers/usb/typec/tcpm/tcpci_husb311.c` 的 `slow_charge` 属性通过 `tcpm_update_sink_capabilities()` 切换 Sink 能力：慢充只声明一个 5 V PDO，常规模式声明 5/9/12 V PDO；已连接时可触发重新协商。当前 site20/X16 设备树未设置 `slow-charge-en`，驱动初始化默认选择常规模式。该设置仅改变协商范围，不是给 SGM41574 写入目标输入电压；最终档位受对端 PDO 和状态机结果约束。

