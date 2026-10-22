"""Typhoon domain library for the Bousai suite.

JMA tropical cyclone analysis and 5-day forecast (typhoon/data/targetTc.json,
<TC>/specifications.json, <TC>/forecast.json), with the official English terms of JMA's
multilingual typhoon pages (Typhoon / Very Strong Typhoon / Violent Typhoon, Large / Very large).

Public API for other apps (plain values, no widgets, never raises on a missing feed):
  bousai_typhoon_current(config) -> [{tc_id, number, name_en, category_en, pressure_hpa, wind_ms,
                                      gust_ms, lat, lon, course_en, speed_kmh, issued, distance_km, bearing}]
"""

# bousai: requires core

load("math.star", "math")
load("render.star", "canvas", "render")
load("time.star", "time")

BOUSAI_TYPHOON_URL = "https://www.jma.go.jp/bosai/typhoon/data/"

BOUSAI_TYPHOON_CLASS = {
    "TD": "Tropical Depression",
    "TS": "Tropical Storm",
    "STS": "Severe Tropical Storm",
    "TY": "Typhoon",
    "LOW": "Extratropical Cyclone",
}

BOUSAI_TYPHOON_INTENSITY = {
    "強い": "",
    "非常に強い": "Very Strong",
    "猛烈な": "Violent",
}

BOUSAI_TYPHOON_SCALE = {
    "大型": "Large",
    "超大型": "Very large",
}

BOUSAI_TYPHOON_DIRS = {
    "北": "N",
    "北北東": "NNE",
    "北東": "NE",
    "東北東": "ENE",
    "東": "E",
    "東南東": "ESE",
    "南東": "SE",
    "南南東": "SSE",
    "南": "S",
    "南南西": "SSW",
    "南西": "SW",
    "西南西": "WSW",
    "西": "W",
    "西北西": "WNW",
    "北西": "NW",
    "北北西": "NNW",
    "全域": "all around",
}

BOUSAI_TYPHOON_SPEED_WORDS = {
    "ゆっくり": "Slow",
    "ほとんど停滞": "Almost stationary",
}

# ---------------------------------------------------------------------------
# Parsing helpers

def bousai_typhoon_num(v):
    """JMA numeric string/number -> int or float; None for '', '-', words."""
    if v == None:
        return None
    if type(v) == "int" or type(v) == "float":
        return v
    s = str(v).strip()
    if s == "" or not s.replace(".", "", 1).isdigit():
        return None
    return float(s) if "." in s else int(s)

def bousai_typhoon_int(v):
    n = bousai_typhoon_num(v)
    return None if n == None else int(n + 0.5)

def bousai_typhoon_sev(cat, intensity_en = ""):
    """Display severity 0..5 for ui["sev"]: TD 1, TS 2, STS 3, TY 4, Violent TY 5, extratropical 0."""
    if cat == "LOW":
        return 0
    if cat == "TD":
        return 1
    if cat == "TS":
        return 2
    if cat == "STS":
        return 3
    return 5 if intensity_en == "Violent" else 4

def bousai_typhoon_category_en(cat, intensity_en = ""):
    """'Violent Typhoon', 'Typhoon', 'Severe Tropical Storm', ... (JMA English wording)."""
    base = BOUSAI_TYPHOON_CLASS.get(cat, cat or "Tropical Cyclone")
    if cat == "TY" and intensity_en:
        return intensity_en + " Typhoon"
    return base

def bousai_typhoon_dir(jp):
    """English direction for a JMA direction: a Japanese string ('北西'), or a {"jp", "en"} dict, which JMA uses for
    the whole-area wind radius ({"jp": "全域", "en": "All"})."""
    if type(jp) == "dict":
        return BOUSAI_TYPHOON_DIRS.get(jp.get("jp") or "", jp.get("en") or "")
    return BOUSAI_TYPHOON_DIRS.get(jp or "", "")

def bousai_typhoon_area_km(areas):
    """[{area, range: {km}}] -> [(English direction, km)] (empty when the radius is missing)."""
    out = []
    for a in areas or []:
        km = bousai_typhoon_int(((a.get("range") or {}).get("km")))
        if km != None:
            out.append((bousai_typhoon_dir(a.get("area")), km))
    return out

