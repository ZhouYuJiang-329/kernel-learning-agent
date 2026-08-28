---
name: kernel-learning-synthesizer
description: >
  将已有内核学习笔记整理成模块级理解框架，而不是重新做源码分析。
  当用户说"帮我理清这些文档"、"总结这个模块"、"生成术语表/状态矩阵/路径索引/字段字典"、
  "这些 analyzer 文档怎么串起来"、"我哪里容易混"、"做 synthesis"、
  "补充理解框架"时触发。输出写到 learn/{module}/synthesis/。
---

# Kernel Learning Synthesizer Skill

## 定位

本 skill 是项目级"学习整理器"。

它不替代 `kernel-code-analyzer`：

```text
kernel-code-analyzer:
  分析具体函数/结构体，产出源码事实。

kernel-learning-synthesizer:
  读取已有 analyzer 笔记和 memory，整理术语、路径、状态矩阵、字段字典、常见误区和阅读顺序。
```

## 触发条件

用户表达以下意图时使用：

- "总结这个模块"
- "这些文档怎么串起来"
- "帮我理清"
- "生成术语表"
- "生成状态矩阵"
- "生成路径索引"
- "补充理解框架"
- "我老是混 X 和 Y"
- "把问答沉淀成文档"

若用户只是问单个函数源码细节，优先用 `kernel-code-analyzer`。

## 输出位置

统一写入：

```text
learn/{module}/synthesis/
```

示例：

```text
learn/sched/synthesis/sched_terms.md
learn/sched/synthesis/sched_state_matrix.md
learn/sched/synthesis/sched_paths_index.md
learn/mpam/synthesis/mpam_terms.md
```

不要把 synthesis 文档混到函数级 analyzer 笔记旁边，除非用户明确要求。

## 执行流程

### Step 0：确认模块

若用户已指定模块，直接使用。否则从最近对话、当前文件路径或 `.claude/memory/MEMORY.md` 的当前学习焦点推断。

推断不明确时只问一个问题：

```text
要整理哪个模块？例如 sched、mpam、perf、ebpf、android_boot。
```

### Step 1：读取现有材料

读取以下文件，按存在情况取用：

```text
learn/{module}/
.claude/memory/{module}/knowledge.md
.claude/memory/{module}/dep-graph.md
.claude/memory/{module}/qa-log.md
.claude/memory/open-questions.md
```

只基于已有笔记和 memory 做整理。不要为了 synthesis 主动进行新的 kernel-graph 深挖；如果发现缺口，写入"待补分析"或建议后续用 `kernel-code-analyzer` 分析。

### Step 2：选择输出类型

若用户指定了类型，只生成对应文档。若未指定，按模块已有材料选择 1-3 个最有价值的输出，避免一次生成过多。

常见输出类型：

| 类型 | 文件名建议 | 适用场景 |
|---|---|---|
| 术语表 | `{module}_terms.md` | 名词相近、概念容易混 |
| 状态矩阵 | `{module}_state_matrix.md` | 多个字段共同决定状态 |
| 路径索引 | `{module}_paths_index.md` | 函数多、调用场景多 |
| 字段字典 | `{module}_field_dictionary.md` | 结构体字段多且跨函数流动 |
| 模块地图 | `{module}_module_map.md` | 子模块/层级关系不清 |
| 常见误区 | `{module}_pitfalls.md` | 问答中反复出现误解 |
| 阅读顺序 | `{module}_reading_order.md` | 用户需要下一步路线 |

### Step 3：生成文档

文档风格：

- 中文说明，函数/字段名保持英文原名。
- 先给总览，再给表格或路径图。
- 明确区分"已由笔记确认"和"待补分析"。
- 不写虚假的源码行号；需要行号时引用已有笔记路径。
- 不做大段背景科普，聚焦帮助用户理解本项目已有材料。

推荐结构：

```markdown
# {标题}

> 定位：...
> 来源：基于 learn/{module}/ 下已有笔记和 .claude/memory/{module}/。

---

## 一、怎么使用这篇

## 二、核心表格/路径/矩阵

## 三、容易混淆的点

## 四、下一步建议
```

### Step 4：更新 synthesis 索引

确保存在：

```text
learn/{module}/synthesis/_index.md
```

若新建或新增文档，更新 `_index.md` 的文档列表。索引只列 synthesis 文档，不列函数级 analyzer 笔记。

### Step 5：必要时更新阅读指南入口

若模块存在：

```text
learn/{module}/{module}_read_guide.md
```

并且本次新增的是通用前置文档（术语表、状态矩阵、路径索引），在 read guide 开头补一小段 "通用辅助文档" 链接。

不要为了每个小文档都更新 read guide。只有对模块整体阅读顺序有帮助时才更新。

### Step 6：输出摘要

输出：

```text
[synthesis 已更新]
模块：{module}
新增/更新文档：
- learn/{module}/synthesis/...
建议下一步：
- ...
```

## 什么时候反向建议更新 analyzer

整理时如果发现已有 analyzer 笔记普遍缺少同一种信息，不要在 synthesis 里硬补源码事实。输出建议：

```text
建议增强 kernel-code-analyzer 输出模板：增加 "{缺失项}" 小节。
```

常见可反向增强项：

- 所属路径
- 入口状态
- 出口状态
- 关键字段读写
- 最容易误解的点
- 建议下一篇读什么

## 质量检查

- [ ] 输出写在 `learn/{module}/synthesis/`
- [ ] 没有伪造源码事实、行号或调用关系
- [ ] 已区分 analyzer 文档与 synthesis 文档
- [ ] 若有缺口，标为"待补分析"，未凭空补全
- [ ] `_index.md` 已更新
- [ ] 用户的真实卡点已沉淀到"容易混淆"或"常见误区"部分

## Version History

- v1.0.0 (2026-07-24): 初始版本，定义 analyzer/synthesis 分层、输出目录和常见文档类型
