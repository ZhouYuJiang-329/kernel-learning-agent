#!/usr/bin/env bash
# append_qa.sh — 向 qa-log.md 追加问答条目
# 用法：append_qa.sh <subsystem> <node> <source> <question> <background> <conclusion> <date>
#
# 参数：
#   subsystem   — 子系统目录名，如 sched、mpam、unclassified
#   node        — 关联节点名（用于分组标题），如 enqueue_task_fair
#   source      — 来源：用户提问 | AI 发现
#   question    — 完整问题描述
#   background  — 触发背景（一句话）
#   conclusion  — 结论（已解决写答案；未解决写"待解决，关联 OQ-NNN"）
#   date        — 日期，格式 YYYY-MM-DD
#
# 退出码：0=成功  1=参数错误  2=qa-log.md 不存在  3=子系统目录不存在

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MEMORY_DIR="${SCRIPT_DIR}/../../../memory"

if [[ $# -lt 7 ]]; then
    echo "usage: append_qa.sh <subsystem> <node> <source> <question> <background> <conclusion> <date>" >&2
    exit 1
fi

SUBSYSTEM="$1"
NODE="$2"
SOURCE="$3"
QUESTION="$4"
BACKGROUND="$5"
CONCLUSION="$6"
DATE="$7"

TARGET_DIR="${MEMORY_DIR}/${SUBSYSTEM}"
QA_FILE="${TARGET_DIR}/qa-log.md"

if [[ ! -d "$TARGET_DIR" ]]; then
    echo "error: subsystem directory not found: ${TARGET_DIR}" >&2
    exit 3
fi

if [[ ! -f "$QA_FILE" ]]; then
    echo "error: qa-log.md not found: ${QA_FILE}" >&2
    exit 2
fi

ASSIGNED_NUM=$(python3 - "$QA_FILE" "$NODE" "$SOURCE" "$QUESTION" "$BACKGROUND" "$CONCLUSION" "$DATE" <<'PYEOF'
import sys
import re

qa_file    = sys.argv[1]
node       = sys.argv[2]
source     = sys.argv[3]
question   = sys.argv[4]
background = sys.argv[5]
conclusion = sys.argv[6]
date       = sys.argv[7]

lines = open(qa_file).readlines()

# ── 1. 分配编号（全文扫描，不重复）────────────────────────────────────────
max_num = 0
for line in lines:
    m = re.match(r'^### Q-(\d+)', line)
    if m:
        max_num = max(max_num, int(m.group(1)))
q_num = f"Q-{max_num + 1:03d}"

# 问题标题：取 question 前 30 字符作为简短标题
short_title = question[:30].rstrip() + ("…" if len(question) > 30 else "")

# ── 2. 构造新条目 ────────────────────────────────────────────────────────
entry = (
    f"\n### {q_num} {short_title}\n"
    f"\n"
    f"- **来源**：{source}\n"
    f"- **问题**：{question}\n"
    f"- **背景**：{background}\n"
    f"- **结论**：{conclusion}\n"
    f"- **日期**：{date}\n"
    f"\n"
    f"---\n"
)

# ── 3. 定位分组，精确插入 ─────────────────────────────────────────────────
section_header = f"## {node}\n"

# 找该分组的起始行
section_start = -1
for i, line in enumerate(lines):
    if line == section_header:
        section_start = i
        break

if section_start == -1:
    # 分组不存在 → 在文件末尾新建分组
    # 确保文件末尾有空行
    if lines and not lines[-1].endswith('\n'):
        lines.append('\n')
    if lines and lines[-1].strip():
        lines.append('\n')
    lines.append(f"## {node}\n")
    lines.append(entry)
else:
    # 分组存在 → 找该分组内最后一个 "---" 行，在其后插入
    # 分组结束：下一个 "## " 标题行，或文件末尾
    section_end = len(lines)
    for i in range(section_start + 1, len(lines)):
        if lines[i].startswith("## "):
            section_end = i
            break

    last_sep = -1
    for i in range(section_start, section_end):
        if lines[i].strip() == "---":
            last_sep = i

    if last_sep == -1:
        # 分组内没有任何条目（空分组）→ 直接在标题后追加
        insert_pos = section_start + 1
    else:
        insert_pos = last_sep + 1

    lines.insert(insert_pos, entry)

with open(qa_file, 'w') as f:
    f.writelines(lines)

print(q_num)
PYEOF
)

echo "appended: ${SUBSYSTEM}/${NODE} → ${ASSIGNED_NUM}"
