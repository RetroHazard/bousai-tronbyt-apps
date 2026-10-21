"""Earthquake information for the Bousai suite.

Merges the JMA earthquake list (Seismic Intensity Flash Reports, Epicenter
Information, Detailed Area Reports) into one record per event, resolves the
intensity felt at the configured location, reads the per-event tsunami
comment, finds JMA estimated-intensity maps, and reports the Nankai Trough /
Hokkaido-Sanriku special information.  Data only: nothing here draws widgets.

Exports for other apps: bousai_quake_recent(), bousai_quake_special().
"""

# bousai: requires core data

load("render.star", "canvas", "render")

BOUSAI_QUAKE_LIST = "https://www.jma.go.jp/bosai/quake/data/list.json"
BOUSAI_QUAKE_DATA = "https://www.jma.go.jp/bosai/quake/data/"
BOUSAI_QUAKE_EST_LIST = "https://www.jma.go.jp/bosai/estimated_intensity_map/data/list.json"
BOUSAI_QUAKE_EST_DATA = "https://www.jma.go.jp/bosai/estimated_intensity_map/data/"
BOUSAI_QUAKE_MULTI = "https://www.data.jma.go.jp/multi/data/"

# list.json `ttl` (report title) -> report kind. Other titles (Nankai Trough commentary...) are ignored.
BOUSAI_QUAKE_KINDS = {
    "震度速報": "flash",
    "震源に関する情報": "epicenter",
    "震源・震度情報": "detail",
    "震源・震度に関する情報": "detail",
    "遠地地震に関する情報": "distant",
}

BOUSAI_QUAKE_KIND_EN = {
    "flash": "Flash",
    "epicenter": "Epicenter",
    "detail": "Detailed",
    "distant": "Overseas",
}

# Fixed tsunami phrases in the report's ForecastComment (JMA code table) -> short English.
BOUSAI_QUAKE_TSUNAMI_SHORT = {
    "0211": "Tsunami warning/advisory in effect",
    "0212": "Slight sea-level change, no damage expected",
    "0213": "Sea-level changes may continue: take care at the shore",
    "0214": "Sea-level changes may continue: take care when fishing",
    "0215": "No tsunami risk",
    "0216": "Tsunami possible if the epicenter is under the sea",
    "0217": "Check upcoming reports",
    "0221": "Ocean-wide Pacific tsunami possible",
    "0222": "Regional Pacific tsunami possible",
    "0226": "Local tsunami possible near epicenter",
    "0230": "No tsunami risk to Japan",
}

# Nankai Trough extra information (VYSE50) code -> [kind, severity, default display hours].
# Display hours mirror other/temporary_info_config.json (JMA's own web display rule).
BOUSAI_QUAKE_NANKAI = {
    "111": ["Under Analysis", 2, 24],
    "112": ["Under Analysis", 2, 24],
    "113": ["Under Analysis", 2, 24],
    "120": ["Megathrust Earthquake Alert", 4, 336],
    "130": ["Megathrust Earthquake Attention", 3, 168],
}
BOUSAI_QUAKE_NANKAI_CONFIG = {
    "111": "underAnalysisTimeForJnantoraringi",
    "112": "underAnalysisTimeForJnantoraringi",
    "113": "underAnalysisTimeForJnantoraringi",
    "120": "mgathrustEarthquakeAlertTimeForJnantoraringi",
    "130": "megathrustEarthquakeAttentionTimeForJnantoraringi",
}

def bousai_quake_as_list(x):
    """JMA's XML-to-JSON conversion gives a bare object when there is one child; always return a list."""
    if x == None:
        return []
    if type(x) == "list":
        return x
    return [x]

def bousai_quake_tidy(s):
    """Collapse the double spaces JMA leaves in some English names."""
    return " ".join(str(s or "").split())

def bousai_quake_parse_cod(cod):
    """Parse a JMA hypocenter coordinate such as '+35.2+139.0-10000/'.

    Returns (lat, lon, depth_km) or None. depth_km is None when the report has no
    depth (overseas events); 0.0 means 'very shallow'.
    """
    s = str(cod or "").strip().rstrip("/")
    if s == "":
        return None
    for ch in s.elems():
        if ch not in "+-.0123456789":
            return None
    signs = [i for i in range(len(s)) if s[i] == "+" or s[i] == "-"]
    if len(signs) < 2 or signs[0] != 0:
        return None
    lat = float(s[signs[0]:signs[1]])
    end = signs[2] if len(signs) > 2 else len(s)
    lon = float(s[signs[1]:end])
    depth = None
    if len(signs) > 2:
        depth = abs(float(s[signs[2]:])) / 1000.0
    return (lat, lon, depth)

