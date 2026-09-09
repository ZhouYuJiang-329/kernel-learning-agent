# Linux 内存管理内核代码阅读需求文档

> 基于：kernel-graph MCP 的 Linux 7.2-rc6 索引；本机 `E:\work\kernel\linux` 当前为 `v7.3-rc2-dirty`，仅扫描其 `mm/Makefile`、`mm/Kconfig` 和文件目录以确认子系统组成，不用它替代 MCP 的 7.2-rc6 符号定位
> 生成时间：2026-09-08
> 说明：本次直接以 Linux 内存管理子系统为阅读对象；所有文件路径和行号均由当前 kernel-graph MCP（Linux 7.2-rc6）确认。2026-09-08 增补“用户页表从创建、填充、复制、改权限到销毁”的完整生命周期路线。

## 概览：涉及的内核子系统

Linux 内存管理不是一条单独路径，而是由“启动期发现物理内存 → 建立节点和 zone → 伙伴系统提供页 → SLUB/vmalloc 提供内核对象与虚拟连续区 → VMA 描述进程地址空间 → 创建页表根 → 缺页按需填充页表 → fork 复制并建立 COW → mprotect 修改权限 → munmap/exit 清页表和 TLB → 页缓存承接文件 I/O → 回收、交换、压缩和 OOM 处理压力”组成。建议先打通普通 4 KiB 页的主线，再进入 THP、HugeTLB、NUMA、memcg、内存热插拔等专项；否则容易同时被地址空间、分配器和回收策略三套术语阻塞。

本次没有可用的 Confluence 架构综述，因此不生成仅靠记忆编写的概念 primer。基础概念缺口应在后续阅读中单独补齐。

## 关键数据结构阅读主线

1. `page`（阶段 1，`include/linux/mm_types.h:80`）：物理页管理的共同对象，连接启动期建模、伙伴系统、页缓存、回收、迁移与 memcg。
2. `zone`（阶段 1，`include/linux/mmzone.h:979`）：理解水位线、空闲区和分配约束如何影响 `get_page_from_freelist()` 与直接回收。
3. `pglist_data`（阶段 1，`include/linux/mmzone.h:1478`）：把 NUMA 节点、zone、回收线程和节点级统计连接起来。
4. `mm_struct`（阶段 2，`include/linux/mm_types.h:1175`）：进程地址空间入口，连接 VMA 集合、页表、锁与 `do_mmap()`/`do_munmap()`。
5. `vm_area_struct`（阶段 2，`include/linux/mm_types.h:923`）：描述一段虚拟地址区间及其访问属性，连接映射创建与缺页处理。
6. `vm_fault`（阶段 3，`include/linux/mm.h:753`）：连接 VMA fault 回调、文件页缓存和页表安装的故障上下文。
7. `pgd_t/p4d_t/pud_t/pmd_t/pte_t`（阶段 3，体系结构页表头文件）：先理解各级表项只是架构相关值类型，再读通用 `mm/memory.c` 如何通过 helper 操作它们；kernel-graph 未给这些 typedef 返回统一定义位置，应结合目标架构确认。
8. `mmu_gather`（阶段 3，`include/asm-generic/tlb.h:325`）：串起批量清表、延迟释放页表页和最终 TLB flush；阅读入口是 `tlb_gather_mmu()` 与 `tlb_finish_mmu()`。
9. `mmu_notifier_range`（阶段 3，`include/linux/mmu_notifier.h:304`）：描述页表失效的地址范围和事件，使 KVM/IOMMU 等二级地址转换消费者同步失效。
10. `kmem_cache`（阶段 4，`mm/slab.h:240`）：连接缓存级对象分配、每 CPU 快路径和后备页分配。
11. `address_space`（阶段 5，`include/linux/fs.h:471`）：连接文件 inode、页缓存、预读和 `filemap_fault()`。
12. `lruvec`（阶段 6，`include/linux/mmzone.h:766`）：连接节点或 memcg 的 LRU 集合与 `shrink_lruvec()`。
13. `scan_control`（阶段 6，`mm/vmscan.c:76`）：把回收目标、扫描约束和直接回收/后台回收场景连接起来。
14. `compact_control`（阶段 7，`mm/internal.h:823`）：连接空闲页扫描、可迁移页隔离与 `compact_zone()`。
15. `mem_cgroup`（阶段 7，`include/linux/memcontrol.h:202`）：连接内存记账、限制、memcg 回收和 memcg OOM。

**已有结构体深度笔记**：[`page_zone_pglist_data.md`](page_zone_pglist_data.md)——逐字段解释 `page`、`zone`、`pglist_data`，并串起初始化、分配、释放和回收路径。

## 分类详解

### 分类一：启动期物理内存建模

**阅读目标**：

