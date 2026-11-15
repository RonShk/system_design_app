// Parsing, diagram rendering and validation for authored content.
// Pure functions (no file-system access) so they can be unit-tested.
import yaml from 'js-yaml';
import { marked } from 'marked';

export const LESSON_SECTIONS = [
  'Intuition',
  'How it works',
  'Example',
  'Why it matters',
  'Tradeoffs and limits',
  'Common misconceptions',
  'Worked scenario',
];
export const CASE_STAGES = [
  'Requirements',
  'Estimates',
  'API and data model',
  'Initial architecture',
  'Bottlenecks',
  'Failure modes',
  'Alternatives',
  'Evolution',
];
export const LAB_SECTIONS = ['Goal', 'What to build', 'Checkpoints', 'Measure and break it'];
export const SKILLS = ['recall', 'explain', 'predict', 'compare', 'estimate', 'diagnose', 'design', 'implement'];
export const FORMATS = ['mcq', 'multi', 'numeric', 'order', 'free'];
export const POOLS = ['practice', 'assess', 'final'];
const ITEMS_MARK = /^=== items ===\s*$/m;
const ID_RE = /^[a-z0-9]+(-[a-z0-9]+)*$/;

// ---------- file parsing ----------

/** Split "---\nyaml\n---\nbody\n=== items ===\nyaml" into its three parts. */
export function splitFile(text) {
  const m = /^---\r?\n([\s\S]*?)\r?\n---\r?\n?/.exec(text);
  if (!m) throw new Error('missing front matter');
  const meta = yaml.load(m[1]) ?? {};
  let body = text.slice(m[0].length);
  let items = [];
  const im = ITEMS_MARK.exec(body);
  if (im) {
    items = yaml.load(body.slice(im.index + im[0].length)) ?? [];
    body = body.slice(0, im.index);
  }
  if (!Array.isArray(items)) throw new Error('items block must be a YAML list');
  return { meta, body, items };
}

