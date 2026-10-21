"""Home (information panel) library for the Bousai suite.

Consolidates every disaster and weather feed of the suite for ONE location into a single list of
items and orders it automatically, the way the information panel of the NERV Disaster Prevention
home screen rearranges itself "according to type, elapsed time and urgency". Data only: nothing
here draws widgets; the Home app turns the items into cards.

Entry points: bousai_home_options(config) -> opts; bousai_home_gather(config, opts) -> state (items sorted,
see below; opts["demo"] returns an embedded sample instead); bousai_home_calm(config, opts, state) -> the
weather / last-quake feeds, read only when the app has room for them.

Sources (each can be switched off with the option src_<id>; all are on by default):
  EEW (bousai_eew_active), shaking detection (bousai_eew_shaking; P2PQuake is a volunteer service that
  can stall, and a stalled request fails the whole render, so the EEW library reads it through the core
  cooldown guard bousai_guarded_json), tsunami (bousai_tsunami_current), weather warnings and notices
  (bousai_warnings_place: warnings, tornado watch, record rain, river flood), volcanic alert levels and
  eruption flash reports within a radius (bousai_volcano_current / _flash), recent earthquakes
  (bousai_quake_recent), Nankai Trough / Hokkaido-Sanriku special information (bousai_quake_special),
  typhoons within a radius (bousai_typhoon_current). Calm information: current conditions
  (bousai_amedas_latest), today's forecast with sunrise / sunset (bousai_forecast_today) and the last
  felt quake.

Item: {kind, sev, cls, when, bands, lines, count, data}
  kind   eew | shaking | tsunami | warnings | notice | volcano | eruption | quake | special | typhoon
  sev    0..5 on the suite's severity scale (ui["sev"]): 1 info, 2 advisory, 3 warning, 4 urgent, 5 emergency
  cls    urgency class name (see below)
  when   Pixlet time of the issue / origin (None when unknown): the "elapsed time" of the item
  bands  title candidates, longest first ("Lv4 Urgent Warning", "Lv4 Urgent", "Lv4")
  lines  plain-text detail lines, most important first
  count  how many individual alerts the item stands for (a Lv4 card for Heavy Rain + Landslide counts 2)
  data   the source record(s) for richer rendering

PRIORITY MODEL. Items are sorted ascending by the tuple (-sev, class rank, -when):
  1. severity, highest first (an emergency outranks everything below it; within one severity:)
  2. urgency class, in this order (lower rank = more urgent):
       0 eew       Earthquake early warning (warning, forecast, cancellation)
       1 tsunami   Tsunami warning / advisory / forecast
       2 urgent    Lv4 and Lv5 warnings of any element, landslide alerts from Lv3, volcano / river flood /
                   special information at Lv4 and above
       3 eruption  Eruption flash report inside the radius
       4 notice    Record short-term heavy rain, tornado watch
       5 quake     Earthquake inside the recency window; shaking detection
       6 warning   Lv3 warnings, volcano Lv3, river flood Lv3, special information at Lv3
       7 typhoon   Typhoon inside the radius
       8 advisory  Lv2 advisories, volcano Lv2, river flood Lv2, special information under analysis
       9 calm      Weather, last felt quake, "No warnings" status: not items; the app appends them after
                   the items and they only fill the dwell time the items leave
  3. newest first.
The severity of each source:
  EEW                 bousai_eew_sev: warning 5, forecast 2 (Int 3+ expected) or 1, cancellation 1.
  Tsunami             grade: Major Tsunami Warning 5, Warning 3, Advisory 2, Forecast 1.
  Warnings            level // 10: Advisory 2, Warning 3, Urgent Warning (Lv4) 4, Emergency Warning (Lv5) 5.
                      One item per level, so Lv4 Heavy Rain + Lv4 Landslide share a card.
  Notices             record short-term heavy rain 4, tornado watch 3, river flood level // 10.
  Volcano             alert level 2..5 inside the radius, one item per level (Lv1 is not an alert).
  Eruption flash      4 for 3 hours after the report (reports stay listed for 24 h), then 2.
  Earthquake          the stronger of the intensity felt at the location (Int 1-2: 1, 3: 2, 4: 3, 5-/5+: 4,
                      6- and above: 5) and the maximum intensity anywhere discounted by two steps (Int 6-
                      and above: 3, 5-/5+: 2). Only quakes inside the recency window count, and quakes
                      of severity 1 are not items: the newest felt quake is the calm "last quake" card.
  Special information 2 under analysis, 3 attention / subsequent-earthquake advisory, 4 megathrust alert.
  Typhoon             inside the radius: Typhoon and Severe Tropical Storm 3, Tropical Storm 2,
                      Tropical Depression 1 (the warnings carry the actual hazard, so it stays at 3).
  Shaking detection   2 when your prefecture is named (or the report names none), else 1.
The number shown as "active" in the header is the sum of `count` of the items at sev >= 2. Nothing at
sev >= 2 is the calm state: the sev <= 1 items first, then weather, last felt quake and "No warnings".
With alerts, calm cards follow only as far as the dwell time allows (weather: its first page).

Alert-only mode (for Tronbyt AutoPin): the app returns nothing unless the strongest item reaches the
chosen level, and the calm feeds are never read.
"""

