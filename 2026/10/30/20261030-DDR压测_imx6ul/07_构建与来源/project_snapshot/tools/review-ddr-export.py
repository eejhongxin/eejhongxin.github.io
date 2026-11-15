#!/usr/bin/env python3
"""Review local DDR exports; write summaries without changing raw data."""

import argparse
import json
import re
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo


OOM = re.compile(r"invoked oom-killer|Out of memory|Killed process|page allocation failure", re.I)
STORAGE = re.compile(r"Corrupted directory|I/O error|Buffer I/O error", re.I)
MEM_ERROR = re.compile(r"FAILURE|\bKilled\b|\bfailed\b|\bcannot\b|\bunable\b", re.I)
MEM_TESTS = {"Stuck Address", "Random Value", "Compare XOR", "Compare SUB", "Compare MUL",
             "Compare DIV", "Compare OR", "Compare AND", "Sequential Increment", "Solid Bits",
             "Block Sequential", "Checkerboard", "Bit Spread", "Bit Flip", "Walking Ones",
             "Walking Zeroes", "8-bit Writes", "16-bit Writes"}


def read(path):
    return path.read_text(errors="replace").replace("\r", "") if path.is_file() else ""


def normalize_terminal(text):
    """Apply memtester's backspaces so final test names/results stay readable."""
    result = []
    for char in text:
        if char == "\b":
            if result and result[-1] != "\n":
                result.pop()
        else:
            result.append(char)
    return "".join(result)


def mem_review(path):
    text = normalize_terminal(read(path))
    ok_lines = [line.strip() for line in text.splitlines()
                if re.match(r"^\s*[^:]+:\s*ok\s*$", line)]
    test_names = {line.split(":", 1)[0].strip() for line in ok_lines}
    errors = [line[:500] for line in text.splitlines() if MEM_ERROR.search(line)]
    done = bool(re.search(r"^Done\.\s*$", text, re.M))
    locked = "trying mlock ...locked." in text
    allocated = re.search(r"got\s+(\d+)MB", text)
    return {"file": path.name, "present": path.is_file(), "ok_count": len(ok_lines),
            "ok_tests": ok_lines, "done": done, "mlock_locked": locked,
            "allocated_MiB": int(allocated[1]) if allocated else None,
            "errors": errors, "pass": len(ok_lines) == 18 and test_names == MEM_TESTS
            and done and locked and not errors}


def sat_review(path):
    text = read(path)
    statuses = re.findall(r"Status:\s*(\S+)", text)
    stats = re.findall(r"Stats: Completed:.*?with\s+(\d+)\s+hardware incidents,\s+(\d+)\s+errors", text)
    speed = re.findall(r"Stats: Memory Copy:.*?at\s+([\d.]+)MB/s", text)
    zero_errors = bool(stats) and all(int(i) == 0 and int(e) == 0 for i, e in stats)
    return {"file": path.name, "present": path.is_file(), "statuses": statuses,
            "hardware_incidents_errors": [[int(i), int(e)] for i, e in stats],
            "zero_errors": zero_errors,
            "memory_copy_MBps": float(speed[-1]) if speed else None,
            "pass": bool(statuses) and all(x == "PASS" for x in statuses) and zero_errors}


def counter(path):
    text = read(path).strip()
    return int(text) if text.isdigit() else None


