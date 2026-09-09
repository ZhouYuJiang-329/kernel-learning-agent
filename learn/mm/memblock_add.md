# memblock_add() 详解

> 源码位置：`mm/memblock.c:751`（Linux 7.2-rc6）  
> 核心职责：把固件或体系结构发现的一段物理内存登记到 `memblock.memory`，并把重叠、相邻区间整理成有序且尽量合并的区间表。

## 一、大白话总览

### （a）为什么要设计它

伙伴系统和 slab 尚未建立时，内核已经必须知道机器有多少物理内存。固件、设备树、E820 或体系结构探测代码提供的是若干物理地址区间；`memblock_add()` 把这些区间变成启动阶段统一可查询的“可用物理内存清单”。

如果没有它，各体系结构只能各自保存内存地图，后续页表、NUMA、per-CPU 数据和正式页分配器便没有统一输入。

### （b）如果让我自己设计

**一句话降级：**把一张新的“可用地址段”登记进一张按地址排序的表。

最小模型：

```text
输入：[base, base + size)
          │
          ▼
已有 memory 区间表 → 跳过重叠部分 → 插入尚未登记的部分 → 合并相邻同属性区间
```

核心对象：

| 对象 | 角色 |
|---|---|
| `memblock` | 启动期物理内存总账本 |
| `memblock.memory` | 固件确认存在、内核可管理的物理内存清单 |
| `memblock_type` | 一类区间的目录，记录数组、数量、容量和总大小 |
| `memblock_region` | 一条物理区间记录：起点、长度、属性、NUMA 节点 |
| `base/size` | 本次准备登记的新物理地址范围 |

真实复杂度来自区间可能乱序、重叠或相邻；region 数组容量有限；NUMA 节点和 flags 必须兼容；启动早期还不能依赖普通动态内存分配。

如果自己实现，大致步骤是：校验并截断溢出范围；空表直接填第一项；否则先计算需要新增几段；容量不够则扩容；再次遍历并真正插入；最后合并相邻且属性一致的区间，同时维护 `cnt` 和 `total_size`。

阅读 checklist：

- 新区间为空或发生地址上溢时如何处理？
- 重叠部分为何不能重复计入 `total_size`？
- 为什么同一套循环可能执行两遍？
- 扩容时为何不能覆盖正在加入的物理范围？
- 哪些条件允许两个 region 合并？

### （c）它是怎么设计的

`memblock_add()` 自身只是固定参数的薄包装：目标固定为 `memblock.memory`，节点先记为 `MAX_NUMNODES`，flags 为 0。真正的区间代数由 `memblock_add_range()` 完成。

核心技巧是“先计数、后插入”：当数组空间不确定够用时，第一遍只算新增 region 数量，扩容后从头再走一遍。这样插入导致的数组移动不会让容量计算失真。

### （d）主要情况

| 情况 | 做法 | 原因 |
|---|---|---|
| `size` 被截断为 0 | 直接成功返回 | 空区间不改变地图 |
| region 表为空 | 直接写入第 0 项 | 避免进入通用拆分流程 |
| 新区间完全被覆盖 | 返回成功、不新增 | 防止重复登记和重复计数 |
| 新区间部分重叠 | 只插入没有覆盖的洞 | 保持 region 互不重叠 |
| 数组空间不足 | 扩容后 `goto repeat` | 插入前必须保证最坏情况下的槽位 |
| 插入完成 | 合并相邻兼容区间 | 控制 region 数量并保持规范形式 |

## 二、控制流骨架

```text
memblock_add(base, size)
│
├─ 计算用于调试输出的闭区间末地址
├─ 输出 memblock debug 日志
└─ memblock_add_range(&memblock.memory, base, size, MAX_NUMNODES, 0)
    │
    ├─ [截断后 size == 0] → return 0
    ├─ [region 表为空] → 填第一项、更新 total_size/cnt → return 0
    ├─ 判断现有数组能否容纳最坏情况
    ├─ repeat：重置 base 和新增计数
    ├─ 【遍历现有 region】
    │   ├─ [现有起点 >= 新区间末尾] → break，后面更不可能重叠
    │   ├─ [现有末尾 <= 当前 base] → continue
    │   ├─ [重叠前仍有未覆盖片段] → 计数；insert 模式下插入
    │   └─ 把 base 推进到已覆盖部分末尾
    ├─ [尾部仍有剩余] → 计数；insert 模式下插入
    ├─ [nr_new == 0] → return 0，新范围已完全存在
    ├─ [尚未进入 insert 模式]
    │   └─ 【容量不足循环】扩容失败 → return -ENOMEM；否则 goto repeat
    └─ [已经插入] → 合并相邻 region → return 0
```

## 三、快速定位与宏观地位

```text
固件 / DT / E820 / 体系结构内存探测
                │
                ▼
      arch setup / early memory scan
                │
                ▼
          [memblock_add()]
                │
                ▼
     memblock.memory 有序区间目录
                │
       ┌────────┴────────┐
       ▼                 ▼
启动期 memblock 分配    free_area_init() 读取 PFN/NUMA 布局
```

真实触发场景包括：

- x86 `start_kernel()` 经 `setup_arch()`、`e820__memblock_setup()` 登记 E820 RAM。
- arm64 的 `arm64_memblock_init()` 把设备树发现并修正后的内存加入 memblock。
- PowerPC 的 `early_init_dt_add_memory_arch()` 登记设备树 memory 节点。
- 某些平台早期探测或内存热插拔准备代码也直接调用它。

## 四、完整调用链

kernel-graph 显示调用者跨多个体系结构。代表性入口为：

