# CPU7 测试命令：空载、50%、80%（每组 2 小时）

压力放在 CPU0–6，测量线程绑定 CPU7。50% 和 80% 是压力目标，不保证每个核都刚好达到这个比例。
测试时不要同时运行其他 stress-ng、cyclictest 或线程绑核程序。

## 1. 上传脚本（Ubuntu 主机）

```bash
cd /home/jihongxin/Documents/RK3588/testcase_linux/cpu_test
scp run_cpu7_night.sh root@192.168.253.1:/tmp/
```

## 2. 开始测试（板子）

下面两种按当前板子配置选一种，**只执行一条，不要重复启动**。

已经隔离 CPU7，跑 0 → 50% → 80%，每组 2 小时：
```bash
nohup sh /tmp/run_cpu7_night.sh isolated 0 50 80 > /tmp/cpu7-night.log 2>&1 < /dev/null &
```

没有隔离 CPU，只把测量线程绑到 CPU7：
```bash
nohup sh /tmp/run_cpu7_night.sh normal 0 50 80 > /tmp/cpu7-night.log 2>&1 < /dev/null &
```

这样放到后台运行，关闭终端也能继续。三组共约 6 小时。
隔离配置需要你自己修改并重启；脚本只检查，不会帮你开启或取消隔离。

想换测试内容，只替换命令里的 `50 80`：

| 要测什么 | 换成 |
| --- | --- |
| 只测空载 | `0` |
| 只测 50% | `50` |
| 只测 80% | `80` |
| 空载后测 50% | `0 50` |
| 50% 后测 80% | `50 80` |
| 三组都测 | `0 50 80` |

`0` 表示不额外启动压力，不是系统 CPU 占用严格为零。
每次都会新建结果目录，只跑你选择的组，不会自动续跑。

## 3. 看进度（板子）

```bash
tail -f /tmp/cpu7-night.log
```

每分钟更新一次。按 Ctrl+C 只退出查看，后台测试继续。
看到 `All requested cases completed.` 和 `Run ended: COMPLETED`，表示本轮已跑完，不代表延时一定达标。

需要停止测试时，把“进程号”换成启动命令显示的数字：
```bash
kill -TERM 进程号
```

## 4. 下载结果（Ubuntu 主机）

日志第一行会显示结果目录。把下面的 `night_实际目录` 换成那个目录名：
```bash
cd /home/jihongxin/Documents/RK3588/testcase_linux/cpu_test
scp -r root@192.168.253.1:/userdata/cpu7-test/night_实际目录 .
```

隔离组目录以 `night_isolated_` 开头，不隔离组以 `night_normal_` 开头。
`run.log` 是过程日志；各组的 `result_cpu7.txt` 是延时结果。

## 5. 画图（Ubuntu 主机）

先进入刚下载的目录，再按实际跑过的组画图：
```bash
cd night_实际目录
bash ../back_cyclictest.sh load50/result_cpu7.txt
bash ../back_cyclictest.sh load80/result_cpu7.txt
```

如果还测了空载：
```bash
bash ../back_cyclictest.sh idle/result_cpu7.txt
```

归档图片位于任务根目录 `image/cpu_test/测试报告/RK3576_CPU测试/` 下，按隔离状态及 `idle`、`load50`、`load80` 分组，名字是 `cyclictest_hist_cpu7.png`；见 [图片索引](<../image/README.md>)。

## SSH 提示旧密钥冲突时

先确认 IP 是自己的板子，且确实重新烧录或更换了密钥，再在 Ubuntu 执行：
```bash
ssh-keygen -R 192.168.253.1
```

然后重新执行 scp，核对新指纹后连接。scp 不需要加 `-O`。
