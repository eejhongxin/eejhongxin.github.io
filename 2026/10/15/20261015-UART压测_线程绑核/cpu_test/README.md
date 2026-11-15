# RK3576 CPU 测试资料

这里是测试资料的归档副本，Ubuntu 仓库里的原文件仍然保留。本次只整理文件，没有重新测试，也没有修改原始数据。

## 从哪里看

| 想看什么 | 打开这里 |
| --- | --- |
| CPU7 隔离组的结果和图片 | [隔离CPU7](<测试报告/RK3576_CPU测试/隔离CPU7>) |
| 不隔离、仅测量线程绑 CPU7 的结果和图片 | [不隔离CPU_测量线程绑CPU7](<测试报告/RK3576_CPU测试/不隔离CPU_测量线程绑CPU7>) |
| 线程绑核的 10 个测试用例日志 | [gtest.log](<测试报告/RK3576_CPU测试/线程绑核接口/thread_affinity_result/details/hc_gtest_thread_affinity/gtest.log>) |
| 线程绑核的运行状态 | [test-result.txt](<测试报告/RK3576_CPU测试/线程绑核接口/thread_affinity_result/details/hc_gtest_thread_affinity/test-result.txt>) |
| 线程绑核原始压缩包 | [gtest-coverage-data.tar.gz](<测试报告/RK3576_CPU测试/线程绑核接口/gtest-coverage-data.tar.gz>) |
| CPU 延迟测试怎么运行、怎么画图 | [隔离CPU时延压测指南.md](<隔离CPU时延压测指南.md>) |
| 线程绑核测试怎么编译、怎么运行 | [线程绑核测试说明.md](<线程绑核测试说明.md>) |
| 以前提供的 Excel 和测试说明 | [原有参考资料](<测试报告/原有参考资料>) |

## CPU 延迟结果怎么看

两组都将 cyclictest 测量线程绑定到 CPU7，区别在于有没有配置 CPU 隔离。压力放在 CPU0–6，不给 CPU7 额外加压力线程。

每组下面的 `idle` 是空载，`load50` 是目标负载 50%，`load80` 是目标负载 80%。负载是压力目标，不保证每个核都刚好达到该数值。

- `result_cpu7.txt`：原始延迟直方图和最小、平均、最大延迟。
- 对应图片已归入任务根目录的 `image/cpu_test/测试报告/`，见 [图片索引](<../image/README.md>)。
- `summary.tsv`、`status.txt`、`run.log`：测试时长、完成状态和过程日志。
- `cmdline.txt`、`isolated.txt`、`nohz_full.txt`：当时的启动参数和 CPU 配置。

隔离组的 `summary.tsv` 记录了 50% 和 80% 各 7200 秒；不隔离组记录了空载、50%、80% 各 7200 秒。
隔离组还包含 `idle` 数据，但该项不在本轮 `summary.tsv` 中，不要当作同一次连续运行的记录。

隔离组 `load80/without_3264us` 是剔除异常点后的辅助分析，不能替代 `load80/result_cpu7.txt` 原始结果和原图；两个版本均已保留。

## 线程绑核结果怎么看

现有 `gtest.log` 记录了 10 项通过，`test-result.txt` 记录退出码为 0。覆盖率文件收集完成不等于接口覆盖率已达验收标准。
这项验证的是绑核接口行为，不是 cyclictest 延迟，也不能单凭该日志判断当时的 CPU 隔离配置。

## 归档来源

原始资料位于 Ubuntu：`/home/jihongxin/Documents/RK3588/testcase_linux/cpu_test`。虽然路径包含 RK3588，本次对照资料按 RK3576 测试归档。

| 原目录 | 归档目录 |
| --- | --- |
| `night_isolated_20210101_120637_yKP5bA` | `测试报告/RK3576_CPU测试/隔离CPU7` |
| `night_normal_20210101_162014_h5qa2v` | `测试报告/RK3576_CPU测试/不隔离CPU_测量线程绑CPU7` |
| `thread_affinity_result` 和 `gtest-coverage-data.tar.gz` | `测试报告/RK3576_CPU测试/线程绑核接口` |

原目录名中的 `20210101` 是板端记录的时间，不代表真实测试日期。空的 `.total`、`isolated_cpu7_idle` 目录未复制。

`原有参考资料/Linux系统实时性测试报告.xlsx` 是原先提供的参考文件，不是本次新制作的结果汇总表。
使用说明中的 `/home/...` 路径是 Ubuntu 源码或工作目录，不是 Windows 目录；本归档不包含完整源码、工具链及覆盖率构建目录。
