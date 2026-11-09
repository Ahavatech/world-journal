#!/usr/bin/env node
// Call the sandbox OJS REST API as the generated admin (credentials from
// .env.sandbox). Sandbox only. Usage:
//   node scripts/sandbox-api.js METHOD PATH [JSON_BODY]
//   node scripts/sandbox-api.js PUT /worj/api/v1/contexts/1/theme '{"themePluginPath":"worj","showAwardsCard":true}'
// N=2000 prints more of the response (default 400 characters).
'use strict';
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const env = Object.fromEntries(
  fs.readFileSync(path.resolve(__dirname, '..', '.env.sandbox'), 'utf8').trim().split('\n')
    .map((l) => l.split(/=(.*)/s).slice(0, 2)));
const base = process.env.SANDBOX_URL || 'http://127.0.0.1:8082';
const [method, apiPath, body] = process.argv.slice(2);
if (!method || !apiPath) {
  console.error('usage: sandbox-api.js METHOD PATH [JSON_BODY]');
  process.exit(2);
}

(async () => {
  const browser = await chromium.launch();
  const ctx = await browser.newContext();
  const page = await ctx.newPage();
  await page.goto(`${base}/index/login`);
  await page.fill('input[name=username]', env.SANDBOX_ADMIN_USER);
  await page.fill('input[name=password]', env.SANDBOX_ADMIN_PASSWORD);
  await Promise.all([page.waitForLoadState('load'), page.click('button[type=submit]')]);
  await page.goto(`${base}/index/admin/contexts`);
  const csrf = await page.evaluate(() => document.querySelector('meta[name=csrf-token]')?.content);
  const r = await ctx.request.fetch(base + apiPath, {
    method,
    headers: { 'X-Csrf-Token': csrf, 'Content-Type': 'application/json' },
    data: body ? JSON.parse(body) : undefined,
  });
  console.log(r.status(), (await r.text()).slice(0, Number(process.env.N || 400)));
  await browser.close();
})().catch((e) => { console.error(e.message); process.exit(1); });
