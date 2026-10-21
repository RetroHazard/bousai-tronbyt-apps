"""EEW library for the Bousai suite: JMA Earthquake Early Warning feeds, a local shaking
estimate (Est. intensity and S-wave countdown) and P2PQuake shaking detection.

Sources (public; 1-5 s HTTP TTLs), as a fallback chain:
- Wolfx relay of the raw JMA EEW telegram, https://api.wolfx.jp/jma_eew.json (latest report only): primary.
- NIED Kyoshin Monitor current-EEW JSON, used when Wolfx gives nothing; also its image layers.
- P2PQuake API v2: code 556 (EEW warnings) only as a last resort when neither of the above answers;
  554 (EEW detection chime) and 9611 (evaluation of user "it shook" reports) for shaking detection.
All three are third-party hosts, read through the core crash guard bousai_guarded_get (BOUSAI_EEW_COOLDOWN).

Everything derived here for the configured location (local_int, s_arrival) is an UNOFFICIAL
estimate. JMA's area forecasts are the official information.
"""

# bousai: requires core data

load("cache.star", "cache")
load("encoding/json.star", "json")
load("math.star", "math")
load("time.star", "time")

BOUSAI_EEW_WOLFX = "https://api.wolfx.jp/jma_eew.json"
BOUSAI_EEW_KMONI = "http://www.kmoni.bosai.go.jp"
BOUSAI_EEW_P2P = "https://api.p2pquake.net/v2/history"

# Wolfx, NIED and P2PQuake are third-party hosts that stall now and then, and a request that runs into
# Pixlet's 5 s HTTP timeout aborts the whole render (Starlark cannot catch it). So every request to them
# goes through the core bousai_guarded_get: when an earlier render never finished a request to a host, that
# host is skipped (None) for the cooldown below, in seconds, and the fallback chain moves on to the next
# source. A cooldown must be longer than the usual 60 s render interval, or the marker expires before the
# next render and the stalled host is retried at once.
BOUSAI_EEW_COOLDOWN = {"wolfx": 120, "kmoni": 120, "p2p": 300}

# Fallback chain: Wolfx (primary) -> NIED kmoni (only when Wolfx gave nothing) -> P2PQuake 556 (last resort,
# only when neither answered). NIED asks that EEW source information from the Kyoshin Monitor is not
# redistributed, so kmoni is not a default second source; True polls it on every render (2 more requests).
BOUSAI_EEW_KMONI_ALWAYS = False

# An EEW stays "active" this long after its latest report (seconds). A final report lingers
# less (no more reports follow, waves may still be travelling); a cancellation is shown briefly.
BOUSAI_EEW_ACTIVE_S = 180
BOUSAI_EEW_FINAL_S = 90
BOUSAI_EEW_CANCEL_S = 60

# Average site amplification of PGV relative to Vs30 = 600 m/s ground: ARV = 10^(1.83 - 0.66 log10 AVS30)
# (Matsuoka & Midorikawa 1994) at AVS30 ~ 350 m/s, a nationwide-average site.
BOUSAI_EEW_ARV = 1.4

BOUSAI_EEW_CACHE_KEY = "bousai_eew_seen_v1"

# JMA prefecture names in JMA code order (01 Hokkaido ... 47 Okinawa). EEW warning areas start
# with the prefecture name, e.g. "石川県能登", "北海道道東".
BOUSAI_EEW_PREF_JP = ["北海道", "青森県", "岩手県", "宮城県", "秋田県", "山形県", "福島県", "茨城県", "栃木県", "群馬県", "埼玉県", "千葉県", "東京都", "神奈川県", "新潟県", "富山県", "石川県", "福井県", "山梨県", "長野県", "岐阜県", "静岡県", "愛知県", "三重県", "滋賀県", "京都府", "大阪府", "兵庫県", "奈良県", "和歌山県", "鳥取県", "島根県", "岡山県", "広島県", "山口県", "徳島県", "香川県", "愛媛県", "高知県", "福岡県", "佐賀県", "長崎県", "熊本県", "大分県", "宮崎県", "鹿児島県", "沖縄県"]

# P2PQuake region code (epsp-area.csv, e.g. 230 Saitama North) // 10 -> JMA prefecture number.
BOUSAI_EEW_P2P_PREF = {1: 1, 2: 1, 3: 1, 4: 1, 5: 1, 6: 1, 7: 1, 10: 2, 11: 3, 12: 4, 13: 5, 14: 6, 15: 7, 20: 8, 21: 9, 22: 10, 23: 11, 24: 12, 25: 13, 26: 13, 27: 14, 30: 15, 31: 16, 32: 17, 33: 18, 34: 19, 35: 20, 40: 21, 41: 22, 42: 23, 43: 24, 44: 25, 45: 26, 46: 27, 47: 28, 48: 29, 49: 30, 50: 31, 51: 32, 52: 33, 53: 34, 54: 35, 55: 36, 56: 37, 57: 38, 58: 39, 60: 40, 61: 41, 62: 42, 63: 42, 64: 43, 65: 44, 66: 45, 67: 46, 68: 46, 70: 47, 71: 47}

