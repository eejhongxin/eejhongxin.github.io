#! /bin/sh

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
export PATH="$SCRIPT_DIR/bin:/data/sbin:$PATH"
. "$SCRIPT_DIR/ddr_progress.sh"
trap 'ddr_progress_stop' EXIT

TEST_DIR="/mnt/ddr_work/ddr_all_test"          # 测试目录
DDR_LOG="${TEST_DIR}/ddr_log.log"
#STRESS_LOG="${TEST_DIR}/stressapptest_$count.log"

help()
{
cat <<EOF
Usage: ./ddr_test.sh [OPTION] [COUNT]
    -h | -help: display this help and exit

    Ex:
        ./ddr_test.sh -c 1000
        ./ddr_test.sh clean
EOF
}

system_test_init()
{
    if ! grep -q ' /mnt ' /proc/mounts; then
        mkdir -p /mnt && mount -t vfat -o rw /dev/mmcblk1p7 /mnt || exit 1
    fi
    awk '$2=="/mnt" {ok=($1=="/dev/mmcblk1p7" && $3=="vfat" && $4 ~ /(^|,)rw(,|$)/)}
         END {exit !ok}' /proc/mounts || {
        echo "ERROR: /mnt must be /dev/mmcblk1p7 mounted vfat/rw" >&2
        exit 1
    }
    if ! grep -q ' /data ' /proc/mounts; then
        mkdir -p /data && mount -t ext4 -o ro,noload /dev/mmcblk1p5 /data || exit 1
    fi
    awk '$2=="/data" {ok=($1=="/dev/mmcblk1p5" && $3=="ext4")}
         END {exit !ok}' /proc/mounts || {
        echo "ERROR: /data must be /dev/mmcblk1p5 mounted ext4" >&2
        exit 1
    }
    [ -x /data/sbin/checkupdate ] || {
        echo "ERROR: Missing existing /data/sbin/checkupdate" >&2
        exit 1
    }
    # The existing P5 checkupdate requires all six eMMC data partitions mounted.
    for spec in '1 /recovery vfat ro' '2 /firmware vfat ro' \
                '3 /reserve vfat ro' '6 /data/app/log ext4 ro,noload'; do
        set -- $spec
        device=/dev/mmcblk1p$1
        point=$2
        filesystem=$3
        options=$4
        if ! awk -v p="$point" '$2==p {found=1} END {exit !found}' /proc/mounts; then
            mkdir -p "$point" && mount -t "$filesystem" -o "$options" "$device" "$point" || exit 1
        fi
        awk -v d="$device" -v p="$point" -v fs="$filesystem" \
            '$2==p {ok=($1==d && $3==fs)} END {exit !ok}' /proc/mounts || {
            echo "ERROR: $point must be $device mounted $filesystem" >&2
            exit 1
        }
    done

    echo "close all app!!!"
    cd /etc/init.d/
    killall S080_application
    ./S080_application stop
    cd - 

	mkdir -p "${TEST_DIR}"
	touch "${DDR_LOG}"
    chmod 777 "${TEST_DIR}" "${DDR_LOG}"
}

##通过 stressapptest 工具对 DDR 进行高并发、长时间、高压力的内存读写测试（默认 1 小时）
ddr_stressapptest_test()
{
    ddr_stage_start stressapptest
    mem=$(free | grep Mem | awk '{print $4}')
	mem=`expr $mem / 1024`
    mem=$(($mem-10))
	echo "Test memory size (MB): $mem (Total available - 10MB)" >> "${DDR_LOG}"
	touch "${TEST_DIR}/stressapptest_${count}.log"
	chmod 777 "${TEST_DIR}/stressapptest_${count}.log"

	### -m 4：启动4个内存读写线程（并发数，建议不超过CPU核心数）  -s 3600:3600秒  -w:启用写验证（写数据后立即读回校验，核心稳定性检测）
    stressapptest_result=`stressapptest -M $mem -m 8 -s 3600 -W -l "${TEST_DIR}/stressapptest_${count}.log" | tee /proc/self/fd/2 | grep "PASS" | wc -l`

    if [ $stressapptest_result == 1 ]
	then
		echo "$num.ddr stressapptest result: PASS" >> "${DDR_LOG}"
	else
		echo "$num.ddr stressapptest result: Failed" >> "${DDR_LOG}"
	fi
	num=$(($num+1))

    printf '[progress] stressapptest cooldown: 30 seconds\n' >&2
	sleep 30
	echo "===== DDR Stressapptest Completed =====" >> "${DDR_LOG}"
    ddr_stage_end
}

###通过 memtester 工具对 DDR 进行基础内存故障检测（覆盖地址线、数据线、读写验证、位翻转等），测试 1 轮后提取关键日志（9-29 行）写入总日志，侧重输出详细测试过程而非仅 PASS/FAIL。
ddr_memtester_test()
{
    ddr_stage_start memtester
    mem=$(free | grep Mem | awk '{print $4}')
	mem=`expr $mem / 1024`
    mem=$(($mem-10))

	touch "${TEST_DIR}/memtester_${count}.log"
	chmod 777 "${TEST_DIR}/memtester_${count}.log"
	### $mem：测试内存大小（MB）  1：测试轮数（仅运行1轮）
	memtester $mem 1 2>&1 | tee -a "${TEST_DIR}/memtester_${count}.log"
	memtester_result=`cat "${TEST_DIR}/memtester_${count}.log" | sed -n '9,29p'`
	echo "$num.ddr memtester result: $memtester_result" >> "${DDR_LOG}"
	num=$(($num+1))
	echo "===== DDR Memtestertest Completed =====" >> "${DDR_LOG}"
    ddr_stage_end
}

