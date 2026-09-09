# Linux 如何管理物理内存

> 定位：建立 Linux 物理内存管理的整体心智模型，解释一块 RAM 如何从固件描述，变成内核能分配、回收和迁移的页。  
> 当前掌握目标：读懂 memblock、`struct page`、NUMA node、zone、伙伴系统、PCP、回收与压缩代码时，知道每一层在管理什么。

---

## 一、先建立总图

Linux 不把物理内存看成一整块可以随意切割的字节数组。它先把物理地址空间切成固定大小的页帧，再按硬件拓扑、寻址能力和用途分层组织。

```text
固件 / 设备树 / E820：机器有哪些物理地址段
                       │
                       ▼
memblock：启动早期的 memory / reserved 区间账本
                       │
                       ▼
NUMA node：内存靠近哪个 CPU / 控制器
                       │
                       ▼
zone：哪些设备或内核路径能够使用这些页
                       │
                       ▼
struct page / folio：每个页帧及一组页帧的软件身份
                       │
                       ▼
buddy + PCP：空闲页的正式分配与释放
                       │
          ┌────────────┴────────────┐
          ▼                         ▼
LRU / reclaim：腾出页面       migration / compaction：整理连续空间
```

这里至少存在四种不同视角：

| 视角 | 关心的问题 | 主要对象 |
|---|---|---|
| 地址视角 | 某个物理地址是否真的有 RAM | memblock region、PFN |
| 拓扑视角 | 这块 RAM 属于哪个节点、离哪个 CPU 更近 | `pglist_data` |
| 分配视角 | 这页能否满足 DMA、NUMA、连续性和水位要求 | `zone`、zonelist、buddy、PCP |
| 使用视角 | 页面当前空闲、匿名、文件缓存、slab，还是正在迁移 | `struct page`、folio、LRU |

一个对象不能替代所有视角，这正是 Linux 物理内存代码看起来结构很多的根本原因。

## 二、物理地址不等于 RAM

CPU 和设备看到的是物理地址空间，但物理地址空间中并非每个地址都连接着普通 RAM。它还可能包含：

- 固件和 ACPI 表。
- 内核镜像、initrd、页表等已占用 RAM。
- PCI BAR、APIC 等 MMIO 窗口。
- 地址空洞。
- 不可用、热插拔、镜像或尚未接受的内存。

因此要区分：

```text
物理地址空间：地址解码的全集
RAM：其中真正由内存条或内存设备提供的区间
可用 RAM：RAM 扣除固件保留和平台限制
可分配页：可用 RAM 中已经交给正式页分配器的部分
```

常见误解是看到最大物理地址为 16 GiB，就认为系统一定有 16 GiB 连续 RAM。中间可能有洞，所以“最高地址”与“总容量”不是一回事。

## 三、页帧、PAGE_SIZE 与 PFN

### 3.1 为什么按页管理

如果按字节记录每个物理地址的状态，元数据和操作成本都会不可接受。CPU 页表、TLB 和内核页分配器共同选择固定粒度：页。

```text
物理页帧：一段 PAGE_SIZE 大小、PAGE_SIZE 对齐的物理内存
PFN：Page Frame Number，物理页帧编号
```

概念换算：

```text
PFN = physical_address >> PAGE_SHIFT
physical_address = PFN << PAGE_SHIFT
```

在常见 4 KiB 基础页系统上，`PAGE_SHIFT` 为 12；但学习内核时不应把 4 KiB 写死，因为体系结构和配置可能不同。

### 3.2 PFN 的价值

PFN 把稀疏的大物理地址转换成以页为粒度的整数坐标。内核可以用它表达：

- node 或 zone 的起止范围。
- 页帧是否有效、是否存在。
- `struct page` 与物理页之间的转换。
- 高阶连续块的对齐和大小。

PFN 只是编号，不保证对应真实 RAM。因此读代码时还会遇到“PFN valid”和“PFN present”等检查。

## 四、`struct page`：物理页的软件档案

每个被内核管理的物理页帧通常都有一个 `struct page` 描述符。它不是页面内容，而是页面的元数据。

```text
物理页帧
┌─────────────────────────────┐
│ 真正的数据：用户内容、文件、页表、slab... │
└─────────────────────────────┘
                ▲
                │ 描述
struct page
┌─────────────────────────────┐
│ flags / refcount / mapping / index / lru... │
└─────────────────────────────┘
```