# P2PQuake "confidence" of a 9611 evaluation -> level 1..4 (0 = not displayed); json_api_v2 spec.
BOUSAI_EEW_P2P_LEVELS = [(1, 0.97015), (2, 0.96774), (3, 0.97024), (4, 0.98052)]

# S-wave travel time (s) from the JMA2001 travel-time table (Ueno et al. 2002; JMA, tjma2001),
# sub-sampled: rows = focal depth (km), columns = epicentral distance (km). Linear interpolation
# stays within 0.5 s of the full table for depths <= 60 km and distances <= 400 km.
BOUSAI_EEW_TT_DEPTH = [0, 10, 20, 30, 40, 60, 80, 100, 150, 200, 300, 400, 500, 600, 700]
BOUSAI_EEW_TT_DIST = [0, 10, 20, 30, 40, 60, 80, 100, 150, 200, 300, 400, 500, 700, 1000, 1500, 2000]
BOUSAI_EEW_TT_S = [
    [0.0, 3.5, 6.7, 9.8, 12.7, 18.5, 24.3, 30.0, 43.9, 56.3, 79.4, 102.0, 124.5, 169.5, 236.7, 346.9, 451.9],
    [3.0, 4.2, 6.7, 9.4, 12.2, 17.9, 23.5, 29.1, 42.4, 54.5, 77.4, 100.0, 122.6, 167.5, 234.7, 344.8, 449.7],
    [5.8, 6.4, 8.1, 10.3, 12.8, 18.0, 23.3, 28.5, 41.2, 53.1, 75.9, 98.5, 121.0, 165.9, 233.1, 343.1, 447.9],
    [8.3, 8.8, 10.0, 11.7, 13.8, 18.4, 23.3, 28.2, 40.3, 51.9, 74.7, 97.3, 119.8, 164.7, 231.9, 341.7, 446.3],
    [10.7, 11.1, 12.0, 13.4, 15.1, 19.1, 23.6, 28.2, 39.8, 51.2, 73.9, 96.5, 118.9, 163.8, 231.0, 340.6, 445.0],
    [15.3, 15.5, 16.1, 17.1, 18.3, 21.5, 25.2, 29.3, 40.0, 51.1, 73.5, 96.0, 118.4, 163.2, 230.3, 339.2, 442.9],
    [19.8, 20.0, 20.4, 21.1, 22.1, 24.7, 27.8, 31.4, 41.3, 52.0, 73.9, 96.1, 118.4, 163.1, 229.6, 337.7, 441.0],
    [24.3, 24.5, 24.8, 25.4, 26.2, 28.3, 31.0, 34.1, 43.2, 53.3, 74.6, 96.5, 118.6, 162.8, 228.9, 336.3, 439.0],
    [35.5, 35.6, 35.8, 36.2, 36.7, 38.1, 40.1, 42.4, 49.7, 58.3, 77.7, 98.4, 119.6, 162.6, 227.3, 333.0, 434.2],
    [46.5, 46.5, 46.7, 47.0, 47.3, 48.4, 49.9, 51.7, 57.6, 65.0, 82.3, 101.5, 121.7, 163.3, 226.3, 330.2, 429.3],
    [67.8, 67.9, 68.0, 68.2, 68.4, 69.1, 70.1, 71.3, 75.4, 80.8, 94.5, 110.7, 128.5, 166.6, 226.1, 325.6, 417.0],
    [88.4, 88.5, 88.5, 88.7, 88.9, 89.4, 90.1, 91.0, 94.0, 98.2, 109.1, 122.7, 138.1, 172.4, 227.7, 321.6, 405.5],
    [108.0, 108.0, 108.1, 108.2, 108.3, 108.7, 109.2, 109.9, 112.3, 115.6, 124.4, 135.8, 149.0, 179.3, 229.7, 315.3, 395.8],
    [126.2, 126.2, 126.2, 126.3, 126.4, 126.7, 127.2, 127.7, 129.6, 132.3, 139.5, 149.0, 160.3, 186.8, 232.1, 311.5, 389.0],
    [143.4, 143.4, 143.4, 143.5, 143.6, 143.8, 144.2, 144.6, 146.2, 148.4, 154.4, 162.4, 172.1, 195.3, 236.2, 310.3, 384.7],
]

# NIED Kyoshin Monitor image layers (352 x 400 px) are an equirectangular map: pixel = A * lon + B,
# pixel_y = C * lat + D, fitted against Natural Earth coastlines (IoU 0.98) and cross-checked
# against the P/S-wave circle centre of the 2024-01-01 Noto earthquake (within 1 px).
BOUSAI_EEW_KMONI_W = 352
BOUSAI_EEW_KMONI_H = 400
BOUSAI_EEW_KMONI_X = (20.258, -2604.984)
BOUSAI_EEW_KMONI_Y = (-24.5517, 1135.033)