1. 如何由固件或架构提供的物理内存区间，经 `memblock_add()` 进入启动期内存模型？
2. 如何用 `memblock_alloc_try_nid()` 在指定 NUMA 节点附近分配启动期元数据？
3. 如何由 `free_area_init()` 建立节点、zone 与伙伴系统接管所需的运行时状态？
4. 怎样划清 memblock 只服务于早期启动、伙伴系统服务于常规运行期的交接点？

**关键源文件**：

| 文件 | 行号 | 重点关注 |
|---|---:|---|
| `mm/memblock.c` | 751 | `memblock_add()`：登记可用物理内存区间 |
| `mm/memblock.c` | 1851 | `memblock_alloc_try_nid()`：带节点偏好的启动期分配 |
| `mm/mm_init.c` | 1761 | `free_area_init()`：初始化节点和 zone |

### 分类二：进程地址空间与 VMA

**阅读目标**：

1. 如何由 `do_mmap()` 选择地址并把新映射交给 VMA 管理层？
2. 如何由 `mmap_region()` 创建或合并 VMA，并处理文件映射关联？
3. 如何由 `do_munmap()` 拆分/删除目标区间并启动页表解除映射？
4. 怎样用 `mm_struct`、`vm_area_struct` 和 maple tree 串起一次映射的查找与修改？

**关键源文件**：

| 文件 | 行号 | 重点关注 |
|---|---:|---|
| `mm/mmap.c` | 338 | `do_mmap()`：MMU 场景的通用 mmap 内核入口 |
| `mm/vma.c` | 2938 | `mmap_region()`：建立映射区间 |
| `mm/mmap.c` | 1077 | `do_munmap()`：解除映射入口 |
| `include/linux/mm_types.h` | 923 | `vm_area_struct` 与 `mm_struct` 的定义位置 |

### 分类三：用户页表完整生命周期

**阅读目标**：

1. 如何由 `mm_init()`、`mm_alloc_pgd()` 和架构 `pgd_alloc()` 为新地址空间建立页表根，并在失败或最终释放时由 `mm_free_pgd()`/`pgd_free()` 对称销毁？
2. 如何让 x86 用户态访问异常从 `do_user_addr_fault()` 进入 `handle_mm_fault()`，再由 `__handle_mm_fault()` 按需分配 P4D/PUD/PMD/PTE 层级并安装匿名页或文件页映射？
3. 如何由 `dup_mm()`、`dup_mmap()` 和 `copy_page_range()` 在 fork 时复制页表，并对私有可写映射执行写保护以建立后续 COW？
4. 如何由 `do_mprotect_pkey()`、`mprotect_fixup()` 和 `change_protection()` 同时修改 VMA 权限与已有 PTE/PMD 权限，并处理 TLB、MMU notifier 和 VMA 拆分/合并？
5. 如何区分 `do_munmap()` 的局部销毁与 `exit_mmap()` 的整地址空间销毁，并追踪 `unmap_vmas()`、`free_pgtables()`、`free_pgd_range()` 的职责边界？
6. 如何由 `mmu_gather`、`tlb_gather_mmu()`、`tlb_finish_mmu()` 和 `mmu_notifier_range` 保证 CPU、KVM/IOMMU 等观察者不继续使用已经失效的页表翻译？

**生命周期阅读顺序**：

1. **创建页表根**：`mm_alloc()` → `mm_init()` → `mm_alloc_pgd()` → 目标架构 `pgd_alloc()`；退出侧对照 `mm_free_pgd()` → `pgd_free()`。
2. **缺页按需填充**：`do_user_addr_fault()` → `handle_mm_fault()` → `__handle_mm_fault()`；重点跟踪 `p4d_alloc()`、`pud_alloc()`、`pmd_alloc()`、`__pte_alloc()`，再读 `handle_pte_fault()`、`do_anonymous_page()`、`do_fault()` 和 `do_wp_page()`。
3. **fork 复制与 COW**：`dup_mm()` → `dup_mmap()` → `copy_page_range()` → `copy_p4d_range()` → `copy_pud_range()` → `copy_pmd_range()` → `copy_pte_range()`；当前版本进一步按 present/non-present 表项分到 `copy_present_ptes()` 与 `copy_nonpresent_pte()`。
4. **修改权限**：`do_mprotect_pkey()` → `mprotect_fixup()` → `change_protection()` → `change_protection_range()` → `change_p4d_range()`/`change_pud_range()`/`change_pmd_range()`/`change_pte_range()`。
5. **局部解除映射**：先读 [`do_mmap.md`](do_mmap.md) 中的 `do_munmap()` VMA 隔离主线，再跟入 `unmap_region()`、`unmap_vmas()` 和 `__zap_vma_range()`，观察叶子表项、rmap、folio 引用与 TLB 的拆除。
6. **进程退出销毁**：`mmput()` → `__mmput()` → `exit_mmap()`；重点比较 `unmap_vmas()` 清叶子映射、`free_pgtables()`/`free_pgd_range()` 释放页表层级、`tlb_finish_mmu()` 完成批量失效、`mm_free_pgd()` 释放根页表的先后关系。

