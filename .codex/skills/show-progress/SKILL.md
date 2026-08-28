---
name: show-progress
description: >
  打开内核学习可视化仪表盘（网页），展示知识图谱、进度条和学习日志。
  当用户说"打开面板"、"学习面板"、"dashboard"、"可视化"、"show dashboard"时触发。
  仅启动网页；如需文字进度报告请使用 kernel-progress-report skill。
---

# Show Progress Skill

## 执行流程

### 启动仪表盘

```bash
bash "${CLAUDE_SKILL_DIR}/../../dashboard/start.sh"
```

脚本行为：
1. 检查端口 7788 是否已占用，已占用则直接打印访问地址，不重复启动
2. 后台启动 `dashboard/server.py`，日志写入 `/tmp/kernel-dashboard.log`
3. 在 WSL Windows 浏览器打开 `http://localhost:7788`

**若脚本不存在**（路径不对或 dashboard 未初始化），输出：
```
[show-progress 失败] dashboard/start.sh 不存在，请检查路径：
  预期位置：{CLAUDE_SKILL_DIR}/../../dashboard/start.sh
  实际项目根：用 pwd 确认当前路径
```

### 停止仪表盘

用户说"关闭面板"/"停止 dashboard" 时：

```bash
bash "${CLAUDE_SKILL_DIR}/../../dashboard/stop.sh"
```

## 仪表盘功能说明

- **总览**：整体进度百分比、各子系统掌握状态进度条、学习焦点
- **知识图谱**：力导向图，节点颜色区分 mastered/exploring/unknown，可拖拽
- **节点列表**：全部函数/结构体，支持按状态筛选，显示置信度和 Confluence 链接
- **开放问题**：CRITICAL/MEDIUM/LOW 分级，含提出日期
- **学习日志**：最近 10 次会话的学习记录

服务启动后实时监听 `.claude/memory/` 目录，文件变化时自动推送更新到浏览器（SSE），无需手动刷新。

## 质量检查

- [ ] 脚本执行成功（无报错，打印了访问地址或"已在运行"）
- [ ] 浏览器正常打开 `http://localhost:7788`
- [ ] 若脚本不存在，已输出明确的路径提示而非静默失败

## Version History

- v1.0.0 (2026-06-30): 初始版本，改用 CLAUDE_SKILL_DIR 相对路径，补充错误处理和质量检查
