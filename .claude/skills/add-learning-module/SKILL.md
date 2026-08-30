---
name: add-learning-module
description: >
  向工程中添加新的内核学习板块。当用户说"我要开始学 X"、"新增模块 X"、
  "添加学习板块"、"add module X"、"start learning X"时触发。
---

# Add Learning Module Skill

## 执行流程

### Step 0：收集模块信息

若用户已说明模块名称，直接使用；否则询问：
"要添加的内核子系统名称是什么？（如：kprobe、内存管理、中断子系统）"

确定以下信息：
- `MODULE_NAME`：显示名称，如 "kprobe 探针机制"
- `MODULE_KEY`：目录键名（小写下划线），如 `kprobe`

### Step 1：并行查询 kernel-graph-linux7.2rc6

**并行执行：**

```
kernel-graph:
  search_functions(MODULE_KEY)       → 找候选入口函数（取前 3 个）
  find_definition(入口函数)           → 确认源码路径（用于 Step 3/4）
  call_chain_down(入口函数, depth=2)  → 获取调用树（用于 Step 3/4）
  find_struct(核心结构体)             → 获取关键结构体（用于 Step 4）
```



### Step 2：初始化 memory 和 learn 目录

```bash
.claude/skills/add-learning-module/scripts/init_module.sh \
  {MODULE_KEY} "{MODULE_NAME}" {入口函数1} {入口函数2} ...
```

脚本原子创建：
- `memory/{MODULE_KEY}/knowledge.md` — 含入口函数初始行
- `memory/{MODULE_KEY}/dep-graph.md` — 含入口函数占位节点
- `memory/{MODULE_KEY}/qa-log.md` — 空问答日志
- `learn/{MODULE_KEY}/_index.md` — Obsidian 目录页

同时精确更新 `memory/MEMORY.md` 三处（子系统列表、当前学习焦点、知识状态）。

### Step 3：更新 CLAUDE.md

```bash
.claude/skills/add-learning-module/scripts/update_claude_md.sh \
  {MODULE_KEY} \
  "{MODULE_NAME}" \
  "{源码路径，来自 find_definition，如 kernel/kprobes.c}" \
  "{调用树，换行用 \n，来自 call_chain_down}" \
  "{关键结构体，来自 find_struct，无则省略}"
```

脚本按内容定位（不依赖行号），同时更新：
- `> 学习领域：` 首行追加 `+ {MODULE_NAME}`
- `## 技术上下文速查` 节末尾插入新子节

### Step 4：生成 specialist agent

```bash
.claude/skills/add-learning-module/scripts/init_agent.sh \
  {MODULE_KEY} \
  "{MODULE_NAME}" \
  "{源码路径，来自 find_definition}" \
  "{调用树，换行用 \n}" \
  "{关键结构体，无则省略}"
```

### Step 5：触发 kernel-reading-guide

自动调用 `kernel-reading-guide` skill，基于 Step 1 的 MCP 查询结果生成该模块的阅读需求文档，并初始化骨架图。

- 输出目标：`learn/{MODULE_KEY}/{MODULE_KEY}_read_guide.md`（只含大框架路线图，不含函数深度解析）
- 骨架图写入：`memory/{MODULE_KEY}/dep-graph.md` + `knowledge.md`
- 调用kernel-concept-mapper这个skill额外生成 `learn/{MODULE_KEY}/{MODULE_KEY}_concepts.md`（基础概念 primer）——这一步由 kernel-reading-guide 自身的触发条件判断，本 skill 不单独控制
- skill 执行完后继续 Step 6

### Step 6：输出完成摘要

```
[新模块已添加：{MODULE_NAME}]

创建的文件：
- memory/{MODULE_KEY}/knowledge.md（{N} 个初始节点）
- memory/{MODULE_KEY}/dep-graph.md
- memory/{MODULE_KEY}/qa-log.md
- learn/{MODULE_KEY}/_index.md
- .claude/agents/{MODULE_KEY}-specialist.md
- learn/{MODULE_KEY}/{MODULE_KEY}_read_guide.md（阅读路线图）
- learn/{MODULE_KEY}/{MODULE_KEY}_concepts.md（若生成了基础概念 primer，注明"已生成"，否则不列出此行）

更新的文件：
- memory/MEMORY.md（子系统列表 + 学习焦点 + 知识状态）
- CLAUDE.md（学习领域首行 + 速查节）

建议第一步：
{若已生成 concepts primer → "先读 learn/{MODULE_KEY}/{MODULE_KEY}_concepts.md 熟悉基础术语，再说"解释 {入口函数1}"深入分析。"}
{若未生成 → "说"解释 {入口函数1}"开始分析，或派遣 {MODULE_KEY}-specialist agent。"}
```

## Scripts

- **`scripts/init_module.sh`** — 原子初始化 memory 三文件 + `learn/_index.md` + 更新 MEMORY.md。在 Step 2 调用。
- **`scripts/update_claude_md.sh`** — 更新 CLAUDE.md 学习领域行和速查节。在 Step 3 调用。
- **`scripts/init_agent.sh`** — 生成格式固定的 specialist agent 文件。在 Step 4 调用。

所有脚本的退出码：`0`=成功，`1`=参数错误，`2`=目标已存在，`3`=依赖文件不存在。

## 质量检查

- [ ] `init_module.sh` 输出四行 `created:` + 一行 `updated:`，无 error
- [ ] `update_claude_md.sh` 输出一行 `updated:`，无 error
- [ ] `init_agent.sh` 输出一行 `created:`，无 error
- [ ] knowledge.md 的入口函数来自 MCP 真实查询，不凭记忆填写
- [ ] CLAUDE.md 速查节的源码路径来自 `find_definition` 结果
- [ ] specialist agent 的"核心调用路径"节包含来自 MCP 查询的真实函数名
- [ ] Step 6 摘要中 concepts primer 行的有无与 kernel-reading-guide 的实际产出一致（不臆测）

## Version History

- v1.1.0 (2026-07-06): Step 5/6 同步 kernel-reading-guide v1.3.0 新增的概念 primer 能力——若生成了 primer，Step 6 摘要列出该文件并调整"建议第一步"为先读 primer；本 skill 不单独判断是否生成 primer，触发条件完全由 kernel-reading-guide 自身控制
- v1.0.0 (2026-06-30): 初始版本，Step 2/3/4 全部脚本化，消除格式漂移风险
