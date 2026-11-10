#!/usr/bin/env node
'use strict';
// Automated parts of the WCAG 2.2 manual pass, run on every page.
//   node checks/a11y-manual.js [section ...]   sections: structure keyboard targets reflow contrast motion
// Exit 1 if any check FAILs. This is not a compliance claim: it covers only what
// these checks measure (see docs/A11Y-REPORT.md for what is not covered).
const { chromium } = require('playwright');
const { PNG } = require('pngjs');
const { pages } = require('../lib/pages');

const wanted = process.argv.slice(2);
const want = (s) => wanted.length === 0 || wanted.includes(s);
let fails = 0;
const fail = (m) => { fails += 1; console.log('FAIL  ' + m); };
const pass = (m) => console.log('PASS  ' + m);
const note = (m) => console.log('NOTE  ' + m);

// ---- colour maths (WCAG 2.x relative luminance) ----
const lum = ([r, g, b]) => {
  const f = (v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; };
  return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
};
const ratio = (a, b) => { const [hi, lo] = [lum(a), lum(b)].sort((x, y) => y - x); return (hi + 0.05) / (lo + 0.05); };

// Runs in the page: effective colours and a short description of an element.
const inPage = `
  window.__rgba = (s) => { const m = s.match(/[\\d.]+/g).map(Number); return { r: m[0], g: m[1], b: m[2], a: m.length > 3 ? m[3] : 1 }; };
  window.__effBg = (el) => {
    const stack = [];
    for (let e = el; e; e = e.parentElement) {
      const c = getComputedStyle(e);
      if (c.backgroundImage !== 'none') { return { image: true, rgb: [255, 255, 255] }; }
      const k = window.__rgba(c.backgroundColor);
      if (k.a > 0) { stack.push(k); if (k.a >= 1) break; }
    }
    let out = [255, 255, 255];
    for (let i = stack.length - 1; i >= 0; i--) { const k = stack[i]; out = [k.r * k.a + out[0] * (1 - k.a), k.g * k.a + out[1] * (1 - k.a), k.b * k.a + out[2] * (1 - k.a)]; }
    return { image: false, rgb: out };
  };
  window.__desc = (el) => { const t = (el.getAttribute('aria-label') || el.innerText || el.value || '').trim().replace(/\\s+/g, ' ').slice(0, 40); return el.tagName.toLowerCase() + (el.id ? '#' + el.id : '') + (el.className && typeof el.className === 'string' ? '.' + el.className.trim().split(/\\s+/)[0] : '') + (t ? ' "' + t + '"' : ''); };
  window.__visible = (el) => { const r = el.getBoundingClientRect(); const c = getComputedStyle(el); return r.width > 0 && r.height > 0 && c.visibility !== 'hidden' && c.display !== 'none'; };
`;

async function open(browser, pg, width) {
  const ctx = await browser.newContext({ viewport: { width, height: 900 } });
  const page = await ctx.newPage();
  const res = await page.goto(pg.url, { waitUntil: 'networkidle' });
  await page.evaluate(inPage);
  return { ctx, page, status: res.status() };
}

