"""
Applet: Bousai Risk Map
Summary: JMA Kikikuru hazard risk map
Description: JMA risk maps (Kikikuru) for landslide, inundation and flood risk from heavy rain around your location, Lv2 to Lv5 with a text key, optionally with the last hour of change.
Author: Bousai Apps
"""

# bousai: requires core map tiles

load("schema.star", "schema")
load("time.star", "time")

# element id -> (menu text, tile element, title, banner text)
RISK_ELEMENTS = [
    ("land", "Landslide", "land", "Landslide", "No Lv2+"),
    ("inund", "Inundation", "inund", "Inundation", "No Lv2+"),
    ("flood", "Flood (river mesh)", "flood_mesh", "Flood", "No Lv2+"),
]

RISK_HISTORY = [
    ("hour", "Last hour and now"),
    ("now", "Now only"),
]

# Kikikuru colours (new Level 2-5 scheme) with JMA's names and alert-level equivalents, highest first.
RISK_KEY = [
    ("#0c000c", "Lv5 Imminent"),
    ("#aa00aa", "Lv4 Danger"),
    ("#ff2800", "Lv3 Warning"),
    ("#f2e700", "Lv2 Caution"),
]

def risk_element(config):
    key = config.get("element") or "land"
    for e in RISK_ELEMENTS:
        if e[0] == key:
            return e
    return RISK_ELEMENTS[0]

def risk_frames(element, history, tz, now_u):
    """Kikikuru analysis frames: Now, or Now plus the last hour on a 20 minute clock grid."""
    rows = bousai_tiles_entries(bousai_jmatile_times("risk/targetTimes.json", ttl = 120), element)
    if len(rows) == 0:
        return []
    newest = rows[-1]
    t0 = newest["u"]
    picks = []
    if history != "now":
        for e in rows[:-1]:
            age = (t0 - e["u"]) // 60
            if age > 10 and age <= 60 and (e["u"] // 60) % 20 == 0:
                picks.append(e)
    picks.append(newest)
    frames = []
    for e in picks:
        ttl = 180 if e["member"] != "none" else bousai_tiles_ttl(e, now_u)
        frames.append(bousai_tiles_frame("risk", e, element, bousai_tiles_rel(bousai_tiles_minutes(e["u"], t0)), bousai_tiles_clock(e["t"], tz), ttl, 1 if e["u"] == t0 else 0))
    frames[-1]["hold"] = max(frames[-1]["hold"], 2)
    return frames

def risk_status(ui, loc, frames, built):
    """Three rows: data time and whether the tiles show a Lv2 or higher area in the region now."""
    rows = [("Updated " + bousai_tiles_clock(frames[-1]["t"], loc["tz"]), ui["muted"])]
    if bousai_tiles_presence(frames, built["states"])["now"]:
        rows.append(("Lv2+ risk", ui["sev"][2]))
        rows.append(("in your region", ui["fg"]))
    else:
        rows.append(("No Lv2+ risk", ui["fg"]))
        rows.append(("in your region", ui["muted"]))
    return rows

def main(config):
    ui = bousai_ui(config)
    loc = bousai_location(config)
    if not bousai_tiles_covered(loc, "nowc"):
        return bousai_message(ui, "Risk map", ["Outside JMA", "Kikikuru coverage"])
    opts = bousai_tiles_options(config, "prefecture")
    spec = risk_element(config)
    frames = risk_frames(spec[2], config.get("history") or "hour", loc["tz"], time.now().unix)
    if len(frames) == 0:
        return bousai_message(ui, "Risk map", ["No risk map", "from JMA now"])
    built = bousai_tiles_build(ui, loc, bousai_tiles_view(loc, opts), opts, frames, {"zooms": BOUSAI_TILES_PRODUCT_ZOOMS["risk"], "empty": spec[4]})
    if bousai_bool(config, "only_when_active", False) and bousai_tiles_all_blank(built["states"]):
        return []
    key = {"title": spec[3], "unit": "risk", "entries": RISK_KEY} if opts["legend"] else None
    return bousai_tiles_root(ui, opts, built, {"title": spec[3] + " risk", "rows": risk_status(ui, loc, frames, built)}, key)

def get_schema():
    return bousai_tiles_schema([
        schema.Dropdown(
            id = "element",
            name = "Risk type",
            desc = "Which Kikikuru risk map to show: landslide, inundation or flood (JMA's river mesh).",
            icon = "hillRockslide",
            default = "land",
            options = [schema.Option(display = e[1], value = e[0]) for e in RISK_ELEMENTS],
        ),
        schema.Dropdown(
            id = "history",
            name = "Timeline",
            desc = "Show only the latest risk map, or also the last hour in 20 minute steps.",
            icon = "clockRotateLeft",
            default = "hour",
            options = [schema.Option(display = h[1], value = h[0]) for h in RISK_HISTORY],
        ),
        schema.Toggle(id = "only_when_active", name = "Only when active", desc = "Hide this app (so Tronbyt skips it) while the risk map around you shows no Lv2 or higher area. Use AutoPin to bring it forward when a risk appears.", icon = "eyeSlash", default = False),
    ], "prefecture")
