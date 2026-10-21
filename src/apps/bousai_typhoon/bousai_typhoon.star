"""
Applet: Bousai Typhoon
Summary: JMA typhoon track and forecast
Description: Typhoon analysis and 5-day forecast from the Japan Meteorological Agency: category, pressure, wind, movement, position, distance from you and the forecast track on a map.
Author: Bousai Apps
"""

# bousai: requires core map mapdata typhoon

load("math.star", "math")
load("render.star", "canvas", "render")
load("schema.star", "schema")

TEXT_FRAMES = 24
NOW_FRAMES = 18
STEP_FRAMES = 14

# JMA anchor cities that join the map fit when the track passes near them.
JAPAN_ANCHORS = [(26.2, 127.7), (31.6, 130.6), (34.7, 135.5), (35.7, 139.7), (38.3, 140.9), (43.1, 141.4)]

def to_int(v, default):
    if v == None or not str(v).isdigit():
        return default
    return int(v)

def rows_per_page(ui, header = True):
    return max(1, canvas.height() // ui["line_h"] - (1 if header else 0))

def fit_text(ui, candidates):
    """First candidate that fits one line, else the last (it scrolls)."""
    for c in candidates:
        if bousai_text_width(ui, c) <= canvas.width():
            return c
    return candidates[0]

def text_rows(ui, text, color):
    """Word-wrapped lines when they fit one page, else a single scrolling line."""
    lines = bousai_typhoon_wrap(ui, text, canvas.width())
    if len(lines) <= rows_per_page(ui):
        return [(l, color) for l in lines]
    return [(text, color)]

def chunk_pages(ui, head_fn, rows, base):
    """[(page, frames)]: header band plus rows; with large text only the first page keeps the band."""
    per_h = rows_per_page(ui)
    keep = per_h >= 3
    per_n = per_h if keep else rows_per_page(ui, False)
    groups = [rows[:per_h]]
    for i in range(per_h, len(rows), per_n):
        groups.append(rows[i:i + per_n])
    out = []
    for i, group in enumerate(groups):
        frames = bousai_typhoon_scroll_frames(ui, group, base)
        head = head_fn(frames) if (i == 0 or keep) else None
        out.append((bousai_typhoon_page(ui, head, group, frames), frames))
    return out

# ---------------------------------------------------------------------------
# Formatting

def wind_text(ms, kt, unit):
    if ms == None:
        return ""
    if unit == "kt":
        return "%dkt" % (kt if kt != None else int(ms * 1.944 + 0.5))
    if unit == "kmh":
        return "%dkm/h" % int(ms * 3.6 + 0.5)
    return "%dm/s" % ms

def position_text(lat, lon):
    return "%s%s %s%s" % (bousai_fixed(abs(lat), 1), "N" if lat >= 0 else "S", bousai_fixed(abs(lon), 1), "E" if lon >= 0 else "W")

def move_text(ui, t):
    if t["speed_kmh"] != None and t["course_en"]:
        return fit_text(ui, ["Moving %s %dkm/h" % (t["course_en"], t["speed_kmh"]), "Moves %s %dkm/h" % (t["course_en"], t["speed_kmh"]), "%s %dkm/h" % (t["course_en"], t["speed_kmh"])])
    if t["speed_word"]:
        return (t["speed_word"] + " " + t["course_en"]).strip()
    return "Movement unknown"

def category_text(ui, t):
    cands = [t["category_en"]]
    if t["cat"] == "TY" and t["intensity_en"]:
        cands.append(t["intensity_en"] + " TY")
    elif t["cat"] == "STS":
        cands.append("Severe TS")
    cands.append(t["cat"])
    return fit_text(ui, cands)

def title_text(t):
    num = "No.%d" % t["number"] if t["number"] else t["cat"]
    return "%s %s" % (num, t["name_en"] or t["tc_id"])

# ---------------------------------------------------------------------------
# Text pages

def pages_info(ui, t, unit, tz, show_dist, loc):
    """Identity card, then movement / position / distance, then size and radii."""
    wind = wind_text(t["wind_ms"], t["wind_kt"], unit)
    gust = wind_text(t["gust_ms"], t["gust_kt"], unit)
    rows = [(category_text(ui, t), ui["fg"])]
    rows.append((("%dhPa %s" % (t["pressure_hpa"], wind)).strip() if t["pressure_hpa"] else wind, ui["fg"]))
    if gust:
        rows.append(("Gust %s" % gust, ui["fg"]))
    rows.append((move_text(ui, t), ui["fg"]))
    rows.append((position_text(t["lat"], t["lon"]), ui["fg"]))
    if show_dist:
        rows.append((fit_text(ui, ["%dkm %s of you" % (t["distance_km"], t["bearing"]), "%dkm %s" % (t["distance_km"], t["bearing"])]), ui["muted"]))
    if t["storm_km"]:
        rows.append(("Storm radius %dkm" % max([k for _, k in t["storm_km"]]), ui["muted"]))
    if t["gale_km"]:
        rows.append(("Gale radius %dkm" % max([k for _, k in t["gale_km"]]), ui["muted"]))
    if t["scale_en"]:
        rows.append(("Size: %s" % t["scale_en"], ui["muted"]))
    closest = bousai_typhoon_closest(t, loc)
    if show_dist and closest != None and closest[0] < t["distance_km"] and closest[0] <= 800:
        rows.append((fit_text(ui, ["Closest %dkm in %dh" % closest, "Near %dkm %dh" % closest]), ui["muted"]))
    rows.append(("Issued %s" % bousai_hhmm(t["issued"], tz), ui["muted"]))
    band = bousai_sev_color(ui, t["sev"])
    return chunk_pages(ui, lambda fr: bousai_header(ui, title_text(t), band, None, fr), rows, TEXT_FRAMES)

# ---------------------------------------------------------------------------
# Map frames

def anchor_points(items):
    """Japan anchors near the track, so land stays visible."""
    pts = []
    for a in JAPAN_ANCHORS:
        for s in items:
            if bousai_distance_km(a[0], a[1], s["lat"], s["lon"]) < 600:
                pts.append(a)
                break
    return pts

def map_view(t, items, loc, mh):
    """One view for every frame of a typhoon: track, probability circles, nearby Japan and you."""
    pts = []
    for i, s in enumerate(items):
        pts.append((s["lat"], s["lon"]))
        r = s.get("radius_km") or 0
        if i == 0 and s.get("storm_km"):
            r = max([d for _, d in s["storm_km"]])
        if r:
            dlat = r / 111.2
            dlon = r / (111.2 * max(0.2, math.cos(math.radians(s["lat"]))))
            pts.extend([(s["lat"] + dlat, s["lon"]), (s["lat"] - dlat, s["lon"]), (s["lat"], s["lon"] + dlon), (s["lat"], s["lon"] - dlon)])
    for p in t["past"]:
        if bousai_distance_km(p[0], p[1], t["lat"], t["lon"]) <= 900:
            pts.append((p[0], p[1]))
    pts.extend(anchor_points(items))
    near_user = False
    for s in items:
        if bousai_distance_km(loc["lat"], loc["lon"], s["lat"], s["lon"]) < 1500:
            near_user = True
            break
    if near_user:
        pts.append((loc["lat"], loc["lon"]))
    return bousai_view_fit(pts, canvas.width(), mh, pad = 4, min_zoom = 0.3, max_zoom = 5.5)

def project_ring(view, ring):
    return [bousai_view_xy(view, p[0], p[1]) for p in ring]

def line_layers(view, pts, color):
    """Line chain through [(lat, lon)] points; segments wholly outside the view are skipped."""
    out = []
    xy = [bousai_view_xy(view, p[0], p[1]) for p in pts]
    w = view["w"]
    h = view["h"]
    for i in range(len(xy) - 1):
        a = xy[i]
        b = xy[i + 1]
        if a == b or (a[0] < 0 and b[0] < 0) or (a[1] < 0 and b[1] < 0) or (a[0] >= w and b[0] >= w) or (a[1] >= h and b[1] >= h):
            continue
        out.append(bousai_typhoon_line(a, b, color))
    return out

def footer_row(ui, step, label, unit, frames):
    """[CAT chip] label wind  — one line on the panel colour."""
    fh = bousai_font_height(ui)
    color = bousai_sev_color(ui, step["sev"])
    chip_text = step["cat"] or "TC"
    chip_w = bousai_text_width(ui, chip_text) + 2
    wind = wind_text(step["wind_ms"], step["wind_kt"], unit)
    text = ("%s %s" % (label, wind)).strip()
    chip = render.Box(width = chip_w, height = fh, color = color, child = bousai_text(ui, chip_text, bousai_on(color)))
    body = bousai_fit(ui, text, width = canvas.width() - chip_w - 2, color = ui["fg"], frames = frames)
    return render.Box(width = canvas.width(), height = ui["line_h"], color = ui["panel"], child = render.Row(cross_align = "center", children = [render.Padding(pad = (1, 0, 0, 0), child = chip), render.Padding(pad = (1, 0, 0, 0), child = body)]))

def frame_map(ui, t, items, k, view, loc, unit, frames):
    """Map with the past track, forecast line up to item k, its circle and a status footer."""
    step = items[k]
    layers = [bousai_basemap(ui, view, "pacific")]
    if view["zoom"] >= 1.8:
        layers.append(bousai_basemap(ui, view, "japan"))
    if t["past"]:
        layers.extend(line_layers(view, t["past"], ui["muted"]))
    color = bousai_sev_color(ui, step["sev"])
    if k == 0:
        if t["gale_circle"]:
            g = t["gale_circle"]
            ring = project_ring(view, bousai_typhoon_circle(g[0], g[1], g[2], 28))
            layers.append(bousai_typhoon_polygon(ring, ui["muted"] + "30", ui["muted"]))
        if t["storm_km"]:
            km = max([d for _, d in t["storm_km"]])
            ring = project_ring(view, bousai_typhoon_circle(step["lat"], step["lon"], km, 20))
            layers.append(bousai_typhoon_polygon(ring, color + "60", color))
    else:
        if step["radius_km"]:
            ring = project_ring(view, bousai_typhoon_circle(step["lat"], step["lon"], step["radius_km"], 20))
            layers.append(bousai_typhoon_polygon(ring, color + "50", color))
    layers.extend(line_layers(view, [(s["lat"], s["lon"]) for s in items[:k + 1]], ui["fg"]))
    for i, s in enumerate(items[:k + 1]):
        if i < k:
            layers.append(bousai_marker(ui, view, s["lat"], s["lon"], ui["fg"], 1))
    layers.append(bousai_marker(ui, view, step["lat"], step["lon"], color, 3))
    layers.append(bousai_cross(ui, view, loc["lat"], loc["lon"], ui["accent"], 2))
    label = "Now" if k == 0 else "+%dh" % step["hours"]
    return render.Column(children = [bousai_map_frame(ui, view, layers), footer_row(ui, step, label, unit, frames)])

def frames_map(ui, t, loc, unit, steps_mode):
    """[(widget, frames, priority)] for the 'Now' frame and the forecast steps."""
    wanted = []
    last = 0
    for s in t["steps"]:
        if steps_mode == "all" or (s["hours"] >= 24 and s["hours"] - last >= 20):
            wanted.append(s)
            last = s["hours"]
    items = [t] + wanted
    view = map_view(t, items, loc, canvas.height() - ui["line_h"])
    # Drop order when time is short: keep the farthest, middle and first steps longest.
    n = len(wanted)
    rank = {}
    for idx in [n, (n + 1) // 2, 1]:
        if idx >= 1 and idx not in rank:
            rank[idx] = 3 + len(rank)
    for idx in range(1, n + 1):
        if idx not in rank:
            rank[idx] = 3 + len(rank)
    out = []
    for k in range(len(items)):
        fr = NOW_FRAMES if k == 0 else STEP_FRAMES
        out.append((frame_map(ui, t, items, k, view, loc, unit, fr), fr, 1 if k == 0 else rank[k]))
    return out

# ---------------------------------------------------------------------------
# Assembly

def typhoon_pages(ui, t, loc, tz, unit, steps_mode, share, show_dist):
    """Pages for one typhoon within `share` frames: [(widget, frames)] in display order."""
    info = pages_info(ui, t, unit, tz, show_dist, loc)
    maps = frames_map(ui, t, loc, unit, steps_mode)
    # (display order, priority, widget, frames)
    items = []
    order = 0
    for i, p in enumerate(info):
        items.append((order, 0 if i == 0 else (2 if i == 1 else 8), p[0], p[1]))
        order += 1
    for m in maps:
        items.append((order, m[2], m[0], m[1]))
        order += 1
    chosen = []
    total = 0
    for it in sorted(items, key = lambda i: (i[1], i[0])):
        if chosen and total + it[3] > share:
            continue
        chosen.append(it)
        total += it[3]
    return [(c[2], c[3]) for c in sorted(chosen, key = lambda i: i[0])]

def sequence(pages):
    return render.Sequence(children = [bousai_hold(p[0], p[1]) for p in pages])

def main(config):
    ui = bousai_ui(config)
    loc = bousai_location(config)
    tz = loc["tz"]
    demo = bousai_bool(config, "demo", False)
    show_idle = bousai_bool(config, "show_idle", False)
    unit = config.get("wind_unit") or "ms"
    steps_mode = config.get("steps") or "daily"
    count = max(1, min(4, to_int(config.get("count"), 3)))
    budget = canvas.max_duration_ms() // ui["delay"]

    typhoons = bousai_typhoon_demo(config) if demo else bousai_typhoon_list(config)
    if typhoons == None or not typhoons:
        if not show_idle:
            return []
        rows = text_rows(ui, "JMA typhoon data is unavailable" if typhoons == None else "No active typhoon", ui["fg"])
        rows.append(("Checked %s" % bousai_hhmm(bousai_now(), tz), ui["muted"]))
        return bousai_root(ui, sequence(chunk_pages(ui, lambda fr: bousai_header(ui, "TYPHOON", None, None, fr), rows, TEXT_FRAMES)[:3]))

    typhoons = typhoons[:count]
    share = budget // len(typhoons)
    pages = []
    for t in typhoons:
        show_dist = t["distance_km"] != None
        pages.extend(typhoon_pages(ui, t, loc, tz, unit, steps_mode, share, show_dist))
    return bousai_root(ui, sequence(pages))

def get_schema():
    return bousai_schema([
        schema.Toggle(
            id = "show_idle",
            name = "Show when idle",
            desc = "Show a calm card while no typhoon is active. Off skips the app, so it only appears for a typhoon (use with Tronbyt AutoPin).",
            icon = "bell",
            default = False,
        ),
        schema.Dropdown(
            id = "wind_unit",
            name = "Wind unit",
            desc = "Unit for maximum wind and gusts.",
            icon = "wind",
            default = "ms",
            options = [
                schema.Option(display = "Metres per second", value = "ms"),
                schema.Option(display = "Knots", value = "kt"),
                schema.Option(display = "Kilometres per hour", value = "kmh"),
            ],
        ),
        schema.Dropdown(
            id = "steps",
            name = "Forecast steps",
            desc = "Which forecast times to animate on the track map.",
            icon = "clock",
            default = "daily",
            options = [
                schema.Option(display = "Daily (24, 48, 72, 96, 120 h)", value = "daily"),
                schema.Option(display = "All JMA forecast times", value = "all"),
            ],
        ),
        schema.Dropdown(
            id = "count",
            name = "Typhoons shown",
            desc = "How many active typhoons to cycle through, nearest to you first.",
            icon = "hurricane",
            default = "3",
            options = [schema.Option(display = "Nearest %d" % n if n > 1 else "Nearest only", value = str(n)) for n in (1, 2, 3, 4)],
        ),
        schema.Toggle(
            id = "demo",
            name = "Show sample alert",
            desc = "Show a sample modelled on Typhoon No. 10 (Shanshan) of August 2024 near Kyushu instead of live data.",
            icon = "play",
            default = False,
        ),
    ])
