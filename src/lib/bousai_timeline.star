"""Timeline domain library for the Bousai suite.

Builds one list of events of the last 24-72 hours (newest first) from official sources only.
Data only: nothing here draws widgets.

Sources and the time they cover (verified 2026-10-21):
  * JMA earthquake list quake/data/list.json (about 30 days)            -> quakes (via bousai_quake_events).
  * JMA tsunami list tsunami/data/list.json (the last reports)          -> tsunami warning / advisory / forecast, lifts.
  * P2PQuake history, code 556 (optional)                               -> EEW warnings and cancellations.
  * JMA XML long feed extra_l.xml (7 days, ~4700 entries, 2.8 MB) holds, as immutable linked XML documents:
      - warning documents VPWW55/56/58/59/61 ("気象警報・注意報（Ｒ０６）"), one per kind group and office, whose Status
        field (発表 issued, 継続 continued, 解除 lifted, 警報から注意報 lowered) gives issue / lift events for the
        user's municipality (class20, else class10)                      -> weather warnings and landslide alerts.
      - tornado watch (VPHW50/51), record short-term heavy rain (VPOA50 / VPBS50)  -> notices (parsed with the
        bousai_warnings bulletin parser).
      - typhoon analysis and forecast bulletins (VPTW60/61, every 3 hours) -> class changes of each typhoon.
      - prefecture weather information (VPFJ50): the topics in the header of the entry text (no document needed).
  * JMA XML long feed eqvol_l.xml (7 days): eruption observation reports (the feed text itself is enough) and
    volcanic alert level documents (VFVO50)                                -> volcano.
  * flood/data/r8/flood_xml.json (current forecasts only)                  -> river flood notices.

Fetch policy: the 2.8 MB feed is parsed with xpath at every render (about 100 ms); every document it links to never
changes, so its parsed summary is cached for five days. At most BOUSAI_TIMELINE_MAX_FETCH documents are fetched per
render and none once BOUSAI_TIMELINE_FETCH_MS of the render has elapsed, newest first, so history fills in over the
first renders without ever making one render slow.

Export for the app: bousai_timeline_build(config, opts, start) -> {events, notes, area}.
"""

# bousai: requires core data quake warnings

load("cache.star", "cache")
load("encoding/json.star", "json")
load("re.star", "re")
load("time.star", "time")
load("xpath.star", "xpath")

BOUSAI_TIMELINE_EXTRA_URL = "https://www.data.jma.go.jp/developer/xml/feed/extra_l.xml"
BOUSAI_TIMELINE_EQVOL_URL = "https://www.data.jma.go.jp/developer/xml/feed/eqvol_l.xml"
BOUSAI_TIMELINE_TSUNAMI_URL = "https://www.jma.go.jp/bosai/tsunami/data/list.json"
BOUSAI_TIMELINE_P2P_URL = "https://api.p2pquake.net/v2/history?codes=556&limit=30"
BOUSAI_TIMELINE_VOLCANO_LIST = "https://www.jma.go.jp/bosai/volcano/const/volcano_list.json"
BOUSAI_TIMELINE_FLOOD_URL = "https://www.jma.go.jp/bosai/flood/data/r8/flood_xml.json"

BOUSAI_TIMELINE_DOC_KEY = "bousai_timeline:doc:v1:"
BOUSAI_TIMELINE_DOC_TTL = 5 * 86400
BOUSAI_TIMELINE_MAX_FETCH = 12
BOUSAI_TIMELINE_FETCH_MS = 550

# Fresh documents per render: tornado / record rain notices may use at most NOTICE_FETCH; weather warnings leave
# TYPHOON_FETCH and VOLCANO_FETCH fetches for the typhoon and volcano documents (which also use anything left over).
BOUSAI_TIMELINE_NOTICE_FETCH = 3
BOUSAI_TIMELINE_TYPHOON_FETCH = 3
BOUSAI_TIMELINE_VOLCANO_FETCH = 2

# Prefecture weather information bulletins (府県気象情報); the header of the feed text names the topics.
BOUSAI_TIMELINE_INFO_XPATH = "//entry[contains(id,'_VPFJ50_%s.xml')]"

# Warning documents of the new (R06) system: every data type except the legacy VPWW53 / VPWW54 duplicates.
BOUSAI_TIMELINE_WARN_XPATH = "//entry[contains(id,'_%s.xml') and (contains(id,'_VPWW5') or contains(id,'_VPWW6')) and not(contains(id,'_VPWW53_')) and not(contains(id,'_VPWW54_'))]"
BOUSAI_TIMELINE_NOTICE_XPATH = "//entry[title='竜巻注意情報' or title='竜巻注意情報（目撃情報付き）' or title='記録的短時間大雨情報' or title='府県気象防災速報']"
BOUSAI_TIMELINE_TYPHOON_XPATH = "//entry[contains(id,'_VPTW60_') or contains(id,'_VPTW61_')]"
BOUSAI_TIMELINE_VOLCANO_XPATH = "//entry[title='噴火警報・予報' or title='噴火に関する火山観測報' or title='噴火速報']"

# Terms follow the bousai_warnings library so every Bousai app names a warning the same way.
BOUSAI_TIMELINE_ELEMENTS = {
    "rain": ["Heavy Rain", "Heavy Rain"],
    "landslide": ["Landslide", "Landslide"],
    "tide": ["Storm Surge", "Storm Surge"],
    "wind": ["Gale", "Storm"],
    "wind_snow": ["Gale and Snow", "Snowstorm"],
    "snow": ["Heavy Snow", "Heavy Snow"],
    "wave": ["High Wave", "High Wave"],
    "thunder": ["Thunderstorm", "Thunderstorm"],
    "snow_melting": ["Snow Melting", "Snow Melting"],
    "fog": ["Dense Fog", "Dense Fog"],
    "dry": ["Dry Air", "Dry Air"],
    "avalanche": ["Avalanche", "Avalanche"],
    "cold": ["Low Temperature", "Low Temperature"],
    "frost": ["Frost", "Frost"],
    "ice_accretion": ["Ice Accretion", "Ice Accretion"],
    "snow_accretion": ["Snow Accretion", "Snow Accretion"],
}

