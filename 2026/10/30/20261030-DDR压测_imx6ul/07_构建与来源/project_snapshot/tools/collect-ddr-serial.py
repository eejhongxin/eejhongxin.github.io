#!/usr/bin/env python3
"""Collect DDR evidence over UART without stopping the board's running test.

Creates only a temporary export directory on the board; source logs/configuration
are never changed. Backup logs are checked against before/after SHA256 lists.
The currently running test is explicitly a non-atomic tar snapshot.
"""

import argparse
import base64
import binascii
import fcntl
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import select
import tarfile
import termios
import time
import uuid


class Serial:
    def __init__(self, port, output, timeout):
        self.fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
        try:
            fcntl.flock(self.fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.attrs = termios.tcgetattr(self.fd)
            attrs = termios.tcgetattr(self.fd)
            attrs[0] = attrs[1] = attrs[3] = 0
            attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
            attrs[4] = attrs[5] = termios.B115200
            attrs[6][termios.VMIN] = attrs[6][termios.VTIME] = 0
            termios.tcsetattr(self.fd, termios.TCSANOW, attrs)
            self.raw = (output / "raw.serial.log").open("wb", buffering=0)
        except BaseException:
            os.close(self.fd)
            raise
        self.deadline = time.monotonic() + timeout
        self.buffer = bytearray()
        self.received = 0
        self.last_progress = time.monotonic()

    def close(self):
        try:
            termios.tcsetattr(self.fd, termios.TCSANOW, self.attrs)
        finally:
            os.close(self.fd)
            self.raw.close()

    def read(self, deadline):
        now = time.monotonic()
        if now >= min(deadline, self.deadline):
            raise TimeoutError("UART response/global deadline expired")
        ready, _, _ = select.select([self.fd], [], [], min(1, deadline - now))
        if ready:
            data = os.read(self.fd, 65536)
            if not data:
                raise RuntimeError("UART disconnected")
            self.raw.write(data)
            self.buffer.extend(data)
            self.received += len(data)
        if now - self.last_progress >= 20:
            print(f"UART received {self.received} bytes", flush=True)
            self.last_progress = now

    def send(self, line):
        data = line.encode("ascii")
        if len(data) >= 400 or b"\n" in data or b"\r" in data:
            raise ValueError("Every board command must be a single line <400 bytes")
        for value in data + b"\r":
            if time.monotonic() >= self.deadline:
                raise TimeoutError("Global deadline expired while sending")
            os.write(self.fd, bytes([value]))
            time.sleep(0.003)

    def probe(self):
        self.send("")
        deadline = time.monotonic() + 12
        while True:
            data = bytes(self.buffer).replace(b"\r", b"")
            if re.search(rb"(?:^|\n)(?:root@[^\n]{0,120})?[^\n]{0,80}# $", data):
                self.buffer.clear()
                return
            if len(data) > 1024:
                bad = sum(x < 9 or x > 126 for x in data)
                if bad > len(data) // 10:
                    raise RuntimeError("UART contains unreadable data; stopping")
            self.read(deadline)

    def command(self, source, timeout=45, allowed=(0,)):
        token = "DDR_" + uuid.uuid4().hex[:18]
        begin, end = token + "_BEGIN", token + "_END:"
        framed = (f"printf '\\n{begin}\\n'; {source}; "
                  f"DDR_RC=$?; printf '\\n{end}%s\\n' \"$DDR_RC\"")
        self.send(framed)
        deadline = min(self.deadline, time.monotonic() + timeout)
        started, lines = False, []
        while True:
            while b"\n" in self.buffer:
                line, _, rest = self.buffer.partition(b"\n")
                self.buffer = bytearray(rest)
                line = bytes(line).replace(b"\r", b"")
                if not started:
                    if line == begin.encode():
                        started = True
                    continue
                if line.startswith(end.encode()):
                    code = int(line[len(end):])
                    if code not in allowed:
                        raise RuntimeError(f"Board command exit {code}: {source}")
                    return b"\n".join(lines), code
                lines.append(line)
            self.read(deadline)


def decode_payload(payload):
    try:
        return base64.b64decode(b"".join(payload.splitlines()), validate=True)
    except (ValueError, binascii.Error) as exc:
        raise RuntimeError("UART base64 payload is not intact") from exc


def safe_extract(archive, destination):
    destination.mkdir()
    with tarfile.open(archive, "r:gz") as stream:
        members = stream.getmembers()
        seen = set()
        for member in members:
            name = PurePosixPath(member.name)
            if name.is_absolute() or ".." in name.parts:
                raise RuntimeError(f"Unsafe archive path: {member.name}")
            if not (member.isfile() or member.isdir()):
                raise RuntimeError(f"Links/special files forbidden: {member.name}")
            key = str(name)
            if key in seen:
                raise RuntimeError(f"Duplicate archive member: {member.name}")
            seen.add(key)
        # Extract manually so no archived ownership, permissions or link is applied.
        for member in members:
            target = destination / member.name
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with stream.extractfile(member) as src, target.open("xb") as dst:
                    while chunk := src.read(1024 * 1024):
                        dst.write(chunk)


def manifest_entries(data):
    result = {}
    for line in data.decode("utf-8", errors="strict").splitlines():
        match = re.fullmatch(r"([0-9a-fA-F]{64})  (.+)", line)
        if not match:
            raise RuntimeError("Malformed board SHA256 manifest")
        digest, name = match.groups()
        path = PurePosixPath(name)
        if path.is_absolute() or ".." in path.parts or not name.startswith("ddr_backup/"):
            raise RuntimeError(f"Unexpected manifest path: {name}")
        if name in result:
            raise RuntimeError(f"Duplicate manifest entry: {name}")
        result[name] = digest.lower()
    return result


def collect(args):
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if any(output.iterdir()):
        raise RuntimeError("Output directory must be empty (never overwrite evidence)")
    report = {"port": args.port, "expected_id": args.expected_id,
              "status": "started", "active_snapshot_atomic": False,
              "active_snapshot_note": "Live files may change during tar; no test stopped."}
    uart = None
    try:
        uart = Serial(args.port, output, args.timeout)
        uart.probe()
        identity, _ = uart.command("cat /sys/fsl_otp/HW_OCOTP_CFG1", timeout=12)
        actual = identity.decode("ascii").strip()
        if int(actual, 0) != int(args.expected_id, 0):
            raise RuntimeError(f"Board identity mismatch: expected {args.expected_id}, got {actual}")
        report["board_id"] = actual
        print(f"Confirmed board {actual} on {args.port}", flush=True)
        # Use the packaged BusyBox explicitly; it provides base64 on these boards.
        uart.command("DDR_BB=/mnt/ddr_work/full/ddr_p5/libexec/busybox; test -x \"$DDR_BB\"")
        uart.command("awk '$2==\"/mnt\"&&$1==\"/dev/mmcblk1p7\"{ok=1} END{exit !ok}' /proc/mounts")
        uart.command("DDR_E=$(mktemp -d /tmp/ddr-export.XXXXXX); test -d \"$DDR_E\"")
        export, _ = uart.command('printf "%s\\n" "$DDR_E"')
        report["board_export_directory"] = export.decode().strip()
        uart.command('mkdir -p "$DDR_E/metadata/scripts"')
        for name in ("cmdline", "uptime", "mounts", "meminfo"):
            uart.command(f'cat /proc/{name} > "$DDR_E/metadata/{name}"')
        uart.command('dmesg > "$DDR_E/metadata/dmesg.log"')
        uart.command('ps > "$DDR_E/metadata/ps.txt"')
        sources = {
            "/mnt/ddr_work/ddr_autostart.count": "ddr_autostart.count",
            "/mnt/ddr_work/ddr_autostart.sh": "ddr_autostart.sh",
            "/etc/init.d/rcS": "rcS",
            "/etc/init.d/ddr_boot_prepare.sh": "ddr_boot_prepare.sh",
            "/etc/inittab": "inittab",
            "/tmp/ddr-boot.log": "ddr-boot.log",
            "/tmp/ddr-autotest-launch.log": "ddr-autotest-launch.log",
        }
        for source, name in sources.items():
            uart.command(f'[ ! -f {source} ] || cp {source} "$DDR_E/metadata/scripts/{name}"')
        uart.command('cd /mnt/ddr_work')
        hash_command = ('if [ -d ddr_backup ]; then find ddr_backup -type f '
                        '-exec sha256sum {} \\;; fi')
        uart.command(hash_command + ' > "$DDR_E/metadata/backup-before.sha256"', timeout=90)
        uart.command(': > "$DDR_E/list.txt"')
        for source in ("mnt/ddr_work/ddr_backup", "mnt/ddr_work/ddr_all_test"):
            uart.command(f'[ ! -d /{source} ] || echo {source} >> "$DDR_E/list.txt"')
        uart.command('echo "${DDR_E#/}/metadata" >> "$DDR_E/list.txt"')
        if args.include_unpack:
            # Reference original evidence directly; never copy raw payloads to RAM.
            for kind in ("bin", "tar"):
                for name in ("check_result", "updateback"):
                    source = f"tmp/check_update_{kind}/{name}"
                    uart.command(f'[ ! -e /{source} ] || echo {source} >> "$DDR_E/list.txt"')
        print("Compressing log snapshot directly into /tmp (no raw-directory copy)", flush=True)
        tar_output, tar_code = uart.command(
            '"$DDR_BB" tar -czf "$DDR_E/board.tar.gz" -C / -T "$DDR_E/list.txt"',
            timeout=120, allowed=(0, 1))
        report["tar_exit_code"] = tar_code
        report["tar_output"] = tar_output.decode(errors="replace")
        uart.command(hash_command + ' > "$DDR_E/backup-after.sha256"', timeout=90)
        size, _ = uart.command('wc -c < "$DDR_E/board.tar.gz"')
        expected_size = int(size.strip())
        if expected_size > 32 * 1024 * 1024:
            raise RuntimeError("Compressed evidence exceeds 32 MiB; left on board without transfer")
        digest, _ = uart.command('sha256sum "$DDR_E/board.tar.gz"')
        expected_digest = digest.decode().split()[0]
        report.update(archive_bytes=expected_size, archive_board_sha256=expected_digest)
        print(f"Transferring {expected_size} compressed bytes", flush=True)
        payload, _ = uart.command('"$DDR_BB" base64 "$DDR_E/board.tar.gz"', timeout=args.timeout)
        archive_bytes = decode_payload(payload)
        if len(archive_bytes) != expected_size:
            raise RuntimeError("Archive byte count differs from board")
        if hashlib.sha256(archive_bytes).hexdigest() != expected_digest:
            raise RuntimeError("Archive SHA256 differs from board")
        archive = output / "board.tar.gz"
        archive.write_bytes(archive_bytes)
        after_payload, _ = uart.command('"$DDR_BB" base64 "$DDR_E/backup-after.sha256"')
        after = decode_payload(after_payload)
        (output / "backup-after.sha256").write_bytes(after)
        extracted = output / "extracted"
        safe_extract(archive, extracted)
        metadata = extracted / report["board_export_directory"].lstrip("/") / "metadata"
        before = (metadata / "backup-before.sha256").read_bytes()
        (output / "backup-before.sha256").write_bytes(before)
        before_entries, after_entries = manifest_entries(before), manifest_entries(after)
        report["backup_manifest_unchanged"] = before_entries == after_entries
        if before_entries != after_entries:
            raise RuntimeError("Backup files changed during export; snapshot requires review")
        extracted_backup = extracted / "mnt/ddr_work/ddr_backup"
        extracted_names = {
            "ddr_backup/" + path.relative_to(extracted_backup).as_posix()
            for path in extracted_backup.rglob("*") if path.is_file()
        }
        if extracted_names != set(before_entries):
            raise RuntimeError("Extracted backup file set differs from SHA256 manifest")
        failures = []
        for name, digest in before_entries.items():
            path = extracted / "mnt/ddr_work" / name
            if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
                failures.append(name)
        report["backup_files_verified"] = len(before_entries)
        report["backup_verification_failures"] = failures
        if failures:
            raise RuntimeError("Extracted backup file SHA256 mismatch")
        report["status"] = "verified"
        report["archive_host_sha256"] = hashlib.sha256(archive_bytes).hexdigest()
        print(f"Verified archive and {len(before_entries)} immutable backup files; active logs are a live snapshot", flush=True)
    except BaseException as exc:
        report["status"] = "failed"
        report["error"] = str(exc)
        raise
    finally:
        (output / "verification.json").write_text(
            json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        if uart:
            uart.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", required=True)
    parser.add_argument("--expected-id", required=True, help="HW_OCOTP_CFG1, e.g. 0x0c3599d4")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--timeout", type=int, default=300, help="Global deadline in seconds")
    parser.add_argument("--include-unpack", action="store_true", help="Include current /tmp check_result/updateback only")
    args = parser.parse_args()
    if args.timeout < 20:
        parser.error("timeout must be at least 20 seconds")
    try:
        collect(args)
    except Exception as exc:
        parser.exit(1, f"ERROR: {exc}\n")


if __name__ == "__main__":
    main()
