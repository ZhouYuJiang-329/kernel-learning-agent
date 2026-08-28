#!/usr/bin/env bash
# find_changed_files.sh — 列出待同步到 Obsidian 的 learn/ 文件
#
# 用法：
#   find_changed_files.sh --session   本次会话中写入/修改的文件（由 capture-reminder hook 记录）
#   find_changed_files.sh --all       learn/ 下全部 .md 文件
#
# 输出：每行一个绝对路径，供 obsidian-sync 逐个处理。
#
# --session 模式说明：
#   依赖 /tmp/kernel-learning-changed.txt，由 capture-reminder.sh hook 在每次写入
#   learn/*.md 时追加路径。用户手动要求"同步本次笔记"时使用此模式；会话结束后日志自动消失。
#   若日志文件不存在（本次会话未写任何 learn/ 文件），输出为空。
#
# 退出码：0=成功（包括输出为空）  1=参数错误

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# scripts/ -> obsidian-sync/ -> skills/ -> .claude/ -> 项目根 -> learn/
LEARN_DIR="${SCRIPT_DIR}/../../../../learn"
CHANGED_LOG="/tmp/kernel-learning-changed.txt"

MODE="${1:-}"

case "$MODE" in
    --session)
        if [[ ! -f "$CHANGED_LOG" ]]; then
            # 本次会话未写任何 learn/ 文件，输出空
            exit 0
        fi
        # 去重、过滤已删除的文件
        sort -u "$CHANGED_LOG" | while IFS= read -r path; do
            [[ -f "$path" ]] && echo "$path"
        done
        ;;
    --all)
        find "$(realpath "$LEARN_DIR")" -name "*.md" -type f | sort
        ;;
    *)
        echo "usage: find_changed_files.sh --session | --all" >&2
        exit 1
        ;;
esac
