"""
Applet: Bousai Shake
Summary: Strong-motion monitor
Description: Real-time shaking from the NIED Kyoshin Monitor stations across Japan, with EEW overlays and P2PQuake shaking reports.
Author: Bousai Apps
"""

# bousai: requires core eew

load("filter.star", "filter")
load("math.star", "math")
load("render.star", "canvas", "render")
load("schema.star", "schema")

# Map column width; the rest of the 64 px is the text panel (after a 1 px divider).
MAP_W = 28

# Pixels per source pixel of the 352 x 400 Kyoshin images for the zoomed views (Japan fits the height).
VIEW_SCALE = {"region": 0.4, "local": 0.8}

# One replay image per second, looped over this many frames.
LOOP_FRAMES = 40

# Source-pixel boxes (x0, y0, x1, y1) that hide the header text (top left) and the NIED logo
# (bottom) printed into the Kyoshin images.
COVERS = [(0, 0, 240, 42), (140, 345, 352, 400)]

# NIED real-time intensity colour scale, -3 (quiet, blue) to 7 (dark red), as drawn on the map.
LEGEND = ["#0000cd", "#0046f0", "#00b4c8", "#2eb729", "#8abb09", "#dcdc00", "#ffd200", "#ff9600", "#ff4700", "#f60200", "#7a0000"]

def rnd(x):
    return int(math.floor(x + 0.5))

def fit_text(ui, options, width):
    for s in options:
        if bousai_text_width(ui, s) <= width:
            return s
    return options[-1]

def clock(t, tz, seconds = True):
    return t.in_location(tz).format("15:04:05" if seconds else "15:04") if t else "--:--"

# ---------------------------------------------------------------------------
# Map

def geometry(view, loc):
    """Scale and offset of the Kyoshin image inside the map column."""
    H = canvas.height()
    sw = BOUSAI_EEW_KMONI_W
    sh = BOUSAI_EEW_KMONI_H
    px, py = bousai_eew_kmoni_xy(loc["lat"], loc["lon"])
    inside = px >= 0 and px < sw and py >= 0 and py < sh
    s = H / float(sh)
    cx = sw / 2.0
    cy = sh / 2.0
    if view in VIEW_SCALE and inside:
        s = VIEW_SCALE[view]
        cx = px
        cy = py
    return {
        "s": s,
        "ox": MAP_W / 2.0 - cx * s,
        "oy": H / 2.0 - cy * s,
        "w": rnd(sw * s),
        "h": rnd(sh * s),
        "px": px,
        "py": py,
        "inside": inside,
        "arm": 2 if view in VIEW_SCALE and inside else 1,
    }

def at(g, x, y, child):
    """Place child with its top-left at source pixel (x, y) of the Kyoshin image."""
    return render.Padding(pad = (rnd(g["ox"] + x * g["s"]), rnd(g["oy"] + y * g["s"]), 0, 0), child = child)

def image(g, src):
    return render.Image(src = src, width = g["w"], height = g["h"])

def base_layer(ui, g, src):
    """NIED white base map: used as is on the light theme, inverted and dimmed (black sea) otherwise."""
    img = image(g, src)
    if ui["theme"] != "light":
        img = bousai_land_filter(ui, filter.Invert(child = img))
    return at(g, 0, 0, img)

def cover_layers(ui, g):
    return [at(g, c[0], c[1], render.Box(width = rnd((c[2] - c[0]) * g["s"]) + 1, height = rnd((c[3] - c[1]) * g["s"]) + 1, color = ui["bg"])) for c in COVERS]

def marker_layer(ui, g):
    """'+' on your location (haloed in high contrast)."""
    x = rnd(g["ox"] + g["px"] * g["s"])
    y = rnd(g["oy"] + g["py"] * g["s"])
    arm = g["arm"]
    kids = []
    if ui["frame"]:
        kids.append(render.Padding(pad = (x - arm - 1, y - 1, 0, 0), child = render.Box(width = 2 * arm + 3, height = 3, color = ui["bg"])))
        kids.append(render.Padding(pad = (x - 1, y - arm - 1, 0, 0), child = render.Box(width = 3, height = 2 * arm + 3, color = ui["bg"])))
    kids.append(render.Padding(pad = (x - arm, y, 0, 0), child = render.Box(width = 2 * arm + 1, height = 1, color = ui["fg"])))
    kids.append(render.Padding(pad = (x, y - arm, 0, 0), child = render.Box(width = 1, height = 2 * arm + 1, color = ui["fg"])))
    return render.Stack(children = kids)

