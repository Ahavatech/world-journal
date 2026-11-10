#!/usr/bin/env node
'use strict';
// Browser checks for scripts/test-nginx-harness.sh (Chromium through Playwright).
//   node scripts/test-nginx-browser.js axe URL           axe (WCAG 2.0/2.1/2.2 A and AA) on one page
//   node scripts/test-nginx-browser.js csp BASE ROOT     crawl public and admin pages under an ENFORCING test policy
//   node scripts/test-nginx-browser.js assets BASE ROOT  crawl public and admin pages; every sub-resource must load (no 4xx)
// journal.example.org is mapped to 127.0.0.1 inside the browser; the self-signed certificate is accepted.
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');
const [mode, arg1, arg2] = process.argv.slice(2);
const HOST = 'journal.example.org';
// the sandbox sets HTTPS_PROXY for the agent; Chromium would send journal.example.org through it and get a reset,
// so the browser process runs without any *proxy* variable
const cleanEnv = Object.fromEntries(Object.entries(process.env).filter(([k]) => !/proxy/i.test(k)));
const launch = () => chromium.launch({ env: cleanEnv, args: [`--host-resolver-rules=MAP ${HOST} 127.0.0.1`] });

async function axe(url) {
  const { AxeBuilder } = require(path.resolve(__dirname, '..', 'autoresearch/eval/node_modules/@axe-core/playwright'));
  const browser = await launch();
  const ctx = await browser.newContext({ ignoreHTTPSErrors: true, viewport: { width: 1280, height: 900 } });
  const page = await ctx.newPage();
  const res = await page.goto(url, { waitUntil: 'networkidle' });
  let bad = 0;
  const report = (ok, msg) => { console.log(`${ok ? 'PASS' : 'FAIL'}  ${msg}`); if (!ok) bad += 1; };
  report(res.status() === 404, `404 page status is 404 (got ${res.status()})`);
  for (const w of [1280, 320]) {
    await page.setViewportSize({ width: w, height: 900 });
    const r = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa']).analyze();
    report(r.violations.length === 0, `axe on the static 404 page at ${w}px: ${r.violations.length} violation(s), ${r.passes.length} rules passed${r.violations.length ? ' (' + r.violations.map((v) => v.id).join(', ') + ')' : ''}`);
  }
  report((await page.locator('h1').count()) === 1, 'exactly one h1');
  report((await page.locator('html[lang=en]').count()) === 1, 'html lang="en"');
  report((await page.title()).startsWith('Page not found'), `title: "${await page.title()}"`);
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  report(overflow <= 0, `no horizontal overflow at 320px (${overflow}px)`);
  await browser.close();
  return bad;
}

async function csp(base, root) {
  const env = Object.fromEntries(fs.readFileSync(path.join(root, '.env.sandbox'), 'utf8').trim().split('\n').map((l) => l.split(/=(.*)/s).slice(0, 2)));
  const { pages } = require(path.join(root, 'autoresearch/eval/lib/pages.js'));
  const publicPaths = [...new Set([...pages.map((p) => p.path), '/worj/article/view/1/1', '/worj/about/contact', '/worj/announcement'])];
  const adminPaths = ['/worj/dashboard/editorial', '/worj/management/settings/context', '/worj/management/settings/website', '/worj/management/settings/workflow',
    '/worj/management/settings/distribution', '/worj/management/settings/access', '/index/admin/index'];
  const browser = await launch();
  const ctx = await browser.newContext({ ignoreHTTPSErrors: true });
  await ctx.addInitScript(() => {
    window.__csp = [];
    document.addEventListener('securitypolicyviolation', (e) => window.__csp.push(`${e.violatedDirective} <- ${(e.blockedURI || '').slice(0, 70)}${e.sample ? ' [' + e.sample.slice(0, 30) + ']' : ''}`));
  });
  const page = await ctx.newPage();
  const consoleCsp = [];
  page.on('console', (m) => { if (/Content Security Policy|Refused to/.test(m.text())) consoleCsp.push(m.text().slice(0, 140)); });
  const visit = async (urlPath) => {
    consoleCsp.length = 0;
    let status = 0;
    try { status = (await page.goto(base + urlPath, { waitUntil: 'networkidle', timeout: 30000 })).status(); } catch (e) { return { urlPath, status: 0, viol: ['navigation error: ' + e.message.slice(0, 60)] }; }
    await page.waitForTimeout(1200);
    const viol = await page.evaluate(() => window.__csp || []);
    return { urlPath, status, viol: [...new Set([...viol, ...consoleCsp.map((c) => 'console: ' + c)])] };
  };
  const summarise = (label, results) => {
    const all = new Map();
    for (const r of results) {
      console.log(`  ${String(r.viol.length).padStart(3)} violation(s)  ${r.status}  ${r.urlPath}`);
      r.viol.forEach((v) => all.set(v, (all.get(v) || 0) + 1));
    }
    const total = results.reduce((n, r) => n + r.viol.length, 0);
    console.log(`CSP RESULT (${label}): ${total} violation(s) on ${results.length} page(s), ${all.size} distinct`);
    [...all.entries()].slice(0, 12).forEach(([v, n]) => console.log(`      ${n}x ${v}`));
    return total;
  };
  console.log('--- public pages, ENFORCING test policy (default-src self; script-src self; style-src self; ...)');
  const pub = [];
  for (const p of publicPaths) pub.push(await visit(p));
  const pubTotal = summarise('public', pub);
  await page.goto(base + '/worj/login', { waitUntil: 'networkidle' });
  await page.fill('input[name=username]', env.SANDBOX_ADMIN_USER);
  await page.fill('input[name=password]', env.SANDBOX_ADMIN_PASSWORD);
  await Promise.all([page.waitForEvent('load'), page.click('button[type=submit]')]);
  console.log('--- logged-in admin pages, same policy applied (informational: the shipped config sends NO policy there)');
  const adm = [];
  for (const p of adminPaths) adm.push(await visit(p));
  summarise('admin', adm);
  await browser.close();
  console.log(pubTotal === 0
    ? 'CSP DECISION INPUT: zero violations on the public pages in this crawl. Enforcing on public paths is possible after a human review; it is still report-only in the shipped config.'
    : 'CSP DECISION INPUT: violations on public pages: keep Report-Only; fix or allow-list them before any enforcement.');
  return process.env.CSP_STRICT === '1' && pubTotal > 0 ? 1 : 0;
}

