#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const assert = require('assert');

const html = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');

function extractFunction(source, name) {
  const start = source.indexOf(`function ${name}(`);
  assert(start !== -1, `${name} should be defined in index.html`);
  const asyncPrefix = 'async ';
  const functionStart = source.slice(Math.max(0, start - asyncPrefix.length), start) === asyncPrefix
    ? start - asyncPrefix.length
    : start;
  const bodyStart = source.indexOf('{', start);
  let depth = 0;
  for (let i = bodyStart; i < source.length; i++) {
    if (source[i] === '{') depth++;
    if (source[i] === '}') depth--;
    if (depth === 0) return source.slice(functionStart, i + 1);
  }
  throw new Error(`Could not extract ${name}`);
}

let activeTab = 'graph';
let elements;
const fetchCalls = [];
const activatedTabs = [];
const renderCalls = [];

function createElement(initial = {}) {
  const el = {
    textContent: '',
    value: '',
    disabled: false,
    focused: false,
    className: '',
    attributes: {},
    classList: {
      values: new Set(),
      contains(name) {
        return this.values.has(name);
      },
      add(name) {
        this.values.add(name);
      },
      remove(name) {
        this.values.delete(name);
      },
      toggle(name, force) {
        const enabled = force === undefined ? !this.values.has(name) : Boolean(force);
        if (enabled) this.values.add(name);
        else this.values.delete(name);
        return enabled;
      },
    },
    focus() {
      this.focused = true;
    },
    setAttribute(name, value) {
      this.attributes[name] = String(value);
    },
    ...initial,
  };
  return el;
}

function resetDom() {
  fetchCalls.length = 0;
  activatedTabs.length = 0;
  renderCalls.length = 0;
  sandbox.nextFetchResponse = null;
  sandbox.nextFetchResponses = null;
  elements = {
    'quicknotes': createElement(),
    'quick-note-content': createElement({ value: ' draft ' }),
    'quick-note-error': createElement(),
    'quick-note-save': createElement(),
    'quick-note-panel': createElement(),
    'quick-note-toast': createElement(),
    'quick-note-recent': createElement(),
    'quick-note-recent-list': createElement(),
  };
  elements['quick-note-panel'].classList.add('open');
  activeTab = 'graph';
}

const sandbox = {
  activatedTabs,
  renderCalls,
  fetch: async (url, options) => {
    fetchCalls.push({ url, options });
    if (sandbox.nextFetchResponses && sandbox.nextFetchResponses.length) {
      return sandbox.nextFetchResponses.shift();
    }
    return sandbox.nextFetchResponse || {
      ok: true,
      json: async () => ({}),
    };
  },
  setTimeout: () => 1,
  clearTimeout: () => {},
  activateDashboardTab: tabName => {
    activatedTabs.push(tabName);
    activeTab = tabName;
  },
  document: {
    getElementById(id) {
      return elements[id] || null;
    },
    querySelector(selector) {
      if (selector === '.tab.active') {
        return activeTab ? { dataset: { tab: activeTab } } : null;
      }
      return null;
    },
    querySelectorAll(selector) {
      if (selector === '.quick-note-type') return [];
      return [];
    },
  },
};

vm.createContext(sandbox);
vm.runInContext(`
let currentDocsFile = null;
let quickNotesData = { notes: [], counts: { total: 0, '问题': 0, '笔记': 0, '待整理': 0 } };
let quickNotesFilter = '全部';
let quickNoteType = '问题';
let quickNoteToastTimer = null;
${extractFunction(html, 'escapeHtml')}
${extractFunction(html, 'quickNotesCounts')}
${extractFunction(html, 'filteredQuickNotes')}
${extractFunction(html, 'setQuickNotesFilter')}
${extractFunction(html, 'renderQuickNotes')}
const realRenderQuickNotes = renderQuickNotes;
renderQuickNotes = function() {
  renderCalls.push('main');
  return realRenderQuickNotes();
};
${extractFunction(html, 'loadQuickNotes')}
${extractFunction(html, 'renderQuickNotesRecent')}
${extractFunction(html, 'openQuickNotesTab')}
${extractFunction(html, 'closeQuickNote')}
${extractFunction(html, 'getQuickNoteSource')}
${extractFunction(html, 'buildQuickNotePayload')}
${extractFunction(html, 'saveQuickNote')}
${extractFunction(html, 'showQuickNoteToast')}
this.setQuickNotesData = value => { quickNotesData = value; };
this.getQuickNotesFilter = () => quickNotesFilter;
this.quickNotesCounts = quickNotesCounts;
this.filteredQuickNotes = filteredQuickNotes;
this.setQuickNotesFilter = setQuickNotesFilter;
this.renderQuickNotes = renderQuickNotes;
this.loadQuickNotes = loadQuickNotes;
this.renderQuickNotesRecent = renderQuickNotesRecent;
this.openQuickNotesTab = openQuickNotesTab;
this.setCurrentDocsFile = value => { currentDocsFile = value; };
this.setQuickNoteTypeValue = value => { quickNoteType = value; };
this.getQuickNoteSource = getQuickNoteSource;
this.buildQuickNotePayload = buildQuickNotePayload;
this.saveQuickNote = saveQuickNote;
`, sandbox);
const plain = value => JSON.parse(JSON.stringify(value));

