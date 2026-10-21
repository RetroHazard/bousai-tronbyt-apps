"""
Applet: Bousai Rain Radar
Summary: JMA rain radar and outlook
Description: Animated JMA rain radar around your location: the last hour observed, a one-hour nowcast and an hourly outlook up to 15 hours ahead, with a text key and the nearest AMeDAS rain readings.
Author: Bousai Apps
"""

# bousai: requires core map tiles

load("schema.star", "schema")
load("time.star", "time")

RADAR_MODES = [
    ("full", "Past hour, next hour, 15 h outlook"),
    ("nowcast", "Past hour and next hour (10 min)"),
    ("hourly", "Now and the next 6 hours (hourly)"),
]

# Tile colours of JMA's rain radar and rain forecast, strongest first (legend of the JMA nowcast page).
RADAR_KEY = [
    ("#b40068", "80+"),
    ("#ff2800", "50-80"),
    ("#ff9900", "30-50"),
    ("#faf500", "20-30"),
    ("#0041ff", "10-20"),
    ("#218cff", "5-10"),
    ("#a0d2ff", "1-5"),
    ("#f2f2ff", "<1"),
]

def radar_frame(kind, entry, element, t0, tz, now_u, hours = None):
    """Frame for one index row: relative label (or +Nh for the hourly outlook) and the local clock time."""
    label = bousai_tiles_rel(bousai_tiles_minutes(entry["u"], t0)) if hours == None else "+%dh" % hours
    return bousai_tiles_frame(kind, entry, element, label, bousai_tiles_clock(entry["t"], tz), bousai_tiles_ttl(entry, now_u))

def radar_frames(mode, tz, now_u):
    """Frames, oldest first: observed radar (N1), one-hour nowcast (N2), then the hourly rain forecast (rasrf).

    Observed frames sit on a 20 / 10 minute clock grid so their tile URLs repeat between renders and stay cached.
    """
    obs = bousai_tiles_entries(bousai_jmatile_times("nowc/targetTimes_N1.json", ttl = 60), "hrpns")
    if len(obs) == 0:
        return []
    newest = obs[-1]
    t0 = newest["u"]
    step = 10 if mode == "nowcast" else 20
    frames = []
    if mode != "hourly":
        for e in obs[:-1]:
            age = (t0 - e["u"]) // 60
            if age > step // 2 and age <= 60 and (e["u"] // 60) % step == 0:
                frames.append(radar_frame("nowc", e, "hrpns", t0, tz, now_u))
    now_frame = radar_frame("nowc", newest, "hrpns", t0, tz, now_u)
    now_frame["hold"] = 1
    frames.append(now_frame)
    if mode != "hourly":
        n2 = bousai_tiles_entries(bousai_jmatile_times("nowc/targetTimes_N2.json", ttl = 60), "hrpns")
        ahead = [e for e in n2 if e["u"] > t0]
        offsets = [10, 20, 30, 40, 50, 60] if mode == "nowcast" else [20, 40, 60]
        for pair in bousai_tiles_pick(ahead, t0, offsets, 6):
            frames.append(radar_frame("nowc", pair[0], "hrpns", t0, tz, now_u))
    if mode != "nowcast":
        rain = bousai_tiles_entries(bousai_jmatile_times("rasrf/targetTimes.json", ttl = 300), "rasrf")
        later = [e for e in rain if e["u"] > t0 + 1200]
        hours = [3, 6, 9, 12, 15] if mode == "full" else [1, 2, 3, 4, 5, 6]
        for pair in bousai_tiles_pick(later, t0, [h * 60 for h in hours], 40):
            frames.append(radar_frame("rasrf", pair[0], "rasrf", t0, tz, now_u, hours = pair[1] // 60))
    frames[-1]["hold"] = max(frames[-1]["hold"], 2)
    return frames

def radar_rate(mm):
    """'0.5mm/10m' reading text."""
    return "%smm/10m" % bousai_fixed(mm, 1)

def radar_status(ui, loc):
    """Status rows from AMeDAS 10-minute rain readings (real numbers, so the radar is readable without colour)."""
    snap = bousai_tiles_amedas_near(loc["lat"], loc["lon"], 40.0)
    if snap == None:
        return [("AMeDAS offline", ui["muted"]), ("No rain readings", ui["muted"])]
    seen = [s for s in snap["stations"] if s["p10"] != None]
    rows = [("AMeDAS " + bousai_tiles_clock(snap["time"], loc["tz"]), ui["muted"])]
    if len(seen) == 0:
        rows.append(("No gauge in 40km", ui["fg"]))
        return rows
    near = [s for s in seen if s["km"] <= 30]
    wet = [s for s in near if s["p10"] > 0]
    first = seen[0]
    if len(wet) > 0:
        heavy = sorted(wet, key = lambda s: -s["p10"])[0]
        rows.append(("Rain nearby", ui["accent"]))
        rows.append(("%d/%d gauges wet" % (len(wet), len(near)), ui["fg"]))
        rows.append(("Max " + radar_rate(heavy["p10"]), ui["fg"]))
        rows.append((bousai_tiles_place(heavy), ui["muted"]))
        rows.append(("%s %dkm %smm" % (first["name"], int(first["km"] + 0.5), bousai_fixed(first["p10"], 1)), ui["muted"]))
    else:
        rows.append(("No rain nearby", ui["fg"]))
        rows.append(("%d gauges <30km" % len(near), ui["muted"]))
        rows.append((bousai_tiles_place(first), ui["muted"]))
        rows.append((radar_rate(first["p10"]), ui["fg"]))
        if first["p1h"] != None:
            rows.append(("%smm/1h" % bousai_fixed(first["p1h"], 1), ui["fg"]))
    return rows

def main(config):
    ui = bousai_ui(config)
    loc = bousai_location(config)
    if not bousai_tiles_covered(loc, "nowc"):
        return bousai_message(ui, "Rain radar", ["Outside JMA", "radar coverage"])
    opts = bousai_tiles_options(config, "prefecture")
    frames = radar_frames(config.get("mode") or "full", loc["tz"], time.now().unix)
    if len(frames) == 0:
        return bousai_message(ui, "Rain radar", ["No radar data", "from JMA now"])
    built = bousai_tiles_build(ui, loc, bousai_tiles_view(loc, opts), opts, frames, {"zooms": BOUSAI_TILES_PRODUCT_ZOOMS["hrpns"], "empty": "No rain"})
    key = {"title": "Rain", "unit": "mm/h", "entries": RADAR_KEY} if opts["legend"] else None
    return bousai_tiles_root(ui, opts, built, {"title": "Rain gauges", "rows": radar_status(ui, loc)}, key)

def get_schema():
    return bousai_tiles_schema([
        schema.Dropdown(
            id = "mode",
            name = "Timeline",
            desc = "Which part of the rain timeline to animate: observed radar, the one-hour nowcast and the hourly forecast.",
            icon = "clockRotateLeft",
            default = "full",
            options = [schema.Option(display = m[1], value = m[0]) for m in RADAR_MODES],
        ),
    ], "prefecture")