def batch_review(path, chip, root):
    total = read(path / "ddr_log.log")
    console = read(path / "console.log")
    markers = list(re.finditer(r"^-+count:\s*(\d+)-*\s*$", total, re.M))
    indices = [int(m[1]) for m in markers]
    file_indices = set()
    for pattern in ("stressapptest_*.log", "memtester_*.log"):
        for p in path.glob(pattern):
            match = re.search(r"_(\d+)\.log$", p.name)
            if match:
                file_indices.add(int(match[1]))
    rounds = []
    segments = {}
    for i, marker in enumerate(markers):
        segments.setdefault(int(marker[1]), []).append(
            total[marker.end():markers[i + 1].start() if i + 1 < len(markers) else len(total)])
    for i in sorted(set(indices) | file_indices):
        segment = "\n".join(segments.get(i, []))
        rounds.append({"index": i, "display_round": i + 1,
                       "stressapptest": sat_review(path / f"stressapptest_{i}.log"),
                       "memtester": mem_review(path / f"memtester_{i}.log"),
                       "summary_sat_pass": "ddr stressapptest result: PASS" in segment,
                       "bin_success": "unpack bin test: Success" in segment,
                       "tar_success": "unpack tar test: Success" in segment})
    temps = [float(x) for x in re.findall(r"CPU temperature:\s*(-?[\d.]+)\s*C", total)]
    kernel = []
    for p in sorted(path.glob("kernel*.log")):
        lines = read(p).splitlines()
        kernel.append({"file": p.name, "oom_lines": [x for x in lines if OOM.search(x)],
                       "storage_error_lines": [x for x in lines if STORAGE.search(x)]})
    oom = any(x["oom_lines"] for x in kernel)
    storage = any(x["storage_error_lines"] for x in kernel)
    exit_code = counter(path / "runner_exit_code")
    end = bool(re.search(r"\bddr test end\b|ddr test\s+end time:", total))
    expected_match = re.search(r"Autotest rounds=(\d+)", console)
    expected = int(expected_match[1]) if expected_match else None
    sequential = bool(indices) and indices == list(range(len(indices)))
    all_stages = bool(rounds) and all(
        r["stressapptest"]["pass"] and r["memtester"]["pass"] and
        r["bin_success"] and r["tar_success"] for r in rounds)
    bin_count = counter(path / "unpack_bin/check_result")
    tar_count = counter(path / "unpack_tar/check_result")
    counters_ok = bin_count == 1000 and tar_count == 100
    issues = []
    if not sequential:
        issues.append("轮次标记缺失、不连续或重复")
    if expected is not None and len(rounds) != expected:
        issues.append(f"声明轮数{expected}与日志轮数{len(rounds)}不符")
    if not all_stages:
        issues.append("至少一个测试阶段未完成、失败或缺少证据")
    if exit_code != 0:
        issues.append("runner退出码不是0或未保存")
    if not counters_ok:
        issues.append("最终BIN/TAR计数不是1000/100或未保存")
    if not kernel:
        issues.append("测试内核日志未保存，无法核对OOM与I/O异常")
    if oom:
        issues.append("保存的测试内核日志有OOM/杀进程/分配失败")
    if storage:
        issues.append("保存的测试内核日志有目录损坏/I/O错误")
    passed = end and not issues
    parts = path.relative_to(chip).parts
    archived = "ddr_backup" in parts or (parts and parts[0] in ("roomtemp", "hightemp", "lowtemp"))
    return {"chip": chip.name, "path": path.relative_to(root).as_posix(),
            "kind": "archived" if archived else "active_snapshot",
            "state": "complete" if end else "incomplete",
            "verdict": "software_checks_pass" if passed else
                       "completed_with_issues" if end else "incomplete",
            "has_end_marker": end, "runner_exit_code": exit_code,
            "started_indices": indices, "expected_rounds_from_console": expected,
            "round_count": len(rounds), "rounds": rounds,
            "sat_pass_count": sum(r["stressapptest"]["pass"] for r in rounds),
            "memtester_pass_count": sum(r["memtester"]["pass"] for r in rounds),
            "bin_success_count": sum(r["bin_success"] for r in rounds),
            "tar_success_count": sum(r["tar_success"] for r in rounds),
            "final_bin_count": bin_count, "final_tar_count": tar_count,
            "cpu_temperatures_C": temps,
            "cpu_temperature_range_C": [min(temps), max(temps)] if temps else None,
            "kernel_logs": kernel, "has_kernel_oom": oom,
            "has_kernel_storage_error": storage, "issues": issues,
            "last_console_lines": console.splitlines()[-3:]}


def markdown(data):
    lines = ["# 三板DDR数据回收索引", "", f"分析生成：{data['generated_at']}。", "",
             "原始数据保持不变；本索引按日志证据区分已结束与未完成批次。当前日志单独列为活动快照，"
             "不是原子文件系统快照，也不代表本次新温箱测试。温度来自CPU采样，批次温箱归属仍须核对实验记录。", "",
             "software_checks_pass要求每轮SAT PASS且0错误、memtester18项ok/Done/mlock、BIN/TAR成功、"
             "总结束、退出码0、最终计数1000/100及保存的内核日志未检出OOM/I/O异常。"
             "未检出异常不代表未保存时段一定无异常；测试结束或退出码0单独不构成通过。", ""]
    for heading, predicate in [
            ("已结束的归档批次", lambda x: x["kind"] == "archived" and x["state"] == "complete"),
            ("未完成的归档批次", lambda x: x["kind"] == "archived" and x["state"] == "incomplete"),
            ("当前日志活动快照", lambda x: x["kind"] == "active_snapshot")]:
        lines += [f"## {heading}", "", "| 芯片目录/批次 | 轮数 | SAT/memtester通过 | BIN/TAR成功 | CPU温度℃ | 结论 |",
                  "| --- | ---: | --- | --- | --- | --- |"]
        selected = [x for x in data["batches"] if predicate(x)]
        for b in selected:
            temp = b["cpu_temperature_range_C"]
            temp_text = f"{temp[0]:.2f}～{temp[1]:.2f}" if temp else "未记录"
            lines.append(f"| [{b['path']}]({b['path']}/ddr_log.log) | {b['round_count']} | "
                         f"{b['sat_pass_count']}/{b['memtester_pass_count']} | "
                         f"{b['bin_success_count']}/{b['tar_success_count']} | {temp_text} | {b['verdict']} |")
        if not selected:
            lines.append("| 无 | | | | | |")
        lines.append("")
    lines += ["详细逐轮结果、缺失证据和内核匹配原文见 `batch-review.json`。", "",
              "内存速率取自SAT的Memory Copy，表示内存拷贝吞吐，不是纯读取速度。", ""]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    args = parser.parse_args()
    root = args.root.resolve()
    if not root.is_dir():
        parser.error(f"目录不存在：{root}")
    batches = []
    for chip in sorted(root.glob("chip_*")):
        if chip.is_dir():
            for path in sorted(chip.rglob("ddr_all_test")):
                if path.is_dir():
                    batches.append(batch_review(path, chip, root))
    if not batches:
        parser.error("未找到 chip_*/.../ddr_all_test；未生成或覆盖报告")
    data = {"schema_version": 1, "generated_at": datetime.now(ZoneInfo("Asia/Shanghai")).isoformat(),
            "root": str(root), "batches": batches}
    (root / "batch-review.json").write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    (root / "README.md").write_text(markdown(data))
    print(json.dumps({"batches": len(batches),
                      "complete": sum(b["state"] == "complete" for b in batches),
                      "software_checks_pass": sum(b["verdict"] == "software_checks_pass" for b in batches)},
                     ensure_ascii=False))


if __name__ == "__main__":
    main()
