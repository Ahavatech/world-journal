#!/usr/bin/env python3
"""Numerically check WCAG 2.2 contrast for the colour pairs the theme uses.

Reads the custom properties from tokens.css, so retuning a colour there is
re-checked automatically. Prints one line per pair and exits 1 on any failure.
  text pairs need 4.5:1 (3:1 for large text); UI components and focus rings 3:1.
"""
import re
import sys
from pathlib import Path

TOKENS = Path(__file__).resolve().parent.parent / "ojs/plugins/themes/worj/assets/css/tokens.css"

# (foreground, background, minimum, what it is)
PAIRS = [
    ("text", "bg", 4.5, "body text"),
    ("text", "surface", 4.5, "body text on panels"),
    ("text-muted", "bg", 4.5, "secondary text"),
    ("text-muted", "surface", 4.5, "secondary text on panels"),
    ("primary", "bg", 4.5, "links and headings"),
    ("primary", "surface", 4.5, "links on panels"),
    ("primary-dark", "bg", 4.5, "link hover"),
    ("on-primary", "primary", 4.5, "text on navy fills"),
    ("accent-text", "bg", 4.5, "small gold text"),
    ("accent", "bg", 3.0, "gold fills, rules, LARGE text only"),
    ("primary", "accent", 3.0, "navy on gold fill (large text / UI)"),
    ("focus", "bg", 3.0, "focus ring on white"),
    ("focus", "surface", 3.0, "focus ring on panels"),
    ("border-strong", "bg", 3.0, "form control borders"),
    ("banner-text", "banner-bg", 4.5, "[PLACEHOLDER] banner"),
    ("error", "bg", 4.5, "form error text on white"),
    ("error", "surface", 4.5, "form error text on panels"),
]


def load():
    css = TOKENS.read_text()
    return {m.group(1): m.group(2) for m in re.finditer(r"--worj-([a-z-]+):\s*(#[0-9a-fA-F]{3,6})\s*;", css)}


def rgb(h):
    h = h.lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def lum(c):
    def f(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (f(v) for v in c)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def ratio(a, b):
    hi, lo = sorted((lum(rgb(a)), lum(rgb(b))), reverse=True)
    return (hi + 0.05) / (lo + 0.05)


def main():
    colours = load()
    bad = 0
    for fg, bg, need, what in PAIRS:
        if fg not in colours or bg not in colours:
            print(f"FAIL  --worj-{fg} / --worj-{bg}: token missing")
            bad += 1
            continue
        r = ratio(colours[fg], colours[bg])
        ok = r >= need
        bad += not ok
        print(f"{'PASS' if ok else 'FAIL'}  {r:5.2f}:1 (need {need})  {fg} on {bg}: {what}")
    print("RESULT:", "PASS" if not bad else f"FAIL ({bad})")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