def bousai_quake_mag_text(mag):
    """Magnitude as text ('7.6'). 'M8 or larger' (not yet determined) becomes '8+'; unknown becomes ''."""
    s = str(mag or "").strip()
    if s == "":
        return ""
    numeric = True
    for ch in s.elems():
        if ch not in "0123456789.":
            numeric = False
    if numeric:
        return s
    if "超" in s:
        return "8+"
    return ""

def bousai_quake_depth_text(depth_km, long = False):
    """'10km'; very shallow quakes read 'Very shallow' (long) or '0km'; unknown depth is ''."""
    if depth_km == None:
        return ""
    if depth_km < 1:
        return "Very shallow" if long else "0km"
    return "%dkm" % int(depth_km + 0.5)

def bousai_quake_merge(eid, entries):
    """Build one event from its list.json reports (newest first). None when the newest report cancels it."""
    entries = sorted(entries, key = lambda x: str(x[1].get("ctt") or ""), reverse = True)
    newest_kind, newest = entries[0]
    if "取消" in str(newest.get("ift") or ""):
        return None

    hypo = None
    max_int = None
    areas = []
    for _, e in entries:
        if hypo == None and (e.get("cod") or e.get("acd")):
            hypo = e
        if max_int == None and e.get("maxi"):
            max_int = bousai_intensity_norm(e.get("maxi"))
        if len(areas) == 0 and e.get("int"):
            areas = e.get("int")
    src = hypo or newest

    coord = bousai_quake_parse_cod(src.get("cod"))
    acd = str(src.get("acd") or "")
    epi = bousai_quake_tidy(src.get("en_anm")) or BOUSAI_EPICENTER_EN.get(acd) or bousai_quake_tidy(src.get("anm")) or "Epicenter pending"
    origin = bousai_parse_time(src.get("at") or newest.get("at"))
    reported = bousai_parse_time(newest.get("rdt")) or origin
    if origin == None:
        return None
    return {
        "id": eid,
        "kind": newest_kind,
        "kind_en": BOUSAI_QUAKE_KIND_EN[newest_kind],
        "time": origin,
        "reported": reported,
        "title_en": bousai_quake_tidy(newest.get("en_ttl")) or BOUSAI_QUAKE_KIND_EN[newest_kind],
        "epi_en": epi,
        "acd": acd,
        "lat": coord[0] if coord else None,
        "lon": coord[1] if coord else None,
        "depth": coord[2] if coord else None,
        "mag": bousai_quake_mag_text(src.get("mag")),
        "max_int": max_int,
        "areas": areas,
        "json": str(newest.get("json") or ""),
    }

def bousai_quake_events(feed = None):
    """All earthquake events in the JMA list (about a month), newest origin time first.

    Reports of one event (flash, epicenter, detailed, corrections) are merged. Drills and
    cancelled events are dropped. Returns None when the feed cannot be read.
    """
    raw = feed
    if raw == None:
        raw = bousai_get_json(BOUSAI_QUAKE_LIST, ttl = 30)
    if type(raw) != "list":
        return None
    groups = {}
    order = []
    for e in raw:
        kind = BOUSAI_QUAKE_KINDS.get(e.get("ttl") or "")
        if kind == None or "_K" in str(e.get("ift") or ""):
            continue
        eid = str(e.get("eid") or "")
        if eid == "":
            continue
        if eid not in groups:
            groups[eid] = []
            order.append(eid)
        groups[eid].append((kind, e))
    out = []
    for eid in order:
        ev = bousai_quake_merge(eid, groups[eid])
        if ev != None:
            out.append(ev)
    return sorted(out, key = lambda ev: -ev["time"].unix)

def bousai_quake_filter(events, min_int = "1", overseas = False, now = None):
    """Events felt at min_int or stronger ('1'..'7', '5-', '5+'...). Overseas events only when asked.

    An epicenter-only report whose intensities are still pending (under 10 minutes old) is kept
    so the display follows the flash -> epicenter -> detailed progression.
    """
    min_rank = max(1, bousai_intensity_rank(bousai_intensity_norm(min_int) or "1"))
    now = now or bousai_now()
    out = []
    for ev in events:
        if ev["kind"] == "distant":
            if overseas:
                out.append(ev)
            continue
        rank = bousai_intensity_rank(ev["max_int"])
        if rank >= min_rank:
            out.append(ev)
        elif rank < 0 and ev["kind"] == "epicenter" and (now - ev["reported"]).minutes < 10:
            out.append(ev)
    return out