```text
start_kernel()
  └── setup_arch()
      └── e820__memblock_setup()             // arch/x86/kernel/e820.c:1347
          └── memblock_add()                  // mm/memblock.c:751

early_init_dt_add_memory_arch()               // arch/powerpc/kernel/prom.c:640
  └── memblock_add()

arm64_memblock_init()                         // arch/arm64/mm/init.c:257/283
  └── memblock_add()
```

向下执行链：

```text
memblock_add()
  ├── memblock_dbg()
  └── memblock_add_range()
      ├── memblock_cap_size()
      ├── memblock_insert_region()
      ├── memblock_double_array()             // 必要时扩容 region 数组
      └── memblock_merge_regions()
```

注意：kernel-graph 没有找到 `memblock_add()` 到 `free_area_init()` 的直接调用路径。它们通过全局 `memblock.memory` 数据发生阶段性依赖，不是普通调用关系。

## 五、逐行详解：memblock_add()

```c
int __init_memblock memblock_add(phys_addr_t base, phys_addr_t size)
{
    phys_addr_t end = base + size - 1;

    memblock_dbg("%s: [%pa-%pa] %pS\n", __func__,
                 &base, &end, (void *)_RET_IP_);

    return memblock_add_range(&memblock.memory, base, size,
                              MAX_NUMNODES, 0);
}
```

- `__init_memblock` 表示该代码服务于 memblock 生命周期；具体段属性受配置影响。
- `end` 只用于打印人类习惯的闭区间 `[base, end]`；内部仍使用 `[base, base + size)`。
- `%pa` 按物理地址类型打印，`_RET_IP_` 帮助定位哪个早期调用者登记了区间。
- `&memblock.memory` 明确这是增加“存在的内存”，不是预留区间；预留使用 `memblock.reserved`。
- `MAX_NUMNODES` 表示此入口没有提供精确 NUMA 节点，后续专用接口可带 nid。
- 返回值原样传递：成功为 0，region 数组无法扩容时可能为 `-ENOMEM`。

## 六、核心 helper：memblock_add_range()

### 6.1 边界与空表快路径

`memblock_cap_size(base, &size)` 防止 `base + size` 溢出。空表时直接建立第一条 region，并同步：

```text
regions[0] = { base, size, flags, nid }
total_size = size
cnt        = 1
```

`WARN_ON(type->cnt != 0 || type->total_size)` 检查空表哨兵和账本是否自洽。

### 6.2 区间去重

遍历时使用半开区间：

```text
新范围：[base, end)
旧范围：[rbase, rend)
```

- `rbase >= end`：旧表有序，后续都位于新范围右侧，可以 `break`。
- `rend <= base`：旧范围在当前待处理片段左侧，`continue`。
- `rbase > base`：`[base, rbase)` 是未登记片段，需要新增。
- 随后 `base = min(rend, end)`，把旧范围覆盖的部分从待办范围中删掉。

因此重复调用 `memblock_add()` 是幂等式的：已登记部分不会重复增加。

### 6.3 两遍执行与扩容

第一遍 `insert == false` 时只增加 `nr_new`，不移动数组。若 `type->cnt + nr_new > type->max`，反复调用 `memblock_double_array()`，然后切换为插入模式并 `goto repeat`。

最坏情况下，新范围与所有旧范围交错，需要额外产生接近 `type->cnt + 1` 个片段，所以代码用 `type->cnt * 2 + 1 <= type->max` 判断能否一开始就安全插入。

### 6.4 插入后的合并

`memblock_insert_region()` 负责移动数组、写入属性并更新计数；`memblock_merge_regions()` 合并相邻且 nid/flags 相容的条目。关键不变量是：

```text
regions 按 base 递增
regions 彼此不重叠
total_size = 所有 region.size 之和
相邻且属性相同的 region 尽量合并
```

## 七、关键结构体

```c
struct memblock {
    bool bottom_up;                 // 分配搜索方向
    phys_addr_t current_limit;      // 当前可访问物理地址上界
    struct memblock_type memory;    // 已发现的可用内存
    struct memblock_type reserved;  // 已被启动代码占用的范围
};

struct memblock_type {
    unsigned long cnt;              // 有效 region 数量
    unsigned long max;              // 数组容量
    phys_addr_t total_size;         // 去重后的总大小
    struct memblock_region *regions;// 有序区间数组
    char *name;                     // 调试名称
};

struct memblock_region {
    phys_addr_t base;
    phys_addr_t size;
    enum memblock_flags flags;
    /* NUMA nid 由配置相关表示保存/访问 */
};
```

## 八、关键设计决策

1. **为什么不直接保存固件原始表？** 固件表可能重叠、乱序且带保留类型；内核需要规范化的统一视图。
2. **为什么用数组而不是早期红黑树？** 启动期 region 数通常较少，数组紧凑、确定且不依赖额外节点分配。
3. **为什么重叠不是错误？** 多个发现渠道或命令行修正可能重复描述同一范围；去重合并更健壮。
4. **为什么登记 memory 不等于内存已经能由伙伴系统分配？** 此时只是建立物理地图；`struct page`、zone 和 buddy free list 尚未完整建立。

## 九、与另外两个函数的关系

```text
memblock_add()              写 memblock.memory：机器“拥有什么”
memblock_alloc_try_nid()    查 memory、写 reserved：启动代码“占用了什么”
free_area_init()            读 memory：把物理地图转换为 node/zone 元数据
```

三者应按阶段理解，而不要误画成 `memblock_add() -> memblock_alloc_try_nid() -> free_area_init()` 的直接调用链。
