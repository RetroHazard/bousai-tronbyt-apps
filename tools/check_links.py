#!/usr/bin/env python3
"""Check local Markdown links/images in the public documentation (no network)."""

import re
import unicodedata
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parent.parent
LINK = re.compile(r"!?\[[^\]]*\]\(([^\s)]+)(?:\s+\"[^\"]*\")?\)")


def headings(path: Path) -> set:
    anchors = set()
    counts = {}
    for title in re.findall(r"^#{1,6}\s+(.+)$", path.read_text(encoding="utf-8"), re.M):
        title = title.strip().lower()
        base = "".join(c for c in title if c in "_- " or c.isalnum() or unicodedata.category(c).startswith("M"))
        base = base.replace(" ", "-")
        count = counts.get(base, 0)
        anchors.add(f"{base}-{count}" if count else base)
        counts[base] = count + 1
    return anchors


def main() -> None:
    paths = sorted(ROOT.glob("*.md")) + sorted((ROOT / "docs").rglob("*.md")) + sorted((ROOT / "examples").rglob("*.md"))
    errors = []
    links = 0
    for path in paths:
        # Links in fenced examples are literal examples, not navigation.
        text = re.sub(r"^```[^\n]*\n.*?^```\s*$", "", path.read_text(encoding="utf-8"), flags=re.M | re.S)
        for match in LINK.finditer(text):
            target = match[1]
            url = urlsplit(target)
            if url.scheme or url.netloc:
                continue
            links += 1
            dest = (path.parent / unquote(url.path)).resolve() if url.path else path
            if not dest.exists():
                errors.append(f"{path.relative_to(ROOT)}: missing {target}")
            elif url.fragment and dest.suffix == ".md" and unquote(url.fragment) not in headings(dest):
                errors.append(f"{path.relative_to(ROOT)}: missing heading in {target}")
    if errors:
        raise SystemExit("\n".join(errors))
    print(f"{links} local links/images checked in {len(paths)} Markdown files")


if __name__ == "__main__":
    main()