# bousai: requires core data eew quake tsunami volcano typhoon warnings forecast amedas

load("time.star", "time")

BOUSAI_HOME_CLASSES = ["eew", "tsunami", "urgent", "eruption", "notice", "quake", "warning", "typhoon", "advisory", "calm"]

# Source id -> option key ("src_<id>"). Order is the order of the menu.
BOUSAI_HOME_SOURCES = ["eew", "shaking", "tsunami", "warnings", "volcano", "quake", "special", "typhoon", "amedas", "forecast"]

# Eruption flash: urgent for this long after the report.
BOUSAI_HOME_ERUPTION_URGENT_MIN = 180

# Warning level -> band texts, longest first.
BOUSAI_HOME_LEVEL_BANDS = {
    20: ["Lv2 Advisory", "Lv2 Advis.", "Lv2"],
    30: ["Lv3 Warning", "Lv3 Warn.", "Lv3"],
    40: ["Lv4 Urgent Warning", "Lv4 Urgent", "Lv4"],
    50: ["Lv5 Emergency Warning", "Lv5 Emergency", "Lv5"],
}

BOUSAI_HOME_TSUNAMI_BANDS = {
    5: ["Major Tsunami Warning", "Major Tsunami", "Tsunami"],
    3: ["Tsunami Warning", "Tsunami Warn.", "Tsunami"],
    2: ["Tsunami Advisory", "Tsunami Adv.", "Tsunami"],
    1: ["Tsunami Forecast", "Tsunami Fcst", "Tsunami"],
}

# Typhoon category (JMA English, bousai_typhoon_current) -> severity inside the radius.
BOUSAI_HOME_TYPHOON_SEV = {
    "Violent Typhoon": 3,
    "Very Strong Typhoon": 3,
    "Typhoon": 3,
    "Severe Tropical Storm": 3,
    "Tropical Storm": 2,
    "Tropical Depression": 1,
}

# ---------------------------------------------------------------------------
# Options

def bousai_home_int(config, key, default, lo, hi):
    """Integer option clamped to lo..hi; default when missing or not a number."""
    v = str(config.get(key) or "")
    if not v.isdigit():
        return default
    return max(lo, min(hi, int(v)))

def bousai_home_options(config):
    """Parse the app options into one dict: a bool per source id (all on by default), quake_hours,
    volcano_km, typhoon_km, alert_only, alert_level (1..5) and demo."""
    opts = {
        "demo": bousai_bool(config, "demo", False),
        "alert_only": bousai_bool(config, "alert_only", False),
        "alert_level": bousai_home_int(config, "alert_level", 3, 1, 5),
        "quake_hours": bousai_home_int(config, "quake_hours", 1, 1, 72),
        "volcano_km": bousai_home_int(config, "volcano_km", 100, 1, 3000),
        "typhoon_km": bousai_home_int(config, "typhoon_km", 500, 1, 5000),
    }
    for s in BOUSAI_HOME_SOURCES:
        opts[s] = bousai_bool(config, "src_" + s, True)
    return opts

# ---------------------------------------------------------------------------
# Priority

def bousai_home_key(item):
    """Sort key of an item: (-severity, class rank, -time)."""
    when = item["when"]
    return (-item["sev"], BOUSAI_HOME_CLASSES.index(item["cls"]), -(when.unix if when != None else 0))

def bousai_home_sort(items):
    """Items in display order: most important first (see the priority model above)."""
    return sorted(items, key = bousai_home_key)

