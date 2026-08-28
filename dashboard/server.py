#!/usr/bin/env python3
"""
kernel-learning dashboard server
读取 .claude/memory/ 下的文件，通过 HTTP+SSE 提供给前端
"""
import json
import re
import time
import os
from datetime import datetime
from pathlib import Path
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse

MEMORY_DIR = Path(__file__).parent.parent / ".claude" / "memory"
LEARN_DIR = Path(__file__).parent.parent / "learn"
NOTES_INBOX_DIR = Path(__file__).parent.parent / "notes" / "inbox"
MANUAL_EDGES_FILE = Path(__file__).parent / "manual_edges.json"
PORT = 7788

_TREE_BOX_CHARS = '│├└─╿┌┐┘┴┬┼ '
_TREE_DASH_RUN = re.compile(r'─+')

_SKIP_NAMES = {'asm', 'goto', 'return', 'true', 'false', 'NULL',
               'IS_ENABLED', 'BUG', 'WARN', 'nop', 'patch', 'boot',
               'for', 'if', 'else', 'while', 'do', 'switch', 'case',
               'break', 'continue', 'struct', 'int', 'void', 'static',
               'const', 'unsigned', 'long', 'char', 'include', 'define'}
# 通用断言/调试宏：几乎所有函数都可能调用，不代表子系统间真实的调用关系，
# 若不过滤会把毫无关联的函数错误地连接到同一个假节点上（如 WARN_ON）
_SKIP_PATTERNS = [
    re.compile(r'^\w*WARN(_ON)?(_ONCE)?$'),      # WARN_ON, WARN_ONCE, MUTEX_WARN_ON, RCU_LOCKDEP_WARN...
    re.compile(r'^\w*BUG_ON$'),                   # BUG_ON, BUILD_BUG_ON...
    re.compile(r'^lockdep_assert\w*$'),
    re.compile(r'^might_sleep\w*$'),
    re.compile(r'^static_assert$'),
]
QUICK_NOTE_HEADER_RE = re.compile(r"^###\s+(\d{2}:\d{2})\s+(.+?)\s*$")


def tree_indent_level(line: str) -> int:
    """计算 ASCII 调用树中一行的缩进层级。

    子节点的深度编码在框线字符（│├└─）里，不能只数前导空格——
    "├─ foo" 和 "│    ├─ bar" 在纯空格意义上前导空格数可能相同，
    层级差异全部来自框线字符的宽度。先把连续横杠（"─" 与 "──"）
    归一化成单字符，避免 "└──"（双横）比 "├─"（单横）多算一层，
    再统计整段框线前缀的字符数作为层级。
    """
    normalized = _TREE_DASH_RUN.sub('─', line)
    prefix_len = len(normalized) - len(normalized.lstrip(_TREE_BOX_CHARS))
    return prefix_len


def extract_tree_node_name(raw: str) -> str:
    """从 ASCII 调用树的一行里提取函数名，过滤框线字符/分支说明/断言宏噪声。

    与 parse_call_chains_from_learn 共用同一套规则，保证手动粘贴的调用链
    和自动扫描 learn/*.md 解析出来的结果行为一致，不会出现两套标准。
    """
    raw = re.sub(r'^[\s─\-╿│├└┌┐┘┴┬┼]+', '', raw).strip()
    for ch in ('←', '→', '//', '#', '/*'):
        pos = raw.find(ch)
        if pos > 0:
            raw = raw[:pos].strip()
    # 去除开头的 [...] 分支/说明标注（可能连续多个），
    # 例如 "[尚未 finalize 分支] update_cpu_capabilities(...)"——
    # 标注后面往往还跟着真实函数名，不能整行丢弃
    while True:
        m = re.match(r'^\[[^\]]*\]\s*', raw)
        if not m:
            break
        raw = raw[m.end():].strip()
    paren = raw.find('(')
    if paren > 0:
        raw = raw[:paren].strip()
    bracket = raw.find('[')
    if bracket > 0:
        raw = raw[:bracket].strip()
    raw = raw.rstrip(')>:,;{').strip()
    # 纯"文件名.c:行号"续行（长注释被换行折断后单独成行的常见情况，
    # 例如 "cpufeature.c:3522-3524"）——不是函数名，整行跳过
    if re.match(r'^[a-zA-Z_][a-zA-Z0-9_./]*\.[ch](:\d|$|-\d)', raw):
        return ""
    name = raw.split()[0].split('.')[0] if raw else ""
    if not re.match(r'^[a-zA-Z_][a-zA-Z0-9_]{2,}$', name):
        return ""
    if name in _SKIP_NAMES:
        return ""
    if any(p.match(name) for p in _SKIP_PATTERNS):
        return ""
    return name


