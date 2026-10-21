"""
Applet: Bousai Lightning
Summary: JMA thunder nowcast and strikes
Description: JMA Thunder Nowcast around your location: lightning activity levels 1 to 4 for the last 30 minutes and the next hour, with LIDEN lightning strikes (cloud-to-ground and cloud-to-cloud) counted as text.
Author: Bousai Apps
"""

# bousai: requires core map tiles

load("encoding/json.star", "json")
load("http.star", "http")
load("schema.star", "schema")
load("time.star", "time")

# Thunder activity levels as defined in JMA's table for the Thunder Nowcast, strongest first.
LIGHTNING_KEY = [
    ("#c800ff", "4 Violent"),
    ("#ff2800", "3 Strong"),
    ("#ffaa00", "2 Thunder"),
    ("#faf500", "1 Possible"),
    ("", "CG to ground", "cg"),
    ("", "CC to cloud", "cc"),
]

LIGHTNING_RADIUS_KM = 50
LIGHTNING_PARSE_BYTES = 2500000

def lightning_files(index, t0):
    """LIDEN 5-minute file rows that cover the analysis frames (the 35 minutes up to Now)."""
    return [e for e in bousai_tiles_entries(index, "liden") if e["u"] <= t0 and e["u"] >= t0 - 2100]

def lightning_strikes(files, loc, now_u):
    """LIDEN strikes near the location per 5-minute file: {valid unix: [(lat, lon, is_cg, obs time string)]}.

    Files are read newest first within a byte budget so a violent storm day cannot slow the render.
    """
    out = {}
    spent = 0
    for e in sorted(files, key = lambda r: -r["u"]):
        url = BOUSAI_JMATILE + "/nowc/%s/none/%s/surf/liden/data.geojson" % (e["valid"], e["valid"])
        resp = http.get(url, headers = BOUSAI_UA, ttl_seconds = 120 if now_u - e["u"] < 1200 else 3600)
        if resp.status_code != 200:
            continue
        body = resp.body()
        spent += len(body)
        if spent > LIGHTNING_PARSE_BYTES:
            break
        data = json.decode(body, default = None)
        if type(data) != "dict":
            continue
        rows = []
        for f in data.get("features") or []:
            c = (f.get("geometry") or {}).get("coordinates") or []
            if len(c) < 2 or abs(c[1] - loc["lat"]) > 1.3 or abs(c[0] - loc["lon"]) > 1.6:
                continue
            p = f.get("properties") or {}
            rows.append((c[1], c[0], p.get("type") == 4, p.get("obstimeJST")))
        out[e["u"]] = rows
    return out

def lightning_window(strikes, u):
    """Strikes of the two 5-minute files that end at or just before u (the 10 minutes up to that frame)."""
    rows = []
    for k in [u, u - 300]:
        rows.extend(strikes.get(k) or [])
    return rows

def lightning_status(ui, loc, strikes, newest, now_u):
    """Text rows from LIDEN counts and distances within 50 km over the latest 10 minutes."""
    if len(strikes) == 0:
        return [("LIDEN offline", ui["muted"]), ("No strike data", ui["muted"])]
    rows = [("LIDEN " + bousai_tiles_clock(time.from_timestamp(newest), loc["tz"]), ui["muted"])]
    cg = 0
    cc = 0
    best = None
    for s in lightning_window(strikes, newest):
        km = bousai_distance_km(loc["lat"], loc["lon"], s[0], s[1])
        if km > LIGHTNING_RADIUS_KM:
            continue
        if s[2]:
            cg += 1
        else:
            cc += 1
        if best == None or km < best[0]:
            best = (km, s)
    if best == None:
        rows.append(("No strikes", ui["fg"]))
        rows.append(("<%dkm, 10 min" % LIGHTNING_RADIUS_KM, ui["muted"]))
        return rows
    km, s = best
    rows.append(("Strikes nearby", ui["accent"]))
    rows.append(("CG %d CC %d" % (cg, cc), ui["fg"]))
    rows.append(("Nearest %dkm %s" % (int(km + 0.5), bousai_bearing_name(loc["lat"], loc["lon"], s[0], s[1])), ui["fg"]))
    seen = bousai_parse_time(s[3])
    if seen != None:
        rows.append(("%s %s ago" % ("CG" if s[2] else "CC", bousai_ago(seen, time.from_timestamp(now_u))), ui["muted"]))
    return rows

def main(config):
    ui = bousai_ui(config)
    loc = bousai_location(config)
    if not bousai_tiles_covered(loc, "nowc"):
        return bousai_message(ui, "Lightning", ["Outside JMA", "thunder coverage"])
    opts = bousai_tiles_options(config, "prefecture")
    now_u = time.now().unix
    axis = bousai_tiles_nowc3_frames("thns", loc["tz"], now_u)
    if axis == None:
        return bousai_message(ui, "Lightning", ["No thunder data", "from JMA now"])
    view = bousai_tiles_view(loc, opts)
    use_strikes = bousai_bool(config, "strikes", True)
    strikes = lightning_strikes(lightning_files(axis["index"], axis["t0"]), loc, now_u) if use_strikes else {}
    marks = 0
    for f in axis["frames"]:
        if f["ana"] and len(strikes) > 0:
            f["extra"] = bousai_tiles_strike_marks(ui, view, lightning_window(strikes, f["u"]))
            marks += len(f["extra"])
            f["quiet"] = len(f["extra"]) > 0
    built = bousai_tiles_build(ui, loc, view, opts, axis["frames"], {"zooms": BOUSAI_TILES_PRODUCT_ZOOMS["thns"], "empty": "No thunder"})
    if bousai_bool(config, "only_when_active", False) and marks == 0 and bousai_tiles_all_blank(built["states"]):
        return []
    status = None
    if use_strikes:
        newest = max(strikes.keys()) if len(strikes) > 0 else axis["t0"]
        status = {"title": "Strikes", "rows": lightning_status(ui, loc, strikes, newest, now_u)}
    key = {"title": "Thunder", "unit": "level", "entries": LIGHTNING_KEY} if opts["legend"] else None
    return bousai_tiles_root(ui, opts, built, status, key)

def get_schema():
    return bousai_tiles_schema([
        schema.Toggle(id = "strikes", name = "Show LIDEN strikes", desc = "Mark cloud-to-ground (square) and cloud-to-cloud (cross) lightning detected in the last 10 minutes and count them as text.", icon = "cloudBolt", default = True),
        schema.Toggle(id = "only_when_active", name = "Only when active", desc = "Hide this app (so Tronbyt skips it) while no thunder activity or strike is on the map around you. Use AutoPin to bring it forward when thunder appears.", icon = "eyeSlash", default = False),
    ], "prefecture")
