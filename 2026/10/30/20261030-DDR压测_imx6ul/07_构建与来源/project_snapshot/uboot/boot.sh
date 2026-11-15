#!/bin/bash

UBOOTDIR=`pwd`
UBOOTCFG=${UBOOTDIR}/board/freescale/mx6ul_14x14_evk

UBOOTOUT=$UBOOTDIR/out

RELEASE_DATE=`date +%Y%m%d`

help()
{
cat << EOF
Usage: boot.sh [OPTION]
Build script for compile the uboot for platform mx6ul
    -h, --help :    display this help and exit
    -product=  :    product name.(example:p4/i50/401/p5dl/x3)
    Ex:
    ./boot.sh -product=p5
EOF
}

outpt_process()
{
    cp u-boot.imx $UBOOTOUT/u-boot_$PRODUCT"_"$RELEASE_DATE.imx
    md5sum $UBOOTOUT/u-boot_$PRODUCT"_"$RELEASE_DATE.imx
    md5sum $UBOOTOUT/u-boot_$PRODUCT"_"$RELEASE_DATE.imx | cut -d ' ' -f1 > $UBOOTOUT/md5_uboot_$PRODUCT"_"$RELEASE_DATE.txt
    chmod +x $UBOOTOUT/*
}

while [ "$1" ];do
    echo $1
    case "$1" in
    -product=p5)
        PRODUCT="p5"
        ;;
    -product=i50)
        PRODUCT="i50"
        ;;
    -product=x3)
        PRODUCT="x3"
        ;;
    -product=mc200)
	PRODUCT="mc200"
	;;
    -product=401)
        PRODUCT="401"
        ;;
    -product=p5dl)
        PRODUCT="p5dl"
        ;;
    -product=i80s)
        PRODUCT="i80s"
        ;;
    -product=bd3)
	PRODUCT="bd3"
	;;
    -product=p2)
	PRODUCT="p2"
	;;
    -product=lband)
        PRODUCT="lband"
        ;;
    -product=b5)
        PRODUCT="b5"
        ;;
    -product=d1)
        PRODUCT="d1"
        ;;
    -product=h920)
        PRODUCT="h920"
        ;;
    -product=nx350)
        PRODUCT="nx350"
        ;;
    -product=p2df)
        PRODUCT="p2df"
        ;;
    -product=gd100)
        PRODUCT="gd100"
        ;;
    -h | -help)
        help
        exit 0
    esac
    shift
done

if [ "$PRODUCT" = "p5" ];then
    cp -f ${UBOOTCFG}/mx6ul_14x14_evk_p5.c ${UBOOTCFG}/mx6ul_14x14_evk.c
    sync
    source /opt/imx6/environment-setup-cortexa7hf-vfp-neon-poky-linux-gnueabi
    make mx6ul_14x14_chc_qspi1_config
    make -j4
    outpt_process
#   cp u-boot.imx u-boot_p5.imx
elif [ "$PRODUCT" = "d1" ];then
    cp -f ${UBOOTCFG}/mx6ul_14x14_evk_d1.c ${UBOOTCFG}/mx6ul_14x14_evk.c
    cp -f ${UBOOTDIR}/include/configs/mx6ul_14x14_evk_d1.h ${UBOOTDIR}/include/configs/mx6ul_14x14_evk.h
    sync
    source /opt/imx6/environment-setup-cortexa7hf-vfp-neon-poky-linux-gnueabi 
    make mx6ul_14x14_chc_qspi1_config
    make -j4
    outpt_process
elif [ "$PRODUCT" = "i50" ];then
    cp -f ${UBOOTCFG}/mx6ul_14x14_evk_i50.c ${UBOOTCFG}/mx6ul_14x14_evk.c
    sync
    source /opt/imx6/environment-setup-cortexa7hf-vfp-neon-poky-linux-gnueabi
    make mx6ul_14x14_chc_qspi1_config
    make -j4
    outpt_process
elif [ "$PRODUCT" = "x3" ];then
    source /opt/imx6/environment-setup-cortexa7hf-vfp-neon-poky-linux-gnueabi
    make mx6ul_chcnav_x3_config
    make -j4
    outpt_process
elif [ "$PRODUCT" = "mc200" ];then
    cp -f ${UBOOTCFG}/mx6ul_14x14_evk_mc200.c ${UBOOTCFG}/mx6ul_14x14_evk.c
	cp -f ${UBOOTDIR}/arch/arm/imx-common/cpu.c ${UBOOTDIR}/arch/arm/imx-common/cpu.c.bak
	cp -f ${UBOOTDIR}/arch/arm/imx-common/cpu_mc200.c ${UBOOTDIR}/arch/arm/imx-common/cpu.c
    sync
    source /opt/imx6/environment-setup-cortexa7hf-vfp-neon-poky-linux-gnueabi
    make mx6ul_14x14_chc_qspi1_config
    make -j4
    outpt_process
	cp -f ${UBOOTDIR}/arch/arm/imx-common/cpu.c.bak ${UBOOTDIR}/arch/arm/imx-common/cpu.c
	rm ${UBOOTDIR}/arch/arm/imx-common/cpu.c.bak
elif [ "$PRODUCT" = "401" ];then
    cp -f ${UBOOTCFG}/mx6ul_14x14_evk_i50.c ${UBOOTCFG}/mx6ul_14x14_evk.c
    sync
    source /opt/imx6/environment-setup-cortexa7hf-vfp-neon-poky-linux-gnueabi
    make mx6ul_14x14_chc_qspi1_config
    make -j4
    outpt_process
elif [ "$PRODUCT" = "p5dl"  ];then
    cp -f ${UBOOTCFG}/mx6ul_14x14_evk_p5dl.c ${UBOOTCFG}/mx6ul_14x14_evk.c
    sync
    source /opt/imx6/environment-setup-cortexa7hf-vfp-neon-poky-linux-gnueabi
    make mx6ul_14x14_chc_qspi1_config
    make -j4
    outpt_process
elif [ "$PRODUCT" = "i80s"  ];then
    cp -f ${UBOOTCFG}/mx6ul_14x14_evk_i80s.c ${UBOOTCFG}/mx6ul_14x14_evk.c
    sync
    source /opt/imx6/environment-setup-cortexa7hf-vfp-neon-poky-linux-gnueabi
    make mx6ul_14x14_chc_qspi1_config
    make -j4
    outpt_process
elif [ "$PRODUCT" = "bd3"  ];then
    cp -f ${UBOOTCFG}/mx6ul_14x14_evk_p5dl.c ${UBOOTCFG}/mx6ul_14x14_evk.c
    sync
    source /opt/imx6/environment-setup-cortexa7hf-vfp-neon-poky-linux-gnueabi
    make mx6ul_14x14_chc_qspi1_config
    make -j4
    outpt_process
elif [ "$PRODUCT" = "p2"  ];then
    cp -f ${UBOOTCFG}/mx6ul_14x14_evk_p2.c ${UBOOTCFG}/mx6ul_14x14_evk.c
    sync
    source /opt/imx6/environment-setup-cortexa7hf-vfp-neon-poky-linux-gnueabi
    make mx6ul_14x14_chc_qspi1_config
    make -j4
    outpt_process
elif [ "$PRODUCT" = "lband" ];then
    cp -f ${UBOOTCFG}/mx6ul_14x14_evk_lband.c ${UBOOTCFG}/mx6ul_14x14_evk.c
    sync
    source /opt/imx6/environment-setup-cortexa7hf-vfp-neon-poky-linux-gnueabi
    make mx6ul_14x14_chc_qspi1_config
    make -j4
    outpt_process
elif [ "$PRODUCT" = "b5" ];then
    source /opt/imx6/environment-setup-cortexa7hf-vfp-neon-poky-linux-gnueabi
    make mx6ul_chcnav_b5_config
    make -j4
    outpt_process
elif [ "$PRODUCT" = "h920" ];then
    cp -f ${UBOOTCFG}/mx6ul_14x14_evk_h920.c ${UBOOTCFG}/mx6ul_14x14_evk.c
    sync
    source /opt/imx6/environment-setup-cortexa7hf-vfp-neon-poky-linux-gnueabi
    make mx6ul_14x14_chc_qspi1_config
    make -j4
    outpt_process
elif [ "$PRODUCT" = "nx350" ];then
    cp -f ${UBOOTCFG}/mx6ul_14x14_evk_nx350.c ${UBOOTCFG}/mx6ul_14x14_evk.c
    sync
    source /opt/imx6/environment-setup-cortexa7hf-vfp-neon-poky-linux-gnueabi
    make mx6ul_14x14_chc_qspi1_config
    make -j4
    outpt_process
elif [ "$PRODUCT" = "p2df" ];then
    cp -f ${UBOOTCFG}/mx6ul_14x14_evk_p2df.c ${UBOOTCFG}/mx6ul_14x14_evk.c
    sync
    source /opt/imx6/environment-setup-cortexa7hf-vfp-neon-poky-linux-gnueabi
    make mx6ul_14x14_chc_qspi1_config
    make -j4
    outpt_process
elif [ "$PRODUCT" = "lband" ];then
    cp -f ${UBOOTCFG}/mx6ul_14x14_evk_lband.c ${UBOOTCFG}/mx6ul_14x14_evk.c
    sync
    source /opt/imx6/environment-setup-cortexa7hf-vfp-neon-poky-linux-gnueabi
    make mx6ul_14x14_chc_qspi1_config
    make -j4
    outpt_process
elif [ "$PRODUCT" = "gd100" ];then
    cp -f ${UBOOTCFG}/mx6ul_14x14_evk_gd100.c ${UBOOTCFG}/mx6ul_14x14_evk.c
    sync
    source /opt/imx6/environment-setup-cortexa7hf-vfp-neon-poky-linux-gnueabi
    make mx6ul_14x14_chc_qspi1_config
    make -j4
    outpt_process
else
    help
    exit 1
fi

echo "end compile uboot"