可以把 `struct page` 理解成页面档案：

- `flags` 记录 zone/node 身份及 dirty、locked、LRU 等状态。
- 引用计数回答“还有多少持有者不允许释放它”。
- mapcount 近似回答“它被多少页表映射”。
- `mapping/index` 在文件页或匿名页场景表达归属。
- `lru` 等联合字段把页面接入回收或其他专用链表。

这些字段大量复用 union，因为一页不可能同时是所有角色。正确解释字段前，必须先确定页面当前类型和生命周期阶段。

### 4.1 folio 是什么

folio 是“以一个或多个连续基础页为单位处理内存”的软件抽象。它减少了把复合页的任意 tail page 误当独立对象的风险，也让页缓存和 LRU 路径更自然地处理大于一页的对象。

先记住：

```text
page：基础页帧描述符，兼容面最广
folio：以 head page 为入口的一组连续、同属一个使用场景的 pages
```

不要把 folio 理解成另一套物理内存；它仍建立在 `struct page` 和物理页帧之上。

## 五、NUMA node：按距离组织物理内存

在 NUMA 系统中，不同 CPU 访问不同内存控制器后的 RAM，延迟和带宽可能不同。Linux 用 node 表达这类拓扑局部性。

每个内存节点主要由 `pglist_data`（常写作 `pg_data_t` 或 `pgdat`）描述：

```text
pglist_data (node 0)
├── node_id
├── node_start_pfn
├── node_spanned_pages / node_present_pages
├── node_zones[]
├── reclaim / kswapd 状态
└── 节点级统计和 LRU 相关状态
```

node 的核心意义不是“把内存平均分组”，而是告诉分配器：

1. 优先在哪个节点分配。
2. 本地节点不足时按什么顺序回退。
3. 回收线程和水位针对哪个节点工作。
4. 页面迁移是否可以改善 NUMA locality。

一个可能节点也可以暂时没有内存，即 memoryless node。Linux 仍可能为它保留最小 `pgdat`，以维持拓扑和支持后续热插拔。

## 六、zone：按可用能力切分节点内存

同一 node 内的页并不一定对所有请求等价。老设备可能只能 DMA 到低物理地址；普通内核分配希望使用正常映射范围；可移动内存又服务于碎片整理和热插拔。

因此每个 node 中有多个 zone：

```text
pgdat
└── node_zones[]
    ├── ZONE_DMA       低地址 DMA 限制
    ├── ZONE_DMA32     32 位 DMA 可达范围（体系结构相关）
    ├── ZONE_NORMAL    内核正常直接映射内存
    ├── ZONE_HIGHMEM   某些 32 位系统的高端内存
    ├── ZONE_MOVABLE   尽量只放可迁移页面
    └── ZONE_DEVICE    特殊设备内存语义（配置相关）
```

不是每台机器都有所有 zone；zone 的物理边界也由体系结构决定。

### 6.1 为什么不能只有一个全局空闲链表

只有一个链表会丢失三个重要约束：

- DMA 请求拿到设备不可达的高地址页。
- 本地 NUMA 分配无法表达距离与 fallback。
- 不可移动内核对象污染所有物理范围，使连续内存和热插拔更困难。

zone 是能力和策略边界，不只是地址分段。

## 七、三种页数：spanned、present、managed

这是理解 zone 初始化最重要的一组概念。

```text
zone PFN 包络：|--------- span ---------|
真实 RAM：      |--RAM--|  hole  |--RAM--|
保留页面：       kernel / firmware / early allocations
buddy 可分配：   剩余真正交给页分配器的页
```

| 计数 | 含义 |
|---|---|
| `spanned_pages` | zone 最低到最高 PFN 的跨度，包含物理洞 |
| `present_pages` | span 中真实存在的 RAM，扣除物理洞 |
| `managed_pages` | present 中已经交给伙伴系统管理的页，扣除保留等不可分配页 |

通常有：

```text
managed_pages <= present_pages <= spanned_pages
```

这解释了为什么 `free_area_init()` 不能把发现的 RAM 数量直接当空闲页数量。初始化 zone 容器时，`managed_pages` 可以先为 0；后续 memblock 把未保留页释放给 buddy，managed 才增长。

