---
name: kernel-concept-mapper
description: >
  Use when kernel learning is blocked by missing theory, background models, algorithms, hardware concepts,
  protocols, memory-ordering ideas, or repeated "why is it designed this way" questions.
---

# Kernel Concept Mapper Skill

## 定位

本 skill 维护"概念/理论层"。它不做函数级源码分析，也不把多篇函数笔记串成路径；它回答的是：

```text
看懂这段内核代码之前，需要先懂哪些概念？
哪些概念只是先记结论即可？
哪些概念已经和具体函数关联起来？
```

边界：

```text
kernel-code-analyzer:
  单个函数/结构体源码事实。

kernel-learning-synthesizer:
  多篇笔记 + 问答后的路径、状态、术语整理。

kernel-concept-mapper:
  理论背景、概念债、概念掌握状态。
```

## 输出位置

概念文档写到：

```text
learn/{module}/concepts/
```

概念掌握状态写到：

```text
.claude/memory/{module}/concepts.md
```

示例：

```text
learn/sched/concepts/_index.md
learn/sched/concepts/eevdf.md
learn/sched/concepts/smp_memory_ordering.md
.claude/memory/sched/concepts.md
```

## 概念状态

| 状态 | 含义 |
|---|---|
| `debt` | 已发现代码依赖该概念，但还没系统讲，暂记为概念债 |
| `primer` | 已有最小可用解释，足够继续读当前代码 |
| `linked` | 已经和具体函数/结构体建立关联 |
| `mastered` | 用户明确理解，或能解释设计取舍 |
| `deferred` | 当前主线暂不需要，先放后面 |

置信度用 0-100：

```text
debt: 10-30
primer: 40-60
linked: 60-80
mastered: 85-100
deferred: 保持现有置信度或 20
```

## 执行流程

### Step 0：确认模块

若用户已指定模块，直接使用。否则从最近对话、当前学习焦点或文件路径推断。

推断不明确时只问一个问题：

```text
要为哪个模块维护概念地图？例如 sched、mpam、perf、ebpf、android_boot。
```

### Step 1：读取已有材料

按存在情况读取：

```text
learn/{module}/
learn/{module}/synthesis/
learn/{module}/concepts/
.claude/memory/{module}/knowledge.md
.claude/memory/{module}/dep-graph.md
.claude/memory/{module}/qa-log.md
.claude/memory/{module}/concepts.md
.claude/memory/open-questions.md
```

不要为了补 concept 主动做新的 kernel-graph 深挖。若发现需要源码验证，写成"待补分析"，建议后续用 `kernel-code-analyzer`。

### Step 2：识别概念债

把以下情况记录成 concept debt：

- analyzer 文档里反复出现但没有概念解释的词
- 用户多次问"为什么这样设计"
- 解释函数时必须临时补一段理论背景
- 代码依赖算法、数学模型、硬件协议、并发模型或 ABI/API 约束
- synthesis 文档里有"先只记结论"的概念

示例：

```text
sched:
  EEVDF、CFS weight/vruntime、SMP memory ordering、PELT/WALT、priority inheritance

mpam:
  PARTID/PMG、MSC、resctrl schema、cache partitioning、SCMI vendor protocol
```

### Step 3：更新 concepts/_index.md

确保存在：

```text
learn/{module}/concepts/_index.md
```

索引应包含：

- 当前概念清单
- 状态
- 关联函数/结构体
- 优先级
- 对应 primer 文件

### Step 4：生成或更新单篇 concept primer

只有用户要求，或该概念阻塞当前阅读主线时，才生成单篇 primer。

每篇 primer 只讲"当前读代码够用"的最小模型，不写教材。

模板：

```markdown
# {Concept Name}

> 定位：这个概念解释什么问题。
> 当前掌握目标：读当前代码需要理解到什么程度。

---

## 一、为什么需要这个概念

## 二、最小可用模型

## 三、代码里哪里依赖它

| 函数/结构体 | 依赖点 | 笔记 |
|---|---|---|

## 四、容易误解的点

## 五、先放后的细节

## 六、下一步
```

### Step 5：更新 memory concepts.md

确保存在：

```text
.claude/memory/{module}/concepts.md
```

表格格式：

```markdown
| concept | status | confidence | note | linked_code |
|---|---|---:|---|---|
| EEVDF | primer | 50 | 知道 lag/deadline，未深挖 pick_eevdf | pick_eevdf, enqueue_entity |
```

更新规则：

- 新概念默认 `debt`
- 写了 primer 后升为 `primer`
- 和 2 个以上已分析函数建立明确关系后升为 `linked`
- 用户明确说"理解了"后可升为 `mastered`
- 当前主线不需要时标 `deferred`

### Step 6：输出摘要

输出：

```text
[concept map 已更新]
模块：{module}
新增/更新：
- learn/{module}/concepts/...
- .claude/memory/{module}/concepts.md
概念债：
- ...
建议下一步：
- ...
```

## 质量检查

- [ ] concepts 文档写在 `learn/{module}/concepts/`
- [ ] memory 状态写在 `.claude/memory/{module}/concepts.md`
- [ ] 没有凭空补源码调用关系或行号
- [ ] primer 只讲当前读代码够用的最小模型
- [ ] 不和 synthesis 文档职责重叠
- [ ] 概念债、状态、关联代码均已记录

## Version History

- v1.0.0 (2026-07-24): 初始版本，定义概念债、概念状态、输出目录和 primer 模板
