"""
Applet: Bousai Tsunami
Summary: JMA tsunami warnings
Description: Tsunami warnings, advisories and forecasts from the Japan Meteorological Agency: the highest grade in effect, the coast nearest you with expected arrival time and height, a map of Japan with coasts coloured by grade, the other warned regions, tide-gauge and offshore observations, and tide times. Skips itself while nothing is in effect, so Tronbyt AutoPin can bring it to the front when a warning is issued.
Author: Bousai Apps
"""

# bousai: requires core map data mapdata quake tsunami

load("render.star", "canvas", "render")
load("schema.star", "schema")
load("time.star", "time")

TSUNAMI_MAX_PAGES = 6

# Short wording for first-wave conditions when the room is tight.
TSUNAMI_COND_SHORT = {"Arriving now": "Now", "Imminent": "Soon", "May have arrived": "Arrived?"}

# A location farther than this from every warned-region coastline is treated as outside Japan.
TSUNAMI_FAR_KM = 400

# Header words per grade, longest first (the first that fits is used).
TSUNAMI_BAND = {
    5: ["Major Tsunami Warning", "Major Warning"],
    3: ["Tsunami Warning", "Warning"],
    2: ["Tsunami Advisory", "Advisory"],
    1: ["Tsunami Forecast", "Forecast"],
}

# Sample: the 2024-01-01 Noto Peninsula earthquake (M7.6). Regions, grades, expected arrival and
# heights are JMA's 16:22 JST tsunami warning report as archived by P2PQuake; shown at 16:30.
# The tide-gauge readings are illustrative values for the same event, not JMA's report.
TSUNAMI_DEMO_NOW = "2024-01-01T16:30:00+09:00"
TSUNAMI_DEMO_ISSUED = "2024-01-01T16:22:00+09:00"
TSUNAMI_DEMO = [
    # region code, kind code, expected first wave ('now' = arriving), height m
    ("360", "52", "now", 5),
    ("240", "51", "16:40", 3),
    ("340", "51", "now", 3),
    ("341", "51", "now", 3),
    ("350", "51", "now", 3),
    ("361", "51", "16:50", 3),
    ("370", "51", "17:00", 3),
    ("520", "51", "17:00", 3),
    ("102", "62", "17:10", 1),
    ("110", "62", "17:30", 1),
    ("111", "62", "16:50", 1),
    ("200", "62", "16:50", 1),
    ("230", "62", "16:50", 1),
    ("500", "62", "17:00", 1),
    ("540", "62", "17:10", 1),
    ("550", "62", "17:40", 1),
    ("551", "62", "17:00", 1),
    ("700", "62", "18:20", 1),
    ("711", "62", "19:10", 1),
    ("720", "62", "19:40", 1),
    ("731", "62", "18:30", 1),
]

def tsunami_int(config, key, default):
    v = str(config.get(key) or "")
    if not v.isdigit():
        return default
    return int(v)

def tsunami_demo_state():
    now = time.parse_time(TSUNAMI_DEMO_NOW)
    items = []
    for code, kcode, arrival, height in TSUNAMI_DEMO:
        items.append({
            "code": code,
            "area_en": BOUSAI_TSUNAMI_AREA_EN[code],
            "kcode": kcode,
            "kind_en": BOUSAI_TSUNAMI_KIND_EN[kcode],
            "sev": BOUSAI_TSUNAMI_SEV[kcode],
            "arrival": None if arrival == "now" else time.parse_time("2024-01-01T" + arrival + ":00+09:00"),
            "cond": "Arriving now" if arrival == "now" else "",
            "height_m": float(height),
            "height_en": "%dm" % height,
            "stations": [],
        })
    noto = BOUSAI_TSUNAMI_AREA_EN["360"]
    toyama = BOUSAI_TSUNAMI_AREA_EN["350"]
    observed = [
        {"name_en": "Wajima", "area_en": noto, "lat": 37.40, "lon": 136.90, "height_m": 1.2, "height_en": "1.2m+", "time": time.parse_time("2024-01-01T16:21:00+09:00"), "first": time.parse_time("2024-01-01T16:21:00+09:00"), "rise": "Rise"},
        {"name_en": "Toyama", "area_en": toyama, "lat": 36.77, "lon": 137.22, "height_m": 0.4, "height_en": "0.4m", "time": time.parse_time("2024-01-01T16:27:00+09:00"), "first": time.parse_time("2024-01-01T16:25:00+09:00"), "rise": "Fall"},
    ]
    return {
        "now": now,
        "active": True,
        "sev": 5,
        "issued": time.parse_time(TSUNAMI_DEMO_ISSUED),
        "items": items,
        "valid_until": None,
        "quakes": [{"name_en": BOUSAI_EPICENTER_EN["390"], "lat": 37.5, "lon": 137.2, "depth": 10.0, "mag": "7.6", "time": time.parse_time("2024-01-01T16:10:00+09:00")}],
        "last": None,
        "stations": [],
        "observed": observed,
        "offshore": [],
        "info_time": time.parse_time("2024-01-01T16:28:00+09:00"),
    }

