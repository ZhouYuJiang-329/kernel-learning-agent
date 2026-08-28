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
${extractFunction(html, 'parseFocusEntry')}
${extractFunction(html, 'truncateFocusBody')}
${extractFunction(html, 'getSubsystemProgressLabel')}
${extractFunction(html, 'escapeOverviewHtml')}
${extractFunction(html, 'overviewNumber')}
${extractFunction(html, 'renderOverview')}
this.parseFocusEntry = parseFocusEntry;
this.truncateFocusBody = truncateFocusBody;
this.getSubsystemProgressLabel = getSubsystemProgressLabel;
this.escapeOverviewHtml = escapeOverviewHtml;
this.overviewNumber = overviewNumber;
this.renderOverview = renderOverview;
`, sandbox);
const plain = value => JSON.parse(JSON.stringify(value));

assert.deepStrictEqual(
  plain(sandbox.parseFocusEntry('**调度器进度**：proxy-exec 已系统分析')),
  { title: '调度器进度', body: 'proxy-exec 已系统分析' }
);

assert.deepStrictEqual(
  plain(sandbox.parseFocusEntry('MPAM 进度: resctrl 已完成')),
  { title: 'MPAM 进度', body: 'resctrl 已完成' }
);

assert.deepStrictEqual(
  plain(sandbox.parseFocusEntry('没有分隔符的焦点')),
  { title: '当前学习焦点', body: '没有分隔符的焦点' }
);
assert.deepStrictEqual(
  plain(sandbox.parseFocusEntry('')),
  { title: '当前学习焦点', body: '' }
);

assert.strictEqual(sandbox.truncateFocusBody('短文本', 10), '短文本');
assert.strictEqual(
  sandbox.truncateFocusBody('abcdefghijklmnopqrstuvwxyz', 10),
  'abcdefghij…'
);

assert.strictEqual(
  sandbox.getSubsystemProgressLabel('unclassified', { mastered: 2, exploring: 0, unknown: 0, total: 2 }),
  '暂存整理'
);
assert.strictEqual(
  sandbox.getSubsystemProgressLabel('sched', { mastered: 10, exploring: 20, unknown: 5, total: 35 }),
  '主线推进中'
);
assert.strictEqual(
  sandbox.getSubsystemProgressLabel('perf', { mastered: 0, exploring: 0, unknown: 12, total: 12 }),
  '基础建设中'
);
assert.strictEqual(
  sandbox.getSubsystemProgressLabel('mm', { mastered: 1, exploring: 2, unknown: 10, total: 13 }),
  '基础建设中'
);
assert.strictEqual(
  sandbox.getSubsystemProgressLabel('mpam', { mastered: 80, exploring: 10, unknown: 2, total: 92 }),
  '稳定沉淀'
);
assert.strictEqual(
  sandbox.getSubsystemProgressLabel('io', { mastered: 4, exploring: 2, unknown: 1, total: 7 }),
  '持续推进'
);

const overviewRoot = { innerHTML: '' };
sandbox.document = {
  getElementById(id) {
    assert.strictEqual(id, 'overview');
    return overviewRoot;
  }
};

const longFocusBody = 'x'.repeat(261);
sandbox.renderOverview({
  focus: [
    `**调度器进度**：${longFocusBody}`,
    'MPAM 进度: resctrl 已完成'
  ],
  knowledge_map: {
    all_nodes: [
      { status: 'mastered' },
      { status: 'exploring' },
      { status: 'unknown' },
      { status: 'exploring' }
    ],
    subsystems: { sched: {}, mpam: {} },
    stats: {
      sched: { mastered: 1, exploring: 2, unknown: 1, questioned: 1, total: 5, avg_confidence: 80.6 },
      mpam: { mastered: 3, exploring: 1, unknown: 0, total: 4, avg_confidence: 0 }
    }
  },
  questions: {
    counts: { CRITICAL: 2, MEDIUM: 3, LOW: 4, resolved: 5 }
  }
});

assert.match(overviewRoot.innerHTML, /class="overview-focus-layout"/);
assert.match(overviewRoot.innerHTML, /class="focus-card"/);
assert.match(overviewRoot.innerHTML, /当前学习焦点/);
assert.match(overviewRoot.innerHTML, /调度器进度/);
assert.match(overviewRoot.innerHTML, /<summary>完整描述<\/summary>/);
assert.match(overviewRoot.innerHTML, /class="attention-card"/);
assert.match(overviewRoot.innerHTML, /优先处理 CRITICAL 问题/);
assert.match(overviewRoot.innerHTML, /<div class="attention-stat-value">2<\/div>/);
assert.match(overviewRoot.innerHTML, /class="cards overview-metrics"/);
assert.match(overviewRoot.innerHTML, /<div class="card-value">50%<\/div>/);
assert.match(overviewRoot.innerHTML, /其他学习焦点/);
assert.match(overviewRoot.innerHTML, /学习进度分块/);
assert.match(overviewRoot.innerHTML, /class="progress-block-grid"/);
assert.match(overviewRoot.innerHTML, /class="progress-block-name">sched<\/div>/);
assert.match(overviewRoot.innerHTML, /主线推进中/);
assert.match(overviewRoot.innerHTML, /掌握 1/);
assert.match(overviewRoot.innerHTML, /探索 2/);
assert.match(overviewRoot.innerHTML, /未知 1/);
assert.match(overviewRoot.innerHTML, /疑问 1/);
assert.match(overviewRoot.innerHTML, /background:var\(--questioned\)/);
assert.match(overviewRoot.innerHTML, /均 80.6/);

overviewRoot.innerHTML = '';
sandbox.renderOverview({
  focus: [
    '**<img src=x onerror=alert(1)>**：<script>alert(1)</script>',
    '<img src=x onerror=alert(1)>: <script>alert(1)</script>'
  ],
  knowledge_map: {
    all_nodes: [],
    subsystems: { unsafe: {} },
    stats: {
      '<script>alert(2)</script>': {
        mastered: '<script>alert(3)</script>',
        exploring: 0,
        unknown: 1,
        total: 1,
        avg_confidence: '<img src=x onerror=alert(3)>'
      }
    }
  },
  questions: { counts: { CRITICAL: '<script>alert(4)</script>' } }
});

assert.match(overviewRoot.innerHTML, /&lt;img src=x onerror=alert\(1\)&gt;/);
assert.match(overviewRoot.innerHTML, /&lt;script&gt;alert\(1\)&lt;\/script&gt;/);
assert.match(overviewRoot.innerHTML, /&lt;script&gt;alert\(2\)&lt;\/script&gt;/);
assert.doesNotMatch(overviewRoot.innerHTML, /<img\b/i);
assert.doesNotMatch(overviewRoot.innerHTML, /<script\b/i);
assert.doesNotMatch(overviewRoot.innerHTML, /NaN/);
assert.match(overviewRoot.innerHTML, /<div class="attention-stat-value">0<\/div>/);
assert.match(overviewRoot.innerHTML, /掌握 0/);

overviewRoot.innerHTML = '';
sandbox.renderOverview({});
assert.match(overviewRoot.innerHTML, /暂无焦点记录/);
assert.doesNotMatch(overviewRoot.innerHTML, /NaN/);

console.log('overview focus helpers ok');
