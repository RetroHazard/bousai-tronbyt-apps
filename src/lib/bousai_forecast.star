"""Weather forecast domain library for the Bousai suite.

JMA forecast.json (3-day + weekly), JMA wdist 3-hourly point forecast, official
English text from the JMA multilingual VPFD51 feed, AMeDAS yesterday/observed
temperatures, sunrise/sunset, pixel weather icons and screen-reader summaries.

Public API for other apps (no widgets, plain values, never raises on a missing feed):
  bousai_forecast_today(area, config)  -> dict or None
  bousai_forecast_model(area)          -> full model dict or None
  bousai_forecast_hourly(class10)      -> list of 3-hourly slots
"""

# bousai: requires core data

load("encoding/json.star", "json")
load("cache.star", "cache")
load("render.star", "canvas", "render")
load("sunrise.star", "sunrise")
load("time.star", "time")

BOUSAI_FORECAST_URL = "https://www.jma.go.jp/bosai/forecast/data/forecast/%s.json"
BOUSAI_FORECAST_CONST = "https://www.jma.go.jp/bosai/forecast/const/%s.json"
BOUSAI_FORECAST_WDIST = "https://www.jma.go.jp/bosai/jmatile/data/wdist/VPFD/%s.json"
BOUSAI_FORECAST_MULTI = "https://www.data.jma.go.jp/multi/data/VPFD51/%s_en.json"
BOUSAI_FORECAST_AMEDAS = "https://www.jma.go.jp/bosai/amedas/data/"

# 3-hourly (wdist) weather words -> [English, sprite key].
BOUSAI_FORECAST_JP_WEATHER = {
    "晴れ": ["Clear", "sun"],
    "くもり": ["Cloudy", "cloud"],
    "雨": ["Rain", "rain"],
    "雪": ["Snow", "snow"],
    "雨または雪": ["Rain or snow", "rain"],
    "みぞれ": ["Sleet", "rain"],
}

BOUSAI_FORECAST_JP_DIR = {
    "北": "N",
    "北東": "NE",
    "東": "E",
    "南東": "SE",
    "南": "S",
    "南西": "SW",
    "西": "W",
    "北西": "NW",
    "静穏": "Calm",
}

# 7x5 sprites. Y sun, M moon, C cloud, B rain, W snow, L lightning.
BOUSAI_FORECAST_MINI = {
    "sun": [".Y.Y.Y.", "..YYY..", "YYYYYYY", "..YYY..", ".Y.Y.Y."],
    "moon": ["..MMM..", ".MM....", ".MM....", ".MM....", "..MMM.."],
    "partly": [".Y.Y...", "Y.YYCC.", "..YCCCC", "..CCCCC", "......."],
    "pmoon": [".MM....", "MM.CC..", "M.CCCCC", "..CCCCC", "......."],
    "cloud": [".......", "..CC.C.", ".CCCCCC", "CCCCCCC", "CCCCCCC"],
    "rain": ["..CCC..", ".CCCCC.", "CCCCCCC", ".B.B.B.", "B.B.B.."],
    "snow": ["..CCC..", ".CCCCC.", "CCCCCCC", ".W.W.W.", "W.W.W.."],
    "thunder": ["..CCC..", ".CCCCC.", "CCCCCCC", "..LL...", "...L..."],
    "sunrain": ["YY.CC..", "Y.CCCCC", ".CCCCCC", "..B.B.B", "...B.B."],
    "sunsnow": ["YY.CC..", "Y.CCCCC", ".CCCCCC", "..W.W.W", "...W.W."],
}

def bousai_forecast_number(v):
    """Parse a JMA numeric string ('' -> None) to int."""
    if v == None or v == "":
        return None
    if type(v) == "int":
        return v
    if type(v) == "float":
        return int(v + 0.5) if v >= 0 else -int(-v + 0.5)
    f = float(v)
    return int(f + 0.5) if f >= 0 else -int(-f + 0.5)

def bousai_forecast_pad2(n):
    """Two-digit zero padded integer text (Starlark % has no width flags)."""
    return ("0%d" % n) if n < 10 else "%d" % n

