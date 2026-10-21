"""
Applet: Bousai Tornado Watch
Summary: JMA tornado probability nowcast
Description: JMA Tornado Nowcast around your location: tornado probability levels 1 and 2 on a 10 km grid for the last 30 minutes and the next hour, with a text key that gives JMA's hit rates.
Author: Bousai Apps
"""

# bousai: requires core map tiles

load("schema.star", "schema")
load("time.star", "time")

# Probability levels of JMA's Tornado Nowcast with the hit rates JMA publishes for them (strongest first).
TORNADO_KEY = [
    ("#ff2800", "2 7-14% hit"),
    ("#faf500", "1 1-7% hit"),
]

def tornado_status(ui, loc, frames, built, t0):
    """Three rows: analysis time and what the tiles say about the region now and ahead."""
    rows = [("Analysis " + bousai_tiles_clock(time.from_timestamp(t0), loc["tz"]), ui["muted"])]
    seen = bousai_tiles_presence(frames, built["states"])
    if seen["now"]:
        rows.append(("Risk now", ui["sev"][2]))
        rows.append(("in your region", ui["fg"]))
    elif seen["ahead"] != None:
        rows.append(("Risk expected", ui["sev"][2]))
        rows.append(("from " + seen["ahead"], ui["fg"]))
    elif seen["any"]:
        rows.append(("Risk was earlier", ui["fg"]))
        rows.append(("none now or ahead", ui["muted"]))
    else:
        rows.append(("No tornado risk", ui["fg"]))
        rows.append(("in region, 1 hour", ui["muted"]))
    return rows

def main(config):
    ui = bousai_ui(config)
    loc = bousai_location(config)
    if not bousai_tiles_covered(loc, "nowc"):
        return bousai_message(ui, "Tornado", ["Outside JMA", "nowcast coverage"])
    opts = bousai_tiles_options(config, "prefecture")
    axis = bousai_tiles_nowc3_frames("trns", loc["tz"], time.now().unix)
    if axis == None:
        return bousai_message(ui, "Tornado", ["No tornado data", "from JMA now"])
    built = bousai_tiles_build(ui, loc, bousai_tiles_view(loc, opts), opts, axis["frames"], {"zooms": BOUSAI_TILES_PRODUCT_ZOOMS["trns"], "empty": "No tornado"})
    if bousai_bool(config, "only_when_active", False) and bousai_tiles_all_blank(built["states"]):
        return []
    status = {"title": "Tornado", "rows": tornado_status(ui, loc, axis["frames"], built, axis["t0"])}
    key = {"title": "Tornado", "unit": "level", "entries": TORNADO_KEY} if opts["legend"] else None
    return bousai_tiles_root(ui, opts, built, status, key)

def get_schema():
    return bousai_tiles_schema([
        schema.Toggle(id = "only_when_active", name = "Only when active", desc = "Hide this app (so Tronbyt skips it) while the tornado nowcast map around you is empty. Use AutoPin to bring it forward when a risk appears.", icon = "eyeSlash", default = False),
    ], "prefecture")
