#!/usr/bin/env python3
"""Does every needle appear in the text, after normalising both?  (used by scripts/check-pdf.sh)

Usage: pdf_match.py TEXTFILE NEEDLE [NEEDLE ...]     prints MISSING <needle> per miss; exit 1 if any, 0 if none.

Normalisation, applied to the text and to every needle alike: Unicode NFKC (so the ligatures fi, fl, ffi become plain
letters), soft hyphens removed, a hyphen at a line end joined to the next word ("Obser-\nvation"), case folded,
every run of whitespace (including line breaks, so a title wrapped over two lines still matches) reduced to one space.
"""
import re
import sys
import unicodedata


def normalise(s: str) -> str:
    s = unicodedata.normalize("NFKC", s).replace("­", "")
    s = re.sub(r"(\w)-\s*\n\s*(\w)", r"\1\2", s)
    return " ".join(s.casefold().split())


def missing(text: str, needles: list[str]) -> list[str]:
    hay = normalise(text)
    return [n for n in needles if normalise(n) not in hay]


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit("usage: pdf_match.py TEXTFILE NEEDLE [NEEDLE ...]")
    with open(sys.argv[1], encoding="utf-8", errors="replace") as fh:
        miss = missing(fh.read(), sys.argv[2:])
    for m in miss:
        print(f"MISSING {m}")
    sys.exit(1 if miss else 0)
