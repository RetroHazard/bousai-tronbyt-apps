"""Volcano domain library for the Bousai suite.

JMA volcanic warnings and Volcanic Alert Levels (volcano/data/warning.json), eruption
flash reports (volcano/data/eruption.json + eruption/<event>.json), ashfall forecasts
(volcano/data/ashfall/*.json) and the official English wording of JMA's multilingual
VFVO50 feed. Volcano names and positions come from BOUSAI_VOLCANOES.

Public API for other apps (plain values, no widgets, never raises on a missing feed):
  bousai_volcano_current(config) -> [{code, name_en, level, sev, kind_en, issued, lat, lon, distance_km}]
  bousai_volcano_flash()         -> [{name_en, time, text_en}]
"""

# bousai: requires core data

load("math.star", "math")
load("render.star", "canvas", "render")
load("time.star", "time")

BOUSAI_VOLCANO_URL = "https://www.jma.go.jp/bosai/volcano/data/"
BOUSAI_VOLCANO_MULTI_URL = "https://www.data.jma.go.jp/multi/data/VFVO50/en.json"

# Kind code of the "target volcano" line of warning.json ->
# [alert level or None, severity 0..5, official English keyword, short English phrase, badge label].
BOUSAI_VOLCANO_KINDS = {
    "11": [1, 1, "Level 1 (Potential for increased activity)", "Potential for increased activity", "Lv1"],
    "12": [2, 2, "Level 2 (Do not approach the crater)", "Do not approach the crater", "Lv2"],
    "13": [3, 3, "Level 3 (Do not approach the volcano)", "Do not approach the volcano", "Lv3"],
    "14": [4, 4, "Level 4 (Evacuation of the elderly, etc.)", "Prepare to evacuate", "Lv4"],
    "15": [5, 5, "Level 5 (Evacuate)", "Evacuate", "Lv5"],
    "21": [None, 1, "Potential for increased activity", "Potential for increased activity", "Calm"],
    "22": [None, 2, "Caution advised around the crater", "Caution around the crater", "Cau"],
    "23": [None, 3, "Caution in non-residential areas near the crater", "Caution near the crater", "Cau+"],
    "24": [None, 4, "Extreme caution advised at the foot of the mountain", "Extreme caution at the foot", "Ext"],
    "25": [None, 5, "Extreme caution advised in residential areas", "Extreme caution in residential areas", "Ext+"],
    "35": [None, 1, "Potential for increased activity (submarine volcano)", "Potential for increased activity", "Calm"],
    "36": [None, 3, "Caution advised for the sea area in the vicinity of the volcano", "Caution in the nearby sea area", "Sea"],
}

# Volcanoes where Volcanic Alert Levels are applied (volcano_list.json levelOperation). Everything
# else is covered by keyword-only warnings. A level volcano missing from warning.json is at Lv1.
BOUSAI_VOLCANO_LEVEL_OPS = {c: True for c in "104 105 107 108 109 111 112 113 114 202 203 204 205 207 208 209 210 212 213 214 215 301 302 306 307 309 310 311 312 313 314 315 316 317 318 319 320 321 322 350 351 502 503 504 506 508 509 511 513 550 551 552 553".split(" ")}

# warning.json "condition" -> English.
BOUSAI_VOLCANO_COND = {
    "発表": "Issued",
    "継続": "Continued",
    "切替": "Updated",
    "引上げ": "Raised",
    "引下げ": "Lowered",
    "解除": "Lifted",
}

# Eruption flash report phenomenon codes (volcano_dictionary.json warningCode).
BOUSAI_VOLCANO_FLASH_KINDS = {
    "51": "Explosive eruption",
    "52": "Eruption",
    "54": "Continuous eruption ongoing",
    "55": "Continuous eruption stopped",
    "56": "Multiple eruptions",
    "61": "Possible explosion",
    "62": "Possible eruption",
    "64": "Continuous eruption ongoing",
    "65": "Eruption appears to have stopped",
}

# Ashfall forecast polygon codes.
BOUSAI_VOLCANO_ASH_KINDS = {
    "70": "Ash fall",
    "71": "Light ash fall",
    "72": "Moderate ash fall",
    "73": "Heavy ash fall",
    "75": "Small cinders",
}

