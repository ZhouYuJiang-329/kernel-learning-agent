# dep-graph.md 追加规则

> 本文件补充说明 Step 5 的依赖图更新细节，供需要深入了解规则的场景参考。
> 日常使用时 `append_dep_edge.sh` 已封装这些规则，直接传参调用即可。

## 调用脚本（标准做法）

```bash
.claude/skills/kernel-learning-capture/scripts/append_dep_edge.sh \
  {subsystem} {parent_func} {child_func} "{子函数说明}"
```

脚本处理所有边界情况，输出：
- `appended: parent → child` — 成功追加
- `skipped: parent → child (already exists)` — 已存在，跳过

## 脚本处理的三种情况

**情况 1：parent 已有节点，child 是新的子节点**

脚本找到 parent 块末尾，追加 `└──` 行，并将原末尾的 `└──` 改为 `├──`。

**情况 2：parent 节点不存在**

在代码块末尾追加新的根节点树：

```
{parent_func}
  └── {child_func} ({说明})
```

**情况 3：dep-graph.md 完全没有代码块**

在文件末尾新建代码块。

## 不重复检查规则

脚本在 parent 块范围内搜索 child 函数名，若已存在任何包含 child 名的行则跳过。
精确匹配函数名（不是子串匹配），避免 `pick_next_task` 匹配到 `pick_next_task_fair`。

## unclassified 子系统

`unclassified/dep-graph.md` 正常追加，作为临时记录。迁移节点后手动将相关树节点移到目标子系统的 dep-graph.md。

## 只追加 MCP 确认的直接调用关系

Step 5 的数据来源只能是本次会话中 kernel-graph MCP 查询的结果（`call_chain_down depth=1` 或 `find_callees`），不能凭记忆补充。每条边都必须有 MCP 返回的证据。

## 格式规范

```
父函数名
  ├── 子函数1 (一句话说明)
  ├── 子函数2 (一句话说明)
  └── 子函数3 (一句话说明)
```

- 缩进：2 个空格
- 多个子节点：最后一个用 `└──`，其余用 `├──`
- 说明：括号内一句话，说明该子函数的主要职责