// ---------------- structure ----------------
async function structure(browser) {
  console.log('\n== structure (1280 px)');
  for (const pg of pages) {
    const { ctx, page } = await open(browser, pg, 1280);
    const r = await page.evaluate(() => {
      const vis = (e) => window.__visible(e) || e.classList.contains('pkp_screen_reader');
      const heads = [...document.querySelectorAll('h1,h2,h3,h4,h5,h6')].filter((e) => getComputedStyle(e).display !== 'none');
      const levels = heads.map((h) => +h.tagName[1]);
      const skips = [];
      levels.forEach((l, i) => { if (i === 0 ? l !== 1 : l > levels[i - 1] + 1) skips.push(`${heads[i].tagName}"${heads[i].innerText.trim().slice(0, 25)}" after ${i ? 'H' + levels[i - 1] : 'start'}`); });
      const navs = [...document.querySelectorAll('nav')].map((n) => ({ name: n.getAttribute('aria-label') || (n.getAttribute('aria-labelledby') ? document.getElementById(n.getAttribute('aria-labelledby'))?.innerText : '') || '' }));
      const generic = /^(read more|more|click here|here|link|learn more)$/i;
      const links = [...document.querySelectorAll('a[href]')].filter(vis).map((a) => ({ text: (a.getAttribute('aria-label') || a.textContent).trim().replace(/\\s+/g, ' '), href: a.href }));
      const dup = {};
      links.forEach((l) => { (dup[l.text] = dup[l.text] || new Set()).add(l.href); });
      return {
        h1: heads.filter((h) => h.tagName === 'H1').length, skips, lang: document.documentElement.getAttribute('lang'), title: document.title.trim(),
        navs, main: document.querySelectorAll('main, [role=main]').length, banner: document.querySelectorAll('header, [role=banner]').length, contentinfo: document.querySelectorAll('footer, [role=contentinfo]').length,
        genericLinks: links.filter((l) => generic.test(l.text)).map((l) => l.text + ' -> ' + l.href),
        repeated: Object.entries(dup).filter(([t, h]) => h.size > 1 && t.length < 12).map(([t, h]) => `"${t}" x${h.size}`),
      };
    });
    const bad = [];
    if (r.h1 !== 1) bad.push(`${r.h1} h1`);
    if (r.skips.length) bad.push('heading skips: ' + r.skips.join('; '));
    if (!/^[a-z]{2,3}(-[A-Za-z0-9]+)*$/.test(r.lang || '')) bad.push(`lang="${r.lang}"`);
    if (!r.title) bad.push('empty title');
    if (r.navs.length > 1 && r.navs.some((n) => !n.name)) bad.push('unlabelled nav among ' + r.navs.length);
    if (r.main !== 1) bad.push(`${r.main} main landmarks`);
    if (r.banner !== 1) bad.push(`${r.banner} banner landmarks`);
    if (r.contentinfo !== 1) bad.push(`${r.contentinfo} contentinfo landmarks`);
    if (r.genericLinks.length) bad.push('generic link text: ' + r.genericLinks.join(', '));
    if (bad.length) { (pg.core ? note : fail)(`${pg.name}${pg.core ? ' (core-owned markup)' : ''}: ${bad.join(' | ')}`); } else { pass(`${pg.name}: 1 h1, no heading skips, lang=${r.lang}, ${r.navs.length} labelled navs, 1 main/banner/contentinfo`); }
    if (r.repeated.length) note(`${pg.name}: same link text, different targets: ${r.repeated.join(', ')} (context comes from the same list item or the same destination page)`);
    await ctx.close();
  }
}

