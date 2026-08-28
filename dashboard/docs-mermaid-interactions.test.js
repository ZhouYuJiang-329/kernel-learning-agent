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

function makeElement(tag, className = '') {
  return {
    tagName: tag.toUpperCase(),
    className,
    dataset: {},
    style: {},
    listeners: {},
    children: [],
    parentElement: null,
    innerHTML: '',
    textContent: '',
    attributes: {},
    classList: {
      contains: name => String(this?.className || '').split(/\s+/).includes(name),
    },
    clientWidth: 300,
    clientHeight: 200,
    scrollWidth: 800,
    scrollHeight: 500,
    appendChild(child) {
      if (child.parentElement) {
        child.parentElement.children = child.parentElement.children.filter(item => item !== child);
      }
      child.parentElement = this;
      this.children.push(child);
      return child;
    },
    insertBefore(child, reference) {
      child.parentElement = this;
      const idx = this.children.indexOf(reference);
      if (idx === -1) this.children.push(child);
      else this.children.splice(idx, 0, child);
      return child;
    },
    remove() {
      if (!this.parentElement) return;
      this.parentElement.children = this.parentElement.children.filter(child => child !== this);
      this.parentElement = null;
    },
    setAttribute(name, value) {
      this.attributes[name] = String(value);
    },
    getAttribute(name) {
      return this.attributes[name] || '';
    },
    addEventListener(type, handler) {
      this.listeners[type] = handler;
    },
    cloneNode() {
      const clone = makeElement(this.tagName, this.className);
      clone.attributes = { ...this.attributes };
      clone.innerHTML = this.innerHTML;
      return clone;
    },
    getBoundingClientRect() {
      return { width: this.scrollWidth, height: this.scrollHeight };
    },
    querySelector(selector) {
      return this.querySelectorAll(selector)[0] || null;
    },
    querySelectorAll(selector) {
      const matches = [];
      const visit = node => {
        node.children.forEach(child => {
          if (selector === '.mermaid-figure' && child.className === 'mermaid-figure') matches.push(child);
          if (selector === '.mermaid-viewport' && child.className === 'mermaid-viewport') matches.push(child);
          if (selector === 'svg' && child.tagName === 'SVG') matches.push(child);
          if (selector === '[data-mermaid-action]' && child.dataset.mermaidAction) matches.push(child);
          if (selector === '[data-mermaid-mode]' && child.dataset.mermaidMode) matches.push(child);
          visit(child);
        });
      };
      visit(this);
      return matches;
    },
  };
}

const viewport = makeElement('div', 'mermaid-viewport');
const svg = makeElement('svg');
svg.setAttribute('viewBox', '0 0 800 500');
viewport.appendChild(svg);

const toolbar = makeElement('div', 'mermaid-toolbar');
['zoom-in', 'zoom-out', 'reset', 'fullscreen'].forEach(action => {
  const button = makeElement('button');
  button.dataset.mermaidAction = action;
  toolbar.appendChild(button);
});

const figure = makeElement('figure', 'mermaid-figure');
figure.dataset.mode = 'diagram';
const modeSwitch = makeElement('div', 'mermaid-mode-switch');
['diagram', 'source'].forEach((mode, idx) => {
  const button = makeElement('button', idx === 0 ? 'active' : '');
  button.dataset.mermaidMode = mode;
  modeSwitch.appendChild(button);
});
figure.appendChild(modeSwitch);
figure.appendChild(toolbar);
figure.appendChild(viewport);

const root = makeElement('div');
root.appendChild(figure);

const sourceOnlyFigure = makeElement('figure', 'mermaid-figure');
sourceOnlyFigure.dataset.mode = 'diagram';
const sourceOnlySwitch = makeElement('div', 'mermaid-mode-switch');
['diagram', 'source'].forEach((mode, idx) => {
  const button = makeElement('button', idx === 0 ? 'active' : '');
  button.dataset.mermaidMode = mode;
  sourceOnlySwitch.appendChild(button);
});
sourceOnlyFigure.appendChild(sourceOnlySwitch);
const sourceOnlyRoot = makeElement('div');
sourceOnlyRoot.appendChild(sourceOnlyFigure);

const zoomCalls = [];
const selectionCalls = [];
let zoomHandler = null;
const sandbox = {
  console,
  document: {
    createElement(tag) {
      return makeElement(tag);
    },
  },
  d3: {
    zoom() {
      const zoom = function() {};
      zoom.scaleExtent = () => zoom;
      zoom.constrain = () => zoom;
      zoom.on = (type, handler) => {
        if (type === 'zoom') zoomHandler = handler;
        return zoom;
      };
      return zoom;
    },
    select(node) {
      selectionCalls.push(node.tagName);
      return {
        call(fn) {
          zoomCalls.push(typeof fn);
          return this;
        },
        transition() {
          return this;
        },
      };
    },
    zoomIdentity: {
      translate() {
        return this;
      },
      scale() {
        return this;
      },
    },
  },
};

