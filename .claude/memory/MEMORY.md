# Memory Index — kernel-learning

## 子系统列表

| 子系统 | 目录 | mastered | exploring | unknown | 平均置信度 |
|---|---|---:|---:|---:|---:|
| 示例模块 | [example/](example/knowledge.md) | 1 | 1 | 1 | 0 |
| 调度器 | [sched/](sched/knowledge.md) | 18 | 5 | 78 | 0 |
| 内存管理 | [mm/](mm/knowledge.md) | 43 | 0 | 39 | 44.57 |

## 当前学习焦点

- **示例模块进度**：已建立三个示例知识节点，用于演示状态管理、调用关系和 Dashboard 展示。
- **调度器路线图**：已基于 Linux 7.2-rc6 生成阅读指南（`learn/sched/sched_read_guide.md`），建立 87 个 unknown 节点和初始依赖图，待 kernel-code-analyzer 逐个深化。
- **内存管理主数据结构**：已完成 `page`、`zone`、`pglist_data` 的逐字段分析，串起启动初始化、页分配、释放和节点回收主线。
- **用户虚拟内存主数据结构**：已完成 `mm_struct`、`vm_area_struct`、`vm_fault` 的逐字段分析，串起地址空间创建、VMA 建立、缺页处理和退出销毁主线。
- **用户虚拟内存映射事务**：已完成 `do_mmap`、`mmap_region`、`do_munmap` 的逐段分析，串起参数归一化、Maple Tree 区间覆盖/合并、提交回滚和页表撤销主线。
- **地址空间与根页表创建**：已完成 `mm_alloc`、`mm_init`、`mm_alloc_pgd`、`mm_free_pgd` 的逐行分析，并以 x86 `pgd_alloc/pgd_free` 串起通用初始化、架构根页表和逆序回滚。
- **fork 地址空间复制与 x86 根页表**：已完成 `dup_mm`、x86 `pgd_alloc`、x86 `pgd_free` 的逐行分析，串起 `CLONE_VM` 分流、VMA/页表/COW 复制、PAE/PTI/paravirt 根构造和最终析构。
- **用户缺页与普通页表填充**：已完成 x86 `do_user_addr_fault`、通用 `handle_mm_fault` / `__handle_mm_fault`、`__pte_alloc`、`handle_pte_fault` 的逐段分析，串起 VMA 快慢锁路径、页表逐级分配、大页回退和 PTE 状态分派。
- **PTE 末端填页与 COW**：已完成 `do_anonymous_page`、`do_fault`、`do_wp_page` 的逐段分析，区分共享零页/匿名 folio、文件私有首次写 COW、共享后备写入、匿名页独占复用和事务式页面复制。
- **fork VMA与普通页表复制**：已完成 `dup_mmap`、`copy_page_range`、`copy_p4d_range`、`copy_pud_range`、`copy_pmd_range`、`copy_pte_range` 的逐段分析，串起 Maple Tree克隆、逐级页表复制、huge分流、PTE批处理、父子写保护与 pinned匿名页预复制。
- **mprotect权限变换**：已完成 `do_mprotect_pkey`、`mprotect_fixup`、`change_protection`、`change_pte_range` 的逐段分析，串起用户权限校验、VMA拆分合并、commit记账、huge分流以及present/softleaf PTE权限变换。
- **缓存与回收主数据结构**：已完成 `kmem_cache`、`address_space`、`lruvec`、`scan_control` 的逐字段分析，串起 SLUB 对象缓存、文件页缓存、LRU 归属和回收决策主线。
- **压缩与资源控制主数据结构**：已完成 `compact_control`、`mem_cgroup` 的逐字段分析，串起直接/后台压缩、memcg charge、定向回收、high 节流、max/OOM 与离线销毁主线。
- **启动期物理内存交接**：已完成 `memblock_add()`、`memblock_alloc_try_nid()`、`free_area_init()` 的逐行分析，区分物理区间登记、早期预留分配以及 node/zone 正式初始化三个阶段。

## 知识状态

- [example/knowledge.md](example/knowledge.md) — 示例节点表
- [example/dep-graph.md](example/dep-graph.md) — 示例依赖图
- [example/qa-log.md](example/qa-log.md) — 示例问答日志
- [sched/knowledge.md](sched/knowledge.md) — 调度器节点表
- [sched/dep-graph.md](sched/dep-graph.md) — 调度器依赖图
- [mm/knowledge.md](mm/knowledge.md) — 内存管理知识节点表
- [mm/dep-graph.md](mm/dep-graph.md) — 内存管理依赖图
- [open-questions.md](open-questions.md) — 开放问题
- [learning-journal.md](learning-journal.md) — 学习日志

## 最近 5 个分析

- `dup_mm/x86 pgd_alloc/x86 pgd_free` (mm, 2026-09-08)
- `do_user_addr_fault/handle_mm_fault/__handle_mm_fault/__pte_alloc/handle_pte_fault` (mm, 2026-09-08)
- `do_anonymous_page/do_fault/do_wp_page` (mm, 2026-09-08)
- `dup_mmap/copy_page_range/copy_p4d_range/copy_pud_range/copy_pmd_range/copy_pte_range` (mm, 2026-09-09)
- `do_mprotect_pkey/mprotect_fixup/change_protection/change_pte_range` (mm, 2026-09-09)

## 开放问题统计

CRITICAL: 0 · MEDIUM: 1 · LOW: 0
