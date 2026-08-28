# API 分类参考表

> 此文件供 kernel-reading-guide 的 Step 2 参考。
> **不要直接照抄**——分类应从工程 `#include` 和 API 调用推导，此表仅提供候选分类名和典型成员。

## 通用内核模块分类

| 分类 | 典型头文件 | 典型 API / 结构体 |
|------|-----------|-----------------|
| 内核模块基础 | `module.h`, `init.h` | `module_init`, `module_exit`, `MODULE_LICENSE`, `MODULE_AUTHOR` |
| Sysfs / 用户接口 | `kobject.h`, `sysfs.h` | `kobject_create_and_add`, `sysfs_create_group`, `kobj_attribute` |
| 内核线程 | `kthread.h` | `kthread_create`, `kthread_bind`, `kthread_stop`, `wake_up_process` |
| 调度器与优先级 | `sched.h`, `sched/rt.h` | `sched_setscheduler_nocheck`, `set_user_nice`, `sched_param` |
| CPU 亲和性与迁移 | `cpumask.h` | `set_cpus_allowed_ptr`, `migrate_disable`, `cpumask_set_cpu` |
| 同步原语 | `mutex.h`, `completion.h`, `atomic.h`, `spinlock.h` | `mutex_lock`, `wait_for_completion`, `atomic_inc_return`, `spin_lock_irqsave` |
| CPU 热插拔 | `cpu.h`, `cpuhotplug.h` | `remove_cpu`, `add_cpu`, `cpuhp_setup_state`, `cpu_online` |
| 时间与延迟 | `delay.h`, `jiffies.h`, `ktime.h`, `hrtimer.h` | `msleep`, `ktime_get`, `hrtimer_init`, `jiffies_to_msecs` |
| 内存分配 | `slab.h`, `gfp.h` | `kcalloc`, `kzalloc`, `kfree`, `GFP_KERNEL`, `GFP_ATOMIC` |
| 中断管理 | `interrupt.h` | `request_irq`, `free_irq`, `disable_irq`, `irq_set_affinity` |
| 设备驱动基础 | `device.h`, `platform_device.h` | `platform_driver_register`, `dev_err`, `devm_kzalloc` |

## 专用子系统分类（按需添加）

| 分类 | 头文件 | 典型 API |
|------|--------|---------|
| MPAM / resctrl | `resctrl.h`, `mpam.h` | `rdtgroup_mkdir`, `resctrl_schemata_write`, `closid_alloc` |
| DMA | `dma-mapping.h` | `dma_alloc_coherent`, `dma_map_single` |
| 设备树 | `of.h`, `of_device.h` | `of_property_read_u32`, `of_find_compatible_node` |
| 块设备 | `blkdev.h`, `bio.h` | `bio_alloc`, `submit_bio` |
| 网络 | `skbuff.h`, `netdevice.h` | `alloc_skb`, `netif_rx` |
| perf / tracing | `perf_event.h` | `perf_event_create_kernel_counter` |

## 分类推导规则

1. 先列出工程所有 `#include <linux/xxx.h>`，按上表查找对应分类
2. 同一分类的头文件合并
3. 工程中用到但上表没有的头文件 → 新建分类，命名用子系统名
4. 只包含 1-2 个 API 的分类可合并到"其他"，不单独成节
