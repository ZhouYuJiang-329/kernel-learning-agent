---
name: obsidian-sync
description: >
  将 learn/ 目录下的内核学习笔记同步到 Obsidian vault，自动生成双向链接。
  仅在用户明确说"同步 obsidian"、"push obsidian"、"写到 obsidian"、"obsidian 同步"、
  "sync obsidian"、"推送笔记"时手动触发。不由任何 hook 自动调用。
---

# Obsidian Sync Skill

## Vault 路径规则

- **映射**：`learn/{path}.md` → vault 路径 `learn/{path}.md`（一一对应）
- **vault 根目录**：`/mnt/c/Users/yujizhou/doc/confludec/`
- **只同步 learn/ 目录**，不写 `.claude/memory/` 等内部文件

## 执行流程

### Step 1：发现待同步文件

**用户说"同步本次笔记"/"同步这次的笔记"**（只同步本次会话变化文件）：

```bash
.claude/skills/obsidian-sync/scripts/find_changed_files.sh --session
```

脚本读取 `/tmp/kernel-learning-changed.txt`（由 `capture-reminder.sh` hook 在每次写入 `learn/*.md` 时追加），输出去重后的绝对路径列表。若文件不存在，输出为空 → 跳过同步。

**用户说"同步 obsidian"等未指定范围时**（默认全量同步）：

```bash
.claude/skills/obsidian-sync/scripts/find_changed_files.sh --all
```

若输出为空，告知用户 `learn/` 目录下暂无笔记文件。

### Step 2：对每个文件，构建双向链接列表

从以下三个来源收集应链接的笔记名，**并集去重，排除自身文件名**：

**来源 A — 正文中直接提到的函数/结构体名**：

1. 扫描文件正文，提取匹配 `[a-z_][a-z0-9_]*` 且长度 >= 5 的词
2. **过滤**：用 `grep -r` 在 `.claude/memory/*/knowledge.md` 中确认该词存在于知识库（精确匹配表格第一列 `^| {词} |`），排除普通英文词
3. 用 `mcp__obsidian__vault_list` 确认 vault 中对应笔记存在，不存在则保留为 `[[名称]]` 占位但不主动建文件

**来源 B — 当前笔记所在子系统的依赖图**：

读取 `.claude/memory/{当前笔记子系统}/dep-graph.md`（只读一个文件，不遍历所有子系统），找该函数的直接上游和下游节点加入列表。

**来源 C — 同子系统目录内已有笔记**：

用 `mcp__obsidian__vault_list` 列出同目录已有笔记，全部加入列表。

### Step 3：判断 vault 中笔记是否已存在

用 `mcp__obsidian__vault_read` 尝试读取目标路径：

- **读取成功** → 笔记已存在，走 Step 5（更新关联文档行）
- **读取失败** → 笔记不存在，走 Step 4（新建）

### Step 4：新建笔记

用 `mcp__obsidian__vault_write` 写入，内容来自本地 `learn/` 源文件，并在文件头 blockquote 区块（`>` 开头的连续行）的**最后一个 `>` 行之后**插入关联文档行：

```markdown
**关联文档**：[[链接1]] · [[链接2]] · [[链接3]]
```

若文件头无 blockquote 区块，在文件第一行后追加。

### Step 5：更新已有笔记的关联文档行

用 `mcp__obsidian__vault_patch` 操作，**只更新关联文档行，不覆盖正文**：

1. 检查正文中是否已有 `**关联文档**：` 行：
   - **已有**：读取现有链接，与新生成列表取并集（只增不删），用 `vault_patch` 替换该行
   - **无**：在 blockquote 区块的最后一个 `>` 行之后追加该行

关联文档行格式：`**关联文档**：[[名称1]] · [[名称2]]`（链接名=文件名去掉 `.md`，分隔符为 ` · `）

### Step 6：输出同步摘要

```
[Obsidian 同步完成]
新建：N 个文件
  - learn/sched/cfs/enqueue_task_fair.md（链接：[[task_struct]] · [[cfs_rq]]）
更新关联文档：N 个文件
  - learn/sched/task_struct.md（新增链接：[[enqueue_task_fair]]）
跳过（无变化）：N 个文件
```

## Scripts

- **`scripts/find_changed_files.sh`** — 列出待同步文件。`--session` 读 hook 写入的变更日志（Stop hook 场景），`--all` 扫描全部 learn/*.md（手动触发场景）。在 Step 1 调用。

## 质量检查

- [ ] Step 1 使用 `find_changed_files.sh` 获取文件列表，不依赖 mtime 比较
- [ ] 来源 A 的函数名已通过 `grep "^| {词} |" memory/*/knowledge.md` 过滤，无普通英文词
- [ ] 只同步 `learn/` 下的文件，未向 vault 写入任何 `.claude/memory/` 内容
- [ ] Step 3 使用 `vault_read` 判断存在性，非 `vault_list` 遍历
- [ ] 关联文档行插入位置正确：在 blockquote 区块最后一个 `>` 行之后
- [ ] 已有关联文档行时，只增不删现有链接
- [ ] 输出摘要列出每个文件的具体操作

## Version History

- v1.0.0 (2026-06-30): 初始版本，修复文件发现机制（hook 日志替代 mtime），来源 A 加知识库过滤，来源 B 只读当前子系统，存在性判断改用 vault_read
