# Linux 调度相关系统调用清单

> 源码位置：`kernel/sched/syscalls.c`、`kernel/sys.c`、`kernel/fork.c`、`kernel/time/hrtimer.c`、`kernel/time/posix-timers.c`、`kernel/signal.c`、`kernel/exit.c`
> 编号来源：`arch/x86/entry/syscalls/syscall_64.tbl`（Linux 7.2-rc6）
> 一句话职责：用户态通过这一组系统调用查询/修改进程的调度策略、优先级、CPU 亲和性与睡眠行为；核心改动最终都汇聚到调度器内部的 `__sched_setscheduler()` 等实现。

---

## 一、大白话总览

### （a）为什么要设计它们？

进程调度策略平时是"内核说了算"：任务创建后由 CFS 一视同仁地排队。但现实需求五花八门——

- 实时任务（音频、控制回路）要求 `sched_setscheduler()` 切换到 SCHED_FIFO/RR，保证不被普通任务抢占；
- 后台批处理希望降权（SCHED_BATCH / nice 调高）；
- 高频线程要绑定特定 CPU 核（`sched_setaffinity()`），避免缓存抖动；
- 应用想要"主动让出"（`sched_yield()`）或"睡到某个时刻"（`nanosleep()`）。

**如果没有这组系统调用**：所有进程只能按默认策略调度，实时性、亲和性、功耗优化全部无从谈起。它们是内核调度器的"用户态控制面板"。

### （b）如果让你自己设计，第一反应应该是什么？

1. **一句话降级**：这组系统调用做的事可以归纳为四类动作——**改参数**（策略/优先级/亲和性）、**查参数**、**主动让出**、**入睡等待**。

2. **最小模型**：最朴素情况下，只需要两条命令：

```
用户态 "我想改变进程X的调度方式"
        │ 传：pid + 新策略 + 新参数
        ▼
内核 "找到进程X → 校验权限和参数 → 修改 task_struct 里相关字段
      → 若正在运行，决定是否需要重新调度"
```

3. **核心数据对象**：
   - `task_struct` — 任务"档案"，被修改的主体；相关字段如 `policy`、`prio`、`rt_priority`、`se`、`cpus_ptr`。
   - `struct sched_attr` — "设置单"，承载用户想设置的一切：策略、nice、RT 优先级、DL 的 runtime/deadline/period、uclamp 上下限。
   - `struct sched_param` — 老版"设置单"，只有一个 `sched_priority` 字段。
   - `cpumask` — CPU 集合，亲和性就是"允许在哪几个核上跑"。
   - `rq`（runqueue）— 任务的"候场区"，改策略意味着任务要从一个队列挪到另一个队列。

4. **真实复杂度从哪里来**：
   - **策略之间的差异**：SCHED_NORMAL 用 nice、SCHED_FIFO/RR 用 RT 优先级、SCHED_DEADLINE 用一组三个时间参数，校验规则完全不同；
   - **并发/锁**：修改任务字段时要同时持有 `task_rq_lock()`，防止与调度主路径并发读写；
   - **权限与安全**：提升实时优先级是特权操作，需 LSM 钩子 `security_task_setscheduler()`；
   - **ABI 兼容**：老接口 `sched_param` 无法表达 DL/uclamp，新接口 `sched_attr` 要支持"变长结构体 + 向后兼容"（`sched_copy_attr`）；
   - **连带副作用**：改完策略后任务可能要换调度类（`__setscheduler_class`）、要重新入队（`splice_balance_callbacks`）、要处理 RT mutex 优先级继承（`rt_mutex_adjust_pi`）。

5. **如果自己实现，大概步骤**（以 `sched_setscheduler` 为例）：
   - 从用户态拷入参数（`copy_from_user`）；
   - 按 pid 找到任务（`find_get_task`），不存在返回 `-ESRCH`；
   - 校验策略合法（`valid_policy`）、RT 优先级越界返回 `-EINVAL`；
   - 校验权限与安全钩子（`user_check_sched_setscheduler` + `security_task_setscheduler`）；
   - 加 `task_rq_lock`，重新校验（`recheck` 标签），DL 还要算带宽是否超预算（`sched_dl_overflow`）；
   - 修改任务参数（`__setscheduler_params`）、换调度类（`__setscheduler_class`）；
   - 解锁，若调度类/优先级变化影响当前 CPU，触发重新调度。

6. **源码阅读 checklist**：
   - 这个 `if` 是参数校验？（策略/优先级越界）
   - 这个分支是权限检查？（普通用户 vs root）
   - 这是并发保护？（为什么在 `recheck` 标签处拿锁后再查一遍策略）
   - 这是特殊策略分流？（DL / RT / CFS 各自的分支）
   - 这是连带副作用？（换类、唤醒、负载均衡、优先级继承）