// ---------------- keyboard, skip link, focus appearance, not obscured ----------------
async function keyboard(browser) {
  console.log('\n== keyboard, skip link, focus appearance (1280 px)');
  const ringWorst = { r: 99, who: '' };
  for (const pg of pages.filter((p) => !p.core)) {
    const { ctx, page } = await open(browser, pg, 1280);
    const sticky = await page.evaluate(() => [...document.querySelectorAll('body *')].filter((e) => ['fixed', 'sticky'].includes(getComputedStyle(e).position)).map(window.__desc));
    const stops = [];
    let first = null;
    let returned = false;
    for (let i = 0; i < 90; i++) {
      await page.keyboard.press('Tab');
      const s = await page.evaluate(() => {
        const e = document.activeElement;
        if (!e || e === document.body) return null;
        const c = getComputedStyle(e); const r = e.getBoundingClientRect();
        const bg = window.__effBg(e); const pbg = window.__effBg(e.parentElement || e);
        const top = document.elementFromPoint(Math.min(Math.max(r.left + r.width / 2, 0), innerWidth - 1), Math.min(Math.max(r.top + r.height / 2, 0), innerHeight - 1));
        return { d: window.__desc(e), key: e.outerHTML.slice(0, 80), outline: c.outlineStyle + ' ' + c.outlineWidth, ring: c.outlineColor, shadow: c.boxShadow, inView: r.bottom > 0 && r.right > 0 && r.top < innerHeight && r.left < innerWidth, w: r.width, h: r.height,
          obscured: !(top === e || e.contains(top) || (top && top.contains(e))), own: bg.rgb, around: pbg.rgb, ownImage: bg.image, rgbaRing: c.outlineColor };
      });
      if (!s) { returned = true; break; }
      if (first === null) first = s.key;
      else if (s.key === first) { returned = true; break; }
      stops.push(s);
    }
    const issues = [];
    if (!returned) issues.push('focus never left or cycled within 90 Tabs (possible trap)');
    const skip = stops[0];
    if (!skip || !/Skip/i.test(skip.d)) issues.push('first Tab stop is not the skip link: ' + (skip && skip.d));
    else if (!skip.inView || skip.w < 1) issues.push('skip link is not visible on focus');
    for (const s of stops) {
      const hasRing = (s.outline && !s.outline.startsWith('none') && !s.outline.endsWith(' 0px')) || (s.shadow && s.shadow !== 'none');
      if (!hasRing) { issues.push('no visible focus indicator: ' + s.d); continue; }
      if (s.obscured) issues.push('focused control obscured: ' + s.d);
      const m = s.ring.match(/[\d.]+/g).map(Number);
      const rgb = m.slice(0, 3);
      for (const [label, bg] of [['page', s.around], ['element', s.own]]) {
        const cr = ratio(rgb, bg);
        if (cr < ringWorst.r) { ringWorst.r = cr; ringWorst.who = `${pg.name}: ${s.d} ring vs ${label}`; }
        if (cr < 3) issues.push(`focus ring ${cr.toFixed(2)}:1 vs ${label} background: ${s.d}`);
      }
    }
    if (sticky.length) issues.push('sticky/fixed elements present: ' + sticky.join(', '));
    // skip link works: Enter, then Tab lands inside main
    await ctx.close();
    const c2 = await open(browser, pg, 1280);
    await c2.page.keyboard.press('Tab');
    await c2.page.keyboard.press('Tab');
    await c2.page.keyboard.press('Shift+Tab');
    await c2.page.keyboard.press('Enter');
    await c2.page.keyboard.press('Tab');
    const inMain = await c2.page.evaluate(() => { const e = document.activeElement; return !!e && !!e.closest('main, .pkp_structure_content, #pkp_content_main') && !e.closest('header'); });
    if (!inMain) issues.push('after the first skip link + Tab, focus is not in the main content');
    await c2.ctx.close();
    if (issues.length) fail(`${pg.name}: ${issues.join(' | ')}`); else pass(`${pg.name}: ${stops.length} tab stops, skip link visible and works, rings present, not obscured, no trap`);
  }
  note(`lowest focus-ring contrast seen: ${ringWorst.r.toFixed(2)}:1 (${ringWorst.who})`);
}

// ---------------- target size (WCAG 2.5.8, 24x24) ----------------
async function targets(browser) {
  console.log('\n== target size, minimum 24x24 CSS px (320 and 1280 px)');
  for (const width of [320, 1280]) {
    for (const pg of pages.filter((p) => !p.core)) {
      const { ctx, page } = await open(browser, pg, width);
      const r = await page.evaluate(() => {
        const els = [...document.querySelectorAll('a[href], button, input:not([type=hidden]), select, textarea, summary, [tabindex]:not([tabindex="-1"])')].filter((e) => window.__visible(e));
        const small = []; let inlineExempt = 0;
        els.forEach((e) => {
          const b = e.getBoundingClientRect(); const c = getComputedStyle(e);
          if (b.width >= 24 && b.height >= 24) return;
          if (e.tagName === 'A' && c.display === 'inline') { inlineExempt += 1; return; } // inline text link exception
          if (e.closest('.pkp_screen_reader') || c.position === 'absolute' && b.width < 2) return; // skip-link targets etc.
          small.push(`${window.__desc(e)} ${Math.round(b.width)}x${Math.round(b.height)}`);
        });
        return { total: els.length, small, inlineExempt };
      });
      if (r.small.length) fail(`${pg.name}@${width}: ${r.small.length} below 24x24: ${r.small.slice(0, 6).join('; ')}`);
      else pass(`${pg.name}@${width}: ${r.total} controls, all >= 24x24 (${r.inlineExempt} inline text links exempt)`);
      await ctx.close();
    }
  }
}