BOUSAI_VOLCANO_ASH_TYPES = {
    "scheduled": "Scheduled",
    "quick": "Preliminary",
    "detail": "Detailed",
}

# ---------------------------------------------------------------------------
# Warnings

def bousai_volcano_entry(loc, code, kind_code, issued, cond = "", prev_code = ""):
    """One volcano state dict (see bousai_volcano_status) or None for an unknown volcano/kind."""
    row = BOUSAI_VOLCANOES.get(code)
    kind = BOUSAI_VOLCANO_KINDS.get(kind_code)
    if row == None or kind == None:
        return None
    prev = BOUSAI_VOLCANO_KINDS.get(prev_code)
    return {
        "code": code,
        "name_en": row[0],
        "level": kind[0],
        "sev": kind[1],
        "kind_en": kind[2],
        "short_en": kind[3],
        "label": kind[4],
        "issued": issued,
        "lat": row[1],
        "lon": row[2],
        "distance_km": int(bousai_distance_km(loc["lat"], loc["lon"], row[1], row[2]) + 0.5),
        "bearing": bousai_bearing_name(loc["lat"], loc["lon"], row[1], row[2]),
        "cond_en": BOUSAI_VOLCANO_COND.get(cond, ""),
        "prev_label": prev[4] if prev else "",
        "prev_sev": prev[1] if prev else None,
    }

def bousai_volcano_sort(states):
    """Severity descending, alert-level volcanoes before keyword-only ones, then nearest first."""
    return sorted(states, key = lambda s: (-s["sev"], 0 if s["level"] else 1, s["distance_km"], s["name_en"]))

def bousai_volcano_status(config):
    """Rich state of every volcano in JMA's current warning list, severest first.

    Each dict has code, name_en, level (1..5 or None), sev (0..5), kind_en (official keyword),
    short_en, label (badge text), issued (time), lat, lon, distance_km, bearing (compass name from
    the configured location to the volcano), cond_en (Raised/Lowered/...), prev_label, prev_sev.
    Returns None when the feed is unavailable and [] when it lists nothing.
    """
    data = bousai_get_json(BOUSAI_VOLCANO_URL + "warning.json", ttl = 60)
    if type(data) != "list":
        return None
    loc = bousai_location(config)
    out = []
    for report in data:
        if type(report) != "dict":
            continue
        issued = bousai_parse_time(report.get("reportDatetime"))
        for info in report.get("volcanoInfos") or []:
            if "対象火山" not in (info.get("type") or ""):
                continue
            for item in info.get("items") or []:
                for area in item.get("areas") or []:
                    entry = bousai_volcano_entry(loc, area.get("code") or "", item.get("code") or "", issued, item.get("condition") or "", item.get("lastCode") or "")
                    if entry != None:
                        out.append(entry)
    return bousai_volcano_sort(out)

def bousai_volcano_current(config):
    """Volcanoes in JMA's current warning list, severest first (sev desc, alert-level volcanoes
    before keyword-only warnings, then nearest to the configured location).

    Returns [{code, name_en, level, sev, kind_en, issued, lat, lon, distance_km}] where level is the
    Volcanic Alert Level 1..5 (None for volcanoes without alert levels), sev is the 0..5 severity
    index for ui["sev"] (Lv2 -> 2 ... Lv5 -> 5; Lv1/forecast-only entries are 1, filter with
    sev >= 2 for alerts), kind_en is JMA's English keyword (e.g. "Level 3 (Do not approach the
    volcano)"), issued is a time object and distance_km is measured from the configured location.
    [] when the feed is unavailable or nothing is listed.
    """
    out = []
    for s in bousai_volcano_status(config) or []:
        out.append({
            "code": s["code"],
            "name_en": s["name_en"],
            "level": s["level"],
            "sev": s["sev"],
            "kind_en": s["kind_en"],
            "issued": s["issued"],
            "lat": s["lat"],
            "lon": s["lon"],
            "distance_km": s["distance_km"],
        })
    return out

