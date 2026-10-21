#!/usr/bin/env python3
"""Build self-contained Tronbyt apps from src/.

Each app in src/apps/<id>/ declares the shared libraries it needs with a
`# bousai: requires core map ...` comment. This tool inlines those libraries
(src/lib/bousai_<name>.star) into a single apps/<id>/<id>.star, so every app
uploads to Tronbyt Server as one .star file, as a .zip, or from a git repo.

Usage:
  python3 tools/build.py                 # build every app, render previews
  python3 tools/build.py bousai_quake    # build selected apps
  python3 tools/build.py --no-render     # inline only
  python3 tools/build.py --gif /tmp/out  # also write magnified GIFs for review
  python3 tools/build.py --zip           # also write dist/<id>.zip
  python3 tools/build.py --check         # fail if apps/ is out of date (no writes)
  python3 tools/build.py --examples      # build examples/<id>/ into build/examples/<id>/
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC_APPS = ROOT / "src" / "apps"
SRC_LIB = ROOT / "src" / "lib"
OUT_APPS = ROOT / "apps"
DIST = ROOT / "dist"
SRC_EXAMPLES = ROOT / "examples"
OUT_EXAMPLES = ROOT / "build" / "examples"

REQUIRES_RE = re.compile(r"^#\s*bousai:\s*requires\s+(.+)$", re.M)
LOAD_RE = re.compile(r'^load\(\s*"([^"]+)"\s*,(.*)\)\s*$')
TOPLEVEL_RE = re.compile(r"^(?:def\s+(\w+)\s*\(|(\w+)\s*=(?!=))")
MANIFEST_KEYS = ("id", "name", "summary", "desc", "author", "fileName", "packageName")


def pixlet_bin() -> str:
    for candidate in (os.environ.get("PIXLET"), shutil.which("pixlet"), str(Path.home() / ".local/share/pixlet/pixlet")):
        if candidate and Path(candidate).exists():
            return candidate
    raise SystemExit("pixlet not found: set PIXLET or put pixlet on PATH")


def split_source(text: str, path: Path) -> tuple:
    """Return (docstring, load lines, body) for a Starlark file."""
    lines = text.splitlines()
    i = 0
    doc = []
    while i < len(lines) and not lines[i].strip():
        i += 1
    if i < len(lines) and lines[i].lstrip().startswith('"""'):
        start = i
        if lines[i].count('"""') >= 2 and len(lines[i].strip()) > 3:
            i += 1
        else:
            i += 1
            while i < len(lines) and '"""' not in lines[i]:
                i += 1
            i += 1
        doc = lines[start:i]
    loads, body = [], []
    for line in lines[i:]:
        if line.startswith("load("):
            if not LOAD_RE.match(line):
                raise SystemExit(f"{path}: load() must be a single line: {line}")
            loads.append(line)
        elif REQUIRES_RE.match(line):
            continue
        else:
            body.append(line)
    while body and not body[0].strip():
        body.pop(0)
    while body and not body[-1].strip():
        body.pop()
    return "\n".join(doc), loads, "\n".join(body)


def requires(text: str) -> list:
    out = []
    for match in REQUIRES_RE.finditer(text):
        out.extend(match.group(1).split())
    return out


def resolve_libs(names: list, seen=None, order=None) -> list:
    seen = set() if seen is None else seen
    order = [] if order is None else order
    for name in names:
        if name in seen:
            continue
        seen.add(name)
        path = SRC_LIB / f"bousai_{name}.star"
        if not path.exists():
            raise SystemExit(f"unknown library '{name}' ({path.relative_to(ROOT)} missing)")
        resolve_libs(requires(path.read_text(encoding="utf-8")), seen, order)
        order.append(name)
    return order


