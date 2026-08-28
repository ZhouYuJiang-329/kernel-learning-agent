#!/usr/bin/env python3
"""
generate_tree.py — 将 dep-graph.md 的 ASCII 树与 knowledge.md 的状态表格合并，
                   输出带状态标注的知识树。

用法：
  python3 generate_tree.py <subsystem>
  python3 generate_tree.py --all

输出：带 [status, conf] 标注的 ASCII 树，有笔记的节点追加 ✓ 标记。

示例输出：
  __schedule [unknown]
    ├── pick_next_task [unknown]
    │     ├── pick_next_task_fair [exploring, 60] ✓
    │     └── pick_next_task_rt [unknown]
    └── context_switch [unknown]
"""

import sys
import re
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
MEMORY_DIR = SCRIPT_DIR / "../../../memory"


def load_knowledge(subsystem: str) -> dict:
    """从 knowledge.md 加载节点状态，返回 {func_name: (status, confidence, has_note)}"""
    km_file = MEMORY_DIR / subsystem / "knowledge.md"
    nodes = {}
    if not km_file.exists():
        return nodes
    for line in km_file.read_text().splitlines():
        if not line.startswith("| ") or "---" in line or "名称" in line:
            continue
        parts = [p.strip() for p in line.split("|")]
        # | name | type | status | confidence | note | internal_doc | date |
        if len(parts) < 7:
            continue
        name, _, status, conf, note = parts[1], parts[2], parts[3], parts[4], parts[5]
        if name and status:
            has_note = note not in ("-", "", "None")
            nodes[name] = (status, conf, has_note)
    return nodes


def annotate_line(line: str, nodes: dict) -> str:
    """在树的一行中，找到函数名并附加状态标注。"""
    # 提取行中的函数名（括号前，去除注释）
    # 格式可能是：  ├── pick_next_task_fair (CFS)
    m = re.search(r"([\w_]+)\s*(\([^)]*\))?", line)
    if not m:
        return line
    fname = m.group(1)
    if fname not in nodes:
        return line
    status, conf, has_note = nodes[fname]
    tag = f"[{status}, {conf}]" if conf and conf != "0" and conf != "-" else f"[{status}]"
    if has_note:
        tag += " ✓"
    # 插入到行末，保留原始注释
    return line.rstrip() + f"  {tag}"


def process_dep_graph(subsystem: str, nodes: dict) -> str:
    dep_file = MEMORY_DIR / subsystem / "dep-graph.md"
    if not dep_file.exists():
        return f"  (dep-graph.md 不存在：{subsystem})"

    lines = dep_file.read_text().splitlines()
    output = []
    in_code = False
    for line in lines:
        if line.strip().startswith("```"):
            in_code = not in_code
            continue
        if in_code:
            output.append(annotate_line(line, nodes))
        # 非代码块（标题、说明行）跳过
    return "\n".join(output)


def run_subsystem(subsystem: str) -> str:
    nodes = load_knowledge(subsystem)
    tree = process_dep_graph(subsystem, nodes)
    return f"### {subsystem}\n\n```\n{tree}\n```\n"


if __name__ == "__main__":
    arg = sys.argv[1] if len(sys.argv) > 1 else ""

    if not arg:
        print("usage: generate_tree.py <subsystem> | --all", file=sys.stderr)
        sys.exit(1)

    if arg == "--all":
        subsystems = sorted(
            d.name for d in MEMORY_DIR.iterdir()
            if d.is_dir() and d.name not in ("unclassified",) and (d / "dep-graph.md").exists()
        )
        for sub in subsystems:
            print(run_subsystem(sub))
    else:
        print(run_subsystem(arg))
