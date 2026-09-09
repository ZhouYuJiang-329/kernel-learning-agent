# 内存管理知识节点

| 名称 | 类型 | 状态 | 置信度 | 笔记 | 内部文档 | 更新日期 |
|---|---|---|---:|---|---|---|
| memblock_add | function | mastered | 85 | learn/mm/memblock_add.md | - | 2026-09-07 |
| memblock_alloc_try_nid | function | mastered | 85 | learn/mm/memblock_alloc_try_nid.md | - | 2026-09-07 |
| do_user_addr_fault | function | mastered | 85 | learn/mm/do_user_addr_fault.md | - | 2026-09-08 |
| handle_mm_fault | function | mastered | 85 | learn/mm/do_user_addr_fault.md | - | 2026-09-08 |
| __handle_mm_fault | function | mastered | 85 | learn/mm/do_user_addr_fault.md | - | 2026-09-08 |
| __pte_alloc | function | mastered | 85 | learn/mm/do_user_addr_fault.md | - | 2026-09-08 |
| handle_pte_fault | function | mastered | 85 | learn/mm/do_user_addr_fault.md | - | 2026-09-08 |
| do_anonymous_page | function | mastered | 85 | learn/mm/do_anonymous_page_do_fault_do_wp_page.md | - | 2026-09-08 |
| do_fault | function | mastered | 85 | learn/mm/do_anonymous_page_do_fault_do_wp_page.md | - | 2026-09-08 |
| do_wp_page | function | mastered | 85 | learn/mm/do_anonymous_page_do_fault_do_wp_page.md | - | 2026-09-08 |
| hugetlb_fault | function | unknown | 0 | - | - | 2026-09-07 |
| __alloc_pages_noprof | function | unknown | 0 | learn/mm/mm_read_guide.md | - | 2026-09-07 |
| __alloc_frozen_pages_noprof | function | unknown | 0 | - | - | 2026-09-07 |
| get_page_from_freelist | function | unknown | 0 | - | - | 2026-09-07 |
| __alloc_pages_slowpath | function | unknown | 0 | - | - | 2026-09-07 |
| __memcg_kmem_charge_page | function | unknown | 0 | - | - | 2026-09-07 |
| __free_frozen_pages | function | unknown | 0 | - | - | 2026-09-07 |
| kmem_cache_alloc_noprof | function | unknown | 0 | learn/mm/mm_read_guide.md | - | 2026-09-07 |
| slab_alloc_node | function | unknown | 0 | - | - | 2026-09-07 |
| ___slab_alloc | function | unknown | 0 | - | - | 2026-09-07 |
| filemap_fault | function | unknown | 0 | learn/mm/mm_read_guide.md | - | 2026-09-07 |
| filemap_get_folio | function | unknown | 0 | - | - | 2026-09-07 |
| __filemap_get_folio | function | unknown | 0 | - | - | 2026-09-07 |
| do_async_mmap_readahead | function | unknown | 0 | - | - | 2026-09-07 |
| page_cache_async_ra | function | unknown | 0 | - | - | 2026-09-07 |
| do_sync_mmap_readahead | function | unknown | 0 | - | - | 2026-09-07 |
| page_cache_sync_ra | function | unknown | 0 | - | - | 2026-09-07 |
| try_to_free_pages | function | unknown | 0 | learn/mm/mm_read_guide.md | - | 2026-09-07 |
| do_try_to_free_pages | function | unknown | 0 | - | - | 2026-09-07 |
| shrink_zones | function | unknown | 0 | - | - | 2026-09-07 |

## 用户虚拟内存数据结构