def merge_loads(load_lines: list) -> list:
    modules = {}
    for line in load_lines:
        module, args = LOAD_RE.match(line).groups()
        symbols = modules.setdefault(module, [])
        for arg in [a.strip() for a in args.split(",") if a.strip()]:
            if arg not in symbols:
                symbols.append(arg)
    out = []
    for module in sorted(modules):
        args = sorted(modules[module], key=lambda a: a.strip('"'))
        out.append(f'load("{module}", {", ".join(args)})')
    return out


def toplevel_names(body: str) -> list:
    names = []
    for line in body.splitlines():
        match = TOPLEVEL_RE.match(line)
        if match:
            names.append(match.group(1) or match.group(2))
    return names


def parse_manifest(path: Path) -> dict:
    data = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        match = re.match(r"^(\w+):\s*(.*)$", line)
        if match:
            data[match.group(1)] = match.group(2).strip().strip('"')
    return data


def build_app(app_id: str, src_root: Path = SRC_APPS) -> str:
    app_path = src_root / app_id / f"{app_id}.star"
    app_text = app_path.read_text(encoding="utf-8")
    libs = resolve_libs(requires(app_text))

    doc, loads, app_body = split_source(app_text, app_path)
    if not doc:
        raise SystemExit(f"{app_path}: missing module docstring (Applet/Summary/Description/Author)")
    parts = []
    all_loads = list(loads)
    owners = {}
    for name in libs:
        lib_path = SRC_LIB / f"bousai_{name}.star"
        _, lib_loads, lib_body = split_source(lib_path.read_text(encoding="utf-8"), lib_path)
        all_loads.extend(lib_loads)
        parts.append((f"src/lib/bousai_{name}.star", lib_body))
    parts.append((app_path.relative_to(ROOT).as_posix(), app_body))

    for origin, body in parts:
        for symbol in toplevel_names(body):
            if symbol in owners and owners[symbol] != origin:
                raise SystemExit(f"{app_id}: '{symbol}' defined in both {owners[symbol]} and {origin}")
            owners[symbol] = origin

    sources = ", ".join(origin for origin, _ in parts)
    out = [doc, "", f"# GENERATED by tools/build.py from {sources}.", "# Edit the sources and rebuild; do not edit this file.", ""]
    out.extend(merge_loads(all_loads))
    for origin, body in parts:
        out.extend(["", f"# ---- {origin} " + "-" * max(4, 70 - len(origin)), "", body])
    return format_star("\n".join(out) + "\n")


def format_star(text: str) -> str:
    """Canonical buildifier formatting via `pixlet format`, so `pixlet check` passes."""
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "app.star"
        path.write_text(text, encoding="utf-8")
        result = subprocess.run([pixlet_bin(), "format", str(path)], capture_output=True, text=True)
        if result.returncode != 0:
            raise SystemExit(f"pixlet format failed\n{result.stdout}{result.stderr}")
        return path.read_text(encoding="utf-8")


def check_manifest(app_id: str, src_root: Path = SRC_APPS) -> None:
    manifest = parse_manifest(src_root / app_id / "manifest.yaml")
    missing = [k for k in MANIFEST_KEYS if not manifest.get(k)]
    if missing:
        raise SystemExit(f"{app_id}: manifest.yaml missing {', '.join(missing)}")
    expected = {"id": app_id.replace("_", "-"), "fileName": f"{app_id}.star", "packageName": app_id}
    for key, value in expected.items():
        if manifest[key] != value:
            raise SystemExit(f"{app_id}: manifest {key} must be {value!r}, got {manifest[key]!r}")


def pixlet_check(app_id: str, out_dir: Path) -> None:
    """Run `pixlet check` (manifest, icons, render, render time, format, lint)."""
    result = subprocess.run([pixlet_bin(), "check", str(out_dir)], capture_output=True, text=True, cwd=out_dir)
    shutil.rmtree(out_dir / ".starcache", ignore_errors=True)
    if result.returncode != 0:
        raise SystemExit(f"{app_id}: pixlet check failed\n{result.stdout}{result.stderr}")


