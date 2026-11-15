#!/bin/sh
set -u

WORK=/mnt/ddr_work
PACKAGE="$WORK/full/ddr_p5"
LOGS="$WORK/ddr_all_test"
ARCHIVES="$WORK/ddr_backup"
COUNT_FILE="$WORK/ddr_autostart.count"
LOCK=/mem/ddr-autotest.lock
LAUNCH_LOG=/tmp/ddr-autotest-launch.log
SELF=$(CDPATH= cd "$(dirname "$0")" && pwd)/$(basename "$0")
PATH="$PACKAGE/bin:/sbin:/bin:/usr/sbin:/usr/bin"
export PATH

die() { echo "ERROR: $*" >&2; exit 1; }
mounted() {
    awk '$2=="/mnt" {ok=($1=="/dev/mmcblk1p7" && $3=="vfat" && $4 ~ /(^|,)rw(,|$)/)}
         END {exit !ok}' /proc/mounts || die "/mnt must be /dev/mmcblk1p7 mounted vfat/rw"
}
idle() {
    if ps | grep -q '[d]dr_test.sh'; then
        die "A DDR test is running; no logs moved and no new test started"
    fi
}
rounds_valid() {
    case "$1" in ''|*[!0-9]*|0*) return 1 ;; esac
    [ "${#1}" -le 4 ] && [ "$1" -le 1000 ]
}
save_unpack() {
    destination=$1
    for kind in bin tar; do
        source_dir=/tmp/check_update_$kind
        [ -d "$source_dir" ] || continue
        mkdir -p "$destination/unpack_$kind" || return 1
        for name in check_result updateback; do
            [ ! -e "$source_dir/$name" ] ||
                cp -R "$source_dir/$name" "$destination/unpack_$kind/" || return 1
        done
    done
}
archive() {
    mounted
    idle
    mkdir -p "$ARCHIVES" || die "Cannot create $ARCHIVES"
    BACKUP=$(mktemp -d "$ARCHIVES/ddr_all_test.XXXXXX") || die "Cannot create backup directory"
    if [ -e "$LOGS" ]; then
        [ -d "$LOGS" ] && [ ! -L "$LOGS" ] || die "Unexpected log path: $LOGS"
        mv "$LOGS" "$BACKUP/ddr_all_test" || die "Cannot archive $LOGS"
    fi
    sync
    echo "Previous data archived: $BACKUP"
}
start() {
    mounted
    [ -f "$COUNT_FILE" ] || die "Autostart is not enabled: $COUNT_FILE missing"
    rounds=$(cat "$COUNT_FILE") || die "Cannot read round count"
    rounds_valid "$rounds" || die "Round count must be 1..1000"
    [ -r "$PACKAGE/ddr_test.sh" ] && [ -r "$PACKAGE/ddr_progress.sh" ] ||
        die "Full DDR package is missing"
    command -v nohup >/dev/null 2>&1 && command -v setsid >/dev/null 2>&1 ||
        die "Missing nohup or setsid"
    idle
    if ! mkdir "$LOCK" 2>/dev/null; then
        echo "Autotest already scheduled in this boot; see $LAUNCH_LOG"
        return 0
    fi
    # Keep this lock until reboot, even when the finite test has completed.
    nohup setsid sh "$SELF" --worker "$rounds" > "$LAUNCH_LOG" 2>&1 < /dev/null &
    echo "Autotest scheduled: rounds=$rounds; startup log=$LAUNCH_LOG"
}
worker() {
    rounds_valid "${1:-}" || die "Invalid worker round count"
    [ -d "$LOCK" ] || die "Start using the start command"
    echo "$$" > "$LOCK/pid" || die "Cannot save worker PID"
    archive
    mkdir -p "$LOGS" || die "Cannot create $LOGS"
    echo "Console log: $LOGS/console.log; previous data: $BACKUP"
    exec > "$LOGS/console.log" 2>&1
    echo "Autotest rounds=$1; previous data=$BACKUP"
    echo "Results directory: $LOGS"
    dmesg > "$LOGS/kernel-before.log"
    cd "$PACKAGE" || die "Cannot enter $PACKAGE"
    sh ./ddr_test.sh -c "$1"
    result=$?
    printf '%s\n' "$result" > "$LOGS/runner_exit_code"
    save_unpack "$LOGS" || echo "ERROR: Could not preserve final unpack evidence"
    dmesg > "$LOGS/kernel-after.log"
    echo "Runner exited with code $result; this is NOT an overall PASS verdict."
    echo "Inspect individual results and kernel logs for OOM/killed processes."
    sync
    exit "$result"
}

case "${1:-}" in
    backup) archive ;;
    start) start ;;
    --worker) worker "${2:-}" ;;
    *) echo "Usage: sh ddr_autostart.sh [backup|start]" >&2; exit 2 ;;
esac