ddr_unpack_bin_test()
{
    ddr_stage_start "BIN unpack (1000 iterations)"
	cp "$SCRIPT_DIR/check_update/check_update_bin/" /tmp/ -rf
	cd /tmp/check_update_bin/
	chmod +x check_update.sh
    ddr_counter_start /tmp/check_update_bin/check_result 1000
	./check_update.sh 1000 >> /dev/null
    ddr_stage_end
	unpack_bin_result=`cat check_result`
	if [ $unpack_bin_result -eq 1000 ]
	then
		echo "$num.unpack bin test: Success" >> "${DDR_LOG}"
	else
		echo "$num.unpack bin test: Failed" >> "${DDR_LOG}"
	fi
	cd -
	num=$(($num+1))
	echo "===== DDR unpacktest Completed =====" >> "${DDR_LOG}"
}

ddr_unpack_tar_test()
{
    ddr_stage_start "TAR unpack (100 iterations)"
	cp "$SCRIPT_DIR/check_update/check_update_tar/" /tmp/ -rf
	cd /tmp/check_update_tar/
	chmod +x check_update.sh
    ddr_counter_start /tmp/check_update_tar/check_result 100
	./check_update.sh 100 >> /dev/null
    ddr_stage_end
	unpack_bin_result=`cat check_result`
	if [ $unpack_bin_result -eq 100 ]
	then
		echo "$num.unpack tar test: Success" >> "${DDR_LOG}"
	else
		echo "$num.unpack tar test: Failed" >> "${DDR_LOG}"
	fi
	cd -
	num=$(($num+1))
	echo "===== DDR unpacktartest Completed =====" >> "${DDR_LOG}"
}

log_cpu_status()
{
	if [ -r /sys/class/thermal/thermal_zone1/temp ]
	then
		cpu_temp=$(awk '{printf "%.2f", $1 / 1000}' /sys/class/thermal/thermal_zone1/temp)
		echo "CPU temperature: ${cpu_temp} C" >> "${DDR_LOG}"
	else
		echo "CPU temperature: N/A" >> "${DDR_LOG}"
	fi

	for cpu_path in /sys/devices/system/cpu/cpu[0-9]*
	do
		[ -d "$cpu_path" ] || continue
		cpu_name=${cpu_path##*/}

		if [ -r "${cpu_path}/online" ] && [ "$(cat "${cpu_path}/online")" != "1" ]
		then
			continue
		fi

		if [ -r "${cpu_path}/cpufreq/cpuinfo_cur_freq" ]
		then
			cpu_freq=$(cat "${cpu_path}/cpufreq/cpuinfo_cur_freq")
			echo "${cpu_name} frequency: ${cpu_freq} kHz" >> "${DDR_LOG}"
		elif [ -r "${cpu_path}/cpufreq/scaling_cur_freq" ]
		then
			cpu_freq=$(cat "${cpu_path}/cpufreq/scaling_cur_freq")
			echo "${cpu_name} frequency: ${cpu_freq} kHz" >> "${DDR_LOG}"
		else
			echo "${cpu_name} frequency: N/A" >> "${DDR_LOG}"
		fi
	done

	echo "===== CPU status collected =====" >> "${DDR_LOG}"
}

echo "---------ddr test start time: $(date "+%Y-%m-%d %H:%M:%S")---------"

if [ "$1" == "-c" ]
then
    count=0
    DDR_ROUNDS=$2
	system_test_init
	#mkdir -p /mnt/ddr_test
	echo "---------ddr test start time: $(date "+%Y-%m-%d %H:%M:%S")---------" >> "${DDR_LOG}"
    while [ $count -lt $2 ]
    do
		echo "----------count: $count----------"
        echo "----------count: $count----------" >> "${DDR_LOG}"
		
        # test project num
		num=1

		# ddr test start
		ddr_stressapptest_test
		ddr_memtester_test
		ddr_unpack_bin_test
		ddr_unpack_tar_test
		log_cpu_status
		# ddr test end

        count=$(($count+1))
        sleep 2
        sync
    done

	echo "[$(date "+%Y-%m-%d %H:%M:%S")] ddr test end" >> "${DDR_LOG}"

elif [ "$1" == "clean" ]
then
	#rm memtester_*.log
	#rm stressapptest_*.log
	rm -rf "${TEST_DIR}"
elif [ "$1" == "-h" ] || [ "$1" == "-help" ]
then
    help
else
    help
fi
echo "---------ddr test   end time: $(date "+%Y-%m-%d %H:%M:%S")---------"
echo "---------ddr test   end time: $(date "+%Y-%m-%d %H:%M:%S")---------" >> "${DDR_LOG}"
