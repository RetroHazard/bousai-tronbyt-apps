"""
Applet: Bousai AMeDAS
Summary: Live JMA observations
Description: Real-time AMeDAS observations from the Japan Meteorological Agency every 10 minutes: temperature, humidity, rain, wind, gusts, snow and sunshine, with a trend chart.
Author: Bousai Apps
"""

# bousai: requires core amedas

load("render.star", "canvas", "render")
load("schema.star", "schema")

def am_hi(ui):
    """Colour for highs / sun / rise (mono palette falls back to full-contrast text)."""
    return ui["fg"] if ui["palette"] == "mono" else ui["sev"][2]

def am_lo(ui):
    """Colour for lows / rain / set (mono palette falls back to full-contrast text)."""
    return ui["fg"] if ui["palette"] == "mono" else ui["sev"][1]

def am_warn(ui):
    return ui["sev"][3]

def am_row_pages(ui, rows):
    """Full-width text rows, as many per page as fit (no header)."""
    cap = max(1, canvas.height() // ui["line_h"])
    pages = []
    for i in range(0, max(1, len(rows)), cap):
        pages.append(render.Column(children = [render.Box(width = canvas.width(), height = ui["line_h"], child = render.Padding(pad = (1, 0, 0, 0), child = bousai_fit(ui, r[0], color = r[1]))) for r in rows[i:i + cap]]))
    return pages

def am_left_panel(ui, series, temp, unit, body_h, max_big_w):
    """Big temperature with a tiny sparkline. Returns (widget, width)."""
    text = bousai_amedas_temp(temp, unit)
    big = ui["big_font"]
    if bousai_text_width(ui, text, big) > max_big_w:
        big = ui["font"]
    tw = bousai_text_width(ui, text, big)
    uw = bousai_text_width(ui, unit, ui["small_font"])
    width = tw + uw + 3
    th = bousai_font_height(ui, big)
    kids = [render.Row(cross_align = "end", children = [
        bousai_text(ui, text, ui["fg"], big),
        bousai_text(ui, unit, ui["muted"], ui["small_font"]),
    ])]
    spark_h = min(9, body_h - th - 2)
    if spark_h >= 5:
        spark = bousai_amedas_spark(ui, bousai_amedas_values(series, "temp"), width - 2, spark_h, am_hi(ui))
        if spark:
            kids.append(render.Box(width = 1, height = 1))
            kids.append(spark)
    return render.Column(cross_align = "center", children = kids), width

def am_pick(ui, width, options):
    """First option that fits in width (the last option is always short enough to fit)."""
    for o in options:
        if bousai_text_width(ui, o) <= width:
            return o
    return bousai_amedas_clip(ui, options[-1], width)

def am_groups(ui, config, cur, units, dist_km, bearing, sid):
    """Observation items grouped per page. An item is (label, short label, value, unit, colour)."""
    e = cur["e"]
    wu = bousai_amedas_wind_unit(units["wind"])
    pu = units["precip"]
    su = "in" if pu == "in" else "cm"
    g = {
        "overview": {"title": "", "items": []},
        "rain": {"title": "Rain " + pu, "items": []},
        "wind": {"title": "Wind " + wu, "items": []},
        "snow": {"title": "Snow " + su, "items": []},
        "info": {"title": "Stn " + sid, "items": []},
    }
    if (bousai_now() - cur["time"]).minutes > 30:
        g["overview"]["items"].append(("Old", "Old", bousai_ago(cur["time"]), "", am_warn(ui)))
    hum = bousai_amedas_val(e.get("humidity"))
    if bousai_bool(config, "el_humidity", True) and hum != None:
        g["overview"]["items"].append(("Hum", "H", "%d" % int(hum + 0.5), "%", ui["fg"]))
    if bousai_bool(config, "el_extremes", True):
        hi = bousai_amedas_val(e.get("maxTemp"))
        lo = bousai_amedas_val(e.get("minTemp"))
        if hi != None:
            g["overview"]["items"].append(("Hi", "H", bousai_amedas_temp(hi, units["temp"]), units["temp"], am_hi(ui)))
        if lo != None:
            g["overview"]["items"].append(("Lo", "L", bousai_amedas_temp(lo, units["temp"]), units["temp"], am_lo(ui)))
    if bousai_bool(config, "el_precip", True):
        for label, short, key in [("10 min", "10m", "precipitation10m"), ("1 hour", "1h", "precipitation1h"), ("24 hours", "24h", "precipitation24h")]:
            v = bousai_amedas_val(e.get(key))
            if v != None:
                g["rain"]["items"].append((label, short, bousai_amedas_precip(v, pu), pu, am_lo(ui) if v > 0 else ui["fg"]))
    if bousai_bool(config, "el_wind", True):
        ws = bousai_amedas_val(e.get("wind"))
        if ws != None:
            d = bousai_amedas_dir(bousai_amedas_val(e.get("windDirection")))
            if d == "Calm" or (ws < 0.3 and d == None):
                g["wind"]["items"].append(("Wind", "Wind", "calm", "", ui["fg"]))
            else:
                g["wind"]["items"].append((d or "Wind", d or "W", bousai_amedas_wind(ws, units["wind"]), wu, ui["fg"]))
        gust = bousai_amedas_val(e.get("gust"))
        if gust != None:
            g["wind"]["items"].append(("Gust", "G", bousai_amedas_wind(gust, units["wind"]), wu, ui["fg"]))
    if bousai_bool(config, "el_snow", True):
        depth = bousai_amedas_val(e.get("snow"))
        if depth != None and depth > 0:
            g["snow"]["items"].append(("Depth", "D", bousai_amedas_depth(depth, pu), su, ui["fg"]))
        new1 = bousai_amedas_val(e.get("snow1h"))
        if new1 != None and new1 > 0:
            g["snow"]["items"].append(("New 1h", "1h", bousai_amedas_depth(new1, pu), su, ui["fg"]))
    if bousai_bool(config, "el_sun", True):
        sun = bousai_amedas_val(e.get("sun1h"))
        if sun != None:
            g["info"]["items"].append(("Sun", "Sun", "%d" % int(sun * 60 + 0.5), "m/h", am_hi(ui)))
    g["info"]["items"].append(("Dist", "Dist", dist_km, "", ui["muted"]))
    g["info"]["items"].append(("Bearing", "Brg", bearing, "", ui["muted"]))
    return g

def am_group_pages(ui, title, items, inline_unit):
    """Header (title carries the unit) + one full-width row per item; spills onto more pages if needed."""
    header = bousai_amedas_header(ui, am_pick(ui, canvas.width() - 3, [title, title.split(" ")[0], "Station"]))
    cap = max(1, (canvas.height() - ui["line_h"]) // ui["line_h"])
    pages = []
    for i in range(0, len(items), cap):
        kids = [header]
        for it in items[i:i + cap]:
            unit = it[3] if inline_unit else ""
            text = am_pick(ui, canvas.width() - 3, ["%s %s%s" % (it[0], it[2], unit), "%s %s%s" % (it[1], it[2], unit)])
            kids.append(render.Box(width = canvas.width(), height = ui["line_h"], child = render.Padding(pad = (1, 0, 0, 0), child = bousai_fit(ui, text, color = it[4]))))
        pages.append(render.Column(children = kids))
    return pages

def am_trend_page(ui, title, unit_label, values, color, lo, hi, top, bottom):
    """Header + gutter labels + chart filling the rest of the screen."""
    body_h = canvas.height() - ui["line_h"]
    gutter = max(bousai_text_width(ui, top), bousai_text_width(ui, bottom)) + 2
    label_col = render.Box(width = gutter, height = body_h, child = render.Column(main_align = "space_between", expanded = True, children = [
        bousai_text(ui, top, ui["muted"]),
        bousai_text(ui, bottom, ui["muted"]),
    ]))
    plot = bousai_amedas_spark(ui, values, canvas.width() - gutter - 1, body_h - 1, color, True, lo, hi)
    chart = render.Box(width = canvas.width() - gutter, height = body_h, child = plot if plot else bousai_fit(ui, "No data", color = ui["muted"]))
    return render.Column(children = [
        bousai_amedas_header(ui, am_pick(ui, canvas.width() - 4 - bousai_text_width(ui, unit_label), [title, title.split(" /")[0]]), right = unit_label),
        render.Row(children = [label_col, chart]),
    ])

def am_trend_pages(ui, config, series, hours, units):
    mode = config.get("trend") or "temp"
    pages = []
    body_h = canvas.height() - ui["line_h"]
    if mode in ("temp", "both"):
        vals = bousai_amedas_values(series, "temp")
        conv = [v * 9.0 / 5.0 + 32 if (v != None and units["temp"] == "F") else v for v in vals]
        have = [v for v in conv if v != None]
        if len(have) >= 2:
            pages.append(am_trend_page(ui, "Temp %dh" % hours, units["temp"], conv, am_hi(ui), None, None, bousai_fixed(max(have), 1), bousai_fixed(min(have), 1)))
    if mode in ("rain", "both"):
        vals = bousai_amedas_values(series, "precipitation10m")
        raw = [v for v in vals if v != None]
        conv = [v / 25.4 if (v != None and units["precip"] == "in") else v for v in vals]
        if len(raw) >= 2:
            if max(raw) <= 0:
                pages.append(render.Column(children = [
                    bousai_amedas_header(ui, "Rain %dh" % hours, right = units["precip"]),
                    render.Box(width = canvas.width(), height = body_h, child = bousai_text(ui, "No rain", ui["fg"])),
                ]))
            else:
                pages.append(am_trend_page(ui, "Rain %dh /10m" % hours, units["precip"], conv, am_lo(ui), 0.0, max([v for v in conv if v != None]), bousai_amedas_precip(max(raw), units["precip"]), "0"))
    return pages

def main(config):
    ui = bousai_ui(config)
    loc = bousai_location(config)
    station = (config.get("station") or "").strip()
    sid, st, dist = bousai_amedas_station(station, loc["lat"], loc["lon"])
    if sid == None:
        if station:
            return bousai_message(ui, "AMeDAS", ["No station matches '%s'." % station, "Use a station ID or English name."])
        return bousai_message(ui, "AMeDAS", ["No AMeDAS station within %d km." % BOUSAI_AMEDAS_MAX_KM, "Pick a location in Japan or enter a station."])
    hours = int(config.get("trend_hours") or "6")
    series = bousai_amedas_series(sid, hours)
    cur = bousai_amedas_current(series) if series else None
    if cur == None:
        return bousai_message(ui, "AMeDAS", ["Observations for %s are unavailable right now." % (st.get("enName") or sid)])

    units = {
        "temp": "F" if config.get("temp_unit") == "F" else "C",
        "wind": config.get("wind_unit") or "ms",
        "precip": "in" if config.get("precip_unit") == "in" else "mm",
    }
    slat, slon = bousai_amedas_coords(st)
    dist_km = "%dkm" % int(dist + 0.5)
    bearing = bousai_bearing_name(loc["lat"], loc["lon"], slat, slon)
    body_h = canvas.height() - ui["line_h"]
    wide = ui["size"] in ("large", "xlarge")
    left, left_w = am_left_panel(ui, series, bousai_amedas_val(cur["e"].get("temp")), units["temp"], body_h, 62 if wide else 30)
    header = bousai_amedas_header(ui, st.get("enName") or sid, right = bousai_hhmm(cur["time"], loc["tz"]))
    groups = am_groups(ui, config, cur, units, dist_km, bearing, sid)
    if wide:
        # Large text: temperature page, then every value as one full-width row with its unit.
        pages = [render.Column(children = [header, render.Box(width = canvas.width(), height = body_h, child = left)])]
        flat = []
        for g in ["overview", "rain", "wind", "snow", "info"]:
            for it in groups[g]["items"]:
                flat.append((am_pick(ui, canvas.width() - 3, [
                    "%s %s%s" % (it[0], it[2], it[3]),
                    "%s %s%s" % (it[1], it[2], it[3]),
                    "%s%s" % (it[2], it[3]),
                ]), it[4]))
        flat.append(("ID " + sid, ui["muted"]))
        pages.extend(am_row_pages(ui, flat))
    else:
        right_w = canvas.width() - left_w - 2
        rows = []
        for it in groups["overview"]["items"]:
            opts = ["%s %s%s" % (it[0], it[2], it[3]), "%s %s%s" % (it[1], it[2], it[3])]
            if it[3] in ("C", "F"):
                opts = [opts[0], "%s %s" % (it[0], it[2]), opts[1], "%s %s" % (it[1], it[2])]
            rows.append((am_pick(ui, right_w, opts), it[4]))
        pages = bousai_amedas_pager(ui, header, left, left_w, rows)
        for g in ["rain", "wind", "snow", "info"]:
            if groups[g]["items"]:
                pages.extend(am_group_pages(ui, groups[g]["title"], groups[g]["items"], g == "info"))
    pages.extend(am_trend_pages(ui, config, series, hours, units))

    return bousai_root(ui, bousai_amedas_rotate([(p, 1.0) for p in pages], "bousai_amedas_rot:%s:%s" % (sid, ui["size"])))

def get_schema():
    return bousai_schema([
        schema.Location(id = "location", name = "Location", desc = "Your location. The nearest AMeDAS station that measures temperature and wind is used.", icon = "locationDot"),
        schema.Text(id = "station", name = "Station (optional)", desc = "AMeDAS station ID (e.g. 44132) or English name (e.g. Sapporo). Overrides the nearest station.", icon = "towerBroadcast", default = ""),
        schema.Dropdown(id = "temp_unit", name = "Temperature unit", desc = "Celsius or Fahrenheit.", icon = "temperatureHalf", default = "C", options = [
            schema.Option(display = "Celsius (°C)", value = "C"),
            schema.Option(display = "Fahrenheit (°F)", value = "F"),
        ]),
        schema.Dropdown(id = "wind_unit", name = "Wind speed unit", desc = "Unit for wind speed and gusts.", icon = "wind", default = "ms", options = [
            schema.Option(display = "m/s", value = "ms"),
            schema.Option(display = "km/h", value = "kmh"),
            schema.Option(display = "knots", value = "kt"),
            schema.Option(display = "mph", value = "mph"),
        ]),
        schema.Dropdown(id = "precip_unit", name = "Rain and snow unit", desc = "Millimetres / centimetres or inches.", icon = "droplet", default = "mm", options = [
            schema.Option(display = "mm / cm", value = "mm"),
            schema.Option(display = "inches", value = "in"),
        ]),
        schema.Toggle(id = "el_humidity", name = "Humidity", desc = "Show relative humidity.", icon = "droplet", default = True),
        schema.Toggle(id = "el_precip", name = "Precipitation", desc = "Show rain for the last 10 minutes, 1 hour and 24 hours.", icon = "cloudRain", default = True),
        schema.Toggle(id = "el_wind", name = "Wind and gusts", desc = "Show wind direction, speed and gusts.", icon = "wind", default = True),
        schema.Toggle(id = "el_snow", name = "Snow", desc = "Show snow depth and snowfall when there is any.", icon = "snowflake", default = True),
        schema.Toggle(id = "el_sun", name = "Sunshine", desc = "Show sunshine minutes in the last hour.", icon = "sun", default = True),
        schema.Toggle(id = "el_extremes", name = "Today's high and low", desc = "Show the highest and lowest temperature so far today.", icon = "temperatureHalf", default = True),
        schema.Dropdown(id = "trend", name = "Trend chart", desc = "Chart of the recent observations.", icon = "chartLine", default = "temp", options = [
            schema.Option(display = "Temperature", value = "temp"),
            schema.Option(display = "Rain", value = "rain"),
            schema.Option(display = "Both", value = "both"),
            schema.Option(display = "None", value = "off"),
        ]),
        schema.Dropdown(id = "trend_hours", name = "Trend length", desc = "How many hours the trend chart covers.", icon = "clock", default = "6", options = [
            schema.Option(display = "3 hours", value = "3"),
            schema.Option(display = "6 hours", value = "6"),
            schema.Option(display = "12 hours", value = "12"),
        ]),
    ], location = False)