def map_frames(ui, g, assets):
    """One map widget per replay image: base, EEW estimated intensity, shaking dots, covers, P/S circles, marker."""
    below = [base_layer(ui, g, assets["base"])] if assets["base"] else []
    if assets["est"]:
        below.append(at(g, 0, 0, image(g, assets["est"])))
    above = cover_layers(ui, g)
    if assets["ps"]:
        above.append(at(g, 0, 0, image(g, assets["ps"])))
    if g["inside"]:
        above.append(marker_layer(ui, g))
    out = []
    for src in assets["real"] or [None]:
        dots = [at(g, 0, 0, image(g, src))] if src else []
        out.append(render.Box(width = MAP_W, height = canvas.height(), color = ui["bg"], child = render.Stack(children = below + dots + above)))
    return out

# ---------------------------------------------------------------------------
# Text panel

def text_row(ui, text, color, width, frames):
    return render.Box(width = width, height = ui["line_h"], child = render.Padding(pad = (1, 0, 0, 0), child = bousai_fit(ui, text, width = width - 1, color = color, frames = frames)))

def panel_rows(ui, st, s, width, frames):
    """Rows (widgets of the line height) for the current state, most important first."""
    lh = ui["line_h"]
    fg = ui["fg"]
    muted = ui["muted"]
    rows = []
    if st["kind"] == "eew":
        ev = st["eew"]
        band = bousai_sev_color(ui, bousai_eew_sev(ev))
        label = fit_text(ui, ["EEW WARNING", "EEW WARN", "EEW!"] if ev["warn"] else ["EEW FORECAST", "EEW FCST", "EEW"], width - 2)
        head = render.Box(width = width, height = lh, color = band, child = render.Row(expanded = True, main_align = "start", cross_align = "center", children = [render.Padding(pad = (1, 0, 0, 0), child = bousai_text(ui, label, bousai_on(band)))]))
        rows.append(bousai_blink(ui, head, width, lh) if ev["warn"] else head)
        if st["r0"] != None:
            r = st["r0"] - s
            rows.append(text_row(ui, "S %ds" % int(math.ceil(r)) if r > 0 else "S arrived", fg if r > 10 else band, width, frames))
        rows.append(text_row(ui, "%s Max %s" % (bousai_eew_mag_text(ev["mag"]), ev["max_int"] or "?"), fg, width, frames))
        rows.append(text_row(ui, "Assumed epicentre" if ev["assumption"] else ev["epicenter_en"], muted, width, frames))
        return rows
    rows.append(text_row(ui, fit_text(ui, [st["clock"], st["clock"][:5]], width - 1), fg, width, frames))
    if st["kind"] == "shake":
        sh = st["shake"]
        rows.append(text_row(ui, fit_text(ui, ["SHAKING", "SHAKE"], width - 1), bousai_sev_color(ui, 2), width, frames))
        rows.append(text_row(ui, "P2P " + sh["confidence"], fg, width, frames))
        rows.append(text_row(ui, ", ".join(sh["areas_en"]) or "Area unknown", muted, width, frames))
        return rows
    rows.append(text_row(ui, "QUIET" if st["image"] else "NO IMAGE", muted, width, frames))
    rows.append(text_row(ui, "P2P none" if st["shake"] != None else "P2P down", muted, width, frames))
    rows.append(text_row(ui, "NIED Kyoshin Monitor", muted, width, frames))
    return rows