vm.createContext(sandbox);
vm.runInContext(`
${extractFunction(html, 'clampDocsMermaidTransform')}
${extractFunction(html, 'getDocsMermaidSvgViewBox')}
${extractFunction(html, 'formatDocsMermaidNumber')}
${extractFunction(html, 'applyDocsMermaidViewBox')}
${extractFunction(html, 'ensureDocsMermaidSvgViewBox')}
${extractFunction(html, 'normalizeDocsMermaidSvgSize')}
${extractFunction(html, 'fitDocsMermaidViewportToAspectRatio')}
${extractFunction(html, 'observeDocsMermaidViewport')}
${extractFunction(html, 'wrapDocsMermaidSvg')}
${extractFunction(html, 'getDocsMermaidViewportSize')}
${extractFunction(html, 'getDocsMermaidCanvasSize')}
${extractFunction(html, 'setDocsMermaidMode')}
${extractFunction(html, 'initDocsMermaidModeSwitches')}
${extractFunction(html, 'initDocsMermaidInteractions')}
this.clampDocsMermaidTransform = clampDocsMermaidTransform;
this.getDocsMermaidSvgViewBox = getDocsMermaidSvgViewBox;
this.applyDocsMermaidViewBox = applyDocsMermaidViewBox;
this.initDocsMermaidModeSwitches = initDocsMermaidModeSwitches;
this.initDocsMermaidInteractions = initDocsMermaidInteractions;
`, sandbox);

const plain = value => JSON.parse(JSON.stringify(value));

assert.deepStrictEqual(
  plain(sandbox.clampDocsMermaidTransform(
    { x: -900, y: -500, k: 1 },
    { width: 300, height: 200 },
    { width: 800, height: 500 }
  )),
  { x: -680, y: -380, k: 1 }
);
assert.deepStrictEqual(
  plain(sandbox.clampDocsMermaidTransform(
    { x: 900, y: 500, k: 1 },
    { width: 300, height: 200 },
    { width: 800, height: 500 }
  )),
  { x: 120, y: 80, k: 1 }
);
assert.deepStrictEqual(
  plain(sandbox.getDocsMermaidSvgViewBox(svg)),
  { x: 0, y: 0, width: 800, height: 500 }
);

sandbox.initDocsMermaidModeSwitches(sourceOnlyRoot);
assert.strictEqual(typeof sourceOnlySwitch.children[1].listeners.click, 'function');
sourceOnlySwitch.children[1].listeners.click({ preventDefault() {}, stopPropagation() {} });
assert.strictEqual(sourceOnlyFigure.dataset.mode, 'source');

sandbox.initDocsMermaidInteractions(root);

assert.deepStrictEqual(selectionCalls, ['DIV']);
assert.strictEqual(zoomCalls.length, 1);
assert.strictEqual(viewport.children[0].className, 'mermaid-canvas');
assert.strictEqual(viewport.children[0].children[0], svg);
assert.strictEqual(viewport.children[0].style.width, '100%');
assert.strictEqual(viewport.children[0].style.height, '100%');
assert.strictEqual(viewport.style.height, '188px');
assert.strictEqual(viewport.style.minHeight, '0px');
assert.strictEqual(svg.style.width, '100%');
assert.strictEqual(svg.style.height, '100%');
assert.strictEqual(svg.getAttribute('preserveAspectRatio'), 'xMidYMid meet');
assert.strictEqual(typeof toolbar.children[0].listeners.click, 'function');
assert.strictEqual(typeof toolbar.children[3].listeners.click, 'function');
assert.strictEqual(typeof modeSwitch.children[1].listeners.click, 'function');
modeSwitch.children[1].listeners.click({ preventDefault() {}, stopPropagation() {} });
assert.strictEqual(figure.dataset.mode, 'source');
assert.strictEqual(modeSwitch.children[0].className, '');
assert.strictEqual(modeSwitch.children[1].className, 'active');
assert.strictEqual(typeof zoomHandler, 'function');

zoomHandler({ transform: { x: -80, y: -50, k: 2 } });
assert.strictEqual(svg.getAttribute('viewBox'), '40 25 400 250');
assert.strictEqual(viewport.children[0].style.transform || '', '');

console.log('docs mermaid interactions ok');