def bousai_typhoon_step(part, loc):
    """Normalise one specifications.json part (analysis or forecast)."""
    pos = (part.get("position") or {}).get("deg") or [None, None]
    wind = part.get("maximumWind") or {}
    cat = ((part.get("category") or {}).get("en")) or ""
    intensity = BOUSAI_TYPHOON_INTENSITY.get(part.get("intensity") or "", "")
    speed = part.get("speed") or {}
    speed_raw = speed.get("km/h")
    lat = pos[0]
    lon = pos[1]
    out = {
        "hours": bousai_typhoon_int(part.get("advancedHours")) or 0,
        "valid": bousai_parse_time(((part.get("validtime") or {}).get("JST"))),
        "lat": lat,
        "lon": lon,
        "cat": cat,
        "intensity_en": intensity,
        "category_en": bousai_typhoon_category_en(cat, intensity),
        "sev": bousai_typhoon_sev(cat, intensity),
        "scale_en": BOUSAI_TYPHOON_SCALE.get(part.get("scale") or "", ""),
        "pressure_hpa": bousai_typhoon_int(part.get("pressure")),
        "wind_ms": bousai_typhoon_int((wind.get("sustained") or {}).get("m/s")),
        "wind_kt": bousai_typhoon_int((wind.get("sustained") or {}).get("kt")),
        "gust_ms": bousai_typhoon_int((wind.get("gust") or {}).get("m/s")),
        "gust_kt": bousai_typhoon_int((wind.get("gust") or {}).get("kt")),
        "course_en": bousai_typhoon_dir(part.get("course")),
        "speed_kmh": bousai_typhoon_int(speed_raw),
        "speed_kt": bousai_typhoon_int(speed.get("kt")),
        "speed_word": BOUSAI_TYPHOON_SPEED_WORDS.get(speed_raw or "", ""),
        "radius_km": bousai_typhoon_int((part.get("probabilityCircleRadius") or {}).get("km")),
        "storm_km": bousai_typhoon_area_km(part.get("stormWarning")),
        "gale_km": bousai_typhoon_area_km(part.get("galeWarning")),
        "distance_km": None,
        "bearing": "",
    }
    if lat != None and lon != None:
        out["distance_km"] = int(bousai_distance_km(loc["lat"], loc["lon"], lat, lon) + 0.5)
        out["bearing"] = bousai_bearing_name(loc["lat"], loc["lon"], lat, lon)
    return out

def bousai_typhoon_build(tc_id, spec, forecast, loc):
    """Typhoon dict from specifications.json (+ optional forecast.json track) or None.

    Keys: tc_id, number, name_en, cat, category_en, intensity_en, scale_en, sev, pressure_hpa,
    wind_ms/kt, gust_ms/kt, lat, lon, course_en, speed_kmh/kt/word, issued, valid, distance_km,
    bearing, storm_km, gale_km ([(direction, km)]), steps (forecast parts, oldest first, each with
    hours, valid, lat, lon, cat, category_en, sev, pressure_hpa, wind_ms, gust_ms, radius_km, ...),
    past ([[lat, lon]] oldest first), gale_circle ([lat, lon, km] or None).
    """
    if type(spec) != "list" or not spec:
        return None
    title = {}
    analysis = None
    steps = []
    for part in spec:
        if type(part) != "dict":
            continue
        if part.get("part") == "title":
            title = part
        elif bousai_typhoon_int(part.get("advancedHours")) == 0 and analysis == None:
            analysis = bousai_typhoon_step(part, loc)
        elif (bousai_typhoon_int(part.get("advancedHours")) or 0) > 0:
            steps.append(bousai_typhoon_step(part, loc))
    if analysis == None or analysis["lat"] == None:
        return None
    number_text = str(title.get("typhoonNumber") or "")
    number = None
    if len(number_text) == 4 and number_text.isdigit():
        number = int(number_text[2:])
    past = []
    gale_circle = None
    for entry in forecast or []:
        if type(entry) != "dict" or bousai_typhoon_int(entry.get("advancedHours")) != 0:
            continue
        track = entry.get("track") or {}
        for pt in (track.get("preTyphoon") or []) + (track.get("typhoon") or []):
            if len(pt) == 2 and (not past or past[-1] != pt):
                past.append(pt)
        gale = entry.get("galeWarningArea") or {}
        if gale.get("center") and gale.get("radius"):
            gale_circle = [gale["center"][0], gale["center"][1], int(gale["radius"] / 1000.0 + 0.5)]
    out = dict(analysis)
    out.update({
        "tc_id": tc_id,
        "number": number,
        "name_en": ((title.get("name") or {}).get("en") or "").strip(),
        "issued": bousai_parse_time(((title.get("issue") or {}).get("JST"))) or analysis["valid"],
        "steps": steps,
        "past": past,
        "gale_circle": gale_circle,
    })
    return out

