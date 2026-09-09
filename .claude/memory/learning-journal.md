# Learning Journal

## 2026-09-07

**学习内容**：
- 深度分析 RT 调度类入队全链路（Linux 7.2-rc6）：`enqueue_task_rt`（rt.c:1435，类入口 + pushable 维护）→ `enqueue_rt_entity`（rt.c:1403，先 `dequeue_rt_stack` 出栈再自底向上重挂）→ `__enqueue_rt_entity`（rt.c:1331，单级原语：`list_add(_tail)` 挂进 `rt_prio_array` + 位图 + `on_list`/`on_rq` + `inc_rt_tasks`）。
- 用本机 kernel-graph 图库 `linux7.2rc6.db`（`D:\claude配置\kernel-graph`）+ 源码逐行核对：确认泛型分发点 `enqueue_task`（core.c:2172→2184）与四条上游路径（ttwu_do_activate / wake_up_new_task / move_queued_task / sched_change_end）。
- 关键机制梳理：位图+100 条 FIFO 链表的设计动机、`on_list`/`on_rq` 双状态位、SAVE/RESTORE 与 `move_entity()` 语义、组实体"空/限流不入队"守卫、pushable plist 与 active 数组双轨登记、ENQUEUE_HEAD 与 PI 提升（core.c:7717）。
- 把 kernel-graph MCP 注册进 DSH web profile（`~/.dsh/profiles/web/cordis.patch.yml`，serverName=kernel-graph，DB 用 linux7.2rc6.db），Host 重启后新会话可获得 `mcp__kernel-graph__*` 原生工具；本会话用 `notes/inbox/kg_query.py`（复用 mcp_server 查询逻辑）作为等价通道。

**新增笔记**：
- `learn/sched/enqueue_task_rt.md`

**知识状态变化**：
- `enqueue_task_rt` / `enqueue_rt_entity` / `__enqueue_rt_entity` / `rt_prio_array` → mastered（85）
- `enqueue_pushable_task` → mastered（80）
- `rt_rq` / `sched_rt_entity` → exploring（60）
- sched 子系统汇总：mastered 5 / exploring 5 / unknown 80 / 平均置信度 6.07

**新增开放问题**：
- OQ-002（MEDIUM）：CONFIG_SCHED_PROXY_EXEC 下 `task_is_blocked` 早退分支与 `rq->donor` 代跑的联动语义。

**下次建议**：
- 沿出队对称路径深化：`dequeue_task_rt`/`dequeue_rt_entity`/`dequeue_rt_stack` + `dequeue_pushable_task`（rt.c:1455-1430, 413）。
- 或继续上游：`__sched_setscheduler` 内部逐分支（呼应 OQ-002 前的 priorities 待办）。
- 读 `pick_next_rt_entity`/`pick_task_rt` 补全"入队-选择"闭环。

## 2026-09-02

**学习内容**：
- 梳理 Linux 7.2-rc6 中与调度相关的系统调用：x86_64 syscall 表 + `kernel/sched/syscalls.c` 源码交叉确认，列出 sched_* 12 个 + setpriority/getpriority + clone/clone3 + nanosleep/clock_nanosleep/pause + exit/wait。
- 用 MCP 确认 `__sched_setscheduler()`（syscalls.c:493）是"改策略"类系统调用的公共实现，`sched_setattr`（内部，syscalls.c:764）是其一行封装。
- 确认老接口 `sched_setscheduler`/`sched_setparam` 经 `do_sched_setscheduler()`（syscalls.c:852）翻译成内部 `sched_attr` 后汇入同一实现。
- 记录关键 ABI 事实：`nice` 系统调用在 x86_64 与通用 unistd.h 均未接线；`SYSCALL_DEFINEn` 宏生成 `__do_sys_*`/`__se_sys_*`/`__x64_sys_*` 三层函数。

**新增笔记**：
- `learn/sched/sched_syscalls.md`

**知识状态变化**：
- `sched_setscheduler` / `__sched_setscheduler` / `sched_setattr` → exploring（置信度 2，仅有清单级/调用链证据，内部逐行行为未展开）。

**待办**：
- `__sched_setscheduler` 内部逐分支深化（EEVDF 权重、DL 带宽账本、RT 优先级继承）。
- `sched_yield` → `yield_task_fair()` 的 EEVDF 出队行为。
- `sched_getscheduler`/`sched_getaffinity` 查询读路径逐行分析。

## 2026-08-28

**学习内容**：
- 为"进程调度器"建立学习板块：基于 Linux 7.2-rc6 源码，用 kernel-graph MCP 确认了调度器核心 API/结构体的真实位置。
- 生成阅读指南 `learn/sched/sched_read_guide.md`（11 个分类 + 关键数据结构主线 + 阅读顺序 + API 检索表）。
- 初始化调度器依赖图骨架：`__schedule` / `pick_next_task` / `try_to_wake_up` / `context_switch` / `enqueue_task_fair` 五条主线的直接调用边。
- 在 `memory/sched/knowledge.md` 建立 66 个 unknown 节点（初始置信度 0）。

**关键版本发现**：
- 7.2-rc6 中 `scheduler_tick` 改名为 `sched_tick`（core.c:5762）；`check_preempt_curr` 重构为 `wakeup_preempt`。
- CFS 的 pick 入口是 `pick_task_fair`（fair.c:9912），`pick_next_task_fair` 不再存在。
- 负载均衡接口重构为 `sched_balance_rq` / `sched_balance_newidle` / `sched_balance_softirq`。

**新增笔记**：
- `learn/sched/sched_read_guide.md`

**知识状态变化**：
- 新建 `sched` 子系统：66 个节点全部 `unknown`，待 `kernel-code-analyzer` 逐个深化。

**下次建议**：
- 从调度主路径开始深度分析 `__schedule`（core.c:7061），再顺调用链深化 `pick_next_task` 与 `context_switch`。

## 2026-01-01

**学习内容**：
- 初始化示例模块和长期记忆结构。
- 演示知识节点状态及依赖关系。

**新增笔记**：
- `learn/example/scheduler_walkthrough.md`

**知识状态变化**：
- `schedule` → mastered
- `pick_next_task` → exploring

**新增开放问题**：
- OQ-001：如何验证函数指针产生的间接调用关系？

**下次建议**：
- 使用真实源码检索工具替换示例节点。

