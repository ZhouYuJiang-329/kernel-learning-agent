# Linux 内存管理概念地图

> 模块：`mm`  
> 当前主线：理解 Linux 如何发现、描述、分配、回收和整理物理内存。

## 当前概念清单

| 概念 | 状态 | 优先级 | 关联函数/结构体 | Primer |
|---|---|---:|---|---|
| Linux 物理内存管理分层模型 | linked | P0 | `memblock_add`, `free_area_init`, `page`, `zone`, `pglist_data` | [physical_memory_management.md](physical_memory_management.md) |
| 物理地址、页帧与 PFN | primer | P0 | `page`, `memmap_init` | [physical_memory_management.md](physical_memory_management.md) |
| NUMA node 与 zone | linked | P0 | `pglist_data`, `zone`, `free_area_init` | [physical_memory_management.md](physical_memory_management.md) |
| memblock 到 buddy 的启动交接 | linked | P0 | `memblock_add`, `memblock_alloc_try_nid`, `free_area_init` | [physical_memory_management.md](physical_memory_management.md) |
| buddy order、pageblock 与碎片 | linked | P0 | `zone`, `compact_control` | [physical_memory_management.md](physical_memory_management.md) |
| `spanned/present/managed` 三种页数 | linked | P0 | `zone`, `pglist_data`, `free_area_init` | [physical_memory_management.md](physical_memory_management.md) |
| per-CPU pageset（PCP） | debt | P1 | `zone`, `free_unref_folios`, `get_page_from_freelist` | 待补 |
| 水位、zonelist 与 GFP 分配约束 | debt | P1 | `zone`, `get_page_from_freelist`, `__alloc_pages_slowpath` | 待补 |
| 页回收、迁移与压缩的边界 | linked | P1 | `lruvec`, `scan_control`, `compact_control` | [physical_memory_management.md](physical_memory_management.md) |
| 页所有权、引用计数与 mapcount | debt | P1 | `page`, `folio` | 待补 |
| Sparse memory、memmap 与物理空洞 | primer | P2 | `memmap_init`, `page` | [physical_memory_management.md](physical_memory_management.md) |
| HugeTLB、THP、CMA、热插拔 | deferred | P2 | 尚未进入当前基础主线 | 待后续专项 |

## 推荐顺序

```text
物理地址 / PFN / 页帧
  → node / zone / struct page
  → memblock 启动期地图
  → buddy order / pageblock
  → PCP / 水位 / zonelist
  → 回收 / 迁移 / 压缩
  → NUMA、memcg、THP 等策略层
```

## 状态说明

- `primer`：已有继续读代码所需的最小解释。
- `linked`：概念已与两项以上分析过的函数或结构体建立联系。
- `debt`：当前源码主线会遇到，但尚未系统展开。
- `deferred`：当前阶段可以先放后。
