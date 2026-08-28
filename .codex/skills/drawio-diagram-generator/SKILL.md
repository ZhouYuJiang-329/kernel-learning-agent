---
name: drawio-diagram-generator
description: >
  Generate .drawio diagram files by analyzing source code, log files, test scripts, or system descriptions.
  Use this skill whenever the user wants to visualize code, system behavior, or processes as a diagram —
  including when they say "画图", "生成图", "draw", "diagram", "visualize", "帮我画", "生成一个图",
  "flowchart", "调用链", "架构图", "状态机", or similar phrasing in any language.
  Also triggers when the user shares code/logs AND asks "what's happening" or "explain this flow" —
  in those cases, proactively offer diagram recommendations.
  The skill handles the full workflow: read content → recommend diagram types → user selects →
  generate valid draw.io XML → validate before delivering.
---

## What this skill does

Turn code, logs, and scripts into `.drawio` diagram files that open directly in draw.io (desktop or web).

The workflow has four steps:

1. **Read** the provided content (source files, log snippets, script steps)
2. **Recommend** 2–3 diagram types suited to what was shared — unless the user already specified one
3. **Generate** a complete `.drawio` XML file after the user picks a type
4. **Validate** the XML before handing it over

---

## Step 1 — Read and understand the content

Before recommending or generating anything, read the relevant files thoroughly:
- Source code → understand the call hierarchy, state transitions, data flow
- Log files → identify sequences of events, actors, timing
- Test scripts → extract setup steps, actions, assertions

Build a mental model of what's happening before deciding what diagram type would best explain it.

---

## Step 2 — Recommend diagram types (skip if user already specified)

If the user has NOT named a specific diagram type, present **2–3 recommendations** based on what you found.

Format them as a numbered list, one per line, with a one-sentence rationale:

```
根据代码内容，我推荐以下图类型，请选择一个：

1. **函数调用图** — 代码中有明确的层级调用链（A→B→C），适合展示执行路径
2. **状态机图** — 存在明显的状态转换（RUNNING→BLOCKED→LIVELOCK），适合展示生命周期
3. **时序图** — 多个线程/进程交互，适合展示跨角色的时间顺序
```

**Choosing which types to recommend:**

| Content type | Usually good choices |
|---|---|
| Function calls / call stack | Call flow, Sequence |
| State flags / transitions | State machine |
| Multiple threads/processes interacting | Sequence, Swimlane |
| System layers (user space / kernel) | Architecture |
| Build/CI pipeline steps | Flowchart |
| Module dependencies | Architecture, Dependency graph |
| Log event sequences | Sequence, Timeline |

Only recommend types that genuinely fit — don't list all types every time.

Wait for the user's selection before generating.

---

## Step 3 — Generate the .drawio file

### Output location

Always save to `<current_working_directory>/img/<filename>.drawio`.
Create the `img/` directory if it doesn't exist (use the Write tool, not Bash mkdir).

### File naming

Use a descriptive snake_case name that reflects the content:
- `call_flow.drawio`, `livelock_sequence.drawio`, `kernel_arch.drawio`
- NOT: `diagram.drawio`, `output.drawio`

### draw.io XML structure

Every file must be valid draw.io XML. Use this as the outer wrapper:

```xml
<mxGraphModel dx="1600" dy="900" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="1654" pageHeight="1169" math="0" shadow="0">
  <root>
    <mxCell id="0"/>
    <mxCell id="1" parent="0"/>
    <!-- your cells here -->
  </root>
</mxGraphModel>
```

**Critical rules for valid XML:**
- Every `<mxCell>` must have a unique `id` (use short strings like `"n1"`, `"e1"`, `"label_a"`)
- All edges need `edge="1"` and at least `source` or `target` pointing to valid cell IDs
- All vertices need `vertex="1"` and a `<mxGeometry>` child
- Geometry `x`/`y`/`width`/`height` must all be numbers (no units, no `px`)
- Special characters in `value=""` must be XML-escaped: `&` → `&amp;`, `<` → `&lt;`, `>` → `&gt;`, `"` inside value → `&quot;`
- Never reuse an ID — if you have a loop arrow, give it a fresh ID

### Layout guidance

- **Flowchart**: top-to-bottom, ~800px wide, nodes at 120px height intervals
- **Sequence**: vertical time axis, actors as columns spaced 200px apart
- **State machine**: center-weighted, spread states to avoid overlapping edges
- **Architecture**: swimlane boxes as outer containers, components inside
- **Call flow**: left-to-right OR top-to-bottom, group by thread/module with swimlanes

Leave at least 20px margin between nodes. Edge labels should be short (≤ 5 words).

**Viewport constraint (applies to every diagram type):** keep all elements within a single page — x in 0–800, y in 0–600. Containers (swimlanes, cloud boxes) max 700×550. Start from margins like x=40, y=40 and keep elements grouped closely rather than sprawling. If content genuinely doesn't fit, prefer a grid/stacked layout over shrinking below readability — never let the diagram spill across a page-break line.

### Using icon/shape libraries (AWS, Azure, GCP, K8s, BPMN, etc.)

When a diagram calls for branded or domain icons — cloud providers, networking gear, BPMN, Material Design, UML-adjacent business shapes — **never guess the `mxgraph.*` shape name or style syntax**. A wrong guess silently renders as a blank/broken box.

Instead:
1. Check `references/shape-libraries/README.md` in this skill's directory — it's an index of 30+ libraries (aws4, azure2, gcp2, alibaba_cloud, kubernetes, cisco19, bpmn, material_design, android, sap, electrical, floorplan, webicons, etc.) with shape counts and style prefixes.
2. Read the specific library file, e.g. `references/shape-libraries/aws4.md`, to get the exact shape names and usage template for that library.
3. Use the shape name and style pattern exactly as documented (e.g. AWS: `style="shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.{shape};..."`).

