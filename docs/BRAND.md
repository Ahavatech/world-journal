# BRAND: logo details (Phase 0.3)

| Property | Value |
|---|---|
| File | `worj.jpeg` (repo root; never edit, move or rename) |
| Format | JPEG, 8-bit sRGB |
| Dimensions | 1600 x 1600 px (square canvas) |
| File size | 236,915 bytes |
| Transparency | none (JPEG) |
| Content | globe with graduation cap and open book, gold orbit ring, wordmark "World Open Research Journal", tagline "Advancing Knowledge Globally" |

The artwork occupies roughly the middle half of the square; there is a large near-white margin above and below.

## Dominant colours

Measured on a 200 px downsample, ignoring near-white (all channels > 225), near-black (all channels < 35) and low-saturation grey pixels. Values are 24-level bucket centres, so they are approximations for starting tokens, not brand-exact. Confirm with the client's brand guide.

| Role (proposed) | Hex | Share of coloured pixels |
|---|---|---|
| Primary navy (wordmark, book) | `#0c2454` | 12.8% |
| Navy, slightly lighter | `#0c246c` | 9.1% |
| Mid blue (globe) | `#0c3c84` | 3.7% |
| Gold (orbit, "Journal") | `#b4840c` | 3.0% |
| Light blue-grey (globe highlight) | `#849cb4` | 2.8% |

Palette in one line: deep navy plus gold on white. Phase 2.2 derives `--worj-primary` and `--worj-accent` from this and must check contrast (gold on white is likely under 4.5:1 for body text).

## Issues with the file

- **JPEG has no transparency and is lossy.** The logo carries a white box. On a coloured or dark header it will look like a pasted white rectangle, and the edges show compression artefacts when scaled.
- The square canvas with wide margins wastes header space; a header logo would need cropping, which is a derived variant, not an edit of the original.
- The tagline is baked into the image and is too small to read at header height.

## Open items

- [ ] **Ask the client for an SVG or transparent PNG** of the logo (ideally also a mark-only version without tagline).
- [ ] Ask for the client's brand colours if they exist.
- Until then, Phase 2 uses a white header background and derived, cropped variants in `ojs/plugins/themes/worj/assets/`.

## Derived assets and theme tokens (Phase 2.2)

Brand colours re-sampled from the wordmark pixels (median of dark navy and of gold pixels): navy `#022760`, gold `#c08b0a`. Contrast on white (`scripts/check-contrast.py`): navy 14.4:1, gold only 3.03:1, so gold is used for fills, rules and large text only, with `#8a6500` (5.3:1) when gold must be small text. Tokens live in `ojs/plugins/themes/worj/assets/css/tokens.css`.

Derived from `worj.jpeg` by cropping only (the original is untouched, no background removal):

| File | Size | Use |
|---|---|---|
| `assets/img/logo-header.jpg` | 760x318 | header, wordmark and globe, tagline cropped off |
| `assets/img/logo-lockup.jpg` | 900x415 | hero, full lockup with tagline |

Both keep the JPEG's white background, so they sit on a white or near-white band. A mark-only crop was tried and dropped: the book and the "W" touch, so a rectangular crop leaves an artefact. That needs the SVG or transparent PNG from the client.