def bousai_forecast_nice(s):
    """JMA upper-case English phrase -> sentence case ('MOSTLY CLOUDY' -> 'Mostly cloudy')."""
    if not s:
        return ""
    low = s.lower().replace(",", ", ").replace(",  ", ", ").replace("  ", " ").strip()
    return low[0].upper() + low[1:]

def bousai_forecast_key(code, group, en):
    """Sprite key for a JMA weather code (group = 100/200/300/400 icon group, en = English telop)."""
    c = str(code or "")
    first = c[:1]
    if group == 400:
        return "sunsnow" if first == "1" else "snow"
    if group == 300:
        if "THUNDER" in (en or ""):
            return "thunder"
        return "sunrain" if first == "1" else "rain"
    if group == 200:
        return "partly" if c in ("201", "210", "211") else "cloud"
    return "sun" if c == "100" else "partly"

def bousai_forecast_weather(code):
    """JMA code -> (English text, icon group int, sprite key)."""
    row = BOUSAI_WEATHER_EN.get(str(code or ""))
    if row == None:
        group = 200
        if code and str(code)[:1] in ("1", "2", "3", "4"):
            group = int(str(code)[:1]) * 100
        return "", group, bousai_forecast_key(code, group, "")
    en = row[0]
    group = int(row[1])
    return bousai_forecast_nice(en), group, bousai_forecast_key(code, group, en)

def bousai_forecast_val(pair):
    """AMeDAS [value, quality] -> float or None (quality >= 5 means not observed)."""
    if type(pair) != "list" or len(pair) < 2 or pair[0] == None:
        return None
    if pair[1] != None and pair[1] >= 5:
        return None
    return pair[0]

def bousai_forecast_find(areas, code):
    """Pick the entry whose area.code == code; fall back to the first entry."""
    for a in areas or []:
        if (a.get("area") or {}).get("code") == code:
            return a
    return (areas or [None])[0]

def bousai_forecast_set(info, date, key, value):
    """First writer wins: store info[date][key] unless value is empty or already set."""
    if value == None or value == "":
        return
    d = info.setdefault(date, {})
    if d.get(key) == None:
        d[key] = value

def bousai_forecast_unit_temp(c, unit):
    """Celsius number -> display number in the chosen unit (int)."""
    if c == None:
        return None
    if unit == "F":
        v = c * 9.0 / 5.0 + 32
        return int(v + 0.5) if v >= 0 else -int(-v + 0.5)
    return int(c + 0.5) if c >= 0 else -int(-c + 0.5)

def bousai_forecast_unit_diff(d, unit):
    """Celsius difference -> difference in unit (int)."""
    if d == None:
        return None
    if unit == "F":
        v = d * 9.0 / 5.0
        return int(v + 0.5) if v >= 0 else -int(-v + 0.5)
    return d

def bousai_forecast_diff_phrase(diff, ref):
    """3 -> '3 degrees higher than yesterday'; 0 -> 'same as yesterday'; None -> ''."""
    if diff == None:
        return ""
    if diff == 0:
        return "same as %s" % ref
    n = abs(diff)
    return "%d %s %s than %s" % (n, "degree" if n == 1 else "degrees", "higher" if diff > 0 else "lower", ref)

def bousai_forecast_signed(n):
    """'+3' / '-2' / '0'."""
    if n == None:
        return "--"
    return ("+%d" % n) if n > 0 else ("%d" % n)

# ---------------------------------------------------------------------------
# Data

def bousai_forecast_mapping(office, class10):
    """JMA forecast/const/week_area.json entry {srf, week, amedas} for a class10 area, or None."""
    table = bousai_get_json(BOUSAI_FORECAST_CONST % "week_area", ttl = 86400)
    if type(table) != "dict":
        return None
    for key in [office] + list(table.keys()):
        for m in table.get(key, []):
            if m.get("srf") == class10:
                return m
    return None

