# Memory Index — kernel-learning

## 子系统列表

| 子系统 | 目录 | mastered | exploring | unknown | 平均置信度 |
|---|---|---:|---:|---:|---:|
| 示例模块 | [example/](example/knowledge.md) | 1 | 1 | 1 | 0 |
| 调度器 | [sched/](sched/knowledge.md) | 0 | 0 | 87 | - |

## 当前学习焦点

- **示例模块进度**：已建立三个示例知识节点，用于演示状态管理、调用关系和 Dashboard 展示。
- **调度器路线图**：已基于 Linux 7.2-rc6 生成阅读指南（`learn/sched/sched_read_guide.md`），建立 87 个 unknown 节点和初始依赖图，待 kernel-code-analyzer 逐个深化。

## 知识状态

- [example/knowledge.md](example/knowledge.md) — 示例节点表
- [example/dep-graph.md](example/dep-graph.md) — 示例依赖图
- [example/qa-log.md](example/qa-log.md) — 示例问答日志
- [sched/knowledge.md](sched/knowledge.md) — 调度器节点表
- [sched/dep-graph.md](sched/dep-graph.md) — 调度器依赖图
- [open-questions.md](open-questions.md) — 开放问题
- [learning-journal.md](learning-journal.md) — 学习日志

## 最近 5 个分析

- `rq` (sched, 2026-08-28)
- `dl_rq` (sched, 2026-08-28)
- `sched_attr` (sched, 2026-08-28)
- `rt_prio_array` (sched, 2026-08-28)
- `__schedule` (sched, 2026-08-28)

## 开放问题统计

CRITICAL: 0 · MEDIUM: 1 · LOW: 0
