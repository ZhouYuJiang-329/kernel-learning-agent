#!/usr/bin/env bash
# count_stats.sh — 统计子系统 knowledge.md 中各状态的节点数量
# 用法：count_stats.sh <subsystem>        # 单个子系统
#       count_stats.sh --all              # 所有子系统
# 输出（单个）：mastered=0 exploring=5 unknown=18 questioned=0 avg_conf=54
# 输出（--all）：每行 <subsystem> mastered=N exploring=N unknown=N avg_conf=N

set -euo pipefail

MEMORY_DIR="$(dirname "$0")/../memory"

count_one() {
    local file="$1"
    local subsystem="$2"

    if [[ ! -f "$file" ]]; then
        echo "${subsystem}: file not found" >&2
        return 1
    fi

    local mastered exploring unknown questioned
    mastered=$(grep -c "| mastered |" "$file" 2>/dev/null || true)
    exploring=$(grep -c "| exploring |" "$file" 2>/dev/null || true)
    unknown=$(grep -c "| unknown |" "$file" 2>/dev/null || true)
    questioned=$(grep -c "| questioned |" "$file" 2>/dev/null || true)
    # grep -c 返回 0 时在某些系统 exit 1，用 || true 兜底后可能带换行，trim 一下
    mastered="${mastered//[$'\t\r\n ']}"
    exploring="${exploring//[$'\t\r\n ']}"
    unknown="${unknown//[$'\t\r\n ']}"
    questioned="${questioned//[$'\t\r\n ']}"
    mastered="${mastered:-0}"
    exploring="${exploring:-0}"
    unknown="${unknown:-0}"
    questioned="${questioned:-0}"

    # 平均置信度（只算 mastered + exploring，忽略 unknown 的 0）
    local total_conf count_conf avg_conf
    total_conf=0
    count_conf=0
    while IFS= read -r line; do
        # 跳过表头和分隔行
        [[ "$line" =~ ^\|[[:space:]]*名称 ]] && continue
        [[ "$line" =~ ^\|[-]+\| ]] && continue
        # 提取置信度列（第5列）
        conf=$(echo "$line" | awk -F'|' '{gsub(/ /,"",$5); print $5}')
        if [[ "$conf" =~ ^[0-9]+$ ]] && [[ "$conf" -gt 0 ]]; then
            total_conf=$((total_conf + conf))
            count_conf=$((count_conf + 1))
        fi
    done < <(grep "^|" "$file" 2>/dev/null || true)

    if [[ $count_conf -gt 0 ]]; then
        avg_conf=$(echo "scale=1; $total_conf / $count_conf" | bc 2>/dev/null || echo 0)
    else
        avg_conf="-"
    fi

    echo "${subsystem} mastered=${mastered} exploring=${exploring} unknown=${unknown} questioned=${questioned} avg_conf=${avg_conf}"
}

ARG="${1:-}"

if [[ "$ARG" == "--all" ]]; then
    while IFS= read -r km_file; do
        subsystem=$(basename "$(dirname "$km_file")")
        # 跳过暂存区，不参与进度统计
        [[ "$subsystem" == "unclassified" ]] && continue
        count_one "$km_file" "$subsystem"
    done < <(find "$MEMORY_DIR" -name "knowledge.md" -type f | sort)
elif [[ -n "$ARG" ]]; then
    km_file="${MEMORY_DIR}/${ARG}/knowledge.md"
    count_one "$km_file" "$ARG"
else
    echo "usage: count_stats.sh <subsystem> | --all" >&2
    exit 1
fi
