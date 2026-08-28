#!/usr/bin/env bash
# init_agent.sh — 生成新子系统的 specialist agent 文件
# 用法：init_agent.sh <MODULE_KEY> <MODULE_NAME> <SOURCE_PATH> <CALL_TREE> [<STRUCTS>]
#
# 参数：
#   MODULE_KEY   — 目录键名，如 kprobe
#   MODULE_NAME  — 显示名称，如 "kprobe 探针机制"
#   SOURCE_PATH  — 本地源码路径，如 kernel/kprobes.c
#   CALL_TREE    — 调用树文本（换行用 \n），来自 call_chain_down 查询结果
#   STRUCTS      — 关键结构体（可选），如 "kprobe, kretprobe"
#
# 创建文件：
#   .claude/agents/{MODULE_KEY}-specialist.md
#
# 退出码：0=成功  1=参数错误  2=文件已存在  3=agents 目录不存在

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENTS_DIR="${SCRIPT_DIR}/../../../../.claude/agents"

if [[ $# -lt 4 ]]; then
    echo "usage: init_agent.sh <MODULE_KEY> <MODULE_NAME> <SOURCE_PATH> <CALL_TREE> [<STRUCTS>]" >&2
    exit 1
fi

MODULE_KEY="$1"
MODULE_NAME="$2"
SOURCE_PATH="$3"
CALL_TREE="$4"
STRUCTS="${5:-}"

if [[ ! -d "$AGENTS_DIR" ]]; then
    echo "error: agents directory not found: ${AGENTS_DIR}" >&2
    exit 3
fi

AGENT_FILE="${AGENTS_DIR}/${MODULE_KEY}-specialist.md"

if [[ -f "$AGENT_FILE" ]]; then
    echo "error: agent file already exists: ${AGENT_FILE}" >&2
    echo "       remove it first if you want to regenerate" >&2
    exit 2
fi

python3 - "$AGENT_FILE" "$MODULE_KEY" "$MODULE_NAME" "$SOURCE_PATH" "$CALL_TREE" "$STRUCTS" <<'PYEOF'
import sys

agent_file  = sys.argv[1]
module_key  = sys.argv[2]
module_name = sys.argv[3]
source_path = sys.argv[4]
call_tree   = sys.argv[5].replace('\\n', '\n')
structs     = sys.argv[6]

# source_dir：取 source_path 的目录部分
import os
source_dir = os.path.dirname(source_path) or source_path

lines = []
lines.append(f'---\n')
lines.append(f'name: {module_key}-specialist\n')
lines.append(f'description: >\n')
lines.append(f'  专注 {module_name} 的深度分析代理。\n')
lines.append(f'  当主会话遇到 {module_name} 相关的函数分析、调用链追踪、源码解读时派遣。\n')
lines.append(f'  使用 kernel-graph MCP + 本地源码分析 Linux 6.0 {module_name} 实现。\n')
lines.append(f'tools:\n')
for tool in [
    'Read', 'Bash',
    'mcp__kernel-graph__find_definition',
    'mcp__kernel-graph__find_callers',
    'mcp__kernel-graph__find_callees',
    'mcp__kernel-graph__call_chain_up',
    'mcp__kernel-graph__call_chain_down',
    'mcp__kernel-graph__find_struct',
    'mcp__kernel-graph__search_functions',
    'mcp__kernel-graph__functions_in_file',
]:
    lines.append(f'  - {tool}\n')
lines.append(f'---\n')
lines.append(f'\n')
lines.append(f'## 角色定位\n')
lines.append(f'\n')
lines.append(f'你是 Linux {module_name} 子系统的专家分析助手。用中文回答。\n')
lines.append(f'\n')
lines.append(f'## 技术背景知识\n')
lines.append(f'\n')
lines.append(f'### 核心调用路径\n')
lines.append(f'\n')
lines.append(f'```\n')
for tree_line in call_tree.split('\n'):
    lines.append(tree_line + '\n')
lines.append(f'```\n')
lines.append(f'\n')
if structs:
    lines.append(f'### 关键结构体\n')
    lines.append(f'\n')
    lines.append(f'{structs}\n')
    lines.append(f'\n')
lines.append(f'### 本地源码位置（内核 6.0）\n')
lines.append(f'\n')
lines.append(f'- `<kernel-source-root>/{source_dir}/`\n')
lines.append(f'\n')
lines.append(f'## 工作规则\n')
lines.append(f'\n')
lines.append(f'1. 每次分析前用 `find_definition` 确认函数/结构体的真实位置\n')
lines.append(f'2. 分析完成后，建议主会话调用 `kernel-learning-capture` skill 更新 memory\n')
lines.append(f'3. 若调用链 >= 3 层，主动建议生成 drawio 图\n')
lines.append(f'\n')
lines.append(f'## 输出格式\n')
lines.append(f'\n')
lines.append(f'- 中文说明 + 英文函数名/文件路径\n')
lines.append(f'- ASCII 调用树（来自 MCP 查询结果）\n')
lines.append(f'- 关键结构体字段对照表\n')

with open(agent_file, 'w') as f:
    f.writelines(lines)
PYEOF

echo "created: .claude/agents/${MODULE_KEY}-specialist.md"
