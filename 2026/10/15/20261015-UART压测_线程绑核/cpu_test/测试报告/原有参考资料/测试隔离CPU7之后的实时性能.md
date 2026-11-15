1. 测试隔离CPU7之后的实时性能


其他0-6核给予80%（--cpu-load可以指定CPU负载） CPU负载
stress-ng -c 7 --io 7 --cpu-load 80 --vm 7 --vm-bytes 1024M --vm-hang 0 --timeout 7200s --metrics-brief

CPU7运行cyclictest验证实时性指标
taskset -c用于绑定cyclictest到CPU7
taskset -c 7 cyclictest -c 0 -m -t 1 -p99 -D1H -H 400 -q > result_1h_normal.txt