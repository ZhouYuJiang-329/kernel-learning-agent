---
name: kernel-impact-analyzer
description: >
  分析修改内核函数或结构体字段的影响范围，生成分级影响报告。
  当用户说"影响分析"、"impact"、"改这个安全吗"、"改完要测哪些"、
  "这个改动影响哪些地方"、"波及范围"、"what breaks"、"who calls this"时触发。
---

# Kernel Impact Analyzer Skill

## 两种分析模式

- **模式 A — 函数修改**：用户修改或计划修改某个函数的行为
- **模式 B — 结构体字段修改**：用户添加/删除/修改结构体的某个字段

若用户未说明，询问一个问题："是函数修改还是结构体字段修改？函数/结构体名是？"

## 执行流程

### Step 0：收集基本信息

确认以下信息（若用户已提供则无需询问）：
- 分析目标：函数名 或 结构体名+字段名
- 修改类型：函数行为变更 / 字段类型变更 / 字段增删

### Step 1：MCP 并行查询

**模式 A（函数修改）**：

```
并行执行：
1. find_definition(函数名)           → 确认源码位置
2. call_chain_up(函数名, depth=5)    → 完整上游调用树（含深度信息）
3. find_callers(函数名)              → 直接调用者（补充 call_chain_up 第 1 层）
```

**模式 B（结构体字段修改）**：

```
并行执行：
1. find_struct(结构体名)                      → 字段列表和位置
2. find_struct_writers(结构体名, 字段名)      → 写入该字段的函数（Level 1 主要来源）
3. search_functions(结构体名)                 → 所有引用该结构体的函数（Level 2/3 来源）
```

> 注意：模式 B **不使用** `find_callers(结构体名)`，结构体不是函数，该调用无意义。

### Step 2：影响分级与去重

将 Step 1 查询结果整理为输入文件，调用分级脚本：

```bash
# 输入格式（每行一条）：
# depth=N  func_name  file:line   （来自 call_chain_up）
# func_name  file:line             （来自 find_callers，视为 depth=1）

python3 .claude/skills/kernel-impact-analyzer/scripts/classify_impact.py input.txt
```

脚本自动按深度分为三级并**跨级去重**（同一函数只出现在最低 Level）：

| Level | 来源 | 深度 | 测试优先级 |
|-------|------|------|-----------|
| Level 1 | find_callers + call_chain_up depth=1 | 1 | P0 必测 |
| Level 2 | call_chain_up depth=2 | 2 | P1 建议 |
| Level 3 | call_chain_up depth=3-5 | 3-5 | P2 回归 |

模式 B 的 **Level 4**（数据结构传播）：取 `find_struct_writers` 结果中不在 Level 1-3 的部分，人工补入报告。**模式 A 跳过 Level 4。**

### Step 3：识别关键路径标签

脚本输出已自动标注，规则如下：

| 标签 | 匹配函数名关键词 | 含义 |
|------|---------------|------|
| `HOT_PATH` | `__schedule`、`pick_next_task`、`enqueue_task`、`dequeue_task`、`scheduler_tick` | 调度热路径，性能敏感 |
| `SMP_SENSITIVE` | `rq_lock`、`rq_unlock`、`raw_spin_lock`、`cpu_rq`、`this_rq` | runqueue 锁操作，死锁风险 |
| `RT_SENSITIVE` | `rt_rq`、`dl_rq`、`sched_rt`、`sched_dl` | 实时/Deadline 调度路径 |
| `MPAM_SENSITIVE` | `rdtgroup`、`resctrl`、`closid`、`rmid`、`rdt_resource`、`mpam` | MPAM/resctrl 资源隔离路径 |

### Step 4：生成影响报告

读取 [templates/impact-report.md](templates/impact-report.md)，用 Step 2-3 的结果填充所有 `{占位符}`：

- `{TARGET}` → 函数名或结构体名
- `{DATE}` → 今天日期
- `{CHANGE_DESCRIPTION}` → 用户描述的修改内容
- `{N1}/{N2}/{N3}/{N4}` → 各级函数数量
- Level 1-3 表格 → 来自 classify_impact.py 输出
- Level 4 → 模式 A 时整节跳过，模式 B 时填入 find_struct_writers 补充结果
- 关键路径警告节 → 仅当对应标签存在时输出，其余跳过

### Step 5（可选）：联动 drawio-diagram-generator

若用户确认生成图，调用 drawio-diagram-generator skill：

- 传入内容：Level 1-2 的调用关系文本（ASCII 树格式，来自 call_chain_up 原始输出）
- 输出路径：`learn/{subsystem}/impact-{target}-{date}.drawio`
- 触发方式：在报告末尾询问 "是否生成调用链影响范围图？（输入 y 触发）"

## Scripts

- **`scripts/classify_impact.py`** — 解析 call_chain_up / find_callers 输出，按深度分 Level 1/2/3 并跨级去重，自动标注 HOT_PATH / SMP_SENSITIVE / RT_SENSITIVE / MPAM_SENSITIVE，输出 markdown 表格。在 Step 2 调用。

## Templates

- **`templates/impact-report.md`** — 完整报告模板，包含所有节和占位符说明。在 Step 4 读取并填充。

## 质量检查

- [ ] 所有函数的文件路径来自 MCP `find_definition`，不依赖记忆
- [ ] 使用 `classify_impact.py` 输出，同一函数不出现在多个 Level
- [ ] HOT_PATH / SMP_SENSITIVE / RT_SENSITIVE / MPAM_SENSITIVE 标注来自脚本自动检测
- [ ] 模式 A：Level 4 节已跳过，报告中无空的数据结构传播节
- [ ] 模式 B：`find_struct_writers` 有返回结果（若返回空需核实字段名拼写）
- [ ] 关键路径警告节：无对应标签时整节跳过，不输出空节
- [ ] 测试策略给出具体工具名（kprobe/bpftrace/schbench/cyclictest），不泛泛说"测试"

## Version History

- v1.0.0 (2026-06-30): 初始版本，模式 A/B 分离，脚本化去重与标签检测，MPAM 标签支持，报告模板外移