### （c）它是怎么设计的？

设计上分三层：**薄薄的 syscall 包装 → 一个统一的内部实现 → 各调度类自己的钩子**。

- 老接口 `sched_param` 与内部 `sched_attr` 结构不同，所以先有个 `do_sched_setscheduler()` 做"老→新"参数翻译；
- 翻译完，所有"设置策略"的入口都汇到同一个 `__sched_setscheduler()`（`syscalls.c:493`），避免每个 syscall 各写一遍校验和改队列逻辑；
- `__sched_setscheduler()` 只负责"通用"部分（校验、锁、换类），真正怎么排队由 `sched_class` 的钩子（`enqueue_task_fair`/`enqueue_task_rt`/...）决定。

### （d）它处理哪几种情况，分别做什么？

情况一：用户**改调度策略**（`sched_setscheduler` / `sched_setattr`）
  → 做：校验 → 改 `task_struct.policy` → 可能换调度类 → 重新入队
  → 为什么：策略是任务分到哪个调度类队列的依据，改动必须同步 rq 结构

情况二：用户**只改参数、不动策略**（`sched_setparam`，内部传 `SETPARAM_POLICY`）
  → 做：`do_sched_setscheduler(pid, SETPARAM_POLICY, param)`，走同一实现，但策略取任务现值
  → 为什么：`sched_param` 里根本没有策略字段，调用方语义就是"只改优先级"

情况三：用户**只查不改**（`sched_getscheduler` / `sched_getparam` / `sched_getattr` / `sched_getaffinity`）
  → 做：只读 `task_struct` 对应字段，无副作用
  → 为什么：查询是旁路，不需要拿 rq 锁做任何队列操作

情况四：用户**让出 CPU**（`sched_yield`）
  → 做：把当前任务移到就绪队列尾部，然后重新调度
  → 为什么：自旋等待场景需要"轮转给兄弟任务"而不是睡眠

情况五：用户**睡眠**（`nanosleep` / `clock_nanosleep` / `pause`）
  → 做：挂入 hrtimer 队列并阻塞，到点由定时器回调唤醒
  → 为什么：内核无法"主动等"，只能把任务从就绪队列摘下来，等事件

情况六：用户**绑定 CPU**（`sched_setaffinity`）
  → 做：更新 `cpus_ptr`，若当前 CPU 不在新集合内则迁移任务
  → 为什么：亲和性直接决定 load balance 与迁移器 `scheduler_ipi` 的行为

---

## 二、调度控制系统调用清单（`sched_*`，12 个）

全部定义在 `kernel/sched/syscalls.c`，x86_64 编号见 `syscall_64.tbl`：

| 系统调用 | x86_64 编号 | 定义位置 | 功能 |
|---|---|---|---|
| `sched_yield` | 24 | `syscalls.c:1360` | 主动让出 CPU，回就绪队列队尾 |
| `sched_setparam` | 142 | `syscalls.c:949` | 仅设置调度参数（不影响策略） |
| `sched_getparam` | 143 | `syscalls.c:1025` | 查询调度参数 |
| `sched_setscheduler` | 144 | `syscalls.c:934` | 同时设置调度策略 + 参数（老接口） |
| `sched_getscheduler` | 145 | `syscalls.c:995` | 查询调度策略 |
| `sched_get_priority_max` | 146 | `syscalls.c:1469` | 查询某策略的优先级上限 |
| `sched_get_priority_min` | 147 | `syscalls.c:1497` | 查询某策略的优先级下限 |
| `sched_rr_get_interval` | 148 | `syscalls.c:1555` | 查询 SCHED_RR 时间片长度 |
| `sched_setaffinity` | 203 | `syscalls.c:1262` | 设置 CPU 亲和性 |
| `sched_getaffinity` | 204 | `syscalls.c:1307` | 查询 CPU 亲和性 |
| `sched_setattr` | 314 | `syscalls.c:960` | 新接口，一次设置策略/参数/亲和性等 |
| `sched_getattr` | 315 | `syscalls.c:1060` | 新接口，查询完整调度属性 |

> 补充：还有 `sched_rr_get_interval_time32/time64` 两个老 32 位时间戳变体（`syscalls.c:1568`，generic 编号 423），x86_64 64 位模式下走 `sched_rr_get_interval`。

---

## 三、其他调度相关系统调用

### 3.1 优先级（nice 值，影响 CFS 权重）