// Every page must load every sub-resource: a deny rule that is too wide shows up as a 4xx script or style.
async function assets(base, root) {
  const env = Object.fromEntries(fs.readFileSync(path.join(root, '.env.sandbox'), 'utf8').trim().split('\n').map((l) => l.split(/=(.*)/s).slice(0, 2)));
  const { pages } = require(path.join(root, 'autoresearch/eval/lib/pages.js'));
  const publicPaths = [...new Set([...pages.filter((p) => !p.core).map((p) => p.path), '/worj/article/view/1/1', '/worj/announcement'])];
  const adminPaths = ['/worj/dashboard/editorial', '/worj/submissions', '/worj/management/settings/context', '/worj/management/settings/website', '/worj/management/settings/workflow',
    '/worj/management/settings/distribution', '/worj/management/settings/access', '/worj/management/importexport', '/index/admin/index', '/index/admin/contexts'];
  const browser = await launch();
  const ctx = await browser.newContext({ ignoreHTTPSErrors: true });
  const page = await ctx.newPage();
  let failed = [];
  page.on('response', (r) => { if (r.status() >= 400 && !r.url().includes('/_errors/')) failed.push(`${r.status()} ${r.url().replace(base, '').slice(0, 110)}`); });
  page.on('requestfailed', (r) => failed.push(`FAILED ${r.url().replace(base, '').slice(0, 100)} (${r.failure() && r.failure().errorText})`));
  let bad = 0;
  const visit = async (urlPath, label) => {
    failed = [];
    let st = 0;
    try { st = (await page.goto(base + urlPath, { waitUntil: 'networkidle', timeout: 30000 })).status(); } catch (e) { failed.push('navigation: ' + e.message.slice(0, 60)); }
    await page.waitForTimeout(500);
    const nav = failed.filter((f) => f.startsWith(String(st) + ' ' + urlPath));
    // the Plugin Gallery grid fetches the plugin list from pkp.sfu.ca on the server; php-fpm in this sandbox cannot reach it (docs/ENV-REPORT.md)
    const known = failed.filter((f) => f.includes('plugin-gallery-grid'));
    const own = failed.filter((f) => !nav.includes(f) && !known.includes(f));
    console.log(`${own.length ? 'FAIL' : 'PASS'}  ${label} ${urlPath}: page ${st}, ${own.length} failed sub-resource(s)${known.length ? ' (+' + known.length + ' known: plugin gallery needs pkp.sfu.ca)' : ''}${own.length ? '\n        ' + own.slice(0, 6).join('\n        ') : ''}`);
    if (own.length) bad += 1;
  };
  for (const p of publicPaths) await visit(p, 'public');
  await page.goto(base + '/worj/login', { waitUntil: 'networkidle' });
  await page.fill('input[name=username]', env.SANDBOX_ADMIN_USER);
  await page.fill('input[name=password]', env.SANDBOX_ADMIN_PASSWORD);
  await Promise.all([page.waitForEvent('load'), page.click('button[type=submit]')]);
  for (const p of adminPaths) await visit(p, 'admin ');
  await browser.close();
  return bad;
}

(async () => {
  const bad = mode === 'assets' ? await assets(arg1, arg2) : mode === 'axe' ? await axe(arg1) : mode === 'csp' ? await csp(arg1, arg2) : (console.error('usage: axe URL | csp BASE ROOT | assets BASE ROOT'), 2);
  process.exit(bad ? 1 : 0);
})().catch((e) => { console.error(e.message); process.exit(1); });
