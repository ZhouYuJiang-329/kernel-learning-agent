# Kernel Learning Dashboard Design

## Product Character

Kernel Learning Dashboard is a technical learning workspace for Linux kernel study. It should feel calm, precise, and durable for long reading sessions. The interface is a work surface, not a marketing page.

Design references:
- Linear: precise spacing, restrained controls, focused workflows.
- Mintlify: readable technical documentation and clean search.
- Vercel: neutral surfaces, crisp typography, quiet hierarchy.
- GitHub Docs: familiar engineering density and code-oriented patterns.

## Visual Principles

- Prefer high information density with clear hierarchy.
- Keep navigation persistent and compact.
- Make "current learning state" visible immediately.
- Use color semantically, not decoratively.
- Optimize reading surfaces for long Chinese and code-heavy notes.
- Avoid ornamental gradients, large hero sections, and brand imitation.

## Color System

Base:
- `--bg`: `#f7f8fa`, application background.
- `--surface`: `#ffffff`, primary cards and panels.
- `--surface-subtle`: `#f2f4f7`, secondary controls and code backgrounds.
- `--surface-raised`: `#ffffff`, floating menus and modals.
- `--border`: `#d8dee7`, ordinary boundaries.
- `--border-subtle`: `#e9edf3`, table row and internal dividers.
- `--text`: `#1b1f24`, primary text.
- `--muted`: `#687180`, secondary text.
- `--faint`: `#8a94a3`, metadata text.
- `--accent`: `#2563eb`, focused action and active navigation.

Learning states:
- `mastered`: green, stable success.
- `exploring`: amber, active learning.
- `unknown`: gray, unvisited material.
- `questioned`: red, blocked or unresolved.
- `note`: violet, extracted from notes but not yet in knowledge map.

## Typography

- Use system UI for interface text.
- Use `ui-monospace`, `SFMono-Regular`, `Menlo`, `Consolas`, monospace for functions, code, commands, and graph search.
- Avoid negative letter spacing.
- Use uppercase labels only for compact metadata, with subtle spacing.
- Long-form documents should use 16px body text, 1.75 line-height, and a max readable width when possible.

## Layout

- Header height should be compact and sticky so the learning context remains available.
- Tabs should behave like a tool navigation rail: compact pills, horizontal overflow on small screens.
- Panels use a constrained-but-wide workspace width.
- Graph view can use full workspace width because canvas and tables need space.
- Cards use 8px radius or less.
- Avoid nested decorative cards. Cards are for actual repeated information units.

## Components

Cards:
- White surface, subtle border, small shadow only when it helps separate stacked surfaces.
- Numeric cards should have strong value text and quiet captions.

Buttons and filters:
- Compact pill controls are acceptable for filters and modes.
- Active state uses accent border and faint accent fill.
- Hover state should be visible but restrained.

Tables:
- Keep tables dense.
- Use subtle row separators.
- Use row hover to support scanning.

Documentation:
- Documentation content is a reading surface, not a dashboard card.
- Use white background, strong headings, readable paragraphs, and distinct code blocks.

Graph:
- Canvas background should be slightly off-white.
- Keep legends compact and semi-floating.
- Search and graph tools must wrap cleanly without overlapping.

## Responsive Behavior

- Header stacks metadata under the title on narrow screens.
- Tabs remain horizontally scrollable.
- Panel padding reduces on mobile.
- Graph toolbar wraps into multiple rows.
- Search boxes become full width on mobile.
- Tables and code blocks may scroll horizontally rather than squeezing text.

## Do

- Preserve the existing learning state colors.
- Preserve current information architecture.
- Use restrained contrast to reduce fatigue.
- Make active tabs and selected filters unambiguous.
- Keep code/function names readable.

## Don't

- Do not copy a specific brand identity.
- Do not add marketing hero sections.
- Do not introduce decorative blobs, orbs, or large gradients.
- Do not make the dashboard one-note blue.
- Do not reduce information density so much that repeated daily use becomes slower.
