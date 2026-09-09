# 内存管理依赖图

> 初始骨架来自 kernel-graph MCP（Linux 7.2-rc6）`call_chain_down(depth=2)`；仅保留能表达内存管理主线的调用边，过滤断言、追踪、锁和简单内联辅助函数。

```text
handle_mm_fault
  ├── __handle_mm_fault（进入普通页表 fault 路径）
  │   └── handle_pte_fault（按 PTE 状态分派匿名页、COW、交换页或文件 fault）
  └── hugetlb_fault（进入 HugeTLB fault 路径）

__alloc_pages_noprof
  └── __alloc_frozen_pages_noprof（准备分配上下文并执行快慢路径）
      ├── get_page_from_freelist（按 zonelist 和水位从空闲区取页）
      ├── __alloc_pages_slowpath（快路径失败后的回收、压缩与 OOM 协调）
      ├── __memcg_kmem_charge_page（为内核页执行 memcg 记账）
      └── __free_frozen_pages（charge 失败时回滚已分配页面）

kmem_cache_alloc_noprof
  └── slab_alloc_node（SLUB 分配入口）
      └── ___slab_alloc（每 CPU 快路径无法满足时的慢路径）

filemap_fault
  ├── filemap_get_folio（从页缓存查询 folio）
  │   └── __filemap_get_folio（页缓存查询核心）
  ├── do_async_mmap_readahead（异步 mmap 预读）
  │   └── page_cache_async_ra（提交异步页缓存预读）
  └── do_sync_mmap_readahead（同步 mmap 预读）
      └── page_cache_sync_ra（提交同步页缓存预读）

try_to_free_pages
  └── do_try_to_free_pages（执行直接回收循环）
      └── shrink_zones（遍历允许回收的 zone）
          └── shrink_node（进入节点级回收）

free_area_init
  └── free_area_init_node（逐节点初始化物理内存管理对象）
      ├── calculate_node_totalpages（计算节点与各 zone 的容量）
      └── free_area_init_core（初始化 pgdat、zone 与 page 核心状态）
          ├── pgdat_init_internals（初始化节点回收与 LRU 状态）
          └── zone_init_internals（初始化 zone 容量、归属、锁与 PCP）

mm_core_init_early
  ├── free_area_init（初始化节点与 zone）
  └── memmap_init（初始化每 PFN 对应的 page 描述符）
      └── memmap_init_zone_range（按 zone 划分 memmap 初始化范围）
          └── memmap_init_range（初始化一段 PFN 范围）
              └── __init_single_page（初始化单个 page 描述符）

free_unref_folios
  ├── __free_pages_prepare（释放前校验并清理 page 身份）
  ├── folio_zone（定位 folio 所属 zone）
  └── free_frozen_page_commit（提交到 PCP 或伙伴系统）

kswapd
  └── balance_pgdat（后台平衡节点水位）
      └── kswapd_shrink_node（按 kswapd 目标回收节点）
          └── shrink_node（调用节点回收核心）

kernel_clone
  └── copy_process（创建新任务并复制进程资源）
      └── copy_mm（决定共享或复制地址空间）
          └── dup_mm（复制 mm_struct 与 VMA）
              ├── mm_init（初始化新地址空间核心状态）
              ├── dup_mmap（复制 VMA 并驱动页表复制）
              │   └── copy_page_range（普通页表复制总入口）
              │       ├── copy_hugetlb_page_range（复制 HugeTLB 页表）
              │       └── copy_p4d_range（复制或分配 P4D 下级范围）
              │           ├── p4d_alloc（取得或分配子 P4D）
              │           └── copy_pud_range（复制 PUD 范围）
              │               ├── pud_alloc（取得或分配子 PUD）
              │               ├── copy_huge_pud（复制 PUD huge 映射）
              │               └── copy_pmd_range（复制 PMD 范围）
              │                   ├── pmd_alloc（取得或分配子 PMD）
              │                   ├── copy_huge_pmd（复制 PMD huge 映射）
              │                   └── copy_pte_range（复制 PTE 范围）
              │                       ├── copy_nonpresent_pte（复制 swap、迁移、设备或 marker 项）
              │                       ├── copy_present_ptes（复制并批量处理 present PTE）
              │                       ├── swap_retry_table_alloc（锁外扩展 swap 重试计数表）
              │                       └── folio_prealloc（锁外预分配 pinned 页的子副本）
              └── mmput（失败时销毁半初始化地址空间）

ksys_mmap_pgoff
  └── vm_mmap_pgoff（通用内核 mmap 包装）
      └── do_mmap（选择地址并校验映射请求）
          └── mmap_region（建立映射区域）
              └── __mmap_region（合并或创建 VMA）
                  └── __mmap_new_vma（创建不能合并的新 VMA）
                      └── vm_area_alloc（分配并初始化 VMA 对象）

handle_page_fault
  └── do_user_addr_fault（处理用户地址范围的体系结构 fault）
      └── handle_mm_fault（通用 MM fault 入口）
          └── __handle_mm_fault（构造 vm_fault 并遍历页表）
              ├── p4d_alloc（取得或按需建立 P4D 层）
              ├── pud_alloc（取得或按需建立 PUD 层）
              ├── pmd_alloc（取得或按需建立 PMD 层）
              └── handle_pte_fault（按 PTE 状态分派）
                  ├── do_pte_missing（处理缺失 PTE）
                  │   ├── do_anonymous_page（建立匿名页映射）
                  │   │   ├── pte_alloc（按需建立 PTE 页表）
                  │   │   ├── alloc_anon_folio（分配并清零匿名 folio）
                  │   │   └── map_anon_folio_pte_pf（安装匿名 PTE、rmap 与统计）
                  │   └── do_fault（进入文件或共享后备 fault）
                  │       ├── do_read_fault（处理文件只读缺页）
                  │       ├── do_cow_fault（处理私有文件首次写 COW）
                  │       ├── do_shared_fault（处理共享后备写缺页）
                  │       └── pte_free（释放未使用的预分配 PTE 页表）
                  ├── do_swap_page（处理 non-present 软件表项与换入）
                  ├── do_uffd_rwp（处理 userfaultfd 读写保护）
                  ├── do_numa_page（处理 NUMA hinting fault）
                  └── do_wp_page（处理写保护与 COW）
                      ├── wp_pfn_shared（处理共享 PFN 或 DAX 映射）
                      ├── wp_page_shared（处理共享普通 folio 写入）
                      ├── wp_page_reuse（原地复用独占匿名 folio）
                      └── wp_page_copy（复制页面并事务式替换 PTE）

__do_sys_mprotect
  └── do_mprotect_pkey（校验用户权限请求并遍历 VMA）
      └── mprotect_fixup（调整 VMA 边界、flags 与权限模板）
          └── change_protection（选择 HugeTLB 或普通页表权限修改）
              ├── hugetlb_change_protection（修改 HugeTLB 映射权限）
              └── change_protection_range（从 PGD 开始遍历普通页表）
                  └── change_p4d_range（遍历 P4D 范围）
                      └── change_pud_range（遍历 PUD 或处理 PUD huge 映射）
                          └── change_pmd_range（遍历 PMD、处理或拆分 THP）
                              └── change_pte_range（修改叶子 PTE 与软件表项）
                                  ├── change_present_ptes（批量变换 present PTE）
                                  └── change_softleaf_pte（变换 migration、device 或 marker 软件叶子）

__pte_alloc
  ├── pte_alloc_one（架构分配并初始化 PTE 页表页）
  ├── pmd_install（在 PMD 锁下竞争安装 PTE 页表）
  └── pte_free（释放并发竞争中未安装的候选页）

do_exit
  └── exit_mm（任务退出地址空间）
      └── mmput（释放一个 mm 用户引用）
          └── __mmput（最后用户执行地址空间清理）
              └── exit_mmap（撤销页表、VMA 与 Maple Tree）

__kmem_cache_create
  └── __kmem_cache_create_args（校验参数、尝试 alias 并创建对象 cache）
      └── create_cache（分配 cache 描述符并进入 SLUB 初始化）
          └── do_kmem_cache_create（计算对象布局并建立每 CPU/节点状态）

kmem_cache_alloc_noprof
  └── slab_alloc_node（执行 SLUB 对象分配快慢路径）
      └── ___slab_alloc（每 CPU sheaf 未命中后的慢路径）
          └── new_slab（向页分配器补充新 slab）

filemap_fault
  └── __filemap_get_folio（查询或创建 fault 所需 page-cache folio）
      └── __filemap_get_folio_mpol（应用内存策略并创建 folio）
          └── filemap_add_folio（把 folio 插入 address_space）
              └── folio_add_lru（批量加入所属 lruvec）

generic_file_read_iter
  └── filemap_read（通用 buffered read）
      └── filemap_get_pages（取得本轮读取所需 folio）
          └── filemap_create_folio（创建缺失的 page-cache folio）
              └── filemap_add_folio（插入 address_space 并加入 LRU）

try_to_free_pages
  └── do_try_to_free_pages（执行直接回收循环）
      └── shrink_zones（遍历允许回收的节点与 zone）
          └── shrink_node（执行节点级回收）
              ├── prepare_scan_control（根据 lruvec 反馈准备本轮策略）
              └── shrink_node_memcgs（遍历节点上的 memcg 回收域）
                  └── shrink_lruvec（扫描一个 lruvec）
                      └── shrink_list（按 LRU 类型执行 aging 或回收）
                          └── shrink_inactive_list（隔离并回收 inactive folio）

__alloc_pages_slowpath
  └── __alloc_pages_direct_compact（页分配慢路径尝试直接压缩）
      └── try_to_compact_pages（遍历允许的 zone 尝试压缩）
          └── compact_zone_order（为指定 order 构造压缩上下文）
              └── compact_zone（执行 zone 内双向扫描与页面迁移）

kcompactd
  └── kcompactd_do_work（处理节点后台压缩请求）
      └── compact_zone（执行 zone 内双向扫描与页面迁移）

sysctl_compaction_handler
  └── compact_nodes（触发所有节点的手工压缩）
      └── compact_node（为节点构造全 zone 压缩上下文）
          └── compact_zone（执行 zone 内双向扫描与页面迁移）

filemap_add_folio
  └── mem_cgroup_charge（为新 folio 选择并记账 memcg）
      └── __mem_cgroup_charge（进入通用 charge 后端）
          └── charge_memcg（取得 objcg 并提交 charge）
              └── try_charge_memcg（执行层级限额检查、回收与 OOM 决策）
                  └── try_to_free_mem_cgroup_pages（仅回收目标 memcg）

memory_reclaim
  └── user_proactive_reclaim（解析 memory.reclaim 并发起主动回收）
      └── try_to_free_mem_cgroup_pages（仅回收目标 memcg）

memblock_add
  └── memblock_add_range（去重、插入并合并可用物理区间）

memblock_alloc_try_nid
  └── memblock_alloc_internal（收紧可访问上界并处理最低地址回退）
      └── memblock_alloc_range_nid（按地址窗口和 NUMA 偏好查找并预留）
          ├── memblock_find_in_range_node（从 memory 减 reserved 的空洞中选择地址）
          └── memblock_prep_allocation（执行 kmemleak 标注与机密虚拟机内存接受）

free_area_init
  ├── arch_zone_limits_init（取得体系结构 zone 最大 PFN 边界）
  ├── find_zone_movable_pfns_for_nodes（计算每节点 ZONE_MOVABLE 起点）
  └── free_area_init_node（初始化单个 NUMA 节点）
      ├── calculate_node_totalpages（计算各 zone 的跨度和实存页）
      └── free_area_init_core（初始化 pgdat、zone 和伙伴系统容器）
          ├── zone_init_internals（初始化 zone 内部状态）
          └── setup_usemap（分配 pageblock flags bitmap）

do_munmap
  └── do_vmi_munmap（校验解除映射区间并进入 Maple Tree-aware 拆除路径）

mm_alloc
  └── mm_init（构造完整地址空间基础设施并协调失败回滚）

mm_init
  ├── mm_alloc_pgd（通过架构接口建立根页表）
  └── mm_free_pgd（PGD 创建后的初始化失败回滚）

mm_alloc_pgd
  └── pgd_alloc（架构相关根页表分配）

mm_free_pgd
  └── pgd_free（架构相关根页表析构与释放）

pgd_alloc
  ├── _pgd_alloc（分配 x86 根页表物理页）
  ├── preallocate_pmds（PAE/PTI 配置下预分配 PMD）
  ├── paravirt_pgd_alloc（通知半虚拟化后端）
  ├── pgd_ctor（复制内核项并登记 pgd_list）
  ├── pgd_prepopulate_pmd（挂接 x86 PAE 预分配 PMD）
  └── pgd_prepopulate_user_pmd（挂接 PTI 用户视图 PMD）

pgd_free
  ├── pgd_mop_up_pmds（拆除构造期预置 PMD）
  ├── pgd_dtor（从 pgd_list 注销根页表）
  ├── paravirt_pgd_free（通知半虚拟化后端释放）
  └── _pgd_free（析构并释放根页表物理页）
```
