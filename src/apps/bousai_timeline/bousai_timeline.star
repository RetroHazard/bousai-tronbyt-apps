"""
Applet: Bousai Timeline
Summary: Last 72 hours of Japan alerts
Description: Newest-first timeline of the past 24 to 72 hours from the Japan Meteorological Agency: when weather advisories, warnings and landslide alerts were issued and lifted for your municipality, with tornado watches, record heavy rain, weather information, earthquakes, tsunami, volcano alert levels and eruptions, and typhoon changes.
Author: Bousai Apps
"""

# bousai: requires core data quake warnings timeline

load("cache.star", "cache")
load("render.star", "canvas", "render")
load("schema.star", "schema")
load("time.star", "time")

# A page is held at least this many frames (2.5 s), the same floor as bousai_hold_frames(); long text on a page
# scrolls at no more than TIMELINE_MAX_SPEED pixels per frame, so a page with long text is held longer.
TIMELINE_MIN_FRAMES = 25
TIMELINE_MAX_SPEED = 2

def timeline_int(config, key, default, lo, hi):
    """Integer option clamped to lo..hi."""
    raw = (config.get(key) or "").strip()
    if not raw or not raw.isdigit():
        return default
    return max(lo, min(hi, int(raw)))

def timeline_wrap(ui, text, width):
    """Greedy word wrap of a short message to the screen width."""
    lines = []
    current = ""
    for word in text.split(" "):
        trial = (current + " " + word) if current else word
        if current and bousai_text_width(ui, trial) > width:
            lines.append(current)
            current = word
        else:
            current = trial
    if current:
        lines.append(current)
    return lines

def timeline_options(config):
    return {
        "hours": timeline_int(config, "window", 72, 1, 168),
        "min_sev": timeline_int(config, "min_sev", 1, 1, 5),
        "quake_int": config.get("quake_int") or "2",
        "volcano_km": timeline_int(config, "volcano_km", 300, 0, 5000),
        "minor": bousai_bool(config, "show_minor", True),
        "cats": {
            "warn": bousai_bool(config, "show_warnings", True),
            "notice": bousai_bool(config, "show_notices", True),
            "info": bousai_bool(config, "show_info", True),
            "quake": bousai_bool(config, "show_quakes", True),
            "eew": bousai_bool(config, "show_eew", False),
            "tsunami": bousai_bool(config, "show_tsunami", True),
            "volcano": bousai_bool(config, "show_volcano", True),
            "typhoon": bousai_bool(config, "show_typhoon", True),
        },
    }

# ---------------------------------------------------------------------------
# Demo: a typhoon night modelled on Typhoon Hagibis (No. 19, 12 October 2019, Kanto) with illustrative quake,
# EEW, tsunami and volcano rows. Times are minutes before now so the sample always looks current.

def timeline_demo_events(now, tz):
    def ev(minutes, cat, sev, chip, ckind, cval, text, tag = "", fold = False):
        return bousai_timeline_event(now.unix - minutes * 60, cat, sev, chip, ckind, cval, text, tag, fold)

    until = (now + time.parse_duration("40m")).in_location(tz).format("15:04")
    return [
        ev(12, "warn", 5, "Lv5", "sev", 5, "Heavy Rain", "Issued", True),
        ev(26, "notice", 4, "Rec.Rain", "sev", 4, "About 100 mm/h"),
        ev(41, "warn", 4, "Lv4", "sev", 4, "Landslide", "Issued", True),
        ev(55, "typhoon", 4, "V.Strong", "sev", 4, "No.19 Hagibis", "Down", True),
        ev(78, "notice", 3, "Tornado", "sev", 3, "Watch until " + until),
        ev(95, "warn", 4, "Lv4", "sev", 4, "Heavy Rain", "Issued", True),
        ev(130, "warn", 3, "Lv3", "sev", 3, "Storm", "Issued", True),
        ev(150, "info", 2, "Info", "sev", 2, "Typhoon No.19, Heavy rain, Gusts", "x3"),
        ev(176, "quake", 3, "Int 4", "int", "4", "M5.7 Off Chiba"),
        ev(177, "eew", 4, "EEW 5-", "int", "5-", "M5.7 35.2N 140.4E"),
        ev(232, "warn", 3, "Lv3", "sev", 3, "Landslide", "Issued", True),
        ev(300, "warn", 3, "Lv3", "sev", 3, "Heavy Rain", "Issued", True),
        ev(371, "tsunami", 2, "Lifted", "off", 0, "Tsunami advisory"),
        ev(430, "warn", 2, "Lv3>2", "sev", 2, "High Wave", "Lowered", True),
        ev(540, "volcano", 3, "Erupt", "sev", 3, "Sakurajima eruptions", "x4"),
        ev(700, "warn", 2, "Lv2", "off", 0, "Thunderstorm, Dense Fog", "Lifted", True),
        ev(1500, "warn", 2, "Lv2", "sev", 2, "Gale", "Issued", True),
        ev(1700, "volcano", 3, "Lv3>2", "sev", 2, "Tokachidake", "Lowered", True),
    ]

