"""Tsunami warnings, advisories, forecasts and observations for the Bousai suite.

Reads JMA's tsunami list (bosai/tsunami/data) and the per-report JSON: the warning report
(VTSE41: grades per forecast region with expected arrival and height), the arrival / high tide
report and the coastal and offshore observation reports (VTSE51 / VTSE52). "In effect" follows
JMA's own site: a report counts while it is newer than clearweb.json, and a forecast-only
report also while its ValidDateTime has not passed. Data only: nothing here draws widgets.

Severity (the suite's ui["sev"] index): Major Tsunami Warning 5 (JMA treats it as an emergency
warning), Tsunami Warning 3, Tsunami Advisory 2, Tsunami Forecast (slight sea-level change) 1.
Warning stays at 3 so it keeps JMA's red against the purple of a major warning, and matches the
word "Warning" in BOUSAI_SEVERITY_EN; sev 4 is left to other domains.

Export for other apps: bousai_tsunami_current().
"""

# bousai: requires core data quake

load("math.star", "math")

BOUSAI_TSUNAMI_LIST = "https://www.jma.go.jp/bosai/tsunami/data/list.json"
BOUSAI_TSUNAMI_CLEAR = "https://www.jma.go.jp/bosai/tsunami/data/clearweb.json"
BOUSAI_TSUNAMI_DATA = "https://www.jma.go.jp/bosai/tsunami/data/"
BOUSAI_TSUNAMI_COAST = "https://www.jma.go.jp/bosai/common/const/geojson/tsunami.json"

# Reports older than this are never treated as current, even if the clear time is missing.
BOUSAI_TSUNAMI_MAX_HOURS = 96

# list.json titles that are information rather than a warning / advisory / forecast.
BOUSAI_TSUNAMI_INFO = {
    "各地の満潮時刻・津波到達予想時刻に関する情報": "arrival",
    "津波観測に関する情報": "observed",
    "沖合の津波観測に関する情報": "offshore",
}

# Kind code (Category.Kind.Code) -> severity. 00 = no tsunami, 50 / 60 = warning / advisory lifted.
BOUSAI_TSUNAMI_SEV = {"52": 5, "53": 5, "51": 3, "62": 2, "71": 1, "72": 1, "73": 1}

BOUSAI_TSUNAMI_GRADE_EN = {5: "Major Tsunami Warning", 3: "Tsunami Warning", 2: "Tsunami Advisory", 1: "Tsunami Forecast"}

# Short grade words for narrow rows, and the one-letter chips used on maps.
BOUSAI_TSUNAMI_GRADE_SHORT = {5: "Major", 3: "Warn", 2: "Adv", 1: "Fcst"}
BOUSAI_TSUNAMI_GRADE_LETTER = {5: "M", 3: "W", 2: "A", 1: "F"}

# First-wave conditions (FirstHeight.Condition) -> short English.
BOUSAI_TSUNAMI_COND_EN = {
    "ただちに津波来襲と予測": "Imminent",
    "津波到達中と推測": "Arriving now",
    "第１波の到達を確認": "Arrived",
    "第1波の到達を確認": "Arrived",
    "早いところでは既に津波到達と推定": "May have arrived",
    "第１波識別不能": "Unclear",
    "第1波識別不能": "Unclear",
}

# Qualitative heights (MaxHeight.Condition) -> short English.
BOUSAI_TSUNAMI_HEIGHT_EN = {
    "巨大": "Huge",
    "高い": "High",
    "観測中": "Observing",
    "推定中": "Estimating",
    "微弱": "Tiny",
    "欠測": "No data",
    "今後最大波到達": "More to come",
}

def bousai_tsunami_title(s):
    """JMA writes some English names in capitals ('IWATE PREF.'); title-case those, keep the rest."""
    s = bousai_quake_tidy(s)
    if s != "" and s == s.upper():
        return s.title()
    return s

