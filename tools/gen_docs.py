#!/usr/bin/env python3
"""Fill the generated blocks of the documentation from the built apps.

Generated blocks are delimited by `<!-- BEGIN GENERATED: <name> -->` / `<!-- END GENERATED: <name> -->`;
everything outside them is hand-written and left untouched.

- docs/apps/<id>.md   `gallery`  images rendered from src/apps/<id>/gallery.json (fallback: preview.json)
                      `settings` settings table from `pixlet schema apps/<id>/<id>.star`
- README.md           `apps`     app table with one image per app
- docs/accessibility.md `a11y`   the same sample in each accessibility variant

Images are 4x animated WebP files in docs/images/, rendered from the built apps/ (run tools/build.py first).
They show live data at render time, except for sample-mode entries.

Usage:
  python3 tools/gen_docs.py               # render images and rewrite generated blocks
  python3 tools/gen_docs.py bousai_quake  # selected apps only (README/accessibility untouched)
  python3 tools/gen_docs.py --no-render   # rewrite text blocks only
  python3 tools/gen_docs.py --check       # fail if a text block is stale or an image is missing (no writes)
"""

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build  # noqa: E402

ROOT = build.ROOT
DOCS = ROOT / "docs"
IMAGES = DOCS / "images"
README = ROOT / "README.md"
ACCESSIBILITY = DOCS / "accessibility.md"
MAGNIFY = 4
NAME_RE = re.compile(r"^[a-z0-9-]+$")

ACCESSIBILITY_IDS = ("theme", "palette", "contrast", "text_size", "text_weight")
A11Y_APP = "bousai_warnings"
A11Y_BASE = {"demo": "true"}
A11Y_VARIANTS = [
    ("default", "Default: dark theme, normal colour vision, standard text", {}),
    ("light", "Light theme", {"theme": "light"}),
    ("protan", "Protanopia / deuteranopia palette", {"palette": "protan"}),
    ("tritan", "Tritanopia palette", {"palette": "tritan"}),
    ("mono", "Monochromacy palette", {"palette": "mono"}),
    ("high-contrast", "High contrast", {"contrast": "high"}),
    ("low-contrast", "Low contrast (also stops blinking)", {"contrast": "low"}),
    ("small", "Small text (more lines per page)", {"text_size": "small"}),
    ("large", "Large text", {"text_size": "large"}),
    ("xlarge-bold", "Extra-large bold text", {"text_size": "xlarge", "text_weight": "bold"}),
]


def block(text: str, name: str, body: str, path: Path) -> str:
    """Replace the content of generated block `name` in `text` with `body`."""
    begin, end = f"<!-- BEGIN GENERATED: {name} -->", f"<!-- END GENERATED: {name} -->"
    pattern = re.compile(re.escape(begin) + r".*?" + re.escape(end), re.S)
    if len(pattern.findall(text)) != 1:
        raise SystemExit(f"{path.relative_to(ROOT)}: expected exactly one '{name}' generated block")
    return pattern.sub(lambda _: f"{begin}\n{body.rstrip()}\n{end}" if body.strip() else f"{begin}\n{end}", text)


def md(text: str) -> str:
    return " ".join(str(text).split()).replace("|", "\\|")


def gallery_entries(app_id: str) -> list:
    path = build.SRC_APPS / app_id / "gallery.json"
    if not path.exists():
        return [{"name": "preview", "caption": "Preview", "config": build.preview_config(app_id)}]
    entries = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(entries, list) or not 1 <= len(entries) <= 4:
        raise SystemExit(f"{path.relative_to(ROOT)}: expected a list of 1-4 entries")
    names = set()
    for entry in entries:
        keys = set(entry)
        if keys not in ({"name", "caption", "config"}, {"name", "caption", "image"}) or not NAME_RE.fullmatch(entry["name"]) or entry["name"] in names:
            raise SystemExit(f"{path.relative_to(ROOT)}: bad entry {entry!r}")
        if "image" in entry and Path(entry["image"]).name != entry["image"]:
            raise SystemExit(f"{path.relative_to(ROOT)}: image must be a filename in docs/images/")
        names.add(entry["name"])
    return entries


def image_table(images: list, prefix: str, per_row: int = 2) -> str:
    """Markdown table: rows of images with their captions underneath."""
    lines = []
    for start in range(0, len(images), per_row):
        row = images[start : start + per_row]
        cells = [f"![{md(cap)}]({prefix}{file})<br>*{md(cap)}*" for file, cap in row]
        cells.extend([""] * (min(per_row, len(images)) - len(cells)))
        lines.append("| " + " | ".join(cells) + " |")
        if start == 0:
            lines.append("|" + " :---: |" * len(cells))
    return "\n".join(lines)


def option_text(field: dict) -> str:
    options = field.get("options") or []
    return ", ".join(f"{md(o.get('display') or o.get('text'))} (`{o['value']}`)" for o in options)


def default_text(field: dict) -> str:
    default = field.get("default")
    if field["type"] == "onoff":
        return "On" if str(default).lower() == "true" else "Off"
    if default in (None, ""):
        return "—"
    for option in field.get("options") or []:
        if option["value"] == default:
            return md(option.get("display") or option.get("text"))
    return f"`{md(default)}`"


