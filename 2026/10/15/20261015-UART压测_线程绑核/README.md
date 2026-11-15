# UART 压测与线程绑核资料

CPU 测试结果已整理到 [cpu_test](<cpu_test/README.md>)，包括 CPU7 隔离对照、线程绑核接口测试、原始日志和图片。

本目录收纳 RK3576 原理图 PDF、芯片手册、实时性测试报告与 CPU 测试资料；独立图片统一归入 image，保留原有分组以区分隔离状态和负载。此次仅整理资料，没有重新运行测试。

## 本地资料索引

- [Linux系统实时性测试报告.xlsx](<Linux系统实时性测试报告.xlsx>)
- [RK_EVB1_RK3576_LP4XD200P132SD6_.pdf](<RK_EVB1_RK3576_LP4XD200P132SD6_.pdf>)
- [Rockchip_RK3576_Datasheet_V1.5-20241216.pdf](<Rockchip_RK3576_Datasheet_V1.5-20241216.pdf>)
- [cpu_test/README.md](<cpu_test/README.md>)
- [cpu_test/测试报告/原有参考资料/Linux系统实时性测试报告.xlsx](<cpu_test/测试报告/原有参考资料/Linux系统实时性测试报告.xlsx>)
- [cpu_test/测试报告/原有参考资料/测试隔离CPU7之后的实时性能.md](<cpu_test/测试报告/原有参考资料/测试隔离CPU7之后的实时性能.md>)
- [cpu_test/线程绑核测试说明.md](<cpu_test/线程绑核测试说明.md>)
- [cpu_test/隔离CPU时延压测指南.md](<cpu_test/隔离CPU时延压测指南.md>)

## 图片

- [图片索引](<image/README.md>)

图片统一保存在本任务的 `image/`，文档与附件保留在任务目录及其资料子目录。

## 原件读取说明

以下 3 个文件检测到 `%TSD-Header` 加密标记，已保留原始字节。是否可查看取决于本机配套环境；本次未转换这些文件或提取其内嵌图片。

- [cpu_test/测试报告/原有参考资料/Linux系统实时性测试报告.xlsx](<cpu_test/测试报告/原有参考资料/Linux系统实时性测试报告.xlsx>)
- [Linux系统实时性测试报告.xlsx](<Linux系统实时性测试报告.xlsx>)
- [RK_EVB1_RK3576_LP4XD200P132SD6_.pdf](<RK_EVB1_RK3576_LP4XD200P132SD6_.pdf>)
