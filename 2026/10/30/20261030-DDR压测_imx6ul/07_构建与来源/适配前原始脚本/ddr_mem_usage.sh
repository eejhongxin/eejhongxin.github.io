#!/bin/sh
###
 # @Author: qishengxuan shengxuan_qi@huace.cn
 # @Date: 2025-08-12 17:50:23
 # @LastEditors: qishengxuan shengxuan_qi@huace.cn
 # @LastEditTime: 2025-08-12 17:59:47
 # @FilePath: /ddr_test/ddr_mem_usage.sh
 # @Description: 这是默认设置,请设置`customMade`, 打开koroFileHeader查看配置 进行设置: https://github.com/OBKoro1/koro1FileHeader/wiki/%E9%85%8D%E7%BD%AE
### 

#脚本功能：计算空闲状态下DDR内存使用率

# 设置日志文件路径
TEST_DIR="/mnt/ddr_all_test"  
LOG_FILE="${TEST_DIR}/ddr_memory_usage.log"
DURATION=7200  # 2小时=7200秒
INTERVAL=1     # 1秒采集一次

# 检查是否已有日志文件，若有则备份
if [ -f "$LOG_FILE" ]; then
    mv "$LOG_FILE" "${LOG_FILE}.bak"
    echo "copy old log to  ${LOG_FILE}.bak"
else
    mkdir -p "${TEST_DIR}"
    touch "$LOG_FILE"
    chmod 777 "${TEST_DIR}" "$LOG_FILE"
fi

# 写入日志头信息
echo "Timestamp,Total Memory(kB),Used Memory(kB),Free Memory(kB),Usage Percentage" > "$LOG_FILE"

# 开始采集
echo "start ddr usuage test,times:2 hours..."
start_time=$(date +%s)
end_time=$((start_time + DURATION))

while [ $(date +%s) -lt $end_time ]; do
    # 获取当前时间戳
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    # 通过free命令获取内存信息（假设开发板支持free命令）
    memory_info=$(free -k | grep Mem)
    total=$(echo $memory_info | awk '{print $2}')
    used=$(echo $memory_info | awk '{print $3}')
    free=$(echo $memory_info | awk '{print $4}')
    
    # 计算使用百分比
    usage_percent=$(echo "scale=2; $used * 100 / $total" | bc)
    
    # 写入日志
    echo "$timestamp,$total,$used,$free,$usage_percent%" >> "$LOG_FILE"
    
    # 等待1秒
    sleep $INTERVAL
done

echo "test end ,result save to  $LOG_FILE"