---
name: kernel-reading-guide
description: >
  根据工程 C 代码生成内核代码阅读需求文档（大框架路线图）：分类、"读完能解决的问题"、
  关键源文件定位、关键数据结构阅读主线、阅读顺序、API 检索表。当用户说"帮我梳理内核代码"、"我需要阅读哪些内核代码"、
  "生成内核阅读文档"、"需要了解哪些内核知识"、"帮我分析需要读什么"时触发。
  也适用于用户粘贴内核模块或 driver 代码后询问需要阅读哪些内核代码的场景。
  若该模块存在贯穿多个函数的领域术语且已有 Confluence 架构综述，会先判断是否需要生成
  一份不涉及代码的基础概念 primer（`{MODULE_KEY}_concepts.md`），避免用户读完函数级
  深度笔记后仍看不懂基础术语。
  ⚠️ 只产出大框架路线图，绝不做单个函数的深度解析（逐行详解/调用链树/结构体字段速查）——
  那是 kernel-code-analyzer 的职责，本 skill 只能以链接引用其产出文件，不能内联复制细节。
  输出文件固定为 learn/{MODULE_KEY}/{MODULE_KEY}_read_guide.md（旧命名 KernelRead.md 已废弃）。
---

# Kernel Reading Guide Skill

## 执行流程

### Step 1：扫描工程代码，提取 API 列表

扫描当前工程目录，重点读取：
- 所有 `.c` / `.h` 文件（尤其是 `#include <linux/xxx.h>` 列表）
- `Makefile` / `Kconfig`（了解编译依赖）
- 已有的 `learn/` 目录（了解已覆盖的内容，避免重复）

**若工程目录无 .c 文件**：提示用户粘贴代码片段或指定文件路径后继续。

提取：
- 所有内核头文件（`#include <linux/xxx.h>`）
- 所有调用的内核 API 和结构体名
- 涉及的内核子系统（从头文件推断）

提取完成后，**立即执行 Step 2 的 MCP 查询**，再继续后续步骤。

### Step 2：用 kernel-graph MCP 工具查询 API 定位（必须）

**在写任何文档内容之前，必须先用 MCP 工具确认 API 的真实位置。**

对 Step 1 提取的每个 API 和结构体，并行执行：

1. `find_definition(函数名)` → 准确的实现文件和行号
2. `find_struct(结构体名)` → 字段列表和所在文件
3. `search_functions(关键词)` → 函数名不确定时先搜索候选
4. `call_chain_up(核心API, depth=3)` → 核心 3-5 个 API 的触发场景（按需）

**查询失败（函数不在 kernel-graph DB）时的降级处理**：
- 在对应表格行的"行号"列填 `?`，备注"未在 Linux 6.0 DB 中找到，需手动确认"
- 继续生成文档，不因单个 API 查询失败而中止整体流程

查询结果用于 Step 4（关键源文件表格）和 Step 6（API 检索表）。**检索表中不允许填写未经 MCP 确认的文件路径。**

### Step 2.5：判断是否需要基础概念 primer（避免"看代码但看不懂术语"）

**动机**：函数级深度笔记（kernel-code-analyzer 产出）建立在一套领域概念之上（如 MPAM 的 PARTID/PMG/MSC）。如果这套概念从未被系统讲解过，用户会在读完多个函数笔记后仍然"看不懂基础术语"——这不是函数分析深度不够，而是缺了一层概念地图。本步骤判断当前模块是否需要先补一份不涉及代码的概念 primer。

**触发条件（必须同时满足，缺一不可）**：
1. 已有 Confluence 搜索结果（来自 `add-learning-module` Step 1，或本 skill 独立运行时临时执行 `confluence_search`），且其中**至少一页读起来是架构/原理综述**（标志：多个小节、成段落的背景介绍和模型讲解，而不是变更记录/会议纪要/单一 bug 描述）
2. 该综述内容包含若干**贯穿多个函数的领域术语**（如硬件寄存器名、协议角色名、缩略语），这些术语不是某一个函数的实现细节，而是理解整个模块都要用到的背景

**不满足则跳过**，不强行生成 primer，不允许仅凭训练知识/记忆编造背景讲解——没有真实材料支撑时，直接跳过本步骤，继续 Step 3。

**已存在 primer 时跳过创建**：检查 `memory/{subsystem}/knowledge.md` 中类型为 `concept` 或 `register` 的行，若存在"笔记"列不为 `-` 的行，说明 primer 已经存在于该路径，跳过创建，记下路径供 Step 9 引用。