| 名称 | 类型 | 状态 | 置信度 | 笔记 | 内部文档 | 更新日期 |
|---|---|---|---:|---|---|---|
| mm_struct | struct | mastered | 85 | learn/mm/mm_struct_vm_area_struct_vm_fault.md | - | 2026-09-07 |
| vm_area_struct | struct | mastered | 85 | learn/mm/mm_struct_vm_area_struct_vm_fault.md | - | 2026-09-07 |
| vm_fault | struct | mastered | 85 | learn/mm/mm_struct_vm_area_struct_vm_fault.md | - | 2026-09-07 |
| do_mmap | function | mastered | 85 | learn/mm/do_mmap.md | - | 2026-09-08 |
| mmap_region | function | mastered | 85 | learn/mm/do_mmap.md | - | 2026-09-08 |
| do_munmap | function | mastered | 85 | learn/mm/do_mmap.md | - | 2026-09-08 |
| mm_alloc | function | mastered | 85 | learn/mm/mm_alloc.md | - | 2026-09-08 |
| mm_init | function | mastered | 85 | learn/mm/mm_alloc.md | - | 2026-09-08 |
| mm_alloc_pgd | function | mastered | 85 | learn/mm/mm_alloc.md | - | 2026-09-08 |
| mm_free_pgd | function | mastered | 85 | learn/mm/mm_alloc.md | - | 2026-09-08 |
| dup_mm | function | mastered | 85 | learn/mm/dup_mm.md | - | 2026-09-08 |
| dup_mmap | function | mastered | 85 | learn/mm/dup_mmap.md | - | 2026-09-09 |
| copy_page_range | function | mastered | 85 | learn/mm/dup_mmap.md | - | 2026-09-09 |
| copy_p4d_range | function | mastered | 85 | learn/mm/dup_mmap.md | - | 2026-09-09 |
| copy_pud_range | function | mastered | 85 | learn/mm/dup_mmap.md | - | 2026-09-09 |
| copy_pmd_range | function | mastered | 85 | learn/mm/dup_mmap.md | - | 2026-09-09 |
| copy_pte_range | function | mastered | 85 | learn/mm/dup_mmap.md | - | 2026-09-09 |
| do_mprotect_pkey | function | mastered | 85 | learn/mm/do_mprotect_pkey.md | - | 2026-09-09 |
| mprotect_fixup | function | mastered | 85 | learn/mm/do_mprotect_pkey.md | - | 2026-09-09 |
| change_protection | function | mastered | 85 | learn/mm/do_mprotect_pkey.md | - | 2026-09-09 |
| change_pte_range | function | mastered | 85 | learn/mm/do_mprotect_pkey.md | - | 2026-09-09 |
| pgd_alloc | function | mastered | 85 | learn/mm/dup_mm.md | - | 2026-09-08 |
| pgd_free | function | mastered | 85 | learn/mm/dup_mm.md | - | 2026-09-08 |

## 缓存与回收数据结构

| 名称 | 类型 | 状态 | 置信度 | 笔记 | 内部文档 | 更新日期 |
|---|---|---|---:|---|---|---|
| kmem_cache | struct | mastered | 85 | learn/mm/kmem_cache_address_space_lruvec_scan_control.md | - | 2026-09-07 |
| address_space | struct | mastered | 85 | learn/mm/kmem_cache_address_space_lruvec_scan_control.md | - | 2026-09-07 |
| lruvec | struct | mastered | 85 | learn/mm/kmem_cache_address_space_lruvec_scan_control.md | - | 2026-09-07 |
| scan_control | struct | mastered | 85 | learn/mm/kmem_cache_address_space_lruvec_scan_control.md | - | 2026-09-07 |

## 压缩与资源控制数据结构

| 名称 | 类型 | 状态 | 置信度 | 笔记 | 内部文档 | 更新日期 |
|---|---|---|---:|---|---|---|
| compact_control | struct | mastered | 85 | learn/mm/compact_control_mem_cgroup.md | - | 2026-09-07 |
| mem_cgroup | struct | mastered | 85 | learn/mm/compact_control_mem_cgroup.md | - | 2026-09-07 |

## 物理内存数据结构

| 名称 | 类型 | 状态 | 置信度 | 笔记 | 内部文档 | 更新日期 |
|---|---|---|---:|---|---|---|
| page | struct | mastered | 85 | learn/mm/page_zone_pglist_data.md | - | 2026-09-07 |
| zone | struct | mastered | 85 | learn/mm/page_zone_pglist_data.md | - | 2026-09-07 |
| pglist_data | struct | mastered | 85 | learn/mm/page_zone_pglist_data.md | - | 2026-09-07 |
| free_area_init | function | mastered | 85 | learn/mm/free_area_init.md | - | 2026-09-07 |
| free_area_init_node | function | unknown | 0 | - | - | 2026-09-07 |
| calculate_node_totalpages | function | unknown | 0 | - | - | 2026-09-07 |
| free_area_init_core | function | unknown | 0 | - | - | 2026-09-07 |
| pgdat_init_internals | function | unknown | 0 | - | - | 2026-09-07 |
| zone_init_internals | function | unknown | 0 | - | - | 2026-09-07 |
| __init_single_page | function | unknown | 0 | - | - | 2026-09-07 |
| free_unref_folios | function | unknown | 0 | - | - | 2026-09-07 |
| __free_pages_prepare | function | unknown | 0 | - | - | 2026-09-07 |
| folio_zone | function | unknown | 0 | - | - | 2026-09-07 |
| free_frozen_page_commit | function | unknown | 0 | - | - | 2026-09-07 |
| shrink_node | function | unknown | 0 | - | - | 2026-09-07 |
| shrink_lruvec | function | unknown | 0 | - | - | 2026-09-07 |
| kswapd | function | unknown | 0 | - | - | 2026-09-07 |
| balance_pgdat | function | unknown | 0 | - | - | 2026-09-07 |
| kswapd_shrink_node | function | unknown | 0 | - | - | 2026-09-07 |
| mm_core_init_early | function | unknown | 0 | - | - | 2026-09-07 |
| memmap_init | function | unknown | 0 | - | - | 2026-09-07 |
| memmap_init_zone_range | function | unknown | 0 | - | - | 2026-09-07 |
| memmap_init_range | function | unknown | 0 | - | - | 2026-09-07 |
