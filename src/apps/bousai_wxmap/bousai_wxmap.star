"""
Applet: Bousai Weather Map
Summary: JMA 5 km weather forecast map
Description: JMA weather distribution forecast on a 5 km grid until midnight of the next day: weather, temperature, 3-hour rain or 3-hour snow around your location, every frame topped by one bar with its time and the forecast weather and temperature, and a JMA colour-key strip along the bottom.
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

# JMA weather distribution tile colours in legend order (legend of the JMA weather distribution page), with the class each marks.
WX_KEYS = {
    "wm": [("#ffaa00", "Clear"), ("#aaaaaa", "Cloudy"), ("#0041ff", "Rain"), ("#a0d2ff", "Rain/snow"), ("#f2f2ff", "Snow")],
    "temp": [
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
    ],
    "r3": [("#ff9900", "20+"), ("#faf500", "15-20"), ("#0041ff", "10-15"), ("#218cff", "5-10"), ("#a0d2ff", "1-5")],
    "s3": [("#0041ff", "6+"), ("#218cff", "3-6"), ("#a0d2ff", "1-3")],
}

# The forecast texts JMA's regional three-hourly forecast uses, abbreviated for the frame bar (JMA weather legend in English).
WX_WEATHER_EN = {"晴れ": "Clr", "くもり": "Cldy", "雨": "Rain", "雨または雪": "R/S", "雪": "Snow"}

# Kanji weekdays as 5x6 bitmaps for the top bar (Pixlet's small fonts have no CJK glyphs), keyed by Go's "Mon" format.
WX_WEEKDAY_KANJI = {
    "Sun": [".####", ".#..#", ".####", ".#..#", ".#..#", ".####"],  # 日
    "Mon": ["..###", "..#.#", "..###", "..#.#", ".#..#", "#..##"],  # 月
    "Tue": ["..#..", "#.#.#", "..#..", "..#..", ".#.#.", "#...#"],  # 火
    "Wed": ["..#..", "###.#", "..##.", "..#..", ".#.#.", "#.#.#"],  # 水
    "Thu": ["..#..", "#####", "..#..", ".###.", "#.#.#", "..#.."],  # 木
    "Fri": ["..#..", ".#.#.", "#####", "..#..", "#.#.#", "#####"],  # 金
    "Sat": ["..#..", "..#..", ".###.", "..#..", "..#..", "#####"],  # 土
}

def wx_number(v):
    return type(v) == "int" or type(v) == "float"

def wx_forecast(loc):
    """JMA regional three-hourly forecast (VPFD) for the area of the location, or None.

    Returns {"wx": {valid unix: abbreviated English weather}, "temp": {valid unix: degrees C}}. Weather periods
    are keyed by their end, which is the tile valid time.
    """
    area = bousai_tiles_first_area(loc["lat"], loc["lon"])
    if area == None:
        return None
    out = {"wx": {}, "temp": {}}
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
    stamps = point.get("timeDefines") or []
    values = point.get("temperature") or []
    for i in range(min(len(stamps), len(values))):
        t = bousai_parse_time(stamps[i].get("dateTime"))
        if t != None and wx_number(values[i]):
            out["temp"][t.unix] = int(values[i])
    return out

def wx_frames(element, tz, now_u, fc):
    """Forecast frames from the 3-hourly index, from the current period on, up to midnight of the next day."""
    rows = [e for e in bousai_tiles_entries(bousai_jmatile_times("wdist/targetTimes.json", ttl = 600), element) if e["u"] >= now_u - 5400]
    frames = []
    for e in rows[:14]:
        local = e["t"].in_location(tz)
        hour = local.hour
        window = element in ("r3", "s3")
        label = "%d-%dh" % ((hour + 21) % 24, hour) if window else "%dh" % hour
        f = bousai_tiles_frame("wdist", e, element, label, None, bousai_tiles_ttl(e, now_u))
        f["lead"] = WX_WEEKDAY_KANJI[local.format("Mon")]

        # The weather period ends at the valid time, so it is exactly the rain/snow window. The point temperature
        # (an instant: the end of the frame) goes to the right of the bar.
        if fc != None:
            f["note"] = fc["wx"].get(e["u"])
            if e["u"] in fc["temp"]:
                f["right"] = "%dC" % fc["temp"][e["u"]]
        frames.append(f)
    if len(frames) > 0:
        frames[0]["hold"] = 1
        frames[-1]["hold"] = max(frames[-1]["hold"], 2)
    return frames

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
    spec = {"zooms": BOUSAI_TILES_PRODUCT_ZOOMS["wdist"], "empty": "No data", "bar": True, "footer": [e[0] for e in WX_KEYS[element]]}
    built = bousai_tiles_build(ui, loc, bousai_tiles_view(loc, opts), opts, frames, spec)
    return bousai_tiles_root(ui, opts, built)

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
    ], "region", legend = False)