def bousai_tsunami_height(h):
    """MaxHeight element -> (metres or None, short English text).

    '3' -> (3.0, '3m'), '<0.2' -> (0.2, '<0.2m'), '10+' -> (10.0, '10m+'); qualitative values
    ('巨大') give (None, 'Huge'); nothing gives (None, '').
    """
    h = h or {}
    raw = str(h.get("TsunamiHeight") or "").strip()
    cond = str(h.get("Condition") or "")
    digits = raw.replace("<", "").replace(">", "").replace("+", "").replace("≧", "").replace("≦", "").strip()
    numeric = digits != ""
    for ch in digits.elems():
        if ch not in "0123456789.":
            numeric = False
    if numeric:
        lead = "<" if "<" in raw else (">" if ">" in raw else "")
        return float(digits), lead + digits + "m" + ("+" if "+" in raw else "")
    return None, BOUSAI_TSUNAMI_HEIGHT_EN.get(cond, "")

def bousai_tsunami_first(first):
    """FirstHeight element -> (arrival time or None, condition text '' or e.g. 'Arriving now')."""
    first = first or {}
    return bousai_parse_time(first.get("ArrivalTime")), BOUSAI_TSUNAMI_COND_EN.get(str(first.get("Condition") or ""), "")

def bousai_tsunami_area_name(area):
    """English name of a forecast region: JMA's table by code, else the report's own enName."""
    area = area or {}
    code = str(area.get("Code") or "")
    return BOUSAI_TSUNAMI_AREA_EN.get(code) or bousai_tsunami_title(area.get("enName")) or str(area.get("Name") or code)

def bousai_tsunami_items(detail):
    """Regions listed in a warning / forecast report (VTSE41 or VTSE51 Forecast section).

    Returns [{code, area_en, kcode, kind_en, sev, arrival, cond, height_m, height_en, stations}];
    regions whose warning was lifted (kind 50 / 60 / 00) are left out.
    """
    out = []
    forecast = (((detail or {}).get("Body") or {}).get("Tsunami") or {}).get("Forecast") or {}
    for it in bousai_quake_as_list(forecast.get("Item")):
        kind = ((it.get("Category") or {}).get("Kind")) or {}
        kcode = str(kind.get("Code") or "")
        sev = BOUSAI_TSUNAMI_SEV.get(kcode)
        if sev == None:
            continue
        area = it.get("Area") or {}
        arrival, cond = bousai_tsunami_first(it.get("FirstHeight"))
        h_m, h_en = bousai_tsunami_height(it.get("MaxHeight"))
        stations = []
        for s in bousai_quake_as_list(it.get("Station")):
            ll = s.get("latlon") or {}
            s_arrival, s_cond = bousai_tsunami_first(s.get("FirstHeight"))
            stations.append({
                "name_en": bousai_tsunami_title(s.get("enName") or s.get("Name")),
                "lat": float(ll["lat"]) if ll.get("lat") != None else None,
                "lon": float(ll["lon"]) if ll.get("lon") != None else None,
                "high_tide": bousai_parse_time(s.get("HighTideDateTime")),
                "arrival": s_arrival,
                "cond": s_cond,
            })
        out.append({
            "code": str(area.get("Code") or ""),
            "area_en": bousai_tsunami_area_name(area),
            "kcode": kcode,
            "kind_en": BOUSAI_TSUNAMI_KIND_EN.get(kcode, BOUSAI_TSUNAMI_GRADE_EN[sev]),
            "sev": sev,
            "arrival": arrival,
            "cond": cond,
            "height_m": h_m,
            "height_en": h_en,
            "stations": stations,
        })
    return out

def bousai_tsunami_quakes(detail):
    """Causative earthquakes of a report: [{name_en, lat, lon, depth, mag, time}]."""
    out = []
    for q in bousai_quake_as_list(((detail or {}).get("Body") or {}).get("Earthquake")):
        area = ((q.get("Hypocenter") or {}).get("Area")) or {}
        coord = bousai_quake_parse_cod(area.get("Coordinate"))
        out.append({
            "name_en": bousai_quake_tidy(area.get("enName")) or BOUSAI_EPICENTER_EN.get(str(area.get("Code") or ""), ""),
            "lat": coord[0] if coord else None,
            "lon": coord[1] if coord else None,
            "depth": coord[2] if coord else None,
            "mag": bousai_quake_mag_text(q.get("Magnitude")),
            "time": bousai_parse_time(q.get("OriginTime")),
        })
    return out