# Elements of the advisories people rarely act on; the "minor advisories" option hides them.
BOUSAI_TIMELINE_MINOR = ["thunder", "fog", "dry", "frost", "cold", "snow_melting", "ice_accretion", "snow_accretion"]

# Shorter English for long JMA epicentre names (quake rows have two short lines).
BOUSAI_TIMELINE_PLACE_SUBS = [
    [" Prefecture", ""],
    [" Region", ""],
    ["Off the northeast Coast of ", "Off NE "],
    ["Off the northwest Coast of ", "Off NW "],
    ["Off the southeast Coast of ", "Off SE "],
    ["Off the southwest Coast of ", "Off SW "],
    ["Off the Coast of ", "Off "],
    ["Adjacent Sea of ", "Near "],
]

# Volcanic alert kind code -> [alert level or 0, severity, badge text].
BOUSAI_TIMELINE_VOLCANO_KINDS = {
    "11": [1, 1, "Lv1"],
    "12": [2, 2, "Lv2"],
    "13": [3, 3, "Lv3"],
    "14": [4, 4, "Lv4"],
    "15": [5, 5, "Lv5"],
    "21": [0, 1, "Calm"],
    "22": [0, 2, "Alert"],
    "23": [0, 3, "Alert"],
    "24": [0, 4, "Alert"],
    "25": [0, 5, "Alert"],
    "35": [0, 1, "Calm"],
    "36": [0, 3, "Alert"],
}

# Eruption observation report 現象 -> English; an explosion makes the row severity 3 instead of 2.
BOUSAI_TIMELINE_ERUPTION_EN = {
    "噴火": "eruption",
    "爆発": "explosion",
    "連続噴火継続": "continuous eruption",
    "連続噴火停止": "eruption stopped",
}

BOUSAI_TIMELINE_TYPHOON_STRENGTH = {"強い": "", "非常に強い": "Very Strong", "猛烈な": "Violent"}

# Topics named in the header of a weather information bulletin -> English. An unlisted topic is left out.
BOUSAI_TIMELINE_TOPICS = {
    "大雨": "Heavy rain",
    "暴風": "Storm",
    "強風": "Strong wind",
    "暴風雪": "Snowstorm",
    "大雪": "Heavy snow",
    "雪": "Snow",
    "高波": "High waves",
    "波浪": "High waves",
    "高潮": "Storm surge",
    "落雷": "Lightning",
    "突風": "Gusts",
    "竜巻": "Tornado",
    "降ひょう": "Hail",
    "濃霧": "Dense fog",
    "洪水": "Flooding",
    "土砂災害": "Landslide",
    "低温": "Low temperature",
    "高温": "High temperature",
    "少雨": "Little rain",
    "長雨": "Prolonged rain",
    "融雪": "Snowmelt",
    "着雪": "Snow accretion",
    "着氷": "Icing",
    "乾燥": "Dry air",
    "低気圧": "Low pressure",
    "梅雨": "Rainy season",
}

# Topics that make a weather information bulletin severity 2 (a typhoon always does).
BOUSAI_TIMELINE_TOPICS_URGENT = ["大雨", "暴風", "暴風雪", "大雪", "高潮", "竜巻", "洪水", "土砂災害"]

# ---------------------------------------------------------------------------
# Plumbing

def bousai_timeline_event(t, cat, sev, chip, ckind, cval, text, tag = "", fold = False):
    """One timeline event.

    t unix seconds; cat the category (warn, notice, info, quake, eew, tsunami, volcano, typhoon); sev 1..5 (the
    ui["sev"] index, also what the minimum-severity filter compares); chip the badge text; ckind how the badge is
    coloured: "sev" (cval is a severity index), "int" (cval is a seismic intensity label) or "off" (neutral: something
    that ended); text the English description; tag an optional short word shown beside the badge, which with fold is
    appended to the text instead when the badge line has no room.
    """
    return {"t": t, "cat": cat, "sev": sev, "chip": chip, "ckind": ckind, "cval": cval, "text": text, "tag": tag, "fold": fold}

def bousai_timeline_fx(start = None):
    """Fetch budget of one render: documents left to fetch and the render time after which none is fetched."""
    return {"start": time.now() if start == None else start, "left": BOUSAI_TIMELINE_MAX_FETCH, "ms": BOUSAI_TIMELINE_FETCH_MS}

def bousai_timeline_budget(fx):
    if fx["left"] <= 0:
        return False
    return (time.now() - fx["start"]).milliseconds < fx["ms"]

def bousai_timeline_sub(fx, cap):
    """A sub-budget of at most `cap` documents; the caller charges what it used (cap minus left) to the parent."""
    return {"start": fx["start"], "left": min(cap, fx["left"]), "ms": fx["ms"]}

def bousai_timeline_fetch(href, key, kind, fx, args = None):
    """Cached summary of an immutable JMA XML document, fetched while the budget allows; None when unavailable.

    kind selects the parser: "warn", "notice", "typhoon" or "volcano".
    """
    cached = cache.get(key)
    if cached:
        return json.decode(cached, default = None)
    if cache.get(key + ":miss") or not bousai_timeline_budget(fx):
        return None
    fx["left"] -= 1
    # Marked before the request: a document that makes the render fail (Starlark cannot catch that) is then
    # skipped for ten minutes instead of failing every render. A cached summary wins over the mark.
    cache.set(key + ":miss", "1", ttl_seconds = 600)
    body = bousai_get_bytes(href, ttl = 3600)
    summary = None
    if body != None:
        if kind == "warn":
            summary = bousai_timeline_parse_warning(body, args[0], args[1])
        elif kind == "typhoon":
            summary = bousai_timeline_parse_typhoon(body)
        elif kind == "volcano":
            summary = bousai_timeline_parse_volcano(body)
        else:
            summary = bousai_warnings_parse_bulletin(body)
    if summary == None:
        return None
    cache.set(key, json.encode(summary), ttl_seconds = BOUSAI_TIMELINE_DOC_TTL)
    return summary