**生成时的写法要求**：
- 内容来源仅限：(a) 已取回的 Confluence 页面正文，(b) Step 1/2 已确认的函数/结构体名（用于在术语表里做"硬件术语 ↔ 代码符号"对照）。**不允许引入 Confluence 和代码扫描之外的背景知识**。
- 结构：动机（为什么需要这套机制）→ 核心角色/模型（Confluence 里的架构讲解）→ 术语速查表（硬件术语 ↔ 已扫描到的代码符号，一一对应）
- 术语表里，如果某个对照关系**还没有被任何函数级分析实际验证过**（只是根据命名/描述猜测的对应关系），必须标注"待验证"，不能写得像已确认的事实——等后续 `kernel-code-analyzer` + `kernel-learning-capture`（见该 skill Step 3.5）分析到对应函数时再摘掉这个标注
- 输出路径：`learn/{MODULE_KEY}/{MODULE_KEY}_concepts.md`
- 生成后，把 `memory/{subsystem}/knowledge.md` 中对应的 concept/register 行的"笔记"列更新为这个路径（用 `.claude/scripts/upsert_node.sh`，若该脚本在当前项目不存在则跳过，仅生成文件）

### Step 3：分类归组

将 Step 1 提取的 API 和头文件按功能子系统归组。

**分类应从工程实际 `#include` 推导**，不要套用固定模板。参考候选分类见 [references/api-categories.md](references/api-categories.md)。

归组原则：
- 同一头文件下的 API 归为一类
- 只有 1-2 个 API 的分类可合并到相邻类，不单独成节
- 工程中未出现的子系统不列入文档

### Step 4：为每个分类生成"要解决的问题"

每个分类下生成 3-6 个**具体可验证**的问题：

- 用"如何……"或"怎样……"开头
- 问题必须与工程代码直接相关，不写泛泛的"了解 X 原理"
- 每个问题应有明确答案

**示例（调度器分类，针对使用了 `sched_setscheduler_nocheck` 的工程）**：
- 如何将内核线程设置为 `SCHED_FIFO` 实时调度，优先级设为 49？
- `sched_setscheduler_nocheck` 和 `sched_setscheduler` 的区别？什么时候用哪个？
- 如何避免高优先级 RT 线程被低优先级 CFS 线程阻塞（优先级反转）？

### Step 5：为每个分类列出关键源文件

**数据来源**：Step 2 的 `find_definition` 结果，文件路径和行号均来自 MCP。

```
| 文件 | 行号 | 重点关注 |
|------|------|---------|
| kernel/sched/core.c | 1234 | sched_setscheduler_nocheck(), set_user_nice() |
| include/linux/sched/rt.h | - | SCHED_FIFO, sched_param, MAX_RT_PRIO |
```

**⚠️ 边界（不可越界）**：本步骤只填"文件+行号+一句话关注点"。**禁止**在这里展开：
- 调用链 ASCII 树（谁调用了它 / 它调用了什么）
- 结构体逐字段解释（字段类型、含义、何时读写）
- 逐行代码详解

以上内容属于 kernel-code-analyzer 的产出。如果某个函数已经被 kernel-code-analyzer 分析过（`learn/{subsystem}/{function}.md` 已存在），这里只放一行链接，不复制内容；如果还没分析过，这里也不要代替它去做——路线图的职责止于"告诉读者去读哪个文件的哪一行"。

### Step 5.5：生成关键数据结构阅读主线

**触发条件**：Step 1/2 提取并确认了 3 个及以上结构体，或某个结构体贯穿多个分类/阶段（如 `task_struct`/`rq`/`sched_class`）。

本步骤的职责是把结构体组织成“先读什么、再读什么、它连接哪些函数/分类”的阅读路线，避免结构体只零散出现在 API 检索表里。

每个条目只写 4 类信息：
- 结构体名（来自 Step 2 的 `find_struct` 或已确认的源码位置）
- 所属分类/阅读阶段
- 阅读目的（一句话说明读它是为了解决什么问题）
- 连接关系（关联的关键函数、上游/下游结构体、已有深度笔记链接）

**禁止越界**：不展开逐字段解释，不复制结构体定义，不写字段读写时机。字段级内容只允许用“字段级细节见 `learn/{subsystem}/{struct}.md`”这类链接引用。

输出格式示例：