# ---------------------------------------------------------------------------
# Parsing helpers

def bousai_eew_num(v, default = None):
    """Number from an int/float or a string such as '37.6' or '10km'; `default` otherwise."""
    t = type(v)
    if t == "int" or t == "float":
        return float(v)
    if t != "string":
        return default
    s = v.strip().replace("km", "")
    body = s[1:] if s.startswith("-") else s
    if body and body.count(".") <= 1 and body.replace(".", "").isdigit():
        return float(s)
    return default

def bousai_eew_flag(v):
    return v == True or v == "true" or v == "True" or v == "1"

def bousai_eew_int_label(v):
    """JMA intensity label ('0'..'7', '5-', '5+', '6-', '6+') from feed text such as '5強', '6+', '5弱以上'."""
    if v == None:
        return None
    s = str(v).strip()
    for junk in ["震度", "程度", "以上", "以下", " "]:
        s = s.replace(junk, "")
    for sep in ["～", "~", "から"]:
        if sep in s:
            s = s.split(sep)[-1]
    return bousai_intensity_norm(s)

def bousai_eew_region_code(text):
    """Epicentre area code (e.g. '190') from a raw JMA EEW telegram, or None."""
    if not text:
        return None
    t = str(text).split()
    for i in range(1, len(t) - 1):
        a, b = t[i], t[i + 1]
        if len(a) == 4 and a[0] == "N" and a[1:].isdigit() and len(b) == 5 and b[0] == "E" and b[1:].isdigit():
            c = t[i - 1]
            if len(c) == 3 and c.isdigit():
                return c
    return None

def bousai_eew_pref_codes(names):
    """JMA prefecture codes ('17') for warning-area names that start with a prefecture name."""
    out = []
    for n in names:
        s = str(n)
        for i in range(47):
            if s.startswith(BOUSAI_EEW_PREF_JP[i]):
                code = ("0" + str(i + 1))[-2:]
                if code not in out:
                    out.append(code)
                break
    return out

def bousai_eew_pref_en(code):
    """Short English prefecture name for a JMA prefecture code ('13' -> 'Tokyo')."""
    return BOUSAI_PREF_EN.get(code, "").replace(" Prefecture", "").replace(" Metropolis", "")

def bousai_eew_blank():
    return {
        "event_id": "",
        "serial": 0,
        "warn": False,
        "final": False,
        "cancel": False,
        "assumption": False,
        "training": False,
        "origin": None,
        "announced": None,
        "lat": None,
        "lon": None,
        "depth_km": None,
        "mag": None,
        "region_code": None,
        "max_int": None,
        "areas": [],
        "source": "",
    }

def bousai_eew_parse_wolfx(d):
    """Wolfx jma_eew.json -> event dict (None when it is not an EEW report)."""
    if type(d) != "dict" or not d.get("EventID"):
        return None
    ev = bousai_eew_blank()
    mag = bousai_eew_num(d.get("Magnitude"))
    if mag == None:
        mag = bousai_eew_num(d.get("Magunitude"))
    title = str(d.get("Title") or "")
    ev["event_id"] = str(d["EventID"])
    ev["serial"] = int(bousai_eew_num(d.get("Serial"), 0))
    ev["warn"] = bousai_eew_flag(d.get("isWarn")) or "警報" in title
    ev["final"] = bousai_eew_flag(d.get("isFinal"))
    ev["cancel"] = bousai_eew_flag(d.get("isCancel"))
    ev["assumption"] = bousai_eew_flag(d.get("isAssumption"))
    ev["training"] = bousai_eew_flag(d.get("isTraining"))
    ev["origin"] = bousai_parse_time(d.get("OriginTime"))
    ev["announced"] = bousai_parse_time(d.get("AnnouncedTime"))
    lat = bousai_eew_num(d.get("Latitude"))
    lon = bousai_eew_num(d.get("Longitude"))
    if ev["cancel"] or (lat == 0 and lon == 0):
        lat, lon = None, None  # cancellations and 0/0 placeholders carry no hypocentre
    ev["lat"] = lat
    ev["lon"] = lon
    ev["depth_km"] = bousai_eew_num(d.get("Depth")) if lat != None else None
    ev["mag"] = mag if lat != None and mag != None and mag > 0 else None
    ev["region_code"] = None if ev["cancel"] else bousai_eew_region_code(d.get("OriginalText"))
    ev["max_int"] = None if ev["cancel"] else bousai_eew_int_label(d.get("MaxIntensity"))
    areas = [a.get("Chiiki") for a in (d.get("WarnArea") or []) if type(a) == "dict"]
    ev["areas"] = bousai_eew_pref_codes([a for a in areas if a])
    ev["source"] = "Wolfx"
    return ev