**关键源文件**：

| 文件 | 行号 | 重点关注 |
|---|---:|---|
| `kernel/fork.c` | 1172 | `mm_alloc()`：分配新的地址空间对象 |
| `kernel/fork.c` | 1091 | `mm_init()`：初始化新 `mm_struct` 并进入页表根创建 |
| `kernel/fork.c` | 581 | `mm_alloc_pgd()`：调用架构 `pgd_alloc()` 建立根页表 |
| `kernel/fork.c` | 589 | `mm_free_pgd()`：调用架构接口释放根页表 |
| `kernel/fork.c` | 1527 | `dup_mm()`：fork 地址空间复制入口 |
| `arch/x86/mm/pgtable.c` | 311 | x86 `pgd_alloc()`：分配并准备页表根 |
| `arch/x86/mm/pgtable.c` | 365 | x86 `pgd_free()`：释放页表根；其他架构位置不同 |
| `arch/x86/mm/fault.c` | 1215 | `do_user_addr_fault()`：x86 用户缺页入口 |
| `mm/memory.c` | 6841 | `handle_mm_fault()`：通用 fault 总入口 |
| `mm/memory.c` | 6604 | `__handle_mm_fault()`：逐级分配/遍历 P4D、PUD、PMD 并进入 PTE 路径 |
| `mm/memory.c` | 451 | `__pte_alloc()`：为用户地址按需分配 PTE 页表 |
| `mm/memory.c` | 6514 | `handle_pte_fault()`：PTE 级分派 |
| `mm/memory.c` | 5427 | `do_anonymous_page()`：匿名页首次 fault |
| `mm/memory.c` | 6104 | `do_fault()`：文件或共享后备的 fault 分派 |
| `mm/memory.c` | 4380 | `do_wp_page()`：写保护与 COW |
| `mm/mmap.c` | 1708 | `dup_mmap()`：复制 VMA 并调用 `copy_page_range()` |
| `mm/memory.c` | 1588 | `copy_page_range()`：普通页表复制总入口 |
| `mm/memory.c` | 1534 | `copy_p4d_range()`：复制/分配 P4D 下级范围 |
| `mm/memory.c` | 1497 | `copy_pud_range()`：复制 PUD 范围 |
| `mm/memory.c` | 1460 | `copy_pmd_range()`：复制 PMD、THP 或继续进入 PTE |
| `mm/memory.c` | 1305 | `copy_pte_range()`：复制 PTE 范围并处理锁、批量和重试 |
| `mm/mprotect.c` | 871 | `do_mprotect_pkey()`：mprotect/pkey 用户入口和 VMA 遍历 |
| `mm/mprotect.c` | 759 | `mprotect_fixup()`：调整 VMA 并触发已有页表权限修改 |
| `mm/mprotect.c` | 686 | `change_protection()`：页表权限修改总入口 |
| `mm/mprotect.c` | 331 | `change_pte_range()`：叶子 PTE 权限更新 |
| `mm/vma.c` | 525 | `unmap_region()`：局部 unmap 的页表和 TLB 拆除入口 |
| `mm/memory.c` | 2292 | `unmap_vmas()`：遍历 VMA 并清除叶子映射 |
| `mm/memory.c` | 2206 | `__zap_vma_range()`：清一段 VMA 的表项和反向映射 |
| `mm/memory.c` | 373 | `free_pgtables()`：释放一组 VMA 对应的页表层级 |
| `mm/memory.c` | 298 | `free_pgd_range()`：自 PGD 向下释放给定地址范围的页表页 |
| `mm/mmap.c` | 1288 | `exit_mmap()`：进程退出时销毁全部 VMA 与用户页表 |
| `kernel/fork.c` | 1185 | `__mmput()`：最后一个 `mm_users` 引用消失后的地址空间销毁入口 |
| `mm/mmu_gather.c` | 462 | `tlb_gather_mmu()`：初始化批量页表/TLB 回收状态 |
| `mm/mmu_gather.c` | 515 | `tlb_finish_mmu()`：提交 TLB flush 并释放延迟回收对象 |
| `include/linux/mmu_notifier.h` | 533 | `mmu_notifier_range_init()`：描述需通知 KVM/IOMMU 等观察者的失效范围 |

**已有学习笔记**：