```markdown
## 关键数据结构阅读主线

1. `task_struct`：任务级调度状态入口，连接 `policy` 选择、`se/rt/dl` 三类调度实体和 `try_to_wake_up`/`context_switch` 等路径。
2. `rq`：每 CPU 运行队列，连接当前任务、调度类分发和 `cfs_rq`/`rt_rq`/`dl_rq` 子队列。
3. `sched_class`：调度类函数指针分发表，帮助理解 `__schedule` 如何统一调用 CFS/RT/Deadline/idle。
```

若 Step 2 未确认足够结构体，跳过本节，不编造结构体路线。

### Step 6：生成阅读顺序建议

按**知识依赖关系**排序，前置知识在前：

```
阶段 1（必读）：{基础分类} → {同步原语}
  收获：{具体能做什么}

阶段 2（必读）：{进阶分类}
  收获：{具体能做什么}

阶段 N（按需）：{专项分类}
  收获：{具体能做什么}
```

每个阶段给出预计天数和明确的阶段收获，不写"了解原理"这类模糊描述。

### Step 7：生成 API 快速检索表

**数据来源**：Step 2 的 `find_definition` 结果，全部来自 MCP 查询。

```
| API / 结构体 | 头文件 | 实现文件 | 行号 | 一句话说明 |
|------------|--------|---------|------|-----------|
| kthread_bind | linux/kthread.h | kernel/kthread.c | 389 | 绑定线程到指定 CPU，必须在 wake 前调用 |
```

行号列填 `?` 表示 MCP 查询未找到，需手动确认。

### Step 8：构建初始骨架图

**触发条件**：检查对应子系统 dep-graph.md 是否已有边：

```bash
grep -c "├──\|└──" .claude/memory/{subsystem}/dep-graph.md 2>/dev/null || echo 0
```

- **输出为 0（无边）** → 执行骨架图初始化
- **输出 > 0（已有边）** → 跳过，输出 `[骨架图] dep-graph 已有 N 条边，跳过初始化`

**骨架图初始化流程**：

**1. 确定核心函数集合（最多 5 个）**

优先取 `memory/{subsystem}/knowledge.md` 中已有记录的函数；若不足 5 个，从 Step 3 各分类的第 1 个函数补齐。

**2. 并行 MCP 查询**（对每个核心函数）：

```
call_chain_down(函数名, depth=2)
```

depth=2 提供两层调用关系，足以建立有意义的骨架，不会引入过多噪声。

**3. 写入 dep-graph.md**

对查询返回的每条调用边（depth=1 和 depth=2 的结果），调用：

```bash
.claude/skills/kernel-learning-capture/scripts/append_dep_edge.sh \
  {subsystem} {parent} {child} "{子函数说明}"
```

脚本自动去重和缩进对齐，已有边输出 `skipped:`，新边输出 `appended:`。

**4. 写入 knowledge.md**

对调用链中出现、但尚未在 `knowledge.md` 记录的函数：

```bash
.claude/scripts/upsert_node.sh \
  {subsystem} {name} function unknown 0 - - [--section "{节名}"]
```

状态初始化为 `unknown`，置信度 0，等待后续 `kernel-code-analyzer` 分析时更新。

**5. 输出骨架图统计**：

```
[骨架图已初始化]
新增节点：N 个（均为 unknown 状态，待 kernel-code-analyzer 深化）
新增边：N 条（来自 MCP call_chain_down depth=2）
可用 /show-progress 查看 dashboard 知识图谱的初始状态。
```

### Step 9：整合已有笔记，输出文档

**整合已有笔记**：检查 `learn/` 目录，对已有文档的分类标注，避免重复：

```
**已有学习笔记**（可直接参考，只放链接，不复制内容）：
- `learn/sched/enqueue_task_fair.md` — enqueue_task_fair 详解
```

若 Step 2.5 生成了概念 primer，在概览节之后单独加一行链接（放在"分类详解"之前，因为它是读分类详解的前提）：

```
**先读这份基础概念 primer**：`learn/{MODULE_KEY}/{MODULE_KEY}_concepts.md` —
不涉及代码，讲清楚贯穿全模块的核心术语，建议在读分类详解前先看一遍。
```

**输出到文件**：

```
learn/{MODULE_KEY}/{MODULE_KEY}_read_guide.md
```