def bousai_timeline_int(v, default = 0):
    """int(v) for digits, else default (feed fields are text)."""
    s = str(v if v != None else "").strip()
    return int(s) if s.isdigit() else default

def bousai_timeline_file(href):
    """File name of a feed document ('20261020225031_0_VPWW55_030000.xml')."""
    return href.split("/")[-1]

def bousai_timeline_entries(doc, path, cut, with_text = False):
    """Feed entries matching an xpath that were updated after `cut`, newest first: [{t, href, file, content}]."""
    out = []
    for n in doc.query_all_nodes(path):
        t = bousai_parse_time(n.query("updated"))
        href = n.query("link/@href") or n.query("id") or ""
        if t == None or t.unix < cut or not href:
            continue
        out.append({
            "t": t.unix,
            "href": href,
            "file": bousai_timeline_file(href),
            "content": (n.query("content") or "") if with_text else "",
        })
    return sorted(out, key = lambda e: -e["t"])

def bousai_timeline_short_place(name):
    for pair in BOUSAI_TIMELINE_PLACE_SUBS:
        name = name.replace(pair[0], pair[1])
    return name.strip()

def bousai_timeline_sev_of_int(label):
    """Severity index of a seismic intensity label: Int 1-2 -> 1, 3 -> 2, 4 -> 3, 5- / 5+ -> 4, 6- and up -> 5."""
    rank = bousai_intensity_rank(label or "")
    if rank <= 2:
        return 1
    if rank == 3:
        return 2
    if rank == 4:
        return 3
    if rank <= 6:
        return 4
    return 5

# ---------------------------------------------------------------------------
# Earthquakes (JMA list) and EEW warnings (P2PQuake)

def bousai_timeline_quakes(now, cut, min_int):
    """Earthquake events at min_int or stronger; None when the JMA list is unavailable."""
    feed = bousai_quake_events()
    if feed == None:
        return None
    out = []
    for ev in bousai_quake_filter(feed, min_int, False, now):
        if ev["time"].unix < cut:
            continue
        label = ev["max_int"]
        mag = ("M" + ev["mag"] + " ") if ev["mag"] else ""
        text = mag + bousai_timeline_short_place(ev["epi_en"])
        if label:
            out.append(bousai_timeline_event(ev["time"].unix, "quake", bousai_timeline_sev_of_int(label), "Int " + label, "int", label, text))
        else:
            out.append(bousai_timeline_event(ev["time"].unix, "quake", 1, "Int ?", "off", 0, text))
    return out

def bousai_timeline_latlon(lat, lon):
    return "%s%s %s%s" % (bousai_fixed(abs(lat), 1), "N" if lat >= 0 else "S", bousai_fixed(abs(lon), 1), "E" if lon >= 0 else "W")

def bousai_timeline_eew_events(data, cut):
    """EEW warning events from P2PQuake history entries (code 556).

    One event per warning (time of its first report, epicentre, magnitude, strongest forecast intensity) and one per
    cancellation. Test and training messages are ignored.
    """
    first = {}
    best = {}
    cancels = []
    for e in data:
        if type(e) != "dict" or e.get("test") == True:
            continue
        issue = e.get("issue") or {}
        eid = str(issue.get("eventId") or "")
        t = bousai_parse_time(issue.get("time") or e.get("time"))
        if not eid or t == None:
            continue
        if e.get("cancelled") == True:
            cancels.append([eid, t.unix])
            continue
        top = best.setdefault(eid, {"int": "", "eq": None, "serial": -1})
        for a in e.get("areas") or []:
            x = a.get("scaleTo")
            label = bousai_intensity_norm(str(int(x))) if type(x) == "int" and x > 0 and x < 99 else None
            if label != None and bousai_intensity_rank(label) > bousai_intensity_rank(top["int"]):
                top["int"] = label
        serial = bousai_timeline_int(issue.get("serial"))
        if e.get("earthquake") and serial > top["serial"]:
            top["eq"] = e.get("earthquake")
            top["serial"] = serial
        if eid not in first or t.unix < first[eid]:
            first[eid] = t.unix
    out = []
    for eid, t in first.items():
        if t < cut:
            continue
        top = best[eid]
        hypo = ((top["eq"] or {}).get("hypocenter")) or {}
        mag = hypo.get("magnitude")
        parts = []
        if type(mag) in ["int", "float"] and mag > 0:
            parts.append("M" + bousai_fixed(mag, 1))
        lat, lon = hypo.get("latitude"), hypo.get("longitude")
        if type(lat) in ["int", "float"] and type(lon) in ["int", "float"] and lat > -90 and lon > -180:
            parts.append(bousai_timeline_latlon(lat, lon))
        else:
            parts.append("assumed epicentre")
        sev = 5 if bousai_intensity_rank(top["int"]) >= 7 else 4
        if top["int"]:
            out.append(bousai_timeline_event(t, "eew", sev, "EEW " + top["int"], "int", top["int"], " ".join(parts)))
        else:
            out.append(bousai_timeline_event(t, "eew", sev, "EEW", "sev", sev, " ".join(parts)))
    for c in cancels:
        if c[1] >= cut:
            out.append(bousai_timeline_event(c[1], "eew", 4, "EEW", "off", 0, "Warning cancelled"))
    return out

