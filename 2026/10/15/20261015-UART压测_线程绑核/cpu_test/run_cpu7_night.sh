#!/bin/sh
# CPU7 延迟测试：按参数顺序测量空载或 CPU0–6 的 50%、80% 负载。
# 不修改 CPU 隔离配置；记录板端实际隔离状态。
# 使用 POSIX sh，兼容板端 BusyBox；默认每组 7200 秒。

set -u

TEST_SECONDS=${TEST_SECONDS:-7200}
WARMUP_SECONDS=${WARMUP_SECONDS:-10}
COOLDOWN_SECONDS=${COOLDOWN_SECONDS:-10}
PROGRESS_SECONDS=${PROGRESS_SECONDS:-60}
OUTPUT_BASE=${OUTPUT_BASE:-/userdata/cpu7-test}
CPU7_LIB_DIR=${CPU7_LIB_DIR:-/tmp/cpu7-libs}
STRESS_PID=
CYCLIC_PID=
RUN_DIR=
CASE_DIR=
STATUS=FAILED
REQUESTED_MODE=auto

usage()
{
    printf '%s\n' \
        'Usage: sh run_cpu7_night.sh [isolated|normal|auto] [0|50|80] ...' \
        'isolated: require isolated CPUs=7; normal: require an affinity-only baseline.' \
        'auto (default): detect state; mixed/other settings are labelled custom.' \
        'normal rejects isolated/nohz_full CPUs and isolcpus/nohz_full/rcu_nocbs/irqaffinity boot options.' \
        'Default: 50 then 80, 2 hours each.' \
        'Examples: 0; 50; 80; 0 50; 50 80; 0 50 80 (idle is an alias for 0).' \
        'Only selected cases run, in argument order; no automatic resume.' \
        'Isolation configuration is not changed; actual state is recorded.' \
        'Optional: TEST_SECONDS=60 sh run_cpu7_night.sh 50 80' \
        'Results: OUTPUT_BASE (default /userdata/cpu7-test), unique night_MODE_* directory.'
}

check_mode()
{
    cpu7_isolated=$(cat /sys/devices/system/cpu/isolated) || die 'cannot read CPU isolation state'
    cpu7_nohz=
    if [ -r /sys/devices/system/cpu/nohz_full ]; then
        cpu7_nohz=$(cat /sys/devices/system/cpu/nohz_full) || die 'cannot read nohz_full state'
    fi
    # 未启用 NO_HZ_FULL 时可能显示 (null)，表示没有 full-dynticks CPU。
    [ "$cpu7_nohz" != '(null)' ] || cpu7_nohz=
    cpu7_cmdline=$(cat /proc/cmdline) || die 'cannot read kernel command line'
    cpu7_boot_options=
    for cpu7_option in $cpu7_cmdline; do
        case "$cpu7_option" in
            isolcpus=*|nohz_full=*|rcu_nocbs=*|irqaffinity=*)
                cpu7_boot_options="$cpu7_boot_options $cpu7_option" ;;
        esac
    done
    cpu7_normal=0
    if [ -z "$cpu7_isolated" ] && [ -z "$cpu7_nohz" ] && [ -z "$cpu7_boot_options" ]; then
        cpu7_normal=1
    fi
    case "$REQUESTED_MODE" in
        isolated)
            [ "$cpu7_isolated" = 7 ] || die "isolated mode requires isolated CPUs=7; actual=${cpu7_isolated:-none}. Change boot configuration and reboot first."
            TEST_MODE=isolated ;;
        normal)
            [ "$cpu7_normal" -eq 1 ] || die "normal baseline requires isolation options removed: isolated=${cpu7_isolated:-none}, nohz_full=${cpu7_nohz:-none}, boot options:${cpu7_boot_options:-none}. Change boot configuration and reboot first."
            TEST_MODE=normal ;;
        auto)
            if [ "$cpu7_isolated" = 7 ]; then
                TEST_MODE=isolated
            elif [ "$cpu7_normal" -eq 1 ]; then
                TEST_MODE=normal
            else
                TEST_MODE=custom
            fi ;;
    esac
}

