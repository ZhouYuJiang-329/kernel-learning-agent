#!/usr/bin/env bash
# upsert_node.sh — 在 knowledge.md 中插入或更新节点行
# 用法：upsert_node.sh <subsystem> <name> <type> <status> <confidence> <note> <internal_doc> [--section <节名>]
#
# 参数说明：
#   subsystem    — 子系统目录名，如 sched、mpam
#   name         — 函数/结构体名
#   type         — function | struct | concept | register
#   status       — unknown | exploring | mastered | questioned
#   confidence   — 0-100
#   note         — 笔记路径，无则传 -
#   internal_doc — Confluence 链接或标题，无则传 -
#   --section    — 可选，指定插入到哪个节（如 "CFS" 或 "ARM 硬件接口层"）
#                  未指定时追加到全文最后一个表格行后
#
# 退出码：0=成功  1=参数错误  2=文件不存在  3=子系统目录不存在

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

MEMORY_DIR="$(dirname "$0")/../memory"
DATE=$(date +%Y-%m-%d)

# 解析参数（支持可选的 --section）
if [[ $# -lt 7 ]]; then
    echo "usage: upsert_node.sh <subsystem> <name> <type> <status> <confidence> <note> <internal_doc> [--section <节名>]" >&2
    exit 1
fi

SUBSYSTEM="$1"
NAME="$2"
TYPE="$3"
STATUS="$4"
CONFIDENCE="$5"
NOTE="$6"
INTERNAL_DOC="$7"
SECTION=""

# 解析可选的 --section 参数
shift 7
while [[ $# -gt 0 ]]; do
    case "$1" in
        --section)
            SECTION="$2"
            shift 2
            ;;
        *)
            echo "unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

# 校验 status
if [[ ! "$STATUS" =~ ^(unknown|exploring|mastered|questioned)$ ]]; then
    echo "error: status must be unknown|exploring|mastered|questioned, got: $STATUS" >&2
    exit 1
fi

# 校验 confidence
if [[ ! "$CONFIDENCE" =~ ^[0-9]+$ ]] || [[ "$CONFIDENCE" -gt 100 ]]; then
    echo "error: confidence must be 0-100, got: $CONFIDENCE" >&2
    exit 1
fi

KM_FILE="${MEMORY_DIR}/${SUBSYSTEM}/knowledge.md"

if [[ ! -d "${MEMORY_DIR}/${SUBSYSTEM}" ]]; then
    echo "error: subsystem directory not found: ${MEMORY_DIR}/${SUBSYSTEM}" >&2
    exit 3
fi

if [[ ! -f "$KM_FILE" ]]; then
    echo "error: knowledge.md not found: $KM_FILE" >&2
    exit 2
fi

# 构造新行
NEW_ROW="| ${NAME} | ${TYPE} | ${STATUS} | ${CONFIDENCE} | ${NOTE} | ${INTERNAL_DOC} | ${DATE} |"

# 检查节点是否已存在（精确匹配第一列）
if grep -q "^| ${NAME} |" "$KM_FILE" 2>/dev/null; then
    # 存在 → 更新该行（用 awk 替换整行）
    ESCAPED_NAME=$(printf '%s\n' "$NAME" | sed 's/[[\.*^$()+?{|]/\\&/g')
    ESCAPED_ROW=$(printf '%s\n' "$NEW_ROW" | sed 's/[[\.*^$()+?{|]/\\&/g')

    # 使用 Python 做替换（比 sed 处理特殊字符更可靠）
    "$PYTHON" - "$KM_FILE" "$NAME" "$NEW_ROW" <<'PYEOF'
import sys
filepath, name, new_row = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(filepath).readlines()
updated = False
with open(filepath, 'w') as f:
    for line in lines:
        if line.startswith(f'| {name} |'):
            f.write(new_row + '\n')
            updated = True
        else:
            f.write(line)
if not updated:
    print(f"warning: node '{name}' not found during update", file=sys.stderr)
    sys.exit(1)
PYEOF
    echo "updated: ${SUBSYSTEM}/${NAME} → ${STATUS}(${CONFIDENCE})"
else
    # 不存在 → 追加到指定节末尾，或全文最后一个表格行后
    "$PYTHON" - "$KM_FILE" "$NEW_ROW" "$SECTION" <<'PYEOF'
import sys
filepath, new_row, section = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(filepath).readlines()

insert_pos = -1

if section:
    # 找到 section 标题行（## 或 ### 开头，包含 section 名称）
    section_start = -1
    for i, line in enumerate(lines):
        if (line.startswith('## ') or line.startswith('### ')) and section in line:
            section_start = i
            break

    if section_start != -1:
        # 找该 section 内最后一个表格数据行（跳过表头和分隔符）
        next_section = len(lines)
        for i in range(section_start + 1, len(lines)):
            if (lines[i].startswith('## ') or lines[i].startswith('### ')):
                next_section = i
                break
        # 在 section_start+1 到 next_section 之间找最后一个表格数据行
        for i in range(next_section - 1, section_start, -1):
            line = lines[i]
            if line.startswith('|') and '---' not in line and '名称' not in line:
                insert_pos = i
                break

if insert_pos == -1:
    # 未找到指定节，或未指定节：追加到全文最后一个表格数据行后
    for i in range(len(lines) - 1, -1, -1):
        line = lines[i]
        if line.startswith('|') and '---' not in line and '名称' not in line:
            insert_pos = i
            break

if insert_pos == -1:
    lines.append(new_row + '\n')
else:
    lines.insert(insert_pos + 1, new_row + '\n')

with open(filepath, 'w') as f:
    f.writelines(lines)
PYEOF
    echo "inserted: ${SUBSYSTEM}/${NAME} → ${STATUS}(${CONFIDENCE})"
fi

# 同步更新 MEMORY.md 统计（update_memory.sh 与本脚本同层级的 capture scripts 目录）
UPDATE_MEMORY="$(dirname "$0")/../skills/kernel-learning-capture/scripts/update_memory.sh"
if [[ -x "$UPDATE_MEMORY" ]]; then
    "$UPDATE_MEMORY" "$SUBSYSTEM" "$NAME" 2>/dev/null || true
fi