def bousai_eew_parse_kmoni(d):
    """NIED kmoni hypo/eew JSON -> event dict (None when no EEW is current)."""
    if type(d) != "dict" or not d.get("report_time") or not d.get("report_id"):
        return None
    ev = bousai_eew_blank()
    lat = bousai_eew_num(d.get("latitude"))
    lon = bousai_eew_num(d.get("longitude"))
    code = str(d.get("region_code") or "")
    ev["event_id"] = str(d["report_id"])
    ev["serial"] = int(bousai_eew_num(d.get("report_num"), 0))
    ev["warn"] = d.get("alertflg") == "警報"
    ev["final"] = bousai_eew_flag(d.get("is_final"))
    ev["cancel"] = bousai_eew_flag(d.get("is_cancel"))
    ev["training"] = bousai_eew_flag(d.get("is_training"))
    ev["origin"] = bousai_parse_time(d.get("origin_time"))
    ev["announced"] = bousai_parse_time(d.get("report_time"))
    ev["lat"] = lat
    ev["lon"] = lon
    ev["assumption"] = lat == None or lon == None
    ev["depth_km"] = bousai_eew_num(d.get("depth"))
    ev["mag"] = bousai_eew_num(d.get("magunitude"))
    ev["region_code"] = code if len(code) == 3 and code.isdigit() else None
    ev["max_int"] = bousai_eew_int_label(d.get("calcintensity"))
    ev["source"] = "NIED"
    return ev

def bousai_eew_parse_p2p(e):
    """P2PQuake code 556 entry -> event dict. Every 556 is a warning; no 'final' flag exists."""
    issue = e.get("issue") or {}
    eid = str(issue.get("eventId") or "")
    if not eid:
        return None
    ev = bousai_eew_blank()
    eq = e.get("earthquake") or {}
    hypo = eq.get("hypocenter") or {}
    lat = bousai_eew_num(hypo.get("latitude"))
    lon = bousai_eew_num(hypo.get("longitude"))
    if lat != None and lat < -90:
        lat = None
    if lon != None and lon < -180:
        lon = None
    mag = bousai_eew_num(hypo.get("magnitude"))
    depth = bousai_eew_num(hypo.get("depth"))
    areas = e.get("areas") or []
    top = None
    for a in areas:
        x = bousai_eew_num(a.get("scaleTo"))
        label = bousai_intensity_norm(str(int(x))) if x != None and x >= 0 and x < 99 else None
        if label != None and bousai_intensity_rank(label) > bousai_intensity_rank(top or ""):
            top = label
    ev["event_id"] = eid
    ev["serial"] = int(bousai_eew_num(issue.get("serial"), 0))
    ev["warn"] = True
    ev["cancel"] = bousai_eew_flag(e.get("cancelled"))
    ev["training"] = bousai_eew_flag(e.get("test"))
    ev["announced"] = bousai_parse_time(issue.get("time"))
    ev["origin"] = bousai_parse_time(eq.get("originTime"))
    ev["lat"] = lat
    ev["lon"] = lon
    ev["assumption"] = eq.get("condition") == "仮定震源要素" or lat == None or lon == None
    ev["mag"] = mag if mag != None and mag > 0 else None
    ev["depth_km"] = depth if depth != None and depth >= 0 else None
    ev["max_int"] = top
    ev["areas"] = bousai_eew_pref_codes([a.get("pref") for a in areas if a.get("pref")])
    ev["source"] = "P2PQuake"
    return ev

def bousai_eew_merge(a, b):
    """Merge two reports of one event: the newer serial wins, gaps are filled from the other."""
    first, second = (a, b) if a["serial"] >= b["serial"] else (b, a)
    out = dict(first)
    for k in second:
        if out.get(k) in (None, "", []) and second[k] not in (None, "", []):
            out[k] = second[k]
    out["warn"] = first["warn"] or second["warn"]
    return out

def bousai_eew_add(events, ev):
    """Add ev to the {event_id: event} dict, merging with an earlier report of the same event."""
    eid = ev["event_id"]
    events[eid] = bousai_eew_merge(events[eid], ev) if eid in events else ev

# ---------------------------------------------------------------------------
# Travel time and local estimate

def bousai_eew_bracket(nodes, x):
    """(i, j, f): x lies between nodes[i] and nodes[j] at fraction f; clamped to the ends."""
    n = len(nodes)
    if x <= nodes[0]:
        return 0, 0, 0.0
    if x >= nodes[n - 1]:
        return n - 1, n - 1, 0.0
    for i in range(n - 1):
        if x < nodes[i + 1]:
            return i, i + 1, (x - nodes[i]) / (nodes[i + 1] - nodes[i])
    return n - 1, n - 1, 0.0

def bousai_eew_s_travel(depth_km, epi_km):
    """S-wave travel time in seconds from the JMA2001 table (bilinear). None beyond 2000 km."""
    if epi_km > 2000:
        return None
    i0, i1, fi = bousai_eew_bracket(BOUSAI_EEW_TT_DEPTH, depth_km)
    j0, j1, fj = bousai_eew_bracket(BOUSAI_EEW_TT_DIST, epi_km)
    rows = BOUSAI_EEW_TT_S
    a = rows[i0][j0] * (1 - fj) + rows[i0][j1] * fj
    b = rows[i1][j0] * (1 - fj) + rows[i1][j1] * fj
    return a * (1 - fi) + b * fi

