#!/usr/bin/env bash
# init_module.sh — 初始化新内核学习子系统的所有文件
# 用法：init_module.sh <MODULE_KEY> <MODULE_NAME> [<func1> <func2> ...]
#
# 参数：
#   MODULE_KEY   — 目录键名（小写下划线），如 kprobe
#   MODULE_NAME  — 显示名称，如 "kprobe 探针机制"
#   func1..N     — 1-3 个入口函数名（可选，但建议提供）
#
# 创建文件：
#   memory/{MODULE_KEY}/knowledge.md
#   memory/{MODULE_KEY}/dep-graph.md
#   memory/{MODULE_KEY}/qa-log.md
#   learn/{MODULE_KEY}/_index.md
#
# 更新文件：
#   memory/MEMORY.md（子系统列表、当前学习焦点、知识状态三处）
#
# 退出码：0=成功  1=参数错误  2=目录已存在（幂等保护）  3=MEMORY.md 不存在

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MEMORY_DIR="${SCRIPT_DIR}/../../../memory"
DATE=$(date +%Y-%m-%d)

if [[ $# -lt 2 ]]; then
    echo "usage: init_module.sh <MODULE_KEY> <MODULE_NAME> [<func1> <func2> ...]" >&2
    exit 1
fi

MODULE_KEY="$1"
MODULE_NAME="$2"
shift 2
ENTRY_FUNCS=("$@")

# 幂等保护：目录已存在则报错，防止覆盖现有数据
TARGET_DIR="${MEMORY_DIR}/${MODULE_KEY}"
if [[ -d "$TARGET_DIR" ]]; then
    echo "error: directory already exists: ${TARGET_DIR}" >&2
    echo "       if you want to reinitialize, remove the directory first" >&2
    exit 2
fi

MEMORY_FILE="${MEMORY_DIR}/MEMORY.md"
if [[ ! -f "$MEMORY_FILE" ]]; then
    echo "error: MEMORY.md not found: ${MEMORY_FILE}" >&2
    exit 3
fi

mkdir -p "$TARGET_DIR"

# ── 1. knowledge.md ──────────────────────────────────────────────────────

KM_FILE="${TARGET_DIR}/knowledge.md"

{
    echo "# ${MODULE_NAME} 子系统 Knowledge Map"
    echo ""
    echo "> 格式：名称 | 类型 | 状态 | 置信度(0-100) | 笔记路径 | 内部文档 | 更新日期"
    echo "> 状态：mastered(≥80) / exploring(40-79) / unknown(<40) / questioned"
    echo "> 内部文档：Confluence 页面链接或页面标题，无则填 -"
    echo ""
    echo "## 核心层"
    echo ""
    echo "| 名称 | 类型 | 状态 | 置信度 | 笔记 | 内部文档 | 更新日期 |"
    echo "|------|------|------|--------|------|---------|---------|"
    for func in "${ENTRY_FUNCS[@]}"; do
        echo "| ${func} | function | unknown | 0 | - | - | - |"
    done
} > "$KM_FILE"

echo "created: ${MODULE_KEY}/knowledge.md (${#ENTRY_FUNCS[@]} initial nodes)"

# ── 2. dep-graph.md ───────────────────────────────────────────────────────

DEP_FILE="${TARGET_DIR}/dep-graph.md"

{
    echo "# ${MODULE_NAME} 依赖图"
    echo ""
    echo '```'
    if [[ ${#ENTRY_FUNCS[@]} -eq 0 ]]; then
        echo "(暂无入口函数，待分析后补充)"
    else
        first=true
        for func in "${ENTRY_FUNCS[@]}"; do
            if [[ "$first" != "true" ]]; then
                echo ""
            fi
            echo "${func}"
            echo "  └── (待分析)"
            first=false
        done
    fi
    echo '```'
} > "$DEP_FILE"

echo "created: ${MODULE_KEY}/dep-graph.md"

# ── 3. qa-log.md ─────────────────────────────────────────────────────────

QA_FILE="${TARGET_DIR}/qa-log.md"

{
    echo "# ${MODULE_NAME} 问答日志"
    echo ""
    echo "> 记录学习过程中的提问与结论，按知识节点分组。"
} > "$QA_FILE"

echo "created: ${MODULE_KEY}/qa-log.md"

# ── 4. learn/{MODULE_KEY}/_index.md ──────────────────────────────────────

LEARN_DIR="${SCRIPT_DIR}/../../../../learn/${MODULE_KEY}"
mkdir -p "$LEARN_DIR"

INDEX_FILE="${LEARN_DIR}/_index.md"

{
    echo "# ${MODULE_NAME} 学习笔记"
    echo ""
    echo "> 学习开始日期：${DATE}"
    if [[ ${#ENTRY_FUNCS[@]} -gt 0 ]]; then
        LINKS=""
        for func in "${ENTRY_FUNCS[@]}"; do
            LINKS="${LINKS}[[${func}]] · "
        done
        LINKS="${LINKS% · }"
        echo "> 入口函数：${LINKS}"
    fi
    echo ""
    echo "## 笔记列表"
    echo ""
    echo "（待添加）"
    echo ""
    echo "## 概念依赖图"
    echo ""
    echo "（待分析后补充，参考 \`.claude/memory/${MODULE_KEY}/dep-graph.md\`）"
} > "$INDEX_FILE"

echo "created: learn/${MODULE_KEY}/_index.md"

# ── 5. 更新 MEMORY.md（Python 精确插入）──────────────────────────────────

FIRST_FUNC="${ENTRY_FUNCS[0]:-}"
NODE_COUNT="${#ENTRY_FUNCS[@]}"

python3 - "$MEMORY_FILE" "$MODULE_KEY" "$MODULE_NAME" "$NODE_COUNT" "$FIRST_FUNC" <<'PYEOF'
import sys

memory_file = sys.argv[1]
module_key  = sys.argv[2]
module_name = sys.argv[3]
node_count  = int(sys.argv[4])
first_func  = sys.argv[5]

lines = open(memory_file).readlines()

table_row   = f'| {module_name} | [{module_key}/]({module_key}/knowledge.md) | 0 | 0 | {node_count} | - |\n'
focus_entry = f'- **{module_name} 进度**：刚开始，入口函数 {first_func if first_func else "（待确定）"} 尚未分析\n'
km_entry    = f'- [{module_key}/knowledge.md]({module_key}/knowledge.md) — {module_name} 节点表\n'
dep_entry   = f'- [{module_key}/dep-graph.md]({module_key}/dep-graph.md) — {module_name} 依赖图\n'

def insert_after_last_table_row(lines, section_marker, new_row):
    in_section = False
    last_data_line = -1
    for i, line in enumerate(lines):
        if section_marker in line:
            in_section = True
        elif in_section and line.startswith(('## ', '# ')):
            break
        elif in_section and line.startswith('|') and '---' not in line and '子系统' not in line:
            last_data_line = i
    if last_data_line != -1:
        lines.insert(last_data_line + 1, new_row)
        return True
    return False

def append_to_section(lines, section_marker, new_entry):
    in_section = False
    last_content_line = -1
    for i, line in enumerate(lines):
        if section_marker in line:
            in_section = True
        elif in_section and line.startswith(('## ', '# ')):
            break
        elif in_section and line.strip():
            last_content_line = i
    if last_content_line != -1:
        lines.insert(last_content_line + 1, new_entry)
        return True
    return False

def insert_before_open_questions(lines, km_entry, dep_entry):
    for i, line in enumerate(lines):
        if 'open-questions.md' in line:
            lines.insert(i, dep_entry)
            lines.insert(i, km_entry)
            return True
    return False

insert_after_last_table_row(lines, '## 子系统列表', table_row)
append_to_section(lines, '## 当前学习焦点', focus_entry)

if not insert_before_open_questions(lines, km_entry, dep_entry):
    append_to_section(lines, '## 知识状态', dep_entry)
    append_to_section(lines, '## 知识状态', km_entry)

with open(memory_file, 'w') as f:
    f.writelines(lines)

print(f"updated: MEMORY.md (+{module_name})")
PYEOF
