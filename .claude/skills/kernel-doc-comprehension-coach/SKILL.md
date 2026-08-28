---
name: kernel-doc-comprehension-coach
description: >
  Use after the user has read a kernel-learning document and wants to know whether they understood it.
  Trigger when the user says they read a document, asks to be quizzed, asks for comprehension evaluation,
  says they are unsure what they mastered, or wants guidance on what to read next. This skill asks targeted
  questions, evaluates the user's answers, identifies fuzzy concepts/details, and recommends whether to use
  kernel-concept-mapper, kernel-learning-synthesizer, kernel-code-analyzer, or another next action.
---

# Kernel Doc Comprehension Coach

## 定位

本 skill 是"读后验收教练"。它不负责重新分析源码，也不负责生成模块级 synthesis；它回答的是：

```text
用户读完这篇文档后，到底掌握到什么程度？
哪些概念只是记住了词，哪些路径/字段/状态还不稳？
下一步应该继续读、回头补概念、整理 synthesis，还是重新分析源码？
```

边界：

```text
kernel-reading-guide:
  读之前规划路线。

kernel-code-analyzer:
  深挖单个函数/结构体源码事实。

kernel-concept-mapper:
  发现概念债后，补理论/概念 primer。

kernel-learning-synthesizer:
  多篇笔记之间串路径、状态矩阵、术语表、字段字典。

kernel-doc-comprehension-coach:
  读完一篇或一组文档后，通过提问和评价判断掌握程度，并建议下一步。
```

## 触发条件

用户表达以下意图时使用：

- "我读完了 X，考我一下"
- "帮我判断这篇文档掌握程度"
- "读后验收"
- "我不知道这篇懂没懂"
- "根据这篇笔记给我提问题"
- "我回答你来评价"
- "哪些细节没掌握，后续看啥"

如果用户只是要求总结文档，不使用本 skill，优先普通总结或 `kernel-learning-synthesizer`。
如果用户要求解释具体函数源码，不使用本 skill，优先 `kernel-code-analyzer`。

## 执行流程

### Step 0：确认材料

若用户已给出文档路径，直接使用。若只说"这篇"或"刚读的"，从最近对话推断；推断不明确时只问一个问题：

```text
你想验收哪篇文档？给我 learn/... 的路径或文档标题即可。
```

### Step 1：读取最小上下文

按需读取：

```text
CLAUDE.md
.claude/memory/MEMORY.md
用户指定的 learn/**/*.md
同目录 _index.md（若存在）
对应模块的 *_read_guide.md（若需要判断阅读顺序）
对应模块的 synthesis/ 文档（若需要判断是否是"串不起来"）
```

不要默认读取整个模块目录。不要为了出题主动调用 kernel-graph 或重新做源码深挖。

### Step 2：识别文档类型

先判断文档属于哪类，再出题：

| 类型 | 验收重点 |
|---|---|
| concept primer | 概念动机、最小模型、术语边界、能否解释设计取舍 |
| 函数分析 | 所属路径、入口/出口状态、关键字段、锁/并发、上下游调用 |
| 结构体分析 | 字段分组、生命周期、谁读写、状态组合、常见误解 |
| 调用链/path 文档 | 主路径、分支条件、场景触发、路径之间差异 |
| synthesis 文档 | 多篇笔记如何串起来、术语区别、状态矩阵、下一步路线 |
| bug/问题分析 | 现象、触发条件、证据链、影响范围、验证方式 |

### Step 3：第一轮只出题，不给答案

生成 5-8 个问题，按难度递进。除非用户明确要求，否则不要一次出超过 8 题。

题目结构：

```text
1. 大意复述题：这篇文档解决什么问题？
2. 定位题：它属于哪条路径/哪个模块层级？
3. 主路径题：入口 -> 中间关键点 -> 结果是什么？
4. 字段/状态题：关键字段入口状态和出口状态怎么变？
5. 易错点题：最容易和哪个概念混？
6. 设计动机题：为什么不是另一种更直观的做法？
7. 迁移应用题：看到某个 trace/bug 现象时下一步查哪里？
8. 取舍题：这篇哪些细节必须掌握，哪些可先跳过？
```

输出格式：

```markdown
我先做读后验收，不直接讲答案。你按自己的理解回答即可，答不全也没关系。

**验收问题**
1. ...
2. ...

回答时可以简写；如果某题不确定，直接写"不确定"。
```

