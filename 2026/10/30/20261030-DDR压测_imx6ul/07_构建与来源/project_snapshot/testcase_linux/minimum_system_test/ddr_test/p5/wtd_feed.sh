#!/bin/sh
set -u

SELF=$(CDPATH= cd "$(dirname "$0")" && pwd)/$(basename "$0")
PATH="${SELF%/*}/bin:$PATH"
export PATH
GPIO=${WTD_GPIO:-/sys/class/leds/LED_Wtd_Done/brightness}
RUN=${WTD_RUN_DIR:-/mem/ddr-wtd-feed}
LOCK="$RUN/lock"
PIDFILE="$LOCK/pid"
LOG="$RUN/feed.log"
PID=
SLEEPER=

die() { echo "ERROR: $*" >&2; exit 1; }
read_pid() {
    PID=
    [ -r "$PIDFILE" ] || return 1
    read -r PID < "$PIDFILE" || return 1
    case "$PID" in ''|*[!0-9]*) return 1 ;; esac
    [ "$PID" -gt 1 ]
}
is_worker() {
    kill -0 "$PID" 2>/dev/null || return 1
    [ "$(awk '{print $3}' "/proc/$PID/stat" 2>/dev/null)" != Z ] || return 1
    tr '\000' '\n' < "/proc/$PID/cmdline" 2>/dev/null | grep -Fx "$SELF" >/dev/null || return 1
    tr '\000' '\n' < "/proc/$PID/cmdline" 2>/dev/null | grep -Fx -- '--worker' >/dev/null
}
cleanup() {
    trap - EXIT
    if [ -n "$SLEEPER" ]; then
        kill "$SLEEPER" 2>/dev/null || :
        wait "$SLEEPER" 2>/dev/null || :
    fi
    echo 0 > "$GPIO" || :
    if read_pid && [ "$PID" = "$$" ]; then
        rm -f "$PIDFILE"
        rmdir "$LOCK" 2>/dev/null || :
    fi
}
worker() {
    [ -d "$LOCK" ] || die "Start with: sh $SELF start"
    trap cleanup EXIT
    trap 'exit 0' TERM INT
    echo 0 > "$GPIO" || exit 1
    echo "$$" > "$PIDFILE" || exit 1
    while :; do
        echo 1 > "$GPIO" || exit 1
        usleep 50000 || exit 1
        echo 0 > "$GPIO" || exit 1
        sleep 10 &
        SLEEPER=$!
        wait "$SLEEPER" || exit 1
        SLEEPER=
    done
}
start() {
    if read_pid && is_worker; then
        echo "Already running: PID=$PID"
        return 0
    fi
    [ -w "$GPIO" ] || die "Cannot write $GPIO"
    command -v usleep >/dev/null 2>&1 || die "Missing usleep"
    command -v nohup >/dev/null 2>&1 || die "Missing nohup"
    command -v setsid >/dev/null 2>&1 || die "Missing setsid"
    # Refuse the earlier manual feeder instead of driving DONE from two loops.
    for cmdline in /proc/[0-9]*/cmdline; do
        [ -r "$cmdline" ] || continue
        if tr '\000' '\n' < "$cmdline" 2>/dev/null | grep -Fx "P=$GPIO" >/dev/null; then
            other=${cmdline%/cmdline}
            die "Manual feeder PID=${other##*/} exists; stop it with kill -TERM first"
        fi
    done
    mkdir -p "$RUN" || die "Cannot create $RUN"
    if ! mkdir "$LOCK" 2>/dev/null; then
        if read_pid && is_worker; then
            echo "Already running: PID=$PID"
            return 0
        fi
        die "Startup/stale lock exists: $LOCK; inspect status, then stop before retrying"
    fi
    # A separate session also protects BusyBox sleep children from terminal HUP.
    nohup setsid sh "$SELF" --worker > "$LOG" 2>&1 < /dev/null &
    child=$!
    n=0
    while [ "$n" -lt 50 ]; do
        if read_pid && is_worker; then
            echo "Started: PID=$PID; pulse=50ms; interval=10s; log=$LOG"
            return 0
        fi
        usleep 100000
        n=$((n + 1))
    done
    kill -TERM "$child" 2>/dev/null || :
    wait "$child" 2>/dev/null || :
    rmdir "$LOCK" 2>/dev/null || :
    die "Feeder failed to start; inspect $LOG"
}
stop() {
    if read_pid; then
        if is_worker; then
            target=$PID
            kill -TERM "$target" || die "Cannot stop PID=$target"
            n=0
            while [ "$n" -lt 50 ]; do
                PID=$target
                if ! is_worker && [ ! -d "$LOCK" ]; then
                    echo "Stopped: PID=$target. Watchdog is STILL ENABLED; reset may follow."
                    return 0
                fi
                usleep 100000
                n=$((n + 1))
            done
            die "Stop not confirmed; inspect PID=$target and $LOG; do not start another feeder"
        fi
        kill -0 "$PID" 2>/dev/null && die "PID=$PID is not this worker; refusing to signal it"
        rm -f "$PIDFILE" || die "Cannot remove stale PID file"
        rmdir "$LOCK" || die "Cannot remove stale lock"
    elif [ -d "$LOCK" ]; then
        die "Lock has no valid PID; startup may be in progress: $LOCK"
    fi
    echo "Not running. Watchdog is STILL ENABLED; reset may follow."
}

[ "$#" -le 1 ] || die "Usage: sh wtd_feed.sh [start|stop|status]"
case "${1:-start}" in
    -h|--help)
        echo "Usage: sh wtd_feed.sh [start|stop|status] (default: start)"
        echo "Temporary external watchdog feeder; no boot configuration is changed."
        echo "Stopping it does NOT disable the watchdog; the board may reset."
        exit 0 ;;
    start|stop|--worker)
        [ "$(id -u)" = 0 ] || die "Run as root"
        case "${1:-start}" in start) start ;; stop) stop ;; --worker) worker ;; esac ;;
    status)
        if read_pid && is_worker; then
            echo "Running: PID=$PID; log=$LOG"
        else
            echo "Not running, or stale startup state: $LOCK"
            exit 1
        fi ;;
    *) die "Usage: sh wtd_feed.sh [start|stop|status]" ;;
esac