## 八、memblock：伙伴系统之前的临时管理员

### 8.1 为什么还需要一个早期分配器

伙伴系统需要 `struct page` 数组、zone、bitmap 等元数据才能工作；但这些元数据本身也需要内存。memblock 用简单有序区间解决自举问题。

```text
memblock.memory   固件/架构确认存在且可管理的 RAM
memblock.reserved 已被内核镜像、initrd、页表或早期分配占用的区间
```

可供早期分配的空间大致是：

```text
memory - reserved
```

### 8.2 三个已经分析的关键步骤

```text
memblock_add()
  → 把物理区间规范化后登记到 memory

memblock_alloc_try_nid()
  → 在 memory - reserved 中按地址/对齐/nid 找空间
  → 成功后写入 reserved 并返回清零虚拟地址

free_area_init()
  → 读取 memblock 的 PFN/NUMA 分布
  → 建立 pgdat、zone、free_area 和 pageblock bitmap
```

注意：这不是三函数首尾相接的直接调用链，而是共享数据上的阶段交接。`free_area_init()` 只有在为自身元数据分配空间时，才局部间接调用 memblock 分配接口。

## 九、伙伴系统：正式的连续页分配器

### 9.1 order 的最小模型

伙伴系统以 2 的幂次管理连续基础页：

| order | 页数 | 若基础页为 4 KiB 时的大小 |
|---:|---:|---:|
| 0 | 1 | 4 KiB |
| 1 | 2 | 8 KiB |
| 2 | 4 | 16 KiB |
| 3 | 8 | 32 KiB |

一般关系：

```text
页数 = 2^order
字节数 = PAGE_SIZE × 2^order
```

### 9.2 为什么叫 buddy

一个 order-N 块可以切成两个相邻、对齐的 order-(N-1) 块，这两个块互为伙伴。释放时，如果伙伴也空闲，就合并回更高 order。

```text
order 2: [ 0 1 2 3 ]
          /         \
order 1: [ 0 1 ]   [ 2 3 ]     ← buddies
```

zone 中的 `free_area[order]` 保存各阶空闲块，并按迁移类型进一步组织。分配高阶块时：

1. 在目标 order 找空闲块。
2. 没有则向更高 order 查找。
3. 找到较大块后逐级拆分。
4. 释放时尝试逐级与 buddy 合并。

### 9.3 总空闲很多为何仍会失败

假设有 8 个空闲页，但每个空闲页之间都夹着不可移动的已用页，那么 order-3 连续块仍不存在。这叫外部碎片：容量足够，连续性不足。

这也是“回收”和“压缩”不能混为一谈的原因：

```text
回收：把已用页变成空闲页，增加空闲总量
压缩：迁移可移动页，把小空洞整理成大连续空洞
```

## 十、pageblock 与迁移类型

如果任意不可移动对象散落在所有区域，长期运行后很难形成大连续块。Linux 用比基础页大的一组页——pageblock——记录迁移类型倾向。

常见思路：

```text
MIGRATE_UNMOVABLE   内核长期对象等难迁移页面
MIGRATE_MOVABLE     匿名页、页缓存等通常可迁移页面
MIGRATE_RECLAIMABLE 可通过回收释放的页面
其他类型            高原子预留、CMA、隔离等特殊用途
```

迁移类型不是每页永不改变的硬身份，而是分配和整理时的分组策略。目标是让不同生命周期的页面少互相污染。

`ZONE_MOVABLE` 与 `MIGRATE_MOVABLE` 也不是同一个层级：前者是 zone，后者是 pageblock/free-list 分类。

## 十一、PCP：为什么每个 CPU 还要缓存空闲页

如果每次 order-0 分配和释放都操作 zone 的全局伙伴锁，多核系统会产生严重竞争。per-CPU pageset（PCP）在每个 CPU 附近缓存一批小阶空闲页。

```text
CPU 本地分配/释放
       │
       ▼
      PCP                  快、少争锁
       │ 批量补充/排空
       ▼
zone buddy free_area       全局连续块账本
```

PCP 是性能缓存，不是另一种物理内存所有权。水位紧张、CPU offline 或批量阈值触发时，页面会在 PCP 和 buddy 之间搬运。