// ---------------- reflow: 200% zoom of 1280 = 640 px, 400% = 320 px ----------------
async function reflow(browser) {
  console.log('\n== reflow: 640 px (200% zoom) and 320 px (400% zoom)');
  for (const width of [640, 320]) {
    for (const pg of pages.filter((p) => !p.core)) {
      const { ctx, page } = await open(browser, pg, width);
      const r = await page.evaluate(() => {
        const cw = document.documentElement.clientWidth;
        const over = document.documentElement.scrollWidth - cw;
        const wide = [...document.querySelectorAll('body *')].filter((e) => window.__visible(e) && e.getBoundingClientRect().right > cw + 0.5 && !e.closest('.pkp_screen_reader')).slice(0, 4).map(window.__desc);
        const clipped = [...document.querySelectorAll('body *')].filter((e) => { const c = getComputedStyle(e); return window.__visible(e) && /hidden|clip/.test(c.overflowX) && e.scrollWidth > e.clientWidth + 1 && !e.closest('.pkp_screen_reader'); }).slice(0, 4).map(window.__desc);
        const ellipsis = [...document.querySelectorAll('body *')].filter((e) => getComputedStyle(e).textOverflow === 'ellipsis' && e.scrollWidth > e.clientWidth).map(window.__desc);
        return { over, wide, clipped, ellipsis };
      });
      const bad = [];
      if (r.over > 0) bad.push(`horizontal scroll ${r.over}px`);
      if (r.wide.length) bad.push('wider than viewport: ' + r.wide.join(', '));
      if (r.clipped.length) bad.push('possibly clipped: ' + r.clipped.join(', '));
      if (r.ellipsis.length) bad.push('truncated text: ' + r.ellipsis.join(', '));
      if (bad.length) fail(`${pg.name}@${width}: ${bad.join(' | ')}`); else pass(`${pg.name}@${width}: no horizontal scroll, nothing clipped or truncated`);
      await ctx.close();
    }
  }
}

// ---------------- contrast numbers ----------------
const CONTRAST = {
  home: [
    ['body text (about)', '.worj-home__about p'], ['hero name (large)', '.worj-hero__name'], ['primary button', '.worj-button--primary'], ['secondary button', '.worj-hero__actions .worj-button:not(.worj-button--primary)'],
    ['announcement title link', '.worj-announcement h3 a'], ['announcement date (muted)', '.worj-announcement__date'], ['nav link', '.worj-nav > ul > li > a'], ['nav search link', '.worj-search-link'], ['account link', '.worj-user a'], ['footer title (large)', '.worj-footer__title'], ['footer link', '.worj-footer__links a'], ['footer placeholder badge', '.worj-footer .worj-placeholder'],
  ],
  article: [['link (issue)', '.entry_details .item a'], ['metadata label (muted)', '.sub_item .label'], ['breadcrumb link', '.cmp_breadcrumbs a'], ['breadcrumb current (muted)', '.cmp_breadcrumbs .current span'], ['sidebar block title', '.pkp_block .title'], ['sidebar link', '.pkp_block li a'], ['make-submission button', '.block_make_submission_link']],
  login: [['form label', 'label'], ['form link', '.page_login a'], ['submit button', 'button[type=submit]']],
};