def bousai_tsunami_observations(detail):
    """Tide-gauge readings of an observation report (VTSE51 coastal / VTSE52 offshore).

    Returns [{name_en, area_en, lat, lon, height_m, height_en, time, first, rise}] strongest first
    (height_m None for qualitative readings, which sort last); time is when the maximum was
    seen, first the first-wave time, rise 'Rise' / 'Fall' / ''.
    """
    out = []
    obs = (((detail or {}).get("Body") or {}).get("Tsunami") or {}).get("Observation") or {}
    for it in bousai_quake_as_list(obs.get("Item")):
        area_en = bousai_tsunami_area_name(it.get("Area")) if it.get("Area") else ""
        for s in bousai_quake_as_list(it.get("Station")):
            ll = s.get("latlon") or {}
            h = s.get("MaxHeight") or {}
            h_m, h_en = bousai_tsunami_height(h)
            first = s.get("FirstHeight") or {}
            f_time, _ = bousai_tsunami_first(first)
            out.append({
                "name_en": bousai_tsunami_title(s.get("enName") or s.get("Name")),
                "area_en": area_en,
                "lat": float(ll["lat"]) if ll.get("lat") != None else None,
                "lon": float(ll["lon"]) if ll.get("lon") != None else None,
                "height_m": h_m,
                "height_en": h_en,
                "time": bousai_parse_time(h.get("DateTime")),
                "first": f_time,
                "rise": {"押し": "Rise", "引き": "Fall"}.get(str(first.get("Initial") or ""), ""),
            })
    return sorted(out, key = lambda o: -(o["height_m"] if o["height_m"] != None else -1.0))

def bousai_tsunami_state(now = None):
    """The tsunami situation right now, or None when the JMA feed cannot be read.

    Returns a dict:
      active (bool): a warning, advisory or forecast is in effect;
      sev (int): highest severity in effect (0 when none);
      issued: time of the newest warning report (None if the list is empty);
      items: regions in effect, strongest first (see bousai_tsunami_items), after the
        in-effect rule described in the module docstring;
      valid_until: ValidDateTime of the report when it is a forecast, else None;
      quakes: causative earthquakes (bousai_tsunami_quakes);
      last: {title_en, quake_en, mag, time} of the newest warning report, even when expired;
      stations: regions with tide-gauge arrival / high tide times (arrival report, if in effect);
      observed, offshore: tide-gauge readings (bousai_tsunami_observations) of the coastal and
        offshore observation reports, newest report each; info_time: time of the newest of them.
    """
    now = now or bousai_now()
    listing = bousai_get_json(BOUSAI_TSUNAMI_LIST, ttl = 30)
    if type(listing) != "list":
        return None
    clear = bousai_get_json(BOUSAI_TSUNAMI_CLEAR, ttl = 30) or {}
    clear_w = bousai_parse_time(clear.get("w"))
    clear_f = bousai_parse_time(clear.get("f"))

    state = {
        "now": now,
        "active": False,
        "sev": 0,
        "issued": None,
        "items": [],
        "valid_until": None,
        "quakes": [],
        "last": None,
        "stations": [],
        "observed": [],
        "offshore": [],
        "info_time": None,
    }
    warn = None
    info = {}
    for e in listing:
        if "_K" in str(e.get("ift") or ""):
            continue
        kind = BOUSAI_TSUNAMI_INFO.get(e.get("ttl") or "")
        if kind == None:
            if warn == None:
                warn = e
        elif kind not in info:
            info[kind] = e

    if warn != None:
        rdt = bousai_parse_time(warn.get("rdt"))
        state["issued"] = rdt
        state["last"] = {
            "title_en": bousai_quake_tidy(warn.get("en_ttl")),
            "quake_en": bousai_quake_tidy(warn.get("en_anm")),
            "mag": bousai_quake_mag_text(warn.get("mag")),
            "time": bousai_parse_time(warn.get("at")),
        }
        recent = rdt != None and (now - rdt).hours < BOUSAI_TSUNAMI_MAX_HOURS
        if recent and "取消" not in str(warn.get("ift") or "") and warn.get("json"):
            detail = bousai_get_json(BOUSAI_TSUNAMI_DATA + warn["json"], ttl = 86400)
            fresh = clear_w == None or rdt > clear_w
            valid = bousai_parse_time(((detail or {}).get("Head") or {}).get("ValidDateTime"))
            kept = []
            for it in bousai_tsunami_items(detail):
                if it["sev"] >= 2 and fresh:
                    kept.append(it)
                elif it["sev"] == 1 and ((valid != None and now < valid) or (valid == None and fresh)):
                    kept.append(it)
            state["items"] = sorted(kept, key = lambda it: (-it["sev"], it["arrival"].unix if it["arrival"] else 0, it["area_en"]))
            state["quakes"] = bousai_tsunami_quakes(detail)
            if len(kept) > 0:
                state["active"] = True
                state["sev"] = state["items"][0]["sev"]
                if state["sev"] == 1:
                    state["valid_until"] = valid

    for kind, e in info.items():
        rdt = bousai_parse_time(e.get("rdt"))
        if rdt == None or "取消" in str(e.get("ift") or "") or not e.get("json"):
            continue
        if (now - rdt).hours >= BOUSAI_TSUNAMI_MAX_HOURS or (clear_f != None and rdt <= clear_f):
            continue
        detail = bousai_get_json(BOUSAI_TSUNAMI_DATA + e["json"], ttl = 86400)
        if detail == None:
            continue
        if state["info_time"] == None or rdt > state["info_time"]:
            state["info_time"] = rdt
        if kind == "arrival":
            state["stations"] = [it for it in bousai_tsunami_items(detail) if len(it["stations"]) > 0]
        elif kind == "observed":
            state["observed"] = bousai_tsunami_observations(detail)
        else:
            state["offshore"] = bousai_tsunami_observations(detail)
    return state

