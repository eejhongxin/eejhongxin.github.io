#!/bin/sh
set -eu
BASE=$(CDPATH= cd "$(dirname "$0")" && pwd)
PATH="$BASE/bin:$PATH"
export PATH
DURATION=${1:-7200}
INTERVAL=${2:-1}
MOUNT=${DDR_MOUNT:-/mnt}
for value in "$DURATION" "$INTERVAL"; do
    case "$value" in ''|*[!0-9]*|0*) echo "Use positive decimal duration/interval" >&2; exit 1 ;; esac
    [ "${#value}" -le 7 ] || exit 1
done
awk -v m="$MOUNT" '$2==m && $1 ~ /^\/dev\// {
    n=split($4,a,","); for(i=1;i<=n;i++) if(a[i]=="rw") ok=1
} END {exit !ok}' /proc/mounts || { echo "$MOUNT is not a writable block mount" >&2; exit 1; }
mkdir -p "$MOUNT/ddr_work"
DIR=$(mktemp -d "$MOUNT/ddr_work/usage.XXXXXX")
LOG="$DIR/ddr_memory_usage.csv"
echo 'Timestamp,Total_kB,Used_kB,Free_kB,Usage_percent' > "$LOG"
echo "Collecting memory usage: $LOG"
END=$(($(date +%s) + DURATION))
while [ "$(date +%s)" -lt "$END" ]; do
    awk -v t="$(date '+%Y-%m-%d %H:%M:%S')" '
        /^MemTotal:/ {total=$2} /^MemFree:/ {free=$2}
        END {if(total>0) printf "%s,%d,%d,%d,%.2f\n", t,total,total-free,free,100*(total-free)/total}
    ' /proc/meminfo >> "$LOG"
    sleep "$INTERVAL"
done
sync
echo "Done: $LOG"
