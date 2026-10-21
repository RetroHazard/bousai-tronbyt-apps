"""
Applet: Bousai Forecast
Summary: JMA weather forecast
Description: Weather forecast for Japan from the Japan Meteorological Agency, with 3-hourly, 7-day, rain chance, sunrise/sunset and official English text.
Author: Bousai Apps
"""

# bousai: requires core data forecast

load("render.star", "canvas", "render")
load("schema.star", "schema")

FC_HOURLY_COLS = {"small": 6, "standard": 6, "large": 3, "xlarge": 3}
FC_TEXT_LINES = {"small": (15, 10), "standard": (12, 8), "large": (9, 6), "xlarge": (6, 4)}

def fc_hi(ui):
    """Colour for highs / sun / rise (mono palette falls back to full-contrast text)."""
    return ui["fg"] if ui["palette"] == "mono" else ui["sev"][2]

def fc_lo(ui):
    """Colour for lows / rain / set (mono palette falls back to full-contrast text)."""
    return ui["fg"] if ui["palette"] == "mono" else ui["sev"][1]

def fc_pick(ui, width, options):
    """First option that fits in width, else the last one clipped."""
    for o in options:
        if bousai_text_width(ui, o) <= width:
            return o
    return bousai_forecast_clip(ui, options[-1], width)

def fc_temp(c, unit):
    """'29C' / '84F' or '--'."""
    v = bousai_forecast_unit_temp(c, unit)
    if v == None:
        return "--"
    return "%d%s" % (v, unit)