def bousai_eew_estimate(mag, depth_km, epi_km):
    """Estimated JMA instrumental intensity (float) at epicentral distance epi_km.

    PGV on Vs30 = 600 m/s ground from Si & Midorikawa (1999), crustal event, point source:
        log10 PGV = 0.58 Mw + 0.0038 D - 1.29 - log10(X + 0.0028 * 10^(0.5 Mw)) - 0.002 X   [cm/s]
    (X = hypocentral distance in km, D = depth in km; Mj is used for Mw). Multiplied by the
    nationwide-average site amplification BOUSAI_EEW_ARV, then converted with Midorikawa,
    Fujimoto & Muramatsu (1999): I_JMA = 2.68 + 1.72 log10 PGV.
    A point-source estimate: it can read low close to the rupture of great earthquakes, and a
    single average site cannot reflect soft ground. JMA's area forecast is authoritative.
    """
    x = math.sqrt(epi_km * epi_km + depth_km * depth_km)
    log_pgv = 0.58 * mag + 0.0038 * depth_km - 1.29 - math.log(x + 0.0028 * math.pow(10, 0.5 * mag), 10) - 0.002 * x
    log_pgv += math.log(BOUSAI_EEW_ARV, 10)
    return 2.68 + 1.72 * log_pgv

def bousai_eew_latlon_text(lat, lon):
    if lat == None or lon == None:
        return "Unknown"
    return "%s%s %s%s" % (bousai_fixed(abs(lat), 1), "N" if lat >= 0 else "S", bousai_fixed(abs(lon), 1), "E" if lon >= 0 else "W")

def bousai_eew_epicenter_en(ev):
    """English epicentre name from the telegram area code; latitude/longitude text as fallback."""
    code = ev.get("region_code")
    if code and code in BOUSAI_EPICENTER_EN:
        return BOUSAI_EPICENTER_EN[code].replace("\u200b", "").replace("  ", " ")
    if ev.get("lat") != None and ev.get("lon") != None:
        return bousai_eew_latlon_text(ev["lat"], ev["lon"])
    return "Unknown epicentre"

def bousai_eew_localize(ev, loc):
    """Copy of ev with epicenter_en and the estimate for loc {lat, lon}: dist_km, s_travel,
    s_arrival (Pixlet time), est_value (float), local_int (label). Estimate keys stay None for
    assumed (PLUM/level) sources, cancellations, missing source parameters and > 2000 km."""
    out = dict(ev)
    out["epicenter_en"] = bousai_eew_epicenter_en(ev)
    out["dist_km"] = None
    out["s_travel"] = None
    out["s_arrival"] = None
    out["est_value"] = None
    out["local_int"] = None
    mag = ev["mag"]
    if ev["cancel"] or ev["assumption"] or ev["lat"] == None or ev["lon"] == None or mag == None or mag <= 0 or ev["origin"] == None:
        return out
    epi = bousai_distance_km(loc["lat"], loc["lon"], ev["lat"], ev["lon"])
    out["dist_km"] = epi
    if epi > 2000:
        return out
    depth = ev["depth_km"] if ev["depth_km"] != None else 10.0
    travel = bousai_eew_s_travel(depth, epi)
    out["s_travel"] = travel
    out["s_arrival"] = ev["origin"] + time.parse_duration("%dms" % int(travel * 1000))
    out["est_value"] = bousai_eew_estimate(mag, depth, epi)
    out["local_int"] = bousai_intensity_from_value(out["est_value"])
    return out

def bousai_eew_sev(ev):
    """Severity index 0..5 for ui['sev']: warning 5; forecast 2 when JMA expects Int 3+, else 1;
    cancellation 1."""
    if ev["cancel"]:
        return 1
    if ev["warn"]:
        return 5
    rank = bousai_intensity_rank(ev.get("max_int") or "")
    return 2 if rank >= bousai_intensity_rank("3") else 1

def bousai_eew_mag_text(mag):
    return "M" + bousai_fixed(mag, 1) if mag != None and mag > 0 else "M?"

def bousai_eew_depth_text(depth_km):
    if depth_km == None:
        return "D?"
    return "D%dkm" % int(depth_km + 0.5) if depth_km >= 1 else "Shallow"

# ---------------------------------------------------------------------------
# Feed polling

def bousai_eew_fetch(feed, url, ttl):
    """Guarded GET (body bytes, or None) from feed 'wolfx', 'kmoni' or 'p2p'. None also means the host is
    being skipped because an earlier request to it never finished (BOUSAI_EEW_COOLDOWN)."""
    return bousai_guarded_get(url, ttl, None, BOUSAI_EEW_COOLDOWN[feed])

