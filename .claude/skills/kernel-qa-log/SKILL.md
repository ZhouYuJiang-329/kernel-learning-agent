---
name: kernel-qa-log
description: >
  记录学习内核时的提问与结论，按知识节点分组存档到 memory/{subsystem}/qa-log.md。
  来源包括用户主动提问和 AI 分析中发现的疑问。
  当用户说"记录这个问题"、"把这个问题存下来"、"这个问题先记着"、
  "log 这个问题"、"我刚才问的那个问题记一下"时触发。
  也在 kernel-learning-capture 完成且本次产生新疑问时自动链式触发。
---

# Kernel QA Log Skill

## 执行流程

### Step 1：确认目标 qa-log.md

推断问题关联的函数所属子系统，用相对路径检查目录：

```bash
ls "$(dirname "$0")/../../../memory/"
```

- **子系统目录存在** → 写入该子系统的 qa-log.md
- **子系统目录不存在，但归属不确定** → 写入 `unclassified/qa-log.md`（暂存区），条目备注"归属待确定"
- **子系统目录不存在，且归属明确** → 中止，输出提示：

```
[qa-log 中止] memory/{subsystem}/ 尚未初始化。
建议先说"我要开始学 {subsystem}"完成初始化，再记录问答。
```

### Step 2：提取问答内容

从当前对话中提取以下字段：

- **来源**：`用户提问` 或 `AI 发现`
- **问题**：完整问题描述
- **背景**：触发这个疑问的函数名 / 上下文（一句话）
- **关联节点**：问题涉及的主要函数或结构体名（用于分组）
- **结论**：
  - 对话中已得出答案 → 填写结论（1-3 句）
  - 尚未解答 → 写 `待解决`，并用以下方式查找对应 OQ 编号：

```bash
# 按关联节点名在 open-questions.md 中查找
grep -n "{关联节点}" .claude/memory/open-questions.md
```

若找到匹配的 OQ 条目，结论写 `待解决，关联 OQ-NNN`；若无匹配，结论写 `待解决`。

**"新疑问"的判断标准**（自动触发时）：本次 capture 流程执行了 Step 4（`append_question.sh` 追加了新 OQ），或对话中出现了明确未解答的技术问题且用户没有表示"先放着"以外的处理意向。

### Step 3：写入 qa-log.md

调用脚本完成编号分配和分组插入：

```bash
.claude/skills/kernel-qa-log/scripts/append_qa.sh \
  {subsystem} \
  "{关联节点}" \
  "{来源：用户提问|AI 发现}" \
  "{完整问题描述}" \
  "{背景一句话}" \
  "{结论}" \
  "{YYYY-MM-DD}"
```

脚本自动处理：
- 全文扫描 `### Q-NNN` 取最大编号 +1，保证不重复
- 定位 `## {关联节点}` 分组（不存在则新建）
- 在分组最后一个 `---` 分隔符后插入新条目

### Step 4：输出确认

```
[qa-log 已记录]
知识节点：{关联节点}
问题：{一句话摘要}
结论：{已解决 / 待解决（关联 OQ-NNN）}
文件：memory/{subsystem}/qa-log.md
```

## Scripts

- **`scripts/append_qa.sh`** — 分配 Q 编号、定位分组、精确插入条目。在 Step 3 调用。
  退出码：`0`=成功，`1`=参数错误，`2`=qa-log.md 不存在，`3`=子系统目录不存在。

## 质量检查

- [ ] `append_qa.sh` 执行成功（输出 `appended: {subsystem}/{node} → Q-NNN`，无 error）
- [ ] 结论字段不能为空（已解决写答案，未解决写"待解决，关联 OQ-NNN"或"待解决"）
- [ ] 来源字段为 `用户提问` 或 `AI 发现` 之一，不为空
- [ ] 未解决问题：先 grep open-questions.md 确认是否有对应 OQ，再填写结论
- [ ] unclassified 暂存条目：背景字段注明"归属待确定"

## Version History

- v1.0.0 (2026-06-30): 初始版本，脚本化编号分配和分组插入，补充 unclassified 分支和 OQ 匹配方式
