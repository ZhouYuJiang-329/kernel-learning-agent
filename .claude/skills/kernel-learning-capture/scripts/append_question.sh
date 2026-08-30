#!/usr/bin/env bash
# append_question.sh — 向 open-questions.md 追加一个新问题
#
# 用法：
#   append_question.sh <priority> <question> <source> <related> <assumption> <query>
#
# 参数：
#   priority   — CRITICAL | MEDIUM | LOW
#   question   — 问题描述
#   source     — 来源（如 "2026-07-01 分析 enqueue_task_fair 时发现"）
#   related    — 相关函数（如 "enqueue_task_fair, update_curr"）
#   assumption — 当前假设（无则传 "-"）
#   query      — 建议查询命令（如 "call_chain_down(enqueue_task_fair, depth=2)"）
#
# 退出码：0=成功  1=参数错误  2=文件不存在  3=优先级无效

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

MEMORY_DIR="$(dirname "$0")/../../../memory"
OQ_FILE="${MEMORY_DIR}/open-questions.md"
DATE=$(date +%Y-%m-%d)

# 参数校验
if [[ $# -lt 6 ]]; then
    echo "usage: append_question.sh <priority> <question> <source> <related> <assumption> <query>" >&2
    echo "  priority: CRITICAL | MEDIUM | LOW" >&2
    exit 1
fi

PRIORITY="$1"
QUESTION="$2"
SOURCE="$3"
RELATED="$4"
ASSUMPTION="$5"
QUERY="$6"

# 校验优先级
if [[ ! "$PRIORITY" =~ ^(CRITICAL|MEDIUM|LOW)$ ]]; then
    echo "error: priority must be CRITICAL, MEDIUM, or LOW" >&2
    exit 3
fi

if [[ ! -f "$OQ_FILE" ]]; then
    echo "error: open-questions.md not found: $OQ_FILE" >&2
    exit 2
fi

# 用 Python 处理文件操作（找最大编号、插入到正确优先级节）
"$PYTHON" - "$OQ_FILE" "$PRIORITY" "$QUESTION" "$SOURCE" "$RELATED" "$ASSUMPTION" "$QUERY" "$DATE" <<'PYEOF'
import sys, re

filepath = sys.argv[1]
priority = sys.argv[2]
question = sys.argv[3]
source   = sys.argv[4]
related  = sys.argv[5]
assumption = sys.argv[6]
query    = sys.argv[7]
date     = sys.argv[8]

lines = open(filepath).readlines()

# 找当前最大 OQ 编号
max_id = 0
for line in lines:
    m = re.search(r'OQ-(\d+)', line)
    if m:
        max_id = max(max_id, int(m.group(1)))
new_id = f"OQ-{max_id + 1:03d}"

# 构造新条目
entry = f"""
### {new_id}（{priority}）

- **问题**：{question}
- **来源**：{source}
- **相关函数**：{related}
- **当前假设**：{assumption}
- **建议查询**：`{query}`
- **提出日期**：{date}
- **解答日期**：-
"""

# 找目标优先级节的插入位置（插在该节最后一个条目之后、下一节之前）
section_header = f"## {priority}（"
next_headers = ["## CRITICAL（", "## MEDIUM（", "## LOW（", "## 已解答"]
# 移除当前节本身，只留后续节作为终止标志
next_headers = [h for h in next_headers if not h.startswith(f"## {priority}（")]

section_start = -1
for i, line in enumerate(lines):
    if line.startswith(section_header):
        section_start = i
        break

if section_start == -1:
    print(f"error: section '## {priority}' not found in file", file=sys.stderr)
    sys.exit(1)

# 找下一节开始位置
section_end = len(lines)
for i in range(section_start + 1, len(lines)):
    if any(lines[i].startswith(h) for h in next_headers):
        section_end = i
        break

# 在 section_end 之前插入（保留空行间距）
# 找 section 内最后一个非空行
insert_pos = section_end
for i in range(section_end - 1, section_start, -1):
    if lines[i].strip():
        insert_pos = i + 1
        break

lines.insert(insert_pos, entry)

with open(filepath, 'w') as f:
    f.writelines(lines)

print(f"added: {new_id} [{priority}] {question[:50]}{'...' if len(question) > 50 else ''}")
PYEOF
