"""Shared core for the Bousai app suite.

Location -> JMA area resolution, accessibility settings (theme, colour-vision
palettes, contrast, text size/weight), paged text layout, time and geo helpers.
Inlined into each app by tools/build.py; every public name is prefixed bousai_.
"""

load("cache.star", "cache")
load("encoding/json.star", "json")
load("filter.star", "filter")
load("http.star", "http")
load("math.star", "math")
load("render.star", "canvas", "render")
load("schema.star", "schema")
load("time.star", "time")

BOUSAI_JST = "Asia/Tokyo"
BOUSAI_UA = {"User-Agent": "bousai-tronbyt-apps (+https://www.jma.go.jp/)"}

BOUSAI_DEFAULT_LOCATION = json.encode({
    "lat": "35.6812",
    "lng": "139.7671",
    "description": "Tokyo Station, Chiyoda, Tokyo, Japan",
    "locality": "Chiyoda",
    "timezone": "Asia/Tokyo",
})

BOUSAI_CLASS20_BOXES = "https://www.jma.go.jp/bosai/common/const/class20relm.json"
BOUSAI_CLASS20_SHAPE = "https://www.jma.go.jp/bosai/common/const/geojson/class20s/%s.json"
BOUSAI_AREA_JSON = "https://www.jma.go.jp/bosai/common/const/area.json"

# ---------------------------------------------------------------------------
# HTTP

def bousai_get_json(url, ttl = 60, params = None):
    """GET url and decode JSON. Returns None on transport-level non-200 or bad JSON."""
    resp = http.get(url, params = params or {}, headers = BOUSAI_UA, ttl_seconds = ttl)
    if resp.status_code != 200:
        return None
    return json.decode(resp.body(), default = None)

def bousai_get_bytes(url, ttl = 60):
    resp = http.get(url, headers = BOUSAI_UA, ttl_seconds = ttl)
    if resp.status_code != 200:
        return None
    return resp.body()

def bousai_guarded_get(url, ttl = 60, params = None, cooldown = 300):
    """GET from a host that may stall, without crash-looping. Returns the body or None.

    A transport error or Pixlet's 5 s HTTP timeout aborts the whole render and Starlark
    cannot catch it. So a "pending:<unix time>" marker is cached before the request and cleared
    after it. A marker older than the HTTP timeout found at the start means an earlier attempt
    died mid-request: the host is then skipped (None) for `cooldown` seconds. A younger marker
    is a concurrent render still in flight and is ignored. Use for third-party feeds (Wolfx,
    P2PQuake, NIED); keep cooldown above the app's render interval.
    """
    key = "bousai_guard:" + url.split("/")[2]
    state = cache.get(key) or ""
    now = time.now().unix
    if state == "down":
        return None
    if state.startswith("pending:") and now - int(state[8:]) > 6:
        cache.set(key, "down", ttl_seconds = cooldown)
        return None
    cache.set(key, "pending:%d" % now, ttl_seconds = cooldown)
    resp = http.get(url, params = params or {}, headers = BOUSAI_UA, ttl_seconds = ttl)
    cache.set(key, "ok", ttl_seconds = 1)
    if resp.status_code != 200:
        return None
    return resp.body()

def bousai_guarded_json(url, ttl = 60, params = None, cooldown = 300):
    """bousai_guarded_get + JSON decode (None on any failure)."""
    body = bousai_guarded_get(url, ttl, params, cooldown)
    return json.decode(body, default = None) if body != None else None

# ---------------------------------------------------------------------------
# Schema

def bousai_schema(fields, location = True, location_desc = "Your location in Japan. Matched to a JMA municipality on the server using JMA's own area polygons; coordinates are never sent anywhere."):
    """Build the app schema: optional location, app fields, then accessibility fields."""
    out = []
    if location:
        out.append(schema.Location(id = "location", name = "Location", desc = location_desc, icon = "locationDot"))
        out.append(schema.Text(id = "area_override", name = "JMA area code (optional)", desc = "7-digit JMA municipality code (e.g. 1310100). Overrides the location lookup.", icon = "mapPin", default = ""))
    out.extend(fields)
    out.extend(bousai_accessibility_fields())
    return schema.Schema(version = "1", fields = out)

