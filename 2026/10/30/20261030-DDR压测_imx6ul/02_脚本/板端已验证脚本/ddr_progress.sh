#!/bin/sh

DDR_PROGRESS_PID=

ddr_progress_now()
{
    read -r uptime idle < /proc/uptime
    printf '%s\n' "${uptime%%.*}"
}

ddr_progress_time()
{
    printf '%02d:%02d:%02d' "$(($1 / 3600))" "$(($1 / 60 % 60))" "$(($1 % 60))"
}

ddr_stage_start()
{
    DDR_STAGE=$1
    DDR_STAGE_START=$(ddr_progress_now)
    printf '[progress] Round %s/%s: %s starting\n' "$(($count + 1))" "$DDR_ROUNDS" "$DDR_STAGE" >&2
}

ddr_counter_report()
{
    elapsed=$1
    completed=$2
    total=$3
    printf '[progress] %s: %s/%s (%s%%), elapsed=' "$DDR_STAGE" "$completed" "$total" "$((completed * 100 / total))" >&2
    ddr_progress_time "$elapsed" >&2
    if [ "$completed" -gt 0 ]; then
        printf ', estimated remaining=' >&2
        ddr_progress_time "$((elapsed * (total - completed) / completed))" >&2
    else
        printf ', estimated remaining=unknown' >&2
    fi
    printf '\n' >&2
}

ddr_counter_start()
{
    DDR_COUNTER=$1
    DDR_TOTAL=$2
    DDR_OLD_COUNTER_ID=$(stat -c %i "$DDR_COUNTER" 2>/dev/null)
    (
        sleeper=
        trap 'if [ -n "$sleeper" ]; then kill "$sleeper" 2>/dev/null; wait "$sleeper" 2>/dev/null; fi; exit 0' INT TERM HUP
        while kill -0 "$$" 2>/dev/null; do
            sleep "${DDR_PROGRESS_INTERVAL:-10}" &
            sleeper=$!
            wait "$sleeper"
            sleeper=
            elapsed=$(($(ddr_progress_now) - DDR_STAGE_START))
            counter_id=$(stat -c %i "$DDR_COUNTER" 2>/dev/null)
            # sed -i replaces check_result each iteration; ignore a previous run.
            if [ -z "$counter_id" ] || [ "$counter_id" = "$DDR_OLD_COUNTER_ID" ]; then
                printf '[progress] %s: waiting for a new counter, elapsed=' "$DDR_STAGE" >&2
                ddr_progress_time "$elapsed" >&2
                printf '\n' >&2
                continue
            fi
            completed=
            read -r completed < "$DDR_COUNTER" 2>/dev/null
            case "$completed" in ''|*[!0-9]*) continue ;; esac
            case "$completed" in 0?*) continue ;; esac
            [ "${#completed}" -le 4 ] || continue
            [ "$completed" -le "$DDR_TOTAL" ] || continue
            ddr_counter_report "$elapsed" "$completed" "$DDR_TOTAL"
        done
    ) &
    DDR_PROGRESS_PID=$!
}

ddr_progress_stop()
{
    if [ -n "$DDR_PROGRESS_PID" ]; then
        kill "$DDR_PROGRESS_PID" 2>/dev/null
        wait "$DDR_PROGRESS_PID" 2>/dev/null
        DDR_PROGRESS_PID=
    fi
}

ddr_stage_end()
{
    ddr_progress_stop
    printf '[progress] %s finished, elapsed=' "$DDR_STAGE" >&2
    ddr_progress_time "$(($(ddr_progress_now) - DDR_STAGE_START))" >&2
    printf '\n' >&2
}