def bousai_home_active(items):
    """Number of individual alerts at severity 2 or more."""
    n = 0
    for it in items:
        if it["sev"] >= 2:
            n += it["count"]
    return n

def bousai_home_item(kind, sev, cls, when, bands, lines, count = 1, data = None):
    return {"kind": kind, "sev": sev, "cls": cls, "when": when, "bands": bands, "lines": lines, "count": count, "data": data}

def bousai_home_level_class(sev, landslide = False):
    """Urgency class of a warning-like item of severity sev (landslide alerts rank as urgent from Lv3)."""
    if sev >= 4 or (sev == 3 and landslide):
        return "urgent"
    return "warning" if sev == 3 else "advisory"

def bousai_home_km(v):
    return "%dkm" % int(v + 0.5)

# ---------------------------------------------------------------------------
# Items from each source

def bousai_home_eew_items(events):
    """Items for the active EEWs of bousai_eew_active (one per event)."""
    out = []
    for ev in events:
        word = "Cancelled" if ev["cancel"] else ("Warning" if ev["warn"] else "Forecast")
        short = {"Cancelled": "Cancel", "Warning": "Warn", "Forecast": "Fcst"}[word]
        place = "Assumed epicentre" if ev["assumption"] else ev["epicenter_en"]
        head = place if ev["assumption"] else "%s %s" % (bousai_eew_mag_text(ev["mag"]), place)
        lines = [head]
        if ev["local_int"] != None and not ev["cancel"]:
            lines.append("Est. Int %s here" % ev["local_int"])
        if ev["max_int"]:
            lines.append("Max Int %s" % ev["max_int"] + ("" if ev["assumption"] or ev["depth_km"] == None else " %s" % bousai_eew_depth_text(ev["depth_km"])))
        lines.append("Report %d%s" % (ev["serial"], " (final)" if ev["final"] else ""))
        out.append(bousai_home_item("eew", bousai_eew_sev(ev), "eew", ev["announced"], ["EEW " + word, "EEW " + short, "EEW"], lines, 1, ev))
    return out

def bousai_home_shaking_item(sh, pref_en):
    """Shaking-detection item (P2PQuake), or None. Severity 2 when pref_en (your prefecture) is named."""
    if sh == None or not sh["detected"]:
        return None
    areas = sh["areas_en"]
    near = len(areas) == 0 or (pref_en != None and pref_en in areas)
    conf = sh["confidence"]
    lines = [", ".join(areas) if areas else "Area not given", "Unconfirmed"]
    if conf.startswith("Lv"):
        lines.append("Confidence %s" % conf[2:])
    elif conf:
        lines.append("EEW detected")
    return bousai_home_item("shaking", 2 if near else 1, "quake", sh["time"], ["Shaking Detected", "Shaking"], lines, 1, sh)

def bousai_home_tsunami_item(ts):
    """Item for a bousai_tsunami_current() result, or None when nothing is in effect."""
    if ts == None or not ts["active"] or len(ts["items"]) == 0:
        return None
    sev = ts["sev"]
    top = ts["items"][0]
    arrival = top["arrival_en"]
    if ":" in arrival:
        arrival = "ETA " + arrival
    parts = [x for x in [arrival, top["height_en"]] if x]
    detail = ", ".join(parts)
    if len(detail) > 15:
        detail = " ".join(parts)
    lines = [top["area_en"], detail or "No timing yet"]
    if len(ts["items"]) > 1:
        lines.append("+%d more region%s" % (len(ts["items"]) - 1, "" if len(ts["items"]) == 2 else "s"))
    return bousai_home_item("tsunami", sev, "tsunami", ts["issued"], BOUSAI_HOME_TSUNAMI_BANDS.get(sev) or ["Tsunami"], lines, 1, ts)

def bousai_home_warning_items(current):
    """One item per warning level of a bousai_warnings_current() list."""
    groups = {}
    for w in current:
        groups.setdefault(w["level"], []).append(w)
    out = []
    for level in sorted(groups.keys(), reverse = True):
        ws = groups[level]
        sev = level // 10
        landslide = len([w for w in ws if w["element"] == "landslide"]) > 0
        when = ws[0]["issued"]
        for w in ws:
            if w["issued"] > when:
                when = w["issued"]
        lines = [w["element_en"] for w in ws] + [ws[0]["area_en"]]
        out.append(bousai_home_item("warnings", sev, bousai_home_level_class(sev, landslide), when, BOUSAI_HOME_LEVEL_BANDS.get(level) or ["Warning"], lines, len(ws), ws))
    return out