当前只需掌握这个模型；PCP 的 batch/high 计算、锁和 drain 路径仍记为概念债，适合结合 `get_page_from_freelist()` 与释放路径继续分析。

## 十二、一次物理页分配要满足什么

页分配不是“找到任何空闲页”即可。请求通常同时携带：

- 大小：order。
- 能否睡眠、回收或执行 I/O：GFP 行为约束。
- 可使用哪些 zone：GFP zone 约束。
- NUMA 策略和目标节点。
- 迁移类型。
- 水位与保留页规则。
- 是否允许回收、压缩或最终 OOM。

概念路径：

```text
分配请求
  → 由 GFP/order 推导允许的 zone 与行为
  → 按 zonelist / NUMA 策略遍历候选的 node/zone
  → 检查水位和低内存保留
  → 先尝试 PCP 或 buddy 快路径
  → 失败进入慢路径：回收、压缩、重试、OOM
```

这里的 GFP、水位、zonelist 细则尚未在本 primer 展开，属于下一阶段概念债。

## 十三、回收、交换、迁移、压缩分别做什么

| 机制 | 是否减少在用页 | 是否搬运内容 | 核心目标 |
|---|---|---|---|
| 回收文件页 | 可以 | 通常丢弃干净缓存或回写后丢弃 | 增加空闲页 |
| 回收匿名页 | 可以 | 可能写入 swap | 增加空闲页 |
| 页面迁移 | 通常不减少 | 是，从源页复制到目标页 | 改变物理位置 |
| 内存压缩 | 通常不减少 | 通过迁移完成 | 形成高阶连续空闲块 |
| NUMA balancing | 不以减少为目标 | 可能迁移 | 改善 CPU 与内存距离 |

### 13.1 LRU 管的是“可回收候选”，不是所有物理页

匿名页和文件页缓存可以进入 LRU 或多代 LRU；内核镜像、很多 slab、页表和特殊 reserved 页并不以普通 LRU 页形式管理。

`lruvec` 把 LRU 组织到 node 与 memcg 的交叉作用域：

```text
lruvec ≈ 某个 node 上、某个 memcg 的可回收页面集合
```

因此物理分配由 zone/buddy 决定，而回收候选又由页面用途、LRU、memcg 和 node 共同决定。

### 13.2 压缩的双向扫描

`compact_control` 驱动两个扫描器：低地址侧找可迁移源页，高地址侧找空闲目标页。迁移后，低地址侧更可能形成大的连续空洞。

```text
低 PFN                                         高 PFN
迁移页扫描  ─────────→        ←─────────  空闲页扫描
```

这解决连续性，不直接解决总容量不足。

## 十四、memcg 管的是归属，不替代 zone

`mem_cgroup` 回答“这页算哪个 cgroup 的额度”，zone 回答“这页在什么物理域、能否满足当前分配约束”。同一页面同时具有两种身份：

```text
物理身份：node + zone + PFN
资源归属：memcg
```

memcg 超过限制时，可以定向回收该 cgroup 在各 node 上的 LRU 页面；但最终释放出来的页仍回到其物理 zone 的 buddy/PCP。

## 十五、页面生命周期主线

```text
固件描述 RAM
  → memblock.memory 登记
  → 启动期 reserved / allocation
  → free_area_init 建 node/zone
  → memmap_init 建立并初始化 struct page
  → 未 reserved 页交给 buddy
  → 分配到某种用途
       ├── 匿名内存
       ├── 文件页缓存
       ├── slab
       ├── 页表
       └── DMA/特殊用途
  → 引用和用途解除
       ├── 直接释放
       ├── LRU 回收
       └── 迁移/压缩后释放源页
  → PCP 或 buddy
```

任何一次“释放”都必须先证明所有权已经结束：引用计数、页表映射、I/O、writeback、LRU 和复合页状态不能被绕过。物理页分配器只负责空闲块，不负责替上层判断页面内容是否还能使用。

## 十六、代码里哪里依赖这些概念

