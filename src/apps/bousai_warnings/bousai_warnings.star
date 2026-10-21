"""
Applet: Bousai Warnings
Summary: JMA weather warnings
Description: Japan weather advisories, warnings, urgent and emergency warnings (Lv2-Lv5) for your location and saved places, plus landslide, river flood, tornado watch and record heavy rain notices from the Japan Meteorological Agency.
Author: Bousai Apps
"""

# bousai: requires core data warnings

load("render.star", "canvas", "render")
load("schema.star", "schema")

# Band text candidates per severity, longest first; the first one that fits the band is used.
WARNINGS_LEVEL_BANDS = {
    2: ["Lv2 Advisory", "Lv2 Advis.", "Lv2"],
    3: ["Lv3 Warning", "Lv3 Warn.", "Lv3"],
    4: ["Lv4 Urgent Warning", "Lv4 Urgent Warn", "Lv4 Urgent", "Lv4"],
    5: ["Lv5 Emergency Warning", "Lv5 Emergency", "Lv5 Emerg.", "Lv5"],
}

WARNINGS_NOTICE_BANDS = {
    "Tornado Watch": ["Tornado Watch", "Tornado"],
    "Record Short-Term Heavy Rain": ["Record Short-Term Heavy Rain", "Record Heavy Rain", "Record Rain", "Rec. Rain", "Rain"],
}

# A page is held at least this long (the core's bousai_hold_frames floor). Cards that do not fit the dwell time
# at that pace lose their area / time lines first, then the least urgent ones become a "+N more" card.
WARNINGS_MIN_PAGE_FRAMES = 25

def warnings_min_level(config):
    """Minimum level (20..50) from the config, Advisory by default."""
    value = config.get("min_level") or "20"
    if value in ["20", "30", "40", "50"]:
        return int(value)
    return 20

def warnings_content_width():
    """Width available to text: the severity stripe, a 1 px gap and a 1 px right margin are taken off."""
    return canvas.width() - 3

def warnings_band_height(ui):
    """Band height: the line height, or the bare font height when that buys one more text line (xlarge)."""
    line = ui["line_h"]
    font = bousai_font_height(ui)
    if (canvas.height() - font) // line > (canvas.height() - line) // line:
        return font
    return line

