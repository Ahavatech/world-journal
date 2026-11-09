// Nav regression test: keyboard, aria-expanded, dropdown focus, Escape, JS off.
// Needs the sandbox running (make sandbox-up sandbox-seed) and Playwright.
'use strict';
const { chromium } = require('playwright');
const url = (process.env.SANDBOX_URL || 'http://127.0.0.1:8082') + '/worj/article/view/1';
const ok = (c, m) => { console.log((c ? 'PASS ' : 'FAIL ') + m); if (!c) process.exitCode = 1; };
(async () => {
  const b = await chromium.launch();
  // --- small screen, JS on
  let page = await b.newPage({ viewport: { width: 375, height: 800 } });
  await page.goto(url, { waitUntil: 'networkidle' });
  const t = page.locator('.worj-nav-toggle');
  ok(await t.isVisible(), 'JS on, 375px: toggle visible');
  ok(!(await page.locator('#worj-nav-panel').isVisible()), 'JS on, 375px: menu collapsed');
  ok((await t.getAttribute('aria-expanded')) === 'false', 'aria-expanded=false initially');
  await t.focus(); await page.keyboard.press('Enter');
  ok((await t.getAttribute('aria-expanded')) === 'true' && await page.locator('#worj-nav-panel').isVisible(), 'Enter on toggle opens menu, aria-expanded=true');
  await page.keyboard.press('Escape');
  ok((await t.getAttribute('aria-expanded')) === 'false' && !(await page.locator('#worj-nav-panel').isVisible()), 'Escape closes menu');
  ok(await page.evaluate(() => document.activeElement.classList.contains('worj-nav-toggle')), 'focus returns to toggle');
  const ring = await t.evaluate(e => { e.focus(); const c = getComputedStyle(e); return c.outlineStyle + ' ' + c.outlineWidth; });
  ok(/solid 3px/.test(ring) || /auto/.test(ring), 'toggle has a visible focus outline: ' + ring);
  await page.close();
  // --- wide, JS on: dropdown by keyboard
  page = await b.newPage({ viewport: { width: 1280, height: 800 } });
  await page.goto(url, { waitUntil: 'networkidle' });
  ok(!(await page.locator('.worj-nav-toggle').isVisible()), '1280px: no toggle');
  const sub = page.locator('.worj-nav > ul > li:has(> ul) > ul');
  ok(!(await sub.first().isVisible()), 'submenu hidden at rest');
  await page.locator('.worj-nav > ul > li:has(> ul) > a').first().focus();
  ok(await sub.first().isVisible(), 'focus on "About" opens submenu (no hover needed)');
  await page.keyboard.press('Tab');
  ok(await sub.first().isVisible() && await page.evaluate(() => !!document.activeElement.closest('.worj-nav li li')), 'Tab moves into submenu, still open');
  await page.keyboard.press('Escape');
  ok(!(await sub.first().isVisible()), 'Escape closes submenu');
  ok(await page.evaluate(() => document.activeElement.parentElement.matches('.worj-nav > ul > li')), 'focus on parent link after Escape');
  await page.close();
  // --- JS off
  const ctx = await b.newContext({ javaScriptEnabled: false, viewport: { width: 375, height: 800 } });
  page = await ctx.newPage();
  await page.goto(url, { waitUntil: 'load' });
  ok(!(await page.locator('.worj-nav-toggle').isVisible()), 'JS off, 375px: no dead toggle button');
  ok(await page.locator('#worj-nav-panel').isVisible() && await page.locator('.worj-nav a', { hasText: 'Archives' }).isVisible(), 'JS off, 375px: menu visible and reachable');
  await b.close();
})();
