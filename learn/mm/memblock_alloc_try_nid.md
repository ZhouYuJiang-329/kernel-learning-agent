# memblock_alloc_try_nid() 详解

> 源码位置：`mm/memblock.c:1851`（Linux 7.2-rc6）  
> 核心职责：在 slab 尚不可用的启动阶段，按大小、对齐、地址窗口和 NUMA 偏好寻找物理内存，登记为 reserved，转换成虚拟地址并清零后返回。

## 一、大白话总览

### （a）为什么要设计它

伙伴系统和 slab 建立之前，页表、NUMA 数据、per-CPU 区、KASAN shadow 等设施已经需要内存。`memblock_alloc_try_nid()` 是这个“先有鸡还是先有蛋”阶段的通用零填充分配接口。

如果没有它，早期初始化只能使用静态大数组，无法依据真实机器内存规模动态创建元数据。

### （b）如果让我自己设计

**一句话降级：**从可用清单中挑一段尚未占用、满足约束的连续地址，并贴上“已占用”标签。

```text
memblock.memory                  memblock.reserved
机器存在的范围                  已经占用的范围
       └────────── 求差集 ───────────┘
                       │ size / align / [min,max) / nid
                       ▼
                 找到并 reserve
                       ▼
              phys_to_virt + 清零
```

核心数据对象：

| 对象 | 角色 |
|---|---|
| `size` | 申请长度 |
| `align` | 起始物理地址必须满足的对齐 |
| `min_addr/max_addr` | 搜索窗口 |
| `nid` | 优先选择的 NUMA 节点，不是绝对要求 |
| `memblock.memory` | 候选空间目录 |
| `memblock.reserved` | 排除空间和成功后的占用账本 |
| `current_limit` | 当前启动阶段 CPU 能安全访问的物理上界 |

真实复杂度来自 NUMA fallback、top-down/bottom-up 策略、镜像内存偏好、未接受的机密虚拟机内存、kmemleak 标注、低地址约束和 slab 生命周期边界。

自己实现时应：先收紧地址上界；在指定窗口和节点内找对齐空洞；找到后原子式地记入 reserved；节点失败时按策略跨节点重试；镜像偏好失败时降级；接受内存并做调试标注；转换虚拟地址并清零。任何查找成功但 reserve 失败的结果都不能返回。

阅读 checklist：

- `nid` 是偏好还是硬约束？
- `min_addr` 为什么失败后可以降到 0？
- 为什么查找到地址后还必须 reserve？
- 为什么返回虚拟地址而底层查找使用物理地址？
- 为什么成功内存必须清零？
- slab 已可用后误调用怎样处理？

### （c）它是怎么设计的

外层函数负责 API 语义：调试、调用内部选择器、清零、返回指针。`memblock_alloc_internal()` 负责地址边界和低地址 fallback；`memblock_alloc_range_nid()` 负责找空洞、NUMA fallback、镜像降级和 reservation。

### （d）主要情况

| 条件 | 动作 | 原因 |
|---|---|---|
| `max_addr > current_limit` | 截到 `current_limit` | 当前阶段更高物理地址可能不可映射 |
| 首次查找成功且 reserve 成功 | 准备内存并返回 | 正常路径 |
| 首次失败且 `min_addr != 0` | 用 0 作为下界重试 | 首选低限不是硬失败条件 |
| 指定 nid 失败且 `exact_nid == false` | 跨节点搜索 | `try_nid` 表示节点偏好 |
| mirrored 搜索失败 | 去掉 MIRROR 后重试 | 镜像是优先级，可降级 |
| `align == 0` | 打印栈并改用 cache-line 对齐 | 太早期不能依赖完整 WARN 路径 |
| slab 已可用 | WARN，并临时退到 `kzalloc_node(GFP_NOWAIT)` | 捕获错误生命周期用法 |
| 所有尝试失败 | 返回 `NULL` | 非 panic 版本允许调用者处理失败 |

## 二、控制流骨架

