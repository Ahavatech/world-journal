#!/usr/bin/env node
'use strict';
// Server-side form errors: after a failed login and a failed registration, the
// error must be announced (role=alert, focused) and tied to its fields
// (aria-invalid, aria-describedby); axe must find nothing on the error pages.
// Needs the sandbox (make sandbox-up sandbox-seed). Exit 1 on any FAIL.
const { chromium } = require('playwright');
const { AxeBuilder } = require('@axe-core/playwright');
const { base } = require('../lib/pages');

// EVAL_CPU_THROTTLE=8 slows the page 8x to expose timing races in the test or the page.
const throttle = Number(process.env.EVAL_CPU_THROTTLE || 1);
async function newPage(browser) {
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  const page = await ctx.newPage();
  if (throttle > 1) { await (await ctx.newCDPSession(page)).send('Emulation.setCPUThrottlingRate', { rate: throttle }); }
  return { ctx, page };
}

let fails = 0;
const check = (ok, msg) => { if (!ok) fails += 1; console.log((ok ? 'PASS  ' : 'FAIL  ') + msg); };

async function inspect(page, label, fieldNames) {
  if (!fieldNames) {
    fieldNames = await page.evaluate(() => [...document.querySelectorAll('#formErrors li a')].map((a) => a.getAttribute('href').slice(1)));
    check(fieldNames.length > 0, `${label}: error list links to ${fieldNames.length} field(s): ${fieldNames.join(', ')}`);
  }
  const r = await page.evaluate((names) => {
    const box = document.getElementById('formErrors') || document.querySelector('form .pkp_form_error');
    if (!box) return { box: false };
    const f = (n) => document.getElementById(n) || document.querySelector(`[name="${n}"]`);
    return {
      box: true, role: box.getAttribute('role'), focused: document.activeElement === box,
      fields: names.map((n) => { const e = f(n); return e && { n, invalid: e.getAttribute('aria-invalid'), described: (e.getAttribute('aria-describedby') || '').split(' ').includes(box.id) }; }),
    };
  }, fieldNames);
  check(r.box, `${label}: error message present`);
  if (!r.box) return;
  check(r.role === 'alert', `${label}: role="alert"`);
  check(r.focused, `${label}: focus moved to the error message`);
  r.fields.forEach((x) => { if (x) check(x.invalid === 'true' && x.described, `${label}: field "${x.n}" has aria-invalid and aria-describedby -> error`); });
  const axe = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa']).analyze();
  check(axe.violations.length === 0, `${label}: axe violations ${axe.violations.length}${axe.violations.length ? ' (' + axe.violations.map((v) => v.id).join(', ') + ')' : ''}`);
}

(async () => {
  const browser = await chromium.launch();
  let { ctx, page } = await newPage(browser);
  await page.goto(base + '/worj/login', { waitUntil: 'networkidle' });
  await page.fill('input[name=username]', 'nobody');
  await page.fill('input[name=password]', 'wrong-password-123');
  // wait for the NEW page's load event (registered before the click). waitForLoadState('load')
  // resolves at once because the old page is already loaded, so the check ran mid-parse
  // and forms.js had not executed yet (a race that only showed under load).
  await Promise.all([page.waitForEvent('load'), page.click('button.submit')]);
  await inspect(page, 'failed login', ['username', 'password']);
  await ctx.close();

  ({ ctx, page } = await newPage(browser));
  await page.goto(base + '/worj/user/register', { waitUntil: 'networkidle' });
  const fill = async (sel, v) => { const e = page.locator(sel).first(); if (await e.count()) await e.fill(v); };
  await fill('input[name=givenName]', 'Test');
  await fill('input[name=familyName]', 'Person');
  await fill('input[name=affiliation]', 'Placeholder Institution');
  await fill('input[name=email]', 'test.person@example.invalid');
  await fill('input[name=username]', 'admin'); // already exists
  await fill('input[name=password]', 'a-long-password-1');
  await fill('input[name=password2]', 'a-different-password-2'); // mismatch
  const country = page.locator('select[name=country]');
  if (await country.count()) await country.selectOption({ index: 1 });
  const privacy = page.locator('input[name=privacyConsent\\[\\]], input[name=privacyConsent]');
  for (let i = 0; i < await privacy.count(); i++) await privacy.nth(i).check();
  await Promise.all([page.waitForEvent('load'), page.click('button.submit')]);
  await inspect(page, 'failed registration');
  await ctx.close();
  await browser.close();
  console.log(`RESULT: ${fails ? 'FAIL (' + fails + ')' : 'PASS'}`);
  process.exit(fails ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(2); });
