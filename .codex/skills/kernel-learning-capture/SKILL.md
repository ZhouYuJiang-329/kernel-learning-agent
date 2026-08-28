---
name: kernel-learning-capture
description: >
  完成内核概念分析后，提取知识点并更新 memory 文件（knowledge.md、dep-graph.md、MEMORY.md、open-questions.md）。
  当用户说"记录这个"、"更新笔记"、"capture"、"我理解了"时手动触发。
  也在 kernel-code-analyzer 分析完成后自动链式调用。
---

# Kernel Learning Capture Skill

## 触发条件

**自动触发**：kernel-code-analyzer 分析完成后链式调用

**手动触发**：记录这个 / capture / 更新笔记 / 我理解了 X / 这部分清楚了 / 把这个加到知识库

**迁移触发**："归类 X 到 {模块}" / "把 X 移到 {模块}" → 调用 `add-learning-module` skill 的 reclassify 流程

## 执行流程

### Step 1：提取本次分析的知识节点

从刚完成的分析中提取：
- **新增函数/结构体**：名称、所属子系统
- **掌握深度判断**：
  - 只看了定义 → `exploring`，置信度 40
  - 看了调用链 + 逐行分析 → `exploring`，置信度 60
  - 理解了设计动机 + 能回答"为什么不用更简单方案" → `mastered`，置信度 85
  - 用户明确说"我理解了" → 置信度 +15（上限 100）
- **笔记文件路径**（如果写了文件）：`learn/xxx/yyy.md`
- **新增疑问**：分析过程中遇到的未解答问题

### Step 1.5：确认子系统目录，决定归属

```bash
ls "$(dirname "$0")/../../../memory/"
```

- **目录存在** → 继续 Step 2，归入该子系统
- **目录不存在，归属不确定** → 归入 `unclassified/`，subsystem 参数用 `unclassified`，Step 7 追加暂存提示
- **目录不存在，归属明确** → 停止所有写操作，输出：

```
[capture 中止] {函数名} 属于 {子系统}，但 memory/{subsystem}/ 未初始化。
先说"我要开始学 {subsystem}"完成初始化，再重新说"分析 {函数名}"。
```

### Step 2（可选）：搜索 Confluence 内部文档

**仅当节点状态为 unknown 或 not_found 时执行**（exploring/mastered 跳过）。

```
confluence_search("{函数名或子系统名} 内核")
```

- 搜到 → 摘要 1-3 句，页面标题存入 Step 3 的 internal_doc 列
- 无结果 → internal_doc 列填 `-`
- 与 kernel-graph 有出入 → 记入 open-questions.md（MEDIUM 级）

### Step 3：更新 knowledge.md

```bash
.claude/scripts/upsert_node.sh {subsystem} {name} {type} {status} {confidence} {note} {internal_doc} [--section "{节名}"]
```

`--section` 节名参照：

| 函数类型 | 节名 |
|---------|------|
| 调度骨架（__schedule、rq 等） | `调度器骨架` |
| CFS 相关（fair、vruntime 等） | `CFS（完全公平调度）` |
| RT 相关（rt_rq、sched_rt 等） | `RT（实时调度）` |
| Deadline 相关（dl_rq 等） | `Deadline（EDF）` |
| MPAM resctrl 层 | `resctrl 文件系统层` |
| MPAM ARM 硬件层 | `ARM 硬件接口层` |
| 新子系统 / 无明确分类 | 不传 `--section` |

### Step 3.5（可选）：回填概念 primer 里的"待验证"标注

**仅当** `learn/{subsystem}/{MODULE_KEY}_concepts.md` 存在，且本次分析的函数/结构体在该 primer 的术语速查表里被引用为"待验证"的对照关系时执行。

对照本次分析得到的真实结论（调用链、字段语义、设计动机），检查 primer 里对应那一行"待验证"的猜测是否成立：

- **成立** → 编辑该文件，去掉"待验证"标注，补一句基于本次真实分析的确认依据（可引用本次笔记路径）
- **不成立/需要修正** → 编辑该文件，更正对照关系，标注修正日期和依据
- **primer 不存在或本次分析未涉及任何"待验证"术语** → 跳过本步骤，不新建 primer（primer 只在 `kernel-reading-guide` Step 2.5 按其自身触发条件生成）

本步骤只做**回填修正**，不允许在这里新增 primer 没有的术语小节或整段重写背景介绍——那超出了"更新已有笔记"的范围，属于 `kernel-reading-guide` 的职责。

