#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BUILD="$ROOT/out/ddr-build"
SRC="$BUILD/stressapptest-1.0.8"
TEST="$ROOT/testcase_linux/minimum_system_test/ddr_test"
BIN_SOURCE="$ROOT/testcase_linux/minimum_system_test/emmc_test/check_update/check_update_bin"
BIN_NAME=x6_v2.1.2.4B560lcyT_b20201225.bin
SDK=/opt/imx6/environment-setup-cortexa7hf-vfp-neon-poky-linux-gnueabi
mkdir -p "$BUILD"
ARCHIVE="$BUILD/stressapptest-v1.0.8.tar.gz"
if [[ ! -f "$ARCHIVE" ]]; then
    curl -fL --connect-timeout 10 --max-time 120 \
        https://codeload.github.com/stressapptest/stressapptest/tar.gz/refs/tags/v1.0.8 -o "$ARCHIVE"
fi
echo "b0432f39055166156ed04eb234f3c226b17a42f802a3f81d76ee999838e205df  $ARCHIVE" | sha256sum -c -
if [[ ! -d "$SRC" ]]; then
    tar -xzf "$ARCHIVE" -C "$BUILD"
fi
(
    set +u
    source "$SDK"
    unset PYTHONHOME
    export LC_ALL=C
    cd "$SRC"
    # The release's generated configure is stale; regenerate ARMv7 support.
    autoreconf -fi > "$BUILD/autoreconf.log" 2>&1
    ./configure --host=armv7a-poky-linux-gnueabi --build=x86_64-linux \
        CXXFLAGS='-O2 -pthread' CFLAGS='-O2 -pthread' > "$BUILD/configure.log" 2>&1
    make -j4 > "$BUILD/make.log" 2>&1
    "$STRIP" -o "$BUILD/stressapptest" src/stressapptest
)
STAGE=$(mktemp -d "$BUILD/package.XXXXXX")
trap 'rm -rf -- "$STAGE"' EXIT
PKG="$STAGE/ddr_p5"
mkdir -p "$PKG/bin" "$PKG/libexec" "$PKG/lib" "$PKG/licenses"
install -m 755 "$BUILD/stressapptest" "$PKG/libexec/"
install -m 755 "$ROOT/rootfs/usr/bin/memtester" "$PKG/libexec/"
install -m 755 "$ROOT/rootfs/sbin/lrz" "$ROOT/rootfs/sbin/lsz" "$ROOT/rootfs/bin/busybox" "$PKG/libexec/"
# SONAME copies and command launchers are regular files: /mnt is VFAT, not ext4.
for library in libstdc++.so.6 libgcc_s.so.1; do
    install -m 755 "$ROOT/rootfs/lib/$library" "$PKG/lib/$library"
done
for tool in stressapptest memtester lrz lsz rz sz \
    awk free df tar bzip2 bunzip2 md5sum sha256sum usleep setsid nohup \
    mktemp grep sed tail tee ps top watch dmesg uptime; do
    install -m 755 "$TEST/p5/tool.sh" "$PKG/bin/$tool"
done
printf 'stressapptest: upstream v1.0.8, rebuilt with /opt/imx6 SDK\nmemtester: rootfs/usr/bin/memtester (4.3.0)\nlrz, lsz, BusyBox and private C++ libraries: current rootfs checkout\n' > "$PKG/TOOLS.txt"
printf 'Requires the board base /lib ARM hard-float glibc runtime.\ncheckupdate is NOT included or replaced. BIN tests use the existing /data/sbin/checkupdate; mount /data first.\nBIN fixture compatibility with the existing board tool must be verified by a small unpack-only test before long full-suite runs.\n' >> "$PKG/TOOLS.txt"
install -m 755 "$TEST/p5/ddr_test.sh" "$TEST/p5/ddr_progress.sh" "$TEST/p5/ddr_mem_usage.sh" "$TEST/p5/wtd_feed.sh" "$PKG/"
install -m 644 "$TEST/p5/README.md" "$PKG/"
install -m 644 "$SRC/COPYING" "$PKG/licenses/stressapptest-COPYING"
install -m 644 "$SRC/NOTICE" "$PKG/licenses/stressapptest-NOTICE"
tar -xOzf "$ROOT/kernel/external/memtester-4.3.0.tar.gz" memtester-4.3.0/COPYING > "$PKG/licenses/memtester-COPYING"
sha256sum "$ARCHIVE" > "$PKG/licenses/stressapptest-source.sha256"
manifest() (
    cd "$PKG"
    find . -type f ! -name SHA256SUMS -print0 | LC_ALL=C sort -z | xargs -0 sha256sum > SHA256SUMS
)
for kind in bin tar; do
    dir="$PKG/check_update/check_update_$kind"
    mkdir -p "$dir"
    if [[ "$kind" == bin ]]; then
        sed -e 's@    checkupdate --unpack @    /data/sbin/checkupdate --unpack @' \
            -e "s@update_13emmc_v1.0.0_b20250703.bin@$BIN_NAME@" \
            "$TEST/check_update/check_update_bin/check_update.sh" > "$dir/check_update.sh"
    else
        install -m 755 "$TEST/check_update/check_update_tar/check_update.sh" "$dir/check_update.sh"
    fi
    chmod 755 "$dir/check_update.sh"
done
manifest
tar -czf "$ROOT/out/ddr-p5-tools.tar.gz" -C "$STAGE" ddr_p5
install -m 644 "$BIN_SOURCE/$BIN_NAME" "$PKG/check_update/check_update_bin/"
install -m 644 "$TEST/check_update/check_update_tar/update.tar.bz2" "$PKG/check_update/check_update_tar/"
for kind in bin tar; do
    source_dir="$TEST/check_update/check_update_$kind"
    [[ "$kind" != bin ]] || source_dir="$BIN_SOURCE"
    sed 's/\r$//' "$source_dir/md5_update_x6_v2.1.2_b20201127.txt" \
        > "$PKG/check_update/check_update_$kind/md5_update_x6_v2.1.2_b20201127.txt"
done
manifest
tar -czf "$ROOT/out/ddr-p5-full.tar.gz" -C "$STAGE" ddr_p5
(
    cd "$ROOT/out"
    sha256sum ddr-p5-tools.tar.gz ddr-p5-full.tar.gz > ddr-p5-bundles.sha256
)
printf 'Built tools and full bundles in %s/out (not transferred or run on board).\n' "$ROOT"