def bousai_eew_fetch_json(feed, url, ttl):
    """bousai_eew_fetch + JSON decode (None on any failure)."""
    return bousai_guarded_json(url, ttl, None, BOUSAI_EEW_COOLDOWN[feed])

def bousai_eew_kmoni_now():
    """(time, 'YYYYMMDDhhmmss') of the newest NIED Kyoshin Monitor observation, or (None, None)."""
    d = bousai_eew_fetch_json("kmoni", BOUSAI_EEW_KMONI + "/webservice/server/pros/latest.json", 1)
    if type(d) != "dict":
        return None, None
    t = bousai_parse_time(d.get("latest_time"))
    if t == None:
        return None, None
    return t, t.in_location(BOUSAI_JST).format("20060102150405")

def bousai_eew_collect():
    """Poll the EEW feeds as a fallback chain that touches as few third-party hosts as possible.

    1. Wolfx (primary): ONE request when idle.
    2. NIED kmoni (latest.json + hypo/eew) only when Wolfx gave nothing usable (host skipped, HTTP error or
       no report), or when BOUSAI_EEW_KMONI_ALWAYS is set.
    3. P2PQuake 556 (warnings only) only as a last resort, when neither Wolfx nor kmoni answered. It is
       never asked to enrich an event a primary source already carries: it is the host seen stalling, and
       a stalled request fails the whole render, which would be exactly while an EEW is live.
    Every request is guarded (bousai_eew_fetch): a host whose previous request never finished is skipped
    for its cooldown, which simply moves the chain on.

    Returns {events: {event_id: event}, ok: {wolfx, kmoni, p2p} (True/False when asked, None when not
    asked), last: newest Wolfx report (even when old) or None}. No filtering by age happens here.
    """
    events = {}
    ok = {"wolfx": False, "kmoni": None, "p2p": None}
    last = None
    now = time.now()

    raw = bousai_eew_fetch_json("wolfx", BOUSAI_EEW_WOLFX, 1)
    if type(raw) == "dict" and raw.get("EventID"):
        ok["wolfx"] = True
        ev = bousai_eew_parse_wolfx(raw)
        if ev != None:
            last = ev
            bousai_eew_add(events, ev)

    if BOUSAI_EEW_KMONI_ALWAYS or not ok["wolfx"]:
        ok["kmoni"] = False
        _, stamp = bousai_eew_kmoni_now()
        if stamp != None:
            k = bousai_eew_fetch_json("kmoni", BOUSAI_EEW_KMONI + "/webservice/hypo/eew/" + stamp + ".json", 1)
            if type(k) == "dict" and (k.get("result") or {}).get("status") == "success":
                ok["kmoni"] = True
                ev = bousai_eew_parse_kmoni(k)
                if ev != None:
                    bousai_eew_add(events, ev)

    if not ok["wolfx"] and not ok["kmoni"]:
        p = bousai_eew_fetch_json("p2p", BOUSAI_EEW_P2P + "?codes=556&limit=30", 2)
        ok["p2p"] = type(p) == "list"
        for e in (p if type(p) == "list" else []):
            if type(e) != "dict":
                continue
            ev = bousai_eew_parse_p2p(e)
            if ev != None and ev["announced"] != None and (now - ev["announced"]).seconds < 600:
                bousai_eew_add(events, ev)
    return {"events": events, "ok": ok, "last": last}

def bousai_eew_window(ev):
    """Seconds after its latest report that ev is still shown."""
    if ev["cancel"]:
        return BOUSAI_EEW_CANCEL_S
    if ev["final"]:
        return BOUSAI_EEW_FINAL_S
    return BOUSAI_EEW_ACTIVE_S

def bousai_eew_pack(ev):
    d = dict(ev)
    d["origin"] = ev["origin"].unix if ev["origin"] != None else None
    d["announced"] = ev["announced"].unix if ev["announced"] != None else None
    return d

def bousai_eew_unpack(d):
    ev = dict(d)
    ev["origin"] = time.from_timestamp(int(d["origin"])) if d.get("origin") else None
    ev["announced"] = time.from_timestamp(int(d["announced"])) if d.get("announced") else None
    return ev

def bousai_eew_remembered():
    """Events seen by earlier renders (a feed only carries its latest report, so a second,
    overlapping EEW would otherwise displace the first). Empty when the cache is not persistent."""
    raw = cache.get(BOUSAI_EEW_CACHE_KEY)
    data = json.decode(raw, default = None) if raw else None
    out = {}
    if type(data) == "list":
        for d in data:
            if type(d) == "dict" and d.get("event_id") and d.get("announced"):
                out[d["event_id"]] = bousai_eew_unpack(d)
    return out