def bousai_accessibility_fields():
    return [
        schema.Dropdown(id = "theme", name = "Theme", desc = "Dark or light display theme.", icon = "circleHalfStroke", default = "dark", options = [
            schema.Option(display = "Dark", value = "dark"),
            schema.Option(display = "Light", value = "light"),
        ]),
        schema.Dropdown(id = "palette", name = "Colour vision", desc = "Colour scheme optimised for your colour vision. Levels are always also shown as text.", icon = "eye", default = "normal", options = [
            schema.Option(display = "Normal vision", value = "normal"),
            schema.Option(display = "Protanopia / Deuteranopia (red-green)", value = "protan"),
            schema.Option(display = "Tritanopia (blue-yellow)", value = "tritan"),
            schema.Option(display = "Monochromacy", value = "mono"),
        ]),
        schema.Dropdown(id = "contrast", name = "Contrast", desc = "Low is calmer and paler; high gives brighter text and frames.", icon = "circleHalfStroke", default = "normal", options = [
            schema.Option(display = "Low", value = "low"),
            schema.Option(display = "Normal", value = "normal"),
            schema.Option(display = "High", value = "high"),
        ]),
        schema.Dropdown(id = "text_size", name = "Text size", desc = "Larger text shows fewer lines per page.", icon = "textHeight", default = "standard", options = [
            schema.Option(display = "Small", value = "small"),
            schema.Option(display = "Standard", value = "standard"),
            schema.Option(display = "Large", value = "large"),
            schema.Option(display = "Extra large", value = "xlarge"),
        ]),
        schema.Dropdown(id = "text_weight", name = "Text weight", desc = "Bold draws each glyph one pixel wider.", icon = "bold", default = "normal", options = [
            schema.Option(display = "Normal", value = "normal"),
            schema.Option(display = "Bold", value = "bold"),
        ]),
    ]

def bousai_bool(config, key, default = False):
    v = config.get(key)
    if v == None or v == "":
        return default
    return v == True or v == "true" or v == "True" or v == "1"

# ---------------------------------------------------------------------------
# Colour

def bousai_rgb(c):
    c = c.lstrip("#")
    if len(c) == 3:
        c = c[0] + c[0] + c[1] + c[1] + c[2] + c[2]
    return (int(c[0:2], 16), int(c[2:4], 16), int(c[4:6], 16))