def fc_row_pages(ui, header, rows):
    """Split rows over pages that fit under an optional header."""
    avail = canvas.height() - (ui["line_h"] if header != None else 0)
    cap = max(1, avail // ui["line_h"])
    pages = []
    for i in range(0, max(1, len(rows)), cap):
        kids = [] if header == None else [header]
        for r in rows[i:i + cap]:
            kids.append(render.Box(width = canvas.width(), height = ui["line_h"], child = bousai_row(ui, (bousai_forecast_clip(ui, r[0], canvas.width() - 1), r[1]) if type(r) == "tuple" else r)))
        pages.append(render.Column(children = kids))
    return pages

def fc_wrap(ui, text, width):
    """Greedy word wrap using the real text width."""
    lines = []
    cur = ""
    for word in text.split(" "):
        w = word
        for _ in range(len(word)):
            if bousai_text_width(ui, w) <= width:
                break
            # A single word wider than the line: break it at the last character that fits.
            cut = len(w) - 1
            for _ in range(len(w)):
                if bousai_text_width(ui, w[:cut]) <= width or cut <= 1:
                    break
                cut -= 1
            if cur:
                lines.append(cur)
                cur = ""
            lines.append(w[:cut])
            w = w[cut:]
        trial = (cur + " " + w) if cur else w
        if cur and bousai_text_width(ui, trial) > width:
            lines.append(cur)
            cur = w
        else:
            cur = trial
    if cur:
        lines.append(cur)
    return lines

def fc_temp_rows(ui, width, base, obs, diff, ref, color):
    """Rows for a high/low: 'Hi 29C obs +4' when it fits; whatever is dropped moves to its own row."""
    o = " obs" if obs else ""
    d = (" " + diff) if diff else ""
    text = base
    has_obs = False
    has_diff = False
    for cand, ho, hd in [(base + o + d, True, True), (base + d, False, True), (base + o, True, False)]:
        if bousai_text_width(ui, cand) <= width:
            text = cand
            has_obs = ho
            has_diff = hd
            break
    rows = [(bousai_forecast_clip(ui, text, width), color)]
    if obs and not has_obs:
        rows.append(("so far", ui["muted"]))
    if diff and not has_diff:
        text = None
        for cand in [diff + " vs " + ref, diff + " " + ref]:
            if text == None and bousai_text_width(ui, cand) <= width:
                text = cand
        if text != None:
            rows.append((text, ui["muted"]))
        else:
            rows.append((diff, ui["muted"]))
            if bousai_text_width(ui, "vs " + ref) <= width:
                rows.append(("vs " + ref, ui["muted"]))
            else:
                rows.extend([("vs", ui["muted"]), (ref, ui["muted"])])
    return rows

def fc_pair(ui, width, label, value, color):
    """'Rise 05:51' as one row when it fits, else label and value on two rows."""
    one = label + " " + value
    if bousai_text_width(ui, one) <= width:
        return [(one, color)]
    return [(label, ui["muted"]), (bousai_forecast_clip(ui, value, width), color)]

def fc_day_pages(ui, model, idx, unit):
    """Overview pages for today (idx 0) or tomorrow (idx 1)."""
    d = model["days"][idx]
    t0 = model["days"][0]
    y = model["yesterday"] or {}
    right_w = canvas.width() - 18
    title = d["label"]
    telop = d["weather_en"]
    telop_in_header = bool(telop) and bousai_text_width(ui, title + " " + telop) <= canvas.width() - 2
    if telop_in_header:
        title = title + " " + telop
    header = bousai_forecast_header(ui, title)
    rows = []
    hi_c = fc_hi(ui)
    lo_c = fc_lo(ui)
    hi_diff = None
    lo_diff = None
    if idx == 0 and not d["high_obs"] and d["high"] != None and y.get("high") != None:
        hi_diff = d["high"] - bousai_forecast_round(y["high"])
    if idx == 0 and not d["low_obs"] and d["low"] != None and y.get("low") != None:
        lo_diff = d["low"] - bousai_forecast_round(y["low"])
    if idx == 1 and d["high"] != None and t0["high"] != None:
        hi_diff = d["high"] - t0["high"]
    if idx == 1 and d["low"] != None and t0["low"] != None:
        lo_diff = d["low"] - t0["low"]
    ref = "yday" if idx == 0 else "today"
    if d["high"] != None:
        rows.extend(fc_temp_rows(ui, right_w, "Hi " + fc_temp(d["high"], unit), d["high_obs"], bousai_forecast_signed(bousai_forecast_unit_diff(hi_diff, unit)) if hi_diff != None else "", ref, hi_c))
    if d["low"] != None:
        rows.extend(fc_temp_rows(ui, right_w, "Lo " + fc_temp(d["low"], unit), d["low_obs"], bousai_forecast_signed(bousai_forecast_unit_diff(lo_diff, unit)) if lo_diff != None else "", ref, lo_c))
    if d["high"] == None and d["low"] == None:
        rows.append(("No temps yet", ui["muted"]))
    pop = bousai_forecast_pop_now(model) if idx == 0 else d["pop"]
    if pop != None:
        rows.extend(fc_pair(ui, right_w, "Rain", "%d%%" % pop, ui["fg"]))
    left = bousai_forecast_big(ui, d["key"]) if d["code"] else bousai_text(ui, "--", ui["muted"])
    pages = []
    if telop and not telop_in_header:
        if max([bousai_text_width(ui, w) for w in telop.split(" ")]) <= right_w:
            pages.extend(bousai_forecast_pager(ui, header, left, 17, [(l, ui["fg"]) for l in fc_wrap(ui, telop, right_w)]))
        else:
            pages.extend(fc_row_pages(ui, header, [(l, ui["fg"]) for l in fc_wrap(ui, telop, canvas.width() - 2)]))
    pages.extend(bousai_forecast_pager(ui, header, left, 17, rows))
    return pages

def fc_rain_pages(ui, model):
    """Chance of rain per six-hour block for today and tomorrow."""
    cells = {}
    for p in model["pops6"]:
        if p["time"] != None:
            cells.setdefault(p["time"].format("2006-01-02"), {})[p["time"].hour] = p["pop"]
    days = [("Tdy", model["days"][0]["date"]), ("Tmr", model["days"][1]["date"])]
    if not cells.get(days[0][1]) and not cells.get(days[1][1]):
        return []
    header = bousai_forecast_header(ui, "Rain %")
    cell_w = (canvas.width() - 14) // 4
    if bousai_text_width(ui, "100") <= cell_w and canvas.height() >= ui["line_h"] * 4:
        label_row = [render.Box(width = 14, height = ui["line_h"])]
        for h in [0, 6, 12, 18]:
            label_row.append(render.Box(width = cell_w, height = ui["line_h"], child = bousai_text(ui, bousai_forecast_pad2(h), ui["muted"])))
        kids = [header, render.Row(children = label_row)]
        for name, date in days:
            row = [render.Box(width = 14, height = ui["line_h"], child = bousai_text(ui, name, ui["fg"]))]
            for h in [0, 6, 12, 18]:
                p = cells.get(date, {}).get(h)
                color = bousai_mix(ui["muted"], fc_lo(ui), (p or 0) / 100.0) if p != None else ui["faint"]
                row.append(render.Box(width = cell_w, height = ui["line_h"], child = bousai_text(ui, "%d" % p if p != None else "-", color)))
            kids.append(render.Row(children = row))
        return [render.Column(children = kids)]
    rows = []
    now = bousai_now()
    for p in model["pops6"]:
        if p["time"] == None or p["pop"] == None or p["time"] + 6 * time.hour <= now:
            continue
        h0 = bousai_forecast_pad2(p["time"].hour)
        h1 = bousai_forecast_pad2((p["time"].hour + 6) % 24)
        text = fc_pick(ui, canvas.width() - 1, ["%s %s-%sh %d%%" % (p["time"].format("Mon"), h0, h1, p["pop"]), "%s-%sh %d%%" % (h0, h1, p["pop"]), "%sh %d%%" % (h0, p["pop"])])
        rows.append((text, bousai_mix(ui["muted"], fc_lo(ui), p["pop"] / 100.0)))
    return fc_row_pages(ui, header if ui["size"] != "xlarge" else None, rows[:4])

def fc_hourly_pages(ui, slots, unit, rise, sset):
    """3-hourly strip: hour, icon, temperature (+ wind) for the next 24 hours."""
    now = bousai_now()
    sel = [s for s in slots if s["time"] != None and s["time"] + 3 * time.hour > now][:(6 if ui["size"] in ("small", "standard") else 6)]
    if not sel:
        return []
    size = ui["size"]
    ncols = FC_HOURLY_COLS[size]
    col_w = canvas.width() // ncols
    wide = size in ("large", "xlarge")
    pages = []
    for i in range(0, len(sel), ncols):
        chunk = sel[i:i + ncols]
        cols = []
        speeds = [s["wind_ms"] for s in chunk if s["wind_ms"] != None]
        for s in chunk:
            t = s["time"]
            if t.hour == 0:
                label = t.format("Mon") if wide else t.format("Mon")[:2]
            else:
                label = ("%dh" % t.hour) if wide else bousai_forecast_pad2(t.hour)
            key = s["key"]
            if bousai_forecast_is_night(t + 90 * time.minute, rise, sset):
                key = {"sun": "moon", "partly": "pmoon"}.get(key, key)
            kids = [
                render.Box(width = col_w, height = ui["line_h"], child = bousai_text(ui, label, ui["muted"])),
                render.Box(width = col_w, height = 6, child = bousai_forecast_mini(ui, key)),
                render.Box(width = col_w, height = ui["line_h"], child = bousai_text(ui, "%d" % bousai_forecast_unit_temp(s["temp"], unit) if s["temp"] != None else "--", ui["fg"])),
            ]
            wind = "%s%d" % (s["wind_dir_en"] or "", s["wind_ms"]) if s["wind_ms"] != None else "--"
            if size == "large":
                kids.append(render.Box(width = col_w, height = 7, child = bousai_text(ui, wind, ui["muted"], ui["small_font"])))
            cols.append(fc_shade(ui, len(cols), col_w, ui["line_h"] * 2 + 6 + (7 if size == "large" else 0), render.Column(children = kids)))
        body = [render.Row(children = cols)]
        if size in ("small", "standard") and speeds:
            rng = "%d-%d" % (min(speeds), max(speeds)) if min(speeds) != max(speeds) else "%d" % speeds[0]
            d0 = chunk[0]["wind_dir_en"] or ""
            body.append(bousai_fit(ui, fc_pick(ui, canvas.width() - 1, ["Wind %s %sm/s" % (d0, rng), "%s %sm/s" % (d0, rng), "%s %s" % (d0, rng)]), color = ui["muted"]))
        pages.append(render.Column(children = body))
    return pages

def fc_week_pages(ui, model, unit):
    days = model["days"]
    size = ui["size"]
    if size in ("small", "standard"):
        # 7 columns of 9 px: two-digit numbers (7 px) always leave a 2 px gap; legend row names the colours.
        col_w = 9
        cols = []
        for d in days:
            cols.append(fc_shade(ui, len(cols), col_w, ui["line_h"] * 3 + 5, render.Column(children = [
                render.Box(width = col_w, height = ui["line_h"], child = bousai_text(ui, d["weekday"][:2], ui["fg"])),
                render.Box(width = col_w, height = 5, child = bousai_forecast_mini(ui, d["key"]) if d["code"] else bousai_text(ui, "-", ui["muted"])),
                render.Box(width = col_w, height = ui["line_h"], child = bousai_text(ui, "%d" % bousai_forecast_unit_temp(d["high"], unit) if d["high"] != None else "-", fc_hi(ui))),
                render.Box(width = col_w, height = ui["line_h"], child = bousai_text(ui, "%d" % bousai_forecast_unit_temp(d["low"], unit) if d["low"] != None else "-", fc_lo(ui))),
            ])))
        legend = render.Row(children = [
            bousai_text(ui, "High ", fc_hi(ui), ui["small_font"]),
            bousai_text(ui, "Low ", fc_lo(ui), ui["small_font"]),
            bousai_text(ui, unit, ui["muted"], ui["small_font"]),
        ])
        return [render.Column(children = [render.Row(children = cols), render.Padding(pad = (1, 0, 0, 0), child = legend)])]
    rows = []
    label_w = bousai_text_width(ui, "Wed") + 3
    for d in days:
        hi = "%d" % bousai_forecast_unit_temp(d["high"], unit) if d["high"] != None else "-"
        lo = "%d" % bousai_forecast_unit_temp(d["low"], unit) if d["low"] != None else "-"
        nums = bousai_text_width(ui, hi + "/" + lo)
        day = d["weekday"] if label_w + 9 + nums <= canvas.width() - 2 else d["weekday"][:2]
        parts = [render.Box(width = bousai_text_width(ui, day) + 3, height = ui["line_h"], child = render.Row(main_align = "start", expanded = True, children = [bousai_text(ui, day, ui["fg"])]))]
        if bousai_text_width(ui, day) + 3 + 9 + nums <= canvas.width() - 2:
            parts.append(render.Box(width = 9, height = ui["line_h"], child = bousai_forecast_mini(ui, d["key"]) if d["code"] else bousai_text(ui, "-", ui["muted"])))
        parts.extend([
            bousai_text(ui, hi, fc_hi(ui)),
            bousai_text(ui, "/", ui["muted"]),
            bousai_text(ui, lo, fc_lo(ui)),
        ])
        rows.append(render.Row(cross_align = "center", children = parts))
    return fc_row_pages(ui, None, rows)

def fc_sun_pages(ui, rise, sset):
    header = bousai_forecast_header(ui, fc_pick(ui, canvas.width() - 2, ["Sunrise/set", "Sun"]))
    rows = []
    right_w = canvas.width() - 18
    if rise and sset:
        mins = int((sset - rise).minutes + 0.5)
        rows.extend(fc_pair(ui, right_w, "Rise", rise.format("15:04"), fc_hi(ui)))
        rows.extend(fc_pair(ui, right_w, "Set", sset.format("15:04"), fc_lo(ui)))
        rows.extend(fc_pair(ui, right_w, "Day", "%dh%sm" % (mins // 60, bousai_forecast_pad2(mins % 60)), ui["muted"]))
    else:
        rows.append(("No sunrise/set today", ui["muted"]))
    return bousai_forecast_pager(ui, header, bousai_forecast_big(ui, "sun"), 17, rows)

def fc_text_pages(ui, model, unit, rise, sset, summary, official):
    """Screen-reader style temperature sentences and the official JMA English forecast, as wrapped text pages.

    Whole sentences only (up to a per-size line budget). Returns (summary pages, official pages)."""
    caps = FC_TEXT_LINES[ui["size"]]
    out = []
    for use, blocks, cap in [
        (summary, [s for s in bousai_forecast_sentences(model, unit, rise, sset) if " high of " in s or " low of " in s], caps[0]),
        (official, model["official"], caps[1]),
    ]:
        lines = []
        if use:
            for b in blocks:
                wrapped = fc_wrap(ui, b, canvas.width() - 1)
                if lines and len(lines) + len(wrapped) > cap:
                    break
                lines.extend(wrapped)
        out.append(fc_row_pages(ui, None, [(l, ui["fg"]) for l in lines]) if lines else [])
    return out[0], out[1]

def main(config):
    ui = bousai_ui(config)
    area = bousai_area(config)
    if area == None:
        return bousai_message(ui, "Forecast", ["Location is outside Japan or has no JMA area.", "Pick a Japanese location."])
    model = bousai_forecast_model(area)
    if model == None:
        return bousai_message(ui, "Forecast", ["JMA forecast data is unavailable right now."])
    unit = "F" if config.get("temp_unit") == "F" else "C"
    rise, sset = bousai_forecast_sun(area["lat"], area["lon"], 0)

    pages = []
    for on, widgets, weight in [
        (bousai_bool(config, "show_today", True), fc_day_pages(ui, model, 0, unit), 1.0),
        (bousai_bool(config, "show_tomorrow", True), fc_day_pages(ui, model, 1, unit), 1.0),
        (bousai_bool(config, "show_rain", False), fc_rain_pages(ui, model), 1.0),
        (bousai_bool(config, "show_hourly", True), fc_hourly_pages(ui, bousai_forecast_hourly(area["class10"]), unit, rise, sset), 1.0),
        (bousai_bool(config, "show_week", True), fc_week_pages(ui, model, unit), 1.0),
        (bousai_bool(config, "show_sun", True), fc_sun_pages(ui, rise, sset), 1.0),
    ]:
        if on:
            pages.extend([(w, weight) for w in widgets])
    summary_pages, official_pages = fc_text_pages(ui, model, unit, rise, sset, bousai_bool(config, "show_summary", False), bousai_bool(config, "show_text", False))
    pages.extend([(w, 1.2) for w in summary_pages + official_pages])
    if not pages:
        return bousai_message(ui, "Forecast", ["All pages are switched off.", "Enable a page in the app settings."])

    loc = bousai_location(config)
    return bousai_root(ui, bousai_forecast_rotate(pages, "bousai_forecast_rot:%s:%s" % (bousai_fixed(loc["lat"], 2), bousai_fixed(loc["lon"], 2))))

def get_schema():
    return bousai_schema([
        schema.Dropdown(id = "temp_unit", name = "Temperature unit", desc = "Show temperatures in Celsius or Fahrenheit.", icon = "temperatureHalf", default = "C", options = [
            schema.Option(display = "Celsius (°C)", value = "C"),
            schema.Option(display = "Fahrenheit (°F)", value = "F"),
        ]),
        schema.Toggle(id = "show_today", name = "Today", desc = "Weather, high/low and rain chance for today.", icon = "sun", default = True),
        schema.Toggle(id = "show_tomorrow", name = "Tomorrow", desc = "Weather, high/low and rain chance for tomorrow.", icon = "calendarDay", default = True),
        schema.Toggle(id = "show_rain", name = "Rain chance per 6 hours", desc = "Chance of rain in each six-hour block.", icon = "umbrella", default = False),
        schema.Toggle(id = "show_hourly", name = "3-hourly forecast", desc = "Weather and temperature every three hours for the next 18 hours.", icon = "clock", default = True),
        schema.Toggle(id = "show_week", name = "7-day forecast", desc = "Weather, high and low for the coming week.", icon = "calendarWeek", default = True),
        schema.Toggle(id = "show_sun", name = "Sunrise and sunset", desc = "Sunrise, sunset and day length.", icon = "cloudSun", default = True),
        schema.Toggle(id = "show_summary", name = "Spoken-style summary", desc = "Plain sentences such as Forecast high of 26 (3 degrees lower than yesterday).", icon = "message", default = False),
        schema.Toggle(id = "show_text", name = "Official English forecast", desc = "The JMA English forecast text for your area.", icon = "list", default = False),
    ])

def fc_shade(ui, i, w, h, child):
    """Alternate faint column backgrounds so adjacent narrow columns stay readable."""
    if i % 2 == 0:
        return child
    return render.Stack(children = [render.Box(width = w, height = h, color = bousai_mix(ui["bg"], ui["faint"], 0.7)), child])