def bousai_typhoon_list(config, with_track = True):
    """Rich dicts for every active tropical cyclone (extratropical ones dropped), nearest first.

    Returns None when JMA's target list is unavailable, [] when no cyclone is active. Each dict is a
    bousai_typhoon_build result; with_track=False skips forecast.json (no past track).
    """
    targets = bousai_get_json(BOUSAI_TYPHOON_URL + "targetTc.json", ttl = 300)
    if type(targets) != "list":
        return None
    loc = bousai_location(config)
    out = []
    for t in targets:
        if type(t) != "dict" or t.get("category") == "LOW":
            continue
        tc_id = t.get("tropicalCyclone") or ""
        if not tc_id:
            continue
        spec = bousai_get_json(BOUSAI_TYPHOON_URL + "%s/specifications.json" % tc_id, ttl = 600)
        forecast = bousai_get_json(BOUSAI_TYPHOON_URL + "%s/forecast.json" % tc_id, ttl = 600) if with_track else None
        ty = bousai_typhoon_build(tc_id, spec, forecast, loc)
        if ty != None and ty["cat"] != "LOW":
            out.append(ty)
    return sorted(out, key = lambda t: (t["distance_km"] or 0, t["tc_id"]))

def bousai_typhoon_current(config):
    """Active typhoons / tropical cyclones from JMA, nearest to the configured location first.

    Returns [{tc_id, number, name_en, category_en, pressure_hpa, wind_ms, gust_ms, lat, lon,
    course_en, speed_kmh, issued, distance_km, bearing}]: tc_id is JMA's id ("TC2636"), number the
    typhoon number (30 for "Typhoon No. 30", None for a depression), category_en JMA's English class
    ("Violent Typhoon", "Very Strong Typhoon", "Typhoon", "Severe Tropical Storm", "Tropical Storm",
    "Tropical Depression"), pressure in hPa, wind_ms the maximum sustained and gust_ms the maximum
    gust in m/s (None when unpublished), course_en the movement as a 16-point compass name (or
    "Slow"/"Almost stationary"), speed_kmh in km/h (None when slow), issued the analysis issue time
    (time object) and distance_km / bearing (16-point compass name from the configured location to
    the typhoon centre). [] when none is active or the feed is unavailable.
    """
    out = []
    for t in bousai_typhoon_list(config, False) or []:
        out.append({
            "tc_id": t["tc_id"],
            "number": t["number"],
            "name_en": t["name_en"],
            "category_en": t["category_en"],
            "pressure_hpa": t["pressure_hpa"],
            "wind_ms": t["wind_ms"],
            "gust_ms": t["gust_ms"],
            "lat": t["lat"],
            "lon": t["lon"],
            "course_en": t["course_en"] or t["speed_word"],
            "speed_kmh": t["speed_kmh"],
            "issued": t["issued"],
            "distance_km": t["distance_km"],
            "bearing": t["bearing"],
        })
    return out

# ---------------------------------------------------------------------------
# Geometry

def bousai_typhoon_circle(lat, lon, radius_km, points = 24):
    """Great-circle ring of `points` (lat, lon) vertices at radius_km around a centre."""
    d = radius_km / 6371.0
    p1 = math.radians(lat)
    l1 = math.radians(lon)
    out = []
    for i in range(points):
        b = 2 * math.pi * i / points
        p2 = math.asin(math.sin(p1) * math.cos(d) + math.cos(p1) * math.sin(d) * math.cos(b))
        l2 = l1 + math.atan2(math.sin(b) * math.sin(d) * math.cos(p1), math.cos(d) - math.sin(p1) * math.sin(p2))
        out.append((math.degrees(p2), math.degrees(l2)))
    return out

def bousai_typhoon_closest(ty, loc):
    """Closest approach of the forecast centre line to the configured location: (km, hours) or None."""
    pts = [(0, ty["lat"], ty["lon"])]
    for s in ty["steps"]:
        pts.append((s["hours"], s["lat"], s["lon"]))
    if len(pts) < 2:
        return None
    best = None
    for i in range(len(pts) - 1):
        a = pts[i]
        b = pts[i + 1]
        for k in range(0, 7):
            t = k / 6.0
            lat = a[1] + (b[1] - a[1]) * t
            lon = a[2] + (b[2] - a[2]) * t
            d = bousai_distance_km(loc["lat"], loc["lon"], lat, lon)
            if best == None or d < best[0]:
                best = (d, a[0] + (b[0] - a[0]) * t)
    return (int(best[0] + 0.5), int(best[1] + 0.5))

# ---------------------------------------------------------------------------
# Demo sample

def bousai_typhoon_stamp(base, hours):
    """{"JST": RFC3339 time} for `hours` after base, in JMA's specifications.json shape."""
    return {"JST": (base + time.parse_duration("%dh" % hours)).format("2006-01-02T15:04:05-07:00")}

