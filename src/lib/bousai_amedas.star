"""AMeDAS real-time observation domain library for the Bousai suite.

JMA AMeDAS station table, nearest-station search, 10-minute observations and
point time series, unit conversion and small chart widgets.

Public API for other apps (no widgets, plain values, never raises on a missing feed):
  bousai_amedas_latest(lat, lon, station = None) -> dict or None
"""

# bousai: requires core

load("math.star", "math")
load("cache.star", "cache")
load("render.star", "canvas", "render")
load("time.star", "time")

BOUSAI_AMEDAS_BASE = "https://www.jma.go.jp/bosai/amedas/"
BOUSAI_AMEDAS_MAX_KM = 120

# windDirection index 0..16 (1 = NNE ... 16 = N).
BOUSAI_AMEDAS_DIRS = ["Calm", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW", "N"]

def bousai_amedas_table():
    """AMeDAS station table {id: {type, elems, lat, lon, alt, kjName, enName}} (cached a day)."""
    t = bousai_get_json(BOUSAI_AMEDAS_BASE + "const/amedastable.json", ttl = 86400)
    return t if type(t) == "dict" else {}

def bousai_amedas_coords(st):
    """(lat, lon) in decimal degrees of a station-table entry."""
    return st["lat"][0] + st["lat"][1] / 60.0, st["lon"][0] + st["lon"][1] / 60.0

def bousai_amedas_observes(st, what):
    """True when the station's elems string says it observes temp / wind / precip."""
    e = st.get("elems") or "00000000"
    if what == "temp":
        return e[0] == "1"
    if what == "wind":
        return e[2] == "1" and e[3] == "1"
    return e[1] == "1"

def bousai_amedas_nearest(table, lat, lon):
    """Nearest station that observes temperature and wind. Returns (id, distance_km) or (None, None)."""
    k = 0.01745329
    cos_lat = math.cos(lat * k)
    best = None
    best_d = 1.0e9
    for sid in table:
        st = table[sid]
        e = st.get("elems") or "00000000"
        if e[0] != "1" or e[2] != "1" or e[3] != "1":
            continue
        slat = st["lat"][0] + st["lat"][1] / 60.0
        slon = st["lon"][0] + st["lon"][1] / 60.0
        dy = slat - lat
        dx = (slon - lon) * cos_lat
        d = dx * dx + dy * dy
        if d < best_d:
            best_d = d
            best = sid
    if best == None:
        return None, None
    slat, slon = bousai_amedas_coords(table[best])
    return best, bousai_distance_km(lat, lon, slat, slon)

def bousai_amedas_find(table, query):
    """Station id for an id or (English / Japanese) name fragment; None if no match."""
    q = (query or "").strip()
    if not q:
        return None
    if q in table:
        return q
    low = q.lower()
    exact, prefix, contains = [], [], []
    for sid in sorted(table.keys()):
        st = table[sid]
        en = (st.get("enName") or "").lower()
        jp = st.get("kjName") or ""
        if en == low or jp == q:
            exact.append(sid)
        elif en.startswith(low) or jp.startswith(q):
            prefix.append(sid)
        elif low in en or q in jp:
            contains.append(sid)
    for group in [exact, prefix, contains]:
        if group:
            for sid in group:
                if bousai_amedas_observes(table[sid], "temp"):
                    return sid
            return group[0]
    return None

def bousai_amedas_val(pair):
    """[value, quality] -> value, or None when missing / not observed (quality >= 5)."""
    if type(pair) != "list" or len(pair) < 2 or pair[0] == None:
        return None
    if pair[1] != None and pair[1] >= 5:
        return None
    return pair[0]

def bousai_amedas_series(station, hours = 6):
    """Last `hours` of 10-minute observations for a station.

    Returns None if the feed is unavailable, else a list of {time, e} oldest first, where e is
    the raw AMeDAS entry ({element: [value, quality], ...}).
    """
    lt = bousai_get_bytes(BOUSAI_AMEDAS_BASE + "data/latest_time.txt", ttl = 60)
    latest = bousai_parse_time((lt or "").strip())
    if latest == None:
        return None
    merged = {}
    for k in range(hours // 3 + 1):
        b = latest - time.parse_duration("%dh" % (3 * k))
        h3 = (b.hour // 3) * 3
        name = "%s_%s" % (b.format("20060102"), ("0%d" % h3) if h3 < 10 else "%d" % h3)
        d = bousai_get_json(BOUSAI_AMEDAS_BASE + "data/point/%s/%s.json" % (station, name), ttl = 120 if k == 0 else 3600)
        if type(d) == "dict":
            merged.update(d)
    if not merged:
        return None
    cutoff = latest - time.parse_duration("%dm" % (hours * 60 + 5))
    out = []
    for key in sorted(merged.keys()):
        t = bousai_parse_time(key)
        if t != None and t >= cutoff and t <= latest:
            out.append({"time": t, "e": merged[key]})
    return out

def bousai_amedas_current(series):
    """Newest series entry that carries any real observation, else None."""
    for i in range(len(series) - 1, -1, -1):
        e = series[i]["e"]
        if bousai_amedas_val(e.get("temp")) != None or bousai_amedas_val(e.get("wind")) != None or bousai_amedas_val(e.get("precipitation10m")) != None:
            return series[i]
    return None

def bousai_amedas_dir(index):
    """16-point English wind direction name from the AMeDAS direction index (None if unknown)."""
    if index == None:
        return None
    i = int(index)
    if i < 0 or i >= len(BOUSAI_AMEDAS_DIRS):
        return None
    return BOUSAI_AMEDAS_DIRS[i]

def bousai_amedas_station(config_station, lat, lon):
    """Resolve station: text override (id or name) else the nearest suitable one.

    Returns (id, table entry, distance_km) or (None, None, None). A station that cannot be
    matched, or no station within BOUSAI_AMEDAS_MAX_KM, gives None.
    """
    table = bousai_amedas_table()
    if not table:
        return None, None, None
    sid = None
    dist = None
    if config_station and config_station.strip():
        sid = bousai_amedas_find(table, config_station)
        if sid == None:
            return None, None, None
        slat, slon = bousai_amedas_coords(table[sid])
        dist = bousai_distance_km(lat, lon, slat, slon)
    else:
        sid, dist = bousai_amedas_nearest(table, lat, lon)
        if sid == None or dist > BOUSAI_AMEDAS_MAX_KM:
            return None, None, None
    return sid, table[sid], dist

def bousai_amedas_latest(lat, lon, station = None):
    """Latest AMeDAS observation for the nearest suitable station (or a station id / name).

    Returns None when no station is within 120 km, the station cannot be found, or the feed is
    unavailable. Otherwise a dict (None for elements the station does not observe):
      station_id, station_en, distance_km (float), time (Pixlet time of the observation),
      temp (C), humidity (%), precip_10m / precip_1h / precip_24h (mm),
      wind_ms (m/s), wind_dir_en (16-point name or 'Calm'), snow_cm (snow depth).
    """
    sid, st, dist = bousai_amedas_station(station, lat, lon)
    if sid == None:
        return None
    series = bousai_amedas_series(sid, 3)
    cur = bousai_amedas_current(series) if series else None
    if cur == None:
        return None
    e = cur["e"]
    return {
        "station_id": sid,
        "station_en": st.get("enName") or sid,
        "distance_km": dist,
        "time": cur["time"],
        "temp": bousai_amedas_val(e.get("temp")),
        "humidity": bousai_amedas_val(e.get("humidity")),
        "precip_10m": bousai_amedas_val(e.get("precipitation10m")),
        "precip_1h": bousai_amedas_val(e.get("precipitation1h")),
        "precip_24h": bousai_amedas_val(e.get("precipitation24h")),
        "wind_ms": bousai_amedas_val(e.get("wind")),
        "wind_dir_en": bousai_amedas_dir(bousai_amedas_val(e.get("windDirection"))),
        "snow_cm": bousai_amedas_val(e.get("snow")),
    }

# ---------------------------------------------------------------------------
# Units

def bousai_amedas_temp(c, unit):
    """Temperature text with one decimal, e.g. '23.5'."""
    if c == None:
        return "--"
    v = c * 9.0 / 5.0 + 32 if unit == "F" else c
    return bousai_fixed(v, 1)

def bousai_amedas_wind(ms, unit):
    """Wind speed number text in m/s, km/h, kt or mph."""
    if ms == None:
        return "--"
    if unit == "kmh":
        return bousai_fixed(ms * 3.6, 0)
    if unit == "kt":
        return bousai_fixed(ms * 1.94384, 0)
    if unit == "mph":
        return bousai_fixed(ms * 2.23694, 0)
    return bousai_fixed(ms, 1)

def bousai_amedas_wind_unit(unit):
    return {"kmh": "km/h", "kt": "kt", "mph": "mph"}.get(unit, "m/s")

def bousai_amedas_precip(mm, unit):
    """Precipitation / snowfall text (mm or inches)."""
    if mm == None:
        return "--"
    if unit == "in":
        return bousai_fixed(mm / 25.4, 2)
    return bousai_fixed(mm, 1)

def bousai_amedas_depth(cm, unit):
    """Snow depth text (cm or inches)."""
    if cm == None:
        return "--"
    if unit == "in":
        return bousai_fixed(cm / 2.54, 1)
    return "%d" % int(cm + 0.5)

# ---------------------------------------------------------------------------
# Widgets

def bousai_amedas_values(series, key):
    """Series values for an element, None where missing."""
    return [bousai_amedas_val(s["e"].get(key)) for s in series]

def bousai_amedas_spark(ui, values, width, height, color, fill = False, lo = None, hi = None):
    """Line chart of values (None skipped). Returns None when fewer than 2 points."""
    pts = [(i, v) for i, v in enumerate(values) if v != None]
    if len(pts) < 2:
        return None
    ys = [p[1] for p in pts]
    ymin = lo if lo != None else min(ys)
    ymax = hi if hi != None else max(ys)
    if ymax - ymin < 1.0:
        mid = (ymax + ymin) / 2.0
        ymin = mid - 0.5
        ymax = mid + 0.5
    return render.Plot(
        data = pts,
        width = width,
        height = height,
        color = color,
        fill = fill,
        fill_color = bousai_mix(color, ui["bg"], 0.55),
        x_lim = (0, max(1, len(values) - 1)),
        y_lim = (ymin, ymax),
    )

def bousai_amedas_clip(ui, text, width):
    """Trim text until it fits width (pages must not contain scrolling marquees: a marquee
    stretches its page's duration inside a Sequence)."""
    t = text
    for _ in range(len(text)):
        if bousai_text_width(ui, t) <= width:
            break
        t = t[:-1]
    return t

def bousai_amedas_header(ui, title, right = None):
    """Title band whose title is clipped to fit (never scrolls)."""
    avail = canvas.width() - 2
    if right:
        avail -= bousai_text_width(ui, right) + 2
    return bousai_header(ui, bousai_amedas_clip(ui, title, avail), right = right)

def bousai_amedas_pager(ui, header, left, left_w, rows):
    """Pages of header + left widget + right-hand text rows; rows are (text, color)."""
    width = canvas.width()
    body_h = canvas.height() - ui["line_h"]
    cap = max(1, body_h // ui["line_h"])
    right_w = width - left_w - 1
    pages = []
    for i in range(0, max(1, len(rows)), cap):
        chunk = rows[i:i + cap]
        col = render.Column(children = [render.Box(width = right_w, height = ui["line_h"], child = bousai_fit(ui, bousai_amedas_clip(ui, r[0], right_w - 1), width = right_w, color = r[1])) for r in chunk])
        pages.append(render.Column(children = [
            header,
            render.Row(children = [
                render.Box(width = left_w, height = body_h, child = left),
                col,
            ]),
        ]))
    return pages

def bousai_amedas_rotate(pages, key, min_frames = 25):
    """Sequence of pages that each stay on screen at least min_frames (2.5 s by default).

    pages is a list of (widget, weight); a page holds min_frames * weight frames. When all pages
    fit the dwell budget (bousai_budget_frames) they are all shown and the spare time is shared.
    Otherwise a window of consecutive pages that fits is shown, starting at an offset stored in
    the cache under `key` and advanced on every render, so every page appears across renders.
    """
    n = len(pages)
    budget = bousai_budget_frames()
    base = [int(min_frames * p[1]) for p in pages]
    total = 0
    for f in base:
        total += f
    chosen = list(range(n))
    if total > budget and n > 1:
        start = int(cache.get(key) or "0") % n
        chosen = []
        used = 0
        for k in range(n):
            i = (start + k) % n
            if chosen and used + base[i] > budget:
                break
            chosen.append(i)
            used += base[i]
        cache.set(key, str(start + len(chosen)), ttl_seconds = 86400)
        total = used
    # Share spare time, but never stretch a page beyond twice its minimum.
    kids = []
    for i in chosen:
        frames = base[i]
        if total < budget:
            frames = min(base[i] * 2, int(base[i] * budget / total))
        kids.append(bousai_hold(render.Column(expanded = True, main_align = "start", children = [pages[i][0]]), frames))
    return kids[0] if len(kids) == 1 else render.Sequence(children = kids)