def bousai_home_notice_items(notices):
    """Items for bousai_warnings_notices(): tornado watch, record heavy rain, river flood."""
    out = []
    for n in notices:
        kind = n["kind_en"]
        sev = n["sev"]
        if kind.startswith("Tornado"):
            cls = "notice"
            bands = ["Tornado Watch", "Tornado"]
        elif kind.startswith("Record"):
            cls = "notice"
            bands = ["Record Short-Term Heavy Rain", "Record Heavy Rain", "Record Rain", "Rain"]
        else:
            cls = bousai_home_level_class(sev)
            bands = ["River Flood Lv%d" % sev, "Flood Lv%d" % sev, "Lv%d" % sev]
        out.append(bousai_home_item("notice", sev, cls, n["issued"], bands, [n["text_en"]], 1, n))
    return out

def bousai_home_volcano_meaning(kind_en):
    """'Level 3 (Do not approach the volcano)' -> 'Do not approach the volcano'."""
    if "(" in kind_en:
        return kind_en.split("(", 1)[1].rstrip(")")
    return kind_en

def bousai_home_volcano_items(volcanoes, loc, radius_km):
    """One item per alert level (2..5) of the volcanoes of bousai_volcano_current within radius_km."""
    groups = {}
    for v in volcanoes:
        if v["sev"] >= 2 and v["distance_km"] <= radius_km:
            groups.setdefault(v["sev"], []).append(v)
    out = []
    for sev in sorted(groups.keys(), reverse = True):
        vs = sorted(groups[sev], key = lambda v: v["distance_km"])
        when = vs[0]["issued"]
        lines = [bousai_home_volcano_meaning(vs[0]["kind_en"])]
        for v in vs:
            lines.append("%s %s %s" % (v["name_en"], bousai_home_km(v["distance_km"]), bousai_bearing_name(loc["lat"], loc["lon"], v["lat"], v["lon"])))
            if v["issued"] != None and (when == None or v["issued"] > when):
                when = v["issued"]
        level = vs[0]["level"]
        label = "Volcano Lv%d" % level if level else "Volcano " + BOUSAI_SEVERITY_EN[sev]
        out.append(bousai_home_item("volcano", sev, bousai_home_level_class(sev), when, [label, "Volc. Lv%d" % level if level else "Volcano", "Lv%d" % level if level else "Vol"], lines, len(vs), vs))
    return out

def bousai_home_eruption_items(flashes, loc, radius_km, now):
    """Items for bousai_volcano_flash() reports whose volcano lies within radius_km (24 h of reports)."""
    rows = {}
    for row in BOUSAI_VOLCANOES.values():
        rows[row[0]] = row
    out = []
    for f in flashes:
        row = rows.get(f["name_en"])
        if row == None:
            continue
        km = bousai_distance_km(loc["lat"], loc["lon"], row[1], row[2])
        if km > radius_km:
            continue
        age_min = (now - f["time"]).minutes
        sev = 4 if age_min <= BOUSAI_HOME_ERUPTION_URGENT_MIN else 2
        lines = [f["name_en"], f["text_en"], "%s %s" % (bousai_home_km(km), bousai_bearing_name(loc["lat"], loc["lon"], row[1], row[2]))]
        out.append(bousai_home_item("eruption", sev, "eruption", f["time"], ["Eruption Flash", "Eruption"], lines, 1, f))
    return out

def bousai_home_quake_sev(q):
    """Severity of a quake for this location (see the priority model): the stronger of the intensity felt
    here and a two-step discount of the maximum intensity anywhere (strong quakes elsewhere still show)."""
    local = bousai_intensity_rank(q["local_int"] or "")
    top = bousai_intensity_rank(q["max_int"] or "")
    sev = 1
    if local >= bousai_intensity_rank("6-"):
        sev = 5
    elif local >= bousai_intensity_rank("5-"):
        sev = 4
    elif local == bousai_intensity_rank("4"):
        sev = 3
    elif local == bousai_intensity_rank("3"):
        sev = 2
    if top >= bousai_intensity_rank("6-"):
        sev = max(sev, 3)
    elif top >= bousai_intensity_rank("5-"):
        sev = max(sev, 2)
    return sev

