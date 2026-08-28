#!/usr/bin/env bash
# PostToolUse hook: 写入 learn/ 笔记后提醒调用 kernel-learning-capture skill
# 同时将文件路径追加到 /tmp/kernel-learning-changed.txt，供 obsidian-sync 使用
# 输入：环境变量 CLAUDE_TOOL_INPUT_FILE_PATH（Claude Code 注入）

FILE="${CLAUDE_TOOL_INPUT_FILE_PATH:-}"

# 仅对 learn/ 目录下的 .md 文件触发
[[ "$FILE" == *learn/*.md ]] || exit 0

# 记录到本次会话变更日志（obsidian-sync 的 --session 模式读取此文件）
echo "$FILE" >> /tmp/kernel-learning-changed.txt

echo "[capture-reminder] 检测到写入 learn/ 笔记：$(basename "$FILE")"
echo "请确认已调用 kernel-learning-capture skill。若尚未调用，现在执行 capture 流程。"