# ---------------------------------------------------------------------------
# Rows. A row is (height, builder); builder(frames) makes the widget (see bousai_quake_pack).

def tsunami_row_text(ui, s, color = None):
    return (ui["line_h"], lambda f: bousai_fit(ui, s, color = color, frames = f))

def tsunami_chip(ui, label, color):
    return render.Box(width = bousai_text_width(ui, label) + 3, height = bousai_font_height(ui) + 1, color = color, child = bousai_text(ui, label, bousai_on(color)))

def tsunami_detail(ui, item, tz, room):
    """Expected first wave and height: 'Arriving now 5m' or '16:40 3m'; the short wording ('Now') if the long one does not fit."""
    when = bousai_tsunami_arrival_text(item, tz)
    text = " ".join([x for x in [when, item["height_en"]] if x])
    if bousai_text_width(ui, text) > room:
        text = " ".join([x for x in [TSUNAMI_COND_SHORT.get(when, when), item["height_en"]] if x])
    return text or "no timing yet"

def tsunami_status_row(ui, item, tz):
    """Grade chip plus expected arrival and height (scrolls in the room left of the chip)."""
    chip_text = BOUSAI_TSUNAMI_GRADE_SHORT[item["sev"]]
    color = bousai_sev_color(ui, item["sev"])
    room = canvas.width() - bousai_text_width(ui, chip_text) - 5
    detail = tsunami_detail(ui, item, tz, room)
    return (ui["line_h"], lambda f: render.Row(expanded = True, main_align = "start", cross_align = "center", children = [tsunami_chip(ui, chip_text, color), render.Padding(pad = (2, 0, 0, 0), child = bousai_fit(ui, detail, width = room, frames = f))]))

def tsunami_entry(ui, item, tz):
    """Two-row entry: region name, then grade chip with arrival and height."""
    chip_text = BOUSAI_TSUNAMI_GRADE_SHORT[item["sev"]]
    color = bousai_sev_color(ui, item["sev"])
    room = canvas.width() - bousai_text_width(ui, chip_text) - 5
    detail = tsunami_detail(ui, item, tz, room)
    name = item["area_en"]

    def build(f):
        bottom = render.Row(expanded = True, main_align = "start", cross_align = "center", children = [tsunami_chip(ui, chip_text, color), render.Padding(pad = (2, 0, 0, 0), child = bousai_fit(ui, detail, width = room, frames = f))])
        return render.Column(children = [bousai_fit(ui, name, frames = f), bottom])

    return (2 * ui["line_h"], build)

def tsunami_obs_color(ui, h):
    """JMA's icon scale for observed heights: over 3 m, over 1 m, 0.2 m and up, below."""
    if h == None:
        return ui["sev"][1]
    if h > 3:
        return ui["sev"][5]
    if h > 1:
        return ui["sev"][3]
    if h >= 0.2:
        return ui["sev"][2]
    return ui["sev"][1]

def tsunami_obs_row(ui, o, offshore):
    chip_text = o["height_en"] or "?"
    color = tsunami_obs_color(ui, o["height_m"])
    room = canvas.width() - bousai_text_width(ui, chip_text) - 5
    name = ("Off: " if offshore else "") + o["name_en"]
    return (ui["line_h"], lambda f: render.Row(expanded = True, main_align = "start", cross_align = "center", children = [tsunami_chip(ui, chip_text, color), render.Padding(pad = (2, 0, 0, 0), child = bousai_fit(ui, name, width = room, frames = f))]))

