#!/usr/bin/env bash
# PostToolUse hook: 仅对 experiments/ 下的内核模块 .c 文件输出提示
# 输入：环境变量 CLAUDE_TOOL_INPUT_FILE_PATH（Claude Code 注入）

FILE="${CLAUDE_TOOL_INPUT_FILE_PATH:-}"

# 条件1：路径包含 experiments/
[[ "$FILE" == *experiments/* ]] || exit 0

# 条件2：扩展名为 .c
[[ "$FILE" == *.c ]] || exit 0

# 条件3：文件包含内核模块头文件
grep -q '#include <linux/module.h>' "$FILE" 2>/dev/null || exit 0

# 三个条件全满足，输出提示
DIR=$(dirname "$FILE")
BASENAME=$(basename "$FILE")

echo "[内核模块检查]"
echo "编译命令：cd $DIR && make -C /lib/modules/\$(uname -r)/build M=\$(pwd) modules"

if ! grep -q 'MODULE_LICENSE' "$FILE" 2>/dev/null; then
    echo "⚠️  警告：缺少 MODULE_LICENSE，insmod 时会触发内核 taint"
fi

echo "代码风格：scripts/checkpatch.pl --no-tree -f $BASENAME"
