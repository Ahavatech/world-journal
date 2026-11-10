#!/usr/bin/env node
// Write the placeholder texts that live in journal SETTINGS (about, privacy,
// author guidelines, information, editorial team, contact) from
// ojs/content/pages.json through the REST API. The custom pages are handled by
// scripts/import-pages.php.
//
// SAFE BY DEFAULT.
//  - It logs in with the generated admin credentials, so it REFUSES to run unless
//    SANDBOX_URL points at localhost, 127.0.0.1 or ::1.
//  - A setting is written only when it is empty. With --force-sandbox it is also
//    refreshed while it still contains the placeholder banner (or, for contact
//    fields, a placeholder value). Text a human has changed is never touched.
//
// Usage: node scripts/sandbox-content.js [--check] [--force-sandbox]
//   --check  print what would happen, change nothing
'use strict';
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const args = process.argv.slice(2);
const dryRun = args.includes('--check');
const force = args.includes('--force-sandbox');
const base = process.env.SANDBOX_URL || 'http://127.0.0.1:8082';

const host = new URL(base).hostname.replace(/^\[|\]$/g, '').toLowerCase();
if (!['localhost', '127.0.0.1', '::1'].includes(host)) {
  console.error(`REFUSED: sandbox-content.js only runs against localhost (SANDBOX_URL host is '${host}').`);
  process.exit(3);
}

const { chromium } = require('playwright');
const { guarded, assertId } = require('./lib/sandbox-guard');
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'ojs/content/pages.json'), 'utf8'));
const BANNER = '[PLACEHOLDER: replace with client-approved text]';
const env = Object.fromEntries(
  fs.readFileSync(path.join(root, '.env.sandbox'), 'utf8').trim().split('\n').map((l) => l.split(/=(.*)/s).slice(0, 2)));

const isPlaceholderValue = (v) => /\[PLACEHOLDER|\.invalid/i.test(v) || /^Placeholder /.test(v);

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
  const rawCall = async (method, url, data) => {
    const r = await ctx.request.fetch(base + url, { method, data, headers: { 'X-Csrf-Token': csrf, 'Content-Type': 'application/json' } });
    const text = await r.text();
    if (!r.ok()) throw new Error(`${method} ${url} -> ${r.status()} ${text.slice(0, 300)}`);
    return JSON.parse(text);
  };
  const call = guarded(rawCall); // refuses empty ids and writes to items that do not exist

  const id = assertId((await call('GET', '/index/api/v1/contexts')).items.find((c) => c.urlPath === 'worj')?.id, 'worj context id');
  const current = await call('GET', `/worj/api/v1/contexts/${id}`);
  const locale = current.primaryLocale || 'en';
  const counts = { written: 0, kept: 0, edited: 0, rejected: 0 };

  const apply = async (label, settingName, html, isHtml, extra = {}) => {
    // HTML texts are localized objects; the contact fields are plain strings
    const raw = current[settingName];
    const existing = (raw && typeof raw === 'object' ? raw[locale] : raw) || '';
    let action;
    if (!existing) action = 'write';
    else if (isHtml ? !existing.includes(BANNER) : !isPlaceholderValue(existing)) action = 'edited';
    else action = force ? 'write' : 'keep';
    if (action === 'edited') { console.log(`leave   ${label}  (edited by a human)`); counts.edited++; return false; }
    if (action === 'keep') { console.log(`skip    ${label}  (exists; create-only)`); counts.kept++; return false; }
    console.log(`${dryRun ? 'would write' : 'write'}  ${label}`);
    if (!dryRun) {
      try {
        await call('PUT', `/worj/api/v1/contexts/${id}`, { [settingName]: isHtml ? { [locale]: html } : html, ...extra });
      } catch (e) {
        // OJS may reject a placeholder value on save: report it, never substitute a plausible one.
        console.log(`REJECTED ${label}: ${e.message.slice(0, 200)}`);
        counts.rejected++;
        return false;
      }
    }
    counts.written++;
    return true;
  };

  for (const p of manifest.pages.filter((x) => x.mechanism === 'setting')) {
    const html = fs.readFileSync(path.join(root, 'ojs/content', p.file), 'utf8');
    if (!html.includes(BANNER)) { console.error(`ERROR: ${p.file} has no placeholder banner`); process.exit(2); }
    await apply(`${p.setting}  (${p.url})`, p.setting, html, true, p.flags || {});
  }
  for (const [name, value] of Object.entries(manifest.contact.settings)) {
    await apply(`${name}  (${manifest.contact.url})`, name, value, false);
  }
  console.log(`${dryRun ? 'dry run' : 'done'}: ${counts.written} written, ${counts.kept} skipped, ${counts.edited} left alone (edited), ${counts.rejected} rejected by OJS`);
  await browser.close();
}
main().catch((e) => { console.error(e.message); process.exit(1); });
