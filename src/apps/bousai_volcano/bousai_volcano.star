"""
Applet: Bousai Volcano
Summary: JMA volcano levels and ash
Description: Volcanic Alert Levels, eruption flash reports and ashfall forecasts from the Japan Meteorological Agency.
Author: Bousai Apps
"""

# bousai: requires core map data mapdata volcano

load("render.star", "canvas", "render")
load("schema.star", "schema")
load("time.star", "time")

TEXT_FRAMES = 24
LIST_FRAMES = 20
MAP_FRAMES = 26
FLASH_FRAMES = 32
ASH_FRAMES = 20

def to_int(v, default):
    if v == None or not str(v).isdigit():
        return default
    return int(v)

def rows_per_page(ui, header = True):
    return max(1, canvas.height() // ui["line_h"] - (1 if header else 0))

def km_text(v):
    return "%dkm" % v["distance_km"]

def short_name(name):
    """'Kirishimayama (Shinmoedake)' -> 'Shinmoedake' for tight spaces."""
    if "(" in name:
        inner = name.split("(")[1].rstrip(")").strip()
        if inner:
            return inner
    return name

def fit_text(ui, candidates):
    """First candidate that fits one line, else the last (it scrolls)."""
    for c in candidates:
        if bousai_text_width(ui, c) <= canvas.width():
            return c
    return candidates[-1]

def text_rows(ui, text, color):
    """Word-wrapped lines when they fit one page, else a single scrolling line."""
    lines = bousai_volcano_wrap(ui, text, canvas.width())
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
        frames = bousai_volcano_scroll_frames(ui, group, base)
        head = head_fn(frames) if (i == 0 or keep) else None
        out.append((bousai_volcano_page(ui, head, group, frames), frames))
    return out

# ---------------------------------------------------------------------------
# Text pages

def pages_flash(ui, f, state, show_dist, tz):
    """Alert-style eruption flash report card: ([(page, frames)] always shown, [(page, frames)] if time allows)."""
    title = "ERUPTION NOTICE"
    if bousai_text_width(ui, title) > canvas.width() - 2:
        title = "ERUPTION"
    rows = [(f["name_en"], ui["fg"]), (f["text_en"], ui["fg"])]
    rows.append(("%s %s ago" % (bousai_hhmm(f["time"], tz), bousai_ago(f["time"])), ui["muted"]))
    more = []
    if state != None:
        more.extend(text_rows(ui, "Now %s: %s" % (state["label"], state["short_en"]), ui["muted"]))
    elif show_dist:
        more.append((fit_text(ui, ["%s %s of you" % (km_text(f), f["bearing"]), "%s %s" % (km_text(f), f["bearing"])]), ui["muted"]))

    band = lambda fr: bousai_blink(ui, bousai_header(ui, title, bousai_sev_color(ui, 4), None, fr), canvas.width(), ui["line_h"], 6, 3)
    extra = chunk_pages(ui, band, more, FLASH_FRAMES) if more else []
    return chunk_pages(ui, band, rows, FLASH_FRAMES), extra

def pages_headline(ui, v, places, show_dist, tz):
    """Card for the most severe volcano: level, keyword, distance, since when and where."""
    rows = text_rows(ui, v["short_en"], ui["fg"])
    if show_dist:
        rows.append((fit_text(ui, ["%s %s of you" % (km_text(v), v["bearing"]), "%s %s" % (km_text(v), v["bearing"])]), ui["muted"]))
    since = bousai_mdhm(v["issued"], tz)
    if v["cond_en"] in ("Raised", "Lowered") and v["prev_label"]:
        rows.extend(text_rows(ui, "%s from %s on %s" % (v["cond_en"], v["prev_label"], since), ui["muted"]))
    else:
        rows.extend(text_rows(ui, "In effect since %s" % since, ui["muted"]))
    if places:
        rows.append((", ".join(places[:3]), ui["muted"]))
    title = "%s %s" % (v["label"], v["name_en"])
    return chunk_pages(ui, lambda fr: bousai_header(ui, title, bousai_sev_color(ui, v["sev"]), None, fr), rows, TEXT_FRAMES)

def pages_calm(ui, sentence, near, show_dist):
    """Calm card: nothing at or above the chosen level."""
    rows = text_rows(ui, sentence, ui["fg"])
    n = near[0]
    if show_dist:
        rows.append(("Nearest: %s %s %s (%s)" % (short_name(n["name_en"]), km_text(n), n["bearing"], n["label"]), ui["muted"]))
    else:
        rows.append(("Location is outside Japan", ui["muted"]))
    return chunk_pages(ui, lambda fr: bousai_header(ui, "VOLCANO", None, None, fr), rows, TEXT_FRAMES)

def list_row(ui, v, badge_w):
    """[Lv] name; names too long for the row step through within the page time."""
    color = bousai_sev_color(ui, v["sev"])
    badge = render.Box(width = badge_w, height = bousai_font_height(ui), color = color, child = bousai_text(ui, v["label"], bousai_on(color)))
    name = bousai_fit(ui, short_name(v["name_en"]), width = canvas.width() - badge_w - 1, color = ui["fg"], frames = LIST_FRAMES)
    return render.Row(cross_align = "center", children = [badge, render.Padding(pad = (1, 0, 0, 0), child = name)])

def pages_list(ui, states, min_sev, max_pages):
    """Ranked list pages: [Lv] name, severest first. Only the first page carries the title band."""
    first = rows_per_page(ui)
    rest = rows_per_page(ui, False)
    titled = first >= 2
    if not titled:
        first = rest
    cap = first + rest * (max_pages - 1)
    shown = states
    more = 0
    if len(states) > cap:
        shown = states[:cap - 1]
        more = len(states) - len(shown)
    badge_w = 0
    for v in shown:
        badge_w = max(badge_w, bousai_text_width(ui, v["label"]) + 2)
    rows = [list_row(ui, v, badge_w) for v in shown]
    if more:
        rows.append(("+%d more" % more, ui["muted"]))
    groups = [rows[:first]]
    for i in range(first, len(rows), rest):
        groups.append(rows[i:i + rest])
    pages = []
    for i, group in enumerate(groups):
        head = None
        if i == 0 and titled:
            head = bousai_header(ui, "VOLCANO Lv%d+" % min_sev, None, str(len(states)), LIST_FRAMES)
        pages.append(bousai_volcano_page(ui, head, group, LIST_FRAMES))
    return pages

# ---------------------------------------------------------------------------
# Map pages

def legend_row(ui, groups, total):
    """Footer chips: coloured label + count, as many as fit."""
    w = canvas.width()
    fh = bousai_font_height(ui)
    children = []
    used = 0
    for g in groups:
        chip_w = bousai_text_width(ui, g[0]) + 2
        count = str(g[2])
        need = chip_w + bousai_text_width(ui, count) + 3
        if used + need > w:
            break
        color = bousai_sev_color(ui, g[1])
        children.append(render.Box(width = chip_w, height = fh, color = color, child = bousai_text(ui, g[0], bousai_on(color))))
        children.append(render.Padding(pad = (1, 0, 2, 0), child = bousai_text(ui, count, ui["fg"])))
        used += need
    if not children:
        children = [bousai_text(ui, "%d volcanoes" % total, ui["fg"])]
    return render.Box(width = w, height = ui["line_h"], color = ui["panel"], child = render.Row(cross_align = "center", expanded = True, children = children))

def level_groups(states):
    """[(label, sev, count)] severest first."""
    seen = {}
    for s in states:
        if s["label"] not in seen:
            seen[s["label"]] = [s["label"], s["sev"], 0]
        seen[s["label"]][2] += 1
    return sorted(seen.values(), key = lambda g: (-g[1], 0 if g[0].startswith("Lv") else 1, g[0]))

def ring(x, y, r, color):
    return bousai_volcano_polygon([(x - r, y - r), (x + r, y - r), (x + r, y + r), (x - r, y + r)], None, color)

def page_map(ui, qualifying, near, states, loc, show_user, footer):
    """Japan map: all volcanoes as dots, level-sized markers, nearest ringed, your location."""
    w = canvas.width()
    mh = canvas.height() - ui["line_h"]
    pts = [(v["lat"], v["lon"]) for v in qualifying]
    if show_user:
        pts.append((loc["lat"], loc["lon"]))
    if len(pts) < 2:
        pts.extend([(n["lat"], n["lon"]) for n in near[:2]])
    view = bousai_view_fit(pts, w, mh, pad = 5, min_zoom = 0.6, max_zoom = 5.0)
    layers = [bousai_basemap(ui, view, "japan")]
    listed = {}
    for v in states:
        listed[v["code"]] = True
    if view["zoom"] >= 2.0:
        for code, row in BOUSAI_VOLCANOES.items():
            if code in listed:
                continue
            x, y = bousai_view_xy(view, row[1], row[2])
            if bousai_in_view(view, x, y):
                layers.append(bousai_place(x, y, render.Box(width = 1, height = 1, color = ui["muted"])))
    ux, uy = bousai_view_xy(view, loc["lat"], loc["lon"])
    if show_user:
        for i, n in enumerate(near):
            x, y = bousai_view_xy(view, n["lat"], n["lon"])
            if bousai_in_view(view, x, y) and abs(x - ux) + abs(y - uy) >= 6:
                layers.append(ring(x, y, 3, ui["fg"] if i == 0 else ui["muted"]))
    marked = {}
    for v in qualifying:
        marked[v["code"]] = True
    for v in states:
        if v["code"] not in marked:
            layers.append(bousai_marker(ui, view, v["lat"], v["lon"], ui["muted"], 1))
    for v in reversed(qualifying):
        layers.append(bousai_marker(ui, view, v["lat"], v["lon"], bousai_sev_color(ui, v["sev"]), 1 + max(1, v["sev"])))
    if show_user:
        layers.append(bousai_cross(ui, view, loc["lat"], loc["lon"], ui["fg"], 2))
    return render.Column(children = [bousai_map_frame(ui, view, layers), footer])

def text_footer(ui, text, frames):
    return render.Box(width = canvas.width(), height = ui["line_h"], color = ui["panel"], child = bousai_fit(ui, text, color = ui["fg"], frames = frames))

# ---------------------------------------------------------------------------
# Ashfall pages

def ash_color(ui, code):
    if code == "73":
        return ui["sev"][3]
    if code == "72":
        return ui["sev"][2]
    return ui["fg"]

def range_text(win, tz, kind):
    if kind == "scheduled":
        return "%s-%sh" % (win["start"].in_location(tz).format("15"), win["end"].in_location(tz).format("15"))
    return "to " + bousai_hhmm(win["end"], tz)

def frame_ash(ui, fc, wins, view, loc, row2):
    """Ash polygons of the given windows over a map centred on the crater, with a 1-2 line footer."""
    w = canvas.width()
    layers = [bousai_basemap(ui, view, "japan")]
    hit = False
    for win in wins:
        hit = hit or win["ash_hit"] or win["cinder_hit"]
        for code, rings in win["layers"]:
            for r in rings:
                pts = [bousai_view_xy(view, p[0], p[1]) for p in r]
                if len(pts) >= 3:
                    layers.append(bousai_volcano_polygon(pts, ash_color(ui, code) + "60", ash_color(ui, code)))
        for r in win["cinders"]:
            pts = [bousai_view_xy(view, p[0], p[1]) for p in r]
            if len(pts) >= 3:
                layers.append(bousai_volcano_polygon(pts, ui["sev"][4] + "c0", ui["sev"][4]))
    layers.append(bousai_marker(ui, view, fc["lat"], fc["lon"], ui["fg"], 2))
    x, y = bousai_view_xy(view, loc["lat"], loc["lon"])
    if bousai_in_view(view, x, y):
        layers.append(bousai_cross(ui, view, loc["lat"], loc["lon"], ui["accent"], 2))
    band = bousai_sev_color(ui, 3) if hit else ui["panel"]
    color = bousai_on(band) if hit else ui["fg"]
    lines = []
    if ui["line_h"] <= 7:
        lines.append(render.Box(width = w, height = ui["line_h"], color = ui["panel"], child = render.Padding(pad = (1, 0, 0, 0), child = bousai_fit(ui, "ASH " + short_name(fc["name_en"]), width = w - 1, color = ui["fg"], frames = ASH_FRAMES))))
    lines.append(render.Box(width = w, height = ui["line_h"], color = band, child = render.Padding(pad = (1, 0, 0, 0), child = bousai_fit(ui, "May reach you" if hit else row2, width = w - 1, color = color, frames = ASH_FRAMES))))
    return render.Column(children = [bousai_map_frame(ui, view, layers)] + lines)

def pages_ash(ui, fc, tz, loc):
    """Map frames: all coming windows together, then the next scheduled window alone."""
    now = time.now()
    wins = [x for x in fc["windows"] if x["end"] != None and x["end"] >= now] or fc["windows"]
    if not wins:
        return []
    pts = [(fc["lat"], fc["lon"])]
    for win in wins:
        for _, rings in win["layers"]:
            for r in rings:
                pts.extend(r[::3])
        for r in win["cinders"]:
            pts.extend(r[::3])
    foot = ui["line_h"] * (2 if ui["line_h"] <= 7 else 1)
    view = bousai_view_fit(pts, canvas.width(), canvas.height() - foot, pad = 3, min_zoom = 3.0, max_zoom = 6.5)
    far = wins[0]
    for win in wins:
        if win["ash_km"] > far["ash_km"]:
            far = win
    out = [frame_ash(ui, fc, wins, view, loc, "Up to %dkm %s" % (far["ash_km"], far["ash_dir"]))]
    if fc["type"] == "scheduled" and len(wins) > 1:
        first = wins[0]
        out.append(frame_ash(ui, fc, [first], view, loc, "%s %s %dkm" % (range_text(first, tz, fc["type"]), first["ash_dir"], first["ash_km"])))
    return out

# ---------------------------------------------------------------------------
# Assembly

def schedule(pages, budget):
    """pages: [(widget, frames)] in priority order. Keeps what fits the animation budget."""
    kept = []
    total = 0
    for p in pages:
        if kept and total + p[1] > budget:
            continue
        kept.append(p)
        total += p[1]
    return render.Sequence(children = [bousai_hold(p[0], p[1]) for p in kept])

def main(config):
    ui = bousai_ui(config)
    loc = bousai_location(config)
    tz = loc["tz"]
    demo = bousai_bool(config, "demo", False)
    nationwide = (config.get("scope") or "nationwide") != "radius"
    radius = to_int(config.get("radius"), 300)
    min_sev = max(2, min(5, to_int(config.get("min_level"), 2)))
    flash_hours = to_int(config.get("flash_hours"), 6)
    alert_only = bousai_bool(config, "alert_only", False)
    show_map = bousai_bool(config, "show_map", True)
    show_ash = bousai_bool(config, "show_ash", True)
    budget = canvas.max_duration_ms() // ui["delay"]

    sample = bousai_volcano_demo(config) if demo else None
    if sample != None:
        states = sample["states"]
        reports = sample["flash"]
    else:
        states = bousai_volcano_status(config)
        reports = bousai_volcano_flash_reports()
    if states == None:
        if alert_only:
            return []
        return bousai_root(ui, schedule(chunk_pages(ui, lambda fr: bousai_header(ui, "VOLCANO", bousai_sev_color(ui, 2), None, fr), text_rows(ui, "JMA volcano data is unavailable", ui["muted"]), TEXT_FRAMES), budget))

    near = bousai_volcano_nearest(config, 3, states)
    show_dist = near[0]["distance_km"] <= 1500
    qualifying = [s for s in states if s["sev"] >= min_sev and (nationwide or s["distance_km"] <= radius)]
    by_code = {}
    for s in states:
        by_code[s["code"]] = s

    flash = []
    for f in reports:
        row = BOUSAI_VOLCANOES[f["code"]]
        f["distance_km"] = int(bousai_distance_km(loc["lat"], loc["lon"], row[1], row[2]) + 0.5)
        f["bearing"] = bousai_bearing_name(loc["lat"], loc["lon"], row[1], row[2])
        if f["age_minutes"] <= flash_hours * 60 and (nationwide or f["distance_km"] <= radius):
            flash.append(f)

    if not qualifying and not flash and alert_only:
        return []

    ash_pages = []
    ash_first = False
    if show_ash and (qualifying or flash):
        wanted = [f["code"] for f in flash] + [v["code"] for v in qualifying]
        forecasts = {}
        if sample != None:
            forecasts = sample["ash"]
        else:
            listed = bousai_volcano_ash_codes()
            for code in wanted:
                if code in listed:
                    forecasts[code] = bousai_volcano_ashfall(code, config)
                    break
        for code in wanted:
            fc = forecasts.get(code)
            if fc != None:
                frames_raw = pages_ash(ui, fc, tz, loc)
                ash_pages = [(p, ASH_FRAMES if len(frames_raw) > 1 else 28) for p in frames_raw]
                ash_first = fc["type"] != "scheduled"
                break

    pages = []
    tail = []
    for f in flash[:2]:
        card, extra = pages_flash(ui, f, by_code.get(f["code"]), show_dist, tz)
        pages.extend(card)
        tail.extend(extra)
    if ash_first:
        pages.extend(ash_pages)

    if qualifying:
        top = qualifying[0]
        if sample != None:
            places = ["Kagoshima City"] if top["code"] == "506" else []
        else:
            places = bousai_volcano_places(top["code"])
        headline = pages_headline(ui, top, places, show_dist, tz)
        pages.append(headline[0])
        tail.extend(headline[1:])
        if show_map:
            pages.append((page_map(ui, qualifying, near, states, loc, show_dist, legend_row(ui, level_groups(qualifying), len(qualifying))), MAP_FRAMES))
        if len(qualifying) > 1:
            for p in pages_list(ui, qualifying, min_sev, 3):
                pages.append((p, LIST_FRAMES))
    else:
        sentence = "No volcano above Lv%d %s" % (min_sev - 1, "nationwide" if nationwide else "within %dkm" % radius)
        pages.extend(pages_calm(ui, sentence, near, show_dist))
        if show_map:
            n = near[0]
            foot_text = "%s %s" % (short_name(n["name_en"]), km_text(n)) if show_dist else "Outside Japan"
            pages.append((page_map(ui, [], near, states, loc, show_dist, text_footer(ui, foot_text, MAP_FRAMES)), MAP_FRAMES))
    if not ash_first:
        pages.extend(ash_pages)

    return bousai_root(ui, schedule(pages + tail, budget))

def get_schema():
    return bousai_schema([
        schema.Dropdown(
            id = "scope",
            name = "Scope",
            desc = "Show volcanoes nationwide or only those within a radius of your location.",
            icon = "globe",
            default = "nationwide",
            options = [
                schema.Option(display = "Nationwide", value = "nationwide"),
                schema.Option(display = "Near my location", value = "radius"),
            ],
        ),
        schema.Dropdown(
            id = "radius",
            name = "Radius",
            desc = "Distance from your location used by 'Near my location'.",
            icon = "ruler",
            default = "300",
            options = [schema.Option(display = "%d km" % r, value = str(r)) for r in (100, 200, 300, 500, 1000)],
        ),
        schema.Dropdown(
            id = "min_level",
            name = "Minimum level",
            desc = "Lowest Volcanic Alert Level (or equivalent warning) to list.",
            icon = "volcano",
            default = "2",
            options = [
                schema.Option(display = "Level 2 and above", value = "2"),
                schema.Option(display = "Level 3 and above", value = "3"),
                schema.Option(display = "Level 4 and above", value = "4"),
            ],
        ),
        schema.Dropdown(
            id = "flash_hours",
            name = "Eruption notice duration",
            desc = "How long an eruption flash report stays on the display as an alert card.",
            icon = "clock",
            default = "6",
            options = [schema.Option(display = "%d hour%s" % (h, "" if h == 1 else "s"), value = str(h)) for h in (1, 3, 6, 24)],
        ),
        schema.Toggle(
            id = "show_ash",
            name = "Ashfall forecast",
            desc = "Show the JMA ashfall forecast map for the most important volcano.",
            icon = "smog",
            default = True,
        ),
        schema.Toggle(
            id = "show_map",
            name = "Map page",
            desc = "Show the Japan map with volcano markers coloured by level.",
            icon = "map",
            default = True,
        ),
        schema.Toggle(
            id = "alert_only",
            name = "Alert only",
            desc = "Skip this app while nothing qualifies, so it only appears for an alert. Use with Tronbyt AutoPin.",
            icon = "bellSlash",
            default = False,
        ),
        schema.Toggle(
            id = "demo",
            name = "Show sample alert",
            desc = "Show a sample modelled on the Sakurajima eruption of July 2022 instead of live data.",
            icon = "play",
            default = False,
        ),
    ])
