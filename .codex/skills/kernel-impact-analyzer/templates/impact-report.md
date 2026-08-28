# 影响分析报告：{TARGET}

**分析日期**：{DATE}
**内核版本**：Linux 6.0
**修改描述**：{CHANGE_DESCRIPTION}
**分析模式**：{模式 A — 函数修改 / 模式 B — 结构体字段修改}

---

## 执行摘要

| 影响级别 | 函数数量 | 测试优先级 |
|---------|---------|-----------|
| Level 1 直接调用者 | {N1} | P0 必测 |
| Level 2 间接调用者（2层内） | {N2} | P1 建议 |
| Level 3 远程影响（3-5层） | {N3} | P2 回归 |
| Level 4 数据结构传播（仅模式B） | {N4 或 -} | P1 建议 |

**热路径警告**：{是 / 否} — {若是，列出函数名}
**SMP 风险**：{是 / 否}
**MPAM 路径风险**：{是 / 否}

---

## Level 1 — 直接调用者（P0 必测）

> 来源：`find_callers` 结果。直接调用被修改函数，或直接读写被修改字段。

| 函数名 | 文件:行号 | 风险标签 |
|--------|---------|---------|
| {func} | {file:line，来自 find_definition} | {HOT_PATH / SMP_SENSITIVE / RT_SENSITIVE / MPAM_SENSITIVE / -} |

---

## Level 2 — 间接调用者（P1 建议测试）

> 来源：`call_chain_up depth=2` 结果，已排除 Level 1 中的函数。

| 函数名 | 文件:行号 | 风险标签 |
|--------|---------|---------|
| {func} | {file:line} | {标签} |

---

## Level 3 — 远程影响（P2 回归测试）

> 来源：`call_chain_up depth=5` 结果，已排除 Level 1/2。仅列函数名，不展开分析。

{func1}、{func2}、{func3} ...

---

## Level 4 — 数据结构传播（P1，仅模式 B）

> 来源：`find_struct_writers` 结果中不在 Level 1-3 的部分。
> 模式 A 时跳过此节。

| 函数名 | 文件:行号 | 操作描述 |
|--------|---------|---------|
| {func} | {file:line} | {写入字段 / 读取字段} |

---

## 关键路径警告

> 仅当 Level 1-2 中存在 HOT_PATH / RT_SENSITIVE / MPAM_SENSITIVE 标签时展开。

### HOT_PATH 风险（如有）

{函数名} 位于调度热路径，修改后需用 `schbench` 或 `perf sched` 验证吞吐量无回退。

### SMP_SENSITIVE 风险（如有）

{函数名} 涉及 runqueue 锁操作，修改时需确认锁顺序不变，无新的死锁路径。

### MPAM_SENSITIVE 风险（如有）

{函数名} 位于 resctrl 路径，修改后需验证资源组隔离语义不变（检查 closid/rmid 分配逻辑）。

---

## 建议测试策略

1. **kprobe 验证**（Level 1 必做）
   在 Level 1 调用者入口插探针，确认参数和返回值变化符合预期：
   ```bash
   # 示例：在 foo_caller 入口打印参数
   bpftrace -e 'kprobe:foo_caller { printf("%s\n", comm); }'
   ```

2. **热路径负载测试**（如有 HOT_PATH 标签）
   ```bash
   schbench -m 2 -t 8 -r 30   # 调度吞吐量基准
   cyclictest -l 10000 -p 80   # RT 延迟基准
   ```

3. **MPAM 功能验证**（如有 MPAM_SENSITIVE 标签）
   ```bash
   # 验证资源组隔离仍然生效
   cat /sys/fs/resctrl/info/L3/cbm_mask
   ```

4. **代码风格检查**
   ```bash
   scripts/checkpatch.pl --no-tree -f {修改的文件}
   ```

---

*由 kernel-impact-analyzer skill 生成。如需调用链可视化，输入 `y` 触发 drawio-diagram-generator。*
