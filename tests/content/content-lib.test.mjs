import test from 'node:test';
import assert from 'node:assert/strict';
import { splitFile, splitSections, renderMarkdown, parseDiagram, evalCalc, compileContent, LESSON_SECTIONS } from '../../scripts/content-lib.mjs';

const body = LESSON_SECTIONS.map((t) => `## ${t}\n${'word '.repeat(70)}\n`).join('\n');
const item = (id, over = {}) => ({
  id, concept: 'c-one', pool: 'practice', skill: 'recall', format: 'mcq', difficulty: 1,
  prompt: `Which option is right for ${id}, exactly?`, choices: ['a', 'b', 'c'], answer: 0, hints: ['h'],
  explanation: 'Because the first option is the only one that is right here.', ...over,
});
const goodItems = () => [
  item('c-one-p1'),
  item('c-one-p2', { format: 'numeric', skill: 'estimate', answer: 50, unit: 'ms', tolerance: 0.1, calc: '100/2', choices: undefined }),
  item('c-one-p3', { format: 'order', steps: ['first', 'second', 'third'], choices: undefined, answer: undefined }),
  item('c-one-p4', { format: 'free', skill: 'explain', choices: undefined, answer: undefined, model: 'A model answer that is long enough to pass the minimum length check.', rubric: ['one', 'two'] }),
  item('c-one-a1', { pool: 'assess', hints: [] }),
  item('c-one-a2', { pool: 'assess', hints: [], format: 'free', skill: 'explain', choices: undefined, answer: undefined, model: 'Another model answer that is long enough to pass the minimum length check.', rubric: ['one', 'two'] }),
];
const yamlItems = (items) => JSON.stringify(items);
const lesson = ({ id = 'l-one', order = 1, prereqs = '[]', concept = 'c-one', items = goodItems(), text = body } = {}) => ({
  path: `${id}.md`,
  text: `---\nid: ${id}\ntitle: T\nmodule: m\norder: ${order}\nminutes: 5\nobjective: Explain the thing well enough to use it later.\nprereqs: ${prereqs}\nconcepts:\n  - {id: ${concept}, name: N, def: "A definition that is long enough to pass."}\nsources:\n  - {ref: s, section: "Ch. 1"}\n---\n${text}\n=== items ===\n${yamlItems(items)}\n`,
});
const compile = (lessons, extra = {}) =>
  compileContent({ modules: [{ id: 'm', title: 'M', summary: 's' }], sources: { s: { title: 'S', url: 'https://example.com' } }, lessons, ...extra });

test('a well-formed lesson compiles', () => {
  const r = compile([lesson()]);
  assert.deepEqual(r.errors, []);
  assert.equal(r.stats.items, 6);
  assert.equal(r.data.items[0].sources[0].url, 'https://example.com');
});

test('missing or reordered sections are rejected', () => {
  const r = compile([lesson({ text: body.replace('## Example', '## Sample') })]);
  assert.ok(r.errors.some((e) => e.includes('sections must be exactly')));
});

test('prerequisites must exist and come earlier', () => {
  const a = lesson({ id: 'l-one', order: 1, prereqs: '[l-two]' });
  const b = lesson({ id: 'l-two', order: 2, concept: 'c-two', items: goodItems().map((i) => ({ ...i, id: i.id.replace('one', 'two'), concept: 'c-two', prompt: i.prompt + ' (two)' })) });
  assert.ok(compile([a, b]).errors.some((e) => e.includes('comes later')));
  assert.ok(compile([lesson({ prereqs: '[nope]' })]).errors.some((e) => e.includes('unknown prerequisite')));
});

test('answer keys are checked', () => {
  const bad = (over) => compile([lesson({ items: [...goodItems().slice(1), item('c-one-p1', over)] })]).errors.join('\n');
  assert.match(bad({ answer: 3 }), /0-based index/);
  assert.match(bad({ choices: ['a', 'a', 'b'] }), /duplicate choices/);
  assert.match(bad({ format: 'numeric', answer: 51, unit: 'ms', tolerance: 0.1, calc: '100/2', choices: undefined }), /calc evaluates to 50/);
  assert.match(bad({ format: 'numeric', answer: 50, unit: 'ms', calc: '100/2', choices: undefined }), /exactly one of tolerance/);
  assert.match(bad({ format: 'free', choices: undefined, answer: undefined }), /model answer/);
  assert.match(bad({ skill: 'explain' }), /cannot be evidenced by multiple choice/);
  assert.match(bad({ explanation: 'short' }), /explanation/);
  assert.match(bad({ hints: [] }), /at least one hint/);
});