def panel_widget(ui, st, s, width, frames):
    H = canvas.height()
    n = max(1, (H - 4) // ui["line_h"])
    rows = panel_rows(ui, st, s, width, frames)[:n]
    legend = render.Padding(pad = (1, H - 3, 0, 0), child = render.Row(children = [render.Box(width = 3, height = 3, color = c) for c in LEGEND]))
    return render.Box(width = width, height = H, child = render.Stack(children = [
        render.Column(expanded = True, main_align = "start", cross_align = "start", children = rows),
        legend,
    ]))

def notice_card(ui, title, band, rows):
    """Full-screen notice: a header band and (text, color) rows inset 1 px so first glyphs are not clipped."""
    width = canvas.width()
    per_page = max(1, (canvas.height() - ui["line_h"]) // ui["line_h"])
    pages = (len(rows) + per_page - 1) // per_page
    frames = bousai_hold_frames(pages) if pages > 1 else bousai_budget_frames()
    return bousai_root(ui, bousai_pages(ui, (title, band), [text_row(ui, row[0], row[1], width, frames) for row in rows]))

def unreachable_card(ui, eew, shaking):
    """Shown when the Kyoshin Monitor cannot be read (down, or skipped for a while after a request that
    never finished). An active EEW is still reported, from the EEW feed."""
    if eew:
        ev = eew[0]
        rows = [
            ("%s Max %s" % (bousai_eew_mag_text(ev["mag"]), ev["max_int"] or "?"), ui["fg"]),
            ("Assumed epicentre" if ev["assumption"] else ev["epicenter_en"], ui["fg"]),
            ("NIED map unreachable", ui["muted"]),
        ]
        title = "EEW WARNING" if ev["warn"] else "EEW FORECAST"
        return notice_card(ui, title, bousai_sev_color(ui, bousai_eew_sev(ev)), rows)
    rows = [("NIED Kyoshin Monitor", ui["muted"]), ("is unreachable", ui["muted"])]
    if shaking != None and shaking["detected"]:
        rows.append(("P2P: shaking " + shaking["confidence"], ui["fg"]))
    return notice_card(ui, "KMONI", bousai_sev_color(ui, 2), rows)

# ---------------------------------------------------------------------------

def main(config):
    ui = bousai_ui(config)
    loc = bousai_location(config)
    tz = loc["tz"]
    only_alerts = bousai_bool(config, "only_when_shaking", False)

    # Alert sources first: Wolfx (one request when idle). While an EEW is active the panel shows it, so the
    # stall-prone P2PQuake request (shaking reports) is skipped then.
    polled = bousai_eew_poll(config)
    eew = [ev for ev in polled["events"] if not ev["cancel"]]
    shaking = None if eew else bousai_eew_shaking()
    shaken = shaking != None and shaking["detected"]
    if only_alerts and not eew and not shaken:
        return []

    now_t, stamp = bousai_eew_kmoni_now()
    if now_t == None:
        return unreachable_card(ui, eew, shaking)

    pick = config.get("replay") or "4"
    replay = max(1, min(8, int(pick))) if pick.isdigit() else 4
    assets = {"base": bousai_eew_fetch("kmoni", bousai_eew_kmoni_url("base_w"), 86400), "real": [], "est": None, "ps": None}
    for back in range(replay - 1, -1, -1):
        src = bousai_eew_fetch("kmoni", bousai_eew_kmoni_url("real", bousai_eew_kmoni_stamp(now_t, back)), 30)
        if src != None:
            assets["real"].append(src)
    if eew:
        assets["est"] = bousai_eew_fetch("kmoni", bousai_eew_kmoni_url("est", stamp), 2)
        assets["ps"] = bousai_eew_fetch("kmoni", bousai_eew_kmoni_url("ps", stamp), 2)

    g = geometry(config.get("view") or "japan", loc)
    maps = map_frames(ui, g, assets)

    st = {"kind": "quiet", "clock": clock(now_t, tz), "image": len(assets["real"]) > 0, "eew": None, "shake": shaking, "r0": None}
    if eew:
        st["kind"] = "eew"
        st["eew"] = eew[0]
        if eew[0]["s_arrival"] != None:
            st["r0"] = (eew[0]["s_arrival"] - polled["checked"]).seconds
    elif shaken:
        st["kind"] = "shake"

    width = canvas.width() - MAP_W - 1
    budget = bousai_budget_frames()
    count = len(maps)
    hold = max(1, LOOP_FRAMES // count)
    panels = {}
    built = {}
    frames = []
    for f in range(budget):
        idx = (f % LOOP_FRAMES) // hold % count if count > 1 else 0
        sec = f // 10 if st["r0"] != None else 0
        if sec not in panels:
            panels[sec] = panel_widget(ui, st, sec, width, budget)
        key = (idx, sec)
        if key not in built:
            built[key] = render.Row(children = [maps[idx], render.Box(width = 1, height = canvas.height(), color = ui["faint"]), panels[sec]])
        frames.append(built[key])
    return bousai_root(ui, render.Animation(children = frames))

def get_schema():
    return bousai_schema([
        schema.Dropdown(
            id = "view",
            name = "Map view",
            desc = "Whole of Japan, or a window centred on your location (the NIED map covers Japan's main islands; elsewhere the whole map is shown).",
            icon = "map",
            default = "japan",
            options = [
                schema.Option(display = "Japan", value = "japan"),
                schema.Option(display = "Region around me (about 350 km)", value = "region"),
                schema.Option(display = "Local around me (about 170 km)", value = "local"),
            ],
        ),
        schema.Dropdown(
            id = "replay",
            name = "Replay",
            desc = "Loop the last few seconds of shaking, one NIED image per second. Longer replays fetch more images per update.",
            icon = "film",
            default = "4",
            options = [
                schema.Option(display = "Off (latest second only)", value = "1"),
                schema.Option(display = "Last 4 seconds", value = "4"),
                schema.Option(display = "Last 8 seconds", value = "8"),
            ],
        ),
        schema.Toggle(
            id = "only_when_shaking",
            name = "Only when shaking",
            desc = "Hide the app unless an EEW is active or P2PQuake users report shaking, so it takes over the display like an alert. Enable Tronbyt AutoPin.",
            icon = "bell",
            default = False,
        ),
    ])