- [`mm_alloc.md`](mm_alloc.md)——`mm_alloc()`、`mm_init()`、根页表创建/释放，以及 x86 `pgd_alloc()/pgd_free()` 实例。
- [`dup_mm.md`](dup_mm.md)——普通 fork 的独立地址空间复制事务、VMA/页表/COW 分工，以及 x86 `pgd_alloc()/pgd_free()` 的 PAE、PTI、paravirt 配置细节。
- [`do_user_addr_fault.md`](do_user_addr_fault.md)——x86 用户地址 #PF 入口、通用 `handle_mm_fault()` 外围、P4D/PUD/PMD逐级处理、PTE表按需分配与PTE状态分派。
- [`do_anonymous_page_do_fault_do_wp_page.md`](do_anonymous_page_do_fault_do_wp_page.md)——PTE末端的匿名首次缺页、文件/共享后备分派，以及写保护、复用与COW事务。
- [`dup_mmap.md`](dup_mmap.md)——fork时复制 VMA、逐级复制普通页表、批量处理 PTE，并建立父子写保护与后续 COW约束。
- [`do_mprotect_pkey.md`](do_mprotect_pkey.md)——mprotect/pkey入口、VMA拆分合并、页表权限总入口与present/softleaf PTE权限变换。
- [`mm_struct_vm_area_struct_vm_fault.md`](mm_struct_vm_area_struct_vm_fault.md)——`mm_struct`、VMA、fault 上下文及普通页表 fault 分派。
- [`do_mmap.md`](do_mmap.md)——mmap 建立 VMA、`MAP_FIXED` 覆盖和 munmap 拆除事务；可作为页表销毁阶段的 VMA 前置知识。

### 分类四：伙伴系统与物理页分配

**阅读目标**：

1. 如何由 `__alloc_pages_noprof()` 把 GFP、order、NUMA 策略转换为具体分配约束？
2. 如何由 `get_page_from_freelist()` 按 zonelist、水位线和迁移类型寻找空闲页？
3. 怎样在快路径失败后进入 `__alloc_pages_slowpath()`，并依次尝试回收、压缩与 OOM？
4. 如何由 `free_unref_folios()` 把释放对象送回每 CPU 缓存或伙伴系统？
5. 怎样从 `zone` 的水位和空闲区状态解释一次高阶分配失败？

**关键源文件**：

| 文件 | 行号 | 重点关注 |
|---|---:|---|
| `mm/page_alloc.c` | 5466 | `__alloc_pages_noprof()`：7.2-rc6 页分配入口 |
| `mm/page_alloc.c` | 3799 | `get_page_from_freelist()`：伙伴系统快路径核心 |
| `mm/page_alloc.c` | 4783 | `__alloc_pages_slowpath()`：回收、压缩与 OOM 协调 |
| `mm/page_alloc.c` | 3010 | `free_unref_folios()`：批量释放 folio |
| `include/linux/mmzone.h` | 979 | `zone`、`pglist_data` 的定义位置 |

### 分类五：SLUB 对象分配与 vmalloc

**阅读目标**：

1. 如何由 `kmem_cache_alloc_noprof()` 从指定 slab cache 分配对象并命中每 CPU 快路径？
2. 如何由 `__kmalloc_noprof()` 按大小选择 kmalloc cache，何时转为大对象页分配？
3. 如何由 `kfree()` 识别并释放 slab 对象或大块 kmalloc 对象？
4. 如何由 `__vmalloc_noprof()` 用虚拟连续映射拼接物理上不连续的页？
5. 如何根据连续性、大小和上下文约束选择 kmalloc、页分配或 vmalloc？

**关键源文件**：

| 文件 | 行号 | 重点关注 |
|---|---:|---|
| `mm/slub.c` | 5001 | `kmem_cache_alloc_noprof()`：指定 cache 分配入口 |
| `mm/slub.c` | 5431 | `__kmalloc_noprof()`：通用 kmalloc 后端 |
| `mm/slub.c` | 6771 | `kfree()`：通用释放入口 |
| `mm/vmalloc.c` | 4177 | `__vmalloc_noprof()`：MMU 场景 vmalloc 入口 |
| `mm/slab.h` | 240 | `kmem_cache` 定义位置 |

### 分类六：页缓存、文件缺页与预读

**阅读目标**：

1. 如何由 `filemap_fault()` 把文件映射缺页转换为页缓存查找和文件系统读页？
2. 如何由 `filemap_get_folio()` 按索引取得页缓存 folio，并表达未命中或异常结果？
3. 如何由 `page_cache_ra_unbounded()` 构造同步/异步预读窗口并提交读请求？
4. 如何由 `address_space` 把文件、缓存索引和文件系统 `a_ops` 连接起来？
5. 怎样区分匿名页 fault 与文件页 fault 在页面来源和回收方式上的差别？

**关键源文件**：

| 文件 | 行号 | 重点关注 |
|---|---:|---|
| `mm/filemap.c` | 3555 | `filemap_fault()`：通用文件映射 fault |
| `include/linux/pagemap.h` | 802 | `filemap_get_folio()`：页缓存查找接口 |
| `mm/readahead.c` | 222 | `page_cache_ra_unbounded()`：页缓存预读 |
| `include/linux/fs.h` | 471 | `address_space` 定义位置 |

### 分类七：内存回收、交换与 OOM

**阅读目标**：

