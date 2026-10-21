"""
Applet: Bousai EEW
Summary: Earthquake early warning
Description: JMA Earthquake Early Warning with epicentre, magnitude, expected intensity and an S-wave countdown for your location.
Author: Bousai Apps
"""

# bousai: requires core eew

load("math.star", "math")
load("render.star", "canvas", "render")
load("schema.star", "schema")

# Shortest time a page of one alert stays up (frames of 100 ms).
MIN_PAGE_FRAMES = 25

SOURCE_TEXT = {
    "Wolfx": "JMA via Wolfx",
    "NIED": "NIED Kyoshin Monitor",
    "P2PQuake": "JMA via P2PQuake",
    "Sample": "Embedded sample",
}

def fit_text(ui, options, width, font = None):
    """First option that fits `width` (the last one otherwise)."""
    for s in options:
        if bousai_text_width(ui, s, font) <= width:
            return s
    return options[-1]

def left_cell(_ui, child, w, h):
    """Left-aligned child in a w x h cell, inset 1 px (some glyphs have a -1 x offset and clip at x = 0)."""
    return render.Box(width = w, height = h, child = render.Row(expanded = True, main_align = "start", cross_align = "center", children = [render.Padding(pad = (1, 0, 0, 0), child = child)]))

def text_row(ui, item, frames):
    """One text row from (text, color): inset 1 px, scrolls within `frames` when too wide."""
    return render.Padding(pad = (1, 0, 0, 0), child = bousai_fit(ui, item[0], width = canvas.width() - 1, color = item[1], frames = frames))

def level_ok(ev, level):
    """Minimum-level filter: all reports, JMA expects Int 3+ or a warning, warnings only."""
    if ev["cancel"]:
        return level == "all" or ev["warn"]
    if level == "warn":
        return ev["warn"]
    if level == "int3":
        return ev["warn"] or bousai_intensity_rank(ev["max_int"] or "") >= bousai_intensity_rank("3")
    return True

SHORT_TITLE = {"WARNING": "WARN", "FORECAST": "FCST", "CANCELLED": "CANCEL"}

def title_text(ev, short):
    word = "CANCELLED" if ev["cancel"] else ("WARNING" if ev["warn"] else "FORECAST")
    return SHORT_TITLE[word] if short else word

def clock(t, tz):
    return t.in_location(tz).format("15:04:05") if t else "--:--:--"

def intensity_fill(ui, label):
    return ui["intensity"].get(label, ui["muted"])

# ---------------------------------------------------------------------------
# Header band (blinks for warnings; the text stays readable in both phases)

def header_widget(ui, seg, right, on):
    W = canvas.width()
    bg = seg["band"] if on else ui["panel"]
    fg = bousai_on(seg["band"]) if on else seg["band"]
    right_w = bousai_text_width(ui, right) + 2 if right else 0
    key = (right_w, on)
    if key not in seg["titles"]:
        seg["titles"][key] = bousai_fit(ui, seg["title"], width = W - right_w - 1, color = fg, frames = seg["page_frames"])
    kids = [render.Padding(pad = (1, 0, 0, 0), child = seg["titles"][key])]
    if right:
        kids.append(render.Padding(pad = (W - right_w + 1, 0, 0, 0), child = bousai_text(ui, right, fg)))
    return render.Box(width = W, height = ui["line_h"], color = bg, child = render.Stack(children = kids))