```text
memblock_alloc_try_nid(size, align, min, max, nid)
│
├─ 输出调试参数和调用点
├─ ptr = memblock_alloc_internal(..., exact_nid=false)
│   ├─ [max > current_limit] → 收紧 max
│   ├─ memblock_alloc_range_nid(...)
│   │   ├─ [slab 已可用] → WARN + kzalloc_node → return 物理地址/0
│   │   ├─ [align == 0] → dump_stack + 使用 SMP_CACHE_BYTES
│   │   ├─ again：在指定 nid 内找空洞并 reserve
│   │   │   └─ [成功] → goto done
│   │   ├─ [nid 有效且不是 exact] → 跨节点找空洞并 reserve
│   │   │   └─ [成功] → goto done
│   │   ├─ [当前要求 MIRROR] → 清 MIRROR、告警、goto again
│   │   ├─ 所有路径失败 → return 0
│   │   └─ done：kmemleak/accept_memory → return 物理地址
│   ├─ [失败且 min != 0] → 下界改 0，再试一次
│   ├─ [仍失败] → return NULL
│   └─ phys_to_virt(alloc) → return 虚拟地址
├─ [ptr != NULL] → memset(ptr, 0, size)
└─ return ptr
```

## 三、宏观地位

```text
start_kernel / setup_arch / mm_core_init
                  │
      页表、KASAN、per-CPU、node 元数据等早期消费者
                  │
                  ▼
       memblock_alloc* 包装接口
                  │
                  ▼
        [memblock_alloc_try_nid()]
                  │
        ┌─────────┴─────────┐
        ▼                   ▼
memblock.memory 找候选   memblock.reserved 排除/记账
                  │
                  ▼
        返回已清零的线性映射地址
```

典型触发场景：

- `setup_per_cpu_areas()` 经 `pcpu_embed_first_chunk()` 分配启动期 per-CPU 元数据。
- `mm_core_init()` 中 page extension、KFENCE 或 stack depot 等组件申请早期内存。
- 体系结构建立早期页表或 KASAN shadow 页时直接调用。
- `free_area_init_core()` 经 `setup_usemap()`、`memblock_alloc_node()` 为 zone pageblock bitmap 分配空间。

## 四、完整调用链

由于它是通用启动期分配 API，调用入口很多。代表路径为：

```text
start_kernel()
  └── setup_per_cpu_areas()
      └── pcpu_embed_first_chunk()
          └── pcpu_fc_alloc()
              └── memblock_alloc_from()
                  └── memblock_alloc_try_nid()        // mm/memblock.c:1851

start_kernel()
  └── mm_core_init_early()
      └── free_area_init()
          └── free_area_init_node()
              └── free_area_init_core()
                  └── setup_usemap()
                      └── memblock_alloc_node()
                          └── memblock_alloc_try_nid()
```

直接调用者还包括 `memblock_alloc()`、`memblock_alloc_from()`、`memblock_alloc_low()`、`memblock_alloc_node()`，以及多种体系结构的早期页表/KASAN helper。

向下：

```text
memblock_alloc_try_nid()
  ├── memblock_dbg()
  ├── memblock_alloc_internal()
  │   ├── memblock_alloc_range_nid()
  │   │   ├── choose_memblock_flags()
  │   │   ├── memblock_find_in_range_node()
  │   │   ├── __memblock_reserve() / memblock_reserve_kern()
  │   │   └── memblock_prep_allocation()
  │   └── phys_to_virt()
  └── memset()
```

## 五、逐行详解：外层接口

```c
void * __init memblock_alloc_try_nid(
        phys_addr_t size, phys_addr_t align,
        phys_addr_t min_addr, phys_addr_t max_addr,
        int nid)
{
    void *ptr;

    memblock_dbg(/* 打印 size、align、nid、窗口和调用点 */);
    ptr = memblock_alloc_internal(size, align,
                                  min_addr, max_addr, nid, false);
    if (ptr)
        memset(ptr, 0, size);

    return ptr;
}
```

- 返回 `void *`，因为早期内存通常已处于直接映射区；底层仍以 `phys_addr_t` 做区间运算。
- `exact_nid=false` 是函数名中 `try_nid` 的精髓：先尝试本节点，必要时允许 fallback。
- 只有成功时清零，向调用者提供类似 `kzalloc` 的确定初值语义。
- 此接口失败返回 `NULL`；需要不可失败语义的调用者应使用对应 `*_or_panic` 包装。

## 六、memblock_alloc_internal()

```c
if (max_addr > memblock.current_limit)
    max_addr = memblock.current_limit;
```

