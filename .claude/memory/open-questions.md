# Open Questions

## CRITICAL（阻塞学习进展）

暂无。

## MEDIUM（重要但不阻塞）

### OQ-001（MEDIUM）

- **来源**：示例学习流程
- **问题**：如何验证函数指针产生的间接调用关系？
- **相关函数/结构体**：`pick_next_task`
- **当前假设**：需要结合静态调用图、函数指针赋值位置和源码人工核验。
- **建议查询**：使用源码搜索定位回调注册点和实际调用点。

## LOW（感兴趣但非当前重点）

暂无。

## 已解答（归档）

### OQ-002（MEDIUM）

- **来源**：2026-09-07 分析 `enqueue_task_rt`/`__enqueue_rt_entity` 时发现
- **问题**：7.2-rc6 引入 `CONFIG_SCHED_PROXY_EXEC` 后，`enqueue_task_rt` 末尾的 `task_is_blocked(p)` 早退分支（rt.c:1448）在"rq->donor 代跑被阻塞任务"语义下的完整行为：被阻塞任务入队后既不登记 pushable，其 `on_rq/on_list` 与 donor 的调度状态如何联动、`pick_next_task_rt` 会不会选到它，尚未展开。
- **相关函数/结构体**：`enqueue_task_rt`, `task_is_blocked`, `task_current_donor`, `rq->donor`, `struct sched_rt_entity`
- **当前假设**：proxy exec 下被阻塞任务的 RT 实体仍挂在 active 数组中由 donor 代表运行，故 pushable 与普通运行路径都绕开它；需要源码确认 donor 的 put/next 流程如何复用该实体。
- **建议查询**：`CONFIG_SCHED_PROXY_EXEC` 相关 core.c 路径 + `find_indirect_callers enqueue_task_rt` 之外检索 `rq->donor` 全部写点（`grep -rn "donor" kernel/sched/`）
- **解答日期**：2026-09-07
- **结论**：blocked_RT任务保持on_rq/on_list并留在active中但不进pushable；pick_task_rt可选它为donor，__schedule随后由find_proxy_task沿mutex_owner链确定实际curr。