def bousai_volcano_nearest(config, count = 3, states = None):
    """The `count` volcanoes closest to the configured location (any alert level), nearest first.

    Each dict has code, name_en, lat, lon, distance_km, bearing, sev, label, level. Volcanoes missing
    from `states` (a bousai_volcano_status result) are Lv1 when they use alert levels, else sev 0.
    """
    loc = bousai_location(config)
    by_code = {}
    for s in states or []:
        by_code[s["code"]] = s
    ranked = []
    for code, row in BOUSAI_VOLCANOES.items():
        ranked.append((bousai_distance_km(loc["lat"], loc["lon"], row[1], row[2]), code))
    out = []
    for r in sorted(ranked)[:count]:
        code = r[1]
        row = BOUSAI_VOLCANOES[code]
        s = by_code.get(code)
        out.append({
            "code": code,
            "name_en": row[0],
            "lat": row[1],
            "lon": row[2],
            "distance_km": int(r[0] + 0.5),
            "bearing": bousai_bearing_name(loc["lat"], loc["lon"], row[1], row[2]),
            "sev": s["sev"] if s else (1 if code in BOUSAI_VOLCANO_LEVEL_OPS else 0),
            "label": s["label"] if s else ("Lv1" if code in BOUSAI_VOLCANO_LEVEL_OPS else "Calm"),
            "level": s["level"] if s else (1 if code in BOUSAI_VOLCANO_LEVEL_OPS else None),
        })
    return out

def bousai_volcano_places(code):
    """English municipality names under a volcano's warning (JMA multilingual VFVO50); [] if unknown."""
    data = bousai_get_json(BOUSAI_VOLCANO_MULTI_URL, ttl = 600)
    if type(data) != "dict":
        return []
    for report in data.get("report") or []:
        area = (report.get("volcanoInfo") or {}).get("area") or {}
        if area.get("code") != code:
            continue
        names = []
        for group in report.get("volcanoAreaInfo") or []:
            for a in group.get("areas") or []:
                name = (a.get("name") or "").split(":")[-1].strip()
                if name and name not in names:
                    names.append(name)
        return names
    return []

# ---------------------------------------------------------------------------
# Eruption flash reports

def bousai_volcano_event_code(event_id):
    """Volcano code in a JMA event id ('20260101123456_506' or '506')."""
    s = str(event_id or "")
    return s.split("_")[-1] if "_" in s else s[-3:]