`memory` 中登记了某段 RAM，不代表当前页表已经能访问它。`current_limit` 把“物理存在”与“当前可访问”分开。

```c
alloc = memblock_alloc_range_nid(...);
if (!alloc && min_addr)
    alloc = memblock_alloc_range_nid(size, align, 0, max_addr,
                                     nid, exact_nid);
```

第一次尊重调用者希望的最低地址；失败后放宽到 0。这里放宽的是地址窗口，不是 `max_addr`、大小或对齐。

```c
if (!alloc)
    return NULL;
return phys_to_virt(alloc);
```

物理地址 0 同时作为失败哨兵，因此查找 helper 会避开第一个物理页。

## 七、memblock_alloc_range_nid()

### 7.1 生命周期防御

`WARN_ON_ONCE(slab_is_available())` 表示正常情况下 memblock 分配不应晚于 slab。由于 memblock 元数据可能已被释放，代码退到 `kzalloc_node(size, GFP_NOWAIT, nid)`，再转换为物理地址，以便暴露错误又尽量维持运行。

### 7.2 查找与 reserve 必须成对

```text
memblock_find_in_range_node() 只选出候选地址
__memblock_reserve()          才把地址加入 reserved
```

只有 `found != 0` 且 reserve 返回 0 才能 `goto done`。否则候选空间并未成为调用者独占资源。

### 7.3 NUMA fallback

第一次用调用者提供的 `nid`。若节点有效且 `exact_nid == false`，第二次用 `NUMA_NO_NODE` 在所有节点搜索。跨节点 reserve 使用 `memblock_reserve_kern()`。

### 7.4 镜像内存降级

`choose_memblock_flags()` 可能优先要求 `MEMBLOCK_MIRROR`。镜像范围不足时清除此 flag 并 `goto again`，同时输出限频警告。这样优先获得高可靠内存，但不会因此让启动失败。

### 7.5 分配后准备

`memblock_prep_allocation()`：

- 按参数向 kmemleak 登记物理分配；部分高频早期调用可跳过。
- 调用 `accept_memory()`，让 TDX、SEV-SNP 等机密虚拟机中的未接受内存先变成来宾可用状态。

## 八、空洞搜索策略

`memblock_find_in_range_node()` 先处理三个边界：

1. 特殊 `end` 值替换为 `memblock.current_limit`。
2. `start` 至少为 `PAGE_SIZE`，避开物理页 0，使地址 0可作为失败值。
3. 保证 `end >= start`。

随后根据 `memblock.bottom_up` 选择：

```text
bottom_up == true  → __memblock_find_range_bottom_up()
bottom_up == false → __memblock_find_range_top_down()
```

两者都搜索 `memory - reserved` 的对齐空洞，只是优先低地址或高地址不同。

## 九、关键不变量与失败语义

- 成功返回的区间必须完全位于 `memblock.memory` 中。
- 成功区间不得与 `memblock.reserved` 重叠，并已加入 reserved。
- 返回指针对应的 `size` 字节已经清零。
- 返回地址满足 `align`；0 对齐会被修正而不是静默使用。
- NUMA nid 是偏好；只有底层 `exact_nid=true` 的其他接口才禁止跨节点。
- `NULL` 表示所有窗口、节点与 flag 降级尝试均失败。

## 十、为什么不能用更简单方案

1. **不能直接 bump pointer：**固件地图有洞，内核镜像、initrd、ACPI 等区间也已预留。
2. **不能只查 memory：**不扣除 reserved 会让两个早期消费者得到同一物理页。
3. **不能只在指定 nid 失败：**启动成功通常比早期 NUMA 局部性更重要。
4. **不能在 slab 可用后继续正常使用：**`memblock_free_all()` 后内部区间数据可能已销毁。
5. **不能省略清零：**大量早期元数据依赖零初始化表示空链表之外的默认状态和零计数。

## 十一、与 memblock_add()/free_area_init() 的关系

`memblock_add()` 先为它建立候选 `memory` 区间；该函数把选中部分写入 `reserved`。`free_area_init()` 随后读取同一份 memory/NUMA 地图建立 node 和 zone；其内部还用本函数为 pageblock usemap 分配启动期内存。最终 memblock 把未 reserved 的页面交给伙伴系统时，这些早期分配不会被误释放。