test('duplicate ids, duplicate prompts and unknown sources are rejected', () => {
  const dup = goodItems();
  dup[1].prompt = dup[0].prompt;
  assert.ok(compile([lesson({ items: dup })]).errors.some((e) => e.includes('duplicate prompt')));
  const sameId = goodItems();
  sameId[1].id = sameId[0].id;
  assert.ok(compile([lesson({ items: sameId })]).errors.some((e) => e.includes('duplicate id')));
  const r = compileContent({ modules: [{ id: 'm' }], sources: {}, lessons: [lesson()] });
  assert.ok(r.errors.some((e) => e.includes('unknown source ref')));
});

test('lessons need enough practice and assessment items in varied formats', () => {
  const few = compile([lesson({ items: goodItems().slice(0, 3) })]).errors.join('\n');
  assert.match(few, /at least 4 practice/);
  assert.match(few, /at least 2 assess/);
  const allMcq = goodItems().map((i) => ({ ...item(i.id), pool: i.pool, hints: ['h'] }));
  assert.match(compile([lesson({ items: allMcq })]).errors.join('\n'), /at least 3 different formats/);
});

test('markdown becomes blocks', () => {
  const blocks = renderMarkdown('Para **bold**\nsecond line.\n\n- a\n  - nested\n- b\n\n| x | y |\n|---|---|\n| 1 | 2 |\n\n```cpp\nint x;\n```\n\n### Sub\n\n> quoted');
  assert.deepEqual(blocks.map((b) => b.t), ['p', 'ul', 'table', 'code', 'h', 'quote']);
  assert.equal(blocks[0].md, 'Para **bold** second line.');
  assert.deepEqual(blocks[1].items, [{ md: 'a', level: 0 }, { md: 'nested', level: 1 }, { md: 'b', level: 0 }]);
  assert.deepEqual(blocks[2].rows, [['1', '2']]);
  assert.throws(() => renderMarkdown('<div>x</div>'), /raw HTML/);
  assert.throws(() => renderMarkdown('| a | b | c | d | e |\n|---|---|---|---|---|\n| 1 | 2 | 3 | 4 | 5 |'), /at most 4 columns/);
});

test('diagrams are parsed, ranked and bounded', () => {
  const d = parseDiagram('flow\nClient -> LB: HTTPS\nLB -> App 1\nLB -> App 2\nApp 1 --> DB\nApp 2 -x DB');
  assert.deepEqual(d.rows, [['Client'], ['LB'], ['App 1', 'App 2'], ['DB']]);
  assert.deepEqual(d.edges.map((e) => e.kind), ['solid', 'solid', 'solid', 'dashed', 'lost']);
  const s = parseDiagram('seq\nA -> B: hi\nnote B: think\nB --> A: ok');
  assert.deepEqual(s.actors, ['A', 'B']);
  assert.equal(s.steps[1].note, true);
  assert.throws(() => parseDiagram('flow\nA -> B\nA -> C\nA -> D\nA -> E'), /at most 3 nodes per row/);
  assert.throws(() => parseDiagram('seq\nA -> B\nB -> C\nC -> D\nD -> E'), /2–4 actors/);
  assert.throws(() => parseDiagram('pie\nA -> B'), /must start with/);
});

test('calc expressions are arithmetic only', () => {
  assert.equal(evalCalc('500e6 * 100 / 1e9'), 50);
  assert.equal(evalCalc('ceil(log2(1000))'), 10);
  assert.ok(Math.abs(evalCalc('(1 - pow(0.99, 20)) * 100') - 18.209) < 0.01);
  assert.throws(() => evalCalc('process.exit(1)'));
  assert.throws(() => evalCalc('1/0'));
});

test('file splitting', () => {
  const f = splitFile('---\nid: x\n---\n## A\ntext\n\n=== items ===\n- id: i\n');
  assert.equal(f.meta.id, 'x');
  assert.equal(f.items[0].id, 'i');
  assert.deepEqual(splitSections('## A\none\n```\n## not a heading\n```\n## B\ntwo').map((s) => s.title), ['A', 'B']);
  assert.throws(() => splitFile('no front matter'));
});
