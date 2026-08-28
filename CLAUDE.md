# Kernel Learning Workspace

> 默认语言：中文
> 学习目标：基于源码证据建立可持续演进的 Linux 内核知识体系

## 会话启动

开始学习任务前读取：

1. `.claude/memory/MEMORY.md`
2. `.claude/memory/open-questions.md`

## 源码分析原则

- 涉及具体函数、结构体、源码路径或调用关系时，优先使用已配置的源码检索 MCP。
- 没有查询证据时，不编造具体路径、行号和调用边。
- 静态分析无法确认的函数指针和间接调用，标记为“待验证”。
- 外部文档与源码不一致时，以当前源码为准，并记录到 `open-questions.md`。

## 分析前检查

查询知识节点是否已经存在：

```bash
.claude/scripts/lookup_status.sh <function-or-struct>
```

- `unknown` 或 `not_found`：执行完整分析。
- `exploring`：优先补充调用链、设计动机或边界条件。
- `mastered`：先复用已有笔记，避免重复分析。
- `questioned`：优先查看关联开放问题。

## 记忆更新

完成函数或结构体分析后：

1. 将深度分析写入 `learn/{subsystem}/`。
2. 更新 `{subsystem}/knowledge.md` 中的状态、置信度和笔记路径。
3. 只将源码工具确认的直接关系加入 `dep-graph.md`。
4. 将未解决问题写入 `open-questions.md`。
5. 将重要问答写入 `qa-log.md`。
6. 刷新 `MEMORY.md` 和 `learning-journal.md`。

优先使用 `kernel-learning-capture` Skill 和仓库脚本完成这些操作。

## 文档边界

- `kernel-code-analyzer`：函数或结构体级源码分析。
- `kernel-reading-guide`：模块级阅读路线，不内联函数深度解析。
- `kernel-concept-mapper`：补充算法、硬件和理论背景。
- `kernel-learning-synthesizer`：整理已有笔记，生成术语表、状态矩阵和路径索引。
- `kernel-doc-comprehension-coach`：通过问答验收理解程度。
- `kernel-learning-capture`：将本次学习结果写入长期记忆。

## 本地路径

通过环境变量或本地配置维护路径，不要把个人绝对路径写入公共文件：

```text
KERNEL_SOURCE_ROOT=/path/to/linux
KERNEL_GRAPH_SERVER=/path/to/kernel-graph/mcp_server.py
KERNEL_GRAPH_DB=/path/to/kernel-graph/kernel.db
```