/** Split a Markdown body into [{title, md}] by level-2 headings. */
export function splitSections(body) {
  const out = [];
  let cur = null;
  let inFence = false;
  for (const line of body.split(/\r?\n/)) {
    if (/^```/.test(line)) inFence = !inFence;
    const h = !inFence && /^## +(.+?)\s*$/.exec(line);
    if (h) {
      cur = { title: h[1], md: '' };
      out.push(cur);
    } else if (cur) {
      cur.md += line + '\n';
    } else if (line.trim()) {
      throw new Error(`text before first "## " heading: ${line.slice(0, 40)}`);
    }
  }
  return out;
}

// ---------- markdown → blocks ----------
// The iOS app renders content natively, so Markdown is compiled to a small block
// model. Inline formatting (**bold**, *italic*, `code`, [links](url)) stays as
// Markdown text and is rendered with AttributedString on the device.

const inline = (s) => String(s ?? '').replace(/\s*\r?\n\s*/g, ' ').trim();
export const renderInline = inline;

export function renderMarkdown(md) {
  const blocks = [];
  const walk = (tokens) => {
    for (const t of tokens) {
      if (t.type === 'space') continue;
      else if (t.type === 'paragraph' || t.type === 'text') blocks.push({ t: 'p', md: inline(t.text) });
      else if (t.type === 'heading') blocks.push({ t: 'h', md: inline(t.text) });
      else if (t.type === 'blockquote') blocks.push({ t: 'quote', md: inline(t.text) });
      else if (t.type === 'code') {
        if (t.lang === 'diagram') blocks.push(parseDiagram(t.text));
        else blocks.push({ t: 'code', text: t.text, lang: t.lang || '' });
      } else if (t.type === 'list') {
        const items = [];
        const add = (list, level) => {
          for (const it of list.items) {
            const own = it.tokens.filter((x) => x.type !== 'list').map((x) => x.text ?? x.raw).join(' ');
            items.push({ md: inline(own), level });
            for (const sub of it.tokens.filter((x) => x.type === 'list')) add(sub, level + 1);
          }
        };
        add(t, 0);
        blocks.push({ t: t.ordered ? 'ol' : 'ul', items });
      } else if (t.type === 'table') {
        if (t.header.length > 4) throw new Error('tables may have at most 4 columns (phone width)');
        blocks.push({ t: 'table', head: t.header.map((c) => inline(c.text)), rows: t.rows.map((r) => r.map((c) => inline(c.text))) });
      } else if (t.type === 'hr') continue;
      else if (t.type === 'html') throw new Error(`raw HTML is not supported: ${t.raw.slice(0, 40)}`);
      else throw new Error(`unsupported markdown element "${t.type}"`);
    }
  };
  walk(marked.lexer(String(md ?? '').trim(), { gfm: true }));
  return blocks;
}

// ---------- diagrams ----------
// Two tiny text formats, parsed and validated here and drawn natively by the app:
//   flow:  "A -> B: label" lines, laid out top-to-bottom by rank
//   seq:   "A -> B: msg", "A --> B: reply", "A -x B: lost", "note A: text"

function parseEdge(line) {
  const m = /^(.+?)\s*(-->|->|-x)\s*(.+?)(?::\s*(.*))?$/.exec(line);
  if (!m) throw new Error(`bad diagram line: "${line}"`);
  const kind = m[2] === '-->' ? 'dashed' : m[2] === '-x' ? 'lost' : 'solid';
  return { from: m[1].trim(), to: m[3].trim(), kind, label: (m[4] ?? '').trim() };
}

export function parseDiagram(src) {
  const lines = src.split(/\r?\n/).map((l) => l.trim()).filter((l) => l && !l.startsWith('#'));
  const kind = lines.shift();
  if (kind === 'flow') {
    const edges = lines.map(parseEdge);
    const names = [];
    for (const e of edges) for (const n of [e.from, e.to]) if (!names.includes(n)) names.push(n);
    if (names.length > 12) throw new Error('flow diagram: at most 12 nodes');
    if (names.some((n) => n.length > 22)) throw new Error('flow diagram: node names must be at most 22 characters');
    // rank = longest path from a source; edges pointing back to an earlier-declared node are ignored
    const rank = Object.fromEntries(names.map((n) => [n, 0]));
    for (let pass = 0; pass < names.length; pass++)
      for (const e of edges)
        if (names.indexOf(e.to) > names.indexOf(e.from) && rank[e.to] < rank[e.from] + 1) rank[e.to] = rank[e.from] + 1;
    const rows = [];
    for (const n of names) (rows[rank[n]] ??= []).push(n);
    if (Math.max(...rows.map((r) => r.length)) > 3) throw new Error('flow diagram: at most 3 nodes per row');
    return { t: 'diagram', kind: 'flow', rows, edges };
  }
  if (kind === 'seq') {
    const steps = lines.map((l) => {
      const n = /^note\s+(.+?):\s*(.+)$/.exec(l);
      return n ? { note: true, from: n[1].trim(), to: n[1].trim(), kind: 'note', label: n[2].trim() } : { note: false, ...parseEdge(l) };
    });
    const actors = [];
    for (const s of steps) for (const n of [s.from, s.to]) if (!actors.includes(n)) actors.push(n);
    if (actors.length > 4 || actors.length < 2) throw new Error('seq diagram: needs 2–4 actors');
    if (actors.some((a) => a.length > 12)) throw new Error('seq diagram: actor names must be at most 12 characters');
    if (steps.some((s) => !s.note && s.from === s.to)) throw new Error('seq diagram: use "note X: text" for a step local to one actor');
    if (steps.some((s) => s.label.length > 34)) throw new Error('seq diagram: labels must be at most 34 characters');
    return { t: 'diagram', kind: 'seq', actors, steps };
  }
  throw new Error(`diagram must start with "flow" or "seq", got "${kind}"`);
}

// ---------- numeric check expressions ----------

const CALC_OK = /^[\d\s.eE+\-*/%(),]*$/;
const CALC_FUNCS = ['log2', 'log10', 'ceil', 'floor', 'round', 'sqrt', 'pow', 'min', 'max'];

/** Evaluate an author-supplied arithmetic expression such as "500e6 * 100 / 2**30". */
export function evalCalc(expr) {
  let stripped = String(expr);
  for (const f of CALC_FUNCS) stripped = stripped.replaceAll(`Math.${f}`, '').replaceAll(f, '');
  if (!CALC_OK.test(stripped)) throw new Error(`calc contains unsupported characters: ${expr}`);
  let js = String(expr);
  for (const f of CALC_FUNCS) js = js.replace(new RegExp(`(?<![.\\w])${f}\\(`, 'g'), `Math.${f}(`);
  // eslint-disable-next-line no-new-func
  const v = Function(`"use strict"; return (${js});`)();
  if (typeof v !== 'number' || !Number.isFinite(v)) throw new Error(`calc did not produce a finite number: ${expr}`);
  return v;
}

// ---------- validation + compilation ----------

const normPrompt = (s) => String(s).toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();

/**
 * @param raw {{modules, sources, lessons:[{path,text}], cases:[...], labs:[...], itemFiles:[{path,text}]}}
 * @returns {{errors:string[], warnings:string[], data:object|null, stats:object}}
 */
export function compileContent(raw) {
  const errors = [];
  const warnings = [];
  const err = (where, msg) => errors.push(`${where}: ${msg}`);
  const sources = raw.sources ?? {};
  const modules = raw.modules ?? [];
  const moduleIds = new Set(modules.map((m) => m.id));
  const ids = new Set();
  const claimId = (where, id) => {
    if (typeof id !== 'string' || !ID_RE.test(id)) return err(where, `invalid id "${id}"`);
    if (ids.has(id)) return err(where, `duplicate id "${id}"`);
    ids.add(id);
  };
  const checkSources = (where, list, required = true) => {
    if (!Array.isArray(list) || list.length === 0) {
      if (required) err(where, 'needs at least one source');
      return [];
    }
    return list.map((s) => {
      if (!s || !sources[s.ref]) err(where, `unknown source ref "${s?.ref}"`);
      if (!s?.section || String(s.section).trim().length < 3) err(where, `source "${s?.ref}" needs a specific section`);
      const base = sources[s?.ref] ?? {};
      return { ref: s.ref, title: base.title, section: String(s.section ?? ''), url: s.url ?? base.url };
    });
  };

  const concepts = {};
  const lessons = [];
  const lessonBodies = {};
  const items = [];

  const compileItem = (where, it, ctx) => {
    const w = `${where} item ${it?.id}`;
    if (!it || typeof it !== 'object') return err(where, 'item is not a mapping');
    claimId(w, it.id);
    const conceptIds = it.concepts ?? (it.concept ? [it.concept] : []);
    if (!conceptIds.length) err(w, 'needs concept or concepts');
    if (!POOLS.includes(it.pool)) err(w, `pool must be one of ${POOLS.join('/')}`);
    if (!SKILLS.includes(it.skill)) err(w, `skill must be one of ${SKILLS.join('/')}`);
    if (!FORMATS.includes(it.format)) err(w, `format must be one of ${FORMATS.join('/')}`);
    if (![1, 2, 3].includes(it.difficulty)) err(w, 'difficulty must be 1, 2 or 3');
    if (!it.prompt || String(it.prompt).trim().length < 20) err(w, 'prompt too short');
    if (!it.explanation || String(it.explanation).trim().length < 40) err(w, 'explanation missing or too short');
    const hints = it.hints ?? [];
    if (!Array.isArray(hints)) err(w, 'hints must be a list');
    if (it.pool === 'practice' && hints.length === 0) err(w, 'practice items need at least one hint');
    const out = {
      id: it.id,
      concepts: conceptIds,
      pool: it.pool,
      skill: it.skill,
      format: it.format,
      difficulty: it.difficulty,
      lessonId: ctx.lessonId ?? null,
      caseId: ctx.caseId ?? null,
      prompt: renderMarkdown(it.prompt),
      hints: hints.map(renderInline),
      explanation: renderMarkdown(it.explanation),
      assumptions: it.assumptions ? renderInline(it.assumptions) : undefined,
      sources: it.sources ? checkSources(w, it.sources) : ctx.sources,
      _raw: normPrompt(it.prompt),
    };
    if (it.format === 'mcq' || it.format === 'multi') {
      if (!Array.isArray(it.choices) || it.choices.length < 3 || it.choices.length > 6) err(w, 'needs 3–6 choices');
      const ch = (it.choices ?? []).map(String);
      if (new Set(ch.map(normPrompt)).size !== ch.length) err(w, 'duplicate choices');
      out.choices = ch.map(renderInline);
      if (it.format === 'mcq') {
        if (!Number.isInteger(it.answer) || it.answer < 0 || it.answer >= ch.length) err(w, 'answer must be a 0-based index into choices');
        out.answer = it.answer;
      } else {
        const a = it.answers;
        if (!Array.isArray(a) || a.length < 1 || a.some((i) => !Number.isInteger(i) || i < 0 || i >= ch.length) || new Set(a).size !== a.length)
          err(w, 'answers must be a list of distinct 0-based indexes');
        else if (a.length === ch.length) err(w, 'multi-select must have at least one wrong choice');
        out.answers = a;
      }
    } else if (it.format === 'numeric') {
      if (typeof it.answer !== 'number' || !Number.isFinite(it.answer)) err(w, 'numeric answer must be a number');
      const hasRel = typeof it.tolerance === 'number' && it.tolerance > 0 && it.tolerance <= 0.5;
      const hasAbs = typeof it.tolAbs === 'number' && it.tolAbs >= 0;
      if (hasRel === hasAbs) err(w, 'numeric items need exactly one of tolerance (relative, 0–0.5) or tolAbs');
      if (!it.unit) err(w, 'numeric items need a unit (use "count" or "ratio" if dimensionless)');
      if (!it.calc) err(w, 'numeric items need calc: an arithmetic expression that reproduces the answer');
      else {
        try {
          const v = evalCalc(it.calc);
          const tol = Math.max(Math.abs(it.answer) * 0.005, 1e-9);
          if (Math.abs(v - it.answer) > tol) err(w, `calc evaluates to ${v} but answer is ${it.answer}`);
        } catch (e) {
          err(w, e.message);
        }
      }
      Object.assign(out, { answer: it.answer, tolerance: hasRel ? it.tolerance : undefined, tolAbs: hasAbs ? it.tolAbs : undefined, unit: String(it.unit ?? '') });
    } else if (it.format === 'order') {
      if (!Array.isArray(it.steps) || it.steps.length < 3 || it.steps.length > 7) err(w, 'order items need 3–7 steps listed in the correct order');
      out.steps = (it.steps ?? []).map((s) => renderInline(String(s)));
    } else if (it.format === 'free') {
      if (!it.model || String(it.model).trim().length < 60) err(w, 'free-response items need a model answer');
      if (!Array.isArray(it.rubric) || it.rubric.length < 2 || it.rubric.length > 7) err(w, 'free-response items need a rubric of 2–7 points');
      out.model = renderMarkdown(it.model);
      out.rubric = (it.rubric ?? []).map((r) => renderInline(String(r)));
    }
    if (['explain', 'design'].includes(it.skill) && ['mcq', 'multi'].includes(it.format))
      err(w, `skill "${it.skill}" cannot be evidenced by multiple choice`);
    items.push(out);
  };

  // lessons
  for (const f of raw.lessons ?? []) {
    let p;
    try { p = splitFile(f.text); } catch (e) { err(f.path, e.message); continue; }
    const { meta } = p;
    const w = f.path;
    claimId(w, meta.id);
    if (!moduleIds.has(meta.module)) err(w, `unknown module "${meta.module}"`);
    if (!meta.title) err(w, 'missing title');
    if (!meta.objective || String(meta.objective).length < 30) err(w, 'objective missing or too short');
    if (!Number.isFinite(meta.order)) err(w, 'missing numeric order');
    if (!Number.isFinite(meta.minutes)) err(w, 'missing minutes');
    if (!Array.isArray(meta.prereqs)) err(w, 'prereqs must be a list (may be empty)');
    if (!Array.isArray(meta.concepts) || meta.concepts.length < 1 || meta.concepts.length > 3) err(w, 'needs 1–3 concepts');
    const src = checkSources(w, meta.sources);
    for (const c of meta.concepts ?? []) {
      claimId(`${w} concept`, c.id);
      if (!c.name || !c.def || String(c.def).length < 25) err(w, `concept ${c.id} needs name and a one-sentence def`);
      concepts[c.id] = { id: c.id, name: c.name, def: renderInline(c.def), lessonId: meta.id, moduleId: meta.module };
    }
    let sections = [];
    try { sections = splitSections(p.body); } catch (e) { err(w, e.message); }
    const titles = sections.map((s) => s.title);
    if (titles.join('|') !== LESSON_SECTIONS.join('|')) err(w, `sections must be exactly: ${LESSON_SECTIONS.join(' / ')} (got: ${titles.join(' / ')})`);
    let secs = [];
    let words = 0;
    try {
      secs = sections.map((s) => { words += s.md.split(/\s+/).length; return { title: s.title, blocks: renderMarkdown(s.md) }; });
    } catch (e) { err(w, e.message); }
    if (words < 450) err(w, `lesson body is ${words} words; substantive lessons need at least 450`);
    lessons.push({
      id: meta.id, title: meta.title, module: meta.module, order: meta.order, minutes: meta.minutes,
      objective: meta.objective, prereqs: meta.prereqs ?? [], concepts: (meta.concepts ?? []).map((c) => c.id), words,
      hasDiagram: /```diagram/.test(p.body),
    });
    lessonBodies[meta.id] = { sections: secs, sources: src };
    const own = new Set((meta.concepts ?? []).map((c) => c.id));
    const before = items.length;
    for (const it of p.items) {
      compileItem(w, it, { lessonId: meta.id, sources: src });
      const primary = it?.concepts?.[0] ?? it?.concept;
      if (primary && !own.has(primary)) err(`${w} item ${it.id}`, `primary concept "${primary}" is not taught by this lesson`);
    }
    const mine = items.slice(before);
    if (mine.filter((i) => i.pool === 'practice').length < 4) err(w, 'needs at least 4 practice items');
    if (mine.filter((i) => i.pool === 'assess').length < 2) err(w, 'needs at least 2 assess items');
    if (new Set(mine.map((i) => i.format)).size < 3) err(w, 'items must use at least 3 different formats');
    for (const c of own) {
      const ci = mine.filter((i) => i.concepts[0] === c);
      if (ci.filter((i) => i.pool === 'practice').length < 2) err(w, `concept ${c} needs at least 2 practice items`);
      if (!ci.some((i) => i.pool === 'assess')) err(w, `concept ${c} needs at least 1 assess item`);
      if (!ci.some((i) => i.format !== 'mcq' && i.format !== 'multi')) err(w, `concept ${c} needs a non-multiple-choice item`);
    }
  }

  // module + lesson ordering
  const modOrder = Object.fromEntries(modules.map((m, i) => [m.id, i]));
  lessons.sort((a, b) => modOrder[a.module] - modOrder[b.module] || a.order - b.order);
  const lessonPos = Object.fromEntries(lessons.map((l, i) => [l.id, i]));
  for (const l of lessons) {
    for (const p of l.prereqs) {
      if (!(p in lessonPos)) err(`lesson ${l.id}`, `unknown prerequisite "${p}"`);
      else if (lessonPos[p] >= lessonPos[l.id]) err(`lesson ${l.id}`, `prerequisite "${p}" comes later in the curriculum order`);
    }
  }
  const seenOrder = new Set();
  for (const l of lessons) {
    const k = `${l.module}:${l.order}`;
    if (seenOrder.has(k)) err(`lesson ${l.id}`, `duplicate order ${l.order} in module ${l.module}`);
    seenOrder.add(k);
  }

  // cases
  const cases = [];
  const caseBodies = {};
  for (const f of raw.cases ?? []) {
    let p;
    try { p = splitFile(f.text); } catch (e) { err(f.path, e.message); continue; }
    const { meta } = p;
    const w = f.path;
    claimId(w, meta.id);
    if (!meta.title || !meta.summary) err(w, 'needs title and summary');
    if (!Number.isFinite(meta.minutes)) err(w, 'missing minutes');
    for (const l of meta.prereqs ?? []) if (!(l in lessonPos)) err(w, `unknown prerequisite lesson "${l}"`);
    for (const c of meta.concepts ?? []) if (!concepts[c]) err(w, `unknown concept "${c}"`);
    if (!(meta.concepts?.length >= 3)) err(w, 'needs at least 3 concepts exercised');
    const src = checkSources(w, meta.sources);
    const ug = meta.unguided;
    if (!ug?.prompt || !(ug.rubric?.length >= 5)) err(w, 'unguided needs a prompt and a rubric of at least 5 points');
    let sections = [];
    try { sections = splitSections(p.body); } catch (e) { err(w, e.message); }
    if (sections.map((s) => s.title).join('|') !== CASE_STAGES.join('|')) err(w, `stages must be exactly: ${CASE_STAGES.join(' / ')}`);
    let words = 0;
    const stages = [];
    for (const s of sections) {
      const m = /^\s*>\s*\*\*Your turn:\*\*\s*([\s\S]*?)\n\s*\n/.exec(s.md);
      if (!m) { err(w, `stage "${s.title}" must start with "> **Your turn:** …"`); continue; }
      words += s.md.split(/\s+/).length;
      try {
        stages.push({ title: s.title, prompt: renderInline(m[1].replace(/\n>\s?/g, ' ')), blocks: renderMarkdown(s.md.slice(m[0].length)) });
      } catch (e) { err(w, e.message); }
    }
    if (words < 1100) err(w, `case study is ${words} words; needs at least 1100`);
    cases.push({ id: meta.id, title: meta.title, summary: meta.summary, minutes: meta.minutes, prereqs: meta.prereqs ?? [], concepts: meta.concepts ?? [], words });
    caseBodies[meta.id] = {
      stages, sources: src,
      unguided: ug ? { prompt: renderMarkdown(ug.prompt), rubric: (ug.rubric ?? []).map((r) => renderInline(String(r))), minutes: ug.minutes ?? 35 } : null,
    };
    for (const it of p.items) compileItem(w, it, { caseId: meta.id, sources: src });
  }

  // labs
  const labs = [];
  const labBodies = {};
  for (const f of raw.labs ?? []) {
    let p;
    try { p = splitFile(f.text); } catch (e) { err(f.path, e.message); continue; }
    const { meta } = p;
    const w = f.path;
    claimId(w, meta.id);
    if (!meta.title || !meta.summary) err(w, 'needs title and summary');
    if (meta.requiresDev !== true) err(w, 'labs must declare requiresDev: true');
    for (const l of meta.lessons ?? []) if (!(l in lessonPos)) err(w, `unknown lesson "${l}"`);
    if (!(meta.lessons?.length >= 1)) err(w, 'needs at least one linked lesson');
    const src = checkSources(w, meta.sources);
    let sections = [];
    try { sections = splitSections(p.body); } catch (e) { err(w, e.message); }
    if (sections.map((s) => s.title).join('|') !== LAB_SECTIONS.join('|')) err(w, `sections must be exactly: ${LAB_SECTIONS.join(' / ')}`);
    labs.push({ id: meta.id, title: meta.title, summary: meta.summary, hours: meta.hours ?? null, lessons: meta.lessons ?? [] });
    try { labBodies[meta.id] = { sections: sections.map((s) => ({ title: s.title, blocks: renderMarkdown(s.md) })), sources: src }; } catch (e) { err(w, e.message); }
    for (const it of p.items) compileItem(w, it, { sources: src });
  }

  // standalone item files (cumulative, final)
  for (const f of raw.itemFiles ?? []) {
    let list;
    try { list = yaml.load(f.text) ?? []; } catch (e) { err(f.path, e.message); continue; }
    if (!Array.isArray(list)) { err(f.path, 'must be a YAML list of items'); continue; }
    for (const it of list) {
      if (!it?.sources) err(`${f.path} item ${it?.id}`, 'standalone items must list their own sources');
      compileItem(f.path, it, { sources: [] });
    }
  }

  // cross-item checks
  const promptSeen = new Map();
  for (const it of items) {
    for (const c of it.concepts) if (!concepts[c]) err(`item ${it.id}`, `unknown concept "${c}"`);
    if (it._raw.length > 0) {
      if (promptSeen.has(it._raw)) err(`item ${it.id}`, `duplicate prompt (same as ${promptSeen.get(it._raw)})`);
      promptSeen.set(it._raw, it.id);
    }
    delete it._raw;
  }
  const mcq = items.filter((i) => i.format === 'mcq');
  if (mcq.length >= 40) {
    const first = mcq.filter((i) => i.answer === 0).length / mcq.length;
    if (first > 0.45) warnings.push(`${Math.round(first * 100)}% of multiple-choice answers are the first choice (choices are shuffled at runtime, so this is cosmetic)`);
  }

  const stats = {
    modules: modules.length,
    lessons: lessons.length,
    concepts: Object.keys(concepts).length,
    items: items.length,
    practiceItems: items.filter((i) => i.pool === 'practice').length,
    assessItems: items.filter((i) => i.pool === 'assess').length,
    finalItems: items.filter((i) => i.pool === 'final').length,
    byFormat: Object.fromEntries(FORMATS.map((f) => [f, items.filter((i) => i.format === f).length])),
    bySkill: Object.fromEntries(SKILLS.map((s) => [s, items.filter((i) => i.skill === s).length])),
    cases: cases.length,
    labs: labs.length,
    words: lessons.reduce((a, l) => a + l.words, 0) + cases.reduce((a, c) => a + c.words, 0),
  };
  const data = { modules, sources, concepts, lessons, lessonBodies, items, cases, caseBodies, labs, labBodies };
  return { errors, warnings, data, stats };
}

/** Delivery targets from the project brief; checked only with --strict. */
export function checkTargets(stats) {
  const out = [];
  const need = (ok, msg) => { if (!ok) out.push(msg); };
  need(stats.lessons >= 100, `lessons: ${stats.lessons} < 100`);
  need(stats.items >= 500, `items: ${stats.items} < 500`);
  need(stats.cases >= 10, `case studies: ${stats.cases} < 10`);
  need(stats.labs >= 6, `labs: ${stats.labs} < 6`);
  need(stats.finalItems >= 12, `final assessment items: ${stats.finalItems} < 12`);
  const nonMc = stats.items - stats.byFormat.mcq - stats.byFormat.multi;
  need(nonMc / Math.max(1, stats.items) >= 0.4, `non-multiple-choice share ${(nonMc / Math.max(1, stats.items)).toFixed(2)} < 0.40`);
  return out;
}