def bousai_eew_active_events(collected, now = None):
    """Events from a bousai_eew_collect() result that are still active, merged with remembered
    ones; training reports dropped; warnings first, then newest first."""
    now = now or time.now()
    merged = bousai_eew_remembered()
    for ev in collected["events"].values():
        bousai_eew_add(merged, ev)
    live = []
    for ev in merged.values():
        if ev["training"] or ev["announced"] == None:
            continue
        age = (now - ev["announced"]).seconds
        if age <= bousai_eew_window(ev):
            live.append(ev)
    if live:
        cache.set(BOUSAI_EEW_CACHE_KEY, json.encode([bousai_eew_pack(e) for e in live]), ttl_seconds = BOUSAI_EEW_ACTIVE_S)
    return sorted(live, key = lambda e: (0 if e["warn"] else 1, -e["announced"].unix))

def bousai_eew_demo_event(loc, now = None):
    """Embedded sample modelled on the 2024-01-01 Noto Peninsula earthquake (EventID 20240101161010,
    JMA warning report no. 30 at +57 s: M7.4, Off the Coast of Noto Peninsula, max Int 7; warned
    prefectures Ishikawa, Toyama, Niigata, Nagano, Fukui). Times are relative to now: the sample is
    placed on its own timeline so the S-wave reaches loc about 9 s from now (an already-past arrival
    when loc is close to Noto; no estimate beyond 2000 km)."""
    now = now or time.now()
    epi = bousai_distance_km(loc["lat"], loc["lon"], 37.6, 137.2)
    elapsed = 60.0
    if epi <= 2000:
        elapsed = max(60.0, bousai_eew_s_travel(10.0, epi) - 9.0)
    origin = now - time.parse_duration("%dms" % int(elapsed * 1000))
    ev = bousai_eew_blank()
    ev["event_id"] = "20240101161010"
    ev["serial"] = 30
    ev["warn"] = True
    ev["origin"] = origin
    ev["announced"] = origin + time.parse_duration("57100ms")
    ev["lat"] = 37.6
    ev["lon"] = 137.2
    ev["depth_km"] = 10.0
    ev["mag"] = 7.4
    ev["region_code"] = "495"
    ev["max_int"] = "7"
    ev["areas"] = ["17", "16", "15", "20", "18"]
    ev["source"] = "Sample"
    return ev

def bousai_eew_poll(config, demo = False):
    """Everything an EEW display needs, for the configured location.

    Returns {events, ok, last, checked, loc}: events = active EEWs as rich dicts (see
    bousai_eew_active for the public subset; extra keys: areas (JMA prefecture codes), dist_km,
    s_travel, est_value, source), ok = feed health (see bousai_eew_collect), last = newest Wolfx report even when
    no longer active (for idle displays), checked = poll time. demo=True returns the embedded
    sample instead of live data.
    """
    loc = bousai_location(config)
    now = time.now()
    if demo:
        sample = bousai_eew_localize(bousai_eew_demo_event(loc, now), loc)
        return {"events": [sample], "ok": {"wolfx": True, "kmoni": None, "p2p": None}, "last": None, "checked": now, "loc": loc}
    got = bousai_eew_collect()
    events = [bousai_eew_localize(ev, loc) for ev in bousai_eew_active_events(got, now)]
    last = bousai_eew_localize(got["last"], loc) if got["last"] != None else None
    return {"events": events, "ok": got["ok"], "last": last, "checked": now, "loc": loc}

def bousai_eew_public(ev):
    """The documented summary shape of one EEW (see bousai_eew_active)."""
    return {
        "event_id": ev["event_id"],
        "serial": ev["serial"],
        "warn": ev["warn"],
        "final": ev["final"],
        "cancel": ev["cancel"],
        "assumption": ev["assumption"],
        "origin": ev["origin"],
        "announced": ev["announced"],
        "lat": ev["lat"],
        "lon": ev["lon"],
        "depth_km": ev["depth_km"],
        "mag": ev["mag"],
        "epicenter_en": ev["epicenter_en"],
        "max_int": ev["max_int"],
        "local_int": ev["local_int"],
        "s_arrival": ev["s_arrival"],
    }

def bousai_eew_active(config):
    """Active Earthquake Early Warnings for the configured location; [] when none (or no feed).

    One dict per EventID, warnings first, then newest report first:
      event_id (str), serial (int report number), warn (bool, Warning rather than Forecast),
      final (bool), cancel (bool; cancellations are listed for 60 s so displays can retract),
      assumption (bool; PLUM / level / assumed hypocentre: lat/lon/mag are placeholders),
      origin, announced (Pixlet times), lat, lon, depth_km, mag (floats or None),
      epicenter_en (English epicentre name, or 'lat lon' text), max_int (JMA max expected intensity
      label '0'..'7','5-','5+','6-','6+' or None), local_int (UNOFFICIAL estimated intensity label at
      the configured location, None when not computable), s_arrival (Pixlet time the S-wave is
      estimated to reach the location, None when not computable).
    A report stays active 180 s (final report 90 s, cancellation 60 s). Training reports are
    ignored. Renders no widgets. bousai_eew_sev(event) maps any of these dicts to the severity
    index 0..5 used with ui["sev"] (cancel 1, warn 5, forecast 1 or 2). The estimate behind
    local_int / s_arrival is documented on bousai_eew_estimate and bousai_eew_s_travel.
    """
    return [bousai_eew_public(ev) for ev in bousai_eew_poll(config)["events"]]

