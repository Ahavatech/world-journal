#!/usr/bin/env node
// Seed the sandbox OJS (see scripts/sandbox-ojs.sh): create the journal if
// missing and activate the worj theme. Idempotent. Sandbox only: it logs in
// as the generated admin from .env.sandbox through Playwright.
// Requires: `playwright` resolvable (preinstalled in the Claude sandbox).
'use strict';
const fs = require('fs');
const { execFileSync } = require('child_process');
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
  await Promise.all([page.waitForEvent('load'), page.click('button[type=submit]')]);
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
  let created = false;
  if (!list.items.some((c) => c.urlPath === 'worj')) {
    created = true;
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
  await call('PUT', `/worj/api/v1/contexts/${id}`, { themePluginPath: 'worj', description: { en: '[PLACEHOLDER: short description of the journal, aims and scope]' } });
  console.log(`journal worj (id ${id}) uses theme worj`);

  // Three placeholder announcements for the homepage (created once)
  await call('PUT', `/worj/api/v1/contexts/${id}`, { enableAnnouncements: true, numAnnouncementsHomepage: 3 });
  const existing = await call('GET', '/worj/api/v1/announcements?count=50');
  for (let n = existing.items.length + 1; n <= 3; n += 1) {
    await call('POST', '/worj/api/v1/announcements', {
      contextId: id,
      title: { en: `[PLACEHOLDER] Sample announcement ${n}` },
      descriptionShort: { en: `[PLACEHOLDER: sample announcement text ${n}. Not real news.]` },
      description: { en: '<p>[PLACEHOLDER: sample announcement body.]</p>' },
    });
    console.log(`created placeholder announcement ${n}`);
  }

  // Placeholder content (Phase 3). OJS ships default text in some of these settings and an older seed
  // wrote other text; neither is a placeholder, so the content script would (correctly) treat it as
  // human-edited and leave it. In a fresh sandbox, or with SANDBOX_RESET_CONTENT=1, empty them first.
  if (created || process.env.SANDBOX_RESET_CONTENT === '1') {
    const empty = { en: '' };
    await call('PUT', `/worj/api/v1/contexts/${id}`, { about: empty, privacyStatement: empty, authorGuidelines: empty, readerInformation: empty, authorInformation: empty, librarianInformation: empty, editorialHistory: empty });
    console.log('emptied the content settings (fresh sandbox or SANDBOX_RESET_CONTENT=1)');
  }
  const here = __dirname;
  execFileSync('node', [path.join(here, 'sandbox-content.js'), '--force-sandbox'], { stdio: 'inherit' });
  execFileSync('php', [path.join(here, 'import-pages.php'), '--journal=worj'], { stdio: ['ignore', 'inherit', 'ignore'] });

  // Sidebar state for layout testing: SANDBOX_SIDEBAR=blocks (default) | none | empty
  //   blocks: Make a Submission + Information (the information texts come from the content step)
  //   none:   no sidebar configured
  //   empty:  a block is configured but renders nothing
  const state = process.env.SANDBOX_SIDEBAR || 'blocks';
  const info = () => ({ en: '' });
  const sidebars = {
    blocks: { sidebar: ['makesubmissionblockplugin', 'informationblockplugin'] },
    none: { sidebar: [] },
    empty: { sidebar: ['informationblockplugin'], readerInformation: info(), authorInformation: info(), librarianInformation: info() },
  };
  if (!sidebars[state]) throw new Error(`SANDBOX_SIDEBAR must be blocks, none or empty (got ${state})`);
  await call('PUT', `/worj/api/v1/contexts/${id}`, sidebars[state]);
  console.log(`sidebar state: ${state}`);

  // The homepage Awards card links to /awards: turn it on only if that page really returns 200.
  const awards = await ctx.request.get(`${base}/worj/awards`);
  const cardOn = awards.status() === 200;
  await call('PUT', `/worj/api/v1/contexts/${id}/theme`, { themePluginPath: 'worj', showAwardsCard: cardOn });
  console.log(`/awards returned ${awards.status()}: showAwardsCard ${cardOn ? 'ON' : 'OFF'}`);
  await browser.close();
}
main().catch((e) => { console.error(e.message); process.exit(1); });
