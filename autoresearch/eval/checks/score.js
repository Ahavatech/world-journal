#!/usr/bin/env node
'use strict';
// Compose the final COMPONENT / GATES / SCORE lines (EVAL-SPEC.md output format).
//   node checks/score.js DIR     DIR holds gates.json axe.json citation.json lh.json
// Components that cannot be measured are SKIPPED and the remaining weights are
// re-scaled to 100; nothing is estimated.
const fs = require('fs');
const path = require('path');

const dir = process.argv[2];
const read = (f) => JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
const gates = read('gates.json');
const axe = read('axe.json');
const cit = read('citation.json');
const lh = read('lh.json');

// ---- gates
const failed = [];
if (!cit.ok) failed.push(`1 citation tags (${cit.failing.join(', ')})`);
if (!gates.gates['overflow-320'].ok) failed.push('2 horizontal overflow at 320 px');
if (!gates.gates['external-requests'].ok) failed.push('3 external network requests');
if (axe.violations.length) failed.push(`4 axe violations (${[...new Set(axe.violations.map((v) => v.id))].join(', ')})`);
if (!gates.gates.size.ok) failed.push('5 theme CSS+JS over budget');
if (!gates.gates['js-off'].ok) failed.push('6 a page breaks with JavaScript off');
if (!gates.gates.placeholders.ok) failed.push('7 [PLACEHOLDER marker removed');

// ---- components, each 0..100 (simplicity 0..5 scaled)
const comp = { a11y: null, seo: null, perf: null, bp: null, resp: null, simplicity: null };
const weight = { a11y: 30, seo: 25, perf: 20, bp: 10, resp: 10, simplicity: 5 };
const skipped = { perf: 'Lighthouse performance needs throttled median-of-three runs: over the 5-minute budget and the flaky category' };
if (!lh.skipped) {
  comp.a11y = lh.mean.accessibility;
  comp.seo = (lh.mean.seo + cit.completeness * 100) / 2; // Lighthouse SEO mean + citation tag completeness
  comp.bp = lh.mean.bestPractices;
} else {
  ['a11y', 'seo', 'bp'].forEach((k) => { skipped[k] = lh.reason; });
}
comp.resp = (gates.resp.passed / gates.resp.total) * 100;
const extraKb = Math.max(0, (gates.info.themeBytes - gates.info.baselineThemeBytes) / 1024);
const penalty = Math.min(5, extraKb * 0.5); // half a point per KB over the baseline
comp.simplicity = ((5 - penalty) / 5) * 100;

const measured = Object.keys(comp).filter((k) => comp[k] !== null);
const totalW = measured.reduce((n, k) => n + weight[k], 0);
const score = measured.reduce((n, k) => n + weight[k] * comp[k], 0) / totalW;

const f = (v) => (v === null ? 'SKIPPED' : v.toFixed(1));
console.log('');
Object.entries(skipped).forEach(([k, why]) => console.log(`note: ${k} SKIPPED: ${why}`));
console.log(`note: score re-weighted over measured components (${measured.join(', ')}; weights ${measured.map((k) => weight[k]).join('+')}=${totalW})`);
if (!lh.skipped) {
  const byAudit = {};
  lh.per.forEach((p) => p.failing.forEach((a) => { (byAudit[a] = byAudit[a] || []).push(p.page); }));
  Object.entries(byAudit).forEach(([a, ps]) => console.log(`note: lighthouse audit "${a}" fails on ${ps.length} page(s): ${ps.join(', ')}`));
}
console.log(`COMPONENT a11y=${f(comp.a11y)}, seo=${f(comp.seo)}, perf=${f(comp.perf)}, bp=${f(comp.bp)}, resp=${f(comp.resp)}, simplicity=${f(comp.simplicity)}`);
console.log(failed.length ? `GATES: FAIL ${failed.join('; ')}` : 'GATES: PASS');
console.log(`SCORE: ${failed.length ? '0.0' : score.toFixed(1)}`);
process.exit(failed.length ? 1 : 0);
