"""Shared helpers for the Bousai JMA tile-map apps (rain radar, thunder, tornado, snow, weather map, risk).

Every one of these apps draws JMA raster tiles around the configured location and animates them over a
time axis. This library owns what they share: zoom presets, the tile fetcher (with blank-tile detection),
frame composition (basemap, JMA mask, location marker, time label, "nothing here" banner), text and colour-key
pages, AMeDAS numbers for text cues, and the animation budget.

JMA tile colours are fixed by JMA and are never recoloured. Theme, colour-vision palette, contrast and text
settings therefore drive the labels, keys, markers and status text; every level is also written out as text.
JMA tile timestamps are UTC (unlike the JST feeds bousai_parse_time handles), see bousai_tiles_utc().
"""

# bousai: requires core map

load("cache.star", "cache")
load("encoding/json.star", "json")
load("filter.star", "filter")
load("http.star", "http")
load("math.star", "math")
load("render.star", "canvas", "render")
load("schema.star", "schema")
load("time.star", "time")

BOUSAI_TILES_AMEDAS = "https://www.jma.go.jp/bosai/amedas/"

# Polygons of JMA's "first forecast areas": the code the regional three-hourly forecast (VPFD) is published under.
BOUSAI_TILES_FIRST_AREA = BOUSAI_JMATILE + "/map/none/none/none/surf/click_first_area/data.geojson"

# Zoom presets: (id, Web-Mercator zoom of the 64 px wide view, menu text). One screen pixel is
# about 0.5 / 1.4 / 4 / 8 km at 36 N, so the 64 x 32 px view spans roughly 30 / 90 / 250 / 500 km.
BOUSAI_TILES_ZOOMS = [
    ("city", 8.0, "City (~30 km)"),
    ("prefecture", 6.5, "Prefecture (~90 km)"),
    ("region", 5.0, "Region (~250 km)"),
    ("wide", 4.0, "Wide (~500 km)"),
]

# Frame delay choices in milliseconds (Pixlet frames are 100 ms ticks).
BOUSAI_TILES_SPEEDS = [("300", "Fast"), ("500", "Normal"), ("900", "Slow")]

# Area each JMA tile family covers (dataArea in the JMA page properties XML): min lat, max lat, min lon, max lon.
BOUSAI_TILES_COVERAGE = {
    "nowc": (20.0, 48.0, 118.0, 150.0),
    "wdist": (23.725, 45.875, 122.40625, 149.34375),
}

# Zoom levels JMA publishes per product, probed 2026-10-21 and in line with zoomUse="even" and maxNativeZoom
# in each JMA page's properties XML: nowcast / rain forecast / snow / risk tiles exist at even zooms only
# (odd zooms are 404 or empty), thunder and tornado stop at z8, the weather distribution has every zoom.
BOUSAI_TILES_PRODUCT_ZOOMS = {
    "hrpns": [4, 6, 8, 10],
    "rasrf": [4, 6, 8, 10],
    "thns": [4, 6, 8],
    "trns": [4, 6, 8],
    "snow": [4, 6, 8, 10],
    "wdist": [3, 4, 5, 6, 7, 8, 9, 10],
    "risk": [4, 6, 8, 10],
}

# ---------------------------------------------------------------------------
# Options and schema

def bousai_tiles_fields(default_zoom = "prefecture", legend = True):
    """Schema fields every tile-map app shares: zoom, location marker, frame delay and the colour key."""
    fields = [
        schema.Dropdown(
            id = "zoom",
            name = "Map zoom",
            desc = "How wide an area is shown around your location.",
            icon = "magnifyingGlassLocation",
            default = default_zoom,
            options = [schema.Option(display = z[2], value = z[0]) for z in BOUSAI_TILES_ZOOMS],
        ),
        schema.Toggle(id = "show_location", name = "Show my location", desc = "Draw a marker at the centre of the map.", icon = "locationCrosshairs", default = True),
        schema.Dropdown(
            id = "delay",
            name = "Frame delay",
            desc = "How long each map frame stays on screen.",
            icon = "gaugeHigh",
            default = "500",
            options = [schema.Option(display = s[1], value = s[0]) for s in BOUSAI_TILES_SPEEDS],
        ),
    ]
    if legend:
        fields.append(schema.Toggle(id = "legend", name = "Show colour key", desc = "End the loop with a text key that explains the JMA map colours.", icon = "key", default = True))
    return fields

def bousai_tiles_schema(app_fields, default_zoom = "prefecture", legend = True):
    """Full schema: location, the app's own fields, the shared tile options, then the accessibility fields."""
    fields = [schema.Location(id = "location", name = "Location", desc = "Centre of the map. It chooses which map tiles are downloaded; coordinates are rounded locally to 0.001 degrees (about 100 m). Requested tiles reveal the selected map region.", icon = "locationDot")]
    fields.extend(app_fields)
    fields.extend(bousai_tiles_fields(default_zoom, legend))
    return bousai_schema(fields, location = False)

