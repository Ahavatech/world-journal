#!/usr/bin/env python3
"""Wrap every inline [PLACEHOLDER: ...] marker in ojs/content/**/*.html in
<span class="worj-ph">...</span> so it shows as a badge. Mechanical and
idempotent: no model involved.

  python3 -I scripts/wrap-placeholders.py           rewrite files in place
  python3 -I scripts/wrap-placeholders.py --check   change nothing, exit 1 if a file would change

Left alone: the page-level banner (<p class="worj-placeholder">), markers that
are already wrapped, and anything inside a tag's attributes.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTENT = ROOT / "ojs/content"
MARKER = re.compile(r"\[PLACEHOLDER:[^\]]*\]")
TAG = re.compile(r"(<[^>]*>)")
OPEN = '<span class="worj-ph">'


def wrap(html):
    parts = TAG.split(html)  # odd indexes are tags, even indexes are text
    depth_ph = 0       # inside a worj-ph span
    in_banner = False  # inside <p class="worj-placeholder">
    for i, part in enumerate(parts):
        if i % 2:
            if part.startswith("<span") and 'class="worj-ph"' in part:
                depth_ph += 1
            elif part == "</span>" and depth_ph:
                depth_ph -= 1
            elif part.startswith("<p") and "worj-placeholder" in part:
                in_banner = True
            elif part == "</p>":
                in_banner = False
            continue
        if depth_ph or in_banner:
            continue
        parts[i] = MARKER.sub(lambda m: f"{OPEN}{m.group(0)}</span>", part)
    return "".join(parts)


def main():
    check = "--check" in sys.argv[1:]
    changed = 0
    for f in sorted(CONTENT.rglob("*.html")):
        old = f.read_text()
        new = wrap(old)
        if new != old:
            changed += 1
            print(("would wrap " if check else "wrapped ") + str(f.relative_to(ROOT)))
            if not check:
                f.write_text(new)
    print(f"{changed} file(s) {'would change' if check else 'changed'}")
    return 1 if (check and changed) else 0


if __name__ == "__main__":
    sys.exit(main())