def bousai_typhoon_demo(config):
    """Embedded sample for previews and the 'Show sample alert' toggle: a list with one typhoon.

    Modelled on Typhoon No. 10 (Shanshan) approaching Kyushu on 28-29 August 2024: a large, very
    strong typhoon heading north-north-west then north-east over Kyushu and Shikoku. Positions,
    intensities and radii are rounded illustrations, not an archived JMA record; times are relative
    to now so the sample always looks current.
    """
    loc = bousai_location(config)
    n = bousai_now()
    base = time.time(year = n.year, month = n.month, day = n.day, hour = n.hour, location = BOUSAI_JST)

    # advancedHours, lat, lon, category, intensity, hPa, wind, gust, radius km, course, km/h
    rows = [
        (0, 30.1, 129.9, "TY", "非常に強い", 945, 45, 65, 0, "北北西", 20),
        (12, 32.0, 130.2, "TY", "強い", 955, 40, 55, 70, "北", 15),
        (24, 33.1, 131.5, "STS", "-", 980, 28, 40, 90, "北東", 20),
        (45, 34.0, 134.4, "TS", "-", 990, 23, 35, 150, "東北東", 20),
        (69, 35.2, 137.8, "TS", "-", 992, 20, 30, 220, "東北東", 30),
        (93, 36.8, 141.5, "LOW", "-", 996, 0, 0, 320, "東北東", 45),
        (117, 38.2, 146.5, "LOW", "-", 998, 0, 0, 460, "東", 50),
    ]
    spec = [{
        "part": "title",
        "issue": bousai_typhoon_stamp(base, 0),
        "typhoonNumber": "2410",
        "name": {"jp": "サンサン", "en": "Shanshan"},
        "category": {"jp": "台風", "en": "TY"},
    }]
    for hours, lat, lon, cat, intensity, hpa, wind, gust, radius, course, speed in rows:
        part = {
            "advancedHours": hours,
            "category": {"en": cat},
            "intensity": intensity,
            "position": {"deg": [lat, lon]},
            "course": course,
            "speed": {"km/h": str(speed), "kt": str(int(speed / 1.852 + 0.5))},
            "pressure": str(hpa),
            "validtime": bousai_typhoon_stamp(base, hours),
        }
        if wind > 0:
            part["maximumWind"] = {"sustained": {"m/s": str(wind), "kt": str(int(wind * 1.944 + 0.5))}, "gust": {"m/s": str(gust), "kt": str(int(gust * 1.944 + 0.5))}}
        if hours == 0:
            part["scale"] = "大型"
            part["galeWarning"] = [{"area": "北東", "range": {"km": 650}}, {"area": "南西", "range": {"km": 500}}]
            part["stormWarning"] = [{"area": "北東", "range": {"km": 300}}, {"area": "南西", "range": {"km": 220}}]
        else:
            part["probabilityCircleRadius"] = {"km": radius}
            if wind > 0:
                part["stormWarning"] = [{"area": "全域", "range": {"km": 200 + radius}}]
        spec.append(part)
    past = [[24.0, 136.5], [25.0, 135.2], [26.0, 134.0], [27.0, 132.9], [28.0, 131.9], [29.0, 130.9], [30.1, 129.9]]
    forecast = [{"advancedHours": 0, "track": {"preTyphoon": [], "typhoon": past}, "galeWarningArea": {"center": [30.1, 129.9], "radius": 575000}}]
    ty = bousai_typhoon_build("TC2410", spec, forecast, loc)
    return [ty]

# ---------------------------------------------------------------------------
# Text layout helpers (bounded scrolling comes from core: bousai_fit / bousai_ticker with `frames`).

def bousai_typhoon_fit_len(ui, s, width, font = None):
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

def bousai_typhoon_wrap(ui, s, width, font = None):
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
            k = bousai_typhoon_fit_len(ui, cur, width, font)
            if k >= len(cur) or k < 1:
                break
            lines.append(cur[:k])
            cur = cur[k:]
    if cur:
        lines.append(cur)
    return lines

def bousai_typhoon_page(ui, header, rows, frames):
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

def bousai_typhoon_scroll_frames(ui, rows, base):
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

def bousai_typhoon_polygon(points, fill_color = None, stroke_color = None):
    """render.Polygon at absolute screen coordinates (the widget itself always draws at its own origin)."""
    x0 = min([p[0] for p in points])
    y0 = min([p[1] for p in points])
    poly = render.Polygon(vertices = [(p[0] - x0, p[1] - y0) for p in points], fill_color = fill_color, stroke_color = stroke_color, stroke_width = 1)
    return render.Padding(pad = (x0, y0, 0, 0), child = poly)

def bousai_typhoon_line(a, b, color):
    """1 px render.Line between two screen points (the widget itself always draws at its own origin)."""
    x0 = min(a[0], b[0])
    y0 = min(a[1], b[1])
    line = render.Line(x1 = a[0] - x0, y1 = a[1] - y0, x2 = b[0] - x0, y2 = b[1] - y0, color = color, width = 1)
    return render.Padding(pad = (x0, y0, 0, 0), child = line)