# ---------------------------------------------------------------------------
# Layout: every event is a two-line cell. Line 1: clock, coloured badge, optional tag. Line 2: the description
# (it scrolls when it is wider than the screen). Each page is a day band plus as many cells as the text size allows.

def timeline_layout(ui):
    body = ui["font"]
    small = ui["small_font"]
    head_h = bousai_font_height(ui, body)
    l1_h = bousai_font_height(ui, small) + 1
    cell_h = l1_h + bousai_font_height(ui, body) + 1
    per_page = max(1, (canvas.height() - head_h) // cell_h)
    return {
        "small": small,
        "head_h": head_h,
        "l1_h": l1_h,
        "cell_h": cell_h,
        "per_page": per_page,
        # Spare pixel rows are shared as a gap above every cell.
        "gap": (canvas.height() - head_h - per_page * cell_h) // (per_page + 1),
    }

def timeline_chip_color(ui, ev):
    if ev["ckind"] == "sev":
        return bousai_sev_color(ui, ev["cval"])
    if ev["ckind"] == "int":
        return bousai_intensity_color(ui, ev["cval"])
    return ui["faint"]

def timeline_parts(ui, layout, ev, tz):
    """What a cell shows: {clock, chip_w, tag, text}.

    The clock sits before the badge; when the two do not fit side by side (large text) it leads the description
    instead. The tag sits beside the badge when it fits, else (for tags that carry a verb) it is appended to the
    description.
    """
    small = layout["small"]
    clock = bousai_hhmm(time.from_timestamp(ev["t"]), tz) if ev["t"] > 0 else ""
    chip_w = bousai_text_width(ui, ev["chip"], small) + 3
    text = ev["text"]
    clock_w = (bousai_text_width(ui, clock, small) + 1) if clock else 0
    if clock and 1 + clock_w + chip_w > canvas.width():
        text = clock + " " + text
        clock = ""
        clock_w = 0
    used = 1 + clock_w + chip_w
    tag = ""
    if ev["tag"]:
        if used + 2 + bousai_text_width(ui, ev["tag"], small) <= canvas.width():
            tag = ev["tag"]
        elif ev["fold"]:
            text = (text + " " + ev["tag"].lower()).strip()
    return {"clock": clock, "chip_w": chip_w, "tag": tag, "text": text}

def timeline_scroll_frames(ui, text, width):
    """Frames a line needs to scroll at TIMELINE_MAX_SPEED pixels per frame at most (the minimum when it fits)."""
    travel = bousai_text_width(ui, text) - width
    if travel <= 0:
        return TIMELINE_MIN_FRAMES
    for f in range(TIMELINE_MIN_FRAMES, 400):
        # bousai_ticker pauses min(8, f/4) frames before and min(8, f/6) after the scroll.
        if f - min(8, f // 4) - min(8, f // 6) >= (travel + TIMELINE_MAX_SPEED - 1) // TIMELINE_MAX_SPEED:
            return f
    return 400

def timeline_page_need(ui, layout, page, tz, budget):
    """Frames a page needs: the slowest-scrolling line decides, but never more than a third of the dwell time."""
    need = TIMELINE_MIN_FRAMES
    for e in page["events"]:
        need = max(need, timeline_scroll_frames(ui, timeline_parts(ui, layout, e, tz)["text"], canvas.width() - 2))
    return min(need, max(TIMELINE_MIN_FRAMES, budget // 3))

def timeline_header(ui, layout, label, right):
    kids = [render.Padding(pad = (1, 0, 0, 0), child = bousai_text(ui, label))]
    if right:
        kids.append(render.Padding(pad = (0, 0, 1, 0), child = bousai_text(ui, right, ui["muted"])))
    return render.Box(width = canvas.width(), height = layout["head_h"], color = ui["panel"], child = render.Row(expanded = True, main_align = "space_between", cross_align = "center", children = kids))

def timeline_cell(ui, layout, ev, tz, frames):
    small = layout["small"]
    width = canvas.width()
    parts = timeline_parts(ui, layout, ev, tz)
    color = timeline_chip_color(ui, ev)
    chip = render.Box(width = parts["chip_w"], height = layout["l1_h"], color = color, child = bousai_text(ui, ev["chip"], bousai_on(color), small))
    kids = []
    if parts["clock"]:
        kids.append(render.Padding(pad = (1, 0, 0, 0), child = bousai_text(ui, parts["clock"], ui["fg"], small)))
    kids.append(render.Padding(pad = (1, 0, 0, 0), child = chip))
    if parts["tag"]:
        kids.append(render.Padding(pad = (2, 0, 0, 0), child = bousai_text(ui, parts["tag"], ui["muted"], small)))
    line1 = render.Box(width = width, height = layout["l1_h"], child = render.Row(expanded = True, main_align = "start", cross_align = "center", children = kids))
    text_color = ui["muted"] if ev["ckind"] == "off" else ui["fg"]
    line2 = render.Padding(pad = (1, 0, 0, 0), child = bousai_fit(ui, parts["text"], width = width - 2, color = text_color, frames = frames))
    return render.Column(children = [line1, line2])

def timeline_page(ui, layout, label, right, events, tz, frames):
    w, h = canvas.width(), canvas.height()
    kids = [timeline_header(ui, layout, label, right)]
    for e in events:
        if layout["gap"] > 0:
            kids.append(render.Box(width = w, height = layout["gap"]))
        kids.append(timeline_cell(ui, layout, e, tz, frames))
    return render.Box(width = w, height = h, child = render.Column(expanded = True, main_align = "start", cross_align = "start", children = kids))

# ---------------------------------------------------------------------------
# Pages: grouped by local day, trimmed to the dwell time

def timeline_day_label(unix, now, tz):
    day = time.from_timestamp(unix).in_location(tz)
    here = now.in_location(tz)
    if day.format("2006-01-02") == here.format("2006-01-02"):
        return "Today"
    if day.format("2006-01-02") == (here + time.parse_duration("-24h")).format("2006-01-02"):
        return "Yesterday"
    return day.format("Mon 1/2")

def timeline_pages(events, per_page, now, tz):
    """Newest-first events grouped into pages of one day each: [{label, events}]."""
    pages = []
    last_day = ""
    for e in events:
        day = time.from_timestamp(e["t"]).in_location(tz).format("2006-01-02")
        if pages and day == last_day and len(pages[-1]["events"]) < per_page:
            pages[-1]["events"].append(e)
        else:
            pages.append({"label": timeline_day_label(e["t"], now, tz), "events": [e]})
        last_day = day
    return pages

def timeline_total(values):
    total = 0
    for v in values:
        total += v
    return total

def timeline_select(need, budget, start):
    """Pages shown in this render: [[index, frames needed]] and the position to continue from next time.

    Pages are taken in order while their frames fit the dwell time. When they do not all fit, the newest page is
    always shown and the rest rotate: a render shows the pages that follow `start` (kept in the cache between renders).
    """
    n = len(need)
    chosen = [[0, need[0]]]
    if n == 1:
        return [chosen, 0]
    used = need[0]
    rest = n - 1
    if timeline_total(need) <= budget:
        return [[[i, need[i]] for i in range(n)], 0]
    taken = 0
    for j in range(rest):
        i = 1 + (start + j) % rest
        if used + need[i] > budget and taken > 0:
            break
        chosen.append([i, min(need[i], max(TIMELINE_MIN_FRAMES, budget - used))])
        used += chosen[-1][1]
        taken += 1
    return [sorted(chosen), (start + taken) % rest]

def timeline_position(key):
    raw = cache.get("bousai_timeline:pos:" + key)
    return int(raw) if raw and raw.isdigit() else 0

def timeline_store(key, pos):
    cache.set("bousai_timeline:pos:" + key, str(pos), ttl_seconds = 6 * 3600)

def timeline_render(ui, events, notes, now, tz, hours, key):
    """Root widget for the events (and notes about missing sources)."""
    layout = timeline_layout(ui)
    pages = timeline_pages(events, layout["per_page"], now, tz)
    if notes:
        note_events = [bousai_timeline_event(0, "note", 1, "!", "off", 0, n) for n in notes]
        for i in range(0, len(note_events), layout["per_page"]):
            pages.append({"label": "Notes", "events": note_events[i:i + layout["per_page"]]})
    budget = bousai_budget_frames()
    need = [timeline_page_need(ui, layout, p, tz, budget) for p in pages]
    picked = timeline_select(need, budget, timeline_position(key))
    shown = picked[0]
    timeline_store(key, picked[1])
    spare = 0
    if len(shown) == 1:
        spare = budget - shown[0][1]
    else:
        spare = max(0, (budget - timeline_total([s[1] for s in shown])) // len(shown))
    widgets = []
    for s in shown:
        page = pages[s[0]]
        frames = s[1] + spare
        right = "%d/%d" % (s[0] + 1, len(pages)) if len(pages) > 1 else "%dh" % hours
        if bousai_text_width(ui, page["label"] + " " + right) + 4 > canvas.width():
            right = None
        widgets.append(bousai_hold(timeline_page(ui, layout, page["label"], right, page["events"], tz, frames), frames))
    if len(widgets) == 1:
        return bousai_root(ui, widgets[0])
    return bousai_root(ui, render.Sequence(children = widgets))

# ---------------------------------------------------------------------------

def main(config):
    ui = bousai_ui(config)
    start = time.now()
    tz = bousai_location(config)["tz"]
    now = bousai_now()
    opts = timeline_options(config)

    if bousai_bool(config, "demo", False):
        return timeline_render(ui, timeline_demo_events(now, tz), [], now, tz, 72, "demo")

    result = bousai_timeline_build(config, opts, start)
    events = result["events"]
    notes = result["notes"]
    if len(events) == 0:
        lines = ["No events in", "the last %d h" % opts["hours"]]
        if notes:
            lines = []
            for n in notes:
                lines.extend(timeline_wrap(ui, n, canvas.width() - 2))
        return bousai_message(ui, "Timeline", lines)

    area = result["area"]
    key = "%s:%d:%d" % (area["class20"] if area else "-", opts["hours"], opts["min_sev"])
    return timeline_render(ui, events, notes, now, tz, opts["hours"], key)

def get_schema():
    return bousai_schema([
        schema.Dropdown(
            id = "window",
            name = "Time window",
            desc = "How far back the timeline reaches.",
            icon = "clockRotateLeft",
            default = "72",
            options = [
                schema.Option(display = "Last 24 hours", value = "24"),
                schema.Option(display = "Last 48 hours", value = "48"),
                schema.Option(display = "Last 72 hours", value = "72"),
            ],
        ),
        schema.Dropdown(
            id = "min_sev",
            name = "Minimum severity",
            desc = "Hide events below this level. Advisory = Lv2, Int 3, tsunami advisory; Warning = Lv3, Int 4, tornado watch; Urgent = Lv4, Int 5-, record rain, EEW.",
            icon = "filter",
            default = "1",
            options = [
                schema.Option(display = "Everything", value = "1"),
                schema.Option(display = "Advisory and above", value = "2"),
                schema.Option(display = "Warning and above", value = "3"),
                schema.Option(display = "Urgent and above", value = "4"),
            ],
        ),
        schema.Dropdown(
            id = "quake_int",
            name = "Minimum quake intensity",
            desc = "Hide earthquakes weaker than this JMA seismic intensity (shindo).",
            icon = "waveSquare",
            default = "2",
            options = [
                schema.Option(display = "Int 1 and up (all felt quakes)", value = "1"),
                schema.Option(display = "Int 2 and up", value = "2"),
                schema.Option(display = "Int 3 and up", value = "3"),
                schema.Option(display = "Int 4 and up", value = "4"),
                schema.Option(display = "Int 5- and up", value = "5-"),
            ],
        ),
        schema.Dropdown(
            id = "volcano_km",
            name = "Volcano radius",
            desc = "Show eruptions and alert-level changes of volcanoes within this distance of your location. Level 4 and 5 changes always show.",
            icon = "volcano",
            default = "300",
            options = [
                schema.Option(display = "100 km", value = "100"),
                schema.Option(display = "300 km", value = "300"),
                schema.Option(display = "500 km", value = "500"),
                schema.Option(display = "Anywhere in Japan", value = "0"),
            ],
        ),
        schema.Toggle(
            id = "show_warnings",
            name = "Weather warnings",
            desc = "Advisories, warnings and landslide alerts for your municipality: when issued, lowered and lifted.",
            icon = "cloudShowersHeavy",
            default = True,
        ),
        schema.Toggle(
            id = "show_minor",
            name = "Minor advisories",
            desc = "Include thunderstorm, dense fog, dry air, frost, low temperature, snow melting and icing advisories. Turn off to keep the timeline for rain, landslide, wind, wave, tide and snow.",
            icon = "cloudBolt",
            default = True,
        ),
        schema.Toggle(
            id = "show_notices",
            name = "Tornado, record rain, floods",
            desc = "Tornado watch, record short-term heavy rain and designated river flood notices.",
            icon = "tornado",
            default = True,
        ),
        schema.Toggle(
            id = "show_info",
            name = "Weather information",
            desc = "JMA weather information bulletins for your prefecture, shown as their topics (for example Heavy rain, Lightning, Gusts).",
            icon = "bullhorn",
            default = True,
        ),
        schema.Toggle(
            id = "show_quakes",
            name = "Earthquakes",
            desc = "Felt earthquakes in Japan from the JMA list.",
            icon = "waveSquare",
            default = True,
        ),
        schema.Toggle(
            id = "show_eew",
            name = "EEW warnings",
            desc = "Earthquake Early Warnings and cancellations from the P2PQuake history. Adds one request to P2PQuake.",
            icon = "bell",
            default = False,
        ),
        schema.Toggle(
            id = "show_tsunami",
            name = "Tsunami",
            desc = "Tsunami warnings, advisories and forecasts.",
            icon = "houseTsunami",
            default = True,
        ),
        schema.Toggle(
            id = "show_volcano",
            name = "Volcanoes",
            desc = "Eruptions (repeated eruptions of one volcano merge into one row a day) and alert-level changes.",
            icon = "volcano",
            default = True,
        ),
        schema.Toggle(
            id = "show_typhoon",
            name = "Typhoons",
            desc = "Formation, strengthening, weakening and the latest status of typhoons.",
            icon = "hurricane",
            default = True,
        ),
        schema.Toggle(
            id = "demo",
            name = "Show sample timeline",
            desc = "Show an embedded sample: a typhoon night modelled on Typhoon Hagibis (12 October 2019) with illustrative quake, EEW, tsunami and volcano rows.",
            icon = "flask",
            default = False,
        ),
    ])
