"""
Applet: Bousai Home
Summary: Prioritised alerts and weather
Description: One panel for your location that gathers earthquake early warnings, tsunami, weather warnings, volcano, quake, typhoon and shaking information from the Japan Meteorological Agency and sorts it by severity, urgency and age; calm weather when nothing is active.
Author: Bousai Apps
"""

# bousai: requires core data eew quake tsunami volcano typhoon warnings forecast amedas home

load("cache.star", "cache")
load("math.star", "math")
load("render.star", "canvas", "render")
load("schema.star", "schema")
load("time.star", "time")

# Every card page stays up at least this long (frames of 100 ms).
HOME_MIN_FRAMES = 25

# Night variants of the forecast sprites (the weather library only draws daytime icons).
HOME_NIGHT_KEY = {"sun": "moon", "partly": "pmoon", "sunrain": "rain", "sunsnow": "snow"}

# Lines of an item from this index on are secondary (muted); every line is primary when absent.
HOME_MUTED_FROM = {"tsunami": 2, "eruption": 2, "typhoon": 3, "shaking": 1}

# ---------------------------------------------------------------------------
# Layout metrics. Every page is: header (location and alert count), band (card title on its severity
# colour), then body rows. Large text leaves one body row per page, so cards page.

def home_metrics(ui):
    height = canvas.height()
    hh = bousai_font_height(ui, ui["small_font"])
    bh = ui["line_h"]
    top = hh + bh
    fh = bousai_font_height(ui)
    return {
        "hh": hh,
        "bh": bh,
        "rows": 1 + max(0, (height - top - fh) // ui["line_h"]),
        "body": height - top,
    }

def home_clip(ui, text, width, font = None):
    """Trim text (no ellipsis, never scrolls) until it fits width."""
    t = text
    for _ in range(len(text)):
        if bousai_text_width(ui, t, font) <= width:
            break
        t = t[:-1]
    return t

def home_pick(ui, options, width, font = None):
    """First option that fits width, else the last one trimmed."""
    for o in options:
        if bousai_text_width(ui, o, font) <= width:
            return o
    return home_clip(ui, options[-1], width, font)

def home_when(t, tz, now):
    """Clock time when t is today, month/day and clock within half a year, else the date with its year."""
    if t.in_location(tz).format("2006-01-02") == now.in_location(tz).format("2006-01-02"):
        return bousai_hhmm(t, tz)
    if (now - t).hours > 24 * 180:
        return t.in_location(tz).format("2006-01-02")
    return bousai_mdhm(t, tz)

def home_short_place(text):
    """Abbreviate long JMA place phrases before they would have to scroll."""
    for a, b in [(" Prefecture", " Pref."), ("Adjacent Sea of ", "Sea of "), ("Off the Coast of ", "Off "), ("Off the ", "Off ")]:
        text = text.replace(a, b)
    return text

# ---------------------------------------------------------------------------
# Header and band

def home_header(ui, label, active, top_sev, m):
    """Location on the left; on the right the number of active alerts on the colour of the strongest one."""
    width = canvas.width()
    font = ui["small_font"]
    label_w = bousai_text_width(ui, label, font)
    if active > 0:
        word = "%d alert%s" % (active, "" if active == 1 else "s")
        text = word if label_w + bousai_text_width(ui, word, font) + 7 <= width else "!%d" % active
        color = bousai_sev_color(ui, top_sev)
        right_w = bousai_text_width(ui, text, font) + 3
        right = render.Box(width = right_w, height = m["hh"], color = color, child = bousai_text(ui, text, bousai_on(color), font))
    else:
        right_w = bousai_text_width(ui, "Calm", font) + 3
        right = bousai_text(ui, "Calm", ui["muted"], font)
    kids = [
        render.Box(width = width, height = 1),
        render.Padding(pad = (1, 0, 0, 0), child = bousai_text(ui, home_clip(ui, label, width - right_w - 3, font), ui["fg"], font)),
        render.Padding(pad = (width - right_w, 0, 0, 0), child = right),
    ]
    return render.Box(width = width, height = m["hh"], color = ui["panel"], child = render.Stack(children = kids))

def home_band(ui, card, m):
    """Card title on its severity colour with the age on the right. Emergencies blink."""
    width = canvas.width()
    color = card["color"]
    ink = bousai_on(color)
    title = home_pick(ui, card["bands"], width - 2)
    right = card["right"] or ""
    right_w = bousai_text_width(ui, right) + 2 if right else 0
    kids = [render.Box(width = width, height = 1), render.Padding(pad = (1, 0, 0, 0), child = bousai_text(ui, title, ink))]
    if right and bousai_text_width(ui, title) + right_w + 3 <= width:
        kids.append(render.Padding(pad = (width - right_w + 1, 0, 0, 0), child = bousai_text(ui, right, ink)))
    band = render.Box(width = width, height = m["bh"], color = color, child = render.Stack(children = kids))
    if card["sev"] >= 5:
        band = bousai_blink(ui, band, width, m["bh"])
    return band

# ---------------------------------------------------------------------------
# Rows. A row spec is a dict; home_row turns it into a widget one line high and one screen wide.
#   text  {k, t, c}                  one line, scrolls (within the page's frames) when too wide
#   pair  {k, l, r, lc, rc}          label on the left, value on the right
#   segs  {k, segs}                  [("t", text, color) | ("c", chip label, chip color)]; the last text may scroll
#   eew   {k, ev}                    estimated intensity with a once-a-second S-wave countdown

def home_text(text, color):
    return {"k": "text", "t": text, "c": color}

def home_pair(ui, label, value, color):
    return {"k": "pair", "l": label, "r": value, "lc": ui["muted"], "rc": color}

def home_segs_row(ui, segs, frames):
    """A row of chips and text. Chips are font-high boxes; only the last text may scroll."""
    room = canvas.width() - 1
    fh = bousai_font_height(ui)
    kids = []
    used = 0
    for i, s in enumerate(segs):
        if s[0] == "c":
            w = bousai_text_width(ui, s[1]) + 3
            kids.append(render.Box(width = w, height = fh, color = s[2], child = bousai_text(ui, s[1], bousai_on(s[2]))))
            used += w
        elif i == len(segs) - 1:
            kids.append(bousai_fit(ui, s[1], width = max(1, room - used), color = s[2], frames = frames))
        else:
            kids.append(bousai_text(ui, s[1], s[2]))
            used += bousai_text_width(ui, s[1])
    return render.Row(children = kids)

def home_segs_width(ui, segs):
    w = 0
    for s in segs:
        w += bousai_text_width(ui, s[1]) + (3 if s[0] == "c" else 0)
    return w

def home_eew_segs(ui, ev, remain, variant):
    """Segments of the estimate row for `remain` seconds to the S-wave."""
    if remain > 0:
        tail = " in %ds" % int(math.ceil(remain))
    elif remain > -10:
        tail = " now"
    else:
        tail = " passed"
    chip = ("c", ev["local_int"], bousai_intensity_color(ui, ev["local_int"]))
    if variant == 0:
        return [("t", "Est ", ui["muted"]), chip, ("t", tail, ui["fg"])]
    return [chip, ("t", tail, ui["fg"])]

def home_eew_row(ui, spec, frames, t0):
    """The estimate row: one widget per second of the page, counting down to the S-wave from the moment
    the page is built (t0 = the frame at which this page starts, so later pages stay in step)."""
    ev = spec["ev"]
    r0 = (ev["s_arrival"] - time.now()).seconds
    widest = home_eew_segs(ui, ev, max(r0, 99.0), 0)
    variant = 0 if home_segs_width(ui, widest) <= canvas.width() - 1 else 1
    seconds = frames // 10 + 1
    per_second = [home_segs_row(ui, home_eew_segs(ui, ev, r0 - t0 / 10.0 - s, variant), frames) for s in range(seconds)]
    return render.Animation(children = [per_second[min(f // 10, seconds - 1)] for f in range(frames)])

def home_row(ui, spec, frames, t0):
    width = canvas.width()
    kind = spec["k"]
    if kind == "pair":
        lw = bousai_text_width(ui, spec["l"])
        rw = bousai_text_width(ui, spec["r"])
        if lw + rw + 3 <= width - 1:
            child = render.Stack(children = [
                bousai_text(ui, spec["l"], spec["lc"]),
                render.Padding(pad = (width - 1 - rw, 0, 0, 0), child = bousai_text(ui, spec["r"], spec["rc"])),
            ])
        else:
            child = bousai_fit(ui, spec["l"] + " " + spec["r"], width = width - 1, color = spec["rc"], frames = frames)
    elif kind == "segs":
        child = home_segs_row(ui, spec["segs"], frames)
    elif kind == "eew":
        child = home_eew_row(ui, spec, frames, t0)
    else:
        child = bousai_fit(ui, spec["t"], width = width - 1, color = spec["c"], frames = frames)
    return render.Box(width = width, height = ui["line_h"], child = render.Row(expanded = True, children = [render.Padding(pad = (1, 0, 0, 0), child = child)]))

# ---------------------------------------------------------------------------
# Cards. A card is {sev, color, bands, right, hero, rows, max_pages}; `hero` (or None) builds the body of
# the first page from the page's frame count, `rows` fill the pages (or the pages after the hero).

def home_card(ui, sev, bands, right, rows, max_pages = 2):
    return {"sev": sev, "color": bousai_sev_color(ui, sev), "bands": bands, "right": right, "hero": None, "rows": rows, "max_pages": max_pages}

def home_line_color(ui, item, i):
    kind = item["kind"]
    if kind == "warnings":
        muted = i == len(item["lines"]) - 1
    else:
        muted = i >= HOME_MUTED_FROM.get(kind, 99)
    return ui["muted"] if muted else ui["fg"]

def home_eew_rows(ui, item):
    ev = item["data"]
    rows = [home_text(home_short_place(item["lines"][0]), ui["fg"])]
    if ev["local_int"] != None and not ev["cancel"]:
        if ev["s_arrival"] != None:
            rows.append({"k": "eew", "ev": ev})
        else:
            rows.append({"k": "segs", "segs": [("t", "Est ", ui["muted"]), ("c", ev["local_int"], bousai_intensity_color(ui, ev["local_int"]))]})
    extra = []
    for line in item["lines"][1:]:
        if line.startswith("Max"):
            rows.append(home_text(line, ui["fg"]))
        elif not line.startswith("Est."):
            extra.append(home_text(line, ui["muted"]))
    return rows, extra

def home_quake_rows(ui, item, state):
    q = item["data"]
    rows = [home_text(home_short_place(item["lines"][0]), ui["fg"]), home_text(item["lines"][1], ui["fg"])]
    if q["local_int"]:
        rows.append({"k": "segs", "segs": [("t", "Your area ", ui["muted"]), ("c", "Int " + q["local_int"], bousai_intensity_color(ui, q["local_int"]))]})
    extra = [home_text("%s  %s ago" % (home_when(q["time"], state["loc"]["tz"], state["now"]), bousai_ago(q["time"], state["now"])), ui["muted"])]
    if q["tsunami_en"]:
        extra.append(home_text(q["tsunami_en"], ui["muted"]))
    return rows, extra

def home_item_rows(ui, item, state, per_page):
    """Rows of an item's card: the essentials, then the optional lines (time of issue...) only while the
    last page has room, so a card does not grow a page for them."""
    kind = item["kind"]
    if kind == "eew":
        rows, extra = home_eew_rows(ui, item)
    elif kind == "quake":
        rows, extra = home_quake_rows(ui, item, state)
    else:
        rows = [home_text(home_short_place(line), home_line_color(ui, item, i)) for i, line in enumerate(item["lines"])]
        extra = []
        if item["when"] != None:
            label = "Issued" if kind in ("tsunami", "warnings", "notice", "special", "volcano") else "At"
            extra.append(home_text("%s %s" % (label, home_when(item["when"], state["loc"]["tz"], state["now"])), ui["muted"]))
    for e in extra:
        if len(rows) % per_page == 0:
            break
        rows.append(e)
    return rows

def home_item_card(ui, item, state, per_page):
    sev = item["sev"]
    right = bousai_ago(item["when"], state["now"]) if item["when"] != None else None
    return home_card(ui, sev, item["bands"], right, home_item_rows(ui, item, state, per_page), 3 if sev >= 4 else 2)

# ---- calm cards ------------------------------------------------------------

def home_icon(ui, key, night, mini):
    """Weather sprite for a forecast key; at night the sun becomes a moon."""
    if night:
        key = HOME_NIGHT_KEY.get(key, key)
    if mini:
        return bousai_forecast_mini(ui, key)
    if key in ("moon", "pmoon"):
        g = bousai_forecast_blank(16, 12)
        if key == "moon":
            bousai_forecast_disc(g, 6, 6, 30, "M")
            bousai_forecast_disc(g, 9, 5, 22, ".")
        else:
            bousai_forecast_disc(g, 5, 5, 22, "M")
            bousai_forecast_disc(g, 8, 4, 14, ".")
            bousai_forecast_cloud_layer(g, 3, 5, "C")
        return bousai_forecast_render_grid(ui, ["".join(r) for r in g])
    return bousai_forecast_big(ui, key)

def home_weather_facts(calm, tz, per_page):
    """Weather lines in priority order: [(short text, label, value)]. One-line pages (large text) get
    sunrise and sunset as one fact and skip the station readings."""
    am = calm["amedas"]
    fc = calm["forecast"]
    facts = []
    if fc != None:
        hi = fc["high"]
        lo = fc["low"]
        if hi != None and lo != None:
            facts.append(("H%d L%d" % (hi, lo), "High/Low", "%d/%dC" % (hi, lo)))
        elif hi != None:
            facts.append(("High %dC" % hi, "High", "%dC" % hi))
        elif lo != None:
            facts.append(("Low %dC" % lo, "Low", "%dC" % lo))
        if fc["pop_now"] != None:
            facts.append(("Rain %d%%" % fc["pop_now"], "Rain", "%d%%" % fc["pop_now"]))
        rise = fc["sunrise"]
        sset = fc["sunset"]
        if rise != None and sset != None:
            if per_page == 1:
                span = "%s-%s" % (bousai_hhmm(rise, tz), bousai_hhmm(sset, tz))
                facts.append(("Sun " + span, "Sun", span))
            else:
                facts.append(("Rise " + bousai_hhmm(rise, tz), "Sunrise", bousai_hhmm(rise, tz)))
                facts.append(("Set " + bousai_hhmm(sset, tz), "Sunset", bousai_hhmm(sset, tz)))
    if am != None and per_page > 1:
        if am["humidity"] != None:
            pct = "%d%%" % int(am["humidity"] + 0.5)
            facts.append(("Humid " + pct, "Humidity", pct))
        if am["precip_1h"] != None:
            mm = bousai_fixed(am["precip_1h"], 1) + "mm"
            facts.append(("Rain " + mm + "/h", "Precip 1h", mm))
        if am["wind_ms"] != None:
            wind = bousai_fixed(am["wind_ms"], 1) + "m/s"
            if am["wind_dir_en"] and am["wind_dir_en"] != "Calm":
                wind += " " + am["wind_dir_en"]
            facts.append(("Wind " + wind, "Wind", wind))
    return facts

def home_hero_layout(ui, m):
    """Weather hero geometry: sprite (16x12, or 7x5 at the largest text), big temperature, extra lines
    beside it, and whether a line fits under the sprite (the chance of rain)."""
    mini = ui["size"] == "xlarge"
    font = ui["font"] if mini else ui["big_font"]
    tf = bousai_font_height(ui, font)
    fh = bousai_font_height(ui)
    space = m["body"] - tf - 1
    icon_h = 5 if mini else 12
    icon_top = max(0, (tf - icon_h) // 2)
    return {
        "mini": mini,
        "font": font,
        "tf": tf,
        "n_extra": 1 + (space - fh) // ui["line_h"] if space >= fh else 0,
        "left": 10 if mini else 19,
        "icon_top": icon_top,
        "under": (not mini) and m["body"] - icon_top - icon_h - 1 >= fh,
    }

def home_weather_hero(ui, lay, temp_text, key, night, extras, under, frames):
    """Body of the weather card's first page: sprite (with `under` text beneath it), big temperature, then the extra lines."""
    right = [bousai_text(ui, temp_text, ui["fg"], lay["font"])]
    for e in extras:
        right.append(render.Padding(pad = (0, 1 if len(right) == 1 else 0, 0, 0), child = bousai_fit(ui, e, width = canvas.width() - lay["left"] - 1, color = ui["fg"], frames = frames)))
    left = []
    if key:
        left.append(render.Padding(pad = (1, lay["icon_top"], 2, 0), child = home_icon(ui, key, night, lay["mini"])))
        if under:
            left.append(render.Padding(pad = (1, 1, 0, 0), child = bousai_text(ui, under, ui["sev"][1])))
    else:
        left.append(render.Box(width = 3, height = 1))
    return render.Row(children = [render.Column(children = left), render.Column(children = right)])

def home_weather_card(ui, state, calm, m, max_pages):
    """Weather: sprite, temperature now (AMeDAS) and the forecast facts. None without any data."""
    am = calm["amedas"]
    fc = calm["forecast"]
    if am == None and fc == None:
        return None
    tz = state["loc"]["tz"]
    facts = home_weather_facts(calm, tz, m["rows"])
    key = None
    night = False
    telop = ""
    if fc != None and fc["code"]:
        telop, _, key = bousai_forecast_weather(fc["code"])
        night = bousai_forecast_is_night(state["now"].in_location(tz), fc["sunrise"], fc["sunset"])
    temp_text = (bousai_fixed(am["temp"], 1) + "C") if am != None and am["temp"] != None else "--"
    lay = home_hero_layout(ui, m)
    extras = [f[0] for f in facts[:lay["n_extra"]]]
    rest = facts[lay["n_extra"]:]
    rows = [home_text(f[0], ui["fg"]) for f in rest] if m["rows"] == 1 else [home_pair(ui, f[1], f[2], ui["fg"]) for f in rest]
    under = None
    if fc != None and fc["pop_now"] != None and lay["under"] and len([e for e in extras if e.startswith("Rain")]) == 0:
        under = "%d%%" % fc["pop_now"]
    card = home_card(ui, 0, [x for x in [telop, "Weather"] if x], bousai_hhmm(am["time"], tz) if am != None else None, rows, max_pages)
    card["hero"] = lambda frames: home_weather_hero(ui, lay, temp_text, key, night, extras, under, frames)
    return card

def home_quake_card(ui, state, calm, per_page):
    """The newest felt quake, for when nothing urgent fills the panel."""
    q = calm["quake"]
    if q == None:
        return None
    label = q["local_int"] or q["max_int"]
    chip = ("c", "Int " + label if label else "Int ?", bousai_intensity_color(ui, label))
    mag = bousai_home_quake_facts(q)
    place = home_short_place(q["epicenter_en"])
    if per_page == 1:
        rows = [{"k": "segs", "segs": [chip, ("t", " %s %s" % (mag, place), ui["fg"])]}]
    else:
        rows = [
            {"k": "segs", "segs": [("t", "Your area " if q["local_int"] else "Max ", ui["muted"]), chip]},
            home_text(mag, ui["fg"]),
            home_text(place, ui["fg"]),
        ]
    return home_card(ui, 0, ["Last felt quake", "Last quake", "Quake"], bousai_ago(q["time"], state["now"]), rows, 1)

def home_status_card(ui, state, opts):
    """'No warnings' (or a no-data notice) with the time of the check and what was clear."""
    if len([s for s in ["eew", "shaking", "tsunami", "warnings", "volcano", "quake", "special", "typhoon"] if opts[s]]) == 0:
        return home_message_card(ui, "No sources on", ["Every source is", "switched off.", "Turn some on."])
    stamp = bousai_hhmm(state["now"], state["loc"]["tz"])
    checked = home_pick(ui, ["Checked " + stamp, "As of " + stamp, "At " + stamp], canvas.width() - 2)
    if opts["warnings"] and state["ok"]["warnings"] == False:
        return home_card(ui, 1, ["No warning data", "No data"], None, [home_text("JMA warning feed", ui["fg"]), home_text("unavailable", ui["fg"]), home_text(checked, ui["muted"])], 1)
    clear = []
    for s, name in [("eew", "EEW"), ("tsunami", "Tsunami"), ("volcano", "Volcano"), ("typhoon", "Typhoon")]:
        if opts[s] and not (s == "tsunami" and state["ok"]["tsunami"] == False):
            clear.append(name)
    rows = [home_text(checked, ui["muted"])]
    if clear:
        rows.append(home_text("Clear: " + ", ".join(clear), ui["fg"]))
    return home_card(ui, 0, ["No warnings", "Calm"] if opts["warnings"] else ["All clear", "Calm"], None, rows, 1)

def home_message_card(ui, title, lines):
    return home_card(ui, 1, [title], None, [home_text(l, ui["fg"]) for l in lines], 2)

def home_alert_cards(ui, state, opts, m):
    """Cards of the items in priority order (only severity 2 and up in alert-only mode)."""
    items = state["items"]
    if opts["alert_only"]:
        items = [it for it in items if it["sev"] >= 2]
    return [home_item_card(ui, it, state, m["rows"]) for it in items]

def home_calm_cards(ui, state, opts, m, calm):
    """Calm cards: weather, the last felt quake and, when nothing is at severity 2 or more, 'No warnings'.
    With alerts the weather shows only its first page."""
    steady = state["top_sev"] < 2
    if state["area"] == None:
        return [home_message_card(ui, "Outside Japan", ["No JMA area for", "this location.", "Set a new one."])] if steady else []
    cards = []
    weather = home_weather_card(ui, state, calm, m, (4 if m["rows"] == 1 else 3) if steady else 1)
    if weather != None:
        cards.append(weather)
    shown = [it["data"]["event_id"] for it in state["items"] if it["kind"] == "quake"]
    quake = home_quake_card(ui, state, calm, m["rows"])
    if quake != None and calm["quake"]["event_id"] not in shown:
        cards.append(quake)
    if steady:
        cards.append(home_status_card(ui, state, opts))
    return cards

# ---------------------------------------------------------------------------
# Pages and planning

def home_page_count(card, per_page):
    pages = (len(card["rows"]) + per_page - 1) // per_page + (1 if card["hero"] != None else 0)
    return max(1, min(pages, card["max_pages"]))

def home_choose(cards, per_page, capacity, key):
    """[(card, pages shown)] of the alert cards in priority order.

    When everything fits the dwell time every card is shown. Otherwise the top card, and the
    urgent cards (severity 4+) that follow it while at least two pages stay free, are pinned; the
    other cards rotate: a window of consecutive ones is shown, starting where the previous render
    stopped (a counter kept in the cache), so every card appears across renders.
    """
    counts = [home_page_count(c, per_page) for c in cards]
    total = 0
    for n in counts:
        total += n
    if total <= capacity:
        return [(cards[i], counts[i]) for i in range(len(cards))]
    pinned = [(0, min(counts[0], capacity))]
    used = pinned[0][1]
    for i in range(1, len(cards)):
        if cards[i]["sev"] >= 4 and used + counts[i] <= capacity - 2:
            pinned.append((i, counts[i]))
            used += counts[i]
        else:
            break
    taken = [p[0] for p in pinned]
    rest = [i for i in range(len(cards)) if i not in taken]
    chosen = []
    if rest and used < capacity:
        start = int(cache.get(key) or "0") % len(rest)
        for k in range(len(rest)):
            if used >= capacity:
                break
            j = rest[(start + k) % len(rest)]
            take = min(counts[j], capacity - used)
            chosen.append((j, take))
            used += take
        cache.set(key, str(start + len(chosen)), ttl_seconds = 86400)
    return [(cards[i], n) for i, n in sorted(pinned + chosen)]

def home_plan(ui, config, opts, state, m):
    """[(card, pages shown)]: the chosen alert cards, then calm cards while dwell time is left. The calm
    feeds (weather) are only read when there is room for their cards."""
    per_page = m["rows"]
    loc = state["loc"]
    key = "bousai_home_rot:%s:%s" % (bousai_fixed(loc["lat"], 2), bousai_fixed(loc["lon"], 2))
    capacity = max(1, bousai_budget_frames() // HOME_MIN_FRAMES)
    picks = home_choose(home_alert_cards(ui, state, opts, m), per_page, capacity, key)
    used = 0
    for _, n in picks:
        used += n
    if used >= capacity or opts["alert_only"] or state["demo"]:
        return picks
    for c in home_calm_cards(ui, state, opts, m, bousai_home_calm(config, opts, state)):
        n = min(home_page_count(c, per_page), capacity - used)
        if n <= 0:
            break
        picks.append((c, n))
        used += n
    return picks

def home_frames(picks):
    """Frames per page of each pick: every page at least HOME_MIN_FRAMES, the spare dwell time shared by
    weight (alerts count double) and never more than three times the minimum."""
    pages = 0
    weight = 0
    for card, n in picks:
        pages += n
        weight += n * (2 if card["sev"] >= 2 else 1)
    spare = max(0, bousai_budget_frames() - pages * HOME_MIN_FRAMES)
    return [min(3 * HOME_MIN_FRAMES, HOME_MIN_FRAMES + spare * (2 if card["sev"] >= 2 else 1) // max(1, weight)) for card, _ in picks]

def home_page(ui, header, card, page, per_page, frames, t0, m):
    """One held page: header, band and the hero or the rows of page `page` of the card."""
    width = canvas.width()
    height = canvas.height()
    kids = [header, home_band(ui, card, m)]
    first = 1 if card["hero"] != None else 0
    if first and page == 0:
        kids.append(card["hero"](frames))
    else:
        start = (page - first) * per_page
        for spec in card["rows"][start:start + per_page]:
            kids.append(home_row(ui, spec, frames, t0))
    body = render.Box(width = width, height = height, child = render.Column(expanded = True, main_align = "start", cross_align = "start", children = kids))
    if ui["frame"]:
        body = render.Stack(children = [
            body,
            render.Padding(pad = (0, height - 1, 0, 0), child = render.Box(width = width, height = 1, color = card["color"])),
            render.Padding(pad = (width - 1, 0, 0, 0), child = render.Box(width = 1, height = height, color = card["color"])),
        ])
    return bousai_hold(body, frames)

def home_render(ui, state, picks, m):
    loc = state["loc"]
    label = loc["label"] or (state["area"] or {}).get("class20_en") or "Home"
    header = home_header(ui, label, state["active"], state["top_sev"], m)
    pages = []
    t0 = 0
    for (card, count), frames in zip(picks, home_frames(picks)):
        for page in range(count):
            pages.append(home_page(ui, header, card, page, m["rows"], frames, t0, m))
            t0 += frames
    return pages[0] if len(pages) == 1 else render.Sequence(children = pages)

def main(config):
    ui = bousai_ui(config)
    opts = bousai_home_options(config)
    state = bousai_home_gather(config, opts)
    if opts["alert_only"] and state["top_sev"] < opts["alert_level"]:
        return []
    m = home_metrics(ui)
    picks = home_plan(ui, config, opts, state, m)
    if not picks:
        return bousai_message(ui, "Home", ["Nothing to show.", "Enable a source in", "the app settings."])
    return bousai_root(ui, home_render(ui, state, picks, m))

# ---------------------------------------------------------------------------
# Schema

def home_source(sid, name, desc, icon, default = True):
    return schema.Toggle(id = "src_" + sid, name = name, desc = desc, icon = icon, default = default)

def home_km_options(values):
    return [schema.Option(display = "%d km" % v, value = str(v)) for v in values]

def get_schema():
    return bousai_schema([
        home_source("eew", "Earthquake early warning", "Show active JMA EEW warnings and forecasts with the estimated intensity and S-wave countdown for your location.", "towerBroadcast"),
        home_source("shaking", "Shaking detection", "Show P2PQuake shaking detection, an unofficial evaluation of user reports and EEW detection. P2PQuake is a volunteer service that sometimes stalls, which fails that render; the app then skips it for a few minutes. Switch it off if your display shows render errors.", "signal"),
        home_source("tsunami", "Tsunami", "Show tsunami warnings, advisories and forecasts.", "water"),
        home_source("warnings", "Weather warnings and notices", "Show JMA warnings and advisories (Lv2 to Lv5) for your municipality plus landslide, river flood, tornado watch and record heavy rain notices.", "triangleExclamation"),
        home_source("volcano", "Volcano", "Show volcanic alert levels (Lv2 and up) and eruption flash reports within the volcano radius.", "volcano"),
        home_source("quake", "Recent earthquakes", "Show earthquakes felt in the recent-quake window, and the last felt quake when calm.", "waveSquare"),
        home_source("special", "Special earthquake information", "Show the Nankai Trough earthquake extra information and the Hokkaido / Sanriku subsequent-earthquake advisory.", "circleExclamation"),
        home_source("typhoon", "Typhoons", "Show typhoons whose centre is within the typhoon radius.", "hurricane"),
        home_source("amedas", "Current conditions", "Show the temperature measured by the nearest AMeDAS station on the weather card. Weather cards only fill the dwell time the alerts leave.", "temperatureHalf"),
        home_source("forecast", "Today's forecast", "Show today's weather, high and low, chance of rain and sunrise / sunset on the weather card. Weather cards only fill the dwell time the alerts leave.", "cloudSun"),
        schema.Dropdown(id = "quake_hours", name = "Recent quake window", desc = "How long an earthquake stays in the panel as an alert: felt at Int 3 or more at your location, or Int 5- or more anywhere in Japan. Weaker ones only appear as the last felt quake.", icon = "clockRotateLeft", default = "1", options = [
            schema.Option(display = "1 hour", value = "1"),
            schema.Option(display = "3 hours", value = "3"),
            schema.Option(display = "6 hours", value = "6"),
            schema.Option(display = "12 hours", value = "12"),
            schema.Option(display = "24 hours", value = "24"),
        ]),
        schema.Dropdown(id = "volcano_km", name = "Volcano radius", desc = "Volcanoes and eruption reports farther away than this are ignored.", icon = "mountain", default = "100", options = home_km_options([30, 50, 100, 200, 500])),
        schema.Dropdown(id = "typhoon_km", name = "Typhoon radius", desc = "Typhoons whose centre is farther away than this are ignored.", icon = "ruler", default = "500", options = home_km_options([300, 500, 1000, 2000])),
        schema.Toggle(id = "alert_only", name = "Only show alerts", desc = "Show nothing (the app is skipped) unless an item reaches the alert level below. Turn on Tronbyt AutoPin so an alert takes over the display; the weather feeds are not read in this mode. A long-standing alert, such as a volcano held at Lv3 for years, keeps the panel up: raise the level or switch that source off.", icon = "bell", default = False),
        schema.Dropdown(id = "alert_level", name = "Alert level", desc = "Lowest severity that counts as an alert when Only show alerts is on. Advisory: Lv2, EEW forecast of Int 3+, tsunami advisory. Warning: Lv3, tornado watch, tsunami warning, typhoon in range. Urgent: Lv4, record heavy rain, fresh eruption. Emergency: Lv5, EEW warning, major tsunami warning.", icon = "gaugeHigh", default = "3", options = [
            schema.Option(display = "Advisory (Lv2)", value = "2"),
            schema.Option(display = "Warning (Lv3)", value = "3"),
            schema.Option(display = "Urgent warning (Lv4)", value = "4"),
            schema.Option(display = "Emergency warning (Lv5)", value = "5"),
        ]),
        schema.Toggle(id = "demo", name = "Show sample alert", desc = "Show an embedded sample: an early warning (2024-01-01 Noto Peninsula report), a tsunami advisory and a Lv4 heavy rain and landslide warning, ordered by priority.", icon = "flask", default = False),
    ])
