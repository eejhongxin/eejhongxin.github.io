#!/bin/sh
set -u

PACKAGE=$(CDPATH= cd "$(dirname "$0")" && pwd -P)
SELF="$PACKAGE/run.sh"
WORK=/mnt/ddr_work
MOUNTPOINT=/mnt
DEVICE=/dev/mmcblk1p7
MOUNTS=/proc/mounts
LOGS="$WORK/ddr_all_test"
ARCHIVES="$WORK/ddr_backup"
COUNT_FILE="$WORK/ddr_autostart.count"
LOCK=/mem/ddr-run.lock
BOOT_LOCK=/mem/ddr-autotest.lock
LAUNCH_LOG=/tmp/ddr-run-launch.log
LOCK_OWNED=0
PATH="$PACKAGE/bin:/sbin:/bin:/usr/sbin:/usr/bin"
export PATH

die() { echo "ERROR: $*" >&2; exit 1; }
valid_rounds() {
    case "$1" in ''|*[!0-9]*|0*) return 1 ;; esac
    [ "${#1}" -le 4 ] && [ "$1" -le 1000 ]
}
cleanup() {
    if [ "$LOCK_OWNED" = 1 ] && [ -r "$LOCK/pid" ]; then
        read -r owner < "$LOCK/pid" || owner=
        if [ "$owner" = "$$" ]; then
            rm -f "$LOCK/pid" "$LOCK/rounds" "$LOCK/ready"
            rmdir "$LOCK" 2>/dev/null || :
        fi
    fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

package_location() {
    case "$PACKAGE" in "$WORK/ddr_p5"|"$WORK/full/ddr_p5") ;;
        *) die "Extract under $WORK or $WORK/full, then run ddr_p5/run.sh" ;;
    esac
}
mounted() {
    awk -v point="$MOUNTPOINT" -v device="$DEVICE" \
        '$2==point {ok=($1==device && $3=="vfat" && $4 ~ /(^|,)rw(,|$)/)}
         END {exit !ok}' "$MOUNTS" || die "$MOUNTPOINT must be $DEVICE mounted vfat/rw"
}
prepare_mount() {
    package_location
    [ "$(id -u)" = 0 ] || die "Run as root"
    before=$(stat -c '%d:%i' "$SELF") || die "Cannot identify $SELF"
    if ! awk -v p="$MOUNTPOINT" '$2==p {found=1} END {exit !found}' "$MOUNTS"; then
        [ -b "$DEVICE" ] || die "Missing $DEVICE"
        mkdir -p "$MOUNTPOINT" && mount -t vfat -o rw "$DEVICE" "$MOUNTPOINT" || die "Cannot mount $DEVICE"
    fi
    mounted
    [ "$before" = "$(stat -c '%d:%i' "$SELF" 2>/dev/null)" ] ||
        die "Mount hid this script on NOR; enter the mounted eMMC and extract the full package there"
    [ "$(stat -c %d "$PACKAGE")" = "$(stat -c %d "$MOUNTPOINT")" ] ||
        die "The package must reside on the mounted eMMC"
}
prepare_feeder() {
    for directory in "$PACKAGE" "$WORK/ddr_p5" /mnt/ddr_bootstrap/ddr_p5 "$WORK/full/ddr_p5"; do
        [ -r "$directory/wtd_feed.sh" ] || continue
        if sh "$directory/wtd_feed.sh" status >/dev/null 2>&1; then
            sh "$directory/wtd_feed.sh" status
            return 0
        fi
    done
    sh "$PACKAGE/wtd_feed.sh" start || die "Watchdog feeder could not start; existing state was not cleared"
    sh "$PACKAGE/wtd_feed.sh" status || die "Watchdog feeder startup was not confirmed"
}
prepare_data() {
    for spec in '5 /data ext4 ro,noload' '1 /recovery vfat ro' \
                '2 /firmware vfat ro' '3 /reserve vfat ro' '6 /data/app/log ext4 ro,noload'; do
        set -- $spec
        dev=/dev/mmcblk1p$1
        point=$2
        filesystem=$3
        options=$4
        if ! awk -v p="$point" '$2==p {found=1} END {exit !found}' "$MOUNTS"; then
            mkdir -p "$point" && mount -t "$filesystem" -o "$options" "$dev" "$point" || die "Cannot mount $point"
        fi
        awk -v p="$point" -v d="$dev" -v fs="$filesystem" \
            '$2==p {ok=($1==d && $3==fs)} END {exit !ok}' "$MOUNTS" || die "Unexpected mount at $point"
    done
    [ -x /data/sbin/checkupdate ] || die "Missing existing /data/sbin/checkupdate"
}
idle() {
    if ps | grep -qE '[d]dr_test[.]sh|[s]tressapptest|[m]emtester|[c]heck_update[.]sh|[d]dr_autostart[.]sh --worker'; then
        die "A DDR test is running; no logs moved and no new test started"
    fi
}
verify() {
    [ -r "$PACKAGE/SHA256SUMS" ] || die "Full package manifest missing"
    (cd "$PACKAGE" && sha256sum -c SHA256SUMS) > /tmp/ddr-package-check.log 2>&1 || {
        cat /tmp/ddr-package-check.log >&2
        die "Package checksum failed; see /tmp/ddr-package-check.log"
    }
    for file in ddr_test.sh ddr_progress.sh wtd_feed.sh \
        check_update/check_update_bin/x6_v2.1.2.4B560lcyT_b20201225.bin \
        check_update/check_update_tar/update.tar.bz2; do
        [ -r "$PACKAGE/$file" ] || die "Full package is missing $file"
    done
}
acquire() {
    mkdir "$LOCK" 2>/dev/null || die "Another startup/run or stale lock exists: $LOCK; inspect status"
    LOCK_OWNED=1
    echo "$$" > "$LOCK/pid" || die "Cannot save startup PID"
}
save_unpack() {
    destination=$1
    for kind in bin tar; do
        source_dir=/tmp/check_update_$kind
        [ -d "$source_dir" ] || continue
        mkdir -p "$destination/unpack_$kind" || return 1
        for name in check_result updateback; do
            [ ! -e "$source_dir/$name" ] || cp -R "$source_dir/$name" "$destination/unpack_$kind/" || return 1
        done
    done
}
archive() {
    [ ! -e "$LOGS" ] || { [ -d "$LOGS" ] && [ ! -L "$LOGS" ]; } || die "Unexpected log path: $LOGS"
    mkdir -p "$ARCHIVES" || die "Cannot create backup root"
    BACKUP=$(mktemp -d "$ARCHIVES/previous.XXXXXX") || die "Cannot create backup directory"
    save_unpack "$BACKUP" || die "Cannot preserve previous unpack evidence"
    dmesg > "$BACKUP/kernel.log" || die "Cannot save kernel log"
    { date; cat /proc/uptime; cat /proc/cmdline; } > "$BACKUP/board.txt" || die "Cannot save board information"
    [ ! -d "$LOGS" ] || mv "$LOGS" "$BACKUP/ddr_all_test" || die "Cannot archive old logs"
    sync
    echo "Previous data: $BACKUP"
}
worker() {
    rounds=$1
    valid_rounds "$rounds" || die "Invalid worker rounds"
    [ -d "$LOCK" ] || die "Start using run.sh N"
    LOCK_OWNED=1
    echo "$$" > "$LOCK/pid" || die "Cannot save worker PID"
    echo "$rounds" > "$LOCK/rounds" || die "Cannot save active rounds"
    mounted
    idle
    archive
    mkdir -p "$LOGS" || die "Cannot create logs"
    printf 'DDR rounds=%s; package=%s; previous=%s\n' "$rounds" "$PACKAGE" "$BACKUP" > "$LOGS/console.log"
    dmesg > "$LOGS/kernel-before.log" || die "Cannot preserve initial kernel log"
    echo ready > "$LAUNCH_LOG.ready" || die "Cannot preserve startup acknowledgement"
    echo ready > "$LOCK/ready" || die "Cannot acknowledge startup"
    cd "$PACKAGE" || die "Cannot enter package"
    # A pipe keeps the original runner's tee /proc/self/fd/2 from truncating
    # console.log; the subshell saves the runner's own status before tee exits.
    (
        sh ./ddr_test.sh -c "$rounds"
        printf '%s\n' "$?" > "$LOGS/runner_exit_code"
    ) 2>&1 | tee -a "$LOGS/console.log" > /dev/null
    result=1
    [ ! -r "$LOGS/runner_exit_code" ] || read -r result < "$LOGS/runner_exit_code"
    save_unpack "$LOGS" || echo "ERROR: Could not preserve unpack evidence" >> "$LOGS/console.log"
    dmesg > "$LOGS/kernel-after.log"
    printf 'Runner exited with code %s; inspect SAT, memtester, BIN/TAR and kernel logs for overall result.\n' "$result" >> "$LOGS/console.log"
    sync
    exit "$result"
}
start() {
    rounds=$1
    valid_rounds "$rounds" || die "Round count must be 1..1000"
    prepare_mount
    idle
    acquire
    prepare_feeder
    prepare_data
    verify
    rm -f "$LAUNCH_LOG.ready" || die "Cannot reset startup acknowledgement"
    nohup setsid sh "$SELF" --worker "$rounds" > "$LAUNCH_LOG" 2>&1 < /dev/null &
    child=$!
    tries=0
    while [ "$tries" -lt 100 ]; do
        if [ -r "$LAUNCH_LOG.ready" ]; then
            echo "Started: $rounds rounds; logs=$LOGS"
            echo "Snapshot: sh $SELF progress"
            return 0
        fi
        if ! kill -0 "$child" 2>/dev/null; then
            cat "$LAUNCH_LOG" >&2
            die "Worker failed before tests started"
        fi
        usleep 100000
        tries=$((tries + 1))
    done
    die "Worker startup is still unconfirmed; do not retry blindly; inspect $LAUNCH_LOG and $LOCK"
}
status() {
    echo "Package: $PACKAGE"
    if [ -r "$COUNT_FILE" ]; then
        echo "Next boot rounds: $(cat "$COUNT_FILE")"
    else
        echo "Future test autostart: disabled"
    fi
    echo "Current processes:"
    ps | grep -E '[r]un[.]sh --worker|[d]dr_test[.]sh|[s]tressapptest|[m]emtester|[c]heck_update[.]sh|[w]td_feed[.]sh' || :
    if [ -d "$LOCK" ]; then
        echo "Run lock: $LOCK; PID=$(cat "$LOCK/pid" 2>/dev/null); rounds=$(cat "$LOCK/rounds" 2>/dev/null)"
    fi
    echo "Results: $LOGS"
    [ ! -r "$LOGS/runner_exit_code" ] || echo "Runner exit: $(cat "$LOGS/runner_exit_code") (not an overall PASS verdict)"
}
progress() {
    if [ ! -r "$LOGS/ddr_log.log" ]; then
        echo "No test summary yet; inspect $LAUNCH_LOG"
        return 0
    fi
    total=
    [ ! -r "$LOCK/rounds" ] || read -r total < "$LOCK/rounds"
    if [ -z "$total" ] && [ -r "$LOGS/console.log" ]; then
        total=$(sed -n 's/^DDR rounds=\([0-9]*\);.*/\1/p' "$LOGS/console.log" | head -n 1)
    fi
    awk -v total="${total:-unknown}" '/count:/ {round=$2+1} END {if(round) printf "Round %d/%s\n",round,total}' "$LOGS/ddr_log.log"
    tail -n 6 "$LOGS/console.log"
    [ ! -r "$LOGS/runner_exit_code" ] || echo "Runner completed; inspect individual results."
}

