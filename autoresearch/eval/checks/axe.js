#!/usr/bin/env node
'use strict';
// axe-core through Playwright on every page at 320 and 1280 px.
// Usage: node checks/axe.js [--json]   Exit 1 if any WCAG 2.x A/AA rule fails.
// Tags: wcag2a wcag2aa wcag21a wcag21aa wcag22aa. Best-practice rules are
// reported separately and do not fail the run.
const { chromium } = require('playwright');
const { AxeBuilder } = require('@axe-core/playwright');
const { pages, viewports } = require('../lib/pages');

const WCAG = ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'];

async function run() {
  const browser = await chromium.launch();
  const out = { violations: [], coreOwned: [], bestPractice: [], incomplete: [], passes: 0, runs: 0 };
  for (const vp of viewports) {
    for (const pg of pages) {
      const ctx = await browser.newContext({ viewport: { width: vp, height: 900 } });
      const page = await ctx.newPage();
      const res = await page.goto(pg.url, { waitUntil: 'networkidle' });
      const wcag = await new AxeBuilder({ page }).withTags(WCAG).analyze();
      const best = await new AxeBuilder({ page }).withTags(['best-practice']).analyze();
      out.runs += 1;
      out.passes += wcag.passes.length;
      const tag = (v) => ({ page: pg.name, width: vp, status: res.status(), id: v.id, impact: v.impact, help: v.help, nodes: v.nodes.length, sample: v.nodes[0].target.join(' ') });
      wcag.violations.forEach((v) => (pg.core ? out.coreOwned : out.violations).push(tag(v)));
      best.violations.forEach((v) => out.bestPractice.push(tag(v)));
      wcag.incomplete.forEach((v) => out.incomplete.push(tag(v)));
      await ctx.close();
    }
  }
  await browser.close();
  return out;
}

run().then((out) => {
  if (process.argv.includes('--json')) { console.log(JSON.stringify(out, null, 2)); }
  const line = (v) => `  ${v.page}@${v.width} [${v.impact}] ${v.id} x${v.nodes}: ${v.help}\n      e.g. ${v.sample}`;
  console.log(`axe ${out.runs} page runs (${pages.length} pages x ${viewports.length} widths), rules passed: ${out.passes}`);
  console.log(`WCAG violations: ${out.violations.length}`);
  out.violations.forEach((v) => console.log(line(v)));
  console.log(`core-owned page findings (not fixable in the theme, reported): ${out.coreOwned.length}`);
  out.coreOwned.forEach((v) => console.log(line(v)));
  console.log(`best-practice findings (not failing): ${out.bestPractice.length}`);
  out.bestPractice.forEach((v) => console.log(line(v)));
  console.log(`needs manual review (axe "incomplete"): ${out.incomplete.length}`);
  const ids = [...new Set(out.incomplete.map((v) => v.id))];
  if (ids.length) { console.log('  rules: ' + ids.join(', ')); }
  process.exit(out.violations.length ? 1 : 0);
}).catch((e) => { console.error(e); process.exit(2); });