def bousai_volcano_flash_reports(max_age_hours = 24, limit = 3):
    """Recent eruption flash reports (噴火速報), newest first, cancelled ones removed.

    Each dict has code, name_en, time, kind_code, text_en, event_id, age_minutes. [] when nothing is
    listed or the feed is unavailable.
    """
    listing = bousai_get_json(BOUSAI_VOLCANO_URL + "eruption.json", ttl = 30)
    if type(listing) != "list":
        return []
    cancelled = {}
    for e in listing:
        if type(e) == "dict" and e.get("infoType") == "取消":
            cancelled[e.get("eventId")] = True
    now = time.now()
    out = []
    seen = {}
    for e in sorted([e for e in listing if type(e) == "dict"], key = lambda e: e.get("reportDatetime") or "", reverse = True):
        event_id = e.get("eventId") or ""
        if event_id in cancelled or event_id in seen or e.get("infoType") == "取消":
            continue
        seen[event_id] = True
        issued = bousai_parse_time(e.get("reportDatetime"))
        if issued == None:
            continue
        age = int((now - issued).seconds // 60)
        if age > max_age_hours * 60:
            continue
        code = bousai_volcano_event_code(event_id)
        row = BOUSAI_VOLCANOES.get(code)
        if row == None:
            continue
        kind_code = ""
        if len(out) < limit:
            detail = bousai_get_json(BOUSAI_VOLCANO_URL + "eruption/%s.json" % event_id, ttl = 300)
            for info in (detail or {}).get("volcanoInfos") or []:
                items = info.get("items") or []
                if items:
                    kind_code = items[0].get("code") or ""
                    break
        out.append({
            "code": code,
            "name_en": row[0],
            "time": issued,
            "kind_code": kind_code,
            "text_en": BOUSAI_VOLCANO_FLASH_KINDS.get(kind_code, "Eruption"),
            "event_id": event_id,
            "age_minutes": age,
        })
        if len(out) >= limit:
            break
    return out

def bousai_volcano_flash():
    """Recent eruption flash reports (JMA 噴火速報) within the last 24 hours, newest first.

    Returns [{name_en, time, text_en}] e.g. {"Sakurajima", <time>, "Explosive eruption"}; [] when
    there is none or the feed is unavailable.
    """
    out = []
    for f in bousai_volcano_flash_reports():
        out.append({"name_en": f["name_en"], "time": f["time"], "text_en": f["text_en"]})
    return out

# ---------------------------------------------------------------------------
# Ashfall forecasts

def bousai_volcano_coord(s):
    """'+3135.55+13039.40+1117/' (ddmm.mm, dddmm.mm, elevation) -> (lat, lon) or None."""
    s = s or ""
    signs = [i for i in range(len(s)) if s[i] == "+" or s[i] == "-"]
    if len(signs) < 2:
        return None
    end = signs[2] if len(signs) > 2 else len(s)
    parts = []
    for a, b in ((signs[0], signs[1]), (signs[1], end)):
        raw = s[a:b].rstrip("/")
        v = float(raw[1:])
        deg = math.floor(v / 100)
        val = deg + (v - deg * 100) / 60.0
        parts.append(-val if raw[0] == "-" else val)
    return (parts[0], parts[1])

def bousai_volcano_ring(poly):
    """'+32.20+131.80/+32.21+131.82/...' -> [(lat, lon), ...]."""
    ring = []
    for part in (poly or "").split("/"):
        if len(part) < 4:
            continue
        cut = -1
        for i in range(1, len(part)):
            if part[i] == "+" or part[i] == "-":
                cut = i
                break
        if cut < 0:
            continue
        ring.append((float(part[:cut]), float(part[cut:])))
    return ring

def bousai_volcano_inside(rings, lat, lon):
    """True when (lat, lon) lies inside any of the rings (ray casting on the lat/lon plane)."""
    for ring in rings:
        inside = False
        j = len(ring) - 1
        for i in range(len(ring)):
            yi, xi = ring[i]
            yj, xj = ring[j]
            if (yi > lat) != (yj > lat) and lon < (xj - xi) * (lat - yi) / (yj - yi) + xi:
                inside = not inside
            j = i
        if inside:
            return True
    return False

def bousai_volcano_extent(rings, lat0, lon0):
    """(distance km, compass name) from the crater to the farthest ring vertex; (0, "") if no rings."""
    best = 0.0
    where = None
    for ring in rings:
        for p in ring:
            d = bousai_distance_km(lat0, lon0, p[0], p[1])
            if d > best:
                best = d
                where = p
    if where == None:
        return 0, ""
    return int(best + 0.5), bousai_bearing_name(lat0, lon0, where[0], where[1])

def bousai_volcano_window(info, lat0, lon0, loc):
    """Normalise one JMA ashinfos entry: layers by polygon code, cinders, extent and user hit flags."""
    layers = []
    cinders = []
    ash_rings = []
    for item in sorted(info.get("items") or [], key = lambda i: i.get("code") or ""):
        rings = [bousai_volcano_ring(p) for p in item.get("polygons") or []]
        code = item.get("code") or ""
        if code == "75":
            cinders.extend(rings)
        elif code in BOUSAI_VOLCANO_ASH_KINDS:
            layers.append((code, rings))
            ash_rings.extend(rings)
    ash_km, ash_dir = bousai_volcano_extent(ash_rings, lat0, lon0)
    cinder_km, cinder_dir = bousai_volcano_extent(cinders, lat0, lon0)
    return {
        "start": bousai_parse_time(info.get("startTime")),
        "end": bousai_parse_time(info.get("endTime")),
        "layers": layers,
        "cinders": cinders,
        "ash_km": ash_km,
        "ash_dir": ash_dir,
        "cinder_km": cinder_km,
        "cinder_dir": cinder_dir,
        "ash_hit": bousai_volcano_inside(ash_rings, loc["lat"], loc["lon"]),
        "cinder_hit": bousai_volcano_inside(cinders, loc["lat"], loc["lon"]),
    }

def bousai_volcano_ash_codes():
    """Volcano codes with a published ashfall forecast: {code: {"type": ..., "reportDatetime": ...}}."""
    data = bousai_get_json(BOUSAI_VOLCANO_URL + "ashfall/japan.json", ttl = 300)
    return data if type(data) == "dict" else {}

def bousai_volcano_ashfall(code, config):
    """Normalised ashfall forecast for a volcano, or None.

    {code, name_en, type ("scheduled" | "quick" | "detail"), type_en, issued, lat, lon, windows}
    where every window has start, end, layers [(polygon code, rings)], cinders (rings), ash_km,
    ash_dir, cinder_km, cinder_dir, ash_hit and cinder_hit (the configured location is inside).
    A scheduled forecast describes where ash would fall IF an eruption occurred; quick and detail
    forecasts follow an actual eruption.
    """
    data = bousai_get_json(BOUSAI_VOLCANO_URL + "ashfall/%s.json" % code, ttl = 300)
    row = BOUSAI_VOLCANOES.get(code)
    if type(data) != "dict" or row == None:
        return None
    best = data.get("scheduled") if type(data.get("scheduled")) == "dict" else None
    best_time = None
    now = time.now()
    for other in data.get("others") or []:
        if type(other) != "dict":
            continue
        t = bousai_parse_time(other.get("reportDatetime"))
        if t == None or (now - t).hours > 12:
            continue
        if best_time == None or t > best_time:
            best = other
            best_time = t
    if best == None:
        return None
    coord = bousai_volcano_coord(best.get("coordinate")) or (row[1], row[2])
    loc = bousai_location(config)
    windows = [bousai_volcano_window(i, coord[0], coord[1], loc) for i in best.get("ashinfos") or []]
    kind = best.get("type") or "scheduled"
    return {
        "code": code,
        "name_en": row[0],
        "type": kind,
        "type_en": BOUSAI_VOLCANO_ASH_TYPES.get(kind, "Forecast"),
        "issued": bousai_parse_time(best.get("reportDatetime")),
        "lat": coord[0],
        "lon": coord[1],
        "windows": windows,
    }

# ---------------------------------------------------------------------------
# Demo sample

def bousai_volcano_plume(lat0, lon0, bearing, length_km, width_km):
    """Teardrop-shaped ring (lat, lon) from the crater towards `bearing` degrees (demo ash plume)."""
    sb = math.sin(math.radians(bearing))
    cb = math.cos(math.radians(bearing))
    kx = 111.2 * math.cos(math.radians(lat0))
    left = []
    right = []
    steps = 10
    for i in range(steps + 1):
        t = i / float(steps)
        along = length_km * t
        half = width_km / 2.0 * math.sin(math.pi * math.pow(t, 1.3))
        for side, bucket in ((1, left), (-1, right)):
            east = along * sb + side * half * cb
            north = along * cb - side * half * sb
            bucket.append((lat0 + north / 111.2, lon0 + east / kx))
    return left + list(reversed(right))

def bousai_volcano_demo(config):
    """Embedded sample for previews and the 'Show sample alert' toggle.

    Sakurajima at Lv3 with a just-issued eruption flash report and a preliminary ashfall forecast,
    plus a few other volcanoes at Lv2 / caution. Modelled on the explosive eruption of Sakurajima
    (Minamidake crater) on 24 July 2022; the other states and the ash plume are illustrative.
    Returns {"states": [...], "flash": [...], "ash": {code: forecast}} in the shapes of the live functions.
    """
    loc = bousai_location(config)
    now = time.now()
    states = []
    for code, kind, days in (("506", "13", 90), ("511", "12", 400), ("551", "12", 365), ("503", "12", 50), ("108", "12", 5), ("326", "22", 40)):
        entry = bousai_volcano_entry(loc, code, kind, now - time.parse_duration("%dh" % (days * 24)))
        if entry != None:
            states.append(entry)
    erupted = now - time.parse_duration("7m")
    flash = [{
        "code": "506",
        "name_en": "Sakurajima",
        "time": erupted,
        "kind_code": "51",
        "text_en": BOUSAI_VOLCANO_FLASH_KINDS["51"],
        "event_id": "demo_506",
        "age_minutes": 7,
    }]
    crater = BOUSAI_VOLCANOES["506"]
    ash = bousai_volcano_plume(crater[1], crater[2], 85, 48, 16)
    heavy = bousai_volcano_plume(crater[1], crater[2], 85, 22, 6)
    cinders = bousai_volcano_plume(crater[1], crater[2], 85, 5, 3)
    ash_km, ash_dir = bousai_volcano_extent([ash], crater[1], crater[2])
    cinder_km, cinder_dir = bousai_volcano_extent([cinders], crater[1], crater[2])
    forecast = {
        "code": "506",
        "name_en": "Sakurajima",
        "type": "quick",
        "type_en": BOUSAI_VOLCANO_ASH_TYPES["quick"],
        "issued": erupted + time.parse_duration("5m"),
        "lat": crater[1],
        "lon": crater[2],
        "windows": [{
            "start": erupted,
            "end": erupted + time.parse_duration("1h"),
            "layers": [("70", [ash]), ("72", [heavy])],
            "cinders": [cinders],
            "ash_km": ash_km,
            "ash_dir": ash_dir,
            "cinder_km": cinder_km,
            "cinder_dir": cinder_dir,
            "ash_hit": False,
            "cinder_hit": False,
        }],
    }
    return {"states": bousai_volcano_sort(states), "flash": flash, "ash": {"506": forecast}}

# ---------------------------------------------------------------------------
# Text layout helpers (bounded scrolling comes from core: bousai_fit / bousai_ticker with `frames`).

def bousai_volcano_fit_len(ui, s, width, font = None):
    """Length of the longest prefix of s that renders within width px."""
    lo = 0
    hi = len(s)
    for _ in range(8):
        if lo >= hi:
            break
        mid = (lo + hi + 1) // 2
        if bousai_text_width(ui, s[:mid], font) <= width:
            lo = mid
        else:
            hi = mid - 1
    return lo

def bousai_volcano_wrap(ui, s, width, font = None):
    """Word-wrap s into lines of at most width px (over-long words are cut)."""
    lines = []
    cur = ""
    for word in s.split(" "):
        trial = cur + " " + word if cur else word
        if bousai_text_width(ui, trial, font) <= width:
            cur = trial
            continue
        if cur:
            lines.append(cur)
        cur = word
        for _ in range(6):
            k = bousai_volcano_fit_len(ui, cur, width, font)
            if k >= len(cur) or k < 1:
                break
            lines.append(cur[:k])
            cur = cur[k:]
    if cur:
        lines.append(cur)
    return lines

def bousai_volcano_page(ui, header, rows, frames):
    """One top-aligned page: header band (widget or None) plus rows (str | (text, colour) | widget).

    Over-long strings scroll within exactly `frames` frames, so the page never outlasts its share
    of the animation budget.
    """
    width = canvas.width()
    kids = []
    if header != None:
        kids.append(header)
    for r in rows:
        if type(r) == "string":
            r = bousai_fit(ui, r, frames = frames)
        elif type(r) == "tuple" or type(r) == "list":
            r = bousai_fit(ui, r[0], color = r[1], frames = frames)
        kids.append(render.Box(width = width, height = ui["line_h"], child = r))
    return render.Box(width = width, height = canvas.height(), child = render.Column(expanded = True, main_align = "start", cross_align = "start", children = kids))

def bousai_volcano_scroll_frames(ui, rows, base):
    """Frames for a page whose over-wide strings should scroll at about 2 px/frame or slower (base .. 60)."""
    travel = 0
    for r in rows:
        text = None
        if type(r) == "string":
            text = r
        elif type(r) == "tuple" or type(r) == "list":
            text = r[0]
        if text != None:
            travel = max(travel, bousai_text_width(ui, text) - canvas.width())
    if travel <= 0:
        return base
    return min(60, max(base, 16 + (travel + 1) // 2))

def bousai_volcano_polygon(points, fill_color = None, stroke_color = None):
    """render.Polygon at absolute screen coordinates (the widget itself always draws at its own origin)."""
    x0 = min([p[0] for p in points])
    y0 = min([p[1] for p in points])
    poly = render.Polygon(vertices = [(p[0] - x0, p[1] - y0) for p in points], fill_color = fill_color, stroke_color = stroke_color, stroke_width = 1)
    return render.Padding(pad = (x0, y0, 0, 0), child = poly)
