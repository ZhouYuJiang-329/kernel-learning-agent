<div align="center">

# Kernel Learning Workspace

[English](README.md) · 中文

**将 Linux 内核源码学习变成可验证、可积累、可回顾的长期知识系统。**

基于 Claude Code / Codex Skills · 源码检索 MCP · Markdown 长期记忆 · 本地 Dashboard

</div>

## 它解决什么问题

用 AI 学内核时，真正困难的往往不是得到一次解释，而是让结论有源码依据、让学习过程可以持续积累，并知道下一步该学什么。这个工作区把这些环节组织成一条可复用的学习闭环：

```text
提出问题 / 阅读源码
        ↓
Skills 按任务类型分析、检索和追问
        ↓
结构化学习文档（learn/）与可核验的调用关系
        ↓
长期记忆（知识状态、依赖图、问答、开放问题、学习日志）
        ↓
Dashboard 回顾进度、知识图谱与下一步学习方向
```

它适合希望围绕 Linux 内核源码进行长期、系统化学习的个人或团队；不是内核源码本身，也不附带内核图数据库。

## 核心能力

| 能力 | 用途 |
| --- | --- |
| 源码深度分析 | 解释函数和结构体，给出上下文、设计意图与调用链；结论优先由源码检索工具验证。 |
| 阅读路线 | 为一个子系统整理关键文件、数据结构、阅读顺序和待补的背景知识。 |
| 知识沉淀 | 将学习结果写入 Markdown 记忆，维护知识节点、置信度、依赖图、问答和开放问题。 |
| 理解验收 | 通过针对性提问识别模糊点，并推荐适合的下一步学习动作。 |
| 影响分析与画图 | 分析内核改动的波及范围，或生成可编辑的 draw.io 调用链、架构图和状态机。 |
| 可视化回顾 | 本地 Dashboard 展示进度、知识图谱、学习文档、问题和学习日志，并自动刷新。 |

## 快速开始

### 依赖

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) 或 Codex；仓库内分别提供对应的 Skills。
- Python 3.9+；Dashboard 仅依赖 Python 标准库。
- 可选：已建立索引的 `kernel-graph` MCP，用于查询函数定义、调用链、结构体和字段写入位置。

### 1. 配置 Claude Code（可选 MCP）

```bash
cp .claude/settings.example.json .claude/settings.json
```

编辑 `.claude/settings.json`，将 `kernel-graph` 的两个绝对路径替换为本机路径：

```json
{
  "mcpServers": {
    "kernel-graph": {
      "command": "python3",
      "args": [
        "/path/to/kernel-graph/mcp_server.py",
        "--db",
        "/path/to/kernel-graph/kernel.db"
      ]
    }
  }
}
```

没有 `kernel-graph` 也可以开始：移除 `mcpServers` 配置即可，Skills 会把无法由静态信息确认的结论标记为待验证。Codex 使用仓库中的 `.codex/skills/`；请按你的 Codex 工作区配置启用该目录。

### 2. 启动 Dashboard

```bash
cd dashboard
./start.sh
```

打开 <http://localhost:7788>。脚本会在服务尚未运行时启动它；若不自动打开浏览器，可手动访问该地址。

### 3. 用自然语言开始学习

在 Claude Code 或 Codex 会话中试试：

```text
我要开始学 Linux 调度器
解释 schedule 函数
帮我梳理需要阅读哪些内核代码
记录这个
我学到哪了
打开学习面板
```

## 推荐学习流程

1. 用“我要开始学 X”创建一个学习板块，明确目标和范围。
2. 让 AI 为模块生成阅读路线，先建立文件、数据结构和概念的全局地图。
3. 粘贴函数或结构体源码，进行带调用链的深度分析；有 MCP 时优先查询源码证据。
4. 遇到“为什么这样设计”或基础概念缺口时，补充理论与硬件背景。
5. 说“记录这个”把结果更新到长期记忆；说“我读完了”或“考考我”验收理解。
6. 定期查看文字进度报告或 Dashboard，围绕开放问题继续学习。

## 内置 Skills

| 任务 | 可以这样说 |
| --- | --- |
| 创建学习板块 | “我要开始学 RCU” |
| 深度分析代码 | “详解这段内核代码”“调用链是什么” |
| 规划阅读 | “我需要阅读哪些内核代码” |
| 补概念 | “为什么使用内存屏障” |
| 整理已有笔记 | “帮我理清这些文档”“生成术语表” |
| 验收理解 | “我读完了，考考我” |
| 分析改动影响 | “改这个安全吗”“改完要测哪些” |
| 生成图 | “帮我画调用链图” |
| 同步笔记 | “同步 Obsidian” |

## 项目结构

```text
.claude/
  skills/       Claude Code Skills
  hooks/        文档捕获提醒与会话结束检查
  memory/       学习状态、依赖图、问答、问题与日志
  scripts/      查询和维护记忆的辅助脚本
.codex/skills/  Codex Skills
dashboard/      本地可视化工作台与测试
learn/          函数分析、概念说明、阅读路线和综合文档
notes/inbox/    Dashboard 随手记入口
img/            生成的架构图和流程图
```

## 记忆模型

学习状态保存在 `.claude/memory/`，文本格式让它能被人直接阅读，也能跨会话被 AI 复用。

| 文件 | 记录内容 |
| --- | --- |
| `MEMORY.md` | 全局索引、当前焦点、统计和最近分析 |
| `{subsystem}/knowledge.md` | 知识节点、掌握状态、置信度和文档位置 |
| `{subsystem}/dep-graph.md` | 已由源码工具确认的调用关系 |
| `{subsystem}/qa-log.md` | 按知识节点归档的问题与结论 |
| `open-questions.md` | 尚未解决的问题及优先级 |
| `learning-journal.md` | 每次学习产物和建议的下一步 |

知识节点有四种状态：`unknown`、`exploring`、`mastered` 和 `questioned`；置信度使用 0–100 表示当前掌握程度。

## 测试

```bash
python3 dashboard/server_journal.test.py
python3 dashboard/quick_notes.test.py

for file in dashboard/*.test.js; do
  node "$file"
done
```

## 可选集成

- **kernel-graph MCP**：检索源码中的定义、调用链、结构体和字段写入位置。
- **Confluence**：检索已有的团队或个人架构资料。
- **Obsidian**：将 `learn/` 笔记同步到 Vault 并生成双向链接。
- **draw.io**：把架构、调用链和状态机保存成可编辑的图文件。

## 数据与安全

- 不要提交 API Token、私钥、公司内部源码或未经授权的文档。
- `.claude/settings.json` 包含本机路径，已默认忽略；请只提交 [`settings.example.json`](.claude/settings.example.json)。
- `kernel-graph` 是外部可选组件，本仓库不包含 Linux 内核源码或其数据库。
- AI 的源码分析应以实际检索结果为准；无法确认的间接调用或动态行为应保留为待验证项。

## 许可证

仓库目前尚未声明开源许可证。公开发布、复用或二次分发前，请根据实际用途添加合适的许可证。