def preview_config(app_id: str, src_root: Path = SRC_APPS) -> dict:
    path = src_root / app_id / "preview.json"
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}


def render(app_id: str, star: Path, out: Path, config: dict, fmt: str = "webp", magnify: int = 1) -> None:
    """Render `star` with `config` (values as in preview.json) to `out`."""
    args = [pixlet_bin(), "render", str(star), "-o", str(out), "--format", fmt, "-m", str(magnify)]
    for key, value in config.items():
        args.append(f"{key}={value if isinstance(value, str) else json.dumps(value)}")
    result = subprocess.run(args, capture_output=True, text=True, cwd=star.parent)
    shutil.rmtree(star.parent / ".starcache", ignore_errors=True)
    if result.returncode != 0:
        raise SystemExit(f"{app_id}: pixlet render failed\n{result.stdout}{result.stderr}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("apps", nargs="*", help="app ids (default: all)")
    parser.add_argument("--no-render", action="store_true", help="skip preview rendering")
    parser.add_argument("--gif", type=Path, help="also write 8x magnified GIFs here")
    parser.add_argument("--zip", action="store_true", help="also write <id>.zip (dist/ for apps)")
    parser.add_argument("--check", action="store_true", help="verify the generated apps are up to date; write nothing")
    parser.add_argument("--pixlet-check", action="store_true", help="also run `pixlet check` on each built app")
    parser.add_argument("--examples", action="store_true", help="build examples/<id>/ into build/examples/<id>/")
    args = parser.parse_args()

    src_root, out_root, dist = (SRC_EXAMPLES, OUT_EXAMPLES, OUT_EXAMPLES) if args.examples else (SRC_APPS, OUT_APPS, DIST)
    all_ids = sorted(p.name for p in src_root.iterdir() if (p / f"{p.name}.star").exists())
    ids = args.apps or all_ids
    unknown = sorted(set(ids) - set(all_ids))
    if unknown:
        raise SystemExit(f"unknown app(s): {', '.join(unknown)}")

    stale = []
    for app_id in ids:
        check_manifest(app_id, src_root)
        generated = build_app(app_id, src_root)
        out_dir = out_root / app_id
        star = out_dir / f"{app_id}.star"
        if args.check:
            if not star.exists() or star.read_text(encoding="utf-8") != generated:
                stale.append(app_id)
            continue
        out_dir.mkdir(parents=True, exist_ok=True)
        star.write_text(generated, encoding="utf-8")
        shutil.copyfile(src_root / app_id / "manifest.yaml", out_dir / "manifest.yaml")
        config = preview_config(app_id, src_root)
        if not args.no_render:
            preview = src_root / app_id / "preview.webp"
            if preview.exists():
                shutil.copyfile(preview, out_dir / f"{app_id}.webp")
            else:
                render(app_id, star, out_dir / f"{app_id}.webp", config)
        if args.gif:
            args.gif.mkdir(parents=True, exist_ok=True)
            render(app_id, star, args.gif.resolve() / f"{app_id}.gif", config, fmt="gif", magnify=8)
        if args.pixlet_check:
            pixlet_check(app_id, out_dir)
        if args.zip:
            dist.mkdir(parents=True, exist_ok=True)
            with zipfile.ZipFile(dist / f"{app_id}.zip", "w", zipfile.ZIP_DEFLATED) as zf:
                for path in sorted(out_dir.iterdir()):
                    if path.is_file():
                        zf.write(path, path.name)
                for name in ("LICENSE", "NOTICE"):
                    zf.write(ROOT / name, name)
        print(f"built {app_id} ({star.stat().st_size} bytes)")

    if args.check:
        if stale:
            raise SystemExit(f"out of date: {', '.join(stale)} (run tools/build.py)")
        print(f"{len(ids)} app(s) up to date")


if __name__ == "__main__":
    main()