def bousai_home_quake_facts(q):
    """'M5.1 D10km' (magnitude and depth; 'shallow' for depth 0, 'Magnitude pending' without magnitude)."""
    parts = []
    if q["mag"]:
        parts.append("M" + q["mag"])
    if q["depth_km"] != None:
        parts.append("D%dkm" % int(q["depth_km"] + 0.5) if q["depth_km"] >= 1 else "shallow")
    return " ".join(parts) or "Magnitude pending"

def bousai_home_quake_items(quakes, hours, now):
    """Items for the quakes inside the recency window whose severity is 2 or more."""
    out = []
    for q in quakes:
        if (now - q["time"]).hours > hours:
            continue
        sev = bousai_home_quake_sev(q)
        if sev < 2:
            continue
        top = q["max_int"] or "?"
        lines = [q["epicenter_en"], bousai_home_quake_facts(q)]
        if q["local_int"]:
            lines.append("Your area Int %s" % q["local_int"])
        out.append(bousai_home_item("quake", sev, "quake", q["time"], ["Quake Int " + top, "Int " + top, "Quake"], lines, 1, q))
    return out

def bousai_home_special_items(specials):
    """Items for bousai_quake_special(): Nankai Trough / Hokkaido-Sanriku information."""
    out = []
    for s in specials:
        nankai = "Nankai" in s["title_en"]
        bands = ["Nankai Trough", "Nankai"] if nankai else ["Hokkaido-Sanriku", "Sanriku"]
        out.append(bousai_home_item("special", s["sev"], bousai_home_level_class(s["sev"]), s["issued"], bands, [s["kind_en"]], 1, s))
    return out

def bousai_home_typhoon_items(typhoons, radius_km):
    """Items for the typhoons of bousai_typhoon_current within radius_km (nearest first)."""
    out = []
    for t in typhoons:
        if t["distance_km"] == None or t["distance_km"] > radius_km:
            continue
        sev = BOUSAI_HOME_TYPHOON_SEV.get(t["category_en"], 2)
        name = ("%s %s" % (t["name_en"], t["category_en"])).strip()
        lines = ["%s %s of you" % (bousai_home_km(t["distance_km"]), t["bearing"]), name]
        stats = []
        if t["pressure_hpa"] != None:
            stats.append("%dhPa" % t["pressure_hpa"])
        if t["wind_ms"] != None:
            stats.append("%d%sm/s" % (t["wind_ms"], "/%d" % t["gust_ms"] if t["gust_ms"] != None else ""))
        if stats:
            lines.append(" ".join(stats))
        move = t["course_en"] or ""
        if move and t["speed_kmh"] != None:
            move = "%s %dkm/h" % (move, t["speed_kmh"])
        if move:
            lines.append("Move " + move)
        bands = ["Typhoon No.%d" % t["number"], "Typhoon %d" % t["number"], "Typhoon"] if t["number"] else ["Tropical Cyclone", "Cyclone"]
        out.append(bousai_home_item("typhoon", sev, "typhoon", t["issued"], bands, lines, 1, t))
    return out

# ---------------------------------------------------------------------------
# Calm information

def bousai_home_last_quake(quakes):
    """The quake for the calm card: the newest one felt at the location, else the newest listed."""
    for q in quakes:
        if q["local_int"]:
            return q
    return quakes[0] if quakes else None

# ---------------------------------------------------------------------------
# Demo

def bousai_home_demo_tsunami(now):
    """Embedded sample in bousai_tsunami_current() shape: the Tsunami Advisory regions of JMA's 16:22
    report of the 2024-01-01 Noto Peninsula earthquake (1 m expected), arrival times relative to now."""
    items = []
    for code, minutes in [("200", 28), ("230", 28), ("500", 38), ("550", 38)]:
        arrival = (now + time.parse_duration("%dm" % minutes)).in_location(BOUSAI_JST).format("15:04")
        items.append({"area_en": BOUSAI_TSUNAMI_AREA_EN[code], "kind_en": BOUSAI_TSUNAMI_KIND_EN["62"], "sev": 2, "arrival_en": arrival, "height_en": "1m"})
    return {"active": True, "issued": now - time.parse_duration("3m"), "sev": 2, "items": items}

