<div align="center">

# Kernel Learning Workspace

English · [中文](README-zh.md)

**Turn Linux kernel source-code study into a long-term knowledge system that is evidence-based, cumulative, and easy to revisit.**

Claude Code / Codex Skills · Source-query MCP · Markdown long-term memory · Local dashboard

</div>

## What it solves

The hard part of learning the kernel with AI is not getting a one-off explanation. It is grounding conclusions in source evidence, retaining what you learn, and knowing what to study next. This workspace turns those pieces into a reusable learning loop:

```text
Ask a question / read source code
        ↓
Skills analyze, query, and follow up based on the task
        ↓
Structured learning documents (learn/) and verifiable call relationships
        ↓
Long-term memory: knowledge state, dependency graph, Q&A, open questions, journal
        ↓
Dashboard for progress, knowledge graph, and next learning steps
```

It is for individuals and teams learning the Linux kernel systematically over time. It is not the Linux kernel source tree and does not include a kernel graph database.

## Core capabilities

| Capability | What it does |
| --- | --- |
| In-depth source analysis | Explains functions and structures with context, design intent, and call paths; source-query evidence takes priority. |
| Reading plans | Maps key files, data structures, reading order, and missing background for a subsystem. |
| Knowledge capture | Stores results in Markdown memory: knowledge nodes, confidence, dependency graphs, Q&A, and open questions. |
| Comprehension checks | Uses focused questions to find gaps and recommend the most useful next learning action. |
| Impact analysis and diagrams | Assesses the blast radius of kernel changes or creates editable draw.io call-chain, architecture, and state-machine diagrams. |
| Visual review | A local dashboard shows progress, knowledge graphs, documents, questions, and learning journals with automatic refresh. |

## Quick start

### Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) or Codex; this repository ships Skills for both.
- Python 3.9+; the dashboard uses only the Python standard library.
- Optional: an indexed `kernel-graph` MCP server for functions, call paths, structures, and field writes.

### 1. Configure Claude Code (optional MCP)

```bash
cp .claude/settings.example.json .claude/settings.json
```

In `.claude/settings.json`, replace the two absolute paths for `kernel-graph` with paths on your machine:

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

You can start without `kernel-graph`: remove the `mcpServers` configuration and the Skills will mark conclusions that static information cannot confirm as needing verification. Codex uses the Skills in `.codex/skills/`; enable that directory according to your Codex workspace configuration.

### 2. Start the dashboard

```bash
cd dashboard
./start.sh
```

Open <http://localhost:7788>. The script starts the service if it is not already running; open the address manually if a browser does not launch.

### 3. Start learning in natural language

Try prompts such as these in a Claude Code or Codex session:

```text
I want to start learning the Linux scheduler
Explain the schedule function
Which kernel code should I read for this subsystem?
Capture this
What have I learned?
Open the learning dashboard
```

## Recommended learning flow

1. Create a learning module with “I want to start learning X” and define its scope.
2. Generate a reading guide to establish the big picture: files, data structures, and concepts.
3. Paste a function or structure for a detailed analysis with call paths; query source evidence when MCP is available.
4. Fill in theory or hardware background whenever you encounter a “why was it designed this way?” gap.
5. Say “Capture this” to update long-term memory, then say “I finished reading this—quiz me” to check your understanding.
6. Review the text progress report or dashboard regularly, and continue from open questions.

## Included Skills

| Task | Example prompt |
| --- | --- |
| Create a learning module | “I want to start learning RCU” |
| Analyze code in depth | “Explain this kernel code in detail” or “What is its call chain?” |
| Plan your reading | “Which kernel code should I read?” |
| Fill conceptual gaps | “Why are memory barriers used here?” |
| Organize existing notes | “Help me connect these documents” or “Generate a glossary” |
| Check comprehension | “I finished reading this—quiz me” |
| Analyze change impact | “Is this change safe?” or “What should I test?” |
| Generate a diagram | “Draw a call-chain diagram” |
| Sync notes | “Sync to Obsidian” |

## Project layout

```text
.claude/
  skills/       Claude Code Skills
  hooks/        Capture reminders and end-of-session checks
  memory/       Learning state, dependency graph, Q&A, questions, and journal
  scripts/      Helpers for querying and maintaining memory
.codex/skills/  Codex Skills
dashboard/      Local visual workspace and tests
learn/          Function analyses, concepts, reading guides, and syntheses
notes/inbox/    Dashboard quick-note inbox
img/            Generated architecture and flow diagrams
```

## Memory model

Learning state is kept in `.claude/memory/`. Its plain-text format is readable by people and reusable by AI across sessions.

| File | Contents |
| --- | --- |
| `MEMORY.md` | Global index, current focus, statistics, and recent analyses |
| `{subsystem}/knowledge.md` | Knowledge nodes, mastery state, confidence, and document locations |
| `{subsystem}/dep-graph.md` | Call relationships confirmed by source tools |
| `{subsystem}/qa-log.md` | Questions and conclusions grouped by knowledge node |
| `open-questions.md` | Unresolved questions and their priority |
| `learning-journal.md` | Learning artifacts from each session and suggested next steps |

Knowledge nodes use four states: `unknown`, `exploring`, `mastered`, and `questioned`. Confidence is represented on a 0–100 scale.

## Tests

```bash
python3 dashboard/server_journal.test.py
python3 dashboard/quick_notes.test.py

for file in dashboard/*.test.js; do
  node "$file"
done
```

## Optional integrations

- **kernel-graph MCP**: query source definitions, call paths, structures, and field write locations.
- **Confluence**: search existing team or personal architecture material.
- **Obsidian**: sync `learn/` notes to a vault and create bidirectional links.
- **draw.io**: save architecture, call-chain, and state-machine diagrams in an editable format.

## Data and safety

- Do not commit API tokens, private keys, internal source code, or unauthorized documents.
- `.claude/settings.json` contains machine-specific paths and is ignored by default; commit only [`settings.example.json`](.claude/settings.example.json).
- `kernel-graph` is an optional external component; this repository contains neither the Linux kernel source nor its database.
- Treat source-query results as authoritative. Keep indirect calls and dynamic behavior that cannot be confirmed as items to verify.

## License

This repository does not currently declare an open-source license. Add an appropriate license before publishing, reusing, or redistributing it.