def bousai_tsunami_coast():
    """JMA tsunami forecast-region coastlines: {region code: [[[lon, lat], ...], ...]}, or None."""
    geo = bousai_get_json(BOUSAI_TSUNAMI_COAST, ttl = 7 * 86400)
    if type(geo) != "dict":
        return None
    out = {}
    for f in geo.get("features") or []:
        code = str((f.get("properties") or {}).get("code") or "")
        g = f.get("geometry") or {}
        lines = g.get("coordinates") or []
        if g.get("type") == "LineString":
            lines = [lines]
        out[code] = lines
    return out

def bousai_tsunami_distances(coast, lat, lon):
    """{region code: km} from lat/lon to the nearest coastline vertex of every forecast region."""
    k = math.cos(math.radians(lat))
    out = {}
    for code, lines in (coast or {}).items():
        best_d = 1.0e9
        best_pt = None
        for line in lines:
            for p in line:
                dx = (p[0] - lon) * k
                dy = p[1] - lat
                d = dx * dx + dy * dy
                if d < best_d:
                    best_d = d
                    best_pt = p
        if best_pt != None:
            out[code] = bousai_distance_km(lat, lon, best_pt[1], best_pt[0])
    return out

def bousai_tsunami_nearest(distances):
    """(region code, km) of the nearest forecast region in a bousai_tsunami_distances() result."""
    best = None
    for code, km in distances.items():
        if best == None or km < distances[best]:
            best = code
    if best == None:
        return None, None
    return best, distances[best]

def bousai_tsunami_arrival_text(item, tz = BOUSAI_JST):
    """'16:40', 'Arriving now', 'Imminent'... for a region / station (arrival time in tz), '' when unknown."""
    if item.get("arrival") != None:
        return bousai_hhmm(item["arrival"], tz)
    return item.get("cond") or ""

def bousai_tsunami_current():
    """Current tsunami warnings, advisories and forecasts for other apps (Home panel, Timeline).

    Returns None when the JMA feed is unavailable, else
    {active (bool), issued (time of the newest warning report, or None), sev (highest severity in
    effect, 0 when none; 5 major warning, 3 warning, 2 advisory, 1 forecast), items: [{area_en,
    kind_en, sev, arrival_en, height_en}]} with the strongest regions first. arrival_en is the
    expected first-wave time as 'HH:MM' in JST, or 'Arriving now' / 'Imminent' / 'Arrived'
    (''); height_en is e.g. '3m', '<0.2m', 'Huge' ('' if not given).
    """
    state = bousai_tsunami_state()
    if state == None:
        return None
    items = []
    for it in state["items"]:
        items.append({
            "area_en": it["area_en"],
            "kind_en": it["kind_en"],
            "sev": it["sev"],
            "arrival_en": bousai_tsunami_arrival_text(it),
            "height_en": it["height_en"],
        })
    return {"active": state["active"], "issued": state["issued"], "sev": state["sev"], "items": items}
