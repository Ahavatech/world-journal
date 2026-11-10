#!/usr/bin/env node
'use strict';
// Offline test of scripts/lib/sandbox-guard.js (no sandbox needed): node scripts/test-sandbox-guard.js
const { assertPath, assertId, guarded } = require('./lib/sandbox-guard');
let failed = 0;
const expect = (name, fn, shouldThrow) => {
  let threw = false; try { fn(); } catch (e) { threw = true; }
  const ok = threw === shouldThrow; if (!ok) failed++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}`);
};
expect('good path', () => assertPath('/worj/api/v1/contexts/1'), false);
expect('good path with query', () => assertPath('/x/grid?navigationMenuItemId=55'), false);
expect('empty segment', () => assertPath('/worj/api/v1/contexts//theme'), true);
expect('trailing slash with id missing', () => assertPath('/worj/api/v1/contexts/'), true);
expect('undefined segment', () => assertPath('/worj/api/v1/contexts/undefined'), true);
expect('empty query value (the incident)', () => assertPath('/x/edit?navigationMenuItemId='), true);
expect('assertId 5', () => assertId(5), false);
expect('assertId empty string', () => assertId(''), true);
expect('assertId undefined', () => assertId(undefined), true);
expect('assertId 0', () => assertId(0), true);
(async () => {
  const calls = [];
  const fake = async (m, u) => { calls.push(m + ' ' + u); if (u.endsWith('/9')) throw new Error('404'); return {}; };
  const g = guarded(fake);
  let threw = false;
  try { await g('PUT', '/api/v1/contexts/9', {}); } catch (e) { threw = /does not exist/.test(e.message); }
  const ok1 = threw && !calls.includes('PUT /api/v1/contexts/9'); if (!ok1) failed++;
  console.log(`${ok1 ? 'PASS' : 'FAIL'}  PUT to a missing item is refused before saving`);
  await g('PUT', '/api/v1/contexts/1', {});
  const ok2 = calls.includes('GET /api/v1/contexts/1') && calls.includes('PUT /api/v1/contexts/1'); if (!ok2) failed++;
  console.log(`${ok2 ? 'PASS' : 'FAIL'}  PUT to an existing item does a GET first, then saves`);
  console.log(failed ? `${failed} FAILED` : 'ALL PASS');
  process.exit(failed ? 1 : 0);
})();
