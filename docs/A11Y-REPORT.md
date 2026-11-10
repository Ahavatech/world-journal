# Accessibility check report (Phase 2.7)

This is **not** a compliance statement. The theme was checked against WCAG 2.2 AA with the tools and manual tests listed here, on the sandbox site with placeholder content. A claim of WCAG 2.2 AA conformance on the public site would need a proper audit with assistive technology, on the real content.

## What was run

Pages: home, about, article, issue, archive, login, register, search, submissions, contact (the ten theme-rendered pages) and the 404 page (core-owned, see findings). Widths: 320 and 1280 px, plus 640 px for the 200% zoom check. Browser: Chromium (Playwright 1.63.0). Everything is repeatable:

```bash
make sandbox-up sandbox-seed      # local OJS with the sample issue
cd autoresearch/eval && npm ci
node checks/axe.js                # axe-core 4.14.0 via @axe-core/playwright 4.14.0
node checks/a11y-manual.js        # structure keyboard targets reflow contrast motion
node checks/forms-errors.js       # failed login and failed registration
python3 -I scripts/check-contrast.py   # token pairs (also part of make lint)
```

## Results at the last run

| Check | Result |
|---|---|
| axe, WCAG 2.0/2.1/2.2 A and AA tags, 22 page runs | 0 violations on the ten theme pages (495 rules passed) and 0 "needs review" items. 4 findings on the core-owned 404 page, listed separately. Before the contrast fixes axe also reported 3 low-contrast metadata labels on the article page (since fixed) |
| Structure | one `h1` per page, no skipped heading levels, `lang="en"`, non-empty title, one `main`, `banner` and `contentinfo` landmark, every `nav` labelled (4 to 5 per page), no generic link text such as a bare "Read more" |
| Keyboard | 24 to 38 Tab stops per page (home 38, about 24, article 28, issue 31, archive 25, login 30, register 38, search 32, submissions 27, contact 25); no trap; the skip link is the first stop, is visible on focus, and moves focus into the main content; every stop has a visible indicator |
| Focus appearance | lowest ring contrast measured on any page, against both the page and the element behind it: 3.61:1 (needs 3:1) |
| Focus not obscured | nothing is `fixed` or `sticky`; the focused control was never covered by another element |
| Target size (2.5.8) | every control at 320 and 1280 px is at least 24x24 CSS px; inline text links are exempt under the spec's inline exception |
| Reflow | no horizontal scroll, nothing clipped or truncated at 640 px (200% zoom of 1280) and 320 px (400%) |
| Motion | under `prefers-reduced-motion: reduce` nothing animates and no transition runs over 50 ms; no video, audio or autoplay on any page |
| Form errors | after a failed login and a failed registration the message has `role="alert"`, receives focus, and the fields it names have `aria-invalid="true"` and `aria-describedby` pointing at it; axe finds nothing on those pages |

### Contrast, measured from the rendered pages (1280 px)

Normal text needs 4.5:1, large text 3:1.

| Pair | Ratio |
|---|---|
| Body text on white | 15.90:1 |
| Links and headings, navy on white | 14.37:1 |
| Muted text on white (announcement date, current breadcrumb) | 7.53:1 |
| Muted text on the light panel (metadata labels) | 6.89:1 |
| Navy text on the light panel (sidebar links, hero name, large text) | 13.16:1 |
| White on navy (nav bar, footer, primary buttons) | 14.37:1 |
| Placeholder badge text | 8.31:1 |
| Form error text on white | 7.26:1 |
| Gold accent on white | 3.03:1, so gold is used for fills and rules only, never for text |
| Hero logo (JPEG, `multiply` blend): its white background against the hero band | corner pixel rgb(242,244,248) vs band rgb(243,245,249), maximum channel difference 1 of 255, so no visible box |

The token pairs (focus ring against white, panel, navy, dark navy and the placeholder banner; borders; error colour) are checked by `scripts/check-contrast.py`.

## What was fixed in this pass

- Metadata labels on the article page: the parent's grey was 3.9:1 on the panel; now the muted token (6.89:1).
- Focus ring colour changed from `#0b5fff` (2.80:1 against navy buttons) to `#2f7bf5` (at least 3.59:1 against white, panel grey, navy, dark navy and the placeholder banner).
- The PDF button's parent focus style turned the background teal (ring 1.21:1); focus and hover now share one light state.
- The "log in or register" notice had a grey `#ddd` background that dropped the link focus ring to 2.93:1; notices now use the panel colour.
- Breadcrumb links were 23 px high (one pixel under 24); checkboxes were 13x13; both fixed.
- The parent's reviewer-interests field stayed keyboard-focusable while collapsed to zero height and invisible; it is now removed from the tab order until the reviewer box is ticked.
- Breadcrumbs on generic and announcement pages now carry the translated `aria-label` (core key `navigation.breadcrumbLabel`) and `aria-current="page"`.
- Form errors are announced, focused and associated with their fields (see above); the parent's white-on-red error boxes (3.46:1) were restyled.
- The parent `main.js` was replaced: it ran `new Swiper()` unconditionally and threw a ReferenceError on every page once Swiper was removed (introduced in 2.3 and not caught by the earlier tests).
- Four parent theme options that did nothing were removed from the admin form.

## Findings the theme cannot fix (reported, not forked)

1. **404 page.** OJS core prints a bare `<h1>404 Not Found</h1>` with no `<html>`, `lang`, `<title>` or landmarks (`lib/pkp/classes/core/PKPApplication.php`, lines 452 to 457), for unknown URLs and for unknown article or issue ids. No theme template can reach it. Proposed fix, for Phase 5: a static, accessible 404 page served by nginx with `fastcgi_intercept_errors on; error_page 404 ...`. The checks list this page separately as core-owned and do not fail on it.
2. **Login error markup.** Core renders a plain `div` with no live-region role or field association. The theme adds both with a few lines of JavaScript (`forms.js`). Without JavaScript the message is still on the page, as text, before the form fields.
3. **Backend screens** (submission wizard, editorial and reviewer workflows, the admin settings) are core's Vue and PHP UI, not themed.

## Not covered

- **Screen readers.** No screen-reader testing (NVDA, JAWS, VoiceOver, TalkBack) has been done. Everything above is automated measurement and keyboard testing.
- Voice control, switch access, screen magnifiers, and Windows forced-colours or high-contrast mode.
- Browsers other than Chromium, real devices, and touch targets measured on a real phone.
- WCAG 1.4.12 text spacing and 1.3.4 orientation were not tested.
- Authenticated pages and the submission, review and editorial workflows (core UI).
- Accessibility of the PDF galleys, which depends on how the client prepares them; the sample PDFs are placeholders.
- Real content: headings, link text, images and alt text, tables and language changes written by editors.
- Email notifications.
- Usability testing with disabled users.

## Conditional exception: registration with ALTCHA (decision D21, not enabled)

Bot protection is a client decision (`docs/ADMIN-SETUP-CHECKLIST.md`, D21, step 5.5). **If ALTCHA is chosen, the registration page (and the login page if `altcha_on_login` stays on) requires JavaScript**: in the sandbox, submitting the register form with JavaScript off failed with "You must complete the validation check used to prevent spam submissions", and with JavaScript on it succeeded. That is an exception to the project rule that every public page works with JavaScript disabled, **limited to the pages that carry the ALTCHA widget**. Record the client's choice here when it is made, with the date. Nothing in this report covers the widget's own accessibility (keyboard use, screen reader announcements): test it before enabling it. reCAPTCHA is not recommended (remote script, third-party privacy disclosure). Today neither is enabled, so no exception is in force.
