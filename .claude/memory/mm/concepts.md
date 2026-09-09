# 内存管理概念状态

| concept | status | confidence | note | linked_code |
|---|---|---:|---|---|
| Linux 物理内存管理分层模型 | linked | 75 | 已建立固件/memblock、node/zone、page/folio、buddy/PCP、回收/压缩的统一模型 | `memblock_add`, `free_area_init`, `page`, `zone`, `pglist_data` |
| 物理地址、页帧与 PFN | primer | 55 | 能区分物理地址空间、真实 RAM、页帧和 PFN；尚未展开体系结构页表差异 | `page`, `memmap_init` |
| NUMA node 与 zone | linked | 75 | 已理解 node 表达距离、zone 表达能力/用途约束 | `pglist_data`, `zone`, `free_area_init` |
| memblock 到 buddy 的启动交接 | linked | 75 | 已区分 memory 登记、reserved 分配、zone 初始化和后续 buddy 接管 | `memblock_add`, `memblock_alloc_try_nid`, `free_area_init` |
| buddy order、pageblock 与碎片 | linked | 70 | 已有 order/拆分合并/pageblock 迁移类型最小模型，并关联 compaction | `zone`, `compact_control` |
| spanned/present/managed 三种页数 | linked | 75 | 能解释地址跨度、真实 RAM 和伙伴系统可管理页的差别 | `free_area_init`, `zone`, `pglist_data` |
| per-CPU pageset（PCP） | debt | 25 | 仅有本地缓存和批量回灌模型，尚未分析 high/batch/drain | `zone`, `free_unref_folios`, `get_page_from_freelist` |
| 水位、zonelist 与 GFP 分配约束 | debt | 20 | 已知其决定候选 zone、回退和慢路径，尚未建立完整决策模型 | `get_page_from_freelist`, `__alloc_pages_slowpath` |
| 页回收、迁移与压缩的边界 | linked | 70 | 已区分容量、物理位置与连续性三个目标 | `lruvec`, `scan_control`, `compact_control` |
| 页所有权、引用计数与 mapcount | debt | 25 | 知道释放前必须结束引用/映射/I/O，未系统分析字段不变量 | `page`, `folio` |
| Sparse memory、memmap 与物理空洞 | primer | 50 | 已理解 PFN 可无 RAM、memmap 为页帧建描述符；具体 sparse section 待补 | `memmap_init`, `page` |
| HugeTLB、THP、CMA、热插拔 | deferred | 20 | 当前基础页主线暂不展开 | - |
