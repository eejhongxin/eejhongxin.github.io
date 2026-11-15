#!/bin/sh
set -eu

BASE=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
NAME=${0##*/}
export LD_LIBRARY_PATH="$BASE/lib:/lib:/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

case "$NAME" in
    stressapptest|memtester|lrz|lsz) exec "$BASE/libexec/$NAME" "$@" ;;
    rz) exec "$BASE/libexec/lrz" "$@" ;;
    sz) exec "$BASE/libexec/lsz" "$@" ;;
    awk|free|df|tar|bzip2|bunzip2|md5sum|sha256sum|usleep|setsid|nohup|mktemp|grep|sed|tail|tee|ps|top|watch|dmesg|uptime)
        exec "$BASE/libexec/busybox" "$NAME" "$@"
        ;;
    *) echo "Unknown bundled tool: $NAME" >&2; exit 2 ;;
esac
