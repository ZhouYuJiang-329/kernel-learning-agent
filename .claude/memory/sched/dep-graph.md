# 调度器依赖图

```text


__schedule
  ├── pick_next_task (选择下一个要运行的任务)
    ├── __pick_next_task (按调度类优先级遍历 pick_task)
      ├── pick_task_fair (CFS 选择下一个可运行任务)
      └── pick_task_idle (idle 类 pick)
    ├── prev_balance (调度前调平（sched_core 路径）)
    └── put_prev_set_next_task (设置 prev/next 的调度类挂钩)
  ├── context_switch (切换到新任务（含 switch_mm_irqs_off/switch_to/finish_task_switch）)
    ├── prepare_task_switch (切换前准备（perf/kcov/钩子）)
    ├── switch_mm_irqs_off (切换地址空间)
    ├── switch_to (架构级寄存器/栈切换)
    └── finish_task_switch (切换后收尾（解锁/清理）)
  ├── update_rq_clock (更新 rq->clock)
  ├── schedule_debug (调度前一致性检查)
  ├── schedule_idle (CPU 进入 idle 时的调度入口)
  ├── preempt_schedule_common (抢占调度入口)
  ├── put_prev_task (调 put_prev 挂钩（让出前清理）)
  ├── set_next_task (调 set_next 挂钩（选定新任务）)

try_to_wake_up
  ├── ttwu_queue (将唤醒任务入队/迁移)
    └── ttwu_do_activate (唤醒任务并 activate 到运行队列)
  ├── select_task_rq (选择目标 CPU)
  ├── ttwu_do_wakeup (唤醒后处理（标记 TASK_RUNNING）)
  └── wakeup_preempt (检查是否需要抢占当前任务)
    └── resched_curr (给目标 CPU 设置 TIF_NEED_RESCHED)

enqueue_task_fair
  ├── enqueue_entity (将调度实体入 CFS 红黑树)
  ├── place_entity (放置实体（初始化 vruntime）)
  ├── update_curr (更新当前实体的运行时间)
  ├── update_load_avg (更新负载均值（PELT）)
  ├── check_update_overutilized_status (标记 CPU 过载状态)
  └── add_nr_running (更新运行队列可运行计数)

## RT 入队路径（kernel/sched/rt.c，见 learn/sched/enqueue_task_rt.md）

enqueue_task_rt (rt.c:1435, sched_class.enqueue_task 回调, 泛型分发点 core.c:2184)
  ├── enqueue_rt_entity (rt.c:1403, 实体级分层入队：先出栈后自底向上重挂)
  │     ├── dequeue_rt_stack (rt.c:1383, 祖先链 top-down 摘除，保证重定位幂等)
  │     ├── __enqueue_rt_entity (rt.c:1331, 单级原语：list_add(_tail) 挂进 rt_prio_array + 位图)
  │     │     ├── __delist_rt_entity (rt.c:1212, 摘链+必要时清位图, 组空/限流守卫用)
  │     │     └── inc_rt_tasks (rt.c:1174, 计数/最高优先级缓存/cpupri/带宽)
  │     └── enqueue_top_rt_rq (rt.c:1027, 顶层 rq->rt 记账: rt_queued/add_nr_running/cpufreq)
  └── enqueue_pushable_task (rt.c:397, pushable plist 登记 + highest_prio.next + overload/rto_mask)

    ├── plist_del (删除可能存在的旧迁移节点)
    ├── plist_node_init (按当前有效优先级重建节点)
    ├── plist_add (有序插入RT迁移候选表)
    └── rt_set_overload (登记root-domain过载CPU)
## 调度系统调用层（kernel/sched/syscalls.c）

sched_setscheduler (syscall, syscalls.c:934)
  └── do_sched_setscheduler (syscalls.c:852, 老接口参数翻译 + copy_from_user)
      └── sched_setscheduler (内部)
          └── __sched_setscheduler (syscalls.c:493, 所有"改策略"公共实现)

sched_setattr (syscall, syscalls.c:960)
  ├── sched_copy_attr (sched_attr 新旧版本结构适配)
  └── sched_setattr (内部, syscalls.c:764)
      └── __sched_setscheduler (p, attr, user=true, pi=true)

__sched_setscheduler
  ├── valid_policy (策略枚举校验)
  ├── __checkparam_dl (DL 参数自洽: runtime<=deadline<=period)
  ├── user_check_sched_setscheduler (普通用户权限 + nice 只降不升)
  ├── security_task_setscheduler (LSM 钩子)
  ├── sched_dl_overflow (DL 全局带宽账本)
  ├── __setscheduler_class (选择/切换 sched_class)
  ├── __setscheduler_params (写入参数, set_load_weight)
  ├── rt_mutex_adjust_pi (RT mutex 优先级继承链)
  └── balance_callbacks (解锁后推迟的入队/迁移回调)

dequeue_task_rt
  ├── update_curr_rt (结算当前 donor 执行时间并检查 RT group bandwidth)
    ├── update_curr_common (结算donor通用精确执行时间)
    ├── rt_bandwidth_enabled (判断RT运行时限额是否启用)
    ├── rt_rq_of_se (取得实体所属层级RT队列)
    ├── sched_rt_runtime (读取本层可用RT额度)
    ├── sched_rt_runtime_exceeded (检查共享额度节流并撤下超额队列)
    ├── resched_curr (超额后请求当前CPU重新调度)
    ├── sched_rt_bandwidth (取得task-group带宽控制器)
    └── do_start_rt_bandwidth (启动周期补充高精度定时器)
  ├── dequeue_rt_entity (撤销叶子及 task-group 祖先的 RT 队列状态)
  └── dequeue_pushable_task (移除 SMP pushable 候选并修正 overload 状态)

    ├── plist_del (移除RT迁移候选节点)
    ├── has_pushable_tasks (判断迁移候选表是否仍非空)
    ├── plist_first_entry (取得新的最高优先级迁移候选)
    └── rt_clear_overload (空表时撤销过载CPU登记)
pick_task_rt
  ├── sched_rt_runnable (读取rt_queued快速判断RT类是否可选)
  └── _pick_next_task_rt (沿RT-task-group层级下钻到叶子任务)
    ├── pick_next_rt_entity (在当前rt_rq选择最高优先级FIFO队头)
      └── sched_find_first_bit (从固定RT位图查找数值最小的置位)
    ├── group_rt_rq (判断实体是否拥有group子rt_rq)
    └── rt_task_of (将叶子sched_rt_entity还原为task_struct)

set_next_task_rt
  ├── rq_clock_task (记录新运行区间的任务时钟起点)
  ├── on_rt_rq (判断RT实体是否仍属于运行队列)
  ├── update_stats_wait_end_rt (结束RT实体的等待统计区间)
  ├── dequeue_pushable_task (撤销运行任务的可迁移资格)
  ├── rq_clock_pelt (读取RT PELT时间轴)
  ├── update_rt_rq_load_avg (推进CPU的RT衰减负载)
  └── rt_queue_push_tasks (登记后续RT push均衡回调)

put_prev_task_rt
  ├── on_rt_rq (判断旧RT实体是否仍可运行)
  ├── update_stats_wait_start_rt (开始RT实体的等待统计区间)
  ├── update_curr_rt (结算旧RT donor执行时间和带宽)
  ├── rq_clock_pelt (读取RT PELT时间轴)
  ├── update_rt_rq_load_avg (按刚结束的运行区间推进RT负载)
  ├── task_is_blocked (识别proxy execution阻塞donor)
  └── enqueue_pushable_task (恢复旧RT任务的可迁移资格)

inc_rt_prio
  └── inc_rt_prio_smp (同步顶层CPU优先级索引)

dec_rt_prio
  ├── sched_find_first_bit (从active位图重算最高优先级)
  └── dec_rt_prio_smp (同步顶层CPU优先级索引)
```
