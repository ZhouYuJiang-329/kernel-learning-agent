#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const assert = require('assert');

const html = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');

function extractFunction(source, name) {
  const start = source.indexOf(`function ${name}(`);
  assert(start !== -1, `${name} should be defined in index.html`);
  const bodyStart = source.indexOf('{', start);
  let depth = 0;
  for (let i = bodyStart; i < source.length; i++) {
    if (source[i] === '{') depth++;
    if (source[i] === '}') depth--;
    if (depth === 0) return source.slice(start, i + 1);
  }
  throw new Error(`Could not extract ${name}`);
}

const sandbox = {};
vm.createContext(sandbox);
vm.runInContext(`
${extractFunction(html, 'escapeHtml')}
${extractFunction(html, 'escapeDocsHtml')}
${extractFunction(html, 'normalizeDocsMermaidSource')}
${extractFunction(html, 'renderDocsMermaid')}
this.renderDocsMermaid = renderDocsMermaid;
`, sandbox);

const rendered = sandbox.renderDocsMermaid(
  '<h1>avg_vruntime</h1><pre><code class="language-mermaid">flowchart LR\nA --&gt; B\n</code></pre>'
);

assert(rendered.includes('class="mermaid-figure"'));
assert(rendered.includes('class="mermaid-toolbar"'));
assert(rendered.includes('class="mermaid-mode-switch"'));
assert(rendered.includes('data-mermaid-mode="diagram"'));
assert(rendered.includes('data-mermaid-mode="source"'));
assert(rendered.includes('class="mermaid-diagram-pane"'));
assert(rendered.includes('class="mermaid-source-pane"'));
assert(rendered.includes('data-mermaid-action="fullscreen"'));
assert(rendered.includes('data-mermaid-action="reset"'));
assert(rendered.includes('<div class="mermaid">flowchart LR\nA --&gt; B\n</div>'));
assert(rendered.includes('<code>flowchart LR\nA --&amp;gt; B\n</code>'));
assert(!rendered.includes('<code class="language-mermaid">'));
assert(rendered.includes('<h1>avg_vruntime</h1>'));

const renderedWithEscapedNewline = sandbox.renderDocsMermaid(
  '<pre><code class="language-mermaid">flowchart TD\nA["avg_vruntime(cfs_rq)\\n得到队列平均虚拟时间 V"] --> B\n</code></pre>'
);

assert(renderedWithEscapedNewline.includes('avg_vruntime(cfs_rq)<br/>得到队列平均虚拟时间 V'));
assert(renderedWithEscapedNewline.includes('avg_vruntime(cfs_rq)\\n得到队列平均虚拟时间 V'));

console.log('docs mermaid rendering ok');