# ---------------------------------------------------------------------------
# Pages

def tsunami_head(ui, sev):
    cands = TSUNAMI_BAND[sev]
    color = bousai_sev_color(ui, sev)
    text = cands[-1]
    for c in cands:
        text = c
        if bousai_text_width(ui, c) <= canvas.width() - 2:
            break
    return (ui["line_h"], lambda f: bousai_header(ui, text, color, frames = f))

def tsunami_status_pages(ui, state, items, region, km, tz):
    now = state["now"]
    by_code = {}
    for it in items:
        by_code[it["code"]] = it
    rows = []
    near_item = by_code.get(region) if region != None and km != None and km <= TSUNAMI_FAR_KM else None
    if region == None or km == None or km > TSUNAMI_FAR_KM:
        rows.append(tsunami_row_text(ui, "Location outside Japan", ui["muted"]))
        top = items[0]
        rows.append(tsunami_status_row(ui, top, tz))
    else:
        label = "Your coast: " + BOUSAI_TSUNAMI_AREA_EN.get(region, region) + (" ~%dkm" % int(km + 0.5) if km >= 15 else "")
        rows.append(tsunami_row_text(ui, label))
        if near_item != None:
            rows.append(tsunami_status_row(ui, near_item, tz))
        else:
            rows.append(tsunami_row_text(ui, "No warning here", ui["muted"]))
    when = state["issued"]
    if when != None:
        rows.append(tsunami_row_text(ui, "Issued " + bousai_hhmm(when, tz) + "  " + bousai_ago(when, now), ui["muted"]))
    sev = items[0]["sev"]
    head = tsunami_head(ui, sev)
    return bousai_quake_pack(rows, head, None if ui["size"] == "xlarge" else head)

def tsunami_points(items, coast):
    pts = []
    for it in items:
        for line in coast.get(it["code"]) or []:
            for p in line[::3]:
                pts.append((p[1], p[0]))
            pts.append((line[-1][1], line[-1][0]))
    return pts

def tsunami_line(view, line, color):
    pts = []
    for p in line:
        x, y = bousai_world_px(p[1], p[0], view["zoom"])
        pts.append((x - view["ox"], view["h"] - (y - view["oy"])))
    return render.Plot(data = pts, width = view["w"], height = view["h"], color = color, x_lim = (0, view["w"]), y_lim = (0, view["h"]), chart_type = "line")

def tsunami_marks(ui, view, quakes, user):
    layers = []
    red = ui["sev"][3]
    for q in quakes:
        if q["lat"] == None:
            continue
        ex, ey = bousai_view_xy(view, q["lat"], q["lon"])
        arm = 3
        layers.append(bousai_place(ex - arm - 1, ey - 1, render.Box(width = 2 * arm + 3, height = 3, color = ui["bg"])))
        layers.append(bousai_place(ex - 1, ey - arm - 1, render.Box(width = 3, height = 2 * arm + 3, color = ui["bg"])))
        layers.append(bousai_place(ex - arm, ey, render.Box(width = 2 * arm + 1, height = 1, color = red)))
        layers.append(bousai_place(ex, ey - arm, render.Box(width = 1, height = 2 * arm + 1, color = red)))
    if user != None:
        ux, uy = bousai_view_xy(view, user["lat"], user["lon"])
        if bousai_in_view(view, ux, uy):
            layers.append(bousai_place(ux - 2, uy - 2, render.Box(width = 5, height = 5, color = ui["bg"], child = render.Box(width = 3, height = 3, color = ui["fg"]))))
    return layers

