#!/usr/bin/env node
'use strict';
// Hard gates 2, 3, 5, 6, 7 and 8 from autoresearch/EVAL-SPEC.md, plus the
// responsiveness component. Gates 1 (citation tags) and 4 (axe) are run by run.sh
// with scripts/check-citation-meta.sh and checks/axe.js.
//
//   node checks/gates.js --out result.json     run everything, print one line per check
//   node checks/gates.js --update-baseline     rewrite baseline.json from the current state
//                                              (an explicit human action, never part of a run)
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');
const { base, pages } = require('../lib/pages');

const ROOT = path.resolve(__dirname, '..', '..', '..');
const ASSETS = path.join(ROOT, 'ojs/plugins/themes/worj/assets');
const BASELINE = path.resolve(__dirname, '..', 'baseline.json');
const SIZE_BUDGET = 150 * 1024; // theme's own CSS + JS, uncompressed (EVAL-SPEC gate 5)
const FONT_TARGET = 100 * 1024; // reported, not gated (108,268 bytes accepted for the italic)

const args = process.argv.slice(2);
const outPath = args.includes('--out') ? args[args.indexOf('--out') + 1] : null;
const updateBaseline = args.includes('--update-baseline');

const result = { gates: {}, resp: { passed: 0, total: 0, failures: [] }, info: {} };
const gate = (name, ok, detail) => { (result.gates[name] = result.gates[name] || { ok: true, details: [] }); if (!ok) result.gates[name].ok = false; result.gates[name].details.push((ok ? 'ok   ' : 'FAIL ') + detail); };

const sumBytes = (dir, ext) => fs.readdirSync(dir).filter((f) => f.endsWith(ext)).reduce((n, f) => n + fs.statSync(path.join(dir, f)).size, 0);
const themeBytes = () => sumBytes(path.join(ASSETS, 'css'), '.css') + sumBytes(path.join(ASSETS, 'js'), '.js');

async function openPage(browser, pg, width, opts = {}) {
  const ctx = await browser.newContext({ viewport: { width, height: 900 }, ...opts });
  const page = await ctx.newPage();
  const reqs = [];
  const errors = []; // uncaught exceptions and console errors, collected before the page loads
  page.on('request', (r) => reqs.push(r.url()));
  page.on('pageerror', (e) => errors.push('uncaught: ' + e.message.split('\n')[0]));
  page.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text().split('\n')[0].slice(0, 120)); });
  const res = await page.goto(pg.url, { waitUntil: 'networkidle' });
  return { ctx, page, reqs, errors, status: res.status() };
}

