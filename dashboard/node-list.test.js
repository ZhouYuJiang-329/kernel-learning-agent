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
${extractFunction(html, 'findNodeDocs')}
${extractFunction(html, 'filterKnowledgeNodes')}
this.findNodeDocs = findNodeDocs;
this.filterKnowledgeNodes = filterKnowledgeNodes;
`, sandbox);

const learnDocs = {
  sched: [
    { name: 'enqueue_task_fair', path: 'sched/enqueue_task_fair.md', content: '# enqueue_task_fair\nmain note' },
    { name: 'schedule', path: 'sched/schedule.md', content: 'mentions enqueue_task_fair and pick_next_task_fair' },
    { name: 'sched_terms', path: 'sched/synthesis/sched_terms.md', content: 'vruntime glossary' },
  ],
  mpam: [
    { name: 'configfs', path: 'mpam/configfs.md', content: 'mentions enqueue_task_fair only as unrelated text' },
  ],
};
const plain = value => JSON.parse(JSON.stringify(value));

const exactMatches = sandbox.findNodeDocs(
  { name: 'enqueue_task_fair', subsystem: 'sched' },
  learnDocs
);
assert.deepStrictEqual(
  plain(exactMatches.map(f => f.path)),
  ['sched/enqueue_task_fair.md', 'sched/schedule.md']
);

const contentMatches = sandbox.findNodeDocs(
  { name: 'pick_next_task_fair', subsystem: 'sched' },
  learnDocs
);
assert.deepStrictEqual(
  plain(contentMatches.map(f => f.path)),
  ['sched/schedule.md']
);

const allNodes = [
  { name: 'enqueue_task_fair', subsystem: 'sched', status: 'exploring', type: 'function', note: 'CFS enqueue', internal_doc: '-' },
  { name: 'sched_entity', subsystem: 'sched', status: 'mastered', type: 'struct', note: 'vruntime carrier', internal_doc: 'wiki' },
  { name: 'configfs', subsystem: 'mpam', status: 'unknown', type: 'function', note: 'mount path', internal_doc: '-' },
];

assert.deepStrictEqual(
  plain(sandbox.filterKnowledgeNodes(allNodes, 'all', 'sched', 'vruntime').map(n => n.name)),
  ['sched_entity']
);
assert.deepStrictEqual(
  plain(sandbox.filterKnowledgeNodes(allNodes, 'unknown', 'all', 'config').map(n => n.name)),
  ['configfs']
);

console.log('node list helpers ok');