def settings_block(app_id: str) -> str:
    star = build.OUT_APPS / app_id / f"{app_id}.star"
    result = subprocess.run([build.pixlet_bin(), "schema", str(star)], capture_output=True, text=True, cwd=star.parent)
    if result.returncode != 0:
        raise SystemExit(f"{app_id}: pixlet schema failed\n{result.stdout}{result.stderr}")
    fields = json.loads(result.stdout)["schema"]
    ids = {f["id"] for f in fields}
    collapse = all(i in ids for i in ACCESSIBILITY_IDS)
    lines = [
        "## Settings",
        "",
        "| Setting | Default | Choices | Description |",
        "|---|---|---|---|",
    ]
    for field in fields:
        if collapse and field["id"] in ACCESSIBILITY_IDS:
            continue
        choices = option_text(field) or {"onoff": "On / Off", "location": "Map picker", "text": "Free text"}.get(field["type"], field["type"])
        lines.append(f"| **{md(field['name'])}** (`{field['id']}`) | {default_text(field)} | {choices} | {md(field.get('description', ''))} |")
    if collapse:
        lines += [
            "",
            "Plus the accessibility settings shared by every Bousai app — **Theme**, **Colour vision**, **Contrast**,",
            "**Text size** and **Text weight**; see [Accessibility](../accessibility.md).",
        ]
    lines += ["", "*This section is generated from the app's schema by `tools/gen_docs.py`.*"]
    return "\n".join(lines)


def render_images(app_id: str, entries: list, render: bool) -> list:
    star = build.OUT_APPS / app_id / f"{app_id}.star"
    images = []
    for entry in entries:
        out = IMAGES / entry.get("image", f"{app_id}-{entry['name']}.webp")
        if render and "config" in entry:
            IMAGES.mkdir(parents=True, exist_ok=True)
            build.render(app_id, star, out, entry["config"], magnify=MAGNIFY)
        if not out.exists() or out.stat().st_size == 0:
            raise SystemExit(f"{out.relative_to(ROOT)} missing or empty (entry may have rendered idle)")
        images.append((out.name, entry["caption"]))
    return images


def readme_block(app_ids: list) -> str:
    lines = ["| App | Shows | Preview |", "|---|---|---|"]
    for app_id in app_ids:
        manifest = build.parse_manifest(build.SRC_APPS / app_id / "manifest.yaml")
        first = gallery_entries(app_id)[0]
        lines.append(
            f"| [{md(manifest['name'])}](docs/apps/{app_id}.md)<br>`{app_id}` | {md(manifest['summary'])} | "
            f"![{md(first['caption'])}](docs/images/{first.get('image', app_id + '-' + first['name'] + '.webp')}) |"
        )
    return "\n".join(lines)


def a11y_block(render: bool) -> str:
    star = build.OUT_APPS / A11Y_APP / f"{A11Y_APP}.star"
    images = []
    for name, caption, config in A11Y_VARIANTS:
        out = IMAGES / f"a11y-{name}.webp"
        if render:
            IMAGES.mkdir(parents=True, exist_ok=True)
            build.render(A11Y_APP, star, out, {**A11Y_BASE, **config}, magnify=MAGNIFY)
        elif not out.exists():
            raise SystemExit(f"{out.relative_to(ROOT)} missing (run tools/gen_docs.py)")
        images.append((out.name, caption))
    return image_table(images, "images/")


def update(path: Path, blocks: dict, check: bool, stale: list) -> None:
    if not path.exists():
        raise SystemExit(f"{path.relative_to(ROOT)} missing")
    text = path.read_text(encoding="utf-8")
    new = text
    for name, body in blocks.items():
        new = block(new, name, body, path)
    if new != text:
        if check:
            stale.append(str(path.relative_to(ROOT)))
        else:
            path.write_text(new, encoding="utf-8")
            print(f"updated {path.relative_to(ROOT)}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("apps", nargs="*", help="app ids (default: all, plus README and accessibility page)")
    parser.add_argument("--no-render", action="store_true", help="do not render images (they must exist)")
    parser.add_argument("--check", action="store_true", help="fail if generated text is stale or images are missing")
    args = parser.parse_args()

    all_ids = sorted(p.name for p in build.SRC_APPS.iterdir() if (p / f"{p.name}.star").exists())
    ids = args.apps or all_ids
    unknown = sorted(set(ids) - set(all_ids))
    if unknown:
        raise SystemExit(f"unknown app(s): {', '.join(unknown)}")
    render = not (args.no_render or args.check)

    stale = []
    for app_id in ids:
        images = render_images(app_id, gallery_entries(app_id), render)
        blocks = {"gallery": image_table(images, "../images/"), "settings": settings_block(app_id)}
        update(DOCS / "apps" / f"{app_id}.md", blocks, args.check, stale)
    if not args.apps:
        update(README, {"apps": readme_block(all_ids)}, args.check, stale)
        update(ACCESSIBILITY, {"a11y": a11y_block(render)}, args.check, stale)

    if stale:
        raise SystemExit(f"stale generated docs: {', '.join(stale)} (run tools/gen_docs.py)")
    if args.check:
        print(f"docs up to date ({len(ids)} app page(s))")


if __name__ == "__main__":
    main()