If the requested icon/library isn't in `references/shape-libraries/`, fall back to a plain labeled rectangle rather than inventing shape syntax.

### Edge routing rules (avoid overlapping/crossing lines)

Before generating edges, plan layout so shapes sit in clear columns/rows spaced 150–200px apart — this creates routing channels and makes most of the rules below automatic.

1. **Two edges between the same pair of nodes must exit/enter at different points** — e.g. first edge `exitY=0.3;entryY=0.3`, second `exitY=0.7;entryY=0.7`. Never let both use `0.5`.
2. **Bidirectional pairs (A↔B) use opposite sides** — A→B exits right (`exitX=1`) enters left (`entryX=0`); B→A exits left (`exitX=0`) enters right (`entryX=1`).
3. **Always set `exitX`, `exitY`, `entryX`, `entryY` explicitly** in the edge style — don't rely on automatic routing for anything but the simplest diagrams.
4. **Route around obstacles** — if any shape sits between source and target, add 1–3 `<mxPoint>` waypoints (as an `<Array as="points">` inside `<mxGeometry>`) that go around the diagram's perimeter (above, below, or to the side) with 20–30px clearance. Never let a line visually cross a shape's bounding box.
5. **Avoid corner connection points** — don't use both X and Y at 0 or 1 (e.g. `entryX=1;entryY=1`) since it looks unnatural. Prefer the side facing the flow direction: top-to-bottom flow exits bottom (`exitY=1`) / enters top (`entryY=0`); left-to-right exits right (`exitX=1`) / enters left (`entryX=0`).

Waypoint example (routing right of an obstacle, then up):
```xml
<mxCell id="e1" style="edgeStyle=orthogonalEdgeStyle;exitX=0.5;exitY=0;entryX=1;entryY=0.5;endArrow=classic;" edge="1" parent="1" source="hotfix" target="main">
  <mxGeometry relative="1" as="geometry">
    <Array as="points">
      <mxPoint x="750" y="80"/>
      <mxPoint x="750" y="150"/>
    </Array>
  </mxGeometry>
</mxCell>
```

Before finalizing, mentally trace each edge and ask: does it cross a shape that isn't its source/target? Do two edges share a path? Are any connection points at corners? Fix any "yes" before writing the file.

### Common cell styles

```
Rectangle:    rounded=1;whiteSpace=wrap;html=1;
Diamond:      rhombus;whiteSpace=wrap;html=1;
Ellipse:      ellipse;whiteSpace=wrap;html=1;
Swimlane:     swimlane;startSize=28;
Dashed edge:  dashed=1;endArrow=block;endFill=0;
Solid edge:   endArrow=block;endFill=1;
```

For color coding, use these fill/stroke pairs consistently within a diagram:
- Green (normal/success): `fillColor=#d5e8d4;strokeColor=#82b366`
- Blue (system/infra): `fillColor=#dae8fc;strokeColor=#6c8ebf`
- Yellow (wait/neutral): `fillColor=#fff2cc;strokeColor=#d6b656`
- Red (error/critical): `fillColor=#f8cecc;strokeColor=#b85450`
- Purple (external/data): `fillColor=#e1d5e7;strokeColor=#9673a6`
- Dark red (fatal): `fillColor=#b85450;strokeColor=#6c0000;fontColor=#ffffff`

---

## Step 4 — Validate before delivering

After writing the file, perform these checks mentally (no need to re-read the file):

1. **ID uniqueness** — did you accidentally reuse any `id` value across the whole file?
2. **No duplicate structural attributes** — no `mxCell` has `edge`, `parent`, `source`, `target`, or `vertex` specified twice.
3. **Edge references** — does every `source`/`target` in edges point to an existing vertex ID?
4. **Geometry completeness** — do all vertices have `x`, `y`, `width`, `height`, all as bare numbers (no `px` units)?
5. **XML escaping** — any unescaped `&`, `<`, `>` inside `value=""` attributes? (`&` → `&amp;`, `<` → `&lt;`, `>` → `&gt;`, `"` → `&quot;`)
6. **Only valid entities** — no invented entity names; only `&lt; &gt; &amp; &quot; &apos;` or numeric `&#NNN;`/`&#xHEX;` refs.
7. **No nested `<mxCell>`** — every mxCell is a sibling; none is nested inside another mxCell (other than its own `<mxGeometry>`/`<mxPoint>` children).
8. **No empty `id` attributes** and no CDATA wrapper around the document.
9. **Tag balance** — every opened tag has a matching close (or is self-closing); no stray/mismatched closing tags.
10. **Wrapper structure** — file starts with `<mxGraphModel>` and ends with `</mxGraphModel>`?

If you find an error, fix it in the file before reporting completion.

Tell the user:
```
✓ 文件已生成：img/<filename>.drawio
  验证通过：ID 唯一，边引用正确，XML 结构完整。
  打开方式：拖入 draw.io 网页版，或 Extras → Edit Diagram 粘贴 XML。
```

If you fixed something during validation, briefly mention what was corrected.

---

## Handling "generate multiple diagrams at once"

If the user asks for several diagrams in one request (e.g., "帮我画这5种图"):
- Generate all of them without stopping to ask between each one
- Name each file descriptively
- Validate all files
- Report a summary at the end

---

## How to open .drawio files

Remind the user once (not every time) if they seem unfamiliar:
- **Desktop**: File → Open
- **draw.io web**: drag and drop the file, or Extras → Edit Diagram to paste XML
- **VS Code**: install the "Draw.io Integration" extension