(async () => {
  const browser = await chromium.launch();
  const placeholders = {};

  // ---- gate 2: no horizontal overflow at 320 px (every page, including core-owned ones)
  for (const pg of pages) {
    const { ctx, page } = await openPage(browser, pg, 320);
    const over = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
    gate('overflow-320', over <= 0, `${pg.name}: ${over}px`);
    await ctx.close();
  }

  // ---- gate 3: no external network requests (both widths: the hero image differs)
  for (const pg of pages) {
    for (const w of [320, 1280]) {
      const { ctx, reqs } = await openPage(browser, pg, w);
      const ext = reqs.filter((u) => !u.startsWith(base) && !u.startsWith('data:') && !u.startsWith('blob:'));
      gate('external-requests', ext.length === 0, `${pg.name}@${w}: ${ext.length ? ext.join(', ') : '0 external of ' + reqs.length}`);
      await ctx.close();
    }
  }

  // ---- gate 8: no uncaught JavaScript errors or console errors on any page
  //      (a parent script once threw a Swiper ReferenceError on every page and got past the other gates)
  for (const pg of pages) {
    for (const w of [320, 1280]) {
      const { ctx, errors, status } = await openPage(browser, pg, w);
      // a core 404 document logs its own status as a console error: that is the expected response, not a script error
      const real = pg.core && status === 404 ? errors.filter((e) => !/status of 404/.test(e)) : errors;
      gate('js-errors', real.length === 0, `${pg.name}@${w}: ${real.length ? real.join(' | ') : 'no errors'}`);
      await ctx.close();
    }
  }

  // ---- gate 5: theme CSS + JS size (the theme's own files; whole-page total reported)
  const tb = themeBytes();
  gate('size', tb <= SIZE_BUDGET, `theme CSS+JS ${tb} bytes (budget ${SIZE_BUDGET})`);
  const fonts = sumBytes(path.join(ASSETS, 'fonts'), '.woff2');
  result.info.themeBytes = tb;
  result.info.fontBytes = fonts;
  result.info.fontNote = `${fonts} bytes of woff2 (target about ${FONT_TARGET}; the italic was accepted, not gated)`;
  {
    const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
    const page = await ctx.newPage();
    let total = 0;
    page.on('response', async (r) => { const t = r.request().resourceType(); if (t === 'stylesheet' || t === 'script') { try { total += (await r.body()).length; } catch (e) { /* redirected or aborted */ } } });
    await page.goto(pages.find((p) => p.name === 'article').url, { waitUntil: 'networkidle' });
    result.info.articlePageCssJsBytes = total;
    await ctx.close();
  }

  // ---- gate 6: pages work with JavaScript disabled
  for (const pg of pages.filter((p) => !p.core)) {
    for (const w of [320, 1280]) {
      const { ctx, page } = await openPage(browser, pg, w, { javaScriptEnabled: false });
      const r = await page.evaluate(() => {
        const vis = (e) => { const b = e.getBoundingClientRect(); const c = getComputedStyle(e); return b.width > 0 && b.height > 0 && c.visibility !== 'hidden' && c.display !== 'none'; };
        const links = [...document.querySelectorAll('.worj-nav > ul a')].filter(vis).length;
        const toggle = document.querySelector('.worj-nav-toggle');
        const main = document.querySelector('main');
        return { links, deadToggle: !!toggle && vis(toggle), h1: document.querySelectorAll('h1').length, mainText: main ? main.innerText.trim().length : 0 };
      });
      const ok = r.links >= 2 && !r.deadToggle && r.h1 >= 1 && r.mainText > 40;
      gate('js-off', ok, `${pg.name}@${w}: ${r.links} nav links reachable, dead toggle ${r.deadToggle}, h1 ${r.h1}, main text ${r.mainText} chars`);
      await ctx.close();
    }
  }

  // ---- gate 7: [PLACEHOLDER banners still rendered (counts vs the baseline)
  for (const pg of pages.filter((p) => !p.core)) {
    const { ctx, page } = await openPage(browser, pg, 1280);
    placeholders[pg.name] = await page.evaluate(() => (document.body.innerText.match(/\[PLACEHOLDER/g) || []).length);
    await ctx.close();
  }

  // ---- responsiveness component: layout assertions at 320 / 768 / 1280
  for (const pg of pages.filter((p) => !p.core)) {
    for (const w of [320, 768, 1280]) {
      const { ctx, page } = await openPage(browser, pg, w);
      const r = await page.evaluate((width) => {
        const vis = (e) => { const b = e.getBoundingClientRect(); const c = getComputedStyle(e); return b.width > 0 && b.height > 0 && c.visibility !== 'hidden' && c.display !== 'none'; };
        const cw = document.documentElement.clientWidth;
        const wide = [...document.querySelectorAll('body *')].filter((e) => vis(e) && !e.closest('.pkp_screen_reader') && e.getBoundingClientRect().right > cw + 0.5).length;
        const toggle = document.querySelector('.worj-nav-toggle');
        const navLink = [...document.querySelectorAll('.worj-nav > ul a')].some(vis);
        const logo = document.querySelector('.worj-logo img');
        const lb = logo ? logo.getBoundingClientRect() : null;
        const clipped = [...document.querySelectorAll('body *')].filter((e) => vis(e) && /hidden|clip/.test(getComputedStyle(e).overflowX) && e.scrollWidth > e.clientWidth + 1 && !e.closest('.pkp_screen_reader')).length;
        return [
          ['no horizontal scroll', document.documentElement.scrollWidth <= cw],
          ['nothing wider than the viewport', wide === 0],
          ['menu reachable (links, or a toggle below 992 px)', width >= 992 ? navLink : !!toggle && vis(toggle)],
          ['header logo visible inside the viewport', !!lb && lb.width > 0 && lb.right <= cw + 0.5 && lb.left >= -0.5],
          ['no clipped content', clipped === 0],
        ];
      }, w);
      r.forEach(([name, ok]) => { result.resp.total += 1; if (ok) result.resp.passed += 1; else result.resp.failures.push(`${pg.name}@${w}: ${name}`); });
      await ctx.close();
    }
  }

  await browser.close();

  if (updateBaseline) {
    const previous = fs.existsSync(BASELINE) ? JSON.parse(fs.readFileSync(BASELINE, 'utf8')) : {};
    fs.writeFileSync(BASELINE, JSON.stringify({ note: 'Written by `node checks/gates.js --update-baseline` after a deliberate review. Gate 7 fails if a page shows fewer [PLACEHOLDER markers than here; simplicity is scored against themeBytes. `components` is the set of score components that were measured when the baseline was recorded; it changes only by hand.', components: previous.components, themeBytes: tb, placeholders }, null, 2) + '\n');
    console.log(`baseline written: themeBytes ${tb}, placeholders ${JSON.stringify(placeholders)}`);
    return;
  }

  const baseline = JSON.parse(fs.readFileSync(BASELINE, 'utf8'));
  for (const [name, min] of Object.entries(baseline.placeholders)) {
    gate('placeholders', (placeholders[name] || 0) >= min, `${name}: ${placeholders[name]} markers (baseline ${min})`);
  }
  result.info.baselineThemeBytes = baseline.themeBytes;
  result.info.baselineComponents = baseline.components || null;
  result.info.placeholders = placeholders;

  for (const [name, g] of Object.entries(result.gates)) {
    console.log(`${g.ok ? 'PASS' : 'FAIL'}  gate ${name}`);
    g.details.filter((d) => d.startsWith('FAIL')).forEach((d) => console.log('      ' + d));
  }
  console.log(`responsiveness: ${result.resp.passed}/${result.resp.total} layout assertions pass${result.resp.failures.length ? '\n      ' + result.resp.failures.slice(0, 8).join('\n      ') : ''}`);
  console.log(`info: ${result.info.fontNote}; whole article page CSS+JS ${result.info.articlePageCssJsBytes} bytes (includes jQuery and jQuery UI, not gated)`);
  if (outPath) fs.writeFileSync(outPath, JSON.stringify(result, null, 2));
  process.exit(Object.values(result.gates).every((g) => g.ok) ? 0 : 1);
})().catch((e) => { console.error(e); process.exit(2); });