# ---------------------------------------------------------------------------
# Shaking detection (P2PQuake)

def bousai_eew_p2p_level(confidence):
    """P2PQuake 9611 confidence value -> level 1..4 (0 = below the display threshold)."""
    c = bousai_eew_num(confidence, 0.0)
    if c <= 0:
        return 0
    best, gap = 0, 1.0
    for level, v in BOUSAI_EEW_P2P_LEVELS:
        if abs(c - v) < gap:
            best, gap = level, abs(c - v)
    return best

def bousai_eew_shaking():
    """Recent shaking detection from P2PQuake, or None when the feed is unavailable (or its host is being
    skipped after a request that never finished, see BOUSAI_EEW_COOLDOWN).

    Returns {detected (bool), time (Pixlet time of the newest evaluation, None when nothing),
    areas_en (prefecture names, most confident first, up to 6), confidence (str)}.
    detected is True when a 9611 evaluation (user-reported "it shook", confidence level 1-4, newest
    update within 5 min) exists, or when a 554 EEW-warning detection arrived in the last 3 min.
    confidence: 'Lv2/4' for 9611 (P2PQuake level), 'EEW' for a 554 detection, '' when not detected.
    """
    d = bousai_eew_fetch_json("p2p", BOUSAI_EEW_P2P + "?codes=554&codes=9611&limit=30", 5)
    if type(d) != "list":
        return None
    now = time.now()
    best = None
    best_t = None
    chime_t = None
    for e in d:
        if type(e) != "dict":
            continue
        code = e.get("code")
        if code == 554:
            t = bousai_parse_time(e.get("time"))
            if t != None and (now - t).seconds <= 180 and (chime_t == None or t > chime_t):
                chime_t = t
        elif code == 9611 and bousai_eew_p2p_level(e.get("confidence")) > 0:
            t = bousai_parse_time(e.get("updated_at") or e.get("time"))
            if t != None and (now - t).seconds <= 300 and (best_t == None or t > best_t):
                best, best_t = e, t
    if best == None and chime_t == None:
        return {"detected": False, "time": None, "areas_en": [], "confidence": ""}
    areas = []
    confidence = "EEW"
    when = chime_t
    if best != None and (chime_t == None or best_t >= chime_t):
        confidence = "Lv%d/4" % bousai_eew_p2p_level(best.get("confidence"))
        when = best_t
        scored = []
        for code, a in (best.get("area_confidences") or {}).items():
            blk = int(code) // 10 if code.isdigit() else -1
            if blk in BOUSAI_EEW_P2P_PREF:
                scored.append((-(bousai_eew_num((a or {}).get("confidence"), 0.0)), BOUSAI_EEW_P2P_PREF[blk]))
        for _, pref in sorted(scored):
            name = bousai_eew_pref_en(("0" + str(pref))[-2:])
            if name and name not in areas:
                areas.append(name)
    return {"detected": True, "time": when, "areas_en": areas[:6], "confidence": confidence}

# ---------------------------------------------------------------------------
# NIED Kyoshin Monitor images

def bousai_eew_kmoni_xy(lat, lon):
    """Pixel (x, y floats) of lat/lon in the 352 x 400 Kyoshin Monitor images. The map covers
    about 128.6-146.0 E, 29.9-46.2 N (the Okinawa inset uses another transform: not supported)."""
    return BOUSAI_EEW_KMONI_X[0] * lon + BOUSAI_EEW_KMONI_X[1], BOUSAI_EEW_KMONI_Y[0] * lat + BOUSAI_EEW_KMONI_Y[1]

def bousai_eew_kmoni_url(kind, stamp = None):
    """URL of a Kyoshin Monitor image. kind: 'real' (realtime shindo dots), 'est' (EEW estimated
    intensity), 'ps' (EEW P/S-wave circles) take a 'YYYYMMDDhhmmss' stamp; 'base_b' / 'base_w'
    are the dark / white base maps."""
    root = BOUSAI_EEW_KMONI + "/data/map_img/"
    if kind == "base_b":
        return root + "CommonImg/base_map_b.gif"
    if kind == "base_w":
        return root + "CommonImg/base_map_w.gif"
    day = stamp[:8]
    if kind == "real":
        return "%sRealTimeImg/jma_s/%s/%s.jma_s.gif" % (root, day, stamp)
    if kind == "est":
        return "%sEstShindoImg/eew/%s/%s.eew.gif" % (root, day, stamp)
    return "%sPSWaveImg/eew/%s/%s.eew.gif" % (root, day, stamp)

def bousai_eew_kmoni_stamp(t, back = 0):
    """'YYYYMMDDhhmmss' (JST) of time t shifted `back` seconds into the past."""
    if back:
        t = t - time.parse_duration("%ds" % back)
    return t.in_location(BOUSAI_JST).format("20060102150405")
