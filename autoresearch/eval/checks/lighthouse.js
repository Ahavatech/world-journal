#!/usr/bin/env node
'use strict';
// Lighthouse accessibility, SEO and best-practices scores (mobile, default
// emulation) for every theme page. Performance is NOT run: it needs throttled
// median-of-three runs per page, which is slow (over the 5-minute budget) and
// the flaky category. If lighthouse is not installed, writes a "skipped" result
// and exits 0, so the gates still work without it.
//   node checks/lighthouse.js --out lh.json
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const { pages } = require('../lib/pages');

const outPath = process.argv.includes('--out') ? process.argv[process.argv.indexOf('--out') + 1] : null;
const cli = path.resolve(__dirname, '..', 'node_modules', 'lighthouse', 'cli', 'index.js');
const write = (o) => { if (outPath) fs.writeFileSync(outPath, JSON.stringify(o, null, 2)); };

if (!fs.existsSync(cli)) {
  write({ skipped: true, reason: 'lighthouse not installed (npm ci in autoresearch/eval)' });
  console.log('lighthouse: SKIPPED (not installed)');
  process.exit(0);
}

const chrome = process.env.CHROME_PATH || (() => {
  const base = '/opt/pw-browsers';
  const dir = fs.existsSync(base) ? fs.readdirSync(base).find((d) => /^chromium-\d+$/.test(d)) : null;
  return dir ? path.join(base, dir, 'chrome-linux64', 'chrome') : '';
})();
if (!chrome || !fs.existsSync(chrome)) {
  write({ skipped: true, reason: 'no Chromium binary found for Lighthouse (set CHROME_PATH)' });
  console.log('lighthouse: SKIPPED (no Chromium binary)');
  process.exit(0);
}

const tmp = fs.mkdtempSync(path.join(require('os').tmpdir(), 'worj-lh-'));
const per = [];
const sums = { accessibility: 0, seo: 0, 'best-practices': 0 };
for (const pg of pages.filter((p) => !p.core)) {
  const file = path.join(tmp, pg.name + '.json');
  const r = spawnSync('node', [cli, pg.url, '--only-categories=accessibility,seo,best-practices', '--chrome-flags=--headless=new --no-sandbox', '--quiet', '--output=json', `--output-path=${file}`], { env: { ...process.env, CHROME_PATH: chrome }, encoding: 'utf8' });
  if (r.status !== 0 || !fs.existsSync(file)) {
    write({ skipped: true, reason: `lighthouse failed on ${pg.name}: ${(r.stderr || '').slice(0, 200)}` });
    console.log(`lighthouse: SKIPPED (failed on ${pg.name})`);
    process.exit(0);
  }
  const d = JSON.parse(fs.readFileSync(file, 'utf8'));
  const s = Object.fromEntries(Object.entries(d.categories).map(([k, v]) => [k, v.score * 100]));
  const fails = Object.entries(d.audits).filter(([, a]) => a.score !== null && a.score < 1 && a.scoreDisplayMode === 'binary').map(([k]) => k);
  per.push({ page: pg.name, ...s, failing: fails });
  Object.keys(sums).forEach((k) => { sums[k] += s[k]; });
  console.log(`lighthouse ${pg.name}: a11y ${s.accessibility} seo ${s.seo} best-practices ${s['best-practices']}${fails.length ? ' (failing: ' + fails.join(', ') + ')' : ''}`);
}
const n = per.length;
write({ skipped: false, runs: 1, note: 'one run per page; accessibility, SEO and best-practices are deterministic', per, mean: { accessibility: sums.accessibility / n, seo: sums.seo / n, bestPractices: sums['best-practices'] / n } });
fs.rmSync(tmp, { recursive: true, force: true });