async function contrast(browser) {
  console.log('\n== contrast, measured from the rendered page (1280 px)');
  for (const [name, list] of Object.entries(CONTRAST)) {
    const pg = pages.find((p) => p.name === name);
    const { ctx, page } = await open(browser, pg, 1280);
    for (const [label, sel] of list) {
      const r = await page.evaluate((s) => {
        const e = document.querySelector(s);
        if (!e) return null;
        const c = getComputedStyle(e); const k = window.__rgba(c.color); const bg = window.__effBg(e);
        return { fg: [k.r, k.g, k.b], alpha: k.a, bg: bg.rgb, image: bg.image, px: parseFloat(c.fontSize), bold: parseInt(c.fontWeight, 10) >= 700 };
      }, sel);
      if (!r) { note(`${name}: ${label}: selector not found (${sel})`); continue; }
      const fg = r.alpha < 1 ? r.fg.map((v, i) => v * r.alpha + r.bg[i] * (1 - r.alpha)) : r.fg;
      const cr = ratio(fg, r.bg);
      const large = r.px >= 24 || (r.px >= 18.66 && r.bold);
      const need = large ? 3 : 4.5;
      const line = `${name}: ${label}: ${cr.toFixed(2)}:1 (need ${need}${large ? ', large text' : ''}) rgb(${fg.map(Math.round)}) on rgb(${r.bg.map(Math.round)})`;
      (cr >= need ? pass : fail)(line);
    }
    await ctx.close();
  }
  // hero band with the multiply-blended JPEG logo: does a white box show?
  const home = pages.find((p) => p.name === 'home');
  const { ctx, page } = await open(browser, home, 1280);
  const boxes = await page.evaluate(() => { const l = document.querySelector('.worj-hero__logo').getBoundingClientRect(); const h = document.querySelector('.worj-hero').getBoundingClientRect(); return { l: [l.left, l.top, l.width, l.height], h: [h.left, h.top, h.width, h.height] }; });
  const shot = PNG.sync.read(await page.screenshot({ clip: { x: 0, y: boxes.h[1], width: 1280, height: boxes.h[3] } }));
  const px = (x, y) => { const i = (shot.width * Math.round(y) + Math.round(x)) << 2; return [shot.data[i], shot.data[i + 1], shot.data[i + 2]]; };
  const band = px(boxes.l[0] / 2, boxes.h[3] / 2);
  const corner = px(boxes.l[0] + 3, 3 + (boxes.l[1] - boxes.h[1]));
  const diff = Math.max(...band.map((v, i) => Math.abs(v - corner[i])));
  (diff <= 3 ? pass : fail)(`home: hero logo corner rgb(${corner}) vs band rgb(${band}): max channel difference ${diff} (no visible white box if <= 3)`);
  await ctx.close();
}

// ---------------- motion ----------------
async function motion(browser) {
  console.log('\n== motion');
  for (const pg of pages.filter((p) => !p.core)) {
    const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 }, reducedMotion: 'reduce' });
    const page = await ctx.newPage();
    await page.goto(pg.url, { waitUntil: 'networkidle' });
    await page.evaluate(inPage);
    await page.waitForTimeout(300);
    const r = await page.evaluate(() => {
      const running = document.getAnimations().filter((a) => a.playState === 'running').map((a) => (a.effect && a.effect.target ? a.effect.target.tagName : '?') + ':' + (a.animationName || a.transitionProperty || ''));
      const media = document.querySelectorAll('video, audio, marquee, [autoplay], embed, object').length;
      const longTransitions = [...document.querySelectorAll('body *')].filter((e) => { const c = getComputedStyle(e); return c.transitionDuration.split(',').some((d) => parseFloat(d) > 0.05) || (c.animationName !== 'none' && c.animationDuration.split(',').some((d) => parseFloat(d) > 0.05)); }).slice(0, 3).map(window.__desc);
      return { running, media, longTransitions };
    });
    const bad = [];
    if (r.running.length) bad.push('running animations under reduced motion: ' + r.running.join(','));
    if (r.media) bad.push(`${r.media} media/autoplay elements`);
    if (r.longTransitions.length) bad.push('transitions > 50ms under reduced motion: ' + r.longTransitions.join(', '));
    if (bad.length) fail(`${pg.name}: ${bad.join(' | ')}`); else pass(`${pg.name}: nothing animates under prefers-reduced-motion, no video/audio/autoplay`);
    await ctx.close();
  }
}

(async () => {
  const browser = await chromium.launch();
  if (want('structure')) await structure(browser);
  if (want('keyboard')) await keyboard(browser);
  if (want('targets')) await targets(browser);
  if (want('reflow')) await reflow(browser);
  if (want('contrast')) await contrast(browser);
  if (want('motion')) await motion(browser);
  await browser.close();
  console.log(`\nRESULT: ${fails === 0 ? 'PASS' : 'FAIL (' + fails + ')'}`);
  process.exit(fails ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(2); });