| 函数/结构体 | 依赖点 | 笔记 |
|---|---|---|
| `memblock_add()` | RAM 区间、重叠去重、memory 账本 | [memblock_add.md](../memblock_add.md) |
| `memblock_alloc_try_nid()` | `memory - reserved`、地址窗口、NUMA fallback | [memblock_alloc_try_nid.md](../memblock_alloc_try_nid.md) |
| `free_area_init()` | PFN、node/zone 切分、span/present/managed | [free_area_init.md](../free_area_init.md) |
| `page` | 页帧的软件身份、复用字段和生命周期 | [page_zone_pglist_data.md](../page_zone_pglist_data.md) |
| `zone` | 水位、buddy、PCP、迁移类型和 per-zone 统计 | [page_zone_pglist_data.md](../page_zone_pglist_data.md) |
| `pglist_data` | NUMA 节点、zone 集合与后台回收 | [page_zone_pglist_data.md](../page_zone_pglist_data.md) |
| `lruvec` / `scan_control` | 回收作用域、候选集合与扫描决策 | [kmem_cache_address_space_lruvec_scan_control.md](../kmem_cache_address_space_lruvec_scan_control.md) |
| `compact_control` | 页面迁移与高阶连续空间形成 | [compact_control_mem_cgroup.md](../compact_control_mem_cgroup.md) |
| `mem_cgroup` | 物理页之外的资源归属和限额维度 | [compact_control_mem_cgroup.md](../compact_control_mem_cgroup.md) |

## 十七、最容易混淆的点

### 17.1 虚拟地址、物理地址和 PFN

虚拟地址是 CPU 在当前页表上下文使用的地址；物理地址是地址翻译后的目标；PFN 是物理地址按页大小编号。三者不能直接混用。

### 17.2 `struct page` 不是页面内容

它是档案。对 `struct page *` 解引用看到的是元数据，不是该物理页中保存的用户字节。

### 17.3 zone 不是 NUMA node

node 表达拓扑距离；zone 表达寻址能力和用途约束。一个 node 内可以有多个 zone，同类 zone 也可以分布于不同 node。

### 17.4 free 不等于可立即满足高阶分配

空闲页可能在 PCP、不同 zone、不同 node 或零散 order-0 块中。总数足够仍可能不满足地址、连续性和水位要求。

### 17.5 `present_pages` 不等于空闲页

它只说明 RAM 真实存在，其中包含内核正在使用或保留的页面。

### 17.6 回收不等于压缩

回收改善容量，压缩改善连续性；分配慢路径可能需要两者协调。

### 17.7 `ZONE_MOVABLE` 不等于页面永远能迁移

它是降低不可移动分配污染的策略；页面瞬时状态、锁、引用、writeback 或 pin 仍可能阻止迁移。

## 十八、先放后的细节

以下主题对完整理解很重要，但不阻塞当前物理内存主线：

- 不同体系结构的直接映射、高端内存和页表布局。
- Sparsemem section、vmemmap 和内存热插拔细节。
- PCP 的 high/batch、自适应和 drain 协议。
- watermark boost、lowmem reserve、ALLOC flags 与完整 zonelist 算法。
- 长期 pin、DMA、IOMMU 对页面迁移的限制。
- THP、HugeTLB、CMA、ZONE_DEVICE 与设备私有内存。
- MGLRU 的代际算法与 refault 反馈。

## 十九、检验是否建立了正确模型

读完应能回答：

1. 为什么最大物理地址不能代表 RAM 总量？
2. PFN 和 `struct page` 分别是什么？
3. node 和 zone 为什么不能合成一个概念？
4. `spanned_pages`、`present_pages`、`managed_pages` 有何区别？
5. 为什么伙伴系统初始化还需要 memblock 分配内存？
6. 为什么总空闲页足够，高阶分配仍可能失败？
7. PCP 为什么能提速，又为什么不能完全替代 buddy？
8. 回收和压缩分别改变了什么？
9. memcg 限额与物理 zone 约束如何同时作用在一页上？
10. 为什么页面不能仅凭“内容不用了”就直接放回 buddy？

## 二十、下一步

最自然的下一段源码主线是：

```text
__alloc_pages_noprof()
  → get_page_from_freelist()
  → zone watermark / zonelist / PCP / buddy
  → __alloc_pages_slowpath()
  → reclaim / compaction / OOM
```

其中建议先补一篇“GFP、zonelist 与水位”的 concept primer，再使用 `kernel-code-analyzer` 深读 `get_page_from_freelist()`；这样不会在大量 flag 和水位判断中失去主线。