def bousai_timeline_eew(cut):
    """EEW events of the last hours from the P2PQuake history; None when it is unavailable.

    P2PQuake is a third-party host that has been seen stalling, and a stalled request aborts the whole render, so
    the request goes through bousai_guarded_json: after an attempt that never finished the host is skipped for 300 s.
    """
    data = bousai_guarded_json(BOUSAI_TIMELINE_P2P_URL, ttl = 120, cooldown = 300)
    if type(data) != "list":
        return None
    return bousai_timeline_eew_events(data, cut)

# ---------------------------------------------------------------------------
# Tsunami (JMA list)

def bousai_timeline_tsunami_events(listing, cut):
    """Tsunami events from JMA list.json entries: warning / advisory / forecast reports, lifts and cancellations.

    The grade comes from the Japanese kind names of the report (大津波警報, 津波警報, 津波注意報, 津波予報); a report
    whose kinds are all 解除 (or whose title says 解除) is a lift. Drills (_K) and observation / arrival information
    are skipped.
    """
    out = []
    for e in listing:
        if type(e) != "dict":
            continue
        ift = str(e.get("ift") or "")
        t = bousai_parse_time(e.get("rdt"))
        if "_K" in ift or t == None or t.unix < cut:
            continue
        ttl = str(e.get("ttl") or "")
        kinds = [str(k.get("kind") or "") for k in e.get("kind") or [] if type(k) == "dict"]
        active = " ".join([k for k in kinds if "解除" not in k])
        if "取消" in ift:
            out.append(bousai_timeline_event(t.unix, "tsunami", 1, "Cancel", "off", 0, "Tsunami report"))
            continue
        if "解除" in ttl or (len(kinds) > 0 and active == ""):
            words = ttl + " " + " ".join(kinds)
            if "津波警報" in words:
                out.append(bousai_timeline_event(t.unix, "tsunami", 3, "Lifted", "off", 0, "Tsunami warning"))
            elif "津波注意報" in words:
                out.append(bousai_timeline_event(t.unix, "tsunami", 2, "Lifted", "off", 0, "Tsunami advisory"))
            else:
                out.append(bousai_timeline_event(t.unix, "tsunami", 2, "Lifted", "off", 0, "Tsunami warnings"))
            continue
        words = active + " " + ttl
        if "大津波警報" in words:
            grade, word = 5, "Major"
        elif "津波警報" in words:
            grade, word = 3, "Warning"
        elif "津波注意報" in words:
            grade, word = 2, "Advisory"
        elif "津波予報" in words:
            grade, word = 1, "Forecast"
        else:
            continue
        place = bousai_quake_tidy(e.get("en_anm"))
        mag = bousai_quake_mag_text(e.get("mag"))
        where = ((" M" + mag) if mag else "") + ((" " + bousai_timeline_short_place(place)) if place else "")
        out.append(bousai_timeline_event(t.unix, "tsunami", grade, word, "sev", grade, "Tsunami" + where))
    return out

def bousai_timeline_tsunami(cut):
    """Tsunami events of the last hours from the JMA list; None when it is unavailable."""
    listing = bousai_get_json(BOUSAI_TIMELINE_TSUNAMI_URL, ttl = 60)
    if type(listing) != "list":
        return None
    return bousai_timeline_tsunami_events(listing, cut)

# ---------------------------------------------------------------------------
# Weather warnings (R06 documents of the user's office)

def bousai_timeline_parse_warning(text, class20, class10):
    """Summary of one warning document for an area: {t, s, k} or None when it cannot be parsed.

    t is the report time (unix), s the area level used ("c20", "c10" or "" when the area is not listed), k the area's
    kinds as [[kind code, status], ...] (an area with nothing issued has none).
    """
    doc = xpath.loads(text)
    rep = bousai_parse_time(doc.query("//Head/ReportDateTime"))
    if rep == None:
        return None
    if (doc.query("//Control/Status") or "") in ["訓練", "試験"] or (doc.query("//Head/InfoType") or "") == "取消":
        return {"t": rep.unix, "s": "x", "k": []}
    for scope, kind, code in [["c20", "気象警報・注意報（市町村等）", class20], ["c10", "気象警報・注意報（一次細分区域等）", class10]]:
        if not code:
            continue
        items = doc.query_all_nodes("//Warning[@type='%s']/Item[Area/Code='%s']" % (kind, code))
        if len(items) > 0:
            kinds = []
            for k in items[0].query_all_nodes("Kind"):
                kcode = k.query("Code") or ""
                if kcode:
                    kinds.append([kcode, k.query("Status") or ""])
            return {"t": rep.unix, "s": scope, "k": kinds}
    return {"t": rep.unix, "s": "", "k": []}

def bousai_timeline_prev_level(status, level):
    """Level a lowered warning came from, read from a status such as 警報から注意報 (warning -> advisory)."""
    head = status.split("から")[0]
    if "特別警報" in head:
        return 50
    if "危険警報" in head:
        return 40
    if "警報" in head:
        return 30
    return level + 10