1. 如何由页分配慢路径通过 `try_to_free_pages()` 发起同步直接回收？
2. 如何由 `shrink_node()` 和 `shrink_lruvec()` 把节点级压力落到匿名页/文件页 LRU 扫描？
3. 如何由 `do_swap_page()` 处理交换 PTE，并通过 `swapin_readahead()` 读回相邻页？
4. 如何由 `swap_read_folio()` 把交换读请求提交到后端或 zswap 路径？
5. 如何由 `out_of_memory()` 在回收无效后执行 OOM 约束检查与受害者选择？

**关键源文件**：

| 文件 | 行号 | 重点关注 |
|---|---:|---|
| `mm/vmscan.c` | 6769 | `try_to_free_pages()`：直接回收入口 |
| `mm/vmscan.c` | 6239 | `shrink_node()`：节点级回收 |
| `mm/vmscan.c` | 5969 | `shrink_lruvec()`：LRU 集合扫描 |
| `mm/memory.c` | 4881 | `do_swap_page()`：交换页缺页处理 |
| `mm/swap_state.c` | 987 | `swapin_readahead()`：交换预读 |
| `mm/page_io.c` | 452 | `swap_read_folio()`：交换读 I/O |
| `mm/oom_kill.c` | 1103 | `out_of_memory()`：OOM 总入口 |

### 分类八：内存压缩、迁移与 memcg

**阅读目标**：

1. 如何由 `compact_zone()` 从 zone 两端扫描并形成可供高阶分配使用的连续空闲区？
2. 如何由 `migrate_pages()` 批量搬迁页面，并处理不可迁移或暂时失败的页面？
3. 如何由 `mem_cgroup_charge()` 把新页纳入 memcg 记账路径？
4. 如何由 `try_charge_memcg()` 处理配额不足、回收、OOM 和重试？
5. 怎样判断一次分配失败的根因是总量不足、外部碎片、NUMA 约束还是 memcg 限制？

**关键源文件**：

| 文件 | 行号 | 重点关注 |
|---|---:|---|
| `mm/compaction.c` | 2561 | `compact_zone()`：zone 压缩核心 |
| `mm/migrate.c` | 2100 | `migrate_pages()`：页面迁移入口 |
| `include/linux/memcontrol.h` | 657 | `mem_cgroup_charge()`：memcg 记账接口 |
| `mm/memcontrol.c` | 2645 | `try_charge_memcg()`：charge、回收与 OOM 协调 |
| `mm/internal.h` | 823 | `compact_control` 定义位置 |

## 阅读顺序建议

### 阶段 1（必读，3—4 天）：启动期建模 → 伙伴系统

收获：能够从一段物理内存区间追到 `zone` 和伙伴系统，并根据 GFP、order、水位线与 zonelist 解释普通页分配为什么成功或失败。

### 阶段 2（必读，3—4 天）：`mm_struct` → VMA 映射管理

收获：能够从 mmap/munmap 请求定位 VMA 的创建、查找、合并、拆分和删除职责，并知道哪些问题属于虚拟地址管理、哪些属于实际物理页映射。

### 阶段 3（必读，8—12 天）：页表根创建 → fault 填充 → fork 复制/COW → mprotect → munmap/exit 销毁

收获：能够从 `mm_struct::pgd` 的建立开始，追踪普通 4 KiB 页表的按需分配、fork 复制与写保护、权限修改、局部/全量销毁，以及 MMU notifier 和 TLB 回收；同时能够判断一次 fault 会进入匿名页、COW、交换页、文件页还是大页路径。

### 阶段 4（必读，3—4 天）：SLUB → kmalloc → vmalloc

收获：能够为内核对象选择合适的分配接口，并从分配大小、物理连续性和上下文约束定位常见内存分配问题。

### 阶段 5（必读，3—4 天）：页缓存 → 文件 fault → 预读

收获：能够解释 mmap 文件第一次访问时数据如何进入页缓存，以及缺页、缓存命中、读 I/O 和预读之间的关系。

### 阶段 6（必读，5—7 天）：LRU 回收 → 交换 → OOM

收获：能够从分配慢路径追到直接回收，区分匿名页与文件页的回收去向，并判断系统为何最终进入 OOM。

### 阶段 7（进阶，4—6 天）：压缩/迁移 → NUMA → memcg

收获：能够区分内存总量压力与碎片问题，解释页面迁移和内存控制组如何改变分配与回收边界。

### 阶段 8（按需）：THP、HugeTLB、KSM、CMA、热插拔与故障处理

收获：在掌握普通页主线后，能按具体工作场景选择专项，而不把特殊页机制混入基础路径。

## API 快速检索

