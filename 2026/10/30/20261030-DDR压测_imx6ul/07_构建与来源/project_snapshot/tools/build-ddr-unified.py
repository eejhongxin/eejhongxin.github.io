#!/usr/bin/env python3
"""Repackage verified ARM tools and fixtures into the single P5 DDR bundle."""

import argparse
import gzip
import hashlib
import io
import os
from pathlib import Path, PurePosixPath
import subprocess
import tarfile
import tempfile


ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "out"
BASELINE = OUT / "ddr-build/unified-base-full.tar.gz"
BASELINE_SHA256 = "ff656a92e74e848bb6507ab4f090fb2613b56bcfd95b03eab7ac79cbaa920907"
DEFAULT_OUTPUT = OUT / "ddr-p5-full.tar.gz"


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def member_name(name):
    path = PurePosixPath(name)
    if path.is_absolute() or ".." in path.parts or "\\" in name:
        raise ValueError(f"Unsafe archive member: {name!r}")
    normalized = str(path)
    if normalized != "ddr_p5" and not normalized.startswith("ddr_p5/"):
        raise ValueError(f"Member outside ddr_p5/: {name!r}")
    return normalized


def read_bundle(path):
    files = {}
    seen = set()
    with tarfile.open(path, "r:gz") as archive:
        for member in archive.getmembers():
            name = member_name(member.name)
            if name in seen:
                raise ValueError(f"Duplicate archive member: {name}")
            seen.add(name)
            if member.isdir():
                continue
            if not member.isfile():
                raise ValueError(f"Links and special files are not accepted: {name}")
            data = archive.extractfile(member).read()
            files[name] = (data, member.mode & 0o777)
    verify_manifest(files)
    return files


def verify_manifest(files):
    manifest_name = "ddr_p5/SHA256SUMS"
    if manifest_name not in files:
        raise ValueError("Bundle has no SHA256SUMS")
    checked = set()
    for line in files[manifest_name][0].decode("utf-8").splitlines():
        if not line.strip():
            continue
        expected, relative = line.split(maxsplit=1)
        if len(expected) != 64 or any(c not in "0123456789abcdef" for c in expected):
            raise ValueError("Invalid SHA256 in bundle manifest")
        relative = relative.removeprefix("*")
        name = member_name("ddr_p5/" + relative)
        if name == manifest_name or name in checked:
            raise ValueError(f"Invalid duplicate/self manifest entry: {relative}")
        if name not in files or sha256(files[name][0]) != expected:
            raise ValueError(f"Bundle checksum mismatch: {relative}")
        checked.add(name)
    expected_files = set(files) - {manifest_name}
    if checked != expected_files:
        raise ValueError(f"Bundle manifest coverage mismatch: {sorted(expected_files ^ checked)}")


def atomic_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix="." + path.name + ".", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def baseline_files():
    source = BASELINE if BASELINE.is_file() else DEFAULT_OUTPUT
    if not source.is_file():
        raise ValueError(f"Verified baseline bundle missing: {source}")
    data = source.read_bytes()
    if sha256(data) != BASELINE_SHA256:
        raise ValueError(f"Baseline SHA256 mismatch: {source}; original full bundle is required")
    files = read_bundle(source)
    if not BASELINE.exists():
        atomic_write(BASELINE, data)
    checksum = f"{BASELINE_SHA256}  {BASELINE.name}\n".encode("ascii")
    atomic_write(Path(str(BASELINE) + ".sha256"), checksum)
    return files


def build(output):
    # Read every input before creating or replacing the output bundle.
    overlays = {}
    test = ROOT / "testcase_linux/minimum_system_test/ddr_test/p5"
    for name in ("ddr_test.sh", "ddr_progress.sh", "ddr_mem_usage.sh", "wtd_feed.sh"):
        overlays["ddr_p5/" + name] = (test / name).read_bytes()
    for source, name in (
        ("tools/ddr-run.sh", "run.sh"),
        ("tools/ddr-unified-install.sh", "boot/install.sh"),
        ("tools/ddr-unified-boot.sh", "boot/prepare.sh"),
    ):
        overlays["ddr_p5/" + name] = (ROOT / source).read_bytes()
    readme = (ROOT / "tools/DDR-P5-UNIFIED.md").read_bytes()
    for name, data in overlays.items():
        subprocess.run(["sh", "-n"], input=data, check=True, capture_output=True)
    files = baseline_files()
    for name, data in overlays.items():
        files[name] = (data, 0o755)
    files["ddr_p5/README.md"] = (readme, 0o644)
    files.pop("ddr_p5/SHA256SUMS", None)
    manifest = "".join(
        f"{sha256(data)}  ./{name.removeprefix('ddr_p5/')}\n"
        for name, (data, _) in sorted(files.items())
    ).encode("utf-8")
    files["ddr_p5/SHA256SUMS"] = (manifest, 0o644)
    verify_manifest(files)

    output.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix="." + output.name + ".", dir=output.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            with gzip.GzipFile(fileobj=stream, mode="wb", filename="", mtime=0) as compressed:
                with tarfile.open(fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT) as archive:
                    for name, (data, mode) in sorted(files.items()):
                        info = tarfile.TarInfo(name)
                        info.size = len(data)
                        info.mode = mode
                        info.uid = info.gid = info.mtime = 0
                        info.uname = info.gname = ""
                        archive.addfile(info, io.BytesIO(data))
            stream.flush()
            os.fsync(stream.fileno())
        verified = read_bundle(temporary)
        if verified != files:
            raise ValueError("Repacked bundle differs from inputs")
        digest = sha256(Path(temporary).read_bytes())
        os.replace(temporary, output)
        atomic_write(Path(str(output) + ".sha256"), f"{digest}  {output.name}\n".encode("utf-8"))
        print(f"Built: {output}")
        print(f"Files: {len(files)}; verified manifest entries: {len(files) - 1}")
        print(f"Bytes: {output.stat().st_size}; SHA256: {digest}")
        print("Existing ARM tools and fixtures reused; no board connected and no test started.")
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT,
                        help="Output archive (default: out/ddr-p5-full.tar.gz)")
    args = parser.parse_args()
    output = args.output.expanduser().resolve()
    if output == BASELINE.resolve():
        parser.error("Output must not overwrite the verified baseline cache")
    try:
        build(output)
    except (OSError, ValueError, subprocess.CalledProcessError, tarfile.TarError) as error:
        parser.exit(1, f"ERROR: {error}\n")


if __name__ == "__main__":
    main()