def bousai_timeline_warning_events(summaries, cut, minor = True):
    """Issue / lift / lowering events from warning document summaries; simultaneous ones of a kind group merge.

    With minor False the advisories listed in BOUSAI_TIMELINE_MINOR are left out."""
    groups = {}
    order = []
    for s in summaries:
        if s == None or s["t"] < cut:
            continue
        for k in s["k"]:
            info = BOUSAI_WARN_CODES.get(k[0])
            status = k[1]
            if info == None or (not minor and info[0] in BOUSAI_TIMELINE_MINOR):
                continue
            prev = 0
            if status == "発表":
                verb = "issued"
            elif status == "解除":
                verb = "lifted"
            elif "から" in status:
                verb = "lowered"
                prev = bousai_timeline_prev_level(status, info[1])
            else:
                continue
            gkey = "%d:%s:%d:%d" % (s["t"], verb, info[1], prev)
            if gkey not in groups:
                groups[gkey] = {"t": s["t"], "verb": verb, "level": info[1], "prev": prev, "elements": []}
                order.append(gkey)
            if info[0] not in groups[gkey]["elements"]:
                groups[gkey]["elements"].append(info[0])
    rank = {}
    for i, element in enumerate(BOUSAI_TIMELINE_ELEMENTS.keys()):
        rank[element] = i
    out = []
    for gkey in order:
        g = groups[gkey]
        level = g["level"]
        names = []
        for element in sorted(g["elements"], key = lambda e: rank.get(e, 99)):
            pair = BOUSAI_TIMELINE_ELEMENTS.get(element) or [element.replace("_", " ").title()] * 2
            names.append(pair[0] if level <= 20 else pair[1])
        text = ", ".join(names)
        sev = level // 10
        tag = g["verb"].capitalize()
        if g["verb"] == "issued":
            out.append(bousai_timeline_event(g["t"], "warn", sev, "Lv%d" % sev, "sev", sev, text, tag, True))
        elif g["verb"] == "lowered":
            out.append(bousai_timeline_event(g["t"], "warn", sev, "Lv%d>%d" % (g["prev"] // 10, sev), "sev", sev, text, tag, True))
        else:
            out.append(bousai_timeline_event(g["t"], "warn", sev, "Lv%d" % sev, "off", 0, text, tag, True))
    return out

def bousai_timeline_warning(entries, area, cut, fx, minor = True):
    """Weather warning events of the area for the warning documents in `entries` (newest first)."""
    c20 = area.get("class20") or ""
    c10 = area.get("class10") or ""
    sums = []
    for e in entries:
        key = BOUSAI_TIMELINE_DOC_KEY + "w:" + e["file"] + ":" + c20
        sums.append(bousai_timeline_fetch(e["href"], key, "warn", fx, [c20, c10]))
    return bousai_timeline_warning_events(sums, cut, minor)

# ---------------------------------------------------------------------------
# Tornado watch, record short-term heavy rain, river flood

def bousai_timeline_notice_entries(entries, pref):
    """Tornado / record rain feed entries of one prefecture, newest first: [{t, href, file, kind, code}].

    A tornado watch is published as two documents with the same time (plain, and with eyewitness information);
    only the richer one is kept.
    """
    items = []
    rich = {}
    for e in entries:
        code = e["file"].replace(".xml", "").split("_")[-1]
        if code[:2] != pref:
            continue
        stamp = "%d:%s" % (e["t"], code)
        items.append({"t": e["t"], "href": e["href"], "file": e["file"], "kind": "tornado" if "_VPHW5" in e["file"] else "record", "code": code, "stamp": stamp})
        if "_VPHW51_" in e["file"]:
            rich[stamp] = True
    return [i for i in items if i["kind"] != "tornado" or "_VPHW51_" in i["file"] or i["stamp"] not in rich]

def bousai_timeline_notices(entries, area, table, tz, cut, fx):
    """Tornado watch and record short-term heavy rain events of the area."""
    cancelled = {}
    details = []
    for e in entries:
        d = bousai_timeline_fetch(e["href"], BOUSAI_TIMELINE_DOC_KEY + "n:" + e["file"], "notice", fx)
        if d == None:
            continue
        issued = bousai_parse_time(d["issued"])
        stamp = issued.unix if issued != None else e["t"]
        details.append([e, d, stamp])
        if d["info_type"] == "取消":
            key = e["kind"] + e["code"]
            if stamp > cancelled.get(key, 0):
                cancelled[key] = stamp
    out = []
    for item in details:
        e, d, stamp = item[0], item[1], item[2]
        if d["info_type"] == "取消" or d["status"] in ["訓練", "試験"] or stamp < cut or stamp < cancelled.get(e["kind"] + e["code"], 0):
            continue
        if e["kind"] == "tornado":
            if not bousai_warnings_area_hit(area, d["codes"]):
                continue
            valid = bousai_parse_time(d["valid"]) if d["valid"] else None
            until = " until " + valid.in_location(tz).format("15:04") if valid != None else ""
            seen = bool(d.get("sight_codes")) and bool(bousai_warnings_area_hit(area, d["sight_codes"]))
            text = ("Tornado seen" if seen else "Watch") + until
            out.append(bousai_timeline_event(stamp, "notice", 3, "Tornado", "sev", 3, text))
        else:
            res = bousai_warnings_record_rain(d, area, table)
            if res != None:
                out.append(bousai_timeline_event(stamp, "notice", 4, "Rec.Rain", "sev", 4, res[1]))
    return out

def bousai_timeline_floods(area, cut):
    """River flood notices that are in effect now (the flood feed keeps no history); [] when none."""
    out = []
    for n in bousai_warnings_flood_notices(bousai_get_json(BOUSAI_TIMELINE_FLOOD_URL, ttl = 60), area):
        if n["issued"].unix >= cut:
            out.append(bousai_timeline_event(n["issued"].unix, "notice", n["sev"], "Flood", "sev", n["sev"], n["text_en"]))
    return out

# ---------------------------------------------------------------------------
# Typhoons (analysis and forecast bulletins, every 3 hours)

def bousai_timeline_parse_typhoon(text):
    """Summary of one typhoon bulletin: {t, id, ser, cls, str, num, name}, or None when it cannot be parsed."""
    doc = xpath.loads(text)
    rep = bousai_parse_time(doc.query("//Head/ReportDateTime"))
    if rep == None:
        return None
    if (doc.query("//Control/Status") or "") in ["訓練", "試験"]:
        return {"t": rep.unix, "id": "", "ser": 0, "cls": "", "str": "", "num": "", "name": ""}
    cls = doc.query("//MeteorologicalInfo[1]//*[local-name()='TyphoonClass']") or ""
    abbr = cls.split("(")[-1].replace(")", "").strip() if "(" in cls else cls
    return {
        "t": rep.unix,
        "id": doc.query("//Head/EventID") or "",
        "ser": bousai_timeline_int(doc.query("//Head/Serial")),
        "cls": abbr,
        "str": (doc.query("//MeteorologicalInfo[1]//*[local-name()='IntensityClass']") or "").strip(),
        "num": doc.query("//MeteorologicalInfo[1]//TyphoonNamePart/Number") or "",
        "name": doc.query("//MeteorologicalInfo[1]//TyphoonNamePart/Name") or "",
    }

def bousai_timeline_typhoon_state(s):
    """[rank, label, chip, severity] of a typhoon summary (rank orders strength: TD 1 ... violent 6)."""
    cls = s["cls"]
    if cls == "LOW":
        return [0, "Extratropical Cyclone", "Ex-TC", 1]
    if cls == "TD":
        return [1, "Tropical Depression", "TD", 1]
    if cls == "TS":
        return [2, "Tropical Storm", "TS", 2]
    if cls == "STS":
        return [3, "Severe Tropical Storm", "STS", 3]
    strength = BOUSAI_TIMELINE_TYPHOON_STRENGTH.get(s["str"], "")
    if strength == "Violent":
        return [6, "Violent Typhoon", "Violent", 5]
    if strength == "Very Strong":
        return [5, "Very Strong Typhoon", "V.Strong", 4]
    return [4, "Typhoon", "Typhoon", 4]

def bousai_timeline_typhoon_subject(s):
    """'No.30 Champi' once the system has a typhoon number (tropical storm or stronger), else ''."""
    if not s["num"]:
        return ""
    return ("No." + str(bousai_timeline_int(s["num"]) % 100) + " " + s["name"].title()).strip()

def bousai_timeline_typhoon_event(t, state, text, tag):
    return bousai_timeline_event(t, "typhoon", state[3], state[2], "sev", state[3], text, tag, True)

def bousai_timeline_typhoon_events(sums, cut, now):
    """Class-change events (formed, up, down, ended) of typhoons from bulletin summaries.

    `sums` are the summaries in the feed's newest-first order, None for a bulletin that is not cached. Changes are
    only read between bulletins that follow each other, so a gap never produces a wrongly timed event. A typhoon with
    no change in the window gets one status row (its newest bulletin) while it is still being tracked.
    """
    out = []
    last = {}
    changed = {}
    newest = {}
    for s in reversed(sums):
        if s == None:
            last = {}
            continue
        if not s["id"]:
            continue
        prev = last.get(s["id"])
        last[s["id"]] = s
        newest[s["id"]] = s
        state = bousai_timeline_typhoon_state(s)
        subject = bousai_timeline_typhoon_subject(s)
        if s["t"] < cut:
            continue
        if prev == None:
            if s["ser"] == 1:
                out.append(bousai_timeline_typhoon_event(s["t"], state, subject or state[1], "Formed"))
                changed[s["id"]] = True
            continue
        before = bousai_timeline_typhoon_state(prev)
        if before[1] == state[1]:
            continue
        changed[s["id"]] = True
        if state[0] == 0:
            out.append(bousai_timeline_typhoon_event(s["t"], state, subject or state[1], "Ended"))
        elif before[0] == 1 and subject:
            out.append(bousai_timeline_typhoon_event(s["t"], state, subject, "Formed"))
        elif state[0] > before[0]:
            out.append(bousai_timeline_typhoon_event(s["t"], state, subject or state[1], "Up"))
        else:
            out.append(bousai_timeline_typhoon_event(s["t"], state, subject or state[1], "Down"))
    for tid, s in newest.items():
        if tid in changed or s["cls"] == "LOW" or now.unix - s["t"] > 12 * 3600 or s["t"] < cut:
            continue
        state = bousai_timeline_typhoon_state(s)
        out.append(bousai_timeline_typhoon_event(s["t"], state, bousai_timeline_typhoon_subject(s) or state[1], "Latest"))
    return out

# ---------------------------------------------------------------------------
# Weather information bulletins (府県気象情報), straight from the feed text

def bousai_timeline_topic_en(token):
    """English for one topic of a weather information bulletin header; '' when it is not in the table."""
    token = bousai_warnings_ascii(token.strip())
    typhoon = re.match("台風第(\\d+)号", token)
    if len(typhoon) > 0:
        return "Typhoon No." + typhoon[0][1]
    return BOUSAI_TIMELINE_TOPICS.get(token, "")

def bousai_timeline_info_events(entries, cut):
    """Weather information events of the user's prefecture from feed entries (newest first, with their text).

    The text starts with a header naming the topics, e.g. 【石川県気象解説情報（大雨・落雷・突風）】; the topics are
    shown in English. Bulletins with the same topics less than 12 hours apart (updates of one information) merge.
    """
    groups = []
    for e in entries:
        head = re.match("【[^】（]*気象(?:解説)?情報（([^）]+)）", e["content"])
        if len(head) == 0 or e["t"] < cut:
            continue
        topics = []
        urgent = False
        for token in head[0][1].split("・"):
            english = bousai_timeline_topic_en(token)
            if english and english not in topics:
                topics.append(english)
            urgent = urgent or token.startswith("台風") or token in BOUSAI_TIMELINE_TOPICS_URGENT
        text = ", ".join(topics) or "Weather information"
        merged = False
        for g in groups:
            if g["text"] == text and g["oldest"] - e["t"] <= 12 * 3600:
                g["n"] += 1
                g["oldest"] = e["t"]
                merged = True
                break
        if not merged:
            groups.append({"text": text, "t": e["t"], "oldest": e["t"], "n": 1, "sev": 2 if urgent else 1})
    return [bousai_timeline_event(g["t"], "info", g["sev"], "Info", "sev", g["sev"], g["text"], ("x%d" % g["n"]) if g["n"] > 1 else "") for g in groups]

# ---------------------------------------------------------------------------
# Volcanoes (eqvol_l.xml)

def bousai_timeline_volcano_codes():
    """{Japanese volcano name: code} from JMA volcano_list.json (cached for a week); {} when unavailable."""
    key = "bousai_timeline:volcano_names:v1"
    cached = cache.get(key)
    if cached:
        return json.decode(cached, default = {})
    data = bousai_get_json(BOUSAI_TIMELINE_VOLCANO_LIST, ttl = 86400)
    if type(data) != "list":
        return {}
    names = {}
    for v in data:
        if type(v) == "dict" and v.get("name_jp") and v.get("code"):
            names[v["name_jp"]] = v["code"]
    cache.set(key, json.encode(names), ttl_seconds = 7 * 86400)
    return names

def bousai_timeline_eruption(content, fallback):
    """[Japanese volcano name, event unix, phenomenon] from an eruption observation / flash report text, or None."""
    name = re.match("【火山名[　 ]+(.+?)[　 ]+", content)
    if len(name) == 0:
        name = re.match("火[　 ]+山：(.+)", content)
    if len(name) == 0:
        return None
    when = re.match("日[　 ]+時：(\\d{4})年(\\d{1,2})月(\\d{1,2})日(\\d{1,2})時(\\d{1,2})分", content)
    unix = fallback
    if len(when) > 0:
        w = when[0]
        unix = time.time(year = int(w[1]), month = int(w[2]), day = int(w[3]), hour = int(w[4]), minute = int(w[5]), location = BOUSAI_JST).unix
    what = re.match("現[　 ]+象：(.+)", content)
    return [name[0][1].strip(), unix, what[0][1].strip() if len(what) > 0 else "噴火"]

def bousai_timeline_parse_volcano(text):
    """Summary of a volcanic warning document (VFVO50): {t, items: [[volcano, kind, condition, previous kind]]}."""
    doc = xpath.loads(text)
    rep = bousai_parse_time(doc.query("//Head/ReportDateTime"))
    if rep == None:
        return None
    if (doc.query("//Control/Status") or "") in ["訓練", "試験"] or (doc.query("//Head/InfoType") or "") == "取消":
        return {"t": rep.unix, "items": []}
    items = []
    for it in doc.query_all_nodes("//VolcanoInfo[@type='噴火警報・予報（対象火山）']/Item"):
        items.append([
            it.query("Areas/Area/Code") or "",
            it.query("Kind/Code") or "",
            it.query("Kind/Condition") or "",
            it.query("LastKind/Code") or "",
        ])
    return {"t": rep.unix, "items": items}

def bousai_timeline_volcano_near(code, loc, km, sev):
    """True when a volcano is within km of the location (km 0 = anywhere); urgent levels (Lv4+) always count."""
    row = BOUSAI_VOLCANOES.get(code)
    if row == None:
        return False
    if km <= 0 or sev >= 4 or loc == None:
        return True
    return bousai_distance_km(loc["lat"], loc["lon"], row[1], row[2]) <= km

def bousai_timeline_volcano_level_events(sums, loc, km, cut):
    """Alert level changes from volcanic warning document summaries."""
    out = []
    for s in sums:
        if s == None or s["t"] < cut:
            continue
        for it in s["items"]:
            code, kind, cond, last = it[0], it[1], it[2], it[3]
            info = BOUSAI_TIMELINE_VOLCANO_KINDS.get(kind)
            row = BOUSAI_VOLCANOES.get(code)
            if info == None or row == None or cond == "継続" or not bousai_timeline_volcano_near(code, loc, km, info[1]):
                continue
            before = BOUSAI_TIMELINE_VOLCANO_KINDS.get(last)
            name = row[0]
            if cond in ["引上げ", "引下げ"] and before != None and before[0] and info[0]:
                chip = "Lv%d>%d" % (before[0], info[0])
                out.append(bousai_timeline_event(s["t"], "volcano", info[1], chip, "sev", info[1], name, "Raised" if cond == "引上げ" else "Lowered", True))
            elif cond == "解除":
                out.append(bousai_timeline_event(s["t"], "volcano", info[1], info[2], "off", 0, name, "Lifted", True))
            else:
                out.append(bousai_timeline_event(s["t"], "volcano", info[1], info[2], "sev", info[1], name, "Issued", True))
    return out

def bousai_timeline_volcano_eruptions(reports, loc, km, tz, cut):
    """Eruption observation / flash events: one row per volcano and day (repeated eruptions of one volcano merge)."""
    names = bousai_timeline_volcano_codes()
    seen = {}
    groups = {}
    order = []
    for r in reports:
        got = bousai_timeline_eruption(r["content"], r["t"])
        if got == None or got[1] < cut:
            continue
        code = names.get(got[0])
        row = BOUSAI_VOLCANOES.get(code) if code else None
        flash = r["flash"]
        if row == None or not bousai_timeline_volcano_near(code, loc, km, 4 if flash else 2):
            continue
        dedupe = "%s:%d" % (code, got[1])
        if dedupe in seen:
            continue
        seen[dedupe] = True
        day = time.from_timestamp(got[1]).in_location(tz).format("2006-01-02")
        key = code + ":" + day + (":flash" if flash else "")
        if key not in groups:
            groups[key] = {"code": code, "t": got[1], "n": 0, "boom": False, "what": got[2], "flash": flash}
            order.append(key)
        g = groups[key]
        g["n"] += 1
        g["t"] = max(g["t"], got[1])
        g["boom"] = g["boom"] or BOUSAI_TIMELINE_ERUPTION_EN.get(got[2]) == "explosion"
    out = []
    for key in order:
        g = groups[key]
        name = BOUSAI_VOLCANOES[g["code"]][0]
        sev = 3 if g["boom"] else 2
        if g["flash"]:
            out.append(bousai_timeline_event(g["t"], "volcano", 4, "Flash", "sev", 4, name + " eruption"))
        elif g["n"] == 1:
            out.append(bousai_timeline_event(g["t"], "volcano", sev, "Erupt", "sev", sev, name + " " + BOUSAI_TIMELINE_ERUPTION_EN.get(g["what"], "eruption")))
        else:
            out.append(bousai_timeline_event(g["t"], "volcano", sev, "Erupt", "sev", sev, name + " eruptions", "x%d" % g["n"]))
    return out

# ---------------------------------------------------------------------------
# Everything together

def bousai_timeline_budgeted(fx, cap, work):
    """Run work(sub-budget) with at most `cap` fresh fetches, charge what it used to fx and return its result."""
    sub = bousai_timeline_sub(fx, max(0, cap))
    before = sub["left"]
    result = work(sub)
    fx["left"] -= before - sub["left"]
    return result

def bousai_timeline_build(config, opts, start):
    """All events for the configured place within opts["hours"], newest first.

    opts: {hours, min_sev, quake_int, volcano_km, minor, cats: {warn, notice, info, quake, eew, tsunami, volcano,
    typhoon}}.
    Returns {events, notes, area}: notes are short messages about sources that could not be read (or a location
    outside Japan); area is bousai_area(config) or None.
    """
    now = bousai_now()
    cut = now.unix - opts["hours"] * 3600
    loc = bousai_location(config)
    tz = loc["tz"]
    cats = opts["cats"]
    events = []
    notes = []
    fx = bousai_timeline_fx(start)

    local = cats["warn"] or cats["notice"] or cats["info"]
    area = bousai_area(config) if local else None
    if area == None and local:
        notes.append("No JMA area (outside Japan)")

    # The long feed lists every document; one parse serves warnings, notices and typhoons.
    doc = None
    if (area != None) or cats["typhoon"]:
        body = bousai_get_bytes(BOUSAI_TIMELINE_EXTRA_URL, ttl = 120)
        if body == None:
            notes.append("JMA feed unavailable")
        else:
            doc = xpath.loads(body)
    feed_cut = cut - 900

    if cats["quake"]:
        quakes = bousai_timeline_quakes(now, cut, opts["quake_int"])
        if quakes == None:
            notes.append("Quake list unavailable")
        else:
            events.extend(quakes)
    if cats["eew"]:
        eew = bousai_timeline_eew(cut)
        if eew == None:
            notes.append("EEW history unavailable")
        else:
            events.extend(eew)
    if cats["tsunami"]:
        tsu = bousai_timeline_tsunami(cut)
        if tsu == None:
            notes.append("Tsunami list unavailable")
        else:
            events.extend(tsu)

    # Fresh documents are fetched in priority order: notices (rare), weather warnings, typhoons, volcanoes. A group
    # may use whatever the earlier groups left unused, but warnings keep a few fetches back for the later groups.
    typhoon_on = doc != None and cats["typhoon"]
    volcano_reserve = BOUSAI_TIMELINE_VOLCANO_FETCH if cats["volcano"] else 0
    reserve = (BOUSAI_TIMELINE_TYPHOON_FETCH if typhoon_on else 0) + volcano_reserve

    if doc != None and area != None and cats["notice"]:
        entries = bousai_timeline_notice_entries(bousai_timeline_entries(doc, BOUSAI_TIMELINE_NOTICE_XPATH, feed_cut, True), area.get("pref") or "")
        events.extend(bousai_timeline_budgeted(fx, BOUSAI_TIMELINE_NOTICE_FETCH, lambda sub: bousai_timeline_notices(entries, area, bousai_area_table(), tz, cut, sub)))
    if area != None and cats["notice"]:
        events.extend(bousai_timeline_floods(area, cut))

    if doc != None and area != None and cats["info"]:
        events.extend(bousai_timeline_info_events(bousai_timeline_entries(doc, BOUSAI_TIMELINE_INFO_XPATH % area["office"], feed_cut, True), cut))

    if doc != None and area != None and cats["warn"]:
        entries = bousai_timeline_entries(doc, BOUSAI_TIMELINE_WARN_XPATH % area["office"], feed_cut)
        events.extend(bousai_timeline_budgeted(fx, fx["left"] - reserve, lambda sub: bousai_timeline_warning(entries, area, cut, sub, opts["minor"])))

    if typhoon_on:
        entries = bousai_timeline_entries(doc, BOUSAI_TIMELINE_TYPHOON_XPATH, feed_cut)
        sums = bousai_timeline_budgeted(fx, fx["left"] - volcano_reserve, lambda sub: [bousai_timeline_fetch(e["href"], BOUSAI_TIMELINE_DOC_KEY + "t:" + e["file"], "typhoon", sub) for e in entries])
        events.extend(bousai_timeline_typhoon_events(sums, cut, now))

    if cats["volcano"]:
        vbody = bousai_get_bytes(BOUSAI_TIMELINE_EQVOL_URL, ttl = 120)
        if vbody == None:
            notes.append("Volcano feed unavailable")
        else:
            vdoc = xpath.loads(vbody)
            reports = []
            levels = []
            for e in bousai_timeline_entries(vdoc, BOUSAI_TIMELINE_VOLCANO_XPATH, feed_cut, True):
                if "VFVO50" in e["file"]:
                    levels.append(e)
                else:
                    reports.append(dict(e, flash = "VFVO56" in e["file"] or e["content"].startswith("【噴火速報")))
            sums = bousai_timeline_budgeted(fx, fx["left"], lambda sub: [bousai_timeline_fetch(e["href"], BOUSAI_TIMELINE_DOC_KEY + "v:" + e["file"], "volcano", sub) for e in levels])
            km = opts["volcano_km"]
            events.extend(bousai_timeline_volcano_level_events(sums, loc, km, cut))
            events.extend(bousai_timeline_volcano_eruptions(reports, loc, km, tz, cut))

    kept = [e for e in events if e["sev"] >= opts["min_sev"] and e["t"] >= cut]
    return {"events": sorted(kept, key = lambda e: (-e["t"], -e["sev"])), "notes": notes, "area": area}