log()
{
    cpu7_message="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    printf '%s\n' "$cpu7_message"
    if [ -n "$RUN_DIR" ]; then
        printf '%s\n' "$cpu7_message" >> "$RUN_DIR/run.log"
    fi
}

die()
{
    log "ERROR: $*"
    exit 1
}

check_number()
{
    case "$2" in
        ''|*[!0-9]*) die "$1 must be an integer" ;;
    esac
    [ "$2" -ge "$3" ] && [ "$2" -le 86400 ] || die "$1 must be between $3 and 86400"
}

uptime_seconds()
{
    read -r cpu7_uptime cpu7_unused < /proc/uptime
    printf '%s\n' "${cpu7_uptime%%.*}"
}

# 仅停止本脚本启动的进程，stress-ng 收到 TERM 后回收其工作进程。
stop_stress()
{
    if [ -n "$STRESS_PID" ]; then
        kill -TERM "$STRESS_PID" 2>/dev/null || :
        wait "$STRESS_PID" 2>/dev/null || :
        STRESS_PID=
    fi
}

stop_cyclic()
{
    if [ -n "$CYCLIC_PID" ]; then
        kill -TERM "$CYCLIC_PID" 2>/dev/null || :
        wait "$CYCLIC_PID" 2>/dev/null || :
        CYCLIC_PID=
    fi
}

cleanup()
{
    cpu7_exit=$?
    trap - 0 INT TERM HUP
    stop_cyclic
    stop_stress
    if [ -n "$RUN_DIR" ]; then
        if [ -n "$CASE_DIR" ] && [ "$(cat "$CASE_DIR/status.txt")" = RUNNING ]; then
            printf '%s\n' "$STATUS" > "$CASE_DIR/status.txt"
        fi
        printf '%s\n' "$STATUS" > "$RUN_DIR/status.txt"
        log "Run ended: $STATUS, exit=$cpu7_exit, results=$RUN_DIR"
    fi
    exit "$cpu7_exit"
}

interrupted()
{
    STATUS=INTERRUPTED
    log 'Interrupted; stopping this script’s test processes.'
    exit 130
}

snapshot()
{
    cat /proc/interrupts > "$CASE_DIR/interrupts_$1.txt"
    cat /proc/stat > "$CASE_DIR/proc_stat_$1.txt"
}