def bousai_hex(rgb):
    """(r, g, b) -> '#rrggbb'. Pixlet's % has no width flags, so pad by hand."""
    digits = "0123456789abcdef"
    out = "#"
    for i in range(3):
        v = max(0, min(255, int(rgb[i])))
        out += digits[v // 16] + digits[v % 16]
    return out

def bousai_mix(a, b, t):
    """Blend colour a toward b by fraction t (0..1)."""
    x, y = bousai_rgb(a), bousai_rgb(b)
    return bousai_hex([x[i] + (y[i] - x[i]) * t for i in range(3)])

def bousai_luma(c):
    r, g, b = bousai_rgb(c)
    return 0.299 * r + 0.587 * g + 0.114 * b

def bousai_on(c):
    """Readable text colour (black or white) on background c."""
    return "#000000" if bousai_luma(c) > 140 else "#ffffff"

# Seismic intensity scale. Keys are normalised JMA labels.
BOUSAI_INTENSITY_ORDER = ["0", "1", "2", "3", "4", "5-", "5+", "6-", "6+", "7"]

BOUSAI_INTENSITY_PALETTES = {
    # JMA-like ramp tuned for LEDs.
    "normal": ["#5a6070", "#8899aa", "#3d8bff", "#22c39a", "#f5e15b", "#ffb020", "#ff7a00", "#ff2e2e", "#c8102e", "#c03cff"],
    # Okabe-Ito based: blue/yellow/orange/purple axis plus a luminance ramp, no red-green pairs.
    "protan": ["#5a6070", "#8899aa", "#56b4e9", "#0072b2", "#f0e442", "#e69f00", "#d55e00", "#cc79a7", "#a0307a", "#ffffff"],
    # Red/cyan axis plus luminance, no blue-yellow pairs.
    "tritan": ["#5a6070", "#8899aa", "#4dd0e1", "#00897b", "#ffcdd2", "#ff8a80", "#ff5252", "#d50000", "#8b0000", "#ffffff"],
    "mono": ["#3a3a3a", "#555555", "#707070", "#8a8a8a", "#a3a3a3", "#bcbcbc", "#cfcfcf", "#e0e0e0", "#efefef", "#ffffff"],
}

# Severity scale shared by warnings, tsunami, volcano and alerts:
# 0 none, 1 info/forecast, 2 advisory (Lv2), 3 warning (Lv3), 4 urgent warning (Lv4), 5 emergency (Lv5).
BOUSAI_SEVERITY_PALETTES = {
    "normal": ["#5a6070", "#3d8bff", "#f2e700", "#ff2800", "#c040c0", "#ff40ff"],
    "protan": ["#5a6070", "#56b4e9", "#f0e442", "#e69f00", "#cc79a7", "#ffffff"],
    "tritan": ["#5a6070", "#4dd0e1", "#ffcdd2", "#ff5252", "#d50000", "#ffffff"],
    "mono": ["#555555", "#8a8a8a", "#a3a3a3", "#c8c8c8", "#e6e6e6", "#ffffff"],
}

BOUSAI_SEVERITY_EN = ["None", "Info", "Advisory", "Warning", "Urgent Warning", "Emergency Warning"]

BOUSAI_FONTS = {
    # text_size: (body font, line height, big font for numbers)
    "small": ("CG-pixel-3x5-mono", 6, "tb-8"),
    "standard": ("tom-thumb", 7, "6x13"),
    "large": ("tb-8", 9, "6x13"),
    "xlarge": ("6x10", 11, "10x20"),
}

def bousai_ui(config):
    """Resolve accessibility settings into colours and fonts. Returns a dict."""
    theme = config.get("theme") or "dark"
    palette = config.get("palette") or "normal"
    if palette not in BOUSAI_SEVERITY_PALETTES:
        palette = "normal"
    contrast = config.get("contrast") or "normal"
    size = config.get("text_size") or "standard"
    if size not in BOUSAI_FONTS:
        size = "standard"
    bold = (config.get("text_weight") or "normal") == "bold"

    if theme == "light":
        bg, fg, muted, faint, panel = "#f4f4f4", "#000000", "#555555", "#c8c8c8", "#dddddd"
        land = -0.3
    else:
        bg, fg, muted, faint, panel = "#000000", "#ffffff", "#9a9a9a", "#3a3a3a", "#141414"
        land = -0.62

    sev = list(BOUSAI_SEVERITY_PALETTES[palette])
    inten = list(BOUSAI_INTENSITY_PALETTES[palette])
    if theme == "light":
        # Pull bright LED colours down so they stay readable on a light background.
        sev = [bousai_mix(c, "#000000", 0.3) for c in sev]
        inten = [bousai_mix(c, "#000000", 0.3) for c in inten]

    if contrast == "low":
        fg = bousai_mix(fg, bg, 0.3)
        muted = bousai_mix(muted, bg, 0.3)
        sev = [bousai_mix(c, bg, 0.35) for c in sev]
        inten = [bousai_mix(c, bg, 0.35) for c in inten]
        land = land - 0.1 if theme != "light" else land + 0.1
    elif contrast == "high":
        muted = bousai_mix(muted, fg, 0.45)
        faint = bousai_mix(faint, fg, 0.3)
        land = land + 0.15 if theme != "light" else land - 0.15

    font, line_h, big = BOUSAI_FONTS[size]
    return {
        "theme": theme,
        "palette": palette,
        "contrast": contrast,
        "size": size,
        "bold": bold,
        "bg": bg,
        "fg": fg,
        "muted": muted,
        "faint": faint,
        "panel": panel,
        "accent": sev[1],
        "sev": sev,
        "intensity": dict(zip(BOUSAI_INTENSITY_ORDER, inten)),
        "land_brightness": land,
        "frame": contrast == "high",
        "font": font,
        "line_h": line_h,
        "big_font": big,
        "small_font": "CG-pixel-3x5-mono" if size in ("small", "standard") else font,
        "delay": 100,
    }

# ---------------------------------------------------------------------------
# Text and layout

def bousai_text(ui, s, color = None, font = None):
    """Text honouring the bold setting."""
    font = font or ui["font"]
    color = color or ui["fg"]
    if not ui["bold"]:
        return render.Text(s, font = font, color = color)
    return render.Stack(children = [
        render.Text(s, font = font, color = color),
        render.Padding(pad = (1, 0, 0, 0), child = render.Text(s, font = font, color = color)),
    ])

def bousai_text_width(ui, s, font = None):
    w = render.Text(s, font = font or ui["font"]).size()[0]
    return w + (1 if ui["bold"] else 0)

def bousai_budget_frames():
    """Frames available for the whole animation (dwell time / 100 ms; 150 when unbounded)."""
    budget = canvas.max_duration_ms()
    if budget <= 0:
        budget = 15000
    return max(1, budget // 100)

def bousai_ticker(ui, s, width, color = None, font = None, frames = None):
    """Scroll text that is wider than `width` within exactly `frames` frames.

    Unlike render.Marquee (fixed 1 px/frame, so long text overruns the dwell time), the ticker
    pauses, scrolls at whatever speed fits the frame budget (never faster than needed), then holds.
    """
    frames = frames or bousai_budget_frames()
    text = bousai_text(ui, s, color, font)
    h = bousai_font_height(ui, font) + 1
    travel = bousai_text_width(ui, s, font) - width
    if travel <= 0 or frames < 2:
        return render.Box(width = width, height = h, child = render.Row(expanded = True, children = [text]))
    lead = min(8, frames // 4)
    tail = min(8, frames // 6)
    moving = max(1, frames - lead - tail)
    children = []
    for i in range(frames):
        step = max(0, i - lead)
        if travel <= moving:
            off = min(travel, step)
        else:
            off = min(travel, (step * travel + moving - 1) // moving)
        children.append(render.Box(width = width, height = h, child = render.Row(expanded = True, children = [render.Padding(pad = (-off, 0, 0, 0), child = text)])))
    return render.Animation(children = children)

def bousai_fit(ui, s, width = None, color = None, font = None, align = "start", frames = None):
    """One line of text; scrolls (bounded to `frames`, default the whole dwell) when wider than width."""
    width = width or canvas.width()
    if bousai_text_width(ui, s, font) <= width:
        return render.Box(width = width, height = bousai_font_height(ui, font) + 1, child = render.Row(main_align = align, expanded = True, children = [bousai_text(ui, s, color, font)]))
    return bousai_ticker(ui, s, width, color, font, frames)

def bousai_font_height(ui, font = None):
    return render.Text("Mg", font = font or ui["font"]).size()[1]

def bousai_header(ui, title, color = None, right = None, frames = None):
    """Title band. color is the band colour (defaults to panel); text picks a readable colour."""
    band = color or ui["panel"]
    text_color = bousai_on(band) if color else ui["fg"]
    h = ui["line_h"]
    width = canvas.width()
    right_w = 0
    children = []
    if right:
        right_w = bousai_text_width(ui, right) + 2
    children.append(render.Padding(pad = (1, 0, 0, 0), child = bousai_fit(ui, title, width = width - right_w - 1, color = text_color, frames = frames)))
    if right:
        children.append(render.Padding(pad = (width - right_w + 1, 0, 0, 0), child = bousai_text(ui, right, text_color)))
    return render.Box(width = width, height = h, color = band, child = render.Stack(children = children))

def bousai_row(ui, item, frames = None):
    """Normalise a row: str or (text, color) become a text line inset 1 px from the left edge
    (like the header title); a prebuilt widget is used as is."""
    if type(item) == "string":
        item = (item, None)
    if type(item) == "tuple" or type(item) == "list":
        line = bousai_fit(ui, item[0], width = canvas.width() - 1, color = item[1], frames = frames)
        return render.Padding(pad = (1, 0, 0, 0), child = line)
    return item

def bousai_hold_frames(pages, min_ms = 2500):
    """Frames per page when `pages` pages share the dwell time (at least min_ms each)."""
    return max(min_ms // 100, bousai_budget_frames() // max(1, pages))

def bousai_hold(widget, frames):
    """Keep widget on screen for at least `frames` frames (marquees keep scrolling)."""
    return render.Stack(children = [widget, render.Animation(children = [render.Box(width = 1, height = 1)] * max(1, frames))])

def bousai_pages(ui, header, rows, footer = None):
    """Paginate rows under a header to fit the text size. Returns a widget.

    header: None, a title string, a (title, band_color[, right_text]) tuple, or a prebuilt widget.
    rows: str | (text, color) | widget. Strings/tuples scroll within their page's share of the
    dwell time; prebuilt widgets are used as is (keep their animation within bousai_hold_frames).
    """
    height = canvas.height()
    header_h = ui["line_h"] if header != None else 0
    footer_h = ui["line_h"] if footer != None else 0
    per_page = max(1, (height - header_h - footer_h) // ui["line_h"])
    rows = rows or [("No data", ui["muted"])]
    n_pages = (len(rows) + per_page - 1) // per_page
    frames = bousai_hold_frames(n_pages) if n_pages > 1 else bousai_budget_frames()
    if type(header) == "string":
        header = bousai_header(ui, header, frames = frames)
    elif type(header) == "tuple" or type(header) == "list":
        header = bousai_header(ui, header[0], header[1] if len(header) > 1 else None, header[2] if len(header) > 2 else None, frames = frames)
    rows = [bousai_row(ui, r, frames) for r in rows]
    pages = []
    for i in range(0, len(rows), per_page):
        children = []
        if header != None:
            children.append(header)
        for r in rows[i:i + per_page]:
            children.append(render.Box(width = canvas.width(), height = ui["line_h"], child = r))
        body = render.Box(width = canvas.width(), height = height, child = render.Column(expanded = True, main_align = "start", cross_align = "start", children = children))
        if footer != None:
            body = render.Stack(children = [body, render.Padding(pad = (0, height - footer_h, 0, 0), child = footer)])
        pages.append(body)
    if len(pages) == 1:
        return pages[0]
    return render.Sequence(children = [bousai_hold(p, frames) for p in pages])

def bousai_root(ui, child):
    return render.Root(delay = ui["delay"], child = render.Box(width = canvas.width(), height = canvas.height(), color = ui["bg"], child = child))

def bousai_message(ui, title, lines, color = None):
    """Full-screen notice (errors, 'no data', setup hints)."""
    return bousai_root(ui, bousai_pages(ui, (title, color), [(l, ui["muted"]) for l in lines]))

def bousai_badge(ui, label, color, width = None, font = None):
    """Coloured box with a centred label (colour is never the only cue)."""
    font = font or ui["font"]
    w = width or (bousai_text_width(ui, label, font) + 3)
    h = bousai_font_height(ui, font) + 2
    return render.Box(width = w, height = h, color = color, child = bousai_text(ui, label, bousai_on(color), font))

def bousai_blink(ui, widget, width, height, on_frames = 6, off_frames = 3):
    """Blinking emphasis; kept static in low-contrast mode to avoid stimulation."""
    if ui["contrast"] == "low":
        return widget
    return render.Animation(children = [widget] * on_frames + [render.Box(width = width, height = height)] * off_frames)

# ---------------------------------------------------------------------------
# Severity and seismic intensity

def bousai_sev_color(ui, level):
    return ui["sev"][max(0, min(5, level))]

def bousai_intensity_norm(v):
    """Normalise JMA / P2PQuake / EEW intensity notations to '0'..'7', '5-', '5+', '6-', '6+'. Unknown -> None."""
    if v == None:
        return None
    s = str(v).strip()
    table = {
        "5弱": "5-",
        "5強": "5+",
        "6弱": "6-",
        "6強": "6+",
        "5-": "5-",
        "5+": "5+",
        "6-": "6-",
        "6+": "6+",
        "5L": "5-",
        "5U": "5+",
        "6L": "6-",
        "6U": "6+",
        "10": "1",
        "20": "2",
        "30": "3",
        "40": "4",
        "45": "5-",
        "46": "5-",
        "50": "5+",
        "55": "6-",
        "60": "6+",
        "70": "7",
    }
    if s in table:
        return table[s]
    if s in BOUSAI_INTENSITY_ORDER:
        return s
    if s.startswith("震度"):
        return bousai_intensity_norm(s[2:])
    return None

def bousai_intensity_rank(label):
    """Index in BOUSAI_INTENSITY_ORDER, -1 for unknown."""
    if label in BOUSAI_INTENSITY_ORDER:
        return BOUSAI_INTENSITY_ORDER.index(label)
    return -1

def bousai_intensity_color(ui, label):
    return ui["intensity"].get(label, ui["muted"])

def bousai_intensity_from_value(x):
    if x < 0.5:
        return "0"
    if x < 1.5:
        return "1"
    if x < 2.5:
        return "2"
    if x < 3.5:
        return "3"
    if x < 4.5:
        return "4"
    if x < 5.0:
        return "5-"
    if x < 5.5:
        return "5+"
    if x < 6.0:
        return "6-"
    if x < 6.5:
        return "6+"
    return "7"

# ---------------------------------------------------------------------------
# Time

def bousai_now():
    return time.now().in_location(BOUSAI_JST)

def bousai_parse_time(s):
    """Parse JMA / P2PQuake / Wolfx / NIED timestamps (JST when no offset). Returns None if unparseable."""
    if not s:
        return None
    s = str(s).strip()
    if "T" in s and len(s) >= 19:
        if s.endswith("Z") or "+" in s[10:] or s[-6] == "-":
            return time.parse_time(s)
        return time.parse_time(s[:19], format = "2006-01-02T15:04:05", location = BOUSAI_JST)
    if len(s) == 14 and s.isdigit():
        return time.parse_time(s, format = "20060102150405", location = BOUSAI_JST)
    if len(s) >= 19 and s[4] == "/":
        return time.parse_time(s[:19], format = "2006/01/02 15:04:05", location = BOUSAI_JST)
    if len(s) == 16 and s[4] == "/":
        return time.parse_time(s, format = "2006/01/02 15:04", location = BOUSAI_JST)
    if len(s) >= 19 and s[4] == "-":
        return time.parse_time(s[:19], format = "2006-01-02 15:04:05", location = BOUSAI_JST)
    return None

def bousai_tz(config):
    loc = bousai_location(config)
    return loc["tz"]

def bousai_hhmm(t, tz = BOUSAI_JST):
    return t.in_location(tz).format("15:04") if t else "--:--"

def bousai_mdhm(t, tz = BOUSAI_JST):
    return t.in_location(tz).format("1/2 15:04") if t else "--"

def bousai_ago(t, now = None):
    """Compact relative age: 45s, 12m, 3h, 2d."""
    if not t:
        return "?"
    now = now or time.now()
    secs = int((now - t).seconds)
    if secs < 0:
        secs = 0
    if secs < 60:
        return "%ds" % secs
    if secs < 3600:
        return "%dm" % (secs // 60)
    if secs < 86400 * 2:
        return "%dh" % (secs // 3600)
    return "%dd" % (secs // 86400)

def bousai_fixed(x, digits = 1):
    """Format a number with exactly `digits` decimals (Starlark's % lacks precision)."""
    m = int(math.pow(10, digits))
    n = int(math.round(abs(float(x)) * m))
    sign = "-" if x < 0 and n != 0 else ""
    if digits <= 0:
        return sign + str(n)
    frac = str(n % m)
    return "%s%d.%s" % (sign, n // m, "0" * (digits - len(frac)) + frac)

# ---------------------------------------------------------------------------
# Geo

def bousai_distance_km(lat1, lon1, lat2, lon2):
    r = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = p2 - p1
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) * math.sin(dp / 2) + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2)
    return 2 * r * math.atan2(math.sqrt(a), math.sqrt(1 - a))

def bousai_bearing_name(lat1, lon1, lat2, lon2):
    """16-point compass direction from point 1 to point 2."""
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dl = math.radians(lon2 - lon1)
    y = math.sin(dl) * math.cos(p2)
    x = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl)
    deg = (math.degrees(math.atan2(y, x)) + 360.0) % 360.0
    names = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
    return names[int((deg + 11.25) // 22.5) % 16]

# ---------------------------------------------------------------------------
# Location -> JMA areas

def bousai_location(config):
    """Configured location: {lat, lon, label, tz}. Coordinates rounded to 0.001 deg (~100 m)."""
    raw = config.get("location") or BOUSAI_DEFAULT_LOCATION
    loc = json.decode(raw, default = None) or json.decode(BOUSAI_DEFAULT_LOCATION)
    lat = float(loc.get("lat", "35.6812"))
    lon = float(loc.get("lng", "139.7671"))
    return {
        "lat": math.round(lat * 1000) / 1000.0,
        "lon": math.round(lon * 1000) / 1000.0,
        "label": loc.get("locality") or loc.get("description") or "",
        "tz": loc.get("timezone") or BOUSAI_JST,
    }

def bousai_area_table():
    """JMA area.json (centers/offices/class10s/class15s/class20s with enName). Cached for a day."""
    return bousai_get_json(BOUSAI_AREA_JSON, ttl = 86400)

def bousai_in_ring(lon, lat, ring):
    """Even-odd ray casting; ring is [[lon, lat], ...]."""
    inside = False
    j = len(ring) - 1
    for i in range(len(ring)):
        xi, yi = ring[i][0], ring[i][1]
        xj, yj = ring[j][0], ring[j][1]
        if (yi > lat) != (yj > lat) and lon < (xj - xi) * (lat - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside

def bousai_in_geometry(lon, lat, geometry):
    """Point in a GeoJSON Polygon / MultiPolygon by even-odd parity over every ring.

    JMA's class20 files store separate islands as extra rings of one Polygon, so rings
    cannot be read as outer + holes; parity handles both islands and real holes.
    """
    polys = [geometry["coordinates"]] if geometry["type"] == "Polygon" else geometry["coordinates"]
    hits = 0
    for poly in polys:
        for ring in poly:
            if bousai_in_ring(lon, lat, ring):
                hits += 1
    return hits % 2 == 1

def bousai_locate_class20(lat, lon):
    """Municipality (class20) containing lat/lon, the way JMA's own pages do it.

    Bounding boxes from class20relm.json pick candidates; their simplified polygons decide.
    A point in no polygon (coast, small islands) takes the nearest box centre within ~25 km.
    Only JMA is contacted, and only with area codes.
    """
    if lat < 20.0 or lat > 46.5 or lon < 122.0 or lon > 154.5:
        return None
    relm = bousai_get_json(BOUSAI_CLASS20_BOXES, ttl = 86400)
    if relm == None:
        return None
    candidates = []
    nearest, best = None, 0.25 * 0.25
    for code, box in relm.items():
        sw, ne = box["sw"], box["ne"]
        if sw[0] <= lat and lat <= ne[0] and sw[1] <= lon and lon <= ne[1]:
            candidates.append(((ne[0] - sw[0]) * (ne[1] - sw[1]), code))
        d = ((sw[0] + ne[0]) / 2.0 - lat) * ((sw[0] + ne[0]) / 2.0 - lat) + ((sw[1] + ne[1]) / 2.0 - lon) * ((sw[1] + ne[1]) / 2.0 - lon)
        if d < best:
            nearest, best = code, d
    for _, code in sorted(candidates)[:8]:
        shape = bousai_get_json(BOUSAI_CLASS20_SHAPE % code, ttl = 30 * 86400)
        if shape and shape.get("features") and bousai_in_geometry(lon, lat, shape["features"][0]["geometry"]):
            return code
    return nearest

def bousai_area(config):
    """Resolve the configured location to JMA forecast areas.

    Returns a dict with keys class20, class15, class10, office, center (codes), pref (2-digit),
    and *_en names; or None when the location is outside Japan / cannot be resolved.
    """
    loc = bousai_location(config)
    override = (config.get("area_override") or "").strip()
    cache_key = "bousai_area:%s:%s:%s" % (override, bousai_fixed(loc["lat"], 3), bousai_fixed(loc["lon"], 3))
    cached = cache.get(cache_key)
    if cached:
        return json.decode(cached, default = None)

    table = bousai_area_table()
    if table == None:
        return None
    class20s = table["class20s"]
    if override:
        code = override if override in class20s else None
    else:
        code = bousai_locate_class20(loc["lat"], loc["lon"])
    if code == None or code not in class20s:
        return None

    c20 = class20s[code]
    c15_code = c20["parent"]
    c15 = table["class15s"].get(c15_code, {})
    c10_code = c15.get("parent", "")
    c10 = table["class10s"].get(c10_code, {})
    office_code = c10.get("parent", "")
    office = table["offices"].get(office_code, {})
    area = {
        "class20": code,
        "class15": c15_code,
        "class10": c10_code,
        "office": office_code,
        "center": office.get("parent", ""),
        "pref": code[:2],
        "class20_en": c20.get("enName", code),
        "class15_en": c15.get("enName", ""),
        "class10_en": c10.get("enName", ""),
        "office_en": office.get("enName", ""),
        "lat": loc["lat"],
        "lon": loc["lon"],
    }
    cache.set(cache_key, json.encode(area), ttl_seconds = 7 * 86400)
    return area

def bousai_land_filter(ui, child):
    """Tint a mid-grey land bitmap for the active theme."""
    return filter.Brightness(child = child, change = ui["land_brightness"])
