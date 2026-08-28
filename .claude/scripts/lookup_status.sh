#!/usr/bin/env bash
# lookup_status.sh — 查询函数/结构体在 memory 中的学习状态
# 用法：lookup_status.sh <function_name>
# 输出：<subsystem>|<status>|<confidence>|<file_path>
#       unclassified|<status>|<confidence>|<file_path>  (在暂存区中)
#       not_found
#       multiple:<file1>,<file2>  (多个已知子系统都匹配，需人工确认)

set -euo pipefail

MEMORY_DIR="$(dirname "$0")/../memory"
NAME="${1:-}"

if [[ -z "$NAME" ]]; then
    echo "usage: lookup_status.sh <function_name>" >&2
    exit 1
fi

# 在所有 knowledge.md 中搜索（精确匹配表格第一列）
# 表格行格式：| name | type | status | confidence | note | internal_doc | date |
matches=()
while IFS= read -r file; do
    line=$(grep -m1 "^| ${NAME} |" "$file" 2>/dev/null || true)
    if [[ -n "$line" ]]; then
        status=$(echo "$line" | awk -F'|' '{gsub(/ /,"",$4); print $4}')
        confidence=$(echo "$line" | awk -F'|' '{gsub(/ /,"",$5); print $5}')
        subsystem=$(basename "$(dirname "$file")")
        matches+=("${subsystem}|${status}|${confidence}|${file}")
    fi
done < <(find "$MEMORY_DIR" -name "knowledge.md" -type f ! -path "*/unclassified/*")

case ${#matches[@]} in
    0)
        # 已知子系统未找到 → 补搜暂存区
        UNCLASSIFIED="${MEMORY_DIR}/unclassified/knowledge.md"
        if [[ -f "$UNCLASSIFIED" ]]; then
            line=$(grep -m1 "^| ${NAME} |" "$UNCLASSIFIED" 2>/dev/null || true)
            if [[ -n "$line" ]]; then
                status=$(echo "$line" | awk -F'|' '{gsub(/ /,"",$4); print $4}')
                confidence=$(echo "$line" | awk -F'|' '{gsub(/ /,"",$5); print $5}')
                echo "unclassified|${status}|${confidence}|${UNCLASSIFIED}"
                exit 0
            fi
        fi
        echo "not_found"
        ;;
    1) echo "${matches[0]}" ;;
    *) echo "multiple:$(IFS=','; echo "${matches[*]}")" ;;
esac
