#!/usr/bin/env bash
# resolve_question.sh — 将已解答的问题从待解答节移至"已解答"归档节
#
# 用法：
#   resolve_question.sh <OQ-NNN> <conclusion>
#
# 参数：
#   OQ-NNN     — 问题编号，如 OQ-001
#   conclusion — 解答结论（一句话描述）
#
# 退出码：0=成功  1=参数错误  2=文件不存在  4=问题编号未找到

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
if [[ $# -lt 2 ]]; then
    echo "usage: resolve_question.sh <OQ-NNN> <conclusion>" >&2
    exit 1
fi

OQ_ID="$1"
CONCLUSION="$2"

# 校验编号格式
if [[ ! "$OQ_ID" =~ ^OQ-[0-9]+$ ]]; then
    echo "error: invalid OQ ID format, expected OQ-NNN (e.g. OQ-001)" >&2
    exit 1
fi

if [[ ! -f "$OQ_FILE" ]]; then
    echo "error: open-questions.md not found: $OQ_FILE" >&2
    exit 2
fi

"$PYTHON" - "$OQ_FILE" "$OQ_ID" "$CONCLUSION" "$DATE" <<'PYEOF'
import sys, re

filepath   = sys.argv[1]
oq_id      = sys.argv[2]
conclusion = sys.argv[3]
date       = sys.argv[4]

lines = open(filepath).readlines()

# 找问题条目的起止行
entry_start = -1
for i, line in enumerate(lines):
    # 匹配 ### OQ-NNN 或 ### OQ-NNN（PRIORITY）
    if re.match(rf'^### {re.escape(oq_id)}', line):
        entry_start = i
        break

if entry_start == -1:
    print(f"error: {oq_id} not found in {filepath}", file=sys.stderr)
    sys.exit(4)

# 找条目结束位置（下一个 ### 或 ## 标题，或文件末尾）
entry_end = len(lines)
for i in range(entry_start + 1, len(lines)):
    if lines[i].startswith('### ') or lines[i].startswith('## '):
        entry_end = i
        break

# 提取条目内容
entry_lines = lines[entry_start:entry_end]

# 更新条目中的解答日期（有则替换，无则追加）
updated_entry = []
has_resolve_date = any('**解答日期**' in l for l in entry_lines)
for line in entry_lines:
    if '**解答日期**' in line:
        updated_entry.append(f"- **解答日期**：{date}\n")
    else:
        updated_entry.append(line)

# 若原条目没有解答日期字段，在最后一个非空行后插入
if not has_resolve_date:
    last_content = len(updated_entry)
    for i in range(len(updated_entry) - 1, -1, -1):
        if updated_entry[i].strip():
            last_content = i + 1
            break
    updated_entry.insert(last_content, f"- **解答日期**：{date}\n")

# 追加结论行（若还没有）
has_conclusion = any('**结论**' in l for l in updated_entry)
if not has_conclusion:
    # 在最后一个非空行后插入
    last_content = len(updated_entry)
    for i in range(len(updated_entry) - 1, -1, -1):
        if updated_entry[i].strip():
            last_content = i + 1
            break
    updated_entry.insert(last_content, f"- **结论**：{conclusion}\n")

# 从原位置删除条目
new_lines = lines[:entry_start] + lines[entry_end:]

# 找"已解答"节，追加到末尾
resolved_header = "## 已解答"
resolved_pos = -1
for i, line in enumerate(new_lines):
    if line.startswith(resolved_header):
        resolved_pos = i
        break

if resolved_pos == -1:
    print(f"error: '## 已解答' section not found in {filepath}", file=sys.stderr)
    sys.exit(1)

# 找已解答节的末尾（文件末尾）
insert_pos = len(new_lines)
# 在文件末尾找最后一个非空行后插入
for i in range(len(new_lines) - 1, resolved_pos, -1):
    if new_lines[i].strip():
        insert_pos = i + 1
        break

for j, line in enumerate(updated_entry):
    new_lines.insert(insert_pos + j, line)

with open(filepath, 'w') as f:
    f.writelines(new_lines)

print(f"resolved: {oq_id} → archived to '已解答' section")
print(f"conclusion: {conclusion}")
PYEOF