(async () => {
  assert(
    html.includes('<div class="tab" data-tab="quicknotes">随时记</div>'),
    'quick notes tab should be present after questions'
  );
  assert(
    html.indexOf('<div id="questions" class="panel"></div>') !== -1 &&
      html.indexOf('<div id="questions" class="panel"></div>') <
      html.indexOf('<div id="quicknotes" class="panel"></div>'),
    'quick notes panel should be present after questions panel'
  );

  resetDom();
  sandbox.setQuickNotesData({
    counts: { total: 2, '问题': 1, '笔记': 1, '待整理': 0 },
    notes: [
      {
        date: '2026-08-08',
        time: '15:40',
        type: '问题',
        source: 'docs · sched/cfs_rq.md',
        status: 'inbox',
        content: '<script>alert(1)</script>\\nsecond line',
        file: 'notes/inbox/2026-08-08.md',
      },
      {
        date: '2026-08-08',
        time: '15:39',
        type: '笔记',
        source: 'graph',
        status: 'inbox',
        content: '笔记内容',
        file: 'notes/inbox/2026-08-08.md',
      },
    ],
  });
  sandbox.renderQuickNotes();
  const quickNotesHtml = elements.quicknotes.innerHTML;
  assert(quickNotesHtml.includes('共 2 条'));
  assert(quickNotesHtml.includes('问题 1'));
  assert(quickNotesHtml.includes('笔记 1'));
  assert(
    quickNotesHtml.indexOf('15:40') < quickNotesHtml.indexOf('15:39'),
    'notes should render newest-first in provided order'
  );
  assert(quickNotesHtml.includes('&lt;script&gt;alert(1)&lt;/script&gt;'));
  assert(!quickNotesHtml.includes('<script>alert(1)</script>'));
  assert(quickNotesHtml.includes('second line'));
  assert(quickNotesHtml.includes('notes/inbox/2026-08-08.md'));

  sandbox.setQuickNotesFilter('笔记');
  assert.strictEqual(sandbox.getQuickNotesFilter(), '笔记');
  assert.strictEqual(plain(sandbox.filteredQuickNotes()).length, 1);
  assert.strictEqual(plain(sandbox.filteredQuickNotes())[0].content, '笔记内容');
  assert(elements.quicknotes.innerHTML.includes('笔记内容'));
  assert(!elements.quicknotes.innerHTML.includes('&lt;script&gt;alert(1)&lt;/script&gt;'));

  resetDom();
  activeTab = 'docs';
  sandbox.setCurrentDocsFile('sched/schedule.md');
  assert.strictEqual(
    sandbox.getQuickNoteSource(),
    'docs · sched/schedule.md'
  );

  activeTab = 'graph';
  sandbox.setCurrentDocsFile('sched/schedule.md');
  assert.strictEqual(sandbox.getQuickNoteSource(), 'graph');

  assert.deepStrictEqual(
    plain(sandbox.buildQuickNotePayload('问题', '  text  ')),
    { type: '问题', content: 'text', source: 'graph' }
  );

  resetDom();
  elements['quick-note-content'].value = '   ';
  await sandbox.saveQuickNote();
  assert.strictEqual(fetchCalls.length, 0);
  assert.strictEqual(elements['quick-note-error'].textContent, '请输入要保存的内容');
  assert.strictEqual(elements['quick-note-content'].value, '   ');

  resetDom();
  sandbox.setQuickNoteTypeValue('笔记');
  elements['quick-note-content'].value = '  saved text  ';
  sandbox.nextFetchResponses = [
    { ok: true, json: async () => ({ ok: true }) },
    {
      ok: true,
      json: async () => ({
        counts: { total: 1, '问题': 0, '笔记': 1, '待整理': 0 },
        notes: [
          { id: 'n6', date: '2026-08-08', time: '16:10', type: '笔记', source: 'graph', status: 'inbox', content: 'saved text', file: 'notes/inbox/2026-08-08.md' },
        ],
      }),
    },
  ];
  await sandbox.saveQuickNote();
  assert.strictEqual(fetchCalls.length, 2);
  assert.strictEqual(fetchCalls[0].url, '/api/quick-notes');
  assert.strictEqual(fetchCalls[1].url, '/api/quick-notes');
  assert.strictEqual(fetchCalls[1].options, undefined);
  assert.deepStrictEqual(
    JSON.parse(fetchCalls[0].options.body),
    { type: '笔记', content: 'saved text', source: 'graph' }
  );
  assert(elements['quick-note-recent-list'].innerHTML.includes('saved text'));
  assert.strictEqual(elements['quick-note-content'].value, '');
  assert.strictEqual(elements['quick-note-panel'].classList.contains('open'), false);
  assert.strictEqual(elements['quick-note-save'].disabled, false);

  resetDom();
  sandbox.setQuickNotesData({
    notes: [
      { id: 'n1', date: '2026-08-08', time: '15:42', type: '问题', source: 'docs', status: 'inbox', content: 'one', file: 'notes/inbox/2026-08-08.md' },
      { id: 'n2', date: '2026-08-08', time: '15:41', type: '笔记', source: 'graph', status: 'inbox', content: '<b>two</b>', file: 'notes/inbox/2026-08-08.md' },
      { id: 'n3', date: '2026-08-08', time: '15:40', type: '待整理', source: 'overview', status: 'inbox', content: 'three', file: 'notes/inbox/2026-08-08.md' },
      { id: 'n4', date: '2026-08-08', time: '15:39', type: '问题', source: 'nodes', status: 'inbox', content: 'four', file: 'notes/inbox/2026-08-08.md' },
    ],
    counts: { total: 4, '问题': 2, '笔记': 1, '待整理': 1 },
  });
  sandbox.renderQuickNotesRecent();
  const recentHtml = elements['quick-note-recent-list'].innerHTML;
  assert(recentHtml.includes('one'));
  assert(recentHtml.includes('&lt;b&gt;two&lt;/b&gt;'));
  assert(!recentHtml.includes('<b>two</b>'));
  assert(recentHtml.includes('three'));
  assert(!recentHtml.includes('four'));

  resetDom();
  sandbox.setQuickNotesData({
    notes: [],
    counts: { total: 0, '问题': 0, '笔记': 0, '待整理': 0 },
  });
  sandbox.renderQuickNotesRecent();
  assert(elements['quick-note-recent-list'].innerHTML.includes('暂无记录'));
  assert(!elements['quick-note-recent-list'].innerHTML.includes('docs-empty'));

  sandbox.openQuickNotesTab();
  assert.strictEqual(elements['quick-note-panel'].classList.contains('open'), false);
  assert.deepStrictEqual(activatedTabs, ['quicknotes']);
  assert(renderCalls.includes('main'));

  resetDom();
  sandbox.setQuickNotesFilter('全部');
  sandbox.nextFetchResponse = {
    ok: true,
    json: async () => ({
      counts: { total: 1, '问题': 1, '笔记': 0, '待整理': 0 },
      notes: [
        { id: 'n5', date: '2026-08-08', time: '16:00', type: '问题', source: 'docs', status: 'inbox', content: 'loaded', file: 'notes/inbox/2026-08-08.md' },
      ],
    }),
  };
  await sandbox.loadQuickNotes();
  assert.strictEqual(fetchCalls.length, 1);
  assert.strictEqual(fetchCalls[0].url, '/api/quick-notes');
  assert.strictEqual(plain(sandbox.filteredQuickNotes())[0].content, 'loaded');
  assert(renderCalls.includes('main'));
  assert(elements['quick-note-recent-list'].innerHTML.includes('loaded'));

  resetDom();
  sandbox.nextFetchResponse = {
    ok: false,
    status: 500,
    json: async () => ({ error: 'boom' }),
  };
  await sandbox.loadQuickNotes();
  assert(elements.quicknotes.innerHTML.includes('随时记加载失败'));
  assert(elements['quick-note-recent-list'].innerHTML.includes('加载失败'));
  assert(!elements['quick-note-recent-list'].innerHTML.includes('docs-empty'));

  resetDom();
  sandbox.setQuickNoteTypeValue('笔记');
  elements['quick-note-content'].value = '  saved then refresh fails  ';
  sandbox.nextFetchResponses = [
    { ok: true, json: async () => ({ ok: true }) },
    {
      ok: false,
      status: 500,
      json: async () => ({ error: 'refresh failed' }),
    },
  ];
  await sandbox.saveQuickNote();
  assert.strictEqual(fetchCalls.length, 2);
  assert.strictEqual(elements['quick-note-content'].value, '');
  assert.strictEqual(elements['quick-note-panel'].classList.contains('open'), false);
  assert.strictEqual(elements['quick-note-toast'].textContent, '已保存');
  assert(elements['quick-note-toast'].className.includes('success'));
  assert.strictEqual(elements['quick-note-save'].disabled, false);
  assert.strictEqual(elements['quick-note-error'].textContent, '');
  assert(elements['quick-note-recent-list'].innerHTML.includes('加载失败'));
  assert(!elements['quick-note-recent-list'].innerHTML.includes('docs-empty'));

  resetDom();
  sandbox.setQuickNoteTypeValue('问题');
  elements['quick-note-content'].value = '  server draft  ';
  sandbox.nextFetchResponse = {
    ok: false,
    status: 400,
    json: async () => ({ error: '随时记内容为空' }),
  };
  await sandbox.saveQuickNote();
  assert.strictEqual(fetchCalls.length, 1);
  assert.strictEqual(elements['quick-note-error'].textContent, '随时记内容为空');
  assert.strictEqual(elements['quick-note-content'].value, '  server draft  ');
  assert.strictEqual(elements['quick-note-save'].disabled, false);

  console.log('quick note ui helpers ok');
})().catch(err => {
  console.error(err);
  process.exit(1);
});