def parse_tree_lines_to_edges(lines: list) -> tuple:
    """把一段 ASCII 调用树的行列表解析成 (edges, ordered_node_names)。

    与 parse_call_chains_from_learn 内部循环共用同一套缩进栈算法：
    - 空行重置栈（视为另起一棵树）
    - 解析不出函数名的行（纯分支说明等）仍占住层级但把父节点透传给
      最近一个有名字的祖先，避免子节点错误挂到栈顶残留的上一个兄弟节点上
    """
    edges = []
    ordered_names = []
    seen_names = set()
    stack = []  # [(level, name_or_None)]

    for line in lines:
        stripped = line.rstrip()
        if not stripped.strip():
            stack = []
            continue

        level = tree_indent_level(stripped)
        name = extract_tree_node_name(stripped)

        while stack and stack[-1][0] >= level:
            stack.pop()

        if not name:
            stack.append((level, stack[-1][1] if stack else None))
            continue

        if name not in seen_names:
            seen_names.add(name)
            ordered_names.append(name)

        if stack and stack[-1][1]:
            src, tgt = stack[-1][1], name
            if not any(e['source'] == src and e['target'] == tgt for e in edges):
                edges.append({"source": src, "target": tgt, "relation": "calls"})

        stack.append((level, name))

    return edges, ordered_names


def load_manual_edges() -> dict:
    """读取用户手动添加的调用链（补丁到自动解析结果之上）"""
    if not MANUAL_EDGES_FILE.exists():
        return {"edges": [], "chains": []}
    try:
        data = json.loads(MANUAL_EDGES_FILE.read_text(encoding="utf-8"))
    except Exception:
        return {"edges": [], "chains": []}
    return {"edges": data.get("edges", []), "chains": data.get("chains", [])}


