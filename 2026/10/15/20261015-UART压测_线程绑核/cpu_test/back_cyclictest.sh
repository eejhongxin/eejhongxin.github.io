#!/bin/bash
# cyclictest -q 结果 → 直方图 PNG
#
# 单文件: ./back_cyclictest.sh <result.txt> [cores] [max_us]
# 双文件(CPU0-6 + CPU7): ./back_cyclictest.sh <result_0-6.txt> <result_7.txt> [max_us]

set -euo pipefail

declare -a MAX_PER_CPU=() CPU_LABELS=()
_CYCLIC_WORKDIR=""

cleanup_workdir() { [[ -n "$_CYCLIC_WORKDIR" ]] && rm -rf "$_CYCLIC_WORKDIR"; }

usage() {
	echo "用法:"
	echo "  $0 <result.txt> [cores] [max_us]          # 单文件，cores 可省略自动检测"
	echo "  $0 <result_0-6.txt> <result_7.txt> [max_us]  # 合并 CPU0-6 与 CPU7"
	echo "示例:"
	echo "  $0 result_1h_cpu7.txt                     # 仅 CPU7，输出 1 张图"
	echo "  $0 result_cpu-0-6.txt result_cpu-7.txt"
	exit 1
}

xmax_for() { local m=$1; echo $((m + m / 10 + 10)); }

write_plot_settings() {
	local label_max="${1:-$MAX_US}"
	local plot_xmax="${2:-$XMAX}"
	echo "set xlabel \"Latency (us)\""
	echo "set ylabel \"Sample count\""
	echo "set label 1 \"max observed: ${label_max} us\" at graph 0.98, graph 0.02 right front font \",10\""
	echo "set logscale y"
	echo "set xrange [0:${plot_xmax}]"
	echo "set yrange [0.8:*]"
	echo "set grid ytics"
}

extract_hist() {
	awk '
		/^#/ { next }
		NF >= 2 && $1 ~ /^[0-9]+$/ {
			for (i = 1; i <= NF; i++) $i = $i + 0
			print
		}
	' OFS="\t" "$1"
}

# 单线程 -q 输出常为 3 列: 延迟 + 计数 + 与计数相同的重复列，不是第 2 个 CPU
hist_effective_cols() {
	local hist="$1"
	awk '
		NR == 1 { n = NF; next }
		NF >= 3 && $2 != $3 { diff = 1 }
		END {
			if (n == 3 && !diff) print 1
			else if (n >= 2) print n - 1
			else print 0
		}
	' "$hist"
}

# 从文件名推断 CPU 编号 (result_1h_cpu7.txt → 7)
cpu_id_from_name() {
	local base
	base=$(basename "$1")
	if [[ "$base" =~ cpu[_-]?([0-9]+) ]]; then
		echo "${BASH_REMATCH[1]}"
		return
	fi
	echo 0
}

parse_max_latencies() {
	local file="$1" count="$2"
	mapfile -t _maxvals < <(grep "Max Latencies" "$file" | awk -v n="$count" '{
		for (i = 4; i <= NF && (i - 4) < n; i++) {
			gsub(/^0+/, "", $i); if ($i == "") $i = "0"
			print $i + 0
		}
	}')
	printf '%s\n' "${_maxvals[@]}"
}

hist_max_for_cpu() {
	local hist="$1" col=$((2 + $2))
	awk -v col="$col" '
		NF >= col && $1 ~ /^[0-9]+$/ && $(col) > 0 { last = $1 + 0 }
		END { print last + 0 }
	' "$hist"
}