def bousai_quake_detail(event):
    """Detail JSON of the event's newest report (comments, observation points). None if unavailable."""
    if not event.get("json"):
        return None
    return bousai_get_json(BOUSAI_QUAKE_DATA + event["json"], ttl = 86400)

def bousai_quake_tsunami_text(detail):
    """Short English tsunami comment of a report ('No tsunami risk'), or None."""
    comments = ((detail or {}).get("Body") or {}).get("Comments") or {}
    fc = comments.get("ForecastComment")
    if type(fc) != "dict":
        return None
    codes = str(fc.get("Code") or "").split()
    lines = [bousai_quake_tidy(l) for l in str(fc.get("enText") or "").split("\n") if bousai_quake_tidy(l)]
    parts = []
    for i in range(len(lines)):
        code = codes[i] if len(codes) == len(lines) else ""
        if code == "0245":
            continue
        parts.append(BOUSAI_QUAKE_TSUNAMI_SHORT.get(code) or lines[i])
    if len(parts) == 0:
        return None
    return "; ".join(parts)

def bousai_quake_stations(detail):
    """Intensity observation points of a detailed report: [(lat, lon, label)], strongest first."""
    out = []
    obs = (((detail or {}).get("Body") or {}).get("Intensity") or {}).get("Observation") or {}
    for p in bousai_quake_as_list(obs.get("Pref")):
        for a in bousai_quake_as_list(p.get("Area")):
            for c in bousai_quake_as_list(a.get("City")):
                for s in bousai_quake_as_list(c.get("IntensityStation")):
                    ll = s.get("latlon") or {}
                    label = bousai_intensity_norm(s.get("Int"))
                    if label == None or ll.get("lat") == None or ll.get("lon") == None:
                        continue
                    out.append((float(ll["lat"]), float(ll["lon"]), label))
    return sorted(out, key = lambda s: -bousai_intensity_rank(s[2]))

def bousai_quake_place(config):
    """The configured place in quake-report terms, or None outside Japan / when it cannot be resolved.

    Returns {codes: [7-digit city codes], pref: 2-digit prefecture, wards: None or (low, high)}.
    Reports list the wards of designated cities (Yokohama, Osaka...) individually while JMA's
    forecast area is the whole city (code like 2710000) or a part of it (Yokohama 1410011 / 1410012),
    so for those cities `wards` bounds the ward codes between the city's own code and the next
    municipality's code (designated cities are municipality numbers 100, 130, 140 and 150).
    """
    area = bousai_area(config)
    if area == None:
        return None
    code = area["class20"]
    wards = None
    if code[2:5] in ["100", "130", "140", "150"]:
        upper = "9999999"
        for k in sorted((bousai_area_table() or {}).get("class20s") or {}):
            if k > code and k[:5] != code[:5]:
                upper = k
                break
        wards = (code[:5] + "00", upper)
    return {"codes": [code], "pref": area["pref"], "wards": wards}

def bousai_quake_local(event, place):
    """Intensity felt at `place` (from bousai_quake_place): {city, wards, pref}.

    city is the municipality's intensity label, or the strongest of the city's wards when `wards`
    is True (designated cities); pref is the prefecture's maximum. None where not reported.
    """
    city = None
    ward_max = None
    pref_label = None
    if place == None:
        return {"city": None, "wards": False, "pref": None}
    for p in event.get("areas") or []:
        if p.get("code") == place["pref"]:
            pref_label = bousai_intensity_norm(p.get("maxi"))
        for c in p.get("city") or []:
            code = str(c.get("code") or "")
            if code in place["codes"]:
                city = bousai_intensity_norm(c.get("maxi"))
            elif place["wards"] != None and code > place["wards"][0] and code < place["wards"][1]:
                label = bousai_intensity_norm(c.get("maxi"))
                if bousai_intensity_rank(label) > bousai_intensity_rank(ward_max):
                    ward_max = label
    if city == None and ward_max != None:
        return {"city": ward_max, "wards": True, "pref": pref_label}
    return {"city": city, "wards": False, "pref": pref_label}