def save_manual_tree(raw_text: str, title: str) -> dict:
    """解析用户粘贴的调用树文本，追加到 manual_edges.json 并返回新增结果"""
    lines = raw_text.splitlines()
    edges, node_names = parse_tree_lines_to_edges(lines)
    if not edges and not node_names:
        raise ValueError("未能从粘贴内容中解析出任何函数名/调用关系")

    data = load_manual_edges()
    chain_idx = len(data["chains"])
    data["chains"].append({
        "title": title or f"手动添加 {chain_idx + 1}",
        "text": raw_text,
        "nodes": node_names,
    })
    existing = {(e['source'], e['target']) for e in data["edges"]}
    new_edges = [e for e in edges if (e['source'], e['target']) not in existing]
    data["edges"].extend(new_edges)

    MANUAL_EDGES_FILE.write_text(
        json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    return {"edges": edges, "nodes": node_names, "new_edge_count": len(new_edges)}


def normalize_quick_note_type(note_type: str) -> str:
    """Normalize quick-note type labels to the supported inbox categories."""
    if note_type in ("问题", "笔记", "待整理"):
        return note_type
    return "笔记"


def format_quick_note_block(note_type: str, content: str, source: str, now: datetime) -> str:
    """Format one quick-note markdown block for the daily inbox file."""
    normalized_type = normalize_quick_note_type(note_type)
    clean_content = content.strip()
    clean_source = source.strip() or "dashboard"
    return (
        f"### {now:%H:%M} {normalized_type}\n\n"
        f"- 来源：{clean_source}\n"
        f"- 状态：inbox\n\n"
        f"{clean_content}\n\n"
    )


def save_quick_note(payload: dict, now: datetime | None = None) -> dict:
    """Append a dashboard quick note to notes/inbox/YYYY-MM-DD.md."""
    now = now or datetime.now()
    content = str(payload.get("content") or "").strip()
    if not content:
        raise ValueError("随时记内容为空")

    note_type = str(payload.get("type") or "")
    source = str(payload.get("source") or "")
    NOTES_INBOX_DIR.mkdir(parents=True, exist_ok=True)
    daily_file = NOTES_INBOX_DIR / f"{now:%Y-%m-%d}.md"
    with daily_file.open("a", encoding="utf-8") as f:
        f.write(format_quick_note_block(note_type, content, source, now))
    return {"ok": True, "path": f"notes/inbox/{now:%Y-%m-%d}.md"}


def empty_quick_note_counts() -> dict:
    """Return the supported quick-note category counters."""
    return {"total": 0, "问题": 0, "笔记": 0, "待整理": 0}


def parse_quick_note_file(path: Path) -> list:
    """Parse one notes/inbox/YYYY-MM-DD.md quick-note file into note objects."""
    date = path.stem
    lines = path.read_text(encoding="utf-8").splitlines()
    notes = []
    current = None

    def flush_current():
        if current is None:
            return
        content = "\n".join(current["content_lines"]).strip()
        current["content"] = content
        current.pop("content_lines", None)
        current["source"] = current["source"].strip() or "dashboard"
        current["status"] = current["status"].strip() or "inbox"
        notes.append(current)

    for line in lines:
        header = QUICK_NOTE_HEADER_RE.match(line)
        if header:
            flush_current()
            time_text, note_type = header.groups()
            current = {
                "id": f"{date}-{time_text}-{len(notes)}",
                "_order": len(notes),
                "date": date,
                "time": time_text,
                "type": normalize_quick_note_type(note_type.strip()),
                "source": "dashboard",
                "status": "inbox",
                "content_lines": [],
                "file": f"notes/inbox/{path.name}",
            }
            continue

        if current is None:
            continue
        if line.startswith("- 来源："):
            current["source"] = line.removeprefix("- 来源：").strip()
            continue
        if line.startswith("- 状态："):
            current["status"] = line.removeprefix("- 状态：").strip()
            continue
        if line.strip() == "" and not current["content_lines"]:
            continue
        current["content_lines"].append(line)

    flush_current()
    return notes


def load_quick_notes() -> dict:
    """Load all markdown quick notes from notes/inbox, newest first."""
    counts = empty_quick_note_counts()
    if not NOTES_INBOX_DIR.exists():
        return {"notes": [], "counts": counts}

    notes = []
    for path in sorted(NOTES_INBOX_DIR.glob("*.md")):
        notes.extend(parse_quick_note_file(path))

    notes.sort(key=lambda note: (note["date"], note["time"], note["_order"]), reverse=True)
    for note in notes:
        counts["total"] += 1
        counts[note["type"]] = counts.get(note["type"], 0) + 1
        note.pop("_order", None)
    return {"notes": notes, "counts": counts}


def decode_json_body(raw: bytes) -> dict:
    """Decode a JSON object request body or raise a user-facing ValueError."""
    try:
        body = json.loads(raw.decode("utf-8"))
    except Exception:
        raise ValueError("请求体不是合法 JSON")
    if not isinstance(body, dict):
        raise ValueError("请求体不是合法 JSON")
    return body


def parse_subsystem_knowledge(text: str, subsystem_name: str) -> list:
    """解析单个 knowledge.md 文件，返回节点列表"""
    nodes = []
    current_section = None

    for line in text.splitlines():
        m = re.match(r'^## (.+)$', line)
        if m:
            current_section = m.group(1).strip()
            continue
        m = re.match(r'^### (.+)$', line)
        if m:
            current_section = m.group(1).strip()
            continue
        if line.startswith("|"):
            cols = [c.strip() for c in line.split("|")[1:-1]]
            if len(cols) >= 6 and cols[0] not in ("名称", "---", "------", ""):
                name, kind, status, conf, note, *rest = cols
                if name.startswith('-') or not name:
                    continue
                conf_val = int(conf) if conf.isdigit() else 0
                internal_doc = rest[0] if rest else "-"
                nodes.append({
                    "name": name,
                    "type": kind,
                    "status": status,
                    "confidence": conf_val,
                    "note": note,
                    "internal_doc": internal_doc,
                    "section": current_section or "",
                    "subsystem": subsystem_name,
                })
    return nodes


def parse_dep_graph_file(text: str) -> str:
    """从 dep-graph.md 提取代码块内容"""
    in_block = False
    content = []
    for line in text.splitlines():
        if line.strip() == "```":
            if not in_block:
                in_block = True
            else:
                break
        elif in_block:
            content.append(line)
    return "\n".join(content)


def load_knowledge_map() -> dict:
    """扫描 memory/*/knowledge.md + dep-graph.md，合并所有子系统数据"""
    all_nodes = []
    stats = {}
    all_dep_graphs = ""

    for subsys_dir in sorted(MEMORY_DIR.iterdir()):
        if not subsys_dir.is_dir():
            continue
        if subsys_dir.name == "unclassified":
            continue
        km_file = subsys_dir / "knowledge.md"
        dg_file = subsys_dir / "dep-graph.md"
        if not km_file.exists():
            continue

        subsys_name = subsys_dir.name
        nodes = parse_subsystem_knowledge(km_file.read_text(encoding="utf-8"), subsys_name)
        all_nodes.extend(nodes)
        stats[subsys_name] = {
            "mastered":  sum(1 for n in nodes if n["status"] == "mastered"),
            "exploring": sum(1 for n in nodes if n["status"] == "exploring"),
            "unknown":   sum(1 for n in nodes if n["status"] == "unknown"),
            "questioned":sum(1 for n in nodes if n["status"] == "questioned"),
            "total": len(nodes),
            "avg_confidence": round(
                sum(n["confidence"] for n in nodes if n["status"] != "unknown")
                / max(1, sum(1 for n in nodes if n["status"] != "unknown")), 1
            ),
        }

        if dg_file.exists():
            dep_text = parse_dep_graph_file(dg_file.read_text(encoding="utf-8"))
            if dep_text.strip():
                all_dep_graphs += dep_text + "\n\n"

    graph_data = parse_dep_graph(all_dep_graphs.strip(), all_nodes)

    return {
        "subsystems": {s: {"nodes": [n for n in all_nodes if n["subsystem"] == s]} for s in stats},
        "stats": stats,
        "all_nodes": all_nodes,
        "edges": graph_data["edges"],
        "reading_order": graph_data["reading_order"],
    }


def parse_knowledge_map(text: str) -> dict:
    """兼容旧接口：直接调用新的目录扫描版本（text 参数保留但忽略）"""
    return load_knowledge_map()


def parse_dep_graph(dep_graph: str, all_nodes: list) -> dict:
    """解析概念依赖图，提取边和推荐阅读顺序"""
    node_map = {n["name"]: n for n in all_nodes}

    def extract_name(raw: str) -> str:
        # 去除所有框线前缀字符
        raw = re.sub(r'^[\s─-╿│├└]+', '', raw).strip()
        # 去除开头的 [...] 分支/说明标注（可能连续多个），
        # 例如 "[尚未 finalize 分支] update_cpu_capabilities(...)"——
        # 标注后面往往还跟着真实函数名，不能整行丢弃
        while True:
            m = re.match(r'^\[[^\]]*\]\s*', raw)
            if not m:
                break
            raw = raw[m.end():].strip()
        # 截取到第一个 '(' 前，彻底避免嵌套括号残留
        paren = raw.find('(')
        if paren > 0:
            raw = raw[:paren].strip()
        # 截取到第一个 '[' 前（标注出现在函数名之后的情况）
        bracket = raw.find('[')
        if bracket > 0:
            raw = raw[:bracket].strip()
        # 清除末尾残留标点
        raw = raw.rstrip(')>:,;')
        return raw.split()[0].split('.')[0] if raw else ""

    # dep-graph에 나타나지만 knowledge.md에 없는 노드를 ghost unknown으로 보충
    # (엣지 source/target이 node_map에 없으면 그래프에 표시 안 됨)
    edge_node_names: set = set()
    for line in dep_graph.splitlines():
        if not line.strip():
            continue
        name = extract_name(line)
        if name:
            edge_node_names.add(name)
    for name in edge_node_names:
        if name not in node_map:
            ghost = {
                "name": name, "type": "function", "status": "unknown",
                "confidence": 0, "note": "-", "internal_doc": "-",
                "section": "", "subsystem": "unknown",
            }
            all_nodes.append(ghost)
            node_map[name] = ghost

    edges = []

    # 解析树形结构 → 边（用缩进栈跟踪父子）
    stack = []  # [(indent_level, name)]
    for line in dep_graph.splitlines():
        if not line.strip():
            stack = []
            continue
        level = tree_indent_level(line)
        name = extract_name(line)
        while stack and stack[-1][0] >= level:
            stack.pop()
        if not name:
            # 无法解析出函数名的行（纯分支说明、control-flow 关键字等）：
            # 仍要占住这一层级，但把父节点"透传"给最近一个有名字的祖先，
            # 否则它的子节点会错误地连到栈顶残留的上一个兄弟节点上
            stack.append((level, stack[-1][1] if stack else None))
            continue
        if stack and stack[-1][1]:
            edges.append({"source": stack[-1][1], "target": name, "relation": "calls"})
        stack.append((level, name))

    # 推荐阅读顺序：拓扑 DFS + 状态加权
    def status_pri(n):
        return {"mastered": 0, "exploring": 1, "questioned": 1, "unknown": 2}.get(
            n.get("status", "unknown"), 2)

    children = {}
    all_edge_nodes = set()
    for e in edges:
        children.setdefault(e["source"], []).append(e["target"])
        all_edge_nodes.add(e["source"])
        all_edge_nodes.add(e["target"])

    has_parent = {e["target"] for e in edges}
    roots = [n for n in all_edge_nodes if n not in has_parent]

    visited, order = set(), []

    def dfs(name, depth=0):
        if name in visited:
            return
        visited.add(name)
        node = node_map.get(name)
        if node:
            ch = children.get(name, [])
            if node["status"] == "mastered":
                reason = "已掌握"
            elif node["status"] == "exploring":
                reason = f"探索中（置信度 {node['confidence']}），建议深化理解"
            else:
                exploring_parents = [e["source"] for e in edges
                                     if e["target"] == name
                                     and node_map.get(e["source"], {}).get("status") in ("exploring", "mastered")]
                if exploring_parents:
                    reason = f"前置 {exploring_parents[0]} 已有基础，可以开始"
                else:
                    reason = "前置节点尚未学习，建议稍后"
            order.append({"name": name, "reason": reason,
                          "status": node["status"], "confidence": node["confidence"],
                          "depth": depth})
        for child in sorted(children.get(name, []), key=lambda x: status_pri(node_map.get(x, {}))):
            dfs(child, depth + 1)

    for root in roots:
        dfs(root)

    # 孤立的 exploring/unknown 节点补充到末尾
    for n in sorted(all_nodes, key=status_pri):
        if n["name"] not in visited and n["status"] != "mastered":
            order.append({"name": n["name"], "reason": "独立节点",
                          "status": n["status"], "confidence": n["confidence"], "depth": -1})

    reading_order = [o for o in order if o["status"] != "mastered"]
    return {"edges": edges, "reading_order": reading_order}




def parse_open_questions(text: str) -> dict:
    """解析 open-questions.md"""
    questions = {"CRITICAL": [], "MEDIUM": [], "LOW": [], "resolved": []}
    current_priority = None
    current_q = None

    for line in text.splitlines():
        # 优先级节切换时先 flush 当前问题
        for p in ("CRITICAL", "MEDIUM", "LOW"):
            if line.startswith(f"## {p}"):
                if current_q and current_priority:
                    questions[current_priority].append(current_q)
                    current_q = None
                current_priority = p
                break
        if line.startswith("## 已解答"):
            if current_q and current_priority:
                questions[current_priority].append(current_q)
                current_q = None
            current_priority = "resolved"
            continue

        # 问题条目标题
        m = re.match(r'^### (OQ-\d+)', line)
        if m and current_priority:
            if current_q:
                questions[current_priority].append(current_q)
            current_q = {"id": m.group(1), "priority": current_priority,
                         "title": "", "date": ""}
            continue

        # 字段解析
        if current_q:
            if line.startswith("- **问题**："):
                current_q["title"] = line.replace("- **问题**：", "").strip()
            elif line.startswith("- **提出日期**："):
                current_q["date"] = line.replace("- **提出日期**：", "").strip()
            elif line.startswith("- **解答日期**："):
                current_q["resolved_date"] = line.replace("- **解答日期**：", "").strip()

    if current_q and current_priority:
        questions[current_priority].append(current_q)

    return {
        "questions": questions,
        "counts": {p: len(questions[p]) for p in ("CRITICAL", "MEDIUM", "LOW", "resolved")},
    }


def parse_journal(text: str) -> list:
    """解析 learning-journal.md，返回全部条目（按日期倒序）"""
    entries = []
    current = None
    current_section = None  # "content" | "changes" | "next"

    for line in text.splitlines():
        # 日期行：允许日期后跟括号说明，如 "## 2026-07-01（备注）"
        m = re.match(r'^## (\d{4}-\d{2}-\d{2})', line)
        if m:
            if current:
                entries.append(current)
            current = {"date": m.group(1), "content": [], "changes": [], "next": []}
            current_section = None
            continue

        if current is None:
            continue

        # section 切换
        if "**学习内容**" in line:
            current_section = "content"
            continue
        elif "**知识状态变化**" in line:
            current_section = "changes"
            continue
        elif "**下次建议**" in line:
            current_section = "next"
            continue
        elif line.startswith("**") and "**" in line[2:]:
            # 其他 bold header（新增笔记等），归入 content
            current_section = "content"
            continue

        if line.startswith("- ") and current_section:
            item = line[2:].strip()
            if current_section == "changes":
                current["changes"].append(item)
            elif current_section == "next":
                current["next"].append(item)
            else:
                current["content"].append(item)

    if current:
        entries.append(current)

    return sorted(entries, key=lambda e: e["date"], reverse=True)


def parse_qa_log(text: str, subsystem_name: str) -> list:
    """解析单个 qa-log.md，返回问答条目列表

    格式：## 分组标题 → ### Q-NNN 标题 → 若干 "- **字段**：内容" 行
    （来源 / 问题 / 背景 / 结论 / 日期，背景为可选字段）
    """
    entries = []
    current_group = None
    current = None

    def flush():
        if current:
            entries.append(current)

    for line in text.splitlines():
        m = re.match(r'^## (.+)$', line)
        if m:
            flush()
            current = None
            current_group = m.group(1).strip()
            continue

        m = re.match(r'^### (Q-\d+)\s*(.*)$', line)
        if m:
            flush()
            current = {"id": m.group(1), "title": m.group(2).strip(),
                       "group": current_group or "", "subsystem": subsystem_name,
                       "source": "", "question": "", "background": "",
                       "conclusion": "", "date": ""}
            continue

        if current is None:
            continue

        for field, key in (("来源", "source"), ("问题", "question"),
                           ("背景", "background"), ("结论", "conclusion"),
                           ("日期", "date")):
            prefix = f"- **{field}**："
            if line.startswith(prefix):
                current[key] = line[len(prefix):].strip()
                break

    flush()
    return entries


def load_qa_logs() -> list:
    """扫描 memory/*/qa-log.md（包含 unclassified），合并所有子系统的问答日志"""
    entries = []
    if not MEMORY_DIR.exists():
        return entries
    for subsys_dir in sorted(MEMORY_DIR.iterdir()):
        if not subsys_dir.is_dir():
            continue
        qa_file = subsys_dir / "qa-log.md"
        if not qa_file.exists():
            continue
        try:
            text = qa_file.read_text(encoding="utf-8")
        except Exception:
            continue
        entries.extend(parse_qa_log(text, subsys_dir.name))
    # 按日期倒序（无日期的排在最后）
    entries.sort(key=lambda e: e.get("date") or "", reverse=True)
    return entries


def load_learn_docs() -> dict:
    """扫描 learn/*/ 返回 {subsystem: [{name, path, content}]}"""
    result = {}
    if not LEARN_DIR.exists():
        return result
    for subsys_dir in sorted(LEARN_DIR.iterdir()):
        if not subsys_dir.is_dir():
            continue
        files = []
        for md_file in sorted(subsys_dir.rglob("*.md")):
            rel = md_file.relative_to(LEARN_DIR)
            try:
                content = md_file.read_text(encoding="utf-8")
            except Exception:
                content = ""
            files.append({
                "name": md_file.stem,
                "path": str(rel).replace("\\", "/"),
                "content": content,
            })
        if files:
            result[subsys_dir.name] = files
    return result


def parse_call_chains_from_learn() -> dict:
    """扫描 learn/**/*.md，提取调用链代码块，返回 {edges, nodes, chains}

    判断逻辑：对每个无语言标签的裸代码块（``` 开头不带 c/bash/python 等）
    用内容评分决定是否为调用树：
      - 含框线字符（│ ├ └ ─ ╿）+1
      - 有效函数名行占比 ≥ 40% +1
      - 缩进层级数 ≥ 2 +1
      - 含 ← 或 → +1
    总分 ≥ 2 则视为调用树，纳入解析。
    标题取该代码块之前最近的 heading。
    """
    edges = []
    node_names = set()
    chains = []
    node_chain_map = {}

    LANG_TAG = re.compile(r'^```\s*[a-zA-Z]')  # ```c  ```bash  ```python …
    extract_name = extract_tree_node_name  # 与手动添加调用链共用同一套提取规则

    def is_call_tree(block_lines: list) -> bool:
        """对代码块内容评分，≥2 分视为调用树"""
        text = "\n".join(block_lines)
        score = 0
        BOX_CHARS = set('│├└─╿┌┐┘┴┬┼')
        if any(c in text for c in BOX_CHARS):
            score += 1
        if '←' in text or '→' in text:
            score += 1
        non_empty = [l for l in block_lines if l.strip()]
        if not non_empty:
            return False
        func_lines = sum(1 for l in non_empty if extract_name(l.rstrip()))
        if func_lines / len(non_empty) >= 0.4:
            score += 1
        indents = set()
        for l in non_empty:
            indents.add(tree_indent_level(l.rstrip()))
        if len(indents) >= 2:
            score += 1
        return score >= 2

    def flush_block(block_lines, block_node_names, title, stack_ref):
        if not block_lines or not block_node_names:
            return
        chain_idx = len(chains)
        chains.append({
            "title": title,
            "text": "\n".join(block_lines),
            "nodes": list(dict.fromkeys(block_node_names)),
        })
        for nm in block_node_names:
            node_chain_map.setdefault(nm, [])
            if chain_idx not in node_chain_map[nm]:
                node_chain_map[nm].append(chain_idx)

    if not LEARN_DIR.exists():
        return {"edges": [], "nodes": [], "chains": [], "node_chain_map": {}}

    for md_file in sorted(LEARN_DIR.rglob("*.md")):
        try:
            content = md_file.read_text(encoding="utf-8")
        except Exception:
            continue

        lines = content.splitlines()
        in_code_block = False
        is_lang_block = False   # 有语言标签的代码块，跳过
        last_heading = ""
        block_lines = []
        block_node_names = []
        stack = []

        for line in lines:
            # 跟踪最近一个 heading 作为代码块标题
            if re.match(r'^#{1,4}\s', line):
                last_heading = re.sub(r'^#{1,4}\s*', '', line).strip()

            fence = line.strip().startswith('```')

            if fence:
                if not in_code_block:
                    in_code_block = True
                    is_lang_block = bool(LANG_TAG.match(line.strip()))
                    block_lines = []
                    block_node_names = []
                    stack = []
                else:
                    # 代码块结束
                    if not is_lang_block and is_call_tree(block_lines):
                        flush_block(block_lines, block_node_names, last_heading, stack)
                    block_lines = []
                    block_node_names = []
                    stack = []
                    in_code_block = False
                    is_lang_block = False
                continue

            if not in_code_block or is_lang_block:
                continue

            block_lines.append(line)

            stripped = line.rstrip()
            if not stripped:
                stack = []
                continue

            level = tree_indent_level(stripped)

            name = extract_name(stripped)

            while stack and stack[-1][0] >= level:
                stack.pop()

            if not name:
                # 无法解析出函数名的行（纯分支说明、control-flow 关键字等）：
                # 仍要占住这一层级，但把父节点"透传"给最近一个有名字的祖先，
                # 否则它的子节点会错误地连到栈顶残留的上一个兄弟节点上
                stack.append((level, stack[-1][1] if stack else None))
                continue

            node_names.add(name)
            block_node_names.append(name)

            if stack and stack[-1][1]:
                src, tgt = stack[-1][1], name
                if not any(e['source'] == src and e['target'] == tgt for e in edges):
                    edges.append({"source": src, "target": tgt, "relation": "calls"})

            stack.append((level, name))

        # 文件末尾未关闭的代码块
        if in_code_block and not is_lang_block and is_call_tree(block_lines):
            flush_block(block_lines, block_node_names, last_heading, stack)

    # 合并手动添加的调用链（用户在 dashboard 里粘贴保存的，见 manual_edges.json）
    manual = load_manual_edges()
    existing_edge_keys = {(e['source'], e['target']) for e in edges}
    for e in manual["edges"]:
        key = (e['source'], e['target'])
        if key not in existing_edge_keys:
            existing_edge_keys.add(key)
            edges.append(e)
    for chain in manual["chains"]:
        chain_idx = len(chains)
        chains.append(chain)
        for nm in chain.get("nodes", []):
            node_names.add(nm)
            node_chain_map.setdefault(nm, [])
            if chain_idx not in node_chain_map[nm]:
                node_chain_map[nm].append(chain_idx)

    return {
        "edges": edges,
        "nodes": [{"name": n, "type": "function", "status": "note", "confidence": 0}
                  for n in node_names],
        "chains": chains,
        "node_chain_map": node_chain_map,
    }


def load_all_data() -> dict:
    try:
        oq = (MEMORY_DIR / "open-questions.md").read_text(encoding="utf-8")
        jn = (MEMORY_DIR / "learning-journal.md").read_text(encoding="utf-8")
        mem = (MEMORY_DIR / "MEMORY.md").read_text(encoding="utf-8")
    except Exception as e:
        return {"error": str(e)}

    # 从 MEMORY.md 提取学习焦点
    focus = []
    for line in mem.splitlines():
        if line.startswith("- **") and "进度**：" in line:
            focus.append(line.strip("- ").strip())

    # SSE 时监听子目录文件变化
    km_data = load_knowledge_map()
    oq_data = parse_open_questions(oq)
    jn_data = parse_journal(jn)

    return {
        "knowledge_map": km_data,
        "questions": oq_data,
        "journal": jn_data,
        "focus": focus,
        "learn_docs": load_learn_docs(),
        "call_chains": parse_call_chains_from_learn(),
        "qa_log": load_qa_logs(),
        "last_updated": time.strftime("%Y-%m-%d %H:%M:%S"),
    }


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass  # 静默日志

    def do_GET(self):
        path = urlparse(self.path).path

        if path == "/" or path == "/index.html":
            self._serve_file(Path(__file__).parent / "index.html", "text/html")
        elif path == "/api/data":
            self._serve_json(load_all_data())
        elif path == "/api/quick-notes":
            try:
                self._serve_json(load_quick_notes())
            except Exception as e:
                self._serve_json({"error": f"加载随时记失败：{e}"}, status=500)
        elif path == "/api/stream":
            self._serve_sse()
        else:
            self.send_error(404)

    def _read_json_body(self) -> dict:
        try:
            length = int(self.headers.get("Content-Length", 0))
        except (TypeError, ValueError):
            raise ValueError("请求体长度无效")
        if length < 0:
            raise ValueError("请求体长度无效")
        return decode_json_body(self.rfile.read(length))

    def do_POST(self):
        path = urlparse(self.path).path
        if path not in ("/api/manual-chain", "/api/quick-notes"):
            self.send_error(404)
            return

        try:
            body = self._read_json_body()
        except ValueError as e:
            self._serve_json({"error": str(e)}, status=400)
            return

        if path == "/api/manual-chain":
            raw_text = body.get("text", "")
            title = body.get("title", "")
            if not raw_text.strip():
                self._serve_json({"error": "粘贴内容为空"}, status=400)
                return

            try:
                result = save_manual_tree(raw_text, title)
            except ValueError as e:
                self._serve_json({"error": str(e)}, status=400)
                return
            except Exception as e:
                self._serve_json({"error": f"保存失败：{e}"}, status=500)
                return

            self._serve_json({"ok": True, **result})
            return

        if path == "/api/quick-notes":
            try:
                result = save_quick_note(body)
            except ValueError as e:
                self._serve_json({"error": str(e)}, status=400)
                return
            except Exception as e:
                self._serve_json({"error": f"保存失败：{e}"}, status=500)
                return

            self._serve_json(result)
            return

    def _serve_file(self, fpath: Path, mime: str):
        if not fpath.exists():
            self.send_error(404)
            return
        data = fpath.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", mime + "; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _serve_json(self, obj: dict, status: int = 200):
        data = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _serve_sse(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()

        last_mtime = 0
        try:
            while True:
                # 扫描所有 memory 文件（包括子目录）
                mtimes = []
                for f in ("open-questions.md", "learning-journal.md", "MEMORY.md"):
                    p = MEMORY_DIR / f
                    if p.exists():
                        mtimes.append(p.stat().st_mtime)
                for subsys_dir in MEMORY_DIR.iterdir():
                    if subsys_dir.is_dir():
                        for f in ("knowledge.md", "dep-graph.md", "qa-log.md"):
                            p = subsys_dir / f
                            if p.exists():
                                mtimes.append(p.stat().st_mtime)
                # 扫描 learn/ 下所有 .md 文件
                if LEARN_DIR.exists():
                    for md in LEARN_DIR.rglob("*.md"):
                        mtimes.append(md.stat().st_mtime)
                # 手动添加的调用链
                if MANUAL_EDGES_FILE.exists():
                    mtimes.append(MANUAL_EDGES_FILE.stat().st_mtime)
                mtime = max(mtimes) if mtimes else 0
                if mtime != last_mtime:
                    last_mtime = mtime
                    data = json.dumps(load_all_data(), ensure_ascii=False)
                    msg = f"data: {data}\n\n"
                    self.wfile.write(msg.encode("utf-8"))
                else:
                    # 心跳：无变化时也写入，及时探测浏览器端连接是否已断开
                    self.wfile.write(b": ping\n\n")
                self.wfile.flush()

                time.sleep(3)
        except (BrokenPipeError, ConnectionResetError):
            pass


if __name__ == "__main__":
    print(f"Dashboard: http://localhost:{PORT}")
    server = ThreadingHTTPServer(("", PORT), Handler)
    server.daemon_threads = True
    server.serve_forever()
