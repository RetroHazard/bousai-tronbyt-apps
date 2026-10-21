#!/usr/bin/env python3
"""Regenerate src/lib/bousai_data.star from official JMA reference tables.

Every table comes from a JMA-published file, so English names match the ones
JMA itself uses on its multilingual site:

- epi.json / areatsunami.json / tsunamiwarning.json / pref.json:
  https://www.data.jma.go.jp/multi/data/dictionary/
- multi_util.js (forecast office -> multilingual publishing office):
  https://www.data.jma.go.jp/multi/js/util.js
- volcano_list.json: https://www.jma.go.jp/bosai/volcano/const/volcano_list.json
- weather code telops and warning code table: embedded in the JS of
  https://www.jma.go.jp/bosai/forecast/ and https://www.jma.go.jp/bosai/warning/

Usage: python3 tools/gen_data.py
"""

import gzip
import json
import re
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "src" / "lib" / "bousai_data.star"
MULTI = "https://www.data.jma.go.jp/multi"
BOSAI = "https://www.jma.go.jp/bosai"


def fetch(url: str) -> str:
    req = urllib.request.Request(url, headers={"Accept-Encoding": "gzip", "User-Agent": "bousai-tronbyt-apps/gen_data"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        body = resp.read()
        if resp.headers.get("Content-Encoding") == "gzip" or body[:2] == b"\x1f\x8b":
            body = gzip.decompress(body)
    return body.decode("utf-8")


def unescape_js(text: str) -> str:
    return re.sub(r"\\u([0-9a-fA-F]{4})", lambda m: chr(int(m.group(1), 16)), text)


def english_dict(name: str) -> dict:
    data = json.loads(fetch(f"{MULTI}/data/dictionary/{name}.json"))
    return {code: entry["english"].strip() for code, entry in sorted(data.items()) if entry.get("english")}


def telops() -> dict:
    page = unescape_js(fetch(f"{BOSAI}/forecast/"))
    match = re.search(r"TELOPS=\{(.*?)\}[,;]", page, re.S)
    if not match:
        raise SystemExit("TELOPS table not found in forecast page")
    out = {}
    for code, group, english in re.findall(r'(\d{3}):\["[^"]*","[^"]*","(\d{3})","[^"]*","([^"]*)"\]', match.group(1)):
        out[code] = [english, group]
    if len(out) < 100:
        raise SystemExit(f"TELOPS table looks truncated ({len(out)} entries)")
    return out


def warning_codes() -> dict:
    page = unescape_js(fetch(f"{BOSAI}/warning/"))
    out = {}
    pattern = r'(?:"(\w+)"|(\d+)):\{shortNameParts:s\.(\w+)\[\d\],nameParts:e\.\w+\[\d\],elem:"(\w+)",level:(\d+)\}'
    for quoted, bare, _table, elem, level in re.findall(pattern, page):
        code = (quoted or bare).zfill(2)
        if elem == "flood":
            continue  # river flood codes live in flood_xml.json, not in the warning feed
        out[code] = [elem, int(level)]
    if len(out) < 25:
        raise SystemExit(f"warning code table looks truncated ({len(out)} entries)")
    return dict(sorted(out.items()))


def multi_offices() -> tuple:
    js = fetch(f"{MULTI}/js/util.js")
    body = js[js.index("function findPublishingOffice("):]
    body = body[: body.index("\n}\n") + 3]
    pref_part, rest = body.split("const areaId", 1)
    by_pref = dict(re.findall(r"case '(\d{2})':\s*(?:if[^}]*\}\s*else\s*\{\s*return '[A-Z]+';\s*\}\s*\}\s*else\s*\{\s*)?return '([A-Z]+)'", pref_part))
    by_prefix = dict(re.findall(r"case '(\d{3})':(?:\s*if[^}]*\}\s*\})?\s*return '([A-Z]+)'", rest))
    special = dict(re.findall(r"code == '(\d{6})'\)\s*\{\s*return '([A-Z]+)'", body))
    if len(by_pref) < 40 or len(by_prefix) < 10:
        raise SystemExit(f"publishing office table looks truncated ({len(by_pref)}, {len(by_prefix)})")
    return dict(sorted(by_pref.items())), dict(sorted(by_prefix.items())), dict(sorted(special.items()))


def volcanoes() -> dict:
    data = json.loads(fetch(f"{BOSAI}/volcano/const/volcano_list.json"))
    out = {}
    for v in data:
        if "latlon" not in v:
            continue  # 900-902 are "all/other/new active volcano" placeholders without a location
        lat, lon = v["latlon"]
        out[v["code"]] = [v["name_en"].strip(), round(float(lat), 3), round(float(lon), 3)]
    return dict(sorted(out.items()))


def star_dict(name: str, value: dict, doc: str) -> str:
    lines = [f"# {doc}", f"{name} = {{"]
    for key, val in value.items():
        lines.append(f"    {json.dumps(key, ensure_ascii=False)}: {json.dumps(val, ensure_ascii=False)},")
    lines.append("}")
    return "\n".join(lines)


def main() -> None:
    by_pref, by_prefix, special = multi_offices()
    sections = [
        star_dict("BOUSAI_EPICENTER_EN", english_dict("epi"), "Epicenter area code -> JMA English name (multilingual dictionary epi.json)."),
        star_dict("BOUSAI_TSUNAMI_AREA_EN", english_dict("areatsunami"), "Tsunami forecast region code -> JMA English name."),
        star_dict("BOUSAI_TSUNAMI_KIND_EN", english_dict("tsunamiwarning"), "Tsunami warning kind code -> JMA English name."),
        star_dict("BOUSAI_PREF_EN", english_dict("pref"), "Prefecture code -> JMA English name."),
        star_dict("BOUSAI_WEATHER_EN", telops(), "Forecast weather code -> [JMA English telop, icon group 100/200/300/400]."),
        star_dict("BOUSAI_WARN_CODES", warning_codes(), "r8 warning kind code -> [element, level] (level 20 advisory, 30 warning, 40 urgent warning, 50 emergency warning)."),
        star_dict("BOUSAI_VOLCANOES", volcanoes(), "Volcano code -> [JMA English name, latitude, longitude]."),
        star_dict("BOUSAI_MULTI_OFFICE_BY_PREF", by_pref, "Prefecture prefix of a class10 code -> JMA multilingual publishing office."),
        star_dict("BOUSAI_MULTI_OFFICE_BY_PREFIX", by_prefix, "Hokkaido/Okinawa class10 prefix -> JMA multilingual publishing office."),
        star_dict("BOUSAI_MULTI_OFFICE_SPECIAL", special, "class10 codes with their own multilingual publishing office."),
    ]
    header = '"""Official JMA reference tables. GENERATED by tools/gen_data.py; do not edit."""\n'
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(header + "\n" + "\n\n".join(sections) + "\n", encoding="utf-8")
    print(f"wrote {OUT.relative_to(ROOT)} ({OUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