| API / 结构体 | 头文件 | 实现文件 | 行号 | 一句话说明 |
|---|---|---|---:|---|
| `memblock_add` | — | `mm/memblock.c` | 751 | 向 memblock 登记物理内存区间 |
| `memblock_alloc_try_nid` | — | `mm/memblock.c` | 1851 | 启动期按节点偏好分配内存 |
| `free_area_init` | — | `mm/mm_init.c` | 1761 | 初始化节点与 zone |
| `do_mmap` | — | `mm/mmap.c` | 338 | 建立用户虚拟内存映射的通用入口 |
| `mmap_region` | — | `mm/vma.c` | 2938 | 创建映射区间 |
| `do_munmap` | — | `mm/mmap.c` | 1077 | 解除用户地址区间映射 |
| `mm_alloc` | — | `kernel/fork.c` | 1172 | 分配新的 `mm_struct` 地址空间对象 |
| `mm_init` | — | `kernel/fork.c` | 1091 | 初始化新地址空间并建立页表根等核心状态 |
| `mm_alloc_pgd` | — | `kernel/fork.c` | 581 | 调用架构接口分配 `mm_struct::pgd` |
| x86 `pgd_alloc` | — | `arch/x86/mm/pgtable.c` | 311 | 分配并准备 x86 用户页表根 |
| x86 `pgd_free` | — | `arch/x86/mm/pgtable.c` | 365 | 释放 x86 页表根 |
| `do_user_addr_fault` | — | `arch/x86/mm/fault.c` | 1215 | x86 用户态地址故障入口 |
| `handle_mm_fault` | `include/linux/mm.h` | `mm/memory.c` | 6841 | 通用内存 fault 总入口 |
| `__handle_mm_fault` | — | `mm/memory.c` | 6604 | 遍历或建立 P4D/PUD/PMD 并进入 PTE fault |
| `__p4d_alloc` | `include/linux/mm.h` | `mm/memory.c` | 6913 | 分配缺失的 P4D 页表层级 |
| `__pud_alloc` | `include/linux/mm.h` | `mm/memory.c` | 6936 | 分配缺失的 PUD 页表层级 |
| `__pmd_alloc` | `include/linux/mm.h` | `mm/memory.c` | 6959 | 分配缺失的 PMD 页表层级 |
| `__pte_alloc` | — | `mm/memory.c` | 451 | 分配缺失的用户 PTE 页表 |
| `handle_pte_fault` | — | `mm/memory.c` | 6514 | PTE 级 fault 分派 |
| `do_anonymous_page` | — | `mm/memory.c` | 5427 | 建立匿名页映射 |
| `do_fault` | — | `mm/memory.c` | 6104 | 分派文件/共享后备 fault |
| `do_wp_page` | — | `mm/memory.c` | 4380 | 处理写保护与 COW |
| `dup_mm` | — | `kernel/fork.c` | 1527 | fork 时创建并复制地址空间 |
| `dup_mmap` | — | `mm/mmap.c` | 1708 | 复制 VMA 并驱动页表复制 |
| `copy_page_range` | — | `mm/memory.c` | 1588 | 普通/hugetlb 页表复制总入口 |
| `copy_p4d_range` | — | `mm/memory.c` | 1534 | 复制 P4D 下级范围 |
| `copy_pud_range` | — | `mm/memory.c` | 1497 | 复制 PUD 范围 |
| `copy_pmd_range` | — | `mm/memory.c` | 1460 | 复制 PMD/THP 或下钻到 PTE |
| `copy_pte_range` | — | `mm/memory.c` | 1305 | 复制叶子 PTE 范围 |
| `copy_present_ptes` | — | `mm/memory.c` | 1210 | 批量复制 present PTE |
| `copy_nonpresent_pte` | — | `mm/memory.c` | 1007 | 复制 swap、迁移、marker 等非 present 表项 |
| `do_mprotect_pkey` | — | `mm/mprotect.c` | 871 | mprotect/pkey 权限修改入口 |
| `mprotect_fixup` | — | `mm/mprotect.c` | 759 | 调整 VMA 并修改已有页表权限 |
| `change_protection` | — | `mm/mprotect.c` | 686 | 页表权限修改总入口 |
| `change_protection_range` | — | `mm/mprotect.c` | 656 | 从 PGD 层开始修改给定地址范围 |
| `change_p4d_range` | — | `mm/mprotect.c` | 633 | 修改 P4D 下级范围 |
| `change_pud_range` | — | `mm/mprotect.c` | 574 | 修改 PUD 范围或处理 PUD 大页 |
| `change_pmd_range` | — | `mm/mprotect.c` | 504 | 修改 PMD 范围、THP 或继续下钻 |
| `change_pte_range` | — | `mm/mprotect.c` | 331 | 修改叶子 PTE 权限和相关软件位 |
| `unmap_region` | — | `mm/vma.c` | 525 | 局部 unmap 的页表/TLB 拆除入口 |
| `unmap_vmas` | — | `mm/memory.c` | 2292 | 遍历 VMA 并清叶子映射 |
| `__zap_vma_range` | — | `mm/memory.c` | 2206 | zap 一段 VMA 的表项和反向映射 |
| `free_pgtables` | — | `mm/memory.c` | 373 | 释放 VMA 范围对应的页表层级 |
| `free_pgd_range` | — | `mm/memory.c` | 298 | 自 PGD 向下释放给定范围的页表页 |
| `exit_mmap` | — | `mm/mmap.c` | 1288 | 最后地址空间用户退出时销毁全部映射 |
| `__mmput` | — | `kernel/fork.c` | 1185 | `mm_users` 归零后调用 `exit_mmap()` |
| `mmput` | — | `kernel/fork.c` | 1211 | 释放一个完整地址空间用户引用 |
| `mm_free_pgd` | — | `kernel/fork.c` | 589 | 调用架构接口释放根页表 |
| `tlb_gather_mmu` | — | `mm/mmu_gather.c` | 462 | 初始化批量页表和 TLB 回收上下文 |
| `tlb_finish_mmu` | — | `mm/mmu_gather.c` | 515 | 完成 TLB flush 和延迟对象释放 |
| `mmu_notifier_range_init` | `include/linux/mmu_notifier.h` | `include/linux/mmu_notifier.h` | 533 | 初始化页表失效通知的范围和事件 |
| `__alloc_pages_noprof` | — | `mm/page_alloc.c` | 5466 | 7.2-rc6 通用页分配后端 |
| `get_page_from_freelist` | — | `mm/page_alloc.c` | 3799 | 从 zonelist/伙伴系统取得页 |
| `__alloc_pages_slowpath` | — | `mm/page_alloc.c` | 4783 | 页分配慢路径 |
| `free_unref_folios` | — | `mm/page_alloc.c` | 3010 | 批量释放 folio |
| `kmem_cache_alloc_noprof` | — | `mm/slub.c` | 5001 | 从 slab cache 分配对象 |
| `__kmalloc_noprof` | — | `mm/slub.c` | 5431 | 通用 kmalloc 后端 |
| `kfree` | — | `mm/slub.c` | 6771 | 释放 kmalloc/slab 对象 |
| `__vmalloc_noprof` | — | `mm/vmalloc.c` | 4177 | 建立虚拟连续内核映射 |
| `filemap_fault` | — | `mm/filemap.c` | 3555 | 通用文件映射缺页处理 |
| `filemap_get_folio` | `include/linux/pagemap.h` | `include/linux/pagemap.h` | 802 | 查询页缓存 folio |
| `page_cache_ra_unbounded` | — | `mm/readahead.c` | 222 | 发起页缓存预读 |
| `try_to_free_pages` | — | `mm/vmscan.c` | 6769 | 直接内存回收入口 |
| `shrink_node` | — | `mm/vmscan.c` | 6239 | 节点级回收 |
| `shrink_lruvec` | — | `mm/vmscan.c` | 5969 | 扫描 LRU 集合 |
| `do_swap_page` | — | `mm/memory.c` | 4881 | 处理交换页 fault |
| `swapin_readahead` | `mm/swap.h` | `mm/swap_state.c` | 987 | 交换读预读 |
| `swap_read_folio` | `mm/swap.h` | `mm/page_io.c` | 452 | 提交交换读 I/O |
| `out_of_memory` | — | `mm/oom_kill.c` | 1103 | OOM 处理入口 |
| `compact_zone` | — | `mm/compaction.c` | 2561 | 对 zone 执行内存压缩 |
| `migrate_pages` | `include/linux/migrate.h` | `mm/migrate.c` | 2100 | 批量迁移页面 |
| `mem_cgroup_charge` | `include/linux/memcontrol.h` | `include/linux/memcontrol.h` | 657 | 对新页执行 memcg charge |
| `try_charge_memcg` | — | `mm/memcontrol.c` | 2645 | memcg charge 核心路径 |
| `page` | `include/linux/mm_types.h` | `include/linux/mm_types.h` | 80 | 物理页的基础描述对象 |
| `zone` | `include/linux/mmzone.h` | `include/linux/mmzone.h` | 979 | 内存域和伙伴系统状态 |
| `pglist_data` | `include/linux/mmzone.h` | `include/linux/mmzone.h` | 1478 | NUMA 节点内存状态 |
| `mm_struct` | `include/linux/mm_types.h` | `include/linux/mm_types.h` | 1175 | 进程地址空间 |
| `vm_area_struct` | `include/linux/mm_types.h` | `include/linux/mm_types.h` | 923 | 虚拟地址区间 |
| `vm_fault` | `include/linux/mm.h` | `include/linux/mm.h` | 753 | VMA fault 上下文 |
| `mmu_gather` | `include/asm-generic/tlb.h` | `include/asm-generic/tlb.h` | 325 | 批量页表拆除、TLB flush 与延迟释放上下文 |
| `mmu_notifier_range` | `include/linux/mmu_notifier.h` | `include/linux/mmu_notifier.h` | 304 | 向二级地址转换观察者描述失效区间 |
| `kmem_cache` | `mm/slab.h` | `mm/slab.h` | 240 | SLUB cache 描述对象 |
| `address_space` | `include/linux/fs.h` | `include/linux/fs.h` | 471 | 文件页缓存映射对象 |
| `lruvec` | `include/linux/mmzone.h` | `include/linux/mmzone.h` | 766 | 节点/memcg 的 LRU 集合 |
| `scan_control` | `mm/vmscan.c` | `mm/vmscan.c` | 76 | 一次回收扫描的控制参数 |
| `compact_control` | `mm/internal.h` | `mm/internal.h` | 823 | 一次内存压缩的控制状态 |
| `mem_cgroup` | `include/linux/memcontrol.h` | `include/linux/memcontrol.h` | 202 | 内存控制组状态 |