| 系统调用 | x86_64 编号 | 定义位置 | 功能 |
|---|---|---|---|
| `setpriority` | 141 | `kernel/sys.c:259` | 设置进程/进程组/用户的 nice 值 |
| `getpriority` | 140 | `kernel/sys.c:329` | 查询 nice 值 |

> 注意：`nice` 系统调用在 x86_64 与通用 `asm-generic/unistd.h` 中**均未接线**（`__NR_nice` 不存在）。glibc 的 `nice()` 实际封装的是 `setpriority`。

### 3.2 进程创建 / 进入调度器

| 系统调用 | x86_64 编号 | 定义位置 | 功能 |
|---|---|---|---|
| `clone` | 56 | `kernel/fork.c:2857` | 创建子进程/线程，触发 `sched_fork()` 等调度钩子 |
| `clone3` | 435 | `kernel/fork.c:3029` | 新式 clone，可传 `struct clone_args`（含调度扩展位） |

### 3.3 睡眠 / 阻塞（调度器负责唤醒）

| 系统调用 | x86_64 编号 | 定义位置 | 功能 |
|---|---|---|---|
| `nanosleep` | 35 | `kernel/time/hrtimer.c:2466` | 高精度定时睡眠，到点由定时器唤醒 |
| `clock_nanosleep` | 230 | `kernel/time/posix-timers.c:1383` | 基于指定时钟（如 CLOCK_ABSTIME）的睡眠 |
| `pause` | 34 | `kernel/signal.c:4832` | 挂起直到收到信号 |

### 3.4 生命周期（调度器参与，但不属调度控制）

| 系统调用 | x86_64 编号 | 定义位置 | 功能 |
|---|---|---|---|
| `exit` / `exit_group` | 60 / 231 | `kernel/exit.c:1117 / 1161` | 退出，把任务从就绪队列摘除 |
| `wait4` / `waitid` | 61 / 247 | `kernel/exit.c:1939 / 1847` | 等待子进程，通常进入睡眠 |

---

## 四、核心调用链：用户态 → `__sched_setscheduler`

### 4.1 宏观链路（所有"改策略"入口汇聚到同一实现）

```
用户态 sched_setscheduler()/sched_setattr()/sched_setparam()
  └── syscall 指令（nr=144/314/142）
        └── __x64_sys_sched_xxx()        // 架构包装，由 syscall_64.tbl 生成
              └── __se_sys_sched_xxx()   // 符号扩展桩（asmlinkage stub）
                    └── __do_sys_sched_xxx()   // 实际实现，syscalls.c:934/960/949
                          ├── (老接口) do_sched_setscheduler(pid, policy, param)
                          │     └── copy_from_user → sched_setscheduler(p, policy, &lparam)
                          │           └── __sched_setscheduler(p, attr, true, true)   ← syscalls.c:493
                          └── (新接口) sched_copy_attr(uattr, &attr) → sched_setattr(p, &attr)
                                └── __sched_setscheduler(p, attr, true, true)   ← syscalls.c:764 包一层
```

要点：
- `SYSCALL_DEFINEn` 宏（`include/linux/syscalls.h`）生成 `__do_sys_*`（真正干活）与 `__se_sys_*`（符号扩展桩）；syscall 表里的 `sys_sched_setscheduler` 在 x86_64 对应 `__x64_sys_sched_setscheduler`。
- 内部 `sched_setattr()`（`syscalls.c:764`，**不是** syscall）只是 `__sched_setscheduler` 的一行封装，cgroup、trace 等内核内部调用方也复用它。
- `sched_setparam` 走 `SETPARAM_POLICY` 哨兵值，表示"策略保持不变，只改参数"。

### 4.2 `__sched_setscheduler()` 内部执行链（MCP 调用链查询结果）

