set encoding utf8
set terminal png size 1400,900 enhanced font ",12"
set output "/home/jihongxin/Documents/RK3588/testcase_linux/cpu_test/night_isolated_20210101_120637_yKP5bA/load80/without_3264us/cyclictest_hist_cpu7_without_3264us.png"
set title "Cyclictest Latency Histogram (CPU7 isolated, 80% load)\nDerived view: one 3264 us outlier excluded"
set xlabel "Latency (us)"
set ylabel "Sample count"
set logscale y
set xrange [0:78]
set yrange [0.8:*]
set grid ytics
set label 1 "Filtered max: 62 us | Original max: 3264 us" at graph 0.98, graph 0.88 right front font ",10"
set label 2 "Retained: 7,199,996 samples | Excluded: 1 sample | Original data unchanged" at graph 0.98, graph 0.83 right front font ",10"
plot "/home/jihongxin/Documents/RK3588/testcase_linux/cpu_test/night_isolated_20210101_120637_yKP5bA/load80/without_3264us/result_cpu7.txt" using 1:2 title "CPU7 (filtered)" with histeps lw 2
