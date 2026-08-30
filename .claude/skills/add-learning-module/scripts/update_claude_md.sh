#!/usr/bin/env bash
# update_claude_md.sh — 向 CLAUDE.md 追加新学习模块的速查节和学习领域声明
# 用法：update_claude_md.sh <MODULE_KEY> <MODULE_NAME> <SOURCE_PATH> <CALL_TREE> [<STRUCTS>]
#
# 参数：
#   MODULE_KEY   — 目录键名，如 kprobe
#   MODULE_NAME  — 显示名称，如 "kprobe 探针机制"
#   SOURCE_PATH  — 本地源码路径（来自 find_definition），如 kernel/kprobes.c
#   CALL_TREE    — 调用树文本（多行，用 \n 分隔），如 "kprobe_register\n  └── ..."
#   STRUCTS      — 关键结构体（可选），如 "kprobe, kretprobe"
#
# 修改内容：
#   1. "学习领域"首行：追加 "+ {MODULE_NAME}"
#   2. "技术上下文速查"节末尾：插入新的 ### {MODULE_NAME} 关键路径 子节
#
# 退出码：0=成功  1=参数错误  3=CLAUDE.md 不存在  4=目标节未找到

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
CLAUDE_MD="${SCRIPT_DIR}/../../../../CLAUDE.md"

if [[ $# -lt 4 ]]; then
    echo "usage: update_claude_md.sh <MODULE_KEY> <MODULE_NAME> <SOURCE_PATH> <CALL_TREE> [<STRUCTS>]" >&2
    exit 1
fi

MODULE_KEY="$1"
MODULE_NAME="$2"
SOURCE_PATH="$3"
CALL_TREE="$4"
STRUCTS="${5:-}"

if [[ ! -f "$CLAUDE_MD" ]]; then
    echo "error: CLAUDE.md not found: ${CLAUDE_MD}" >&2
    exit 3
fi

"$PYTHON" - "$CLAUDE_MD" "$MODULE_KEY" "$MODULE_NAME" "$SOURCE_PATH" "$CALL_TREE" "$STRUCTS" <<'PYEOF'
import sys

claude_file  = sys.argv[1]
module_key   = sys.argv[2]
module_name  = sys.argv[3]
source_path  = sys.argv[4]
call_tree    = sys.argv[5].replace('\\n', '\n')
structs      = sys.argv[6]

lines = open(claude_file).readlines()
changed = []

# ── 1. 更新"学习领域"首行 ─────────────────────────────────────────────────
# 找到以 "> 学习领域：" 开头的行，在行末追加 " + {MODULE_NAME}"
# 直接按内容定位，不依赖行号，第二次新增模块也不会失配

domain_updated = False
for i, line in enumerate(lines):
    if line.startswith('> 学习领域：') and module_name not in line:
        lines[i] = line.rstrip('\n').rstrip() + f' + {module_name}\n'
        domain_updated = True
        break

if not domain_updated:
    print(f"warning: '> 学习领域：' line not found or already contains '{module_name}'", file=sys.stderr)

# ── 2. 在"技术上下文速查"节末尾插入新子节 ────────────────────────────────
# 定位：找 "## 技术上下文速查" 后、下一个 "## " 节之前的最后一个非空行
# 在其后插入新的 ### 子节

new_section_lines = [
    f'\n',
    f'### {module_name} 关键路径\n',
    f'```\n',
]
for tree_line in call_tree.split('\n'):
    new_section_lines.append(tree_line + '\n')
if structs:
    new_section_lines.append(f'关键结构体：{structs}\n')
new_section_lines.append('```\n')
new_section_lines.append('\n')
new_section_lines.append(f'- 本地源码：`<kernel-source-root>/{source_path}`\n')

in_section = False
last_content_line = -1
next_section_line = -1

for i, line in enumerate(lines):
    if line.startswith('## 技术上下文速查'):
        in_section = True
        continue
    if in_section:
        if line.startswith('## '):
            next_section_line = i
            break
        if line.strip():
            last_content_line = i

if last_content_line == -1:
    print("error: '## 技术上下文速查' section not found or empty", file=sys.stderr)
    sys.exit(4)

insert_pos = last_content_line + 1
for j, new_line in enumerate(new_section_lines):
    lines.insert(insert_pos + j, new_line)

with open(claude_file, 'w') as f:
    f.writelines(lines)

print(f"updated: CLAUDE.md (学习领域 + {module_name} 速查节)")
PYEOF