def bousai_forecast_yesterday(point):
    """Yesterday's observed {high, low} (Celsius floats or None) at an AMeDAS point, or None."""
    y = bousai_now() - time.parse_duration("24h")
    d = bousai_get_json(BOUSAI_FORECAST_AMEDAS + "point/%s/%s_21.json" % (point, y.format("20060102")), ttl = 86400)
    if type(d) != "dict" or len(d) == 0:
        return None
    last = d[sorted(d.keys())[-1]]
    hi = bousai_forecast_val(last.get("maxTemp"))
    lo = bousai_forecast_val(last.get("minTemp"))
    if hi == None and lo == None:
        return None
    return {"high": hi, "low": lo}

def bousai_forecast_observed(point):
    """Today's observed {high, low, temp, time} so far at an AMeDAS point, or None."""
    lt = bousai_get_bytes(BOUSAI_FORECAST_AMEDAS + "latest_time.txt", ttl = 60)
    t = bousai_parse_time((lt or "").strip())
    if t == None:
        return None
    block = "%s_%s" % (t.format("20060102"), bousai_forecast_pad2((t.hour // 3) * 3))
    d = bousai_get_json(BOUSAI_FORECAST_AMEDAS + "point/%s/%s.json" % (point, block), ttl = 120)
    if type(d) != "dict" or len(d) == 0:
        return None
    last = d[sorted(d.keys())[-1]]
    return {
        "high": bousai_forecast_val(last.get("maxTemp")),
        "low": bousai_forecast_val(last.get("minTemp")),
        "temp": bousai_forecast_val(last.get("temp")),
        "time": bousai_parse_time(sorted(d.keys())[-1]),
    }

def bousai_forecast_multi_office(class10):
    """JMA multilingual publishing office code (e.g. JPTK) for a class10 code."""
    special = BOUSAI_MULTI_OFFICE_SPECIAL.get(class10)
    if special:
        return special
    return BOUSAI_MULTI_OFFICE_BY_PREFIX.get(class10[:3]) or BOUSAI_MULTI_OFFICE_BY_PREF.get(class10[:2])

def bousai_forecast_day_label(date, today_date, idx):
    """Today / Tomorrow / weekday name for a forecast date string (relative to today_date)."""
    if date == today_date:
        return "Today"
    if idx == 1:
        return "Tomorrow"
    t = time.parse_time(date, format = "2006-01-02", location = BOUSAI_JST)
    return t.format("Monday")

def bousai_forecast_official_text(class10, rel_labels):
    """Official English forecast sentences from JMA VPFD51 for a class10 area (list of str).

    rel_labels name the forecast days of the 3-day block (e.g. ['Today', 'Tomorrow']).
    """
    office = bousai_forecast_multi_office(class10)
    if not office:
        return []
    d = bousai_get_json(BOUSAI_FORECAST_MULTI % office, ttl = 600)
    if type(d) != "dict":
        return []
    infos = (d.get("meteorologicalInfos") or {}).get("timeSeriesInfoWeather") or []
    match = None
    for it in infos:
        if str((it.get("area") or {}).get("code")) == class10:
            match = it
    if match == None:
        return []
    parts = (match.get("kind") or {}).get("weatherPart") or []
    out = []
    area_en = (match.get("area") or {}).get("name") or ""
    for i, p in enumerate(parts):
        label = rel_labels[i] if i < len(rel_labels) else "Day %d" % (i + 1)
        out.append("%s%s: %s." % (area_en + " - " if i == 0 and area_en else "", label, bousai_forecast_nice(p.get("weather"))))
    return out

def bousai_forecast_model(area):
    """Full forecast model for a JMA area (from bousai_area), or None when JMA data is unavailable.

    Keys: office, class10, class10_en, point (AMeDAS id of the temperature point), point_en,
    report (time), days (7 dicts, today first: date, label, weekday, code, weather_en, icon_group,
    key, high, low, pop, reliability, high_obs, low_obs), pops6 (list of {time, pop} six-hour
    blocks), yesterday ({high, low} or None), official (list of English sentences).
    Temperatures are Celsius ints (None if JMA gives none); times are Pixlet time objects.
    """
    office = area["office"]
    c10 = area["class10"]
    data = bousai_get_json(BOUSAI_FORECAST_URL % office, ttl = 600)
    if type(data) != "list" or len(data) == 0 or type(data[0]) != "dict":
        return None
    daily = data[0]
    week = data[1] if len(data) > 1 and type(data[1]) == "dict" else {}
    mapping = bousai_forecast_mapping(office, c10)
    week_code = mapping["week"] if mapping else c10
    point = mapping["amedas"] if mapping else None

    info = {}
    pops6 = []
    daily_dates = []
    ts = daily.get("timeSeries") or []

    # 3-day block: weather, 6-hourly rain chance, temperatures.
    if len(ts) > 0:
        a = bousai_forecast_find(ts[0].get("areas"), c10)
        if a:
            for i, td in enumerate(ts[0]["timeDefines"]):
                if i < len(a.get("weatherCodes", [])):
                    bousai_forecast_set(info, td[:10], "code", a["weatherCodes"][i])
                daily_dates.append(td[:10])
    if len(ts) > 1:
        a = bousai_forecast_find(ts[1].get("areas"), c10)
        if a:
            for i, td in enumerate(ts[1]["timeDefines"]):
                if i < len(a.get("pops", [])):
                    pops6.append({"time": bousai_parse_time(td), "pop": bousai_forecast_number(a["pops"][i])})
    if len(ts) > 2:
        a = bousai_forecast_find(ts[2].get("areas"), point) if point else bousai_forecast_find(ts[2].get("areas"), "")
        if a:
            point = a["area"]["code"]
            for i, td in enumerate(ts[2]["timeDefines"]):
                v = bousai_forecast_number(a["temps"][i]) if i < len(a.get("temps", [])) else None
                if v == None:
                    continue
                if td[11:13] == "09":
                    bousai_forecast_set(info, td[:10], "high", v)
                elif td[11:13] == "00":
                    bousai_forecast_set(info, td[:10], "low", v)

    # JMA repeats the maximum in today's 00:00 (minimum) slot once the morning minimum has passed.
    for date in info:
        d = info[date]
        if d.get("low") != None and d.get("high") != None and d["low"] >= d["high"]:
            d.pop("low")

    # Weekly block: day weather, rain chance, reliability, temperatures.
    wts = week.get("timeSeries") or []
    if len(wts) > 0:
        a = bousai_forecast_find(wts[0].get("areas"), week_code)
        if a:
            for i, td in enumerate(wts[0]["timeDefines"]):
                bousai_forecast_set(info, td[:10], "code", a["weatherCodes"][i] if i < len(a.get("weatherCodes", [])) else None)
                bousai_forecast_set(info, td[:10], "pop", bousai_forecast_number(a["pops"][i]) if i < len(a.get("pops", [])) else None)
                bousai_forecast_set(info, td[:10], "rel", a["reliabilities"][i] if i < len(a.get("reliabilities", [])) else None)
    if len(wts) > 1:
        a = bousai_forecast_find(wts[1].get("areas"), point) if point else bousai_forecast_find(wts[1].get("areas"), "")
        if a:
            point = point or a["area"]["code"]
            for i, td in enumerate(wts[1]["timeDefines"]):
                bousai_forecast_set(info, td[:10], "high", bousai_forecast_number(a["tempsMax"][i]) if i < len(a.get("tempsMax", [])) else None)
                bousai_forecast_set(info, td[:10], "low", bousai_forecast_number(a["tempsMin"][i]) if i < len(a.get("tempsMin", [])) else None)

    now = bousai_now()
    today_date = now.format("2006-01-02")
    days = []
    for i in range(7):
        t = now + time.parse_duration("%dh" % (24 * i))
        date = t.format("2006-01-02")
        d = info.get(date, {})
        code = d.get("code")
        en, group, key = bousai_forecast_weather(code) if code else ("", 200, "cloud")
        day_pops = [p["pop"] for p in pops6 if p["time"] != None and p["time"].format("2006-01-02") == date and p["pop"] != None]
        pop = max(day_pops) if day_pops else d.get("pop")
        days.append({
            "date": date,
            "label": "Today" if i == 0 else ("Tomorrow" if i == 1 else t.format("Mon")),
            "weekday": t.format("Mon"),
            "code": code,
            "weather_en": en,
            "icon_group": group,
            "key": key,
            "high": d.get("high"),
            "low": d.get("low"),
            "pop": pop,
            "reliability": d.get("rel"),
            "high_obs": False,
            "low_obs": False,
        })

    # Today's missing high (evening) / low (morning) -> observed so far.
    if point and (days[0]["high"] == None or days[0]["low"] == None):
        obs = bousai_forecast_observed(point)
        if obs:
            if days[0]["high"] == None and obs["high"] != None:
                days[0]["high"] = bousai_forecast_number(obs["high"])
                days[0]["high_obs"] = True
            if days[0]["low"] == None and obs["low"] != None:
                days[0]["low"] = bousai_forecast_number(obs["low"])
                days[0]["low_obs"] = True

    yesterday = bousai_forecast_yesterday(point) if point else None
    names = bousai_get_json(BOUSAI_FORECAST_CONST % "en_amedas", ttl = 86400) or {}
    labels = [bousai_forecast_day_label(dd, today_date, i) for i, dd in enumerate(daily_dates)]
    return {
        "office": office,
        "class10": c10,
        "class10_en": area.get("class10_en") or "",
        "point": point,
        "point_en": names.get(point or "", ""),
        "report": bousai_parse_time(daily.get("reportDatetime")),
        "days": days,
        "pops6": pops6,
        "yesterday": yesterday,
        "official": bousai_forecast_official_text(c10, labels),
    }

def bousai_forecast_round(x):
    """Round a number to the nearest int (half away from zero)."""
    return int(x + 0.5) if x >= 0 else -int(-x + 0.5)

def bousai_forecast_pop_now(model):
    """Chance of rain (int %) for the six-hour block that contains now, else the next block."""
    now = bousai_now()
    best = None
    for p in model["pops6"]:
        if p["time"] == None or p["pop"] == None:
            continue
        end = p["time"] + time.parse_duration("6h")
        if now < end:
            return p["pop"]
        best = p["pop"]
    if best != None:
        return best
    return model["days"][0]["pop"]

def bousai_forecast_sun(lat, lon, offset_days = 0):
    """Sunrise/sunset (Pixlet times in JST, or None in polar conditions) for today + offset_days."""
    now = bousai_now() + time.parse_duration("%dh" % (24 * offset_days))
    noon = time.time(year = now.year, month = now.month, day = now.day, hour = 12, location = BOUSAI_JST)
    rise = sunrise.sunrise(lat, lon, noon)
    sset = sunrise.sunset(lat, lon, noon)
    return (rise.in_location(BOUSAI_JST) if rise else None), (sset.in_location(BOUSAI_JST) if sset else None)

def bousai_forecast_hourly(class10):
    """3-hourly forecast slots from the JMA wdist point series for a class10 area.

    Returns [] when unavailable. Each slot: {time, weather_en, key, temp, wind_dir_en,
    wind_ms}. Weather is one of Clear/Cloudy/Rain/Snow/Rain or snow; temp is the point
    forecast in Celsius (int or None); wind_ms is the forecast mean speed in m/s.
    """
    d = bousai_get_json(BOUSAI_FORECAST_WDIST % class10, ttl = 600)
    if type(d) != "dict":
        return []
    series = d.get("areaTimeSeries") or {}
    pts = d.get("pointTimeSeries") or {}
    temps = {}
    for i, td in enumerate(pts.get("timeDefines") or []):
        temps[td["dateTime"]] = bousai_forecast_number((pts.get("temperature") or [])[i]) if i < len(pts.get("temperature") or []) else None
    out = []
    for i, td in enumerate(series.get("timeDefines") or []):
        w = (series.get("weather") or [""])[i] if i < len(series.get("weather") or []) else ""
        wind = (series.get("wind") or [{}])[i] if i < len(series.get("wind") or []) else {}
        conv = BOUSAI_FORECAST_JP_WEATHER.get(w, ["Unknown", "cloud"])
        out.append({
            "time": bousai_parse_time(td["dateTime"]),
            "weather_en": conv[0],
            "key": conv[1],
            "temp": temps.get(td["dateTime"]),
            "wind_dir_en": BOUSAI_FORECAST_JP_DIR.get(wind.get("direction", ""), ""),
            "wind_ms": wind.get("speed"),
        })
    return out

def bousai_forecast_today(area, _config):
    """Summary of today's forecast for home/timeline panels.

    Returns None when JMA data is unavailable, else a dict:
      weather_en  English telop, e.g. 'Mostly cloudy'
      code        JMA weather code string, e.g. '201'
      icon_group  100 sun / 200 cloud / 300 rain / 400 snow (int)
      high, low   Celsius ints (observed-so-far fallback when JMA no longer gives today's value; None if neither)
      pop_now     chance of rain (int %) of the six-hour block containing now (None if unknown)
      sunrise, sunset  Pixlet time objects in JST (None in polar conditions)
      text_en     one-paragraph official English forecast (JMA multilingual VPFD51), or None
    area is the dict from bousai_area(config); _config is the app config (accepted for a uniform call signature).
    """
    if not area:
        return None
    model = bousai_forecast_model(area)
    if model == None:
        return None
    d = model["days"][0]
    rise, sset = bousai_forecast_sun(area["lat"], area["lon"], 0)
    text = " ".join(model["official"]) if model["official"] else None
    return {
        "weather_en": d["weather_en"],
        "code": d["code"],
        "icon_group": d["icon_group"],
        "high": d["high"],
        "low": d["low"],
        "pop_now": bousai_forecast_pop_now(model),
        "sunrise": rise,
        "sunset": sset,
        "text_en": text,
    }

# ---------------------------------------------------------------------------
# Screen-reader style sentences

def bousai_forecast_sentences(model, unit, rise, sset):
    """English sentences for today and tomorrow ('Forecast high of 26 (3 degrees lower than yesterday)')."""
    out = []
    t0 = model["days"][0]
    t1 = model["days"][1]
    y = model["yesterday"] or {}
    deg = "F" if unit == "F" else "C"
    if t0["weather_en"]:
        out.append("Today: %s." % t0["weather_en"])
    if t0["high"] != None:
        diff = (t0["high"] - bousai_forecast_round(y["high"])) if y.get("high") != None else None
        phrase = bousai_forecast_diff_phrase(bousai_forecast_unit_diff(diff, unit), "yesterday")
        out.append("%s high of %d%s%s" % ("Observed" if t0["high_obs"] else "Forecast", bousai_forecast_unit_temp(t0["high"], unit), deg, (" (%s)" % phrase) if phrase else ""))
    if t0["low"] != None:
        diff = (t0["low"] - bousai_forecast_round(y["low"])) if y.get("low") != None else None
        phrase = bousai_forecast_diff_phrase(bousai_forecast_unit_diff(diff, unit), "yesterday")
        out.append("%s low of %d%s%s" % ("Observed" if t0["low_obs"] else "Forecast", bousai_forecast_unit_temp(t0["low"], unit), deg, (" (%s)" % phrase) if phrase else ""))
    pop = bousai_forecast_pop_now(model)
    if pop != None:
        out.append("Chance of rain now %d%%." % pop)
    if t1["weather_en"]:
        out.append("Tomorrow: %s." % t1["weather_en"])
    if t1["high"] != None:
        diff = (t1["high"] - t0["high"]) if t0["high"] != None else None
        phrase = bousai_forecast_diff_phrase(bousai_forecast_unit_diff(diff, unit), "today")
        out.append("Tomorrow's forecast high of %d%s%s" % (bousai_forecast_unit_temp(t1["high"], unit), deg, (" (%s)" % phrase) if phrase else ""))
    if t1["low"] != None:
        diff = (t1["low"] - t0["low"]) if t0["low"] != None else None
        phrase = bousai_forecast_diff_phrase(bousai_forecast_unit_diff(diff, unit), "today")
        out.append("Tomorrow's forecast low of %d%s%s" % (bousai_forecast_unit_temp(t1["low"], unit), deg, (" (%s)" % phrase) if phrase else ""))
    if t1["pop"] != None:
        out.append("Chance of rain tomorrow %d%%." % t1["pop"])
    if rise and sset:
        out.append("Sunrise %s, sunset %s." % (rise.format("15:04"), sset.format("15:04")))
    return out


# ---------------------------------------------------------------------------
# Pixel icons (drawn here; colours come from ui)

def bousai_forecast_palette(ui):
    return {
        "Y": ui["sev"][2],
        "M": ui["fg"],
        "C": bousai_mix(ui["fg"], ui["bg"], 0.45),
        "B": ui["sev"][1],
        "W": ui["fg"],
        "L": ui["sev"][2],
    }

def bousai_forecast_render_grid(ui, rows):
    """Render a list of equal-width strings ('.' transparent) as 1-px boxes with run-length merging."""
    pal = bousai_forecast_palette(ui)
    line_widgets = []
    for r in rows:
        runs = []
        i = 0
        n = len(r)
        for _ in range(n):
            if i >= n:
                break
            ch = r[i]
            j = i
            for _ in range(n):
                if j + 1 < n and r[j + 1] == ch:
                    j += 1
                else:
                    break
            runs.append(render.Box(width = j - i + 1, height = 1, color = pal.get(ch) if ch != "." else None))
            i = j + 1
        line_widgets.append(render.Row(children = runs))
    return render.Column(children = line_widgets)

def bousai_forecast_blank(w, h):
    return [["."] * w for _ in range(h)]

def bousai_forecast_dot(g, x, y, ch):
    if y >= 0 and y < len(g) and x >= 0 and x < len(g[0]):
        g[y][x] = ch

def bousai_forecast_disc(g, cx, cy, r2, ch):
    for y in range(len(g)):
        for x in range(len(g[0])):
            if (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r2:
                g[y][x] = ch

def bousai_forecast_sun_layer(g, cx, cy, r2, ch, ray_in, ray_out):
    bousai_forecast_disc(g, cx, cy, r2, ch)
    for d in range(ray_in, ray_out + 1):
        for v in [(1, 0), (-1, 0), (0, 1), (0, -1)]:
            bousai_forecast_dot(g, cx + v[0] * d, cy + v[1] * d, ch)
    diag = ray_in - 1
    for v in [(1, 1), (1, -1), (-1, 1), (-1, -1)]:
        bousai_forecast_dot(g, cx + v[0] * diag, cy + v[1] * diag, ch)

def bousai_forecast_cloud_layer(g, ox, oy, ch):
    for x in range(ox + 1, ox + 12):
        for y in range(oy + 4, oy + 7):
            bousai_forecast_dot(g, x, y, ch)
    bousai_forecast_disc(g, ox + 3, oy + 4, 5, ch)
    bousai_forecast_disc(g, ox + 7, oy + 3, 10, ch)
    bousai_forecast_disc(g, ox + 10, oy + 4, 5, ch)

def bousai_forecast_big(ui, key):
    """16x12 weather icon for a sprite key."""
    g = bousai_forecast_blank(16, 12)
    if key == "sun":
        bousai_forecast_sun_layer(g, 8, 6, 9, "Y", 5, 6)
    elif key == "partly":
        bousai_forecast_sun_layer(g, 5, 4, 4, "Y", 4, 5)
        bousai_forecast_cloud_layer(g, 3, 5, "C")
    elif key == "cloud":
        bousai_forecast_cloud_layer(g, 1, 2, "C")
    elif key in ("rain", "thunder"):
        bousai_forecast_cloud_layer(g, 1, 0, "C")
        if key == "rain":
            for x in (3, 7, 11):
                bousai_forecast_dot(g, x, 8, "B")
                bousai_forecast_dot(g, x - 1, 9, "B")
            for x in (5, 9, 13):
                bousai_forecast_dot(g, x, 10, "B")
                bousai_forecast_dot(g, x - 1, 11, "B")
        else:
            for p in [(8, 7), (9, 7), (7, 8), (8, 8), (7, 9), (8, 9), (9, 9), (6, 10), (7, 10), (6, 11)]:
                bousai_forecast_dot(g, p[0], p[1], "L")
    elif key == "snow":
        bousai_forecast_cloud_layer(g, 1, 0, "C")
        for p in [(3, 9), (7, 9), (11, 9), (5, 11), (9, 11), (13, 11)]:
            bousai_forecast_dot(g, p[0], p[1], "W")
            bousai_forecast_dot(g, p[0] + 1, p[1], "W")
    elif key in ("sunrain", "sunsnow"):
        bousai_forecast_sun_layer(g, 4, 4, 4, "Y", 4, 5)
        bousai_forecast_cloud_layer(g, 3, 3, "C")
        ch = "B" if key == "sunrain" else "W"
        for x in (6, 10, 14):
            bousai_forecast_dot(g, x, 10, ch)
            bousai_forecast_dot(g, x - 1, 11, ch)
    else:
        bousai_forecast_cloud_layer(g, 1, 2, "C")
    return bousai_forecast_render_grid(ui, ["".join(r) for r in g])

def bousai_forecast_mini(ui, key):
    """7x5 weather icon for a sprite key."""
    return bousai_forecast_render_grid(ui, BOUSAI_FORECAST_MINI.get(key) or BOUSAI_FORECAST_MINI["cloud"])

def bousai_forecast_is_night(t, rise, sset):
    """True when t (a time) lies outside sunrise..sunset by clock time of day."""
    if rise == None or sset == None:
        return False
    tod = t.hour * 60 + t.minute
    return tod < rise.hour * 60 + rise.minute or tod >= sset.hour * 60 + sset.minute

# ---------------------------------------------------------------------------
# Layout helper

def bousai_forecast_clip(ui, text, width):
    """Trim text (no ellipsis) until it fits width, so pages never contain scrolling marquees
    (a marquee stretches its page's duration in a Sequence)."""
    t = text
    for _ in range(len(text)):
        if bousai_text_width(ui, t) <= width:
            break
        t = t[:-1]
    return t

def bousai_forecast_header(ui, title, right = None):
    """Title band whose title is clipped to fit (never scrolls)."""
    avail = canvas.width() - 2
    if right:
        avail -= bousai_text_width(ui, right) + 2
    return bousai_header(ui, bousai_forecast_clip(ui, title, avail), right = right)

def bousai_forecast_pager(ui, header, left, left_w, rows):
    """Pages of header + left widget + right-hand text rows. rows are (text, color).

    Returns a list of page widgets (not yet held); each page shows as many rows as fit.
    """
    width = canvas.width()
    body_h = canvas.height() - ui["line_h"]
    cap = max(1, body_h // ui["line_h"])
    right_w = width - left_w - 1
    pages = []
    for i in range(0, max(1, len(rows)), cap):
        chunk = rows[i:i + cap]
        col = render.Column(children = [render.Box(width = right_w, height = ui["line_h"], child = bousai_fit(ui, bousai_forecast_clip(ui, r[0], right_w), width = right_w, color = r[1])) for r in chunk])
        pages.append(render.Column(children = [
            header,
            render.Row(children = [
                render.Box(width = left_w, height = body_h, child = left),
                col,
            ]),
        ]))
    return pages

def bousai_forecast_rotate(pages, key, min_frames = 25):
    """Sequence of pages that each stay on screen at least min_frames (2.5 s by default).

    pages is a list of (widget, weight); a page holds min_frames * weight frames. When all pages
    fit the dwell budget (bousai_budget_frames) they are all shown and the spare time is shared.
    Otherwise a window of consecutive pages that fits is shown, starting at an offset stored in
    the cache under `key` and advanced on every render, so every page appears across renders.
    """
    n = len(pages)
    budget = bousai_budget_frames()
    base = [int(min_frames * p[1]) for p in pages]
    total = 0
    for f in base:
        total += f
    chosen = list(range(n))
    if total > budget and n > 1:
        start = int(cache.get(key) or "0") % n
        chosen = []
        used = 0
        for k in range(n):
            i = (start + k) % n
            if chosen and used + base[i] > budget:
                break
            chosen.append(i)
            used += base[i]
        cache.set(key, str(start + len(chosen)), ttl_seconds = 86400)
        total = used
    # Share spare time, but never stretch a page beyond twice its minimum.
    kids = []
    for i in chosen:
        frames = base[i]
        if total < budget:
            frames = min(base[i] * 2, int(base[i] * budget / total))
        kids.append(bousai_hold(render.Column(expanded = True, main_align = "start", children = [pages[i][0]]), frames))
    return kids[0] if len(kids) == 1 else render.Sequence(children = kids)