def bousai_tiles_options(config, default_zoom = "prefecture"):
    """Resolve the shared options: view zoom (scaled for 2x canvases), marker, frame delay in ms, colour key."""
    key = config.get("zoom") or default_zoom
    zoom = 6.5
    for z in BOUSAI_TILES_ZOOMS:
        if z[0] == key:
            zoom = z[1]
    scale = canvas.width() / 64.0
    if scale > 1.01:
        zoom = zoom + math.log(scale, 2)
    raw = config.get("delay") or "500"
    delay = int(raw) if raw.isdigit() else 500
    delay = max(100, min(2000, (delay // 100) * 100))
    return {
        "zoom_key": key,
        "zoom": zoom,
        "show_location": bousai_bool(config, "show_location", True),
        "delay": delay,
        "legend": bousai_bool(config, "legend", True),
    }

def bousai_tiles_covered(loc, area = "nowc"):
    """True when the location lies inside the area JMA publishes this tile family for."""
    b = BOUSAI_TILES_COVERAGE[area]
    return loc["lat"] >= b[0] and loc["lat"] <= b[1] and loc["lon"] >= b[2] and loc["lon"] <= b[3]

def bousai_tiles_view(loc, opts):
    """Map view centred on the location at the chosen zoom, one pixel per canvas pixel."""
    return bousai_view(loc["lat"], loc["lon"], opts["zoom"], canvas.width(), canvas.height())

# ---------------------------------------------------------------------------
# Time axis

def bousai_tiles_utc(s):
    """Parse a JMA tile timestamp 'YYYYMMDDhhmmss' (UTC). Returns None when malformed."""
    if type(s) != "string" or len(s) != 14 or not s.isdigit():
        return None
    return time.parse_time(s, format = "20060102150405", location = "UTC")

def bousai_tiles_minutes(u, ref_u):
    """Whole minutes (rounded) from ref_u to u, both unix seconds."""
    d = u - ref_u
    if d >= 0:
        return (d + 30) // 60
    return -((-d + 30) // 60)

def bousai_tiles_rel(minutes):
    """Relative time label: Now, -35m, +20m, +1h, -1h5m."""
    if minutes == 0:
        return "Now"
    sign = "+" if minutes > 0 else "-"
    m = abs(minutes)
    if m < 60:
        return "%s%dm" % (sign, m)
    if m % 60 == 0:
        return "%s%dh" % (sign, m // 60)
    return "%s%dh%dm" % (sign, m // 60, m % 60)

def bousai_tiles_clock(t, tz):
    """Local HH:MM of a time object."""
    return t.in_location(tz).format("15:04")

def bousai_tiles_entries(index, element):
    """Rows of a JMA target-time index that carry `element`, oldest valid time first.

    Each row is {base, valid (strings), member, u (valid, unix s), bu (base, unix s), t (valid, time)}.
    When several rows share a valid time the one with the newest base time wins.
    """
    best = {}
    for e in index or []:
        if element not in (e.get("elements") or []):
            continue
        v = bousai_tiles_utc(e.get("validtime"))
        b = bousai_tiles_utc(e.get("basetime"))
        if v == None or b == None:
            continue
        row = {"base": e["basetime"], "valid": e["validtime"], "member": e.get("member") or "none", "u": v.unix, "bu": b.unix, "t": v}
        old = best.get(v.unix)
        if old == None or old["bu"] <= row["bu"]:
            best[v.unix] = row
    return [best[k] for k in sorted(best.keys())]

def bousai_tiles_pick(entries, ref_u, offsets, tol_min = 6):
    """For each offset (minutes from ref_u) the nearest entry within tol_min; every entry is used at most once.

    Returns [(entry, offset)] in the order of offsets.
    """
    out = []
    used = {}
    for off in offsets:
        want = ref_u + off * 60
        best = None
        gap = None
        for e in entries:
            d = abs(e["u"] - want)
            if gap == None or d < gap:
                best = e
                gap = d
        if best != None and gap <= tol_min * 60 and best["u"] not in used:
            used[best["u"]] = True
            out.append((best, off))
    return out

def bousai_tiles_ttl(entry, now_u):
    """Tile cache time: tiles of a base time younger than 20 minutes may still be completed, older ones never change."""
    if now_u - entry["bu"] < 1200:
        return 180
    return 3600

def bousai_tiles_frame(kind, entry, element, label, sub = None, ttl = 3600, hold = 0):
    """A frame description: tile URL template plus the texts that go with it."""
    return {
        "url": bousai_jmatile_url(kind, entry["base"], entry["valid"], element, entry["member"]),
        "t": entry["t"],
        "u": entry["u"],
        "label": label,
        "sub": sub,
        "ttl": ttl,
        "hold": hold,
        "extra": [],
    }

def bousai_tiles_nowc3_frames(element, tz, now_u):
    """Frames for a 10-minute nowcast product of the N3 index (thns thunder, trns tornado).

    30 minutes of analysis, Now (held) and the forecast at +10 ... +60 minutes. Returns
    {"frames": [...], "t0": unix time of the newest analysis, "index": raw index} or None without analysis.
    Each frame carries "ana" (True up to Now) so apps can overlay observations only there.
    """
    index = bousai_jmatile_times("nowc/targetTimes_N3.json", ttl = 60)
    rows = bousai_tiles_entries(index, element)
    ana = [e for e in rows if e["u"] == e["bu"]]
    if len(ana) == 0:
        return None
    newest = ana[-1]
    t0 = newest["u"]
    picks = [(e, "ana") for e, _ in bousai_tiles_pick([e for e in ana if e["u"] < t0], t0, [-30, -20, -10], 4)]
    picks.append((newest, "now"))
    picks.extend([(e, "fcst") for e, _ in bousai_tiles_pick([e for e in rows if e["u"] > t0], t0, [10, 20, 30, 40, 50, 60], 4)])
    frames = []
    for e, kind in picks:
        f = bousai_tiles_frame("nowc", e, element, bousai_tiles_rel(bousai_tiles_minutes(e["u"], t0)), bousai_tiles_clock(e["t"], tz), bousai_tiles_ttl(e, now_u), 1 if kind == "now" else 0)
        f["ana"] = kind != "fcst"
        frames.append(f)
    frames[-1]["hold"] = max(frames[-1]["hold"], 2)
    return {"frames": frames, "t0": t0, "index": index}

# ---------------------------------------------------------------------------
# Tiles

def bousai_tiles_is_blank(src):
    """JMA writes a fully transparent tile as a 334-byte RGBA PNG (colour type 6); real data tiles are palette PNGs."""
    return len(src) == 334 and src[25] == "\x06"

def bousai_tiles_count(view, tile_zoom):
    """Number of tiles needed to cover the view at tile_zoom."""
    scale = math.pow(2, view["zoom"] - tile_zoom)
    ox = view["ox"] / scale
    oy = view["oy"] / scale
    tx0 = int(math.floor(ox / 256.0))
    ty0 = int(math.floor(oy / 256.0))
    tx1 = int(math.floor((ox + view["w"] / scale - 0.001) / 256.0))
    ty1 = int(math.floor((oy + view["h"] / scale - 0.001) / 256.0))
    return (tx1 - tx0 + 1) * (ty1 - ty0 + 1)

def bousai_tiles_pick_zoom(view, zooms, max_tiles = 3):
    """Published tile zoom closest to one level above the view zoom that needs at most max_tiles tiles.

    Finer tiles keep the 'blank' test (no data in view) tight; coarser ones save requests.
    """
    target = view["zoom"] + 1.0
    best = None
    for z in zooms:
        if bousai_tiles_count(view, z) > max_tiles:
            continue
        d = abs(z - target)
        if best == None or d < best[0] - 0.01 or (abs(d - best[0]) <= 0.01 and z < best[1]):
            best = (d, z)
    if best == None:
        return min(zooms)
    return best[1]

def bousai_tiles_fetch(view, url_template, tile_zoom, ttl):
    """Fetch the PNG tiles that cover the view and place them.

    Returns {"widgets": [...], "state": s}: "content" when at least one tile holds pixels, "blank" when every
    tile is empty or absent (404 means JMA has no data there), "unknown" when a request failed and nothing was drawn.
    """
    scale = math.pow(2, view["zoom"] - tile_zoom)
    tile_px = 256.0 * scale
    ox = view["ox"] / scale
    oy = view["oy"] / scale
    tx0 = int(math.floor(ox / 256.0))
    ty0 = int(math.floor(oy / 256.0))
    tx1 = int(math.floor((ox + view["w"] / scale - 0.001) / 256.0))
    ty1 = int(math.floor((oy + view["h"] / scale - 0.001) / 256.0))
    n = int(math.pow(2, tile_zoom))
    widgets = []
    failed = 0
    for ty in range(ty0, ty1 + 1):
        if ty < 0 or ty >= n:
            continue
        for tx in range(tx0, tx1 + 1):
            resp = http.get(url_template.format(z = tile_zoom, x = tx % n, y = ty), headers = BOUSAI_UA, ttl_seconds = ttl)
            if resp.status_code == 404:
                continue
            if resp.status_code != 200:
                failed += 1
                continue
            src = resp.body()
            if len(src) < 40 or src[1:4] != "PNG":
                failed += 1
                continue
            if bousai_tiles_is_blank(src):
                continue
            px = int(math.floor(tx * tile_px - view["ox"]))
            py = int(math.floor(ty * tile_px - view["oy"]))
            nx = int(math.floor((tx + 1) * tile_px - view["ox"]))
            ny = int(math.floor((ty + 1) * tile_px - view["oy"]))
            widgets.append(bousai_place(px, py, render.Image(src = src, width = nx - px, height = ny - py)))
    state = "content"
    if len(widgets) == 0:
        state = "unknown" if failed > 0 else "blank"
    return {"widgets": widgets, "state": state}

# ---------------------------------------------------------------------------
# Frame composition

def bousai_tiles_data_dim(ui):
    """Brightness shift for JMA data tiles: calmer for low contrast, darker on the light theme so pale colours stay visible."""
    if ui["theme"] == "light":
        return -0.3 if ui["contrast"] == "low" else -0.18
    return -0.3 if ui["contrast"] == "low" else 0.0

def bousai_tiles_mask_dim(ui):
    """Brightness shift for the JMA coast and border overlay (bright grey on its own, dimmed for LEDs)."""
    if ui["theme"] == "light":
        return -0.15 if ui["contrast"] == "high" else -0.05
    if ui["contrast"] == "high":
        return -0.2
    return -0.55 if ui["contrast"] == "low" else -0.38

def bousai_tiles_mask(ui, view):
    """Dimmed JMA coast / prefecture border overlay for the view, or None when the tiles are unavailable."""
    mz = max(4, min(11, int(math.floor(view["zoom"] + 1.5))))
    layers = bousai_mask_layer(view, mz)
    if len(layers) == 0:
        return None
    return filter.Brightness(child = render.Stack(children = layers), change = bousai_tiles_mask_dim(ui))

def bousai_tiles_marker(ui, view, lat, lon):
    """Location cross with a halo in the background colour so it reads over any JMA colour."""
    x, y = bousai_view_xy(view, lat, lon)
    arm = 3 if ui["frame"] else 2
    halo = ui["bg"]
    kids = [
        bousai_place(x - arm - 1, y - 1, render.Box(width = 2 * arm + 3, height = 3, color = halo)),
        bousai_place(x - 1, y - arm - 1, render.Box(width = 3, height = 2 * arm + 3, color = halo)),
        bousai_place(x - arm, y, render.Box(width = 2 * arm + 1, height = 1, color = ui["fg"])),
        bousai_place(x, y - arm, render.Box(width = 1, height = 2 * arm + 1, color = ui["fg"])),
    ]
    return render.Stack(children = kids)

def bousai_tiles_backing(ui):
    """Semi-opaque backing colour for text drawn over the map (opaque in high contrast)."""
    return ui["bg"] + ("ff" if ui["frame"] else "d2")

def bousai_tiles_label(ui, text, sub = None):
    """Small time label with a readable backing, drawn at the top-left of the map."""
    font = ui["small_font"]
    full = text if not sub else text + " " + sub
    if bousai_text_width(ui, full, font) > canvas.width() - 3:
        full = text
    w = min(canvas.width(), bousai_text_width(ui, full, font) + 3)
    h = bousai_font_height(ui, font) + 1
    box = render.Box(width = w, height = h, color = bousai_tiles_backing(ui), child = bousai_text(ui, full, ui["fg"], font))
    if ui["frame"]:
        box = render.Box(width = w + 1, height = h + 1, color = ui["muted"], child = box)
    return box

def bousai_tiles_banner(ui, text, frames = None):
    """Full-width text strip at the bottom of the map ('No rain', or a per-frame note such as 'Cloudy 21C')."""
    font = ui["small_font"]
    h = bousai_font_height(ui, font) + 1
    strip = render.Box(width = canvas.width(), height = h, color = bousai_tiles_backing(ui), child = bousai_fit(ui, text, width = canvas.width() - 2, color = ui["fg"], font = font, align = "center", frames = frames))
    return bousai_place(0, canvas.height() - h, strip)

def bousai_tiles_glyph(rows, color, scale = 1):
    """A small hand-drawn bitmap (rows of '#' and '.') as a widget, each pixel scaled to scale x scale."""
    kids = []
    for y in range(len(rows)):
        for x in range(len(rows[y])):
            if rows[y][x] == "#":
                kids.append(bousai_place(x * scale, y * scale, render.Box(width = scale, height = scale, color = color)))
    return render.Box(width = len(rows[0]) * scale, height = len(rows) * scale, child = render.Stack(children = kids))

def bousai_tiles_bar(ui, text, right = None, lead = None, frames = None):
    """Opaque full-width text bar at the top of the map: an optional bitmap glyph (`lead`, rows of '#'/'.', e.g. a
    kanji weekday), the frame time and note ('21h Cldy'), and an optional value pinned to the right edge ('21C').
    The glyph and right value always stay put; only the text between them scrolls when it does not fit.
    The bar is one row taller than the font so a 6-row glyph fits; text sits on the bottom rows.
    """
    font = ui["small_font"]
    h = bousai_font_height(ui, font) + 1
    w = canvas.width()
    rw = bousai_text_width(ui, right, font) if right else 0
    head = []
    lw = w - 1 - (rw + 1 if right else 0)
    if lead:
        scale = max(1, h // len(lead))
        head = [bousai_tiles_glyph(lead, ui["fg"], scale), render.Box(width = scale, height = 1)]
        lw -= len(lead[0]) * scale + scale
    fits = bousai_text_width(ui, text, font) <= lw
    left = bousai_text(ui, text, ui["fg"], font) if fits else bousai_fit(ui, text, width = lw, color = ui["fg"], font = font, frames = frames)
    kids = [render.Padding(pad = (1, 0, 0, 0), child = render.Row(cross_align = "end", children = head + [left]))]
    if right:
        kids.append(bousai_text(ui, right, ui["fg"], font))
    line = render.Row(expanded = True, main_align = "space_between", cross_align = "end", children = kids)
    bar = render.Box(width = w, height = h, color = ui["bg"], child = line)
    if ui["frame"]:
        return render.Column(children = [bar, render.Box(width = w, height = 1, color = ui["muted"])])
    return bar

def bousai_tiles_gradient(colors):
    """Colour-key footer for the bottom of the map: the tile colours left to right as one smooth gradient, outlined in black.

    The colours sit at evenly spaced stops (first at the left edge, last at the right) and every pixel between two
    stops is linearly interpolated, so neighbouring classes run into each other without hard steps.
    """
    inner = canvas.width() - 2
    n = len(colors)
    cols = []
    for x in range(inner):
        c = colors[0]
        if n > 1:
            p = x * (n - 1) / (inner - 1.0)
            i = min(n - 2, int(p))
            c = bousai_mix(colors[i], colors[i + 1], p - i)
        cols.append(render.Box(width = 1, height = 2, color = c))
    strip = render.Padding(pad = 1, child = render.Row(children = cols))
    return bousai_place(0, canvas.height() - 4, render.Box(width = canvas.width(), height = 4, color = "#000000", child = strip))

def bousai_tiles_strike(ui, cg):
    """Lightning discharge glyph: a filled square for cloud-to-ground (CG), a cross for cloud-to-cloud (CC).

    Shape carries the meaning, so it does not depend on colour; the halo keeps it readable over any JMA colour.
    """
    if cg:
        return render.Box(width = 4, height = 4, color = ui["bg"], child = render.Box(width = 2, height = 2, color = ui["fg"]))
    return render.Stack(children = [
        render.Box(width = 5, height = 5, color = ui["bg"]),
        bousai_place(1, 2, render.Box(width = 3, height = 1, color = ui["fg"])),
        bousai_place(2, 1, render.Box(width = 1, height = 3, color = ui["fg"])),
    ])

def bousai_tiles_strike_marks(ui, view, strikes, cap = 40):
    """Positioned glyphs for strikes [(lat, lon, is_cg)] that fall inside the view (at most `cap` of each kind)."""
    out = []
    n_cg = 0
    n_cc = 0
    for s in strikes:
        x, y = bousai_view_xy(view, s[0], s[1])
        if not bousai_in_view(view, x, y):
            continue
        if s[2]:
            if n_cg >= cap:
                continue
            n_cg += 1
            out.append(bousai_place(x - 1, y - 1, bousai_tiles_strike(ui, True)))
        else:
            if n_cc >= cap:
                continue
            n_cc += 1
            out.append(bousai_place(x - 2, y - 2, bousai_tiles_strike(ui, False)))
    return out

def bousai_tiles_build(ui, loc, view, opts, frames, spec):
    """Fetch tiles and compose one widget per frame.

    frames: dicts from bousai_tiles_frame, optionally with "extra" (widgets drawn above the mask), "note" (bottom
    text strip, or after the label in the top bar), "right" (top bar only: text pinned to the bar's right edge),
    "lead" (top bar only: bitmap glyph rows drawn before the label) and "quiet" (True: do not claim 'nothing here'
    even when the tiles are blank).
    spec: {"zooms": [tile zooms], "empty": banner text when a frame's tiles are blank (optional),
           "basemap": True to force the land silhouette (default: only when zoomed out),
           "bar": True to write label, note and empty text into one opaque top bar instead (optional),
           "footer": tile colours drawn as a gradient strip along the bottom (optional)}.
    Returns {"widgets": [...], "holds": [extra ticks], "states": ["content"|"blank"|"unknown"], "tile_zoom": z}.
    """
    tile_zoom = bousai_tiles_pick_zoom(view, spec["zooms"])
    under = []
    if spec.get("basemap", view["zoom"] <= 5.5):
        under.append(bousai_basemap(ui, view, "japan"))
    mask = bousai_tiles_mask(ui, view)
    over = [mask] if mask != None else []
    marker = bousai_tiles_marker(ui, view, loc["lat"], loc["lon"]) if opts["show_location"] else None
    dim = bousai_tiles_data_dim(ui)
    footer = bousai_tiles_gradient(spec["footer"]) if spec.get("footer") else None
    widgets = []
    holds = []
    states = []
    for f in frames:
        got = {"widgets": [], "state": "blank"}
        if f.get("url"):
            got = bousai_tiles_fetch(view, f["url"], tile_zoom, f["ttl"])
        kids = list(under)
        if len(got["widgets"]) > 0:
            data = render.Stack(children = got["widgets"])
            kids.append(filter.Brightness(child = data, change = dim) if dim != 0 else data)
        kids.extend(over)
        kids.extend(f.get("extra") or [])
        if marker != None:
            kids.append(marker)
        empty = got["state"] == "blank" and spec.get("empty") and not f.get("quiet")
        if spec.get("bar"):
            if footer != None:
                kids.append(footer)
            parts = [f["label"]]
            if f.get("note"):
                parts.append(f["note"])
            elif empty:
                parts.append(spec["empty"])
            kids.append(bousai_tiles_bar(ui, " ".join(parts), f.get("right"), f.get("lead")))
        else:
            if f.get("note"):
                kids.append(bousai_tiles_banner(ui, f["note"]))
            elif empty:
                kids.append(bousai_tiles_banner(ui, spec["empty"]))
            kids.append(bousai_tiles_label(ui, f["label"], f.get("sub")))
        widgets.append(render.Box(width = view["w"], height = view["h"], color = ui["bg"], child = render.Stack(children = kids)))
        holds.append(f.get("hold") or 0)
        states.append(got["state"])
    return {"widgets": widgets, "holds": holds, "states": states, "tile_zoom": tile_zoom}

def bousai_tiles_all_blank(states):
    """True when every frame's tiles were fetched and none holds any pixel (nothing to see anywhere)."""
    if len(states) == 0:
        return False
    for s in states:
        if s != "blank":
            return False
    return True

def bousai_tiles_presence(frames, states):
    """What the tiles say frame by frame (tile level, so 'in your region'): {"now": bool, "ahead": label or None, "any": bool}.

    "now" is the frame labelled Now, "ahead" the label of the first later frame whose tiles hold data.
    """
    now = False
    ahead = None
    found = False
    seen_now = False
    for i in range(len(frames)):
        has = states[i] == "content"
        found = found or has
        if frames[i]["label"] == "Now":
            seen_now = True
            now = has
        elif seen_now and has and ahead == None:
            ahead = frames[i]["label"]
    return {"now": now, "ahead": ahead, "any": found}

# ---------------------------------------------------------------------------
# Pages: text rows and colour keys

def bousai_tiles_chunks(items, per_page):
    """Split items into pages of per_page."""
    out = []
    for i in range(0, len(items), per_page):
        out.append(items[i:i + per_page])
    return out

def bousai_tiles_text_layout(ui, rows):
    """Row chunks, one per page. Large and extra-large text drops the title band so two or three rows fit a page."""
    head = ui["line_h"] if ui["line_h"] < 9 else 0
    return bousai_tiles_chunks(rows, max(1, (canvas.height() - head) // ui["line_h"]))

def bousai_tiles_text_page(ui, title, rows, ticks):
    """One text page: title band (not for large text) plus rows (str or (text, colour)); long lines scroll within `ticks` frames."""
    kids = [bousai_header(ui, title, frames = ticks)] if ui["line_h"] < 9 else []
    for r in rows:
        kids.append(render.Box(width = canvas.width(), height = ui["line_h"], child = bousai_row(ui, r, ticks)))
    body = render.Box(width = canvas.width(), height = canvas.height(), child = render.Column(expanded = True, main_align = "start", cross_align = "start", children = kids))
    return bousai_hold(body, ticks)

def bousai_tiles_key_layout(ui, entries, titled = True):
    """How a colour key is laid out. The key text uses the small font where there is one, so eight entries fit one page.

    A key without a unit (the weather key) skips the title band, which leaves room for a fifth row.
    """
    font = ui["small_font"]
    lh = bousai_font_height(ui, font) + 1
    head = ui["line_h"] if (ui["line_h"] < 9 and titled) else 0
    sw = 6 if lh <= 9 else 8
    widest = 0
    for e in entries:
        widest = max(widest, bousai_text_width(ui, e[1], font))
    cell = sw + 2 + 1 + 2 + widest
    cols = 2 if 2 * cell <= canvas.width() else 1
    rows = max(1, (canvas.height() - head) // lh)
    return {"cols": cols, "per_page": rows * cols, "sw": sw, "sh": max(3, lh - 3), "lh": lh, "font": font, "banded": head > 0}

def bousai_tiles_key_page(ui, title, entries, unit, ticks, layout):
    """One colour-key page: swatch (the real JMA tile colour, outlined) plus its text, `cols` cells per row."""
    cols = layout["cols"]
    width = canvas.width() // cols
    kids = [bousai_header(ui, title, right = unit, frames = ticks)] if layout["banded"] else []
    for r in range(0, len(entries), cols):
        cells = []
        for e in entries[r:r + cols]:
            shape = e[2] if len(e) > 2 else "box"
            if shape == "cg" or shape == "cc":
                swatch = render.Box(width = layout["sw"] + 2, height = layout["sh"] + 2, child = bousai_tiles_strike(ui, shape == "cg"))
            else:
                swatch = render.Box(width = layout["sw"] + 2, height = layout["sh"] + 2, color = ui["muted"], child = render.Box(width = layout["sw"], height = layout["sh"], color = e[0]))
            label = render.Padding(pad = (2, 0, 0, 0), child = bousai_text(ui, e[1], ui["fg"], layout["font"]))
            cells.append(render.Box(width = width, height = layout["lh"], child = render.Row(expanded = True, main_align = "start", cross_align = "center", children = [render.Padding(pad = (1, 0, 0, 0), child = swatch), label])))
        kids.append(render.Row(children = cells))
    body = render.Box(width = canvas.width(), height = canvas.height(), child = render.Column(expanded = True, main_align = "start", cross_align = "start", children = kids))
    return bousai_hold(body, ticks)

# ---------------------------------------------------------------------------
# Animation budget and root

def bousai_tiles_total(values):
    """Sum of a list of numbers (Starlark has no sum())."""
    out = 0
    for v in values:
        out += v
    return out

def bousai_tiles_root(ui, opts, built, status = None, key = None):
    """Assemble the animation: map frames, then status text pages, then the colour key, all inside the dwell budget.

    built: result of bousai_tiles_build.
    status: {"title": str, "rows": [str | (text, colour)]} or None.
    key: {"title": str, "unit": str or None, "entries": [(tile colour hex, text)]} or None.
    Holds are trimmed first, then page time, then the oldest frames, so the newest frames and the text always fit.
    """
    total = bousai_budget_frames()
    per = max(1, opts["delay"] // 100)
    widgets = built["widgets"]
    holds = built["holds"]

    text_chunks = bousai_tiles_text_layout(ui, status["rows"]) if status else []
    key_layout = None
    key_chunks = []
    if key and len(key["entries"]) > 0:
        key_layout = bousai_tiles_key_layout(ui, key["entries"], key.get("unit") != None)
        key_chunks = bousai_tiles_chunks(key["entries"], key_layout["per_page"])
    n_pages = len(text_chunks) + len(key_chunks)

    frame_ticks = [per * (1 + h) for h in holds]
    page_ticks = [30 if i < len(text_chunks) else 25 for i in range(n_pages)]
    need = bousai_tiles_total(frame_ticks) + bousai_tiles_total(page_ticks)
    if need > total:
        frame_ticks = [per for _ in widgets]
        need = bousai_tiles_total(frame_ticks) + bousai_tiles_total(page_ticks)
    if need > total:
        page_ticks = [min(t, 16) for t in page_ticks]
        need = bousai_tiles_total(frame_ticks) + bousai_tiles_total(page_ticks)
    if need > total:
        page_ticks = [min(t, 12) for t in page_ticks]
        need = bousai_tiles_total(frame_ticks) + bousai_tiles_total(page_ticks)
    first = 0
    if need > total:
        for i in range(max(0, len(widgets) - 2)):
            if need <= total:
                break
            need -= frame_ticks[i]
            first += 1
    shown = []
    for i in range(first, len(widgets)):
        shown.extend([widgets[i]] * frame_ticks[i])
    seq = [render.Animation(children = shown)]
    k = 0
    for chunk in text_chunks:
        seq.append(bousai_tiles_text_page(ui, status["title"], chunk, page_ticks[k]))
        k += 1
    for chunk in key_chunks:
        seq.append(bousai_tiles_key_page(ui, key["title"], chunk, key.get("unit"), page_ticks[k], key_layout))
        k += 1
    if len(seq) == 1:
        return bousai_root(ui, seq[0])
    return bousai_root(ui, render.Sequence(children = seq))

# ---------------------------------------------------------------------------
# AMeDAS numbers for text cues

def bousai_tiles_val(pair):
    """AMeDAS [value, quality] pair -> value, or None when missing or flagged as not observed (quality >= 5)."""
    if type(pair) != "list" or len(pair) == 0 or pair[0] == None:
        return None
    if len(pair) > 1 and pair[1] != None and pair[1] >= 5:
        return None
    return pair[0]

def bousai_tiles_amedas_near(lat, lon, radius_km = 40.0):
    """Latest AMeDAS observations (JMA, 10-minute cadence) around a point.

    Returns None when the feed is unavailable, else {"time": time, "stations": [...]} with the stations inside
    radius_km sorted by distance. Each station: {id, name (English), km, dir (16-point bearing from the point),
    p10 / p1h (precipitation mm over 10 min / 1 h), snow (depth cm), snow1h / snow3h / snow6h / snow12h /
    snow24h (snowfall cm), temp (C)}; a value is None where the station does not report it.
    """
    lt = http.get(BOUSAI_TILES_AMEDAS + "data/latest_time.txt", headers = BOUSAI_UA, ttl_seconds = 60)
    if lt.status_code != 200:
        return None
    stamp = lt.body().strip()
    when = bousai_parse_time(stamp)
    if when == None or len(stamp) < 19:
        return None
    key = stamp[0:4] + stamp[5:7] + stamp[8:10] + stamp[11:13] + stamp[14:16] + stamp[17:19]
    obs = bousai_get_json(BOUSAI_TILES_AMEDAS + "data/map/" + key + ".json", ttl = 300)
    table = bousai_get_json(BOUSAI_TILES_AMEDAS + "const/amedastable.json", ttl = 86400)
    if type(obs) != "dict" or type(table) != "dict":
        return None
    dlat = radius_km / 111.0
    dlon = radius_km / (111.0 * max(0.2, math.cos(math.radians(lat))))
    near = []
    for sid, o in obs.items():
        st = table.get(sid)
        if st == None:
            continue
        slat = st["lat"][0] + st["lat"][1] / 60.0
        slon = st["lon"][0] + st["lon"][1] / 60.0
        if abs(slat - lat) > dlat or abs(slon - lon) > dlon:
            continue
        km = bousai_distance_km(lat, lon, slat, slon)
        if km > radius_km:
            continue
        near.append({
            "id": sid,
            "name": st.get("enName") or st.get("kjName") or sid,
            "km": km,
            "dir": bousai_bearing_name(lat, lon, slat, slon),
            "p10": bousai_tiles_val(o.get("precipitation10m")),
            "p1h": bousai_tiles_val(o.get("precipitation1h")),
            "snow": bousai_tiles_val(o.get("snow")),
            "snow1h": bousai_tiles_val(o.get("snow1h")),
            "snow3h": bousai_tiles_val(o.get("snow3h")),
            "snow6h": bousai_tiles_val(o.get("snow6h")),
            "snow12h": bousai_tiles_val(o.get("snow12h")),
            "snow24h": bousai_tiles_val(o.get("snow24h")),
            "temp": bousai_tiles_val(o.get("temp")),
        })
    return {"time": when, "stations": sorted(near, key = lambda s: s["km"])}

def bousai_tiles_place(st):
    """'Name 12km SE' for an AMeDAS station entry."""
    return "%s %dkm %s" % (st["name"], int(st["km"] + 0.5), st["dir"])

# ---------------------------------------------------------------------------
# JMA first forecast area

def bousai_tiles_first_area(lat, lon):
    """JMA first forecast area containing a point: {"code": "130010", "name": "Tokyo Region"} or None.

    The code is what JMA publishes the regional three-hourly forecast under (wdist/VPFD/<code>.json). It comes
    from JMA's own polygon file (one cached request, point-in-polygon with the core helper), so no geocoder is
    involved; the answer is cached for a week.
    """
    key = "bousai_tiles_first:%s:%s" % (bousai_fixed(lat, 3), bousai_fixed(lon, 3))
    hit = cache.get(key)
    if hit != None:
        return json.decode(hit, default = None) if hit != "-" else None
    data = bousai_get_json(BOUSAI_TILES_FIRST_AREA, ttl = 7 * 86400)
    if type(data) != "dict":
        return None
    found = None
    for f in data.get("features") or []:
        if bousai_in_geometry(lon, lat, f["geometry"]):
            p = f.get("properties") or {}
            found = {"code": p.get("areaCode"), "name": p.get("areaNameEN") or ""}
            break
    cache.set(key, json.encode(found) if found != None else "-", ttl_seconds = 7 * 86400)
    return found