def tsunami_legend(ui, items):
    """One chip per grade in effect: letter and region count (M major, W warning, A advisory, F forecast)."""
    counts = {}
    for it in items:
        counts[it["sev"]] = counts.get(it["sev"], 0) + 1
    kids = []
    for sev in [5, 3, 2, 1]:
        if sev in counts:
            kids.append(render.Padding(pad = (0, 0, 2, 0), child = tsunami_chip(ui, BOUSAI_TSUNAMI_GRADE_LETTER[sev] + str(counts[sev]), bousai_sev_color(ui, sev))))
    return render.Box(width = canvas.width(), height = bousai_font_height(ui) + 2, child = render.Row(expanded = True, main_align = "start", cross_align = "center", children = kids))

def tsunami_map(ui, items, coast, quakes, user, points):
    """Japan with each warned coast drawn in its grade colour, the epicenter and you."""
    mh = canvas.height() - (bousai_font_height(ui) + 2)
    points = list(points)
    for q in quakes:
        if q["lat"] != None:
            points.append((q["lat"], q["lon"]))
    if user != None:
        points.append((user["lat"], user["lon"]))
    view = bousai_view_fit(points, canvas.width(), mh, pad = 3, min_zoom = 1.0, max_zoom = 5.0)
    layers = [bousai_basemap(ui, view, "japan")]
    for sev in [1, 2, 3, 5]:
        color = bousai_sev_color(ui, sev)
        for it in items:
            if it["sev"] != sev:
                continue
            for line in coast.get(it["code"]) or []:
                if len(line) > 1:
                    layers.append(tsunami_line(view, line, color))
    layers.extend(tsunami_marks(ui, view, quakes, user))
    return render.Column(children = [bousai_map_frame(ui, view, layers), tsunami_legend(ui, items)])

def tsunami_area_pages(ui, items, tz, region, dist, budget):
    """Two-row entries for the regions most relevant to you, as many as fit in `budget` pages."""
    ordered = sorted(items, key = lambda it: (0 if it["code"] == region else 1, -it["sev"], dist.get(it["code"], 99999.0)))
    entries = [tsunami_entry(ui, it, tz) for it in ordered]
    k = len(entries)
    for _ in range(len(entries)):
        rows = entries[:k]
        if k < len(entries):
            rows = rows + [tsunami_row_text(ui, "+%d more regions" % (len(entries) - k), ui["muted"])]
        pages = bousai_quake_pack(rows, None, None)
        if k < len(entries) and len(pages) > 1 and len(pages[-1]["rows"]) == 1:
            pages = bousai_quake_pack(entries[:k], None, None)
        if len(pages) <= budget or k <= 1:
            return pages
        k -= 1
    return bousai_quake_pack(entries[:1], None, None)

def tsunami_observed_pages(ui, state, tz):
    """Strongest tide-gauge readings (coastal first, then one offshore)."""
    rows = [tsunami_obs_row(ui, o, False) for o in state["observed"][:2 if len(state["offshore"]) > 0 else 3]]
    rows.extend([tsunami_obs_row(ui, o, True) for o in state["offshore"][:1]])
    if len(rows) == 0:
        return []
    title = "Observed"
    if state["info_time"] != None:
        title = "Observed " + bousai_hhmm(state["info_time"], tz)
    head = (ui["line_h"], lambda f: bousai_header(ui, title, frames = f))
    return bousai_quake_pack(rows, head, None if ui["size"] == "xlarge" else head)[:1]

def tsunami_tide_pages(ui, state, loc, tz):
    """First wave and high tide at the tide gauge nearest you (needs JMA's arrival / high tide report)."""
    best = None
    best_km = 150.0
    for it in state["stations"]:
        for s in it["stations"]:
            if s["lat"] == None:
                continue
            km = bousai_distance_km(loc["lat"], loc["lon"], s["lat"], s["lon"])
            if km < best_km:
                best, best_km = s, km
    if best == None:
        return []
    first = bousai_hhmm(best["arrival"], tz) if best["arrival"] != None else (best["cond"] or "-")
    high = bousai_hhmm(best["high_tide"], tz) if best["high_tide"] != None else "-"
    rows = [
        tsunami_row_text(ui, best["name_en"]),
        tsunami_row_text(ui, "1st wave " + first, ui["muted"]),
        tsunami_row_text(ui, "High tide " + high, ui["muted"]),
    ]
    head = (ui["line_h"], lambda f: bousai_header(ui, "Tide gauge", frames = f))
    return bousai_quake_pack(rows, head, None if ui["size"] == "xlarge" else head)[:1]

