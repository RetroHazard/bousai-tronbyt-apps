"""Map helpers: Web Mercator views, embedded land basemaps and JMA tile layers."""

# bousai: requires core mapdata

load("encoding/base64.star", "base64")
load("math.star", "math")
load("render.star", "canvas", "render")

BOUSAI_JMATILE = "https://www.jma.go.jp/bosai/jmatile/data"
BOUSAI_MASK_URL = BOUSAI_JMATILE + "/map/none/none/none/surf/mask/{z}/{x}/{y}.png"

def bousai_world_px(lat, lon, zoom):
    """Web Mercator world pixel coordinates (256 px tiles) at a fractional zoom."""
    size = 256.0 * math.pow(2, zoom)
    lat = max(-85.0, min(85.0, lat))
    r = math.radians(lat)
    x = (lon + 180.0) / 360.0 * size
    y = (1.0 - math.log(math.tan(r) + 1.0 / math.cos(r)) / math.pi) / 2.0 * size
    return x, y

def bousai_view(lat, lon, zoom, width = None, height = None):
    """A map view centred on lat/lon. zoom may be fractional."""
    w = width or canvas.width()
    h = height or canvas.height()
    cx, cy = bousai_world_px(lat, lon, zoom)
    return {"zoom": zoom, "ox": cx - w / 2.0, "oy": cy - h / 2.0, "w": w, "h": h}

def bousai_view_fit(points, width = None, height = None, pad = 3, min_zoom = 2.0, max_zoom = 9.0):
    """Smallest-zoom-out view containing every (lat, lon) in points."""
    w = width or canvas.width()
    h = height or canvas.height()
    xs, ys = [], []
    for p in points:
        x, y = bousai_world_px(p[0], p[1], 0)
        xs.append(x)
        ys.append(y)
    dx = max(max(xs) - min(xs), 0.0001)
    dy = max(max(ys) - min(ys), 0.0001)
    fit = min((w - 2 * pad) / dx, (h - 2 * pad) / dy)
    zoom = max(min_zoom, min(max_zoom, math.log(fit, 2)))
    clat, clon = bousai_unproject((min(xs) + max(xs)) / 2.0, (min(ys) + max(ys)) / 2.0, 0)
    return bousai_view(clat, clon, zoom, w, h)

def bousai_unproject(x, y, zoom):
    size = 256.0 * math.pow(2, zoom)
    lon = x / size * 360.0 - 180.0
    n = math.pi - 2.0 * math.pi * y / size
    lat = math.degrees(math.atan(0.5 * (math.exp(n) - math.exp(-n))))
    return lat, lon

def bousai_view_xy(view, lat, lon):
    """Screen pixel of lat/lon in view (ints, may be off-screen)."""
    x, y = bousai_world_px(lat, lon, view["zoom"])
    return int(math.floor(x - view["ox"])), int(math.floor(y - view["oy"]))

def bousai_in_view(view, x, y):
    return x >= 0 and y >= 0 and x < view["w"] and y < view["h"]

def bousai_place(x, y, child):
    """Position child with its top-left at (x, y); negative offsets are clipped by the parent."""
    return render.Padding(pad = (x, y, 0, 0), child = child)

def bousai_basemap(ui, view, name = "japan"):
    """Embedded land silhouette scaled into the view, tinted for the theme."""
    m = BOUSAI_BASEMAPS[name]
    scale = math.pow(2, view["zoom"] - m["zoom"])
    w = max(1, int(m["w"] * scale + 0.5))
    h = max(1, int(m["h"] * scale + 0.5))
    x = int(math.floor(m["x0"] * scale - view["ox"]))
    y = int(math.floor(m["y0"] * scale - view["oy"]))
    img = render.Image(src = base64.decode(m["png"]), width = w, height = h)
    return bousai_place(x, y, bousai_land_filter(ui, img))

def bousai_tile_layer(view, url_template, tile_zoom, ttl = 300, max_tiles = 9):
    """Slippy-map tiles at integer tile_zoom, scaled into view. Missing tiles (no data) are skipped.

    url_template uses {z}/{x}/{y}. Returns a list of positioned widgets for a render.Stack.
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
    out = []
    count = 0
    for ty in range(ty0, ty1 + 1):
        if ty < 0 or ty >= n:
            continue
        for tx in range(tx0, tx1 + 1):
            if count >= max_tiles:
                return out
            count += 1
            src = bousai_get_bytes(url_template.format(z = tile_zoom, x = tx % n, y = ty), ttl = ttl)
            if src == None:
                continue
            px = int(math.floor(tx * tile_px - view["ox"]))
            py = int(math.floor(ty * tile_px - view["oy"]))
            nx = int(math.floor((tx + 1) * tile_px - view["ox"]))
            ny = int(math.floor((ty + 1) * tile_px - view["oy"]))
            out.append(bousai_place(px, py, render.Image(src = src, width = nx - px, height = ny - py)))
    return out

def bousai_jmatile_times(path, ttl = 60):
    """JMA tile target-time index, e.g. 'nowc/targetTimes_N1.json'. Returns [] on failure."""
    return bousai_get_json(BOUSAI_JMATILE + "/" + path, ttl = ttl) or []

def bousai_jmatile_url(kind, basetime, validtime, element, member = "none"):
    """Tile URL template for a JMA tile product (kind: nowc, rasrf, wdist, snow, risk, ...)."""
    return "%s/%s/%s/%s/%s/surf/%s/{z}/{x}/{y}.png" % (BOUSAI_JMATILE, kind, basetime, member, validtime, element)

def bousai_mask_layer(view, tile_zoom):
    """JMA coastline/prefecture border overlay."""
    return bousai_tile_layer(view, BOUSAI_MASK_URL, tile_zoom, ttl = 7 * 86400)

def bousai_marker(ui, view, lat, lon, color, size = 3):
    """Square marker centred on lat/lon, with a contrasting outline when contrast is high."""
    x, y = bousai_view_xy(view, lat, lon)
    half = size // 2
    box = render.Box(width = size, height = size, color = color)
    if ui["frame"]:
        box = render.Box(width = size + 2, height = size + 2, color = ui["bg"], child = box)
        half += 1
    return bousai_place(x - half, y - half, box)

def bousai_cross(ui, view, lat, lon, color, arm = 2):
    """'+' marker for epicentres / your location; haloed in high contrast."""
    x, y = bousai_view_xy(view, lat, lon)
    layers = []
    if ui["frame"]:
        layers.append(bousai_place(x - arm - 1, y - 1, render.Box(width = 2 * arm + 3, height = 3, color = ui["bg"])))
        layers.append(bousai_place(x - 1, y - arm - 1, render.Box(width = 3, height = 2 * arm + 3, color = ui["bg"])))
    layers.append(bousai_place(x - arm, y, render.Box(width = 2 * arm + 1, height = 1, color = color)))
    layers.append(bousai_place(x, y - arm, render.Box(width = 1, height = 2 * arm + 1, color = color)))
    return render.Stack(children = layers)

def bousai_map_frame(ui, view, layers):
    """Clip layers to the view size over the theme background."""
    return render.Box(width = view["w"], height = view["h"], color = ui["bg"], child = render.Stack(children = layers))
