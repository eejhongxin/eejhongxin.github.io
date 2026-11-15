#!/usr/bin/env python3
"""Serial console with explicit baud switching and host ZMODEM upload."""

import argparse
import fcntl
import os
from pathlib import Path
import pty
import select
import subprocess
import sys
import termios
import time
import tty


ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--port", default="/dev/ttyUSB0")
parser.add_argument("--baud", type=int, default=115200)
parser.add_argument("--log", type=Path, default=ROOT / "out/serial-x6-fixture-transfer.log")
args = parser.parse_args()
fd = os.open(args.port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
log = args.log.open("ab", buffering=0)


def configure(speed):
    attrs = termios.tcgetattr(fd)
    attrs[0] = attrs[1] = attrs[3] = 0
    attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
    attrs[4] = attrs[5] = getattr(termios, "B" + str(speed))
    attrs[6][termios.VMIN] = attrs[6][termios.VTIME] = 0
    termios.tcsetattr(fd, termios.TCSANOW, attrs)


def send(line):
    for byte in line.encode() + b"\r":
        os.write(fd, bytes([byte]))
        time.sleep(0.003)


current_baud = args.baud
configure(current_baud)
print(f"OPEN {args.port} {args.baud}. /baud SPEED, /hostbaud SPEED, /cancel, /send ARCHIVE, /quit", flush=True)
try:
    while True:
        ready, _, _ = select.select([fd, sys.stdin], [], [], 1)
        if fd in ready:
            data = os.read(fd, 65536)
            log.write(data)
            sys.stdout.buffer.write(data)
            sys.stdout.buffer.flush()
        if sys.stdin not in ready:
            continue
        line = sys.stdin.readline()
        if not line or line.strip() == "/quit":
            break
        line = line.rstrip("\r\n")
        if line == "/cancel":
            os.write(fd, b"\x18" * 10)
            time.sleep(0.3)
            os.write(fd, b"\x03\r")
        elif line.startswith("/hostbaud "):
            current_baud = int(line.split()[1])
            configure(current_baud)
        elif line.startswith("/baud "):
            speed = int(line.split()[1])
            getattr(termios, "B" + str(speed))
            send(f"stty -F /dev/ttymxc0 {speed}")
            time.sleep(0.3)
            configure(speed)
            current_baud = speed
            send("")
            print(f"HOST BAUD {speed}", flush=True)
        elif line.startswith("/send "):
            archive = Path(line[6:]).resolve()
            if not archive.is_file():
                print("ERROR: archive missing", flush=True)
                continue
            sender = ROOT / "out/ddr-build/host-lrzsz/usr/bin/sz"
            send("lrz -b -Z -y -e -w 4096")
            os.set_blocking(fd, True)
            start = time.monotonic()
            master, slave = pty.openpty()
            tty.setraw(slave)
            # Keep sz's terminal mode changes away from the USB serial device.
            process = subprocess.Popen([str(sender), "-b", "-y", "-q", "-e", "-w", "4096", str(archive)],
                                       stdin=slave, stdout=slave, stderr=subprocess.PIPE)
            os.close(slave)
            diagnostics = bytearray()
            sent = received = 0
            last_report = start
            try:
                while process.poll() is None:
                    ready, _, _ = select.select([fd, master, process.stderr], [], [], 1)
                    for source in ready:
                        try:
                            data = os.read(source if isinstance(source, int) else source.fileno(), 4096)
                        except OSError:
                            continue
                        if source == fd:
                            received += len(data)
                            os.write(master, data)
                        elif source == master:
                            sent += len(data)
                            os.write(fd, data)
                        else:
                            diagnostics.extend(data)
                    now = time.monotonic()
                    if now - start >= 3600 or (now - start >= 25 and sent < 2048):
                        print("ERROR: transfer timeout or handshake stalled", flush=True)
                        process.kill()
                    if now - last_report >= 30:
                        print(f"ZMODEM elapsed={int(now-start)}s wire_sent={sent} wire_received={received}", flush=True)
                        last_report = now
                process.wait()
                ready, _, _ = select.select([master], [], [], 0)
                if ready:
                    try:
                        os.write(fd, os.read(master, 4096))
                    except OSError:
                        pass
                diagnostics.extend(process.stderr.read())
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait()
                process.stderr.close()
                os.close(master)
                os.set_blocking(fd, False)
                configure(current_baud)
            log.write(diagnostics)
            print(f"ZMODEM exit={process.returncode}; elapsed={time.monotonic()-start:.1f}s",
                  diagnostics.decode(errors="replace"), flush=True)
            if process.returncode:
                os.write(fd, b"\x18" * 10 + b"\x03\r")
        else:
            send(line)
finally:
    os.close(fd)
    log.close()