def header_right(ui, seg, page, r, sec):
    """Right-hand header text: serial tag on the hero page, countdown on the detail pages. Extra
    large text has no label row, so the hero header alternates 'S-wave' with the tag."""
    if page["kind"] == "hero":
        if seg["labels"] or not seg["countdown"]:
            return seg["tag"]
        options = ["S-wave", seg["tag"]] if seg["tag"] else ["S-wave"]
        return options[(sec // 2) % len(options)]
    if not seg["countdown"]:
        return seg["tag"]
    if r > 0:
        return "%ds" % int(math.ceil(r))
    if bousai_text_width(ui, seg["title"]) + bousai_text_width(ui, "Arrived") + 6 <= canvas.width():
        return "Arrived"
    return "Now"

def serial_tag(ui, ev, demo, room):
    """Serial / sample tag for the header, or None when no variant fits `room`."""
    n = ev["serial"]
    if demo:
        options = ["SAMPLE", "DEMO"]
    elif ev["final"] and not ev["cancel"]:
        options = ["#%d FINAL" % n, "#%d FIN" % n, "#%dF" % n, "#%d" % n]
    else:
        options = ["#%d" % n]
    for s in options:
        if bousai_text_width(ui, s) <= room:
            return s
    return None

# ---------------------------------------------------------------------------
# Hero page: S-wave countdown and estimated intensity at your location

def count_widget(ui, r, width, color):
    """Seconds to S-wave arrival (rounded up), or 'Arrived' once past; font shrinks to fit."""
    big = ui["big_font"]
    if r > 0:
        s = "%ds" % int(math.ceil(r))
        font = big if bousai_text_width(ui, s, big) <= width else ui["font"]
        return bousai_text(ui, s, color, font)
    for font in [big, ui["font"]]:
        if bousai_text_width(ui, "Arrived", font) <= width:
            return bousai_text(ui, "Arrived", color, font)
    return bousai_text(ui, "Now", color, big)

def hero_page(ui, ev, ctx, seg):
    W = canvas.width()
    H = canvas.height()
    lh = ui["line_h"]
    big = ui["big_font"]
    bh = bousai_font_height(ui, big)
    small = ui["small_font"]
    sh = bousai_font_height(ui, small)
    labels = seg["labels"]
    if seg["countdown"]:
        left_label = ["S-wave", "S"]
        left_text = None
        right_label = ["Est.Int", "Est."]
        right_text = ev["local_int"]
    elif ev["assumption"]:
        left_label = ["Source", "Src"]
        left_text = "Assumed"
        right_label = ["Max Int", "Max"]
        right_text = ev["max_int"] or "?"
    else:
        left_label = ["Magnitude", "Mag"]
        left_text = bousai_eew_mag_text(ev["mag"])
        right_label = ["Max Int", "Max"]
        right_text = ev["max_int"] or "?"
    fill = intensity_fill(ui, right_text)

    page = {"kind": "hero", "labels": labels, "value_h": bh, "left_text": left_text}
    if labels:
        badge_w = bousai_text_width(ui, right_text, big) + 4
        rl = fit_text(ui, right_label, W // 2, small)
        rw = max(badge_w, bousai_text_width(ui, rl, small)) + 2
        lw = W - rw
        page["lw"] = lw
        page["label_h"] = sh + 1
        page["label_l"] = bousai_text(ui, fit_text(ui, left_label, lw - 1, small), ui["muted"], small)
        page["label_r"] = bousai_text(ui, rl, ui["muted"], small)
        page["rw"] = rw
        page["right"] = render.Box(width = rw, height = bh, child = render.Box(width = rw - 2, height = bh, color = fill, child = bousai_text(ui, right_text, bousai_on(fill), big)))
        used = lh + sh + 1 + bh
    else:
        # Extra large text: no room for a label row, so the label is stacked over the badge.
        font = ui["font"]
        fh = bousai_font_height(ui, font)
        rl = fit_text(ui, right_label, W // 2, font)
        badge_w = bousai_text_width(ui, right_text, font) + 4
        rw = max(badge_w, bousai_text_width(ui, rl, font)) + 2
        page["lw"] = W - rw
        page["rw"] = rw
        badge = render.Box(width = badge_w, height = bh - fh, color = fill, child = bousai_text(ui, right_text, bousai_on(fill), font))
        page["right"] = render.Column(children = [
            render.Box(width = rw, height = fh, child = bousai_text(ui, rl, ui["muted"], font)),
            render.Box(width = rw, height = bh - fh, child = badge),
        ])
        # Once the S-wave has arrived the label is dropped so "Arrived" fits.
        page["lw_arrived"] = W - badge_w - 2
        page["right_arrived"] = render.Box(width = badge_w + 2, height = bh, child = render.Box(width = badge_w, height = bh, color = fill, child = bousai_text(ui, right_text, bousai_on(fill), font)))
        used = lh + bh

    # Spare rows below the values: epicentre / magnitude ticker lines in the small font.
    line_h = sh + 1
    spare = (H - used) // line_h
    lines = []
    if spare > 0:
        facts = "%s %s  Max %s" % (bousai_eew_mag_text(ev["mag"]), bousai_eew_depth_text(ev["depth_km"]), ev["max_int"] or "?")
        place = "Assumed epicentre (PLUM/level)" if ev["assumption"] else ev["epicenter_en"]
        if ctx["pref"] != None and ctx["pref"] in ev["areas"]:
            place = "Your prefecture is warned. " + place
        if ev["assumption"]:
            facts = "Max Int %s" % (ev["max_int"] or "?")
        texts = [place + "  " + facts] if spare == 1 else [place, facts]
        for t in texts[:spare]:
            lines.append(render.Padding(pad = (1, 0, 0, 0), child = bousai_fit(ui, t, width = W - 1, color = ui["fg"] if len(lines) == 0 else ui["muted"], font = small, frames = seg["page_frames"])))
    page["lines"] = lines
    return page

def hero_body(ui, seg, page, r):
    kids = []
    arrived = seg["countdown"] and r <= 0
    lw = page["lw"]
    right = page["right"]
    if arrived and not page["labels"]:
        lw = page["lw_arrived"]
        right = page["right_arrived"]
    if page["labels"]:
        kids.append(render.Row(children = [
            left_cell(ui, page["label_l"], page["lw"], page["label_h"]),
            left_cell(ui, page["label_r"], page["rw"], page["label_h"]),
        ]))
    if seg["countdown"]:
        left = count_widget(ui, r, lw - 1, seg["band"] if r <= 10 else ui["fg"])
    else:
        text = page["left_text"]
        font = ui["big_font"] if bousai_text_width(ui, text, ui["big_font"]) <= lw - 1 else ui["font"]
        left = bousai_text(ui, text, ui["fg"], font)
    kids.append(render.Row(children = [left_cell(ui, left, lw, page["value_h"]), right]))
    kids.extend(page["lines"])
    return render.Column(children = kids)

# ---------------------------------------------------------------------------
# Detail pages

def info_rows(ui, ev, ctx):
    fg = ui["fg"]
    muted = ui["muted"]
    tz = ctx["tz"]
    rows = []
    if ev["cancel"]:
        rows.append(("The earlier EEW was cancelled", fg))
        if ev["region_code"] != None or ev["lat"] != None:
            rows.append((ev["epicenter_en"], muted))
    else:
        rows.append(("Assumed epicentre" if ev["assumption"] else ev["epicenter_en"], fg))
        if ctx["pref"] != None and ctx["pref"] in ev["areas"]:
            rows.append(("Warning covers your prefecture", bousai_sev_color(ui, 5)))
        if ev["assumption"]:
            rows.append(("PLUM or level method: no epicentre, magnitude or S-wave estimate", muted))
        else:
            rows.append(("%s  %s" % (bousai_eew_mag_text(ev["mag"]), bousai_eew_depth_text(ev["depth_km"])), fg))
        rows.append(("Max Int %s (JMA)" % (ev["max_int"] or "?"), fg))
        if ctx["local_est"]:
            if ev["local_int"] != None:
                rows.append(("Est. here Int %s" % ev["local_int"], fg))
                rows.append(("%dkm %s of you" % (int(ev["dist_km"] + 0.5), bousai_bearing_name(ctx["loc"]["lat"], ctx["loc"]["lon"], ev["lat"], ev["lon"])), muted))
                rows.append(("Est. = unofficial estimate, not a JMA forecast", muted))
            elif ev["dist_km"] != None:
                rows.append(("Est. n/a: %dkm away" % int(ev["dist_km"] + 0.5), muted))
        if ev["areas"]:
            rows.append(("Warned: " + ", ".join([bousai_eew_pref_en(c) for c in ev["areas"]]), fg))
    rows.append(("Report %d%s" % (ev["serial"], " (final)" if ev["final"] and not ev["cancel"] else ""), muted))
    rows.append(("Issued " + clock(ev["announced"], tz), muted))
    if not ev["cancel"] and ev["origin"] != None:
        rows.append(("Origin " + clock(ev["origin"], tz), muted))
    if ctx["demo"]:
        rows.append(("Sample: Noto 2024-01-01 M7.6", muted))
    rows.append((SOURCE_TEXT.get(ev["source"], ev["source"]), muted))
    return rows

# ---------------------------------------------------------------------------
# One alert = one animation: the countdown ticks once per second of the dwell

def frame_widget(ui, seg, page, r, sec):
    right = header_right(ui, seg, page, r, sec)
    on = header_widget(ui, seg, right, True)
    head = on
    if seg["blink"]:
        head = render.Animation(children = [on] * 6 + [header_widget(ui, seg, right, False)] * 3)
    body = hero_body(ui, seg, page, r) if page["kind"] == "hero" else page["body"]
    return render.Box(width = canvas.width(), height = canvas.height(), child = render.Column(expanded = True, main_align = "start", cross_align = "start", children = [head, body]))

def segment(ui, ev, ctx, secs, t0):
    """Animation for one alert lasting `secs` seconds, starting `t0` seconds into the dwell."""
    W = canvas.width()
    H = canvas.height()
    lh = ui["line_h"]
    total = secs * 10
    countdown = ctx["local_est"] and not ev["cancel"] and ev["s_arrival"] != None and ev["local_int"] != None
    r0 = (ev["s_arrival"] - ctx["now"]).seconds if countdown else 0.0
    # With extra large text there is no room for a label row: short titles (WARN) leave the header
    # room for the S-wave label.
    labels = lh + bousai_font_height(ui, ui["small_font"]) + 1 + bousai_font_height(ui, ui["big_font"]) <= H
    title = title_text(ev, not labels)
    seg = {
        "title": title,
        "band": bousai_sev_color(ui, bousai_eew_sev(ev)),
        "blink": ev["warn"] and not ev["cancel"] and ui["contrast"] != "low",
        "countdown": countdown,
        "labels": labels,
        "titles": {},
        "page_frames": total,
    }
    seg["tag"] = serial_tag(ui, ev, ctx["demo"], W - bousai_text_width(ui, title) - 5)

    # Pages: the hero (countdown) gets ~40% of the time (30% with extra large text, which pages
    # more), the rest shares the detail pages; no page stays up less than MIN_PAGE_FRAMES, so a short
    # slot (several alerts) keeps fewer detail rows.
    rows = info_rows(ui, ev, ctx)
    per_page = max(1, (H - lh) // lh)
    hero = 0 if ev["cancel"] else 1
    hero_f = max(MIN_PAGE_FRAMES, total * (2 if labels else 3) // (5 if labels else 10)) if hero else 0
    info_n = min((len(rows) + per_page - 1) // per_page, (total - hero_f) // MIN_PAGE_FRAMES)
    if hero == 0:
        info_n = max(1, info_n)
    if hero and info_n == 0:
        hero_f = total
    info_f = max(1, (total - hero_f) // info_n) if info_n else 1
    seg["page_frames"] = hero_f if hero else info_f

    pages = []
    if hero:
        pages.append(hero_page(ui, ev, ctx, seg))
    seg["page_frames"] = info_f
    for i in range(info_n):
        chunk = rows[i * per_page:(i + 1) * per_page]
        body = render.Column(children = [render.Box(width = W, height = lh, child = text_row(ui, item, info_f)) for item in chunk])
        pages.append({"kind": "info", "body": body})

    built = {}
    frames = []
    for f in range(total):
        s = f // 10
        p = 0 if hero and f < hero_f else hero + min(info_n - 1, (f - hero_f) // info_f)
        key = (p, s if countdown or (p == 0 and hero and not labels) else 0)
        if key not in built:
            built[key] = frame_widget(ui, seg, pages[p], r0 - (t0 + s), s)
        frames.append(built[key])
    return render.Animation(children = frames)

def alerts_card(ui, events, ctx):
    count = min(len(events), 3)
    secs = max(3, bousai_budget_frames() // 10 // count)
    segments = [segment(ui, ev, ctx, secs, i * secs) for i, ev in enumerate(events[:count])]
    return segments[0] if count == 1 else render.Sequence(children = segments)

# ---------------------------------------------------------------------------
# Idle / error card

def inset_rows(ui, rows):
    """(text, color) rows as widgets inset 1 px, so first glyphs are not clipped at x = 0, scrolling within
    their page's share of the dwell time (the pagination bousai_pages uses under a header)."""
    per_page = max(1, (canvas.height() - ui["line_h"]) // ui["line_h"])
    pages = (len(rows) + per_page - 1) // per_page
    frames = bousai_hold_frames(pages) if pages > 1 else bousai_budget_frames()
    return [text_row(ui, row, frames) for row in rows]

def idle_card(ui, data, tz):
    ok = data["ok"]
    checked = clock(data["checked"], tz)
    if not ok["wolfx"] and not ok["kmoni"]:
        # Neither primary source answered (down, or skipped for a while after a stalled request).
        if ok["p2p"]:
            rows = [
                ("No EEW warning", ui["fg"]),
                ("Checked " + checked, ui["muted"]),
                ("Wolfx, NIED unavailable", ui["muted"]),
                ("P2PQuake: warnings only", ui["muted"]),
            ]
        else:
            rows = [
                ("EEW feeds unreachable", ui["fg"]),
                ("Checked " + checked, ui["muted"]),
                ("An alert could be missed", ui["muted"]),
            ]
        return bousai_root(ui, bousai_pages(ui, ("EEW", bousai_sev_color(ui, 2)), inset_rows(ui, rows)))
    rows = [("No EEW active", ui["fg"]), ("Checked " + checked, ui["muted"])]
    last = data["last"]
    if last != None and last["announced"] != None:
        kind = "warning" if last["warn"] else "forecast"
        rows.append(("Last EEW " + bousai_mdhm(last["announced"], tz), ui["muted"]))
        rows.append((last["epicenter_en"], ui["muted"]))
        rows.append(("%s %s Int %s, %s" % (bousai_eew_mag_text(last["mag"]), bousai_eew_depth_text(last["depth_km"]), last["max_int"] or "?", kind), ui["muted"]))
    if not ok["wolfx"]:
        rows.append(("Wolfx feed down, using NIED", ui["muted"]))
    rows.append(("JMA EEW via Wolfx" if ok["wolfx"] else "NIED Kyoshin Monitor", ui["muted"]))
    return bousai_root(ui, bousai_pages(ui, ("EEW", None, bousai_hhmm(data["checked"], tz)), inset_rows(ui, rows)))

def main(config):
    ui = bousai_ui(config)
    loc = bousai_location(config)
    demo = bousai_bool(config, "demo", False)
    level = config.get("min_level") or "all"
    data = bousai_eew_poll(config, demo)
    events = [ev for ev in data["events"] if level_ok(ev, level)]
    if not events:
        if bousai_bool(config, "show_idle", False):
            return idle_card(ui, data, loc["tz"])
        return []

    pref = None
    if any([ev["areas"] for ev in events]):
        area = bousai_area(config)
        if area != None:
            pref = area["pref"]
    ctx = {
        "tz": loc["tz"],
        "loc": loc,
        "demo": demo,
        "local_est": bousai_bool(config, "local_est", True),
        "pref": pref,
        "now": data["checked"],
    }
    return bousai_root(ui, alerts_card(ui, events, ctx))

def get_schema():
    return bousai_schema([
        schema.Dropdown(
            id = "min_level",
            name = "Alerts to show",
            desc = "Which EEW reports take over the display: everything JMA issues (forecasts start at Int 3 or M3.5), forecasts expecting Int 3 or more plus warnings, or warnings only (Int 5- or more).",
            icon = "filter",
            default = "all",
            options = [
                schema.Option(display = "All forecasts and warnings", value = "all"),
                schema.Option(display = "Int 3+ forecasts and warnings", value = "int3"),
                schema.Option(display = "Warnings only", value = "warn"),
            ],
        ),
        schema.Toggle(
            id = "local_est",
            name = "Estimate for my location",
            desc = "Show Est. (an unofficial estimated intensity) and the S-wave arrival countdown for your location. Computed by this app from the JMA hypocentre with published attenuation and travel-time tables; JMA's area forecast is the official information. The countdown starts from the moment the server renders the app.",
            icon = "stopwatch",
            default = True,
        ),
        schema.Toggle(
            id = "show_idle",
            name = "Show when idle",
            desc = "Show a calm status card (last check time and the latest EEW) when no EEW is active. Off: the app hides itself until an EEW arrives, so enable Tronbyt AutoPin.",
            icon = "bell",
            default = False,
        ),
        schema.Toggle(
            id = "demo",
            name = "Show sample alert",
            desc = "Show an embedded sample modelled on the 2024-01-01 Noto Peninsula earthquake warning (M7.4 report), timed so the S-wave countdown for your location is meaningful.",
            icon = "flask",
            default = False,
        ),
    ])