# ---------- 双文件模式: CPU0-6 + CPU7 ----------
run_dual_mode() {
	local RESULT_06="$1" RESULT_07="$2" MAX_US="${3:-}"
	local CORES=8 CPUS_06=7

	[[ -f "$RESULT_06" && -f "$RESULT_07" ]] || usage

	local HIST_06 HIST_07 HIST_ALL
	_CYCLIC_WORKDIR=$(mktemp -d)
	trap cleanup_workdir EXIT
	HIST_06="$_CYCLIC_WORKDIR/hist_0-6.tsv"
	HIST_07="$_CYCLIC_WORKDIR/hist_7.tsv"
	HIST_ALL="$_CYCLIC_WORKDIR/histogram.tsv"

	extract_hist "$RESULT_06" > "$HIST_06"
	extract_hist "$RESULT_07" > "$HIST_07"
	[[ -s "$HIST_06" && -s "$HIST_07" ]] || { echo "错误: 直方图数据为空" >&2; exit 1; }

	awk -v cpus06="$CPUS_06" '
		FILENAME == ARGV[1] {
			for (i = 2; i <= cpus06 + 1; i++) h06[$1, i - 2] = $i
			lat[$1] = 1
			next
		}
		{ h07[$1] = $2; lat[$1] = 1 }
		END {
			n = asorti(lat, sorted)
			for (i = 1; i <= n; i++) {
				b = sorted[i]
				printf "%s", b
				for (c = 0; c < cpus06; c++) printf "\t%d", h06[b, c] + 0
				printf "\t%d\n", h07[b] + 0
			}
		}
	' "$HIST_06" "$HIST_07" > "$HIST_ALL"

	MAX_PER_CPU=()
	CPU_LABELS=()
	mapfile -t _max06 < <(parse_max_latencies "$RESULT_06" "$CPUS_06")
	mapfile -t _max07 < <(parse_max_latencies "$RESULT_07" 1)
	for ((i = 0; i < CPUS_06; i++)); do
		MAX_PER_CPU[i]=${_max06[i]:-0}
		CPU_LABELS[i]=$i
		[[ "${MAX_PER_CPU[i]}" -eq 0 ]] && MAX_PER_CPU[i]=$(hist_max_for_cpu "$HIST_ALL" "$i")
	done
	MAX_PER_CPU[7]=${_max07[0]:-0}
	CPU_LABELS[7]=7
	[[ "${MAX_PER_CPU[7]}" -eq 0 ]] && MAX_PER_CPU[7]=$(hist_max_for_cpu "$HIST_ALL" 7)

	run_plot "$HIST_ALL" "$RESULT_06" "$MAX_US"
}