def bousai_home_demo(config):
    """Combined sample state (same shape as bousai_home_gather): an EEW warning (the 2024-01-01 Noto
    Peninsula report of the EEW library, countdown timed for the location), a tsunami advisory
    (that event's advisory regions) and the urgent part of the warnings library's sample: Lv4 Heavy
    Rain + Landslide and a record short-term heavy rain notice (a July-2025-type event). Not real."""
    loc = bousai_location(config)
    now = time.now()
    items = bousai_home_eew_items([bousai_eew_public(ev) for ev in bousai_eew_poll(config, demo = True)["events"]])
    tsunami = bousai_home_tsunami_item(bousai_home_demo_tsunami(now))
    if tsunami != None:
        items.append(tsunami)
    place = bousai_warnings_demo()[0]
    items.extend(bousai_home_warning_items([w for w in place["current"] if w["level"] >= 40]))
    items.extend(bousai_home_notice_items([n for n in place["notices"] if n["kind_en"].startswith("Record")]))
    return bousai_home_finish(loc, None, now, items, [], {"warnings": True, "tsunami": True}, True)

# ---------------------------------------------------------------------------
# Gathering

def bousai_home_finish(loc, area, now, items, quakes, ok, demo):
    """The state dict every consumer gets: loc, area, now, items (sorted), active, top_sev, quakes, ok, demo."""
    items = bousai_home_sort(items)
    return {
        "loc": loc,
        "area": area,
        "now": now,
        "items": items,
        "active": bousai_home_active(items),
        "top_sev": items[0]["sev"] if items else 0,
        "quakes": quakes,
        "ok": ok,
        "demo": demo,
    }

def bousai_home_gather(config, opts):
    """Collect and prioritise everything for the configured location.

    Returns {loc, area (bousai_area or None), now, items (sorted, see the priority model), active (alerts at
    sev >= 2), top_sev, quakes (the recent felt quakes listed by JMA, newest first), ok, demo}; ok =
    {warnings, tsunami}: True / False when the feed was read / not readable, None when not asked. The calm
    feeds are not read here: see bousai_home_calm.
    """
    if opts["demo"]:
        return bousai_home_demo(config)
    loc = bousai_location(config)
    now = time.now()
    area = bousai_area(config)
    items = []
    ok = {"warnings": None, "tsunami": None}
    quakes = []

    if opts["eew"]:
        items.extend(bousai_home_eew_items(bousai_eew_active(config)))
    if opts["shaking"]:
        pref_en = BOUSAI_PREF_EN.get(area["pref"]) if area else None
        sh = bousai_home_shaking_item(bousai_eew_shaking(), pref_en)
        if sh != None:
            items.append(sh)
    if opts["tsunami"]:
        ts = bousai_tsunami_current()
        ok["tsunami"] = ts != None
        tsunami = bousai_home_tsunami_item(ts)
        if tsunami != None:
            items.append(tsunami)
    if opts["warnings"] and area != None:
        place = bousai_warnings_place(area)
        ok["warnings"] = place["ok"]
        items.extend(bousai_home_warning_items(place["current"]))
        items.extend(bousai_home_notice_items(place["notices"]))
    if opts["volcano"]:
        items.extend(bousai_home_volcano_items(bousai_volcano_current(config), loc, opts["volcano_km"]))
        items.extend(bousai_home_eruption_items(bousai_volcano_flash(), loc, opts["volcano_km"], now))
    if opts["quake"]:
        quakes = bousai_quake_recent(config, 5, "1")
        items.extend(bousai_home_quake_items(quakes, opts["quake_hours"], now))
    if opts["special"]:
        items.extend(bousai_home_special_items(bousai_quake_special()))
    if opts["typhoon"]:
        items.extend(bousai_home_typhoon_items(bousai_typhoon_current(config), opts["typhoon_km"]))

    return bousai_home_finish(loc, area, now, items, quakes, ok, False)

def bousai_home_calm(config, opts, state):
    """The calm-information feeds for a gathered state: {quake (the newest felt quake, or None), amedas
    (current conditions, or None), forecast (today's forecast, or None)}. Separate from bousai_home_gather
    so the caller reads the weather feeds only when there is dwell time left for them."""
    loc = state["loc"]
    amedas = bousai_amedas_latest(loc["lat"], loc["lon"]) if opts["amedas"] else None
    forecast = bousai_forecast_today(state["area"], config) if opts["forecast"] and state["area"] != None else None
    return {"quake": bousai_home_last_quake(state["quakes"]), "amedas": amedas, "forecast": forecast}
