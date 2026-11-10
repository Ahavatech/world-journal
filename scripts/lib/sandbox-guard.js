'use strict';
// Guards for the sandbox scripts that edit things by id. Added after a script with an
// empty id edited the wrong menu item (Phase 4 session 1): any id used in a write
// must be non-empty and the target must exist before anything is saved.

const BAD_SEGMENT = /^(undefined|null|NaN|\[object Object\])$/;

// Throws if a URL path contains an empty or placeholder segment, or a query value that is empty.
function assertPath(url) {
  const [path, query = ''] = String(url).split('?');
  const segments = path.split('/').slice(1);
  segments.forEach((s, i) => {
    const last = i === segments.length - 1;
    if (s === '' && !(last && segments.length === 1)) throw new Error(`guard: empty segment in "${url}"`);
    if (BAD_SEGMENT.test(decodeURIComponent(s))) throw new Error(`guard: "${s}" in "${url}" is not an id`);
  });
  for (const pair of query.split('&').filter(Boolean)) {
    const [k, v = ''] = pair.split('=');
    if (v === '' || BAD_SEGMENT.test(v)) throw new Error(`guard: empty or invalid value for "${k}" in "${url}"`);
  }
}

// Throws unless id is a positive integer or a non-empty string that is not a placeholder.
function assertId(id, label = 'id') {
  const ok = (Number.isInteger(id) && id > 0) || (typeof id === 'string' && id.trim() !== '' && !BAD_SEGMENT.test(id));
  if (!ok) throw new Error(`guard: ${label} is empty or invalid (${JSON.stringify(id)})`);
  return id;
}

// Wraps call(method, url, data): every URL is checked, and a write to an existing item
// (PUT, PATCH, DELETE) first does a GET of the same URL and refuses unless it exists.
function guarded(call) {
  return async (method, url, data) => {
    assertPath(url);
    if (['PUT', 'PATCH', 'DELETE'].includes(method)) {
      try { await call('GET', url); } catch (e) { throw new Error(`guard: ${method} ${url} refused, the target does not exist (${e.message.slice(0, 120)})`); }
    }
    return call(method, url, data);
  };
}

module.exports = { assertPath, assertId, guarded };