run_case()
{
    cpu7_load=$1
    case "$cpu7_load" in
        0) cpu7_case=idle ;;
        *) cpu7_case=load$cpu7_load ;;
    esac
    CASE_DIR=$RUN_DIR/$cpu7_case
    mkdir "$CASE_DIR" || die "cannot create $CASE_DIR"
    printf '%s\n' RUNNING > "$CASE_DIR/status.txt"
    log "START $cpu7_case: measurement CPU7, duration=${TEST_SECONDS}s"
    if [ "$cpu7_load" != 0 ]; then
        cpu7_stress_timeout=$((TEST_SECONDS + WARMUP_SECONDS + 180))
        taskset -c 0-6 stress-ng --cpu 7 --cpu-load "$cpu7_load" \
            --timeout "${cpu7_stress_timeout}s" --metrics-brief \
            > "$CASE_DIR/stress.log" 2>&1 &
        STRESS_PID=$!
        printf '%s\n' "$STRESS_PID" > "$CASE_DIR/stress.pid"
        log "Pressure CPU0-6: target=$cpu7_load%, pid=$STRESS_PID; warmup=${WARMUP_SECONDS}s"
        sleep "$WARMUP_SECONDS"
        if ! kill -0 "$STRESS_PID" 2>/dev/null; then
            wait "$STRESS_PID"
            cpu7_stress_rc=$?
            STRESS_PID=
            printf 'FAILED: stress exited during warmup, exit=%s\n' "$cpu7_stress_rc" \
                > "$CASE_DIR/status.txt"
            die "stress-ng failed during warmup; see $CASE_DIR/stress.log"
        fi
    fi
    snapshot before
    cpu7_start=$(uptime_seconds)
    cpu7_next_progress=$PROGRESS_SECONDS
    cyclictest -m -a 7 -t 1 -p 80 -i 1000 -D "${TEST_SECONDS}s" -H 10000 -q \
        > "$CASE_DIR/result_cpu7.txt" 2>&1 &
    CYCLIC_PID=$!
    printf '%s\n' "$CYCLIC_PID" > "$CASE_DIR/cyclictest.pid"
    log "cyclictest started: pid=$CYCLIC_PID"
    cpu7_reason=
    while kill -0 "$CYCLIC_PID" 2>/dev/null; do
        if [ -n "$STRESS_PID" ] && ! kill -0 "$STRESS_PID" 2>/dev/null; then
            cpu7_reason='pressure stopped before measurement finished'
            break
        fi
        cpu7_elapsed=$(($(uptime_seconds) - cpu7_start))
        if [ "$cpu7_elapsed" -ge "$cpu7_next_progress" ]; then
            log "RUNNING $cpu7_case: ${cpu7_elapsed}/${TEST_SECONDS}s, cyclictest pid=$CYCLIC_PID"
            cpu7_next_progress=$((cpu7_elapsed + PROGRESS_SECONDS))
        fi
        if [ "$cpu7_elapsed" -gt "$((TEST_SECONDS + 120))" ]; then
            cpu7_reason='cyclictest exceeded duration by more than 120s'
            break
        fi
        sleep 1
    done
    if [ -n "$cpu7_reason" ]; then
        stop_cyclic
        cpu7_cyclic_rc=1
    else
        wait "$CYCLIC_PID"
        cpu7_cyclic_rc=$?
        CYCLIC_PID=
    fi
    cpu7_elapsed=$(($(uptime_seconds) - cpu7_start))
    snapshot after
    # 正常情况下压力仍然运行；提前结束不能当成完整负载测试。
    if [ -n "$STRESS_PID" ] && ! kill -0 "$STRESS_PID" 2>/dev/null; then
        cpu7_reason='pressure exited unexpectedly'
    fi
    stop_stress
    printf '%s\n' "$cpu7_cyclic_rc" > "$CASE_DIR/exit_code.txt"
    if [ "$cpu7_cyclic_rc" -ne 0 ] || [ -n "$cpu7_reason" ] || \
        [ "$cpu7_elapsed" -lt "$TEST_SECONDS" ] || \
        ! grep -q '^# Max Latencies:' "$CASE_DIR/result_cpu7.txt"; then
        printf 'FAILED: cyclictest_exit=%s, elapsed=%ss, reason=%s\n' \
            "$cpu7_cyclic_rc" "$cpu7_elapsed" "$cpu7_reason" > "$CASE_DIR/status.txt"
        die "$cpu7_case incomplete; see $CASE_DIR/status.txt and result_cpu7.txt"
    fi
    printf '%s\n' COMPLETED > "$CASE_DIR/status.txt"
    log "DONE $cpu7_case: elapsed=${cpu7_elapsed}s, exit=0"
    grep -E '^# (Min Latencies|Avg Latencies|Max Latencies|Histogram Overflows):' \
        "$CASE_DIR/result_cpu7.txt" | tee -a "$RUN_DIR/run.log"
    printf '%s\t%s\t%s\t%s\n' "$cpu7_case" "$TEST_SECONDS" "$cpu7_elapsed" COMPLETED \
        >> "$RUN_DIR/summary.tsv"
}

case "${1:-}" in
    --help|-h) usage; exit 0 ;;
    isolated|normal|auto) REQUESTED_MODE=$1; shift ;;
esac
[ "$#" -gt 0 ] || set -- 50 80
cpu7_seen=' '
cpu7_needs_stress=0
for cpu7_arg do
    case "$cpu7_arg" in
        0|idle) cpu7_arg=0 ;;
        50|80) cpu7_needs_stress=1 ;;
        *) usage; exit 2 ;;
    esac
    case "$cpu7_seen" in *" $cpu7_arg "*) printf '%s\n' 'Duplicate case'; exit 2 ;; esac
    cpu7_seen="$cpu7_seen$cpu7_arg "