```
__sched_setscheduler(p, attr, user, pi)
  ├── 策略/参数校验
  │     ├── valid_policy()              // 策略是否合法（SCHED_* 枚举范围内）
  │     ├── __checkparam_dl()           // DL 参数自洽性（runtime<=deadline<=period 等）
  │     ├── rt_policy()!= (priority!=0) // RT 策略必须有非零优先级
  │     └── user_check_sched_setscheduler()  // 普通用户权限检查
  │           ├── is_nice_reduction()   // nice 只能降不能升
  │           ├── task_rlimit()/capable()   // 改 RT 优先级需特权
  │           └── check_same_owner()
  ├── security_task_setscheduler()      // LSM 安全钩子
  ├── uclamp_validate()                 // 验证 util clamp 上下限
  ├── cpuset_lock + task_rq_lock        // 拿 rq 锁，进入临界区
  │     ├── update_rq_clock()           // 先刷新 rq 时钟（统计基线）
  │     └── recheck 标签                // 锁内重查策略（防止与并发改动打架）
  ├── DL 带宽检查
  │     └── sched_dl_overflow()         // DL 任务会不会超系统带宽预算
  ├── __normal_prio() / rt_effective_prio()  // 重算静态/有效优先级
  ├── __setscheduler_class()            // 决定换到哪个 sched_class（dl/rt/fair/scx...）
  ├── __setscheduler_params()           // 写入具体参数（__setparam_dl/__setparam_fair/set_load_weight）
  ├── __setscheduler_dl_pi()            // DL 优先级继承调整
  ├── __setscheduler_uclamp()           // 应用 uclamp 限制
  ├── rt_mutex_adjust_pi()              // RT mutex 优先级继承链调整
  └── balance_callbacks()               // 出临界区后执行推迟的入队/迁移回调
```

内部 `sched_setattr` 的调用方（`find_callers`）：`trace_wakeup_test_thread`（`kernel/trace/trace_selftest.c:1433`，调度器自测试）。

---

## 五、新旧接口对比：`sched_setscheduler` vs `sched_setattr`

| 维度 | 老接口 `sched_setscheduler` | 新接口 `sched_setattr` |
|---|---|---|
| 参数结构 | `struct sched_param`（仅 `int sched_priority`） | `struct sched_attr`（11 个字段） |
| 能表达 DL | 否 | 是（`sched_runtime/deadline/period`） |
| 能表达 uclamp | 否 | 是（`sched_util_min/max`） |
| 能表达 nice | 间接（CFS 只认 nice） | 是（`sched_nice`） |
| 策略/参数分离 | 不支持 | `SCHED_FLAG_KEEP_POLICY` / `KEEP_PARAMS` 标志 |
| 变长结构兼容 | 无 | `sched_attr.size` + `sched_copy_attr()` 做新旧版本适配 |
| 引入版本 | 2.6 之前（长期） | 3.14（配合 SCHED_DEADLINE） |

`struct sched_attr`（`include/uapi/linux/sched/types.h`，MCP 查询确认）：

| 字段 | 类型 | 含义 |
|---|---|---|
| `size` | `__u32` | 结构体长度，用于前后向兼容 |
| `sched_policy` | `__u32` | 调度策略（SCHED_* 枚举） |
| `sched_flags` | `__u64` | 行为标志（见 6.3） |
| `sched_nice` | `__s32` | nice 值（SCHED_NORMAL/BATCH） |
| `sched_priority` | `__u32` | 静态优先级（SCHED_FIFO/RR，1..MAX_RT_PRIO-1） |
| `sched_runtime` | `__u64` | DL 任务每个实例运行时间（ns） |
| `sched_deadline` | `__u64` | DL 任务相对截止时间（ns） |
| `sched_period` | `__u64` | DL 任务激活周期（ns） |
| `sched_util_min` | `__u32` | uclamp 利用率下限 |
| `sched_util_max` | `__u32` | uclamp 利用率上限 |

`struct sched_param` 则只有一个 `int sched_priority` 字段（`include/uapi/linux/sched/types.h`）。

---

## 六、策略与属性速查

### 6.1 调度策略枚举（`include/uapi/linux/sched.h`）

| 值 | 宏 | 调度类 | 含义 |
|---|---|---|---|
| 0 | `SCHED_NORMAL` | CFS | 普通公平调度，靠 nice 分权重 |
| 1 | `SCHED_FIFO` | RT | 先进先出实时，优先级高者先跑，跑完才让 |
| 2 | `SCHED_RR` | RT | 轮转实时，同优先级平分时间片 |
| 3 | `SCHED_BATCH` | CFS | 批处理，更省电、更少抢占 |
| 5 | `SCHED_IDLE` | CFS（idle） | 极低优先级，仅在系统空闲时运行 |
| 6 | `SCHED_DEADLINE` | DL | 硬实时，用 runtime/deadline/period 描述 |
| 7 | `SCHED_EXT` | sched_ext | 可扩展 BPF 调度器 |

### 6.2 查询类 syscall 返回值语义

- `sched_getscheduler`：返回策略值（SCHED_* 枚举）；
- `sched_get_priority_max/min`：返回该策略下优先级上下限（RT 策略返回 `MAX_RT_PRIO-1` / `1`，CFS 返回 0）；
- `sched_rr_get_interval`：把 SCHED_RR 时间片写入 `timespec`。

### 6.3 `sched_flags` 位定义（`include/uapi/linux/sched.h`）

