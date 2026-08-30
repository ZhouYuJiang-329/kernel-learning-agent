#!/usr/bin/env bash
# reclassify.sh — 将 unclassified/ 中的节点迁移到目标子系统
# 用法：reclassify.sh <NAME> <TARGET_SUBSYSTEM> [--section "<节名>"]
#
# 参数：
#   NAME              — 函数/结构体名，必须已存在于 unclassified/knowledge.md
#   TARGET_SUBSYSTEM  — 目标子系统目录名，如 sched、mpam
#   --section         — 可选，指定插入到目标 knowledge.md 的哪个节
#
# 操作：
#   1. 从 unclassified/knowledge.md 读取该节点行
#   2. 调用 upsert_node.sh 写入目标子系统
#   3. 从 unclassified/knowledge.md 删除该行
#
# 退出码：0=成功  1=参数错误  2=节点不在 unclassified 中  3=目标子系统不存在

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
UPSERT="${SCRIPT_DIR}/../../../scripts/upsert_node.sh"

if [[ $# -lt 2 ]]; then
    echo "usage: reclassify.sh <NAME> <TARGET_SUBSYSTEM> [--section <节名>]" >&2
    exit 1
fi

NAME="$1"
TARGET="$2"
shift 2
SECTION_ARGS=("$@")

UNCLASSIFIED_KM="${MEMORY_DIR}/unclassified/knowledge.md"
TARGET_DIR="${MEMORY_DIR}/${TARGET}"

if [[ ! -d "$TARGET_DIR" ]]; then
    echo "error: target subsystem not found: ${TARGET_DIR}" >&2
    exit 3
fi

if [[ ! -f "$UNCLASSIFIED_KM" ]]; then
    echo "error: unclassified/knowledge.md not found" >&2
    exit 2
fi

# 从 unclassified/knowledge.md 读取节点行
NODE_LINE=$(grep -m1 "^| ${NAME} |" "$UNCLASSIFIED_KM" 2>/dev/null || true)

if [[ -z "$NODE_LINE" ]]; then
    echo "error: '${NAME}' not found in unclassified/knowledge.md" >&2
    exit 2
fi

# 解析各字段
TYPE=$(echo "$NODE_LINE"       | awk -F'|' '{gsub(/^ +| +$/,"",$3); print $3}')
STATUS=$(echo "$NODE_LINE"     | awk -F'|' '{gsub(/^ +| +$/,"",$4); print $4}')
CONFIDENCE=$(echo "$NODE_LINE" | awk -F'|' '{gsub(/^ +| +$/,"",$5); print $5}')
NOTE=$(echo "$NODE_LINE"       | awk -F'|' '{gsub(/^ +| +$/,"",$6); print $6}')
INTERNAL=$(echo "$NODE_LINE"   | awk -F'|' '{gsub(/^ +| +$/,"",$7); print $7}')

echo "migrating: unclassified/${NAME} → ${TARGET} (${STATUS}, ${CONFIDENCE})"

# upsert 到目标子系统
"$UPSERT" "$TARGET" "$NAME" "$TYPE" "$STATUS" "$CONFIDENCE" "$NOTE" "$INTERNAL" "${SECTION_ARGS[@]}"

# 从 unclassified/knowledge.md 删除该行
"$PYTHON" - "$UNCLASSIFIED_KM" "$NAME" <<'PYEOF'
import sys
filepath, name = sys.argv[1], sys.argv[2]
lines = open(filepath).readlines()
with open(filepath, 'w') as f:
    for line in lines:
        if not line.startswith(f'| {name} |'):
            f.write(line)
PYEOF

echo "done: ${NAME} removed from unclassified/"
