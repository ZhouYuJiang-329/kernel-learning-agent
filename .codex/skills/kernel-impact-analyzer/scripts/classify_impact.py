#!/usr/bin/env python3
"""
classify_impact.py — 将 call_chain_up / find_callers 输出按深度分级并去重

用法：
  python3 classify_impact.py <input_file>

input_file 格式（纯文本，每行一条记录，格式如下）：
  depth=1  func_name  file:line
  depth=2  func_name  file:line
  depth=3  func_name  file:line
  ...

其中 depth 来自 call_chain_up 结果的层级编号。
find_callers 的直接调用者统一视为 depth=1 输入。

若无文件参数，从 stdin 读取。

输出：按 Level 1/2/3 分组的 markdown 表格，已去重（同一函数名只出现在最低 Level）。
"""

import sys
import re

HOT_PATH_KEYWORDS = [
    "__schedule", "pick_next_task", "enqueue_task", "dequeue_task",
    "schedule_tick", "scheduler_tick",
]
SMP_SENSITIVE_KEYWORDS = [
    "rq_lock", "rq_unlock", "raw_spin_lock", "raw_spin_unlock",
    "cpu_rq", "this_rq",
]
RT_SENSITIVE_KEYWORDS = ["rt_rq", "dl_rq", "sched_rt", "sched_dl"]
MPAM_SENSITIVE_KEYWORDS = [
    "rdtgroup", "resctrl", "closid", "rmid", "rdt_resource",
    "resctrl_schema", "mpam",
]

def tag(func_name: str) -> str:
    tags = []
    fl = func_name.lower()
    if any(k in fl for k in HOT_PATH_KEYWORDS):
        tags.append("HOT_PATH")
    if any(k in fl for k in SMP_SENSITIVE_KEYWORDS):
        tags.append("SMP_SENSITIVE")
    if any(k in fl for k in RT_SENSITIVE_KEYWORDS):
        tags.append("RT_SENSITIVE")
    if any(k in fl for k in MPAM_SENSITIVE_KEYWORDS):
        tags.append("MPAM_SENSITIVE")
    return " ".join(tags) if tags else "-"

def parse_lines(lines):
    """
    解析输入行，返回 list of (depth, func_name, location)
    支持两种格式：
      depth=N  func_name  file:line
      func_name  file:line        (视为 depth=1，来自 find_callers)
    """
    entries = []
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        m = re.match(r"depth=(\d+)\s+(\S+)\s*(.*)", line)
        if m:
            entries.append((int(m.group(1)), m.group(2), m.group(3).strip()))
            continue
        # 无 depth 前缀 → find_callers 输出，视为 depth=1
        parts = line.split(None, 1)
        if parts:
            entries.append((1, parts[0], parts[1].strip() if len(parts) > 1 else "-"))
    return entries

def classify(entries):
    """
    按 depth 分级（1 → L1，2 → L2，3-5 → L3），同一函数只保留最低 Level。
    返回 {1: [...], 2: [...], 3: [...]}，每项为 (func_name, location, tags)
    """
    best = {}  # func_name → (depth, location)
    for depth, func, loc in entries:
        if func not in best or depth < best[func][0]:
            best[func] = (depth, loc)

    levels = {1: [], 2: [], 3: []}
    for func, (depth, loc) in sorted(best.items(), key=lambda x: (x[1][0], x[0])):
        level = 1 if depth == 1 else (2 if depth == 2 else 3)
        levels[level].append((func, loc, tag(func)))
    return levels

def render(levels):
    lines = []
    label = {1: "Level 1 — 直接调用者（P0 必测）",
             2: "Level 2 — 间接调用者（P1 建议测试）",
             3: "Level 3 — 远程影响（P2 回归）"}
    for lv in [1, 2, 3]:
        items = levels[lv]
        lines.append(f"## {label[lv]}\n")
        if not items:
            lines.append("（无）\n")
        else:
            lines.append("| 函数名 | 文件:行号 | 风险标签 |")
            lines.append("|--------|---------|---------|")
            for func, loc, tags in items:
                lines.append(f"| {func} | {loc or '-'} | {tags} |")
        lines.append("")
    return "\n".join(lines)

if __name__ == "__main__":
    if len(sys.argv) > 1:
        with open(sys.argv[1]) as f:
            raw = f.readlines()
    else:
        raw = sys.stdin.readlines()

    entries = parse_lines(raw)
    if not entries:
        print("error: no valid input entries found", file=sys.stderr)
        sys.exit(1)

    levels = classify(entries)
    print(render(levels))