def warnings_per_page(ui):
    """Text lines that fit under the band."""
    return max(1, (canvas.height() - warnings_band_height(ui)) // ui["line_h"])

def warnings_fit_text(ui, options, width):
    """First option that fits `width` pixels (the last one when none does)."""
    for option in options:
        if bousai_text_width(ui, option) <= width:
            return option
    return options[-1]

def warnings_notice_options(kind, sev):
    """Band text candidates for a notice kind."""
    if kind in WARNINGS_NOTICE_BANDS:
        return WARNINGS_NOTICE_BANDS[kind]
    if kind.startswith("River Flood"):
        return [kind, "River Flood Lv%d" % sev, "Flood Lv%d" % sev, "Lv%d" % sev]
    return [kind]

def warnings_wrap(ui, text, width):
    """Greedy word wrap using the real text width."""
    lines = []
    current = ""
    for word in text.split(" "):
        trial = current + " " + word if current else word
        if not current or bousai_text_width(ui, trial) <= width:
            current = trial
        else:
            lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines

def warnings_when(t, tz, now):
    """Issue time: clock only when it is today, otherwise month/day and clock."""
    if t.in_location(tz).format("2006-01-02") == now.in_location(tz).format("2006-01-02"):
        return bousai_hhmm(t, tz)
    return bousai_mdhm(t, tz)

# ---------------------------------------------------------------------------
# Cards: plain data first (so the page count, and with it the frame budget, is known), widgets afterwards.
# A card is {sev, band: [text options], rows: [content lines], info: [area / time lines], count, first}.

def warnings_line(text, color):
    return {"kind": "line", "text": text, "color": color}

def warnings_short_name(name):
    """Area name without a trailing City / Town / Village (JMA English names), for the compact info line."""
    for suffix in [" City", " Town", " Village"]:
        if name.endswith(suffix) and len(name) > len(suffix):
            return name[:-len(suffix)]
    return name

def warnings_info(ui, rows, name, when):
    """Area name and issue time under `rows` content lines.

    Two plain lines when they fit on the same page, otherwise one line: the time, then the short name (it
    scrolls when it is still too long for what is left).
    """
    width = warnings_content_width()
    short = warnings_short_name(name)
    free = width - bousai_text_width(ui, when) - 3
    if rows + 2 <= warnings_per_page(ui) or free < min(bousai_text_width(ui, short), width // 2):
        shown = name
        if bousai_text_width(ui, name) > width and bousai_text_width(ui, short) <= width:
            shown = short
        return [warnings_line(shown, ui["muted"]), warnings_line(warnings_fit_text(ui, ["Issued " + when, "At " + when], width), ui["muted"])]
    return [{"kind": "pair", "name": short, "when": when}]

def warnings_group_card(ui, place, items, tz, now):
    """Card for all warnings of one level: one line per element, then area and issue time."""
    latest = items[0]["issued"]
    for w in items:
        if w["issued"] > latest:
            latest = w["issued"]
    rows = [warnings_line(w["element_en"], ui["fg"]) for w in items]
    info = warnings_info(ui, len(rows), place["name"], warnings_when(latest, tz, now))
    return {"sev": items[0]["sev"], "band": WARNINGS_LEVEL_BANDS[items[0]["sev"]], "rows": rows, "info": info, "count": len(items)}

def warnings_notice_card(ui, place, notice, tz, now):
    """Card for a tornado watch, record rain or river flood notice."""
    lines = warnings_wrap(ui, notice["text_en"], warnings_content_width())
    if len(lines) > 4:
        # Very long text: the lines beyond the third are joined into one scrolling line.
        lines = lines[:3] + [" ".join(lines[3:])]
    rows = [warnings_line(line, ui["fg"]) for line in lines]
    info = warnings_info(ui, len(rows), place["name"], warnings_when(notice["issued"], tz, now))
    return {"sev": notice["sev"], "band": warnings_notice_options(notice["kind_en"], notice["sev"]), "rows": rows, "info": info, "count": 1}

def warnings_calm_card(ui, places, min_level, tz, now):
    """'No warnings' card listing the places that have nothing at or above the minimum level."""
    title = "Warnings" if min_level <= 20 else "Warnings Lv%d+" % (min_level // 10)
    rows = [warnings_line("No warnings", ui["fg"])]
    for p in places:
        rows.append(warnings_line(p["name"] if p["ok"] else p["name"] + " (no data)", ui["muted"]))
    rows.append(warnings_line("Checked " + bousai_hhmm(now, tz), ui["muted"]))
    return {"sev": 1, "band": [title, "Warnings"], "rows": rows, "info": [], "count": 0}

def warnings_unknown_card(ui, rejected):
    """Hint for saved-location codes that are not JMA municipality codes."""
    return {"sev": 2, "band": ["Unknown codes", "Bad codes", "Codes"], "rows": [warnings_line(code, ui["muted"]) for code in rejected], "info": [], "count": 0}

def warnings_entries(place, min_level):
    """Display entries of a place at or above the minimum level: warning levels first, then notices of the same severity."""
    groups = {}
    for w in place["current"]:
        if w["level"] >= min_level:
            groups.setdefault(w["level"], []).append(w)
    entries = []
    for items in groups.values():
        entries.append({"sev": items[0]["sev"], "order": 0, "items": items, "notice": None})
    for n in place["notices"]:
        if n["sev"] * 10 >= min_level:
            entries.append({"sev": n["sev"], "order": 1, "items": None, "notice": n})
    return sorted(entries, key = lambda e: (-e["sev"], e["order"]))

def warnings_lines_of(card):
    """All lines of a card, content first."""
    return card["rows"] + card["info"]

def warnings_pages_of(ui, card):
    """[lines per page (balanced), page count] of a card."""
    per_page = warnings_per_page(ui)
    n = max(1, len(warnings_lines_of(card)))
    count = (n + per_page - 1) // per_page
    return [(n + count - 1) // count, count]

def warnings_total_pages(ui, cards):
    total = 0
    for card in cards:
        total += warnings_pages_of(ui, card)[1]
    return total

def warnings_fit_budget(ui, cards):
    """Fit the cards into the dwell time at a readable pace.

    First the area / time lines are dropped from every card except the first of each place, then the leading
    cards that fit are kept and the rest becomes a '+N more' card.
    """
    capacity = max(1, bousai_budget_frames() // WARNINGS_MIN_PAGE_FRAMES)
    if warnings_total_pages(ui, cards) <= capacity:
        return cards
    cards = [card if card["first"] else dict(card, info = []) for card in cards]
    if warnings_total_pages(ui, cards) <= capacity:
        return cards
    kept = []
    used = 0
    for card in cards:
        pages = warnings_pages_of(ui, card)[1]
        if kept and used + pages > capacity - 1:
            break
        kept.append(card)
        used += pages
    more = 0
    sev = 2
    for card in cards[len(kept):]:
        more += card["count"]
        if card["count"] > 0:
            sev = max(sev, card["sev"])
    if more > 0:
        kept.append({"sev": sev, "band": ["More alerts", "More"], "rows": [warnings_line("+%d more" % more, ui["fg"])], "info": [], "count": 0, "first": False})
    return kept

# ---------------------------------------------------------------------------
# Widgets

def warnings_band(ui, options, color, sev):
    """Coloured level band. Emergency (Lv5) blinks, except at low contrast (handled by bousai_blink)."""
    height = warnings_band_height(ui)
    text = warnings_fit_text(ui, options, canvas.width() - 2)
    band = render.Box(width = canvas.width(), height = height, color = color, child = render.Row(expanded = True, cross_align = "center", children = [
        render.Padding(pad = (1, 0, 0, 0), child = bousai_text(ui, text, bousai_on(color))),
    ]))
    if sev >= 5:
        band = bousai_blink(ui, band, canvas.width(), height)
    return band

def warnings_row(ui, spec, color, frames):
    """One line with the severity stripe on its left edge."""
    width = warnings_content_width()
    if spec["kind"] == "pair":
        when_w = bousai_text_width(ui, spec["when"])
        child = render.Row(children = [
            bousai_text(ui, spec["when"], ui["muted"]),
            render.Box(width = 3, height = 1),
            bousai_fit(ui, spec["name"], width = width - when_w - 3, color = ui["muted"], frames = frames),
        ])
    else:
        child = bousai_fit(ui, spec["text"], width = width, color = spec["color"], frames = frames)
    return render.Row(children = [
        render.Box(width = 1, height = ui["line_h"], color = color),
        render.Padding(pad = (1, 0, 0, 0), child = child),
    ])

def warnings_page(ui, band, rows, color):
    """One top-aligned page; high contrast adds a frame in the severity colour."""
    w, h = canvas.width(), canvas.height()
    page = render.Box(width = w, height = h, child = render.Column(expanded = True, main_align = "start", cross_align = "start", children = [band] + rows))
    if not ui["frame"]:
        return page
    return render.Stack(children = [
        page,
        render.Padding(pad = (0, h - 1, 0, 0), child = render.Box(width = w, height = 1, color = color)),
        render.Padding(pad = (w - 1, 0, 0, 0), child = render.Box(width = 1, height = h, color = color)),
    ])

def warnings_render(ui, cards):
    """Root widget for a list of cards: balanced pages, all sharing the dwell time."""
    if not cards:
        return []
    cards = warnings_fit_budget(ui, cards)
    total = warnings_total_pages(ui, cards)
    frames = bousai_hold_frames(total) if total > 1 else bousai_budget_frames()

    pages = []
    for card in cards:
        color = ui["sev"][card["sev"]]
        band = warnings_band(ui, card["band"], color, card["sev"])
        rows = [warnings_row(ui, spec, color, frames) for spec in warnings_lines_of(card)]
        per_page = warnings_pages_of(ui, card)[0]
        for start in range(0, len(rows), per_page):
            pages.append(warnings_page(ui, band, rows[start:start + per_page], color))
    if len(pages) == 1:
        return bousai_root(ui, pages[0])
    return bousai_root(ui, render.Sequence(children = [bousai_hold(p, frames) for p in pages]))

# ---------------------------------------------------------------------------
# Data

def warnings_places(config, ui):
    """Main place plus saved places: [places, rejected codes]; a root widget or [] when nothing can be shown."""
    area = bousai_area(config)
    if area == None:
        if bousai_bool(config, "alert_only", False):
            return []
        return bousai_message(ui, "Warnings", ["Not in Japan", "JMA data covers", "Japan only"])
    main_place = bousai_warnings_place(area)
    if not main_place["ok"]:
        if bousai_bool(config, "alert_only", False):
            return []
        return bousai_message(ui, "Warnings", ["JMA data", "unavailable", "Retrying soon"])
    places = [main_place]
    parsed = bousai_warnings_parse_codes(config.get("saved_areas"))
    rejected = list(parsed[1])
    table = bousai_area_table()
    for code in parsed[0]:
        if code == area["class20"]:
            continue
        saved = bousai_warnings_area_for_code(code, table)
        if saved == None:
            rejected.append(code)
        else:
            places.append(bousai_warnings_place(saved))
    return [places, rejected]

def main(config):
    ui = bousai_ui(config)
    alert_only = bousai_bool(config, "alert_only", False)
    min_level = warnings_min_level(config)
    tz = bousai_location(config)["tz"]
    now = bousai_now()

    demo = bousai_bool(config, "demo", False)
    rejected = []
    if demo:
        places = bousai_warnings_demo()
    else:
        res = warnings_places(config, ui)
        if type(res) != "list" or len(res) == 0:
            return res
        places, rejected = res[0], res[1]

    cards = []
    calm = []
    for place in places:
        entries = warnings_entries(place, min_level) if place["ok"] else []
        if not entries:
            calm.append(place)
            continue
        if calm and not alert_only:
            cards.append(dict(warnings_calm_card(ui, calm, min_level, tz, now), first = True))
        calm = []
        for i, e in enumerate(entries):
            if e["notice"] != None:
                card = warnings_notice_card(ui, place, e["notice"], tz, now)
            else:
                card = warnings_group_card(ui, place, e["items"], tz, now)
            cards.append(dict(card, first = i == 0))

    if alert_only and not demo:
        if not cards:
            return []
    elif calm:
        cards.append(dict(warnings_calm_card(ui, calm, min_level, tz, now), first = True))
    if rejected and not (alert_only and not demo):
        cards.append(dict(warnings_unknown_card(ui, rejected), first = True))
    return warnings_render(ui, cards)

def get_schema():
    return bousai_schema([
        schema.Dropdown(
            id = "min_level",
            name = "Minimum level",
            desc = "Hide warnings below this level.",
            icon = "filter",
            default = "20",
            options = [
                schema.Option(display = "Advisory (Lv2)", value = "20"),
                schema.Option(display = "Warning (Lv3)", value = "30"),
                schema.Option(display = "Urgent warning (Lv4)", value = "40"),
                schema.Option(display = "Emergency warning (Lv5)", value = "50"),
            ],
        ),
        schema.Toggle(
            id = "alert_only",
            name = "Alert only",
            desc = "Skip this app unless something at or above the minimum level is active. Enable AutoPin in Tronbyt so it takes over the display, and set the minimum level to Warning (Lv3) or higher so advisories do not.",
            icon = "bell",
            default = False,
        ),
        schema.Text(
            id = "saved_areas",
            name = "Saved locations",
            desc = "Extra 7-digit JMA municipality codes, comma separated (for example 2710000, 4010000). Shown after your location.",
            icon = "bookmark",
            default = "",
        ),
        schema.Toggle(
            id = "demo",
            name = "Show sample alert",
            desc = "Show an embedded heavy-rain sample: Lv4 Heavy Rain and Landslide, river flood, record rain.",
            icon = "flask",
            default = False,
        ),
    ])