> `—` 表示 kernel-graph 本次只确认了实现位置，没有返回独立声明位置；未凭记忆补写头文件路径。

## 已有学习笔记

当前已有 [`page_zone_pglist_data.md`](page_zone_pglist_data.md)、[`mm_struct_vm_area_struct_vm_fault.md`](mm_struct_vm_area_struct_vm_fault.md)、[`kmem_cache_address_space_lruvec_scan_control.md`](kmem_cache_address_space_lruvec_scan_control.md) 和 [`compact_control_mem_cgroup.md`](compact_control_mem_cgroup.md) 四份结构体深度笔记；启动期内存主线另有 [`memblock_add.md`](memblock_add.md)、[`memblock_alloc_try_nid.md`](memblock_alloc_try_nid.md) 和 [`free_area_init.md`](free_area_init.md) 三份函数深度笔记；[`do_mmap.md`](do_mmap.md) 已覆盖 mmap/VMA 建立与 munmap 事务，[`mm_alloc.md`](mm_alloc.md) 已覆盖地址空间对象和根页表的创建/释放，[`dup_mm.md`](dup_mm.md) 已覆盖 fork 地址空间复制、COW 分工和 x86 根页表配置细节，[`dup_mmap.md`](dup_mmap.md) 已深入覆盖 VMA与普通页表逐级复制，[`do_user_addr_fault.md`](do_user_addr_fault.md) 已覆盖普通页表fault从x86入口到PTE分派，[`do_anonymous_page_do_fault_do_wp_page.md`](do_anonymous_page_do_fault_do_wp_page.md) 已继续覆盖匿名/文件首次填充和写保护COW，[`do_mprotect_pkey.md`](do_mprotect_pkey.md) 已覆盖VMA与现有页表权限修改。页表生命周期其余函数仍只列阅读路线，后续应由 `kernel-code-analyzer` 分阶段输出独立深度笔记，不在本指南复制逐行解释或调用链。