| 标志 | 值 | 含义 |
|---|---|---|
| `SCHED_FLAG_RESET_ON_FORK` | 0x01 | fork 后重置调度策略 |
| `SCHED_FLAG_RECLAIM` | 0x02 | DL reclaim（GRUB） |
| `SCHED_FLAG_DL_OVERRUN` | 0x04 | DL 超时 |
| `SCHED_FLAG_KEEP_POLICY` | 0x08 | 保持原策略，只改参数 |
| `SCHED_FLAG_KEEP_PARAMS` | 0x10 | 保持原参数，只改策略 |
| `SCHED_FLAG_UTIL_CLAMP_MIN/MAX` | 0x20/0x40 | 设置 uclamp 下/上限 |

---

## 七、关键概念补充

### 7.1 `SYSCALL_DEFINEn` 宏如何生成三层函数

`include/linux/syscalls.h` 的宏展开（源码确认）：

```
SYSCALL_DEFINE3(sched_setscheduler, ...)
  → SYSCALL_DEFINEx(3, _sched_setscheduler, ...)
      → __SYSCALL_DEFINEx(3, _sched_setscheduler, ...)
          ├── 定义 __do_sys_sched_setscheduler(...)   // 真正的实现体
          ├── 定义 __se_sys_sched_setscheduler(...)   // 符号扩展桩，调用 __do_sys_*
          └── （架构层）__x64_sys_sched_setscheduler   // syscall 表引用它，转发到 __se_sys_*
```

这就是为什么源码里看不到 `__do_sys_*` 的显式定义——它们是宏生成的。

> 注：kernel-graph 已于 2026-09-02 增强（分支 `feat/syscall-indexing`）：`parse_kernel.py` 新增 `extract_syscalls`，识别 `SYSCALL_DEFINEn`（含 `SYSCALL_DEFINE0` 被 tree-sitter 解析为 function_definition 的特殊形态）并合成 `__do_sys_*`/`__x64_sys_*`/`__do_compat_sys_*` 行；`mcp_server.py` 的 `functions_in_file` 已做路径分隔符归一化。现在可直接 `find_definition("__do_sys_sched_setattr")`、`search_functions("__do_sys_sched")` 查询。MCP 服务重启后生效。

### 7.2 为什么 syscall 定义搬到了 `kernel/sched/syscalls.c`

旧内核中调度 syscall 定义在 `kernel/sched/core.c` 里，与核心调度逻辑混在一起。内核 6.x 起把"用户态 API 层"单独抽到 `syscalls.c`，`core.c` 专注调度主路径。阅读时注意区分：**syscalls.c 是"门面"，真正排队的是 core.c / fair.c / rt.c / dl.c 里的调度类钩子**。

### 7.3 DL 参数校验：为什么比 RT/CFS 复杂

`__checkparam_dl()` 和 `sched_dl_overflow()` 是 DL 特有的两道关：
- `__checkparam_dl`：参数自洽——`runtime ≤ deadline ≤ period`，且数值在合理范围；
- `sched_dl_overflow`：全局带宽账本——系统里所有 DL 任务的总 util 不能超过 CPU 数量 × 每 CPU 带宽，否则 `-EBUSY`。

设计原因：DL 是硬实时，超订会直接导致某些实例错过截止时间，所以必须在**设置时就拒绝**，而不是运行中打折扣。

---

## 八、待验证 / 边界说明

- [ ] 本清单为 x86_64 视角（`syscall_64.tbl`）；其他架构（arm64/riscv 等）编号不同但函数名一致。
- [ ] 未展开：`sched_setattr` 中 `SCHED_FLAG_SUGOV`（schedutil 治理相关）具体消费路径。
- [ ] `sched_yield` 实际会调用 `do_sched_yield()` → CFS 的 `yield_task_fair()`，其 EEVDF 下的具体出队/占位行为留待专门分析。
- [ ] `sched_getscheduler` 等查询类 syscall 的完整读路径（`task_lock` → 读 `policy`）未逐行展开。
- [ ] clone/clone3 中与调度相关的 `CLONE_*` 标志（如 `CLONE_SCHED` 不存在、`clone3` 的 `exit_signal` 等）与 `sched_fork()` 的交互未在本清单展开（见知识节点 `sched_fork`，仍为 `unknown`）。

---

## 关联笔记

- `learn/sched/sched_read_guide.md` — 调度器阅读路线图
- `learn/sched/sched_class.md` — 调度类抽象与各策略实现
- `learn/sched/task_struct.md` — 被本清单修改的核心数据结构
- 知识节点状态见 `.claude/memory/sched/knowledge.md`（优先级与策略分组）
