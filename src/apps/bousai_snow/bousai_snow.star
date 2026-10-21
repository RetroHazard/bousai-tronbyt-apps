"""
Applet: Bousai Snow
Summary: JMA snow depth and snowfall
Description: JMA analysed snow depth and short-term snowfall forecast on a 5 km grid around your location, with 3, 6, 12 and 24 hour snowfall options, a text key and nearby AMeDAS snow readings.
Author: Bousai Apps
"""

# bousai: requires core map tiles

load("schema.star", "schema")
load("time.star", "time")

# element id -> (menu text, tile element, class bounds high to low, unit, AMeDAS key, banner text)
SNOW_ELEMENTS = [
    ("snowd", "Snow depth", "snowd", [200, 150, 100, 50, 20, 5], "cm", "snow", "No snow"),
    ("snowf03h", "Snowfall, 3 hours", "snowf03h", [30, 25, 20, 15, 10, 5, 3], "cm/3h", "snow3h", "No snowfall"),
    ("snowf06h", "Snowfall, 6 hours", "snowf06h", [40, 30, 25, 20, 15, 10, 5], "cm/6h", "snow6h", "No snowfall"),
    ("snowf12h", "Snowfall, 12 hours", "snowf12h", [50, 40, 30, 25, 20, 15, 7], "cm/12h", "snow12h", "No snowfall"),
    ("snowf24h", "Snowfall, 24 hours", "snowf24h", [70, 60, 50, 40, 30, 20, 10], "cm/24h", "snow24h", "No snowfall"),
]

# JMA snow tile colours, strongest first (legend of the JMA snow page).
SNOW_COLORS = ["#b40068", "#ff2800", "#ff9900", "#faf500", "#0041ff", "#218cff", "#a0d2ff", "#f0f0f8"]

def snow_element(config):
    key = config.get("element") or "snowd"
    for e in SNOW_ELEMENTS:
        if e[0] == key:
            return e
    return SNOW_ELEMENTS[0]

def snow_key(bounds):
    """Colour key entries from the class bounds, each class labelled by its lower bound: '200+', '150+' ... '<5'."""
    out = []
    for i in range(len(bounds)):
        out.append((SNOW_COLORS[i], "%d+" % bounds[i]))
    out.append((SNOW_COLORS[len(bounds)], "<%d" % bounds[-1]))
    return out

def snow_frames(element, tz, now_u):
    """Analysis at -6 h, -3 h and Now, then the short-term forecast at +2, +4 and +6 hours."""
    index = bousai_jmatile_times("snow/targetTimes.json", ttl = 300)
    rows = bousai_tiles_entries(index, element)
    ana = [e for e in rows if e["u"] == e["bu"]]
    if len(ana) == 0:
        return []
    newest = ana[-1]
    t0 = newest["u"]
    picks = [e for e, _ in bousai_tiles_pick([e for e in ana if e["u"] < t0], t0, [-360, -180], 30)]
    picks.append(newest)
    picks.extend([e for e, _ in bousai_tiles_pick([e for e in rows if e["u"] > t0], t0, [120, 240, 360], 40)])
    frames = []
    for e in picks:
        frames.append(bousai_tiles_frame("snow", e, element, bousai_tiles_rel(bousai_tiles_minutes(e["u"], t0)), bousai_tiles_clock(e["t"], tz), bousai_tiles_ttl(e, now_u), 1 if e["u"] == t0 else 0))
    frames[-1]["hold"] = max(frames[-1]["hold"], 2)
    return frames

def snow_reading(v, unit):
    return "%scm" % bousai_fixed(v, 0) if unit == "cm" else "%s%s" % (bousai_fixed(v, 0), unit)

def snow_status(ui, loc, spec):
    """AMeDAS snow gauges within 80 km: depth or the matching snowfall window (real numbers)."""
    snap = bousai_tiles_amedas_near(loc["lat"], loc["lon"], 80.0)
    if snap == None:
        return [("AMeDAS offline", ui["muted"]), ("No snow readings", ui["muted"])]
    key = spec[5]
    unit = spec[4]
    seen = [s for s in snap["stations"] if s[key] != None]
    rows = [("AMeDAS " + bousai_tiles_clock(snap["time"], loc["tz"]), ui["muted"])]
    if len(seen) == 0:
        rows.append(("No snow gauge", ui["fg"]))
        rows.append(("within 80km", ui["muted"]))
        return rows
    top = sorted(seen, key = lambda s: -s[key])[0]
    first = seen[0]
    if top[key] > 0:
        rows.append(("Snow reported", ui["accent"]))
        rows.append(("Max " + snow_reading(top[key], unit), ui["fg"]))
        rows.append((bousai_tiles_place(top), ui["muted"]))
    else:
        rows.append(("No snow reported", ui["fg"]))
        rows.append(("%d gauges, 80km" % len(seen), ui["muted"]))
    rows.append(("Nearest " + bousai_tiles_place(first), ui["muted"]))
    rows.append((snow_reading(first[key], unit), ui["fg"]))
    return rows

def main(config):
    ui = bousai_ui(config)
    loc = bousai_location(config)
    if not bousai_tiles_covered(loc, "nowc"):
        return bousai_message(ui, "Snow", ["Outside JMA", "snow coverage"])
    opts = bousai_tiles_options(config, "region")
    spec = snow_element(config)
    frames = snow_frames(spec[2], loc["tz"], time.now().unix)
    if len(frames) == 0:
        return bousai_message(ui, "Snow", ["No snow data", "from JMA now"])
    built = bousai_tiles_build(ui, loc, bousai_tiles_view(loc, opts), opts, frames, {"zooms": BOUSAI_TILES_PRODUCT_ZOOMS["snow"], "empty": spec[6]})
    key = {"title": "Snow", "unit": spec[4], "entries": snow_key(spec[3])} if opts["legend"] else None
    return bousai_tiles_root(ui, opts, built, {"title": "Snow gauges", "rows": snow_status(ui, loc, spec)}, key)

def get_schema():
    return bousai_tiles_schema([
        schema.Dropdown(
            id = "element",
            name = "Layer",
            desc = "Analysed snow depth, or the amount of snow that fell (analysis) or is forecast to fall in a 3, 6, 12 or 24 hour window.",
            icon = "snowflake",
            default = "snowd",
            options = [schema.Option(display = e[1], value = e[0]) for e in SNOW_ELEMENTS],
        ),
    ], "region")