### Step 4：更新 open-questions.md

**追加新问题**（每个疑问一次）：

```bash
.claude/skills/kernel-learning-capture/scripts/append_question.sh \
  <CRITICAL|MEDIUM|LOW> \
  "<问题描述>" \
  "<YYYY-MM-DD 分析 {函数名} 时发现>" \
  "<相关函数列表>" \
  "<当前假设，无则传 ->" \
  "<建议查询命令>"
```

**解答已有问题**（本次分析解答了某个 OQ）：

```bash
.claude/skills/kernel-learning-capture/scripts/resolve_question.sh <OQ-NNN> "<一句话结论>"
```

### Step 5：更新依赖图

对本次 MCP 查询中确认的每条**直接**调用关系（`call_chain_down depth=1` 或 `find_callees`），调用脚本追加：

```bash
.claude/skills/kernel-learning-capture/scripts/append_dep_edge.sh \
  {subsystem} {parent_func} {child_func} "{子函数说明}"
```

- 已存在的边 → 脚本自动跳过（输出 `skipped:`）
- 不存在的边 → 脚本追加并对齐缩进（输出 `appended:`）
- **只追加 MCP 确认的直接关系，不凭记忆补充**
- `unclassified` 子系统正常追加，迁移后手动移至目标 dep-graph.md

详细追加规则见 [references/dep-graph-rules.md](references/dep-graph-rules.md)。

### Step 6：更新 MEMORY.md

```bash
.claude/skills/kernel-learning-capture/scripts/update_memory.sh {subsystem} {func_name}
```

脚本原子完成三处更新：
1. 调用 `count_stats.sh --all` 刷新子系统列表表格数字
2. 向"最近 5 个分析"追加本次，超出 5 条自动移除最旧
3. grep `open-questions.md` 统计 CRITICAL/MEDIUM/LOW 数量，刷新"开放问题统计"行

### Step 7：输出捕获摘要

```
[已捕获学习进度]
新增节点：{函数名}（{状态}, {置信度}）
笔记位置：{路径 或 无}
新增疑问：{OQ-NNN（优先级）— 问题摘要 或 无}
建议下一步：{具体建议}
```

若本次产生新疑问，capture 完成后自动链式调用 `kernel-qa-log` skill。
若节点归入 `unclassified/`，追加：`[暂存] 确定后说"归类 {函数名} 到 {模块}"完成迁移。`

## Scripts

- **`scripts/append_question.sh`** — 向 open-questions.md 追加新问题，自动分配编号。在 Step 4 调用。
- **`scripts/resolve_question.sh`** — 将已解答 OQ 移至归档节。在 Step 4 调用。
- **`scripts/append_dep_edge.sh`** — 向 dep-graph.md 追加调用关系边，自动去重和缩进。在 Step 5 调用。
- **`scripts/update_memory.sh`** — 刷新 MEMORY.md 三处（表格数字、最近分析、OQ 统计）。在 Step 6 调用。

## References

- **`references/dep-graph-rules.md`** — dep-graph.md 格式规范和边界情况详解（unclassified 处理、不重复检查规则等）。

## 质量检查

- [ ] 置信度是数字（0-100），不是文字
- [ ] Step 1.5 已确认子系统目录归属（存在 / unclassified / 中止三选一）
- [ ] `upsert_node.sh` 输出 `updated:` 或 `inserted:`，无 error
- [ ] `append_dep_edge.sh` 每条边都输出 `appended:` 或 `skipped:`，无 error
- [ ] `update_memory.sh` 输出 `updated: MEMORY.md`，无 error
- [ ] 疑问描述具体，含相关函数和建议查询命令
- [ ] dep-graph 追加的关系来自本次 MCP 查询，不凭记忆填写
- [ ] Step 3.5：若概念 primer 存在且本次分析涉及其"待验证"术语，已回填修正；未涉及则跳过，未越权新增内容

## Version History

- v1.1.0 (2026-07-06): 新增 Step 3.5——回填概念 primer（`{MODULE_KEY}_concepts.md`）里的"待验证"术语标注，只做修正不新增内容，与 kernel-reading-guide Step 2.5 的 primer 生成职责划清边界
- v1.0.0 (2026-06-30): 初始版本，Step5/6 全部脚本化，移除 reclassify 内嵌流程，修复绝对路径