def tsunami_idle_pages(ui, state, tz):
    rows = [tsunami_row_text(ui, l) for l in bousai_quake_name_lines(ui, "No warning or advisory")]
    last = state["last"] if state != None else None
    if last != None and state["issued"] != None:
        rows.append(tsunami_row_text(ui, "Last " + bousai_mdhm(state["issued"], tz), ui["muted"]))
        rows.append(tsunami_row_text(ui, last["title_en"], ui["muted"]))
        rows.append(tsunami_row_text(ui, last["quake_en"] + (" M" + last["mag"] if last["mag"] else ""), ui["muted"]))
    head = (ui["line_h"], lambda f: bousai_header(ui, "Tsunami", frames = f))
    return bousai_quake_pack(rows, head, None if ui["size"] == "xlarge" else head)

# ---------------------------------------------------------------------------

def tsunami_build(ui, config, state):
    """The app output for a tsunami state (None: JMA feed unavailable): pages, an idle card, or [] to be skipped."""
    loc = bousai_location(config)
    tz = loc["tz"]
    show_idle = bousai_bool(config, "show_idle", False)
    min_sev = tsunami_int(config, "min_level", 1)

    if state == None:
        if show_idle:
            return bousai_message(ui, "Tsunami", ["JMA tsunami feed", "unavailable", "Retrying soon"], ui["sev"][2])
        return []
    items = [it for it in state["items"] if it["sev"] >= min_sev]
    if len(items) == 0:
        if not show_idle:
            return []
        return bousai_root(ui, bousai_quake_render(tsunami_idle_pages(ui, state, tz)))

    coast = bousai_tsunami_coast()
    dist = bousai_tsunami_distances(coast, loc["lat"], loc["lon"]) if coast != None else {}
    region, km = bousai_tsunami_nearest(dist)
    near = region != None and km <= TSUNAMI_FAR_KM
    user = {"lat": loc["lat"], "lon": loc["lon"]} if near else None

    pages = tsunami_status_pages(ui, state, items, region, km, tz)
    points = tsunami_points(items, coast) if coast != None else []
    if len(points) > 0:
        pages.append({"full": lambda f: tsunami_map(ui, items, coast, state["quakes"], user, points)})
    tail = tsunami_observed_pages(ui, state, tz)
    if near:
        tail = tail + tsunami_tide_pages(ui, state, loc, tz)
    budget = max(1, TSUNAMI_MAX_PAGES - len(pages) - len(tail))
    pages.extend(tsunami_area_pages(ui, items, tz, region if near else None, dist if near else {}, budget))
    pages.extend(tail)
    return bousai_root(ui, bousai_quake_render(pages[:TSUNAMI_MAX_PAGES]))

def main(config):
    ui = bousai_ui(config)
    state = tsunami_demo_state() if bousai_bool(config, "demo", False) else bousai_tsunami_state()
    return tsunami_build(ui, config, state)

def get_schema():
    return bousai_schema([
        schema.Dropdown(
            id = "min_level",
            name = "Minimum level",
            desc = "Skip tsunami information below this grade. Forecast means slight sea-level change expected, no damage.",
            icon = "water",
            default = "1",
            options = [
                schema.Option(display = "Forecast and up (all)", value = "1"),
                schema.Option(display = "Advisory and up", value = "2"),
                schema.Option(display = "Warning and up", value = "3"),
                schema.Option(display = "Major Tsunami Warning only", value = "5"),
            ],
        ),
        schema.Toggle(
            id = "show_idle",
            name = "Show when idle",
            desc = "Show a calm card with the last JMA report when nothing is in effect. Off: the app skips itself, so enable AutoPin in Tronbyt to let a warning take over the display.",
            icon = "toggleOn",
            default = False,
        ),
        schema.Toggle(
            id = "demo",
            name = "Show sample alert",
            desc = "Show the 2024-01-01 Noto Peninsula Major Tsunami Warning (Ishikawa Noto, warnings along the Sea of Japan coast) as an embedded sample.",
            icon = "flask",
            default = False,
        ),
    ])