- `MODULE_KEY` 从工程目录名或用户说明推断（如 `experiments/mpam-test/` → `mpam`）
- 文件已存在时：用新生成内容**覆盖**，保留文件头的"基于"和"生成时间"行
- **旧命名 `KernelRead.md` 已废弃**：若发现同目录下存在该文件，提示用户是否要重命名迁移（不要自动删除旧文件，也不要同时维护两份）
- 写入完成后调用 `obsidian-sync` skill 同步到 Obsidian

**文档结构**：

```markdown
# [工程名] 内核代码阅读需求文档

> 基于：[扫描的代码文件列表]
> 生成时间：[日期]

## 概览：涉及的内核子系统

[一段话描述工程涉及哪些子系统和整体复杂度]

## 关键数据结构阅读主线

[当 Step 5.5 触发时生成；否则省略本节]

## 分类详解

### 分类一：[名称]

**阅读目标**：
1. 如何...
2. 如何...

**关键源文件**：
| 文件 | 行号 | 重点关注 |

**已有学习笔记**（若有）：
- `learn/xxx/yyy.md` — 说明

---

## 阅读顺序建议

## API 快速检索
```

## References

- **`references/api-categories.md`** — 常见内核子系统的分类参考表和 API 候选列表。在 Step 3 分类归组时参考，不直接照抄。

## 质量检查

- [ ] Step 2 已并行调用 MCP：`find_definition` 和 `find_struct` 覆盖工程所有 `#include` 中的 API
- [ ] API 检索表中无凭记忆填写的文件路径（未找到的填 `?` 并备注）
- [ ] 每个分类有 3 个以上具体的"如何…"问题，与工程代码直接相关
- [ ] 阅读顺序按知识依赖排序，无"先用后介绍"的情况
- [ ] Step 5.5：若 Step 2 确认了 3 个及以上结构体，已生成“关键数据结构阅读主线”；若跳过，已确认结构体不足或不贯穿多个分类
- [ ] 输出路径为 `learn/{MODULE_KEY}/{MODULE_KEY}_read_guide.md`（非工程根目录，非旧命名 `KernelRead.md`）
- [ ] 已检查 `learn/` 目录并在对应分类标注已有笔记（仅链接，未内联复制调用链/逐字段解析等深度内容）
- [ ] 全文不含 ASCII 调用链树、结构体逐字段速查表、逐行代码详解——出现即视为越界，需删除并改为链接引用
- [ ] Step 8 骨架图：dep-graph.md 原本无边时，`append_dep_edge.sh` 已执行（输出 `appended:` 或 `skipped:`）
- [ ] Step 8 骨架图：骨架中出现的新函数已写入 `knowledge.md`（`upsert_node.sh` 输出 `inserted:` 或 `updated:`）
- [ ] Step 2.5：已判断是否需要概念 primer；若生成了 primer，内容仅来自 Confluence 原文 + 已扫描到的代码符号，未验证的术语对照已标注"待验证"，且未凭训练知识编造背景
- [ ] 写入完成后已调用 `obsidian-sync` skill 同步

## Version History

- v1.4.0 (2026-07-20): 新增 Step 5.5——关键数据结构阅读主线，要求把已确认的重要结构体组织成阅读路线，避免结构体只零散出现在 API 检索表；仍禁止逐字段解释和字段读写时机，字段级内容只能链接到结构体/函数深度笔记
- v1.3.0 (2026-07-06): 新增 Step 2.5——基础概念 primer 判断与生成，解决"函数级笔记读完仍看不懂贯穿全模块的术语"问题；primer 内容严格限定来源（Confluence 原文 + 已扫描代码符号），未验证的术语对照必须标注"待验证"；Step 9 补充 primer 链接位置
- v1.2.0 (2026-07-05): 明确与 kernel-code-analyzer 的边界——移除 Step 5/9 中调用链树、结构体字段速查示例，改为"仅链接不内联"；输出文件改名为 `{MODULE_KEY}_read_guide.md`，废弃 `KernelRead.md`；新增质量检查项防止深度解析内容混入路线图（根因：混入的调用链会被 kernel-learning-capture 当作"已分析"写入 knowledge.md，导致后续对该函数的深度分析请求被误判为"已学过"而跳过）
- v1.1.0 (2026-06-30): 新增 Step 8 骨架图初始化（call_chain_down depth=2 → dep-graph.md + knowledge.md），仅在 dep-graph 无边时触发
- v1.0.0 (2026-06-30): 初始版本，修复步骤顺序，统一输出路径为 learn/{MODULE_KEY}/KernelRead.md，分类表外移 references，补充无 .c 文件和 MCP 失败的处理，加 obsidian-sync 联动
