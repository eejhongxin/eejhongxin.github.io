#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
STAGE=$(mktemp -d "$ROOT/out/ddr-build/boot.XXXXXX")
trap 'rm -rf -- "$STAGE"' EXIT
install -m 755 "$ROOT/rootfs/etc/init.d/ddr_boot_prepare.sh" "$STAGE/"
install -m 755 "$ROOT/tools/install-ddr-boot.sh" "$ROOT/tools/ddr_autostart.sh" "$STAGE/"
tar -czf "$ROOT/out/ddr-p5-boot.tar.gz" -C "$STAGE" \
    install-ddr-boot.sh ddr_boot_prepare.sh ddr_autostart.sh
sha256sum "$ROOT/out/ddr-p5-boot.tar.gz"