def bousai_quake_places(event, table = None):
    """Strongest-shaking places as [(English name, intensity label)], strongest first.

    Cities when the report lists them (names from JMA area.json), prefectures otherwise.
    """
    names = (table or {}).get("class20s") or {}
    found = []
    for p in event.get("areas") or []:
        pref_name = BOUSAI_PREF_EN.get(str(p.get("code") or ""), "")
        cities = p.get("city") or []
        for c in cities:
            label = bousai_intensity_norm(c.get("maxi"))
            name = (names.get(c.get("code")) or {}).get("enName") or pref_name
            if label != None and name:
                found.append((name, label))
        if len(cities) == 0:
            label = bousai_intensity_norm(p.get("maxi"))
            if label != None and pref_name:
                found.append((pref_name, label))
    return sorted(found, key = lambda f: -bousai_intensity_rank(f[1]))

def bousai_quake_estimate(event):
    """JMA estimated seismic intensity distribution map for the event, or None.

    Only strong events have one. Returns {dir, meshes, bounds, comment}. Each mesh is a PNG
    '<dir>/<mesh>.png' (800x800, transparent background) covering 1 degree of longitude by 40
    minutes of latitude: see bousai_quake_mesh_bounds().
    """
    prefix = event["time"].in_location(BOUSAI_JST).format("200601021504")
    est = bousai_get_json(BOUSAI_QUAKE_EST_LIST, ttl = 300)
    if type(est) != "list":
        return None
    for e in est:
        url = str(e.get("url") or "")
        if url.startswith(prefix):
            return {
                "dir": BOUSAI_QUAKE_EST_DATA + url + "/",
                "meshes": [str(m) for m in e.get("mesh_num") or []],
                "bounds": e.get("bounds"),
                "comment": e.get("comment") or "",
            }
    return None

def bousai_quake_mesh_bounds(mesh):
    """(south, west, north, east) of a first-order mesh code such as '5339'."""
    south = int(mesh[0:2]) / 1.5
    west = int(mesh[2:4]) + 100.0
    return (south, west, south + 40.0 / 60.0, west + 1.0)

def bousai_quake_recent(config, limit = 5, min_int = "1"):
    """Most recent earthquakes felt at min_int or stronger, newest first.

    Returns a list of dicts: event_id (str), time (origin, Pixlet time), reported (time of the
    newest report), title_en, epicenter_en, lat, lon (floats, None if unknown), depth_km (float,
    None if unknown, 0.0 = very shallow), mag (str like '4.2', '' if unknown), max_int
    (label '1'..'7', '5-', '5+', '6-', '6+'; '' while pending), local_int (label felt in the
    configured municipality, None when not reported) and tsunami_en (JMA tsunami comment,
    None if absent). Returns [] when the JMA feed is unavailable.
    """
    events = bousai_quake_events()
    if events == None:
        return []
    place = bousai_quake_place(config)
    out = []
    for ev in bousai_quake_filter(events, min_int)[:limit]:
        local = bousai_quake_local(ev, place)
        out.append({
            "event_id": ev["id"],
            "time": ev["time"],
            "reported": ev["reported"],
            "title_en": ev["title_en"],
            "epicenter_en": ev["epi_en"],
            "lat": ev["lat"],
            "lon": ev["lon"],
            "depth_km": ev["depth"],
            "mag": ev["mag"],
            "max_int": ev["max_int"] or "",
            "local_int": local["city"],
            "tsunami_en": bousai_quake_tsunami_text(bousai_quake_detail(ev)),
        })
    return out