done
# cpu7_seen 只包含校验过的数字和空格；统一 idle 别名并保留输入顺序。
set -- $cpu7_seen
check_number TEST_SECONDS "$TEST_SECONDS" 1
check_number WARMUP_SECONDS "$WARMUP_SECONDS" 0
check_number COOLDOWN_SECONDS "$COOLDOWN_SECONDS" 0
check_number PROGRESS_SECONDS "$PROGRESS_SECONDS" 1
for cpu7_tool in cyclictest taskset mktemp date grep tee; do
    command -v "$cpu7_tool" >/dev/null 2>&1 || die "missing tool: $cpu7_tool"
done
if [ "$cpu7_needs_stress" -eq 1 ]; then
    command -v stress-ng >/dev/null 2>&1 || die 'missing tool: stress-ng'
fi
[ "$(id -u)" -eq 0 ] || die 'run as root on the board'
[ "$(cat /sys/devices/system/cpu/online)" = 0-7 ] || die 'expected all CPU0-7 online'
[ -r /sys/devices/system/cpu/isolated ] || die 'CPU isolation sysfs is missing'
check_mode
taskset -c 7 true || die 'CPU7 is not online/available to this shell'
# 脚本及压力/监控进程继承 CPU0–6 集合，cyclictest 自己把测量线程绑到 CPU7。
taskset -pc 0-6 "$$" >/dev/null || die 'cannot move the script to CPU0-6'
if [ -d "$CPU7_LIB_DIR" ]; then
    export LD_LIBRARY_PATH="$CPU7_LIB_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
mkdir -p "$OUTPUT_BASE" || die "cannot create $OUTPUT_BASE"
RUN_DIR=$(mktemp -d "$OUTPUT_BASE/night_${TEST_MODE}_$(date '+%Y%m%d_%H%M%S')_XXXXXX") || die 'cannot create run directory'
trap cleanup 0
trap interrupted INT TERM HUP
printf '%s\n' RUNNING > "$RUN_DIR/status.txt"
printf 'case\trequested_seconds\telapsed_seconds\tstatus\n' > "$RUN_DIR/summary.tsv"
printf '%s\n' "$$" > "$RUN_DIR/runner.pid"
printf '%s\n' "$TEST_MODE" > "$RUN_DIR/mode.txt"
printf '%s\n' "$REQUESTED_MODE" > "$RUN_DIR/requested_mode.txt"
uname -a > "$RUN_DIR/kernel.txt"
cat /proc/cmdline > "$RUN_DIR/cmdline.txt"
cat /sys/devices/system/cpu/online > "$RUN_DIR/online.txt"
cat /sys/devices/system/cpu/isolated > "$RUN_DIR/isolated.txt"
cat /sys/devices/system/cpu/nohz_full > "$RUN_DIR/nohz_full.txt" 2>/dev/null || :
log "Results: $RUN_DIR; cases:$cpu7_seen; seconds per case=$TEST_SECONDS"
log "Mode: $TEST_MODE (requested=$REQUESTED_MODE); cyclictest thread pinned to CPU7 in both isolated and normal modes."
log "Scheduler isolated CPUs: ${cpu7_isolated:-none}; boot configuration is unchanged (see cmdline.txt and nohz_full.txt)."
if [ "$TEST_MODE" = custom ]; then
    log 'WARNING: mixed/other isolation configuration; do not treat this run as a clean normal baseline.'
fi
log 'Target load is approximate; CPU7 receives no extra stress worker.'
cpu7_first=1
for cpu7_arg do
    if [ "$cpu7_first" -eq 0 ]; then
        log "Cooldown: ${COOLDOWN_SECONDS}s"
        sleep "$COOLDOWN_SECONDS"
    fi
    cpu7_first=0
    run_case "$cpu7_arg"
done
STATUS=COMPLETED
log 'All requested cases completed.'
exit 0