提问后停止，等待用户回答。

### Step 4：评价用户回答

用户回答后，按以下维度评价：

| 维度 | 关注点 |
|---|---|
| 框架 | 是否知道文档在解决什么问题 |
| 路径 | 是否能串起入口、关键中间点、最终效果 |
| 字段/状态 | 是否掌握关键结构体字段、状态位、锁和生命周期 |
| 概念 | 是否理解背后的理论/硬件/算法/ABI/API 约束 |
| 边界 | 是否知道哪些细节当前可跳过 |
| 迁移 | 是否能用这篇内容分析 bug、trace 或设计取舍 |

不要只给笼统鼓励。要明确指出：

- 哪些回答说明已经真懂
- 哪些回答只是背到了词
- 哪些关键细节遗漏或混淆
- 哪些错误会影响后续阅读
- 哪些细节暂时不值得深挖

### Step 5：给掌握等级

使用 0-4 级，允许 0.5 分：

| 等级 | 含义 |
|---:|---|
| 0 | 没建立框架，读完仍不知道文档在解决什么 |
| 1 | 能复述大意，但路径/字段基本说不清 |
| 2 | 能说清主路径，但关键状态变化或设计动机不稳 |
| 3 | 能解释关键字段、状态变化、分支条件和易错点 |
| 4 | 能迁移到 bug/trace/设计取舍分析，知道下一步查哪里 |

输出格式：

```markdown
**掌握度**
当前：2.5 / 4
判断：能串主路径，但字段状态模型还不稳。
```

### Step 6：诊断卡点类型

根据用户回答，判断后续动作：

| 表现 | 判断 | 建议 |
|---|---|---|
| 会背术语，但说不出为什么需要 | 概念债 | 建议 `kernel-concept-mapper` |
| 单篇能说，跨多篇串不起来 | 整合不足 | 建议 `kernel-learning-synthesizer` |
| 路径能说，字段状态反复错 | 状态模型不足 | 建议补 synthesis 状态矩阵或字段字典 |
| 文档关键源码事实不足 | 源码证据不足 | 建议 `kernel-code-analyzer` |
| 调用链层级多，脑中没有图 | 可视化不足 | 建议 drawio 调用链图 |
| 已能解释并迁移应用 | 可以前进 | 建议下一篇或做 trace/实验验证 |

默认只建议，不自动调用其他 skill。只有用户明确说"按你的建议直接补 concept/synthesis"时，才继续执行相应 skill。

### Step 7：给下一步阅读建议

根据掌握等级输出：

```text
0-1:
  先重读文档开头/概念 primer，不建议进入下一篇。

1.5-2:
  可以继续，但要先补 1-2 个关键概念或状态表。

2.5-3:
  可以读下一篇；保留 1-2 个待确认细节。

3.5-4:
  可以进入更复杂路径，或拿真实 trace/bug 做应用验证。
```

下一步建议必须具体到文件或动作，例如：

```text
建议先补：learn/sched/synthesis/sched_state_matrix.md 的 on_rq/on_cpu 部分。
下一篇建议：learn/sched/cfs/pick_next_task_fair.md。
暂时可跳过：RT/DL 带宽细节。
建议触发：kernel-concept-mapper，原因是 EEVDF lag/deadline 概念不稳。
```

## 输出模板：评价阶段

```markdown
**掌握度**
当前：{score} / 4
判断：{一句话}

**已经掌握**
- ...

**薄弱点**
- ...

**需要纠正**
- ...

**可先忽略**
- ...

**后续动作**
- 建议：...
- 是否需要 skill：...
- 下一篇：...
```

## 质量检查

- [ ] 第一轮只出题，不提前泄露答案
- [ ] 问题覆盖框架、路径、字段/状态、概念、迁移应用
- [ ] 评价基于用户回答，而不是默认用户已经掌握
- [ ] 明确区分"概念债"和"多篇文档串不起来"
- [ ] 只建议 `kernel-concept-mapper` / `kernel-learning-synthesizer`，不默认自动调用
- [ ] 下一步建议具体到文件、概念或动作
- [ ] 不凭空补源码调用关系、行号或未读文档结论

## Version History

- v1.0.0 (2026-07-30): 初始版本，定义读后验收、评分、卡点诊断和后续 skill 建议流程