command=${1:-6}
case "$command" in
    --validate-autostart) prepare_mount; prepare_data; verify ;;
    --worker) [ "$#" = 2 ] || die "Internal worker requires rounds"; worker "$2" ;;
    --boot)
        prepare_mount
        prepare_feeder
        [ -f "$COUNT_FILE" ] || { echo "Mount and feeding ready; test autostart disabled"; exit 0; }
        rounds=$(cat "$COUNT_FILE")
        valid_rounds "$rounds" || die "Invalid $COUNT_FILE"
        mkdir "$BOOT_LOCK" 2>/dev/null || { echo "Autotest already scheduled this boot"; exit 0; }
        start "$rounds"
        ;;
    prepare) prepare_mount; prepare_feeder; prepare_data; verify; echo "Ready; no test started" ;;
    status) status ;;
    progress) progress ;;
    autostart) prepare_mount; sh "$PACKAGE/boot/install.sh" autostart "${2:-6}" ;;
    manual) prepare_mount; sh "$PACKAGE/boot/install.sh" manual ;;
    start) start "${2:-6}" ;;
    -h|--help)
        echo "Usage: sh run.sh [N|start N|prepare|status|progress|autostart N|manual]"
        echo "Default: start 6 rounds in the background; only autostart/manual change future startup settings."
        ;;
    *) valid_rounds "$command" || die "Use N, status, progress, autostart N, or manual"; [ "$#" -le 1 ] || die "Too many arguments"; start "$command" ;;
esac
