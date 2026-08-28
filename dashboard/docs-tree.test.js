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
${extractFunction(html, 'formatDocsOptionLabel')}
${extractFunction(html, 'buildDocsFileTree')}
${extractFunction(html, 'buildDocsHeadingItems')}
this.formatDocsOptionLabel = formatDocsOptionLabel;
this.buildDocsFileTree = buildDocsFileTree;
this.buildDocsHeadingItems = buildDocsHeadingItems;
`, sandbox);

const files = [
  { path: 'mpam/configfs.md', name: 'configfs' },
  { path: 'mpam/resctrl/rdtgroup.md', name: 'rdtgroup' },
  { path: 'mpam/resctrl/alloc_rmid.md', name: 'alloc_rmid' },
  { path: 'mpam/hardware/mpam_concepts.md', name: 'mpam_concepts' },
  { path: 'mpam/slc_full_step/full_step.md', name: 'full_step' },
];

assert.strictEqual(
  sandbox.formatDocsOptionLabel({ path: 'mpam/configfs.md', name: 'configfs' }),
  'configfs'
);
assert.strictEqual(
  sandbox.formatDocsOptionLabel({ path: 'mpam/resctrl/rdtgroup.md', name: 'rdtgroup' }),
  'resctrl / rdtgroup'
);

const tree = sandbox.buildDocsFileTree(files);
const plain = value => JSON.parse(JSON.stringify(value));

assert.deepStrictEqual(
  plain(tree.files.map(file => file.name)),
  ['configfs']
);
assert.deepStrictEqual(
  plain(Object.keys(tree.dirs)),
  ['hardware', 'resctrl', 'slc_full_step']
);
assert.deepStrictEqual(
  plain(tree.dirs.resctrl.files.map(file => file.name)),
  ['alloc_rmid', 'rdtgroup']
);
assert.strictEqual(tree.dirs.resctrl.files[1].path, 'mpam/resctrl/rdtgroup.md');
assert.strictEqual(tree.dirs.slc_full_step.files[0].name, 'full_step');

const headings = sandbox.buildDocsHeadingItems(`# Overview

intro

## Details

\`\`\`
# ignored
## also ignored
\`\`\`

### Details

#### Not shown

## Details
`);

assert.deepStrictEqual(
  plain(headings),
  [
    { level: 1, text: 'Overview', id: 'doc-heading-1-overview' },
    { level: 2, text: 'Details', id: 'doc-heading-2-details' },
    { level: 3, text: 'Details', id: 'doc-heading-3-details' },
    { level: 2, text: 'Details', id: 'doc-heading-4-details' },
  ]
);

console.log('docs tree selector data ok');