def bousai_quake_special():
    """Nankai Trough Earthquake Extra Information and Hokkaido/Sanriku Subsequent Earthquake Advisory in effect.

    Uses JMA's multilingual VYSE50 / VYSE60 files and the same display rule as JMA's own site:
    the report is ANNOUNCED/UPDATED and not older than the configured display period
    (Under Analysis 24 h, Attention 7 days, Alert 14 days, Hokkaido/Sanriku 7 days; 'Analysis
    Complete' is never shown). Returns a list of {title_en, kind_en, issued (time), sev}; sev is
    2 under analysis, 3 attention / subsequent-earthquake advisory, 4 alert. [] when none or unreadable.
    """
    out = []
    now = bousai_now()
    cfg = None
    for name in ["VYSE50", "VYSE60"]:
        j = bousai_get_json(BOUSAI_QUAKE_MULTI + name + "/en.json", ttl = 120)
        if type(j) != "dict" or j.get("infoType") not in ["ANNOUNCED", "UPDATED"]:
            continue
        issued = bousai_parse_time(j.get("reportDateTime"))
        if issued == None:
            continue
        if name == "VYSE50":
            code = str((j.get("earthquakeInfo") or {}).get("code") or "")
            if code not in BOUSAI_QUAKE_NANKAI:
                continue
            kind, sev, hours = BOUSAI_QUAKE_NANKAI[code]
            cfg_key = BOUSAI_QUAKE_NANKAI_CONFIG[code]
            title = "Nankai Trough Earthquake Extra Information"
        else:
            kind, sev, hours = "Subsequent Earthquake Advisory", 3, 168
            cfg_key = "timeForJkouhatsu"
            title = "Off the Coast of Hokkaido and Sanriku Subsequent Earthquake Advisory"
        age_h = (now - issued).hours
        if age_h > 336:
            continue
        if cfg == None:
            cfg = bousai_get_json(BOUSAI_QUAKE_MULTI + "other/temporary_info_config.json", ttl = 86400) or {}
        if age_h > cfg.get(cfg_key, hours):
            continue
        out.append({"title_en": title, "kind_en": kind, "issued": issued, "sev": sev})
    return out

# ---------------------------------------------------------------------------
# Layout helpers shared by the quake and tsunami apps (not part of the data exports).
# A row is (height, builder); builder(frames) makes the widget once the page count, and so each
# page's share of the dwell time for scrolling text, is known.

def bousai_quake_wrap(ui, text, width, max_lines):
    """Greedy word wrap of text to width pixels in the UI font; extra lines are joined onto the last."""
    lines = []
    cur = ""
    for word in text.split(" "):
        trial = cur + " " + word if cur else word
        if cur == "" or bousai_text_width(ui, trial) <= width:
            cur = trial
        else:
            lines.append(cur)
            cur = word
    if cur:
        lines.append(cur)
    if len(lines) > max_lines:
        lines = lines[:max_lines - 1] + [" ".join(lines[max_lines - 1:])]
    return lines

def bousai_quake_name_lines(ui, text, max_lines = None):
    """A place name wrapped over up to two lines (one at the largest text size); long JMA phrases
    are abbreviated ('Prefecture' -> 'Pref.') before the last line would have to scroll."""
    max_lines = max_lines or (1 if ui["size"] == "xlarge" else 2)
    width = canvas.width() - 1
    lines = bousai_quake_wrap(ui, text, width, max_lines)
    full_n = len(bousai_quake_wrap(ui, text, width, 9))
    if full_n > max_lines or max([bousai_text_width(ui, l) for l in lines]) > width:
        short = text
        for a, b in [(" Prefecture", " Pref."), ("Adjacent Sea of ", "Sea of "), ("Off the Coast of ", "Off "), ("Off the ", "Off ")]:
            short = short.replace(a, b)
        if len(bousai_quake_wrap(ui, short, width, 9)) <= full_n:
            lines = bousai_quake_wrap(ui, short, width, max_lines)
    return lines

def bousai_quake_pack(rows, head_first, head_rest):
    """Greedy pagination of (height, builder) rows. Heads are (height, builder) or None; head_rest repeats on later pages."""
    pages = []
    cur = []
    used = 0
    head = head_first
    avail = canvas.height() - (head[0] if head else 0)
    for r in rows:
        if used + r[0] > avail and len(cur) > 0:
            pages.append({"head": head, "rows": cur})
            cur = []
            used = 0
            head = head_rest
            avail = canvas.height() - (head[0] if head else 0)
        cur.append(r)
        used += r[0]
    if len(cur) > 0:
        pages.append({"head": head, "rows": cur})
    return pages

def bousai_quake_page(page, frames):
    """One page: a {'full': builder} page, or a head over rows from bousai_quake_pack."""
    if "full" in page:
        return page["full"](frames)
    kids = []
    if page["head"]:
        kids.append(page["head"][1](frames))
    for h, build in page["rows"]:
        kids.append(render.Box(width = canvas.width(), height = h, child = build(frames)))
    return render.Box(width = canvas.width(), height = canvas.height(), child = render.Column(expanded = True, main_align = "start", cross_align = "start", children = kids))

def bousai_quake_render(pages):
    """Pages share the dwell time (at least 2.5 s each); a single page uses all of it."""
    n = len(pages)
    if n == 1:
        return bousai_quake_page(pages[0], bousai_budget_frames())
    frames = bousai_hold_frames(n)
    return render.Sequence(children = [bousai_hold(bousai_quake_page(p, frames), frames) for p in pages])
