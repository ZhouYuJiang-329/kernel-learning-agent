---
name: kernel-progress-report
description: >
  读取 memory 文件，生成结构化学习进度报告，包含各子系统掌握统计、带状态的知识树、
  开放问题汇总和具体下一步建议。
  当用户说"我学到哪了"、"进度报告"、"总结一下"、"我现在掌握了什么"、"下一步学什么"、
  "progress"、"summary"、"what have I learned"时触发。
  仅输出文字报告；如需可视化仪表盘请启动 `dashboard/server.py`（端口 7788）。
---

# Kernel Progress Report Skill

## 执行流程

### Step 1：读取 memory 文件

```bash
# 获取各子系统统计数字（自动排除 unclassified 暂存区）
.claude/scripts/count_stats.sh --all
```

同时读取：
- `.claude/memory/MEMORY.md` — 子系统列表和当前学习焦点
- `.claude/memory/open-questions.md` — 开放问题（取 CRITICAL + MEDIUM 部分）
- `.claude/memory/learning-journal.md` — 最近 5 个会话条目

### Step 2：生成统计数据

使用 `count_stats.sh --all` 的输出填写总体表格，**不手动 grep 估算**：

```
mpam  mastered=0 exploring=23 unknown=0  avg_conf=55.0
sched mastered=0 exploring=0  unknown=23 avg_conf=-
```

从 `open-questions.md` grep 统计问题数：

```bash
grep -c "^### OQ-" .claude/memory/open-questions.md || true
grep -c "CRITICAL" .claude/memory/open-questions.md || true
```

### Step 3：构建知识树

调用脚本将 dep-graph.md 的 ASCII 树与 knowledge.md 的状态表格合并：

```bash
# 单个子系统
python3 .claude/skills/kernel-progress-report/scripts/generate_tree.py sched

# 所有子系统
python3 .claude/skills/kernel-progress-report/scripts/generate_tree.py --all
```

脚本自动在每个函数名后追加 `[status, conf]`，有笔记的节点追加 `✓`。

### Step 4：生成下一步建议

基于以下逻辑推荐 3 个选项：

1. **选项 A — 解决 CRITICAL 疑问**（若有）：列出 CRITICAL 问题编号和具体 MCP 查询命令；若无 CRITICAL 则改为最高优先级 MEDIUM 问题
2. **选项 B — 深化已探索节点**：找 `exploring` 中置信度最高的节点，给出提升到 `mastered` 的具体分析命令
3. **选项 C — 开拓新节点**：在知识树中找已 `exploring` 节点的直接下游，推荐下一个分析目标

### Step 5：输出格式

```markdown
# 学习进度报告 — {当前日期}

## 总体概况

| 子系统 | 掌握 | 探索中 | 未知 | 平均置信度 |
|--------|------|--------|------|-----------|
| {来自 count_stats.sh 输出，动态行数} |

累计有笔记节点：N 个 ｜ 开放问题：N 个（CRITICAL: N）

## 知识树（当前状态）

{来自 generate_tree.py --all 输出}

## 开放问题摘要

### CRITICAL（阻塞学习进展）
- OQ-NNN：{摘要} → `{具体 MCP 查询命令}`

### MEDIUM
- OQ-NNN：{摘要}

## 建议的下一步（3 选 1）

### 选项 A：{标题}（推荐）
- 目标：{具体目标}
- 方法：{含 MCP 命令}
- 预期收获：{节点状态变化}

### 选项 B：{标题}
- 目标：{具体目标}
- 预期收获：{打通哪条路径}

### 选项 C：{标题}（新方向）
- 目标：{具体目标}
- 预期收获：{建立哪个新知识节点}

---
*报告基于 .claude/memory/ 文件*
```

## Scripts

- **`scripts/generate_tree.py`** — 合并 `dep-graph.md` 树与 `knowledge.md` 状态，输出带 `[status, conf]` 标注的 ASCII 树。接收 `<subsystem>` 或 `--all`，自动跳过 unclassified。在 Step 3 调用。

## 质量检查

- [ ] Step 2 统计数字来自 `count_stats.sh --all` 输出，未手动估算
- [ ] 知识树来自 `generate_tree.py` 输出，每个节点都有状态标注
- [ ] 建议选项包含具体 MCP 命令（`find_definition`/`call_chain_up` 等），不泛泛说"继续学习"
- [ ] 若有 CRITICAL 问题，选项 A 必须针对该问题
- [ ] 表格行数与实际子系统数一致（不含 unclassified）

## Version History

- v1.0.0 (2026-06-30): 初始版本，修复 knowledge-map.md 旧引用，统计和知识树全部脚本化
