#!/usr/bin/env bash
# append_dep_edge.sh — 向 dep-graph.md 追加调用关系边
# 用法：append_dep_edge.sh <subsystem> <parent> <child> [<description>]
#
# 参数：
#   subsystem   — 子系统目录名，如 sched、mpam、unclassified
#   parent      — 父函数名（调用方）
#   child       — 子函数名（被调用方）
#   description — 可选，子函数说明（如 "vruntime 初始化"）
#
# 行为：
#   1. 若 parent → child 边已存在 → 跳过，输出 skipped:
#   2. 若 parent 节点存在，child 不存在 → 在 parent 最后一个子节点后追加 child
#   3. 若 parent 节点不存在 → 在文件末尾追加新根节点树
#   unclassified 子系统：正常追加，dep-graph 仅作临时记录
#
# 退出码：0=成功  1=参数错误  2=dep-graph.md 不存在  3=子系统目录不存在

set -euo pipefail

# Python 解释器探测（Windows 的 python3 常是无效 stub，实际解释器是 python）
PYTHON="${PYTHON:-python3}"
if ! command -v "$PYTHON" >/dev/null 2>&1 || ! "$PYTHON" -c 'import sys' >/dev/null 2>&1; then
    PYTHON="python"
fi
if ! command -v "$PYTHON" >/dev/null 2>&1 || ! "$PYTHON" -c 'import sys' >/dev/null 2>&1; then
    echo "error: no working Python found (tried \$PYTHON, python3, python)" >&2
    exit 1
fi
# 强制 UTF-8 模式（Windows 默认 GBK 会导致中文文件读写乱码）
export PYTHONUTF8=1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MEMORY_DIR="${SCRIPT_DIR}/../../../memory"

if [[ $# -lt 3 ]]; then
    echo "usage: append_dep_edge.sh <subsystem> <parent> <child> [<description>]" >&2
    exit 1
fi

SUBSYSTEM="$1"
PARENT="$2"
CHILD="$3"
DESC="${4:-}"

TARGET_DIR="${MEMORY_DIR}/${SUBSYSTEM}"
DEP_FILE="${TARGET_DIR}/dep-graph.md"

if [[ ! -d "$TARGET_DIR" ]]; then
    echo "error: subsystem directory not found: ${TARGET_DIR}" >&2
    exit 3
fi

if [[ ! -f "$DEP_FILE" ]]; then
    echo "error: dep-graph.md not found: ${DEP_FILE}" >&2
    exit 2
fi

"$PYTHON" - "$DEP_FILE" "$PARENT" "$CHILD" "$DESC" <<'PYEOF'
import sys
import re

dep_file = sys.argv[1]
parent   = sys.argv[2]
child    = sys.argv[3]
desc     = sys.argv[4]

child_label = f"{child} ({desc})" if desc else child

content = open(dep_file).read()
lines = content.splitlines(keepends=True)

# ── 判断 parent→child 边是否已存在 ──────────────────────────────────────
# 在代码块内查找 parent 节点后的 child 行
in_code = False
parent_found = False
for i, line in enumerate(lines):
    stripped = line.strip()
    if stripped.startswith("```"):
        in_code = not in_code
        continue
    if not in_code:
        continue
    if stripped == parent or re.match(rf"^{re.escape(parent)}\s*$", stripped):
        parent_found = True
    if parent_found and child in line:
        # child 已出现在 parent 后面，视为已存在
        print(f"skipped: {parent} → {child} (already exists)")
        sys.exit(0)

# ── 提取代码块内容，用于修改 ─────────────────────────────────────────────
# 找代码块的起止行（只处理第一个代码块）
code_start = code_end = -1
in_code = False
for i, line in enumerate(lines):
    if line.strip().startswith("```"):
        if not in_code:
            code_start = i
            in_code = True
        else:
            code_end = i
            break

if code_start == -1:
    # 没有代码块，在文件末尾新建
    if not lines or lines[-1].strip():
        lines.append("\n")
    lines.append("```\n")
    lines.append(f"{parent}\n")
    child_line = f"  └── {child_label}\n"
    lines.append(child_line)
    lines.append("```\n")
    with open(dep_file, 'w') as f:
        f.writelines(lines)
    print(f"appended: new root {parent} → {child}")
    sys.exit(0)

code_lines = lines[code_start+1:code_end]

# ── 在代码块内查找 parent 节点位置 ──────────────────────────────────────
parent_idx = -1  # 相对于 code_lines 的下标
for i, line in enumerate(code_lines):
    stripped = line.rstrip('\n')
    # 去掉 tree 前缀符号，取函数名部分
    name_part = re.sub(r'^[\s│├└─]+', '', stripped).split('(')[0].strip()
    if name_part == parent:
        parent_idx = i
        break

if parent_idx == -1:
    # parent 不在代码块中 → 在代码块末尾追加新根节点
    # 找代码块最后一个非空行
    last_content = len(code_lines)
    for i in range(len(code_lines)-1, -1, -1):
        if code_lines[i].strip():
            last_content = i + 1
            break
    insert_at = code_start + 1 + last_content
    new_tree = f"\n{parent}\n  └── {child_label}\n"
    lines.insert(insert_at, new_tree)
    with open(dep_file, 'w') as f:
        f.writelines(lines)
    print(f"appended: new root {parent} → {child}")
    sys.exit(0)

# parent 存在 → 找 parent 块的末尾（下一个同级或更高级的节点前）
parent_line = code_lines[parent_idx]
parent_indent = len(parent_line) - len(parent_line.lstrip())

# parent 的子节点缩进比 parent 更深；找到下一个缩进 ≤ parent_indent 的行
block_end = len(code_lines)
for i in range(parent_idx + 1, len(code_lines)):
    stripped = code_lines[i].rstrip('\n')
    if not stripped:
        continue
    cur_indent = len(stripped) - len(stripped.lstrip('│ '))
    # tree 字符：├ └ │ 算缩进
    cur_indent = len(re.match(r'^[\s│]*', stripped).group(0))
    if cur_indent <= parent_indent and re.sub(r'^[\s│├└─]+', '', stripped).strip():
        block_end = i
        break

# 找 block_end 前最后一个有内容的行，在其后插入
last_in_block = block_end - 1
for i in range(block_end - 1, parent_idx, -1):
    if code_lines[i].strip():
        last_in_block = i
        break

# 构造新子节点行，缩进 = parent_indent + 2（标准树缩进）
child_indent = ' ' * (parent_indent + 2)
child_line_str = f"{child_indent}└── {child_label}\n"

# 将已有子节点的最后一个 └── 换成 ├──（若需要）
# 找 parent 块最后一个 "└──" 行改为 "├──"
for i in range(last_in_block, parent_idx, -1):
    if '└──' in code_lines[i]:
        code_lines[i] = code_lines[i].replace('└──', '├──', 1)
        break

insert_abs = code_start + 1 + last_in_block + 1
code_lines.insert(last_in_block + 1, child_line_str)

# 重写文件
new_lines = lines[:code_start+1] + code_lines + lines[code_end:]
with open(dep_file, 'w') as f:
    f.writelines(new_lines)

print(f"appended: {parent} → {child}")
PYEOF
