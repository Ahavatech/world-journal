'use strict';
// Pages the QA checks visit. Paths are relative to the sandbox OJS (see
// scripts/sandbox-ojs.sh). The awards page is added when Phase 3.4 builds it.
const base = process.env.SANDBOX_URL || 'http://127.0.0.1:8082';

const pages = [
  { name: 'home', path: '/worj/' },
  { name: 'about', path: '/worj/about' },
  { name: 'article', path: '/worj/article/view/1' },
  { name: 'issue', path: '/worj/issue/view/1' },
  { name: 'archive', path: '/worj/issue/archive' },
  { name: 'awards', path: '/worj/awards' },
  { name: 'editorial', path: '/worj/about/editorialMasthead' },
  { name: 'peer-review', path: '/worj/peer-review' },
  { name: 'login', path: '/worj/login' },
  { name: 'register', path: '/worj/user/register' },
  { name: 'search', path: '/worj/search' },
  { name: 'submissions', path: '/worj/about/submissions' },
  { name: 'contact', path: '/worj/about/contact' },
  // core: true = markup printed by OJS core (a bare <h1>), which a theme cannot
  // override. Findings on it are reported separately and do not fail the run.
  { name: '404', path: '/worj/this-page-does-not-exist', core: true },
].map((p) => ({ ...p, url: base + p.path }));

module.exports = { base, pages, viewports: [320, 1280] };