# ---------- 单文件模式 ----------
run_single_mode() {
	local RESULT="$1"
	local CORES_ARG="${2:-}" MAX_US="${3:-}"

	[[ -f "$RESULT" ]] || usage

	# 第 2 参数: <=8 视为 cores，>8 且无第 3 参数时视为 max_us（如 400）
	local CORES="" CPU_ID=""
	if [[ -n "$CORES_ARG" && "$CORES_ARG" =~ ^[0-9]+$ ]]; then
		if [[ -z "${3:-}" && "$CORES_ARG" -gt 8 ]]; then
			MAX_US="$CORES_ARG"
		else
			CORES="$CORES_ARG"
			[[ "${3:-}" =~ ^[0-9]+$ ]] && MAX_US="${3:-}"
		fi
	fi

	local HIST_ALL
	_CYCLIC_WORKDIR=$(mktemp -d)
	trap cleanup_workdir EXIT
	HIST_ALL="$_CYCLIC_WORKDIR/histogram.tsv"

	extract_hist "$RESULT" > "$HIST_ALL"
	[[ -s "$HIST_ALL" ]] || { echo "错误: 未在 $RESULT 中找到直方图数据" >&2; exit 1; }

	local NCOLS DETECTED
	NCOLS=$(awk 'NR==1 { print NF; exit }' "$HIST_ALL")
	DETECTED=$(hist_effective_cols "$HIST_ALL")

	if [[ -z "$CORES" ]]; then
		CORES="$DETECTED"
		if (( NCOLS - 1 != DETECTED )); then
			echo "提示: 直方图 ${NCOLS} 列，有效 CPU 列数 ${DETECTED}（已忽略单线程重复列）" >&2
		fi
	elif (( CORES > DETECTED )); then
		echo "警告: 指定 ${CORES} 核，文件仅 ${DETECTED} 列有效数据，按 ${DETECTED} 核绘图" >&2
		CORES="$DETECTED"
	fi

	MAX_PER_CPU=()
	CPU_LABELS=()
	_maxvals=()
	if grep -q "Max Latencies" "$RESULT"; then
		mapfile -t _maxvals < <(parse_max_latencies "$RESULT" "$CORES")
		if ((${#_maxvals[@]} > 0 && ${#_maxvals[@]} < CORES)); then
			CORES=${#_maxvals[@]}
			echo "提示: 按 Max Latencies 识别为 ${CORES} 核" >&2
		fi
	fi

	CPU_ID=$(cpu_id_from_name "$RESULT")
	for ((i = 0; i < CORES; i++)); do
		if (( CORES == 1 )); then
			CPU_LABELS[i]=$CPU_ID
		else
			CPU_LABELS[i]=$i
		fi
		MAX_PER_CPU[i]=${_maxvals[i]:-0}
		if [[ "${MAX_PER_CPU[i]}" -eq 0 ]]; then
			MAX_PER_CPU[i]=$(hist_max_for_cpu "$HIST_ALL" "$i")
		fi
	done

	run_plot "$HIST_ALL" "$RESULT" "$MAX_US"
}

run_plot() {
	local HIST_ALL="$1" RESULT="$2" MAX_US="${3:-}"
	local CORES=${#MAX_PER_CPU[@]}
	local PLOT_DIR
	PLOT_DIR=$(dirname "$HIST_ALL")

	if [[ -z "$MAX_US" ]]; then
		MAX_US=0
		for v in "${MAX_PER_CPU[@]}"; do (( v > MAX_US )) && MAX_US=$v; done
		MAX_US=${MAX_US:-400}
	fi
	XMAX=$(xmax_for "$MAX_US")

	local OUTDIR PREFIX
	OUTDIR=$(dirname "$(readlink -f "$RESULT")")
	PREFIX="${OUTDIR}/cyclictest_hist"

	if ! command -v gnuplot >/dev/null 2>&1; then
		echo "错误: 未安装 gnuplot" >&2
		exit 1
	fi

	for ((i = 0; i < CORES; i++)); do
		cut -f1,$((i + 2)) "$HIST_ALL" > "$PLOT_DIR/cpu${i}.tsv"
	done

	# 仅 1 核时只出一张图，避免汇总图与单核图重复
	if (( CORES == 1 )); then
		local lid=${CPU_LABELS[0]} cmax=${MAX_PER_CPU[0]} cxmax
		cxmax=$(xmax_for "$cmax")
		local OUT="${PREFIX}_cpu${lid}.png"
		{
			echo "set title \"Cyclictest Latency Histogram (CPU${lid})\""
			echo "set terminal png size 1400,900 enhanced font \",12\""
			echo "set output \"${OUT}\""
			write_plot_settings "$cmax" "$cxmax"
			echo "plot \"$PLOT_DIR/cpu0.tsv\" using 1:2 title \"CPU${lid}\" with histeps lw 2"
		} > "$PLOT_DIR/plot_single.gp"
		gnuplot "$PLOT_DIR/plot_single.gp"
		echo "完成:"
		echo "  输入: $RESULT (1 核, 标注 CPU${lid})"
		echo "  图片: ${OUT}"
		echo "  max (us): ${cmax}"
		return
	fi

	local PNG="${PREFIX}.png"
	{
		echo "set title \"Cyclictest Latency Histogram (${CORES} CPUs)\""
		echo "set terminal png size 1400,900 enhanced font \",12\""
		echo "set output \"${PNG}\""
		write_plot_settings
		echo "set key outside right top"
		echo -n "plot "
		for ((i = 0; i < CORES; i++)); do
			[[ $i -gt 0 ]] && echo -n ", "
			echo -n "\"$PLOT_DIR/cpu${i}.tsv\" using 1:2 title \"CPU${CPU_LABELS[i]}\" with histeps lw 2"
		done
		echo
	} > "$PLOT_DIR/plot.gp"
	gnuplot "$WORKDIR/plot.gp"

	for ((i = 0; i < CORES; i++)); do
		local lid=${CPU_LABELS[i]} cmax=${MAX_PER_CPU[i]} cxmax
		cxmax=$(xmax_for "$cmax")
		local CPU_PNG="${PREFIX}_cpu${lid}.png"
		{
			echo "set title \"Cyclictest Latency Histogram (CPU${lid})\""
			echo "set terminal png size 1400,900 enhanced font \",12\""
			echo "set output \"${CPU_PNG}\""
			write_plot_settings "$cmax" "$cxmax"
			echo "plot \"$PLOT_DIR/cpu${i}.tsv\" using 1:2 title \"CPU${lid}\" with histeps lw 2"
		} > "$PLOT_DIR/plot_cpu${i}.gp"
		gnuplot "$PLOT_DIR/plot_cpu${i}.gp"
	done

	echo "完成:"
	echo "  汇总图片: ${PNG}"
	echo "  单核图片: ${PREFIX}_cpu${CPU_LABELS[0]}.png .. (共 ${CORES} 张)"
	echo "  各核 max (us): ${MAX_PER_CPU[*]}"
	echo "  汇总 X 轴上限: ${XMAX} us"
}

# ---------- 入口 ----------
if [[ -n "${1:-}" && -n "${2:-}" && -f "${1:-}" && -f "${2:-}" ]]; then
	run_dual_mode "$1" "$2" "${3:-}"
elif [[ -n "${1:-}" ]]; then
	run_single_mode "$@"
else
	usage
fi
