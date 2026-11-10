'use strict';
// Where the seeding scripts (sandbox-seed.js, sandbox-content.js) write: the local sandbox (default) or, with
// WORJ_TARGET=remote, the not-yet-public test site on the shared host (scripts/seed-shared.sh sets it).
//
//   sandbox: SANDBOX_URL (default http://127.0.0.1:8082) and the generated admin in .env.sandbox; localhost only.
//   remote:  WORJ_URL (https://HOST, nothing after the host), WORJ_ADMIN_USER and WORJ_ADMIN_PASSWORD from the environment
//            (never argv). These scripts write PLACEHOLDER text and sample content, so a remote target is refused unless the
//            site is still closed to crawlers: robots.txt says `Disallow: /` and the response carries X-Robots-Tag: noindex.
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..', '..');

function load(env = process.env) {
  if (env.WORJ_TARGET === 'remote') {
    const base = env.WORJ_URL || '';
    if (!/^https:\/\/[a-z0-9]([a-z0-9.-]*[a-z0-9])?$/.test(base)) throw new Error(`WORJ_URL must be https://HOST with no path (got '${base}')`);
    if (!env.WORJ_ADMIN_USER || !env.WORJ_ADMIN_PASSWORD) throw new Error('WORJ_ADMIN_USER and WORJ_ADMIN_PASSWORD are required for a remote target');
    return { remote: true, base, user: env.WORJ_ADMIN_USER, pass: env.WORJ_ADMIN_PASSWORD };
  }
  const e = Object.fromEntries(
    fs.readFileSync(path.join(root, '.env.sandbox'), 'utf8').trim().split('\n').map((l) => l.split(/=(.*)/s).slice(0, 2)));
  return { remote: false, base: env.SANDBOX_URL || 'http://127.0.0.1:8082', user: e.SANDBOX_ADMIN_USER, pass: e.SANDBOX_ADMIN_PASSWORD };
}

// Throws (message starts with REFUSED) unless writing placeholders to this target is allowed.
async function assertAllowed(t, fetchImpl = fetch) {
  const host = new URL(t.base).hostname.replace(/^\[|\]$/g, '').toLowerCase();
  if (!t.remote) {
    if (!['localhost', '127.0.0.1', '::1'].includes(host)) throw new Error(`REFUSED: the sandbox scripts only run against localhost (SANDBOX_URL host is '${host}'); use scripts/seed-shared.sh for the host.`);
    return;
  }
  let res;
  try { res = await fetchImpl(`${t.base}/robots.txt`, { redirect: 'manual' }); } catch (e) { throw new Error(`REFUSED: cannot read ${t.base}/robots.txt (${e.message}); not writing anything`); }
  const body = res.status === 200 ? await res.text() : '';
  const closed = /^Disallow:\s*\/\s*$/m.test(body) && !/^Allow:\s*\/\s*$/m.test(body);
  const noindex = /noindex/i.test(res.headers.get('x-robots-tag') || '');
  if (!closed || !noindex) {
    throw new Error(`REFUSED: ${t.base} is open to crawlers (robots.txt closed: ${closed}, X-Robots-Tag noindex: ${noindex}). Placeholder content is only written to a closed test site; rebuild the release with --robots-mode closed.`);
  }
}

module.exports = { load, assertAllowed };
