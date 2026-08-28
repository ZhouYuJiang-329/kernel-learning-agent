#!/usr/bin/env bash
# update_memory.sh — 更新 MEMORY.md 的统计数字、最近分析列表、开放问题统计
# 用法：update_memory.sh <subsystem> <func_name>
#
# 参数：
#   subsystem  — 触发本次更新的子系统，如 sched、mpam（用于更新表格对应行）
#   func_name  — 本次分析的函数/结构体名（加入"最近 5 个分析"列表）
#
# 操作：
#   1. 调用 count_stats.sh --all 获取各子系统统计数字，更新子系统列表表格
#   2. 在"最近 5 个分析"列表中追加本次，超出 5 条时移除最旧
#   3. grep open-questions.md 统计 CRITICAL/MEDIUM/LOW 数量，更新"开放问题统计"行
#
# 退出码：0=成功  1=参数错误  3=MEMORY.md 不存在

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MEMORY_DIR="${SCRIPT_DIR}/../../../memory"
SCRIPTS_DIR="${SCRIPT_DIR}/../../../scripts"

if [[ $# -lt 2 ]]; then
    echo "usage: update_memory.sh <subsystem> <func_name>" >&2
    exit 1
fi

SUBSYSTEM="$1"
FUNC_NAME="$2"
DATE=$(date +%Y-%m-%d)

MEMORY_FILE="${MEMORY_DIR}/MEMORY.md"
OQ_FILE="${MEMORY_DIR}/open-questions.md"

if [[ ! -f "$MEMORY_FILE" ]]; then
    echo "error: MEMORY.md not found: ${MEMORY_FILE}" >&2
    exit 3
fi

# ── 1. 获取各子系统统计数字 ───────────────────────────────────────────────
STATS=$("${SCRIPTS_DIR}/count_stats.sh" --all)

# ── 2. 统计开放问题 ───────────────────────────────────────────────────────
CRITICAL_COUNT=0
MEDIUM_COUNT=0
LOW_COUNT=0
if [[ -f "$OQ_FILE" ]]; then
    CRITICAL_COUNT=$(grep -c "^### OQ-.*CRITICAL" "$OQ_FILE" 2>/dev/null || true)
    MEDIUM_COUNT=$(grep -c "^### OQ-.*MEDIUM" "$OQ_FILE" 2>/dev/null || true)
    LOW_COUNT=$(grep -c "^### OQ-.*LOW" "$OQ_FILE" 2>/dev/null || true)
fi

# ── 3. Python 更新 MEMORY.md ────────────────────────────────────────────
python3 - \
    "$MEMORY_FILE" \
    "$STATS" \
    "$FUNC_NAME" \
    "$DATE" \
    "$SUBSYSTEM" \
    "$CRITICAL_COUNT" \
    "$MEDIUM_COUNT" \
    "$LOW_COUNT" \
<<'PYEOF'
import sys
import re

memory_file     = sys.argv[1]
stats_output    = sys.argv[2]   # 多行字符串
func_name       = sys.argv[3]
date            = sys.argv[4]
subsystem       = sys.argv[5]
critical_count  = int(sys.argv[6])
medium_count    = int(sys.argv[7])
low_count       = int(sys.argv[8])

lines = open(memory_file).readlines()

# ── 解析 count_stats.sh --all 输出 ──────────────────────────────────────
# 格式：sched mastered=0 exploring=5 unknown=18 questioned=0 avg_conf=62.0
stats = {}
for line in stats_output.strip().splitlines():
    parts = line.split()
    if not parts:
        continue
    sub = parts[0]
    kv = {}
    for p in parts[1:]:
        k, _, v = p.partition('=')
        kv[k] = v
    stats[sub] = kv

def update_table_row(lines, sub, kv):
    """更新子系统列表表格中对应子系统行的数字列"""
    for i, line in enumerate(lines):
        if not line.startswith('|'):
            continue
        if '---' in line or '子系统' in line or '目录' in line:
            continue
        # 找到包含该子系统目录链接的行，如 [sched/](sched/knowledge.md)
        if f'({sub}/knowledge.md)' in line or f'[{sub}/]' in line:
            parts = [p.strip() for p in line.split('|')]
            # | 子系统名 | 目录链接 | mastered | exploring | unknown | 平均置信度 |
            if len(parts) >= 7:
                parts[3] = f" {kv.get('mastered','0')} "
                parts[4] = f" {kv.get('exploring','0')} "
                parts[5] = f" {kv.get('unknown','0')} "
                parts[6] = f" {kv.get('avg_conf','-')} "
                lines[i] = '| ' + ' | '.join(p.strip() for p in parts[1:-1]) + ' |\n'
            break
    return lines

for sub, kv in stats.items():
    lines = update_table_row(lines, sub, kv)

# ── 更新"最近 5 个分析"列表 ────────────────────────────────────────────
new_entry = f"- `{func_name}` ({subsystem}, {date})\n"

# 已有相同条目（同一天同一函数）则跳过，避免重复
skip_recent = new_entry in lines

in_recent = False
recent_start = -1
recent_items = []
recent_end = -1

if not skip_recent:
    for i, line in enumerate(lines):
        if '## 最近' in line and '分析' in line:
            in_recent = True
            recent_start = i
            continue
        if in_recent:
            if line.startswith('## '):
                recent_end = i
                break
            if line.strip().startswith('- '):
                recent_items.append(i)
            elif line.strip() == '（暂无）':
                # 替换占位行
                lines[i] = new_entry
                with open(memory_file, 'w') as f:
                    f.writelines(lines)
                print(f"updated: MEMORY.md (recent={func_name}, OQ={critical_count}/{medium_count}/{low_count})")
                # 继续处理 OQ 统计
                lines = open(memory_file).readlines()
                break

    if in_recent and recent_items:
        insert_pos = recent_items[-1] + 1
    elif in_recent and recent_start >= 0 and not recent_items:
        insert_pos = recent_start + 1
        while insert_pos < len(lines) and lines[insert_pos].strip() == '':
            insert_pos += 1
    else:
        insert_pos = -1

    if insert_pos >= 0:
        lines.insert(insert_pos, new_entry)
        recent_items.append(insert_pos)
        all_items = []
        in_recent2 = False
        for i, line in enumerate(lines):
            if '## 最近' in line and '分析' in line:
                in_recent2 = True
                continue
            if in_recent2:
                if line.startswith('## '):
                    break
                if line.strip().startswith('- '):
                    all_items.append(i)
        while len(all_items) > 5:
            del lines[all_items[0]]
            all_items = all_items[1:]
            all_items = [x - 1 for x in all_items]

# ── 更新"开放问题统计"行 ────────────────────────────────────────────────
new_oq_line = f"CRITICAL: {critical_count} · MEDIUM: {medium_count} · LOW: {low_count}\n"
for i, line in enumerate(lines):
    if line.startswith('CRITICAL:') and 'MEDIUM:' in line:
        lines[i] = new_oq_line
        break

# ── 同步更新知识状态节中 open-questions.md 链接行的统计 ─────────────────
for i, line in enumerate(lines):
    if 'open-questions.md' in line and '待解答问题' in line:
        lines[i] = re.sub(
            r'CRITICAL: \d+，MEDIUM: \d+，LOW: \d+',
            f'CRITICAL: {critical_count}，MEDIUM: {medium_count}，LOW: {low_count}',
            line
        )
        break

with open(memory_file, 'w') as f:
    f.writelines(lines)

print(f"updated: MEMORY.md (recent={func_name}, OQ C:{critical_count}/M:{medium_count}/L:{low_count})")
PYEOF
