"""
Applet: Bousai Weather Map
Summary: JMA 5 km weather forecast map
Description: JMA weather distribution forecast on a 5 km grid until midnight of the next day: weather, temperature, 3-hour rain or 3-hour snow around your location, every frame labelled and the forecast weather and temperature written out as text.
Author: Bousai Apps
"""

# bousai: requires core map tiles

load("schema.star", "schema")
load("time.star", "time")

WX_ELEMENTS = [
    ("wm", "Weather"),
    ("temp", "Temperature"),
    ("r3", "Rain, 3 hours"),
    ("s3", "Snow, 3 hours"),
]

# JMA weather distribution tile colours (legend of the JMA weather distribution page).
WX_KEYS = {
    "wm": ("Weather", None, [("#ffaa00", "Clear"), ("#aaaaaa", "Cloudy"), ("#0041ff", "Rain"), ("#a0d2ff", "Rain/snow"), ("#f2f2ff", "Snow")]),
    "temp": ("Temp", "C", [
        ("#50002e", "40+"),
        ("#b40068", "35+"),
        ("#ff2800", "30+"),
        ("#ff9900", "25+"),
        ("#faf500", "20+"),
        ("#ffff96", "15+"),
        ("#fffff0", "10+"),
        ("#b9ebff", "5+"),
        ("#0096ff", "0+"),
        ("#0041ff", "-5+"),
        ("#002080", "-10+"),
        ("#4d4471", "-15+"),
        ("#776fa4", "-20+"),
        ("#a8a3c5", "-25+"),
        ("#d8d6e4", "<-25"),
    ]),
    "r3": ("Rain", "mm/3h", [("#ff9900", "20+"), ("#faf500", "15-20"), ("#0041ff", "10-15"), ("#218cff", "5-10"), ("#a0d2ff", "1-5")]),
    "s3": ("Snow", "cm/3h", [("#0041ff", "6+"), ("#218cff", "3-6"), ("#a0d2ff", "1-3")]),
}

# The forecast texts JMA's regional three-hourly forecast uses, in English (as in the JMA weather legend).
WX_WEATHER_EN = {"晴れ": "Clear", "くもり": "Cloudy", "雨": "Rain", "雨または雪": "Rain/snow", "雪": "Snow"}

def wx_number(v):
    return type(v) == "int" or type(v) == "float"

def wx_forecast(loc):
    """JMA regional three-hourly forecast (VPFD) for the area of the location, or None.

    Returns {"area": area name, "city": temperature point, "wx": {valid unix: English weather},
    "temp": {valid unix: degrees C}}. Weather periods are keyed by their end, which is the tile valid time.
    """
    area = bousai_tiles_first_area(loc["lat"], loc["lon"])
    if area == None:
        return None
    out = {"area": area["name"], "city": "", "wx": {}, "temp": {}}
    data = bousai_get_json("%s/wdist/VPFD/%s.json" % (BOUSAI_JMATILE, area["code"]), ttl = 900)
    if type(data) != "dict":
        return out
    series = data.get("areaTimeSeries") or {}
    stamps = series.get("timeDefines") or []
    words = series.get("weather") or []
    for i in range(min(len(stamps), len(words))):
        t = bousai_parse_time(stamps[i].get("dateTime"))
        if t != None and words[i] in WX_WEATHER_EN:
            out["wx"][t.unix + 10800] = WX_WEATHER_EN[words[i]]
    point = data.get("pointTimeSeries") or {}
    out["city"] = point.get("pointNameEN") or ""
    stamps = point.get("timeDefines") or []
    values = point.get("temperature") or []
    for i in range(min(len(stamps), len(values))):
        t = bousai_parse_time(stamps[i].get("dateTime"))
        if t != None and wx_number(values[i]):
            out["temp"][t.unix] = int(values[i])
    return out

def wx_note(fc, u):
    """'Cloudy 21C' for a frame valid time, from the regional forecast."""
    if fc == None:
        return None
    parts = []
    if u in fc["wx"]:
        parts.append(fc["wx"][u])
    if u in fc["temp"]:
        parts.append("%dC" % fc["temp"][u])
    return " ".join(parts) if parts else None

def wx_frames(element, tz, now_u, fc):
    """Forecast frames from the 3-hourly index, from the current period on, up to midnight of the next day."""
    rows = [e for e in bousai_tiles_entries(bousai_jmatile_times("wdist/targetTimes.json", ttl = 600), element) if e["u"] >= now_u - 5400]
    frames = []
    for e in rows[:14]:
        local = e["t"].in_location(tz)
        hour = local.hour
        label = "%s %d-%dh" % (local.format("Mon"), (hour + 21) % 24, hour) if element in ("r3", "s3") else "%s %dh" % (local.format("Mon"), hour)
        f = bousai_tiles_frame("wdist", e, element, label, None, bousai_tiles_ttl(e, now_u))
        f["note"] = wx_note(fc, e["u"])
        frames.append(f)
    if len(frames) > 0:
        frames[0]["hold"] = 1
        frames[-1]["hold"] = max(frames[-1]["hold"], 2)
    return frames

def wx_status(ui, loc, fc):
    """Forecast area and temperature point, plus the nearest AMeDAS temperature now."""
    rows = []
    if fc != None:
        rows.append(("Forecast area", ui["muted"]))
        rows.append((fc["area"], ui["fg"]))
        if fc["city"]:
            rows.append(("Temp: " + fc["city"], ui["muted"]))
    snap = bousai_tiles_amedas_near(loc["lat"], loc["lon"], 40.0)
    if snap != None:
        seen = [s for s in snap["stations"] if s["temp"] != None]
        if len(seen) > 0:
            rows.append(("AMeDAS " + bousai_tiles_clock(snap["time"], loc["tz"]), ui["muted"]))
            rows.append((bousai_tiles_place(seen[0]), ui["muted"]))
            rows.append(("%sC now" % bousai_fixed(seen[0]["temp"], 1), ui["fg"]))
    if len(rows) == 0:
        rows.append(("No text forecast", ui["muted"]))
        rows.append(("for this area", ui["muted"]))
    return rows

def main(config):
    ui = bousai_ui(config)
    loc = bousai_location(config)
    if not bousai_tiles_covered(loc, "wdist"):
        return bousai_message(ui, "Weather map", ["Outside JMA", "forecast grid"])
    opts = bousai_tiles_options(config, "region")
    element = config.get("element") or "wm"
    if element not in WX_KEYS:
        element = "wm"
    fc = wx_forecast(loc)
    frames = wx_frames(element, loc["tz"], time.now().unix, fc)
    if len(frames) == 0:
        return bousai_message(ui, "Weather map", ["No forecast map", "from JMA now"])
    built = bousai_tiles_build(ui, loc, bousai_tiles_view(loc, opts), opts, frames, {"zooms": BOUSAI_TILES_PRODUCT_ZOOMS["wdist"], "empty": "No data"})
    title, unit, entries = WX_KEYS[element]
    key = {"title": title, "unit": unit, "entries": entries} if opts["legend"] else None
    return bousai_tiles_root(ui, opts, built, {"title": "Forecast", "rows": wx_status(ui, loc, fc)}, key)

def get_schema():
    return bousai_tiles_schema([
        schema.Dropdown(
            id = "element",
            name = "Layer",
            desc = "Weather, temperature, 3-hour rain or 3-hour snow forecast on JMA's 5 km grid.",
            icon = "cloudSunRain",
            default = "wm",
            options = [schema.Option(display = e[1], value = e[0]) for e in WX_ELEMENTS],
        ),
    ], "region")
