#!/usr/bin/env node
// Seed the sandbox OJS (see scripts/sandbox-ojs.sh): create the journal if
// missing and activate the worj theme. Idempotent. Sandbox only: it logs in
// as the generated admin from .env.sandbox through Playwright.
// Requires: `playwright` resolvable (preinstalled in the Claude sandbox).
'use strict';
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const root = path.resolve(__dirname, '..');
const env = Object.fromEntries(
  fs.readFileSync(path.join(root, '.env.sandbox'), 'utf8').trim().split('\n')
    .map((l) => l.split(/=(.*)/s).slice(0, 2)));
const base = process.env.SANDBOX_URL || 'http://127.0.0.1:8082';

async function main() {
  const browser = await chromium.launch();
  const ctx = await browser.newContext();
  const page = await ctx.newPage();
  await page.goto(`${base}/index/login`);
  await page.fill('input[name=username]', env.SANDBOX_ADMIN_USER);
  await page.fill('input[name=password]', env.SANDBOX_ADMIN_PASSWORD);
  await Promise.all([page.waitForLoadState('load'), page.click('button[type=submit]')]);
  await page.goto(`${base}/index/admin/contexts`);
  const csrf = await page.evaluate(() => document.querySelector('meta[name=csrf-token]')?.content);
  const call = async (method, url, data) => {
    const r = await ctx.request.fetch(base + url, {
      method, data,
      headers: { 'X-Csrf-Token': csrf, 'Content-Type': 'application/json' },
    });
    if (!r.ok()) throw new Error(`${method} ${url} -> ${r.status()} ${(await r.text()).slice(0, 300)}`);
    return r.json();
  };

  const list = await call('GET', '/index/api/v1/contexts');
  if (!list.items.some((c) => c.urlPath === 'worj')) {
    await call('POST', '/index/api/v1/contexts', {
      urlPath: 'worj', name: { en: 'World Open Research Journal' }, acronym: { en: 'WORJ' },
      primaryLocale: 'en', supportedLocales: ['en'], supportedFormLocales: ['en'],
      supportedSubmissionLocales: ['en'], contactName: 'Placeholder Contact',
      contactEmail: 'contact@example.invalid', description: { en: '[PLACEHOLDER: description]' },
    });
    console.log('created journal worj');
  }
  const ctxs = (await call('GET', '/index/api/v1/contexts')).items;
  const id = ctxs.find((c) => c.urlPath === 'worj').id;
  await call('PUT', `/worj/api/v1/contexts/${id}`, { themePluginPath: 'worj' });
  console.log(`journal worj (id ${id}) uses theme worj`);
  await browser.close();
}
main().catch((e) => { console.error(e.message); process.exit(1); });
