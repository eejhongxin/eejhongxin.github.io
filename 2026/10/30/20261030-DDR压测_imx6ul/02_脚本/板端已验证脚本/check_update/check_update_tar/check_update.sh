#!/bin/sh
###
 # @Author: qishengxuan shengxuan_qi@huace.cn
 # @Date: 2025-07-14 19:02:09
 # @LastEditors: qishengxuan shengxuan_qi@huace.cn
 # @LastEditTime: 2025-07-17 23:36:22
 # @FilePath: /ddr_test/check_update/check_update_tar/check_update.sh
 # @Description: 这是默认设置,请设置`customMade`, 打开koroFileHeader查看配置 进行设置: https://github.com/OBKoro1/koro1FileHeader/wiki/%E9%85%8D%E7%BD%AE
### 

i=0

if [ -e check_result ];
then
	rm check_result
fi
echo $i > check_result
if [ -d ./updateback ]
then
	rm ./updateback -rf
fi
mkdir ./updateback
while [ $i -lt $1 ]
do
    i=$((i+1))
    tar -xvf update.tar.bz2
    sync  
    md5sum -c  md5_update_x6_v2.1.2_b20201127.txt
    if [ $? != 0 ];then
      echo $i error >>  check_result
      md5sum update/* >> check_result
      mkdir ./updateback/updateback${i}
      cp update/* ./updateback/updateback${i}/
      sync
    fi
    sed -i "1c $i" check_result
    rm -rf update
    sync
    usleep 100000
done