## 建议的第一轮深读清单

1. `__alloc_pages_noprof()`：先建立“约束 → 快路径 → 慢路径”的页分配框架。
2. `handle_mm_fault()`：建立“VMA → 页表层级 → fault 类型”的虚拟内存主线。
3. `filemap_fault()`：把缺页异常与文件页缓存连接起来。
4. `try_to_free_pages()`：理解内存压力怎样反向影响分配路径。
5. `kmem_cache_alloc_noprof()`：理解内核小对象怎样建立在页分配器之上。

这五个函数的函数级细节应分别使用 `kernel-code-analyzer` 产出独立笔记，本指南不内联展开。

## 页表生命周期专项深读清单

建议按以下五组逐篇分析，而不是一次把 `mm/memory.c` 全部摊开：

1. **根页表创建与销毁**：`mm_init()`、`mm_alloc_pgd()`、x86 `pgd_alloc()`、`mm_free_pgd()`、x86 `pgd_free()`。
2. **缺页填充普通页表**：`__handle_mm_fault()`、`__p4d_alloc()`、`__pud_alloc()`、`__pmd_alloc()`、`__pte_alloc()`、`handle_pte_fault()`。
3. **fork 复制与 COW 建立**：`dup_mmap()`、`copy_page_range()`、`copy_p4d_range()`、`copy_pud_range()`、`copy_pmd_range()`、`copy_pte_range()`。
4. **权限修改**：`do_mprotect_pkey()`、`mprotect_fixup()`、`change_protection()`、`change_pte_range()`。
5. **解除映射与最终销毁**：`unmap_region()`、`unmap_vmas()`、`__zap_vma_range()`、`free_pgtables()`、`free_pgd_range()`、`exit_mmap()`、`tlb_gather_mmu()`、`tlb_finish_mmu()`。

每组分析都应同时检查 `mm_struct`/VMA 锁、页表锁、`mmu_gather`、MMU notifier 和 TLB 的约束；否则容易只理解“表项改了什么”，却遗漏“其他 CPU 或设备何时停止使用旧翻译”。
