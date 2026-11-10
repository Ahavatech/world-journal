#!/usr/bin/env node
// Unit tests for scripts/lib/target.js: a remote target is only allowed while the site is closed to crawlers.
'use strict';
const assert = require('assert');
const { load, assertAllowed } = require('./lib/target');

let pass = 0;
let fail = 0;
const t = async (name, fn) => { try { await fn(); console.log(`PASS  ${name}`); pass++; } catch (e) { console.log(`FAIL  ${name}: ${e.message}`); fail++; } };
const res = (status, body, headers = {}) => ({ status, text: async () => body, headers: { get: (k) => headers[k.toLowerCase()] || null } });
const remote = { remote: true, base: 'https://journal.example.org' };
const rejects = async (p, re) => { try { await p; } catch (e) { assert.match(e.message, re); return; } throw new Error('expected a refusal'); };

(async () => {
  await t('closed site (Disallow: / and noindex) is allowed', () => assertAllowed(remote, async () => res(200, 'User-agent: *\nDisallow: /\n', { 'x-robots-tag': 'noindex, nofollow' })));
  await t('open site (production robots, no noindex) is refused', () => rejects(assertAllowed(remote, async () => res(200, 'User-agent: *\nDisallow: /cache/\n\nSitemap: https://x/index/sitemap\n')), /REFUSED.*open to crawlers/));
  await t('robots closed but no X-Robots-Tag is refused', () => rejects(assertAllowed(remote, async () => res(200, 'User-agent: *\nDisallow: /\n')), /REFUSED/));
  await t('noindex header but robots open is refused', () => rejects(assertAllowed(remote, async () => res(200, 'User-agent: *\nDisallow: /cache/\n', { 'x-robots-tag': 'noindex' })), /REFUSED/));
  await t('a closed robots.txt that also says Allow: / is refused', () => rejects(assertAllowed(remote, async () => res(200, 'User-agent: *\nDisallow: /\nAllow: /\n', { 'x-robots-tag': 'noindex' })), /REFUSED/));
  await t('robots.txt answering 404 is refused', () => rejects(assertAllowed(remote, async () => res(404, 'x', { 'x-robots-tag': 'noindex' })), /REFUSED/));
  await t('an unreachable site is refused', () => rejects(assertAllowed(remote, async () => { throw new Error('ECONNREFUSED'); }), /REFUSED.*cannot read/));
  await t('the sandbox target only runs on localhost', () => rejects(assertAllowed({ remote: false, base: 'https://journal.example.org' }), /REFUSED.*localhost/));
  await t('the sandbox target on 127.0.0.1 is allowed', () => assertAllowed({ remote: false, base: 'http://127.0.0.1:8082' }));
  await t('a remote target needs https and a bare host', () => {
    assert.throws(() => load({ WORJ_TARGET: 'remote', WORJ_URL: 'http://journal.example.org', WORJ_ADMIN_USER: 'a', WORJ_ADMIN_PASSWORD: 'b' }), /https/);
    assert.throws(() => load({ WORJ_TARGET: 'remote', WORJ_URL: 'https://journal.example.org/worj', WORJ_ADMIN_USER: 'a', WORJ_ADMIN_PASSWORD: 'b' }), /no path/);
  });
  await t('a remote target needs credentials from the environment', () => assert.throws(() => load({ WORJ_TARGET: 'remote', WORJ_URL: 'https://journal.example.org' }), /required/));
  await t('a valid remote target loads', () => assert.deepStrictEqual(load({ WORJ_TARGET: 'remote', WORJ_URL: 'https://journal.example.org', WORJ_ADMIN_USER: 'a', WORJ_ADMIN_PASSWORD: 'b' }), { remote: true, base: 'https://journal.example.org', user: 'a', pass: 'b' }));
  console.log(`${pass} PASS, ${fail} FAIL`);
  process.exit(fail ? 1 : 0);
})();
