"""
Applet: Bousai Quake
Summary: Japan earthquake information
Description: Latest earthquakes in Japan from the Japan Meteorological Agency: maximum seismic intensity, magnitude, depth, epicenter, a map with your location, the shaking reported where you are, JMA's tsunami comment, the estimated intensity distribution of strong quakes, and Nankai Trough or Hokkaido-Sanriku special information.
Author: Bousai Apps
"""

# bousai: requires core map data mapdata quake

load("encoding/base64.star", "base64")
load("filter.star", "filter")
load("render.star", "canvas", "render")
load("schema.star", "schema")
load("time.star", "time")

QUAKE_MAX_PAGES = 6

# Sample: the 2024-01-01 Noto Peninsula earthquake (M7.6, Int 7), JMA report of 16:24 JST.
# Municipality intensities come from JMA's multilingual sample feed (VXSE53); the estimated
# intensity distribution is JMA's published 250 m mesh map, downsampled to a 91x87 PNG.
QUAKE_DEMO_TSUNAMI = "Tsunami warning/advisory in effect"
QUAKE_DEMO_EST_BOUNDS = (34.0, 134.0, 39.3333, 141.0)
QUAKE_DEMO_EST = "iVBORw0KGgoAAAANSUhEUgAAAFsAAABXCAMAAABcKsnQAAAAeFBMVEX865z+2hT/8Ab55ZXxIgT////85U/55ZX/ogH+4Af/nwD75G3tIgb3IQH/3QauARLiHgr/f3//rgH+YAC/v3//fwD+YgD/v3//qqr75mr75WKuAx2nACT/oQAAAAD55ZT+5Qb55pT55ZX55ZT55ZX55ZX//3/75XH8Q8IGAAAAKHRSTlMH9w1u8gH7r/ZdFxKaF6McWgKO/wQIqAQDWLpP/18A/f0UL0uQzQL9ToZkmwAAA3xJREFUeNrtmNmWoyAQhgtwzdJZeu+ZiVAsvv8bDqBGzNKdKF7MnHAT4zGflb9+qgA4zDfgwX6wL7EQZmOjkrOx33E2NubzxY34L/rkZT62ED0SYrPN8ZKZuGyT+g9l0wlsuibL0HBtqPBhw5bT2eVTyMaj3kgns0teDrxNTWpZqYjgE8o5Db7mTGslXLmKwCac0GVvjcoNjSkEXhzLpjUh/MiWVTuUrthk9rJ84qS7/LIhd/TciUKnaVJy/ukvFhnhWXVE359Luju98USa4J6KgvO6jxqm55K2f7ssLJu0ZK3RRKxVX5yQupMkBwHx2JSEYldKmN3d7MW1jJKCVMFgdFzcm+36fHKesFGwEezNKklWp//GKhJ4RCs0COZO9nq9TZJkuzm5/Yf05EpTOIyoJ+vEj+3w7mtpwybHTKpx/XLl0auh3As76R28C1uMYjdhnyRysbdae7VdKdG5NGYMe/M7STa/Bv4o7XzkGenUZrC0/VLACPYqeVttB8WE88LKwbO6mZMaRq99nP1WQdBODKuIC7v2savx66rFc/L81jV3VXPPJoH9cNDs72Q/F/umfDhg5rKY1cFM95WVHsQYti2kr75Yt7CMN97TziFapma8JqVVYL92TbI6whstXOd9Ty/IcSt74fJWFPv9oCxVirnfpt9gbmCXzm7EjUE5dR3XlVQQ49ff1E9Am70ssEZgO5Qwlm27bmO6ugq8wW7J04/PlHXmo+6xzHXGTugp7EXRRd2vQASDm8r+Dw9RWzdqJ8oxbOntBmYyu2z7eN0r3btCwgS2KEnW6VwHbNrsmGBK3J/h2qOTxL2zyWM6gS2yc7ZvXZdNgnAHW1XhZPGdq+0CICf6BFSfQqWUXUgKkMrrIXKYpolRDmqjZSzX1tZSoPSz5uYV0/WnlmiZjEkbboogsdJSV+GWY5K/0+4BV/Egr2Re4SznECkqIUQah23OkiXM4RCHDVKcvy4OWxgwEzcscHli0R26MzkWiy0Gxzi7g0Cl6BRR4Lt9HlM31+q7PQiYXjqbi8A2hxfXcoWMf4a3dLOlKUyYIkRlA+qmlNoiKGCM6NfZMs+bJZPUWkuGkdiNGwW2hy/SBs4kRIrbzkg6KCdSxYp7uAV1r2IiUi4RxO6sbqVR2Ci73dzHMXAayScoJEY5p4UrrUzMw27q4HzsKOPBfrD/Z/ZfipaAsnZkdawAAAAASUVORK5CYII="
QUAKE_DEMO_MUNI = "7:17384;6+:17202,17204,17205,17461;6-:15202,17407,17463;5+:15103,15106,15107,15108,15204,15205,15211,15213,15216,15217,15222,15224,15226,15385,15504,16201,16202,16205,16209,16210,16211,16321,17201,17203,17206,17207,17209,17211,17386,18208;5-:15102,15104,15105,15208,15209,15210,15218,15223,15405,16206,16207,16208,16322,16323,16343,17210,17365,18201,18210,20201,20583,20602,21203,21217;4:06202,06203,06204,06208,06213,06302,06322,06401,06403,06426,07203,07208,07303,07367,07368,07405,07408,07421,07422,07423,07445,07447,09213,10206,11210,11232,15206,15212,15225,15227,15307,15342,15361,15461,15482,15581,16204,16342,17212,17324,18202,18204,18205,18206,18207,18209,18322,18423,18481,18483,18501,20202,20203,20206,20208,20211,20212,20213,20217,20218,20321,20323,20324,20432,20446,20485,20486,20541,20562,20563,20588,20590,21202,21206,21216,21219,21220,21221,21382,21604,22216,23101,23108,23109,23111,23112,23205,23211,23225,23232,23233,23235,23236,23427,23446,24205,24303,25202,25203,25204,25210,25211,25212,25213,25383,25384,27104,27113,27123,27203,27218,27220,27223,28209,29203,29361,31201;3:03322,04101,04202,04206,04208,04211,04212,04213,04215,04301,04321,04324,04341,04361,04362,04444,04445,04501,04505,05201,05202,05203,05204,05206,05207,05210,05211,05212,05214,05366,05463,05464,06205,06206,06207,06210,06211,06212,06301,06323,06324,06341,06362,06363,06365,06366,06367,06381,06402,06428,06461,07201,07202,07204,07205,07207,07212,07213,07322,07342,07362,07364,07402,07407,07444,07446,07464,07466,07541,07542,07543,07547,08201,08203,08204,08205,08210,08211,08214,08215,08216,08217,08220,08221,08223,08225,08226,08227,08228,08229,08230,08232,08233,08234,08235,08310,08341,08442,08447,08521,08542,08546,09201,09203,09205,09206,09208,09209,09210,09211,09214,09215,09216,09301,09344,09345,09364,09384,09386,09407,09411,10201,10202,10203,10204,10205,10207,10208,10209,10210,10211,10344,10345,10421,10425,10426,10428,10429,10443,10448,10449,10464,10521,10522,10523,10524,10525,11101,11103,11104,11105,11106,11107,11108,11109,11110,11202,11203,11206,11208,11211,11214,11216,11217,11219,11229,11231,11233,11235,11237,11238,11240,11241,11243,11246,11301,11346,11381,11383,11385,11442,11464,11465,12207,12208,12220,12227,12236,12342,12463,13107,13108,13111,13116,13118,13119,13121,13123,14103,14104,14109,14110,14131,14136,14203,14205,14206,14321,14342,14361,14362,15586,18382,18404,18442,19201,19208,19209,19210,19211,19214,19346,19368,19384,19424,19425,20204,20205,20207,20209,20210,20215,20219,20220,20305,20349,20350,20361,20362,20363,20382,20383,20384,20385,20388,20402,20403,20404,20407,20409,20410,20411,20414,20423,20429,20448,20450,20451,20452,20481,20482,20521,20561,21201,21204,21205,21208,21209,21210,21211,21212,21213,21214,21215,21218,21302,21303,21341,21361,21362,21381,21383,21401,21403,21404,21421,21502,21503,21506,21521,22131,22132,22133,22134,22135,22136,22137,22203,22207,22210,22211,22213,22215,22221,22224,22226,23103,23104,23105,23106,23107,23110,23113,23114,23115,23116,23201,23202,23203,23212,23213,23214,23216,23220,23221,23222,23224,23229,23231,23441,23561,24201,24202,24203,24204,24207,24210,24216,24324,24341,24343,24344,24543,25201,25206,25207,25209,25214,25425,25441,25442,25443,26102,26103,26104,26105,26106,26107,26108,26109,26110,26111,26201,26202,26204,26205,26206,26207,26208,26210,26211,26212,26213,26214,26303,26322,26366,26367,26463,26465,27103,27106,27107,27109,27114,27115,27116,27119,27120,27121,27122,27124,27126,27127,27128,27141,27142,27143,27147,27202,27204,27205,27206,27207,27209,27210,27211,27212,27213,27214,27215,27216,27217,27222,27224,27225,27226,27227,27228,27229,27230,27231,27301,27341,27361,27362,27381,28101,28102,28106,28110,28111,28202,28203,28204,28206,28210,28214,28215,28217,28219,28223,28224,28226,28228,28381,28382,28585,29201,29202,29204,29205,29208,29210,29211,29212,29344,29345,29362,29363,29424,29426,29427,30201,30208,30209,30381,31202,31204,31370,32203,33104,33213,33214,36201;2:02201,02202,02204,02205,02206,02209,02210,02304,02323,02361,02367,02384,02402,02405,02408,02412,02442,02443,03201,03205,03206,03209,03213,03214,03215,03216,03301,03321,03366,03381,03402,03485,03503,04102,04103,04104,04105,04207,04214,04216,04302,04322,04323,04401,04406,04421,04422,04424,05209,05213,05215,05327,05346,05348,05349,05361,05368,05434,06201,06361,07209,07210,07211,07214,07308,07344,07461,07481,07482,07483,07501,07502,07503,07504,07505,07522,07544,07545,07561,08202,08208,08212,08222,08364,08564,09204,09342,09343,10212,10367,10382,10383,10384,10424,11102,11201,11207,11209,11212,11215,11218,11222,11225,11227,11230,11239,11242,11245,11324,11326,11341,11342,11343,11347,11348,11361,11362,11365,12101,12102,12103,12104,12105,12106,12204,12205,12206,12210,12211,12212,12213,12215,12216,12217,12219,12221,12222,12223,12224,12225,12226,12228,12229,12230,12231,12232,12233,12234,12235,12237,12238,12239,12322,12329,12347,12349,12403,12409,12410,12421,12422,12423,12424,12426,12427,12441,13101,13102,13103,13104,13105,13106,13109,13110,13112,13113,13114,13115,13117,13120,13122,13201,13202,13203,13204,13206,13207,13208,13209,13210,13211,13212,13213,13214,13215,13218,13219,13220,13222,13223,13224,13225,13227,13228,13229,13303,13363,13364,14101,14102,14105,14106,14107,14108,14112,14113,14114,14115,14116,14117,14118,14132,14133,14134,14135,14137,14151,14153,14201,14204,14207,14208,14210,14211,14212,14213,14214,14215,14216,14217,14301,14341,14363,14364,14383,14384,14402,19202,19205,19206,19207,19212,19213,19364,19365,19366,19423,19429,19430,19442,20303,20304,20306,20307,20386,20412,20413,20415,20416,20417,21207,21501,21504,21505,21507,22101,22102,22103,22206,22209,22212,22214,22220,22223,22225,22302,22304,22305,22306,22325,22342,22344,22424,22429,22461,23207,23445,24208,24209,24211,24212,24215,24441,24442,24443,24461,24471,24472,24561,24562,26203,26364,26365,26407,27232,27321,27322,27366,27382,28105,28107,28109,28201,28205,28208,28212,28213,28218,28220,28221,28222,28225,28227,28229,28301,28365,28443,28446,28464,28481,28586,29206,29209,29322,29342,29343,29385,29386,29401,29425,29441,29442,29446,29450,30203,30204,30205,30206,30207,30341,30361,30382,30383,30391,30392,30401,30404,30406,30422,30424,30427,30428,31302,31328,31329,31371,31372,31384,31386,31390,32201,32528,33101,33102,33103,33202,33205,33212,33216,33346,33423,33445,34103,34202,34203,34207,34215,34302,34304,36202,36203,36204,36205,36206,36207,36208,36341,36401,36402,36403,36404,36405,36489,37201,37202,37203,37205,37206,37207,37208,37324,37404,37406,38201,38202,38206,38210,38213,38356,38401,39201,39203,39302,41201,41210,41425,43214,44201,45209,46201;1:01109,01202,01206,01332,01333,01334,02203,02208,02303,02307,02321,02362,02387,02423,02424,02426,02441,02445,03202,03203,03207,03208,03211,03302,03303,04205,04209,04404,05303,07548,07564,11327,11349,11363,11369,11408,12202,12218,12443,13205,13307,13361,13362,13381,14152,14401,19204,19443,22205,22208,22219,22222,22301,24470,28442,28501,29207,29443,29444,29447,29451,29452,30202,30304,30343,30344,30366,30390,31203,31325,31364,31389,31401,31402,32206,32209,33203,33207,33208,33209,33210,33211,33215,33461,33586,33606,33622,33623,33666,33681,34101,34104,34105,34204,34205,34209,34210,34211,34212,34214,34431,34545,35203,35204,35208,35212,35305,35321,36383,36387,36388,36468,37364,38203,38215,39202,39204,39206,39211,39212,39303,39305,39306,39307,39341,39344,39403,39405,39412,39428,40203,40207,40215,41208,41345,41346,43104,45205,45361"

def quake_int(config, key, default, lo, hi):
    v = str(config.get(key) or "")
    if not v.isdigit():
        return default
    return max(lo, min(hi, int(v)))

# ---------------------------------------------------------------------------
# Sample event

def quake_demo_event():
    prefs = {}
    for group in QUAKE_DEMO_MUNI.split(";"):
        label, codes = group.split(":")
        for m in codes.split(","):
            p = prefs.get(m[:2])
            if p == None:
                p = {"code": m[:2], "maxi": label, "city": []}
                prefs[m[:2]] = p
            p["city"].append({"code": m + "00", "maxi": label})
    return {
        "id": "20240101161010",
        "kind": "detail",
        "kind_en": "Detailed",
        "time": time.parse_time("2024-01-01T16:10:00+09:00"),
        "reported": time.parse_time("2024-01-01T16:24:00+09:00"),
        "title_en": "Earthquake and Seismic Intensity Information",
        "epi_en": BOUSAI_EPICENTER_EN["390"],
        "acd": "390",
        "lat": 37.5,
        "lon": 137.2,
        "depth": 0.0,
        "mag": "7.6",
        "max_int": "7",
        "areas": [prefs[k] for k in sorted(prefs)],
        "json": "",
    }

# ---------------------------------------------------------------------------
# Row and page machinery. A row is (height, builder); builder(frames) makes the widget once the
# page count (and therefore each page's share of the dwell time) is known.

def quake_row_text(ui, s, color = None):
    return (ui["line_h"], lambda f: bousai_fit(ui, s, color = color, frames = f))

def quake_chip(ui, label, color):
    return render.Box(width = bousai_text_width(ui, label) + 3, height = bousai_font_height(ui) + 1, color = color, child = bousai_text(ui, label, bousai_on(color)))

def quake_int_label(ev):
    if ev["kind"] == "distant":
        return "M" + ev["mag"] if ev["mag"] else "M?"
    return "Int " + ev["max_int"] if ev["max_int"] else "Int ?"

def quake_int_color(ui, ev):
    if ev["kind"] == "distant":
        return ui["sev"][1]
    if ev["max_int"]:
        return bousai_intensity_color(ui, ev["max_int"])
    return ui["intensity"]["0"]

def quake_name_rows(ui, text, color = None):
    return [quake_row_text(ui, l, color) for l in bousai_quake_name_lines(ui, text)]

# ---------------------------------------------------------------------------
# Heads

def quake_band(ui, ev, now, demo):
    """Intensity block with the magnitude and age beside it (the first thing read)."""
    label = quake_int_label(ev)
    color = quake_int_color(ui, ev)
    big = ui["big_font"]
    bh = bousai_font_height(ui, big)
    left_w = min(canvas.width(), bousai_text_width(ui, label, big) + 4)
    kids = [render.Box(width = left_w, height = bh, color = color, child = bousai_text(ui, label, bousai_on(color), big))]
    age = "demo" if demo else bousai_ago(ev["time"], now)
    mag = "M" + ev["mag"] if ev["mag"] else "M?"
    if ev["kind"] == "distant":
        lines = ["Overseas", age]
    elif ui["size"] == "standard":
        lines = [mag, age]
    elif ui["size"] == "xlarge":
        lines = []
    else:
        lines = [mag]
    font = ui["small_font"] if len(lines) > 1 else ui["font"]
    right_w = canvas.width() - left_w
    if len(lines) > 0 and max([bousai_text_width(ui, l, font) for l in lines]) + 2 <= right_w:
        kids.append(render.Box(width = right_w, height = bh, child = render.Padding(pad = (2, 0, 0, 0), child = render.Column(main_align = "center", cross_align = "start", children = [bousai_text(ui, l, ui["fg"] if i == 0 else ui["muted"], font) for i, l in enumerate(lines)]))))
    return render.Row(cross_align = "start", children = kids)

def quake_thin_head(ui, ev, now, demo):
    """Compact coloured header repeated on later pages."""
    if ui["size"] == "xlarge":
        return None
    title = quake_int_label(ev) + ("  M" + ev["mag"] if ev["mag"] and ev["kind"] != "distant" else "")
    right = "demo" if demo else bousai_ago(ev["time"], now)
    if bousai_text_width(ui, title) + bousai_text_width(ui, right) + 6 > canvas.width():
        right = None
    color = quake_int_color(ui, ev)
    return (ui["line_h"], lambda f: bousai_header(ui, title, color, right, frames = f))

# ---------------------------------------------------------------------------
# Detail rows

def quake_time_row(ui, ev, tz, now, demo):
    text = bousai_mdhm(ev["time"], tz) + "  " + ("demo" if demo else bousai_ago(ev["time"], now))
    return quake_row_text(ui, text, ui["muted"])

def quake_area_row(ui, ev, local, in_japan):
    if not in_japan:
        return quake_row_text(ui, "Location outside Japan", ui["muted"])
    if local["city"] != None:
        lead, label = ("City max" if local["wards"] else "Your area"), local["city"]
    elif local["pref"] != None:
        lead, label = "Pref max", local["pref"]
    else:
        none_text = {"flash": "Area: below Int 3", "epicenter": "Area: pending"}.get(ev["kind"], "Area: no report")
        return quake_row_text(ui, none_text, ui["muted"])
    color = bousai_intensity_color(ui, label)
    chip_text = "Int " + label
    text = lead
    for candidate in [lead, "Area", "You"]:
        text = candidate
        if bousai_text_width(ui, candidate) + 2 + bousai_text_width(ui, chip_text) + 3 <= canvas.width():
            break
    return (ui["line_h"], lambda f: render.Row(expanded = True, main_align = "start", cross_align = "center", children = [bousai_text(ui, text, ui["muted"]), render.Padding(pad = (2, 0, 0, 0), child = quake_chip(ui, chip_text, color))]))

def quake_tsunami_row(ui, text):
    color = ui["sev"][3] if "in effect" in text or "possible" in text else ui["fg"]
    return quake_row_text(ui, text, color)

def quake_type_row(ui, ev):
    depth = bousai_quake_depth_text(ev["depth"], long = True)
    text = ev["kind_en"] + ("  " + depth if depth else "")
    return quake_row_text(ui, text, ui["muted"])

def quake_places_row(ui, places):
    """Strongest-shaking place: chip with the intensity and the place name (+ how many more)."""
    label = places[0][1]
    same = [p for p in places if p[1] == label]
    name = places[0][0] + (" +%d" % (len(same) - 1) if len(same) > 1 else "")
    chip_text = "Int " + label
    color = bousai_intensity_color(ui, label)
    room = canvas.width() - bousai_text_width(ui, chip_text) - 6
    return (ui["line_h"], lambda f: render.Row(expanded = True, main_align = "start", cross_align = "center", children = [quake_chip(ui, chip_text, color), render.Padding(pad = (2, 0, 0, 0), child = bousai_fit(ui, name, width = room, frames = f))]))

def quake_distance_row(ui, ev, loc):
    km = bousai_distance_km(loc["lat"], loc["lon"], ev["lat"], ev["lon"])
    text = "%dkm %s of you" % (int(km + 0.5), bousai_bearing_name(loc["lat"], loc["lon"], ev["lat"], ev["lon"]))
    return quake_row_text(ui, text, ui["muted"])

# ---------------------------------------------------------------------------
# Map

def quake_strip(ui, ev, now, demo):
    w = canvas.width()
    label = quake_int_label(ev)
    chip = quake_chip(ui, label, quake_int_color(ui, ev))
    left = [chip]
    used = bousai_text_width(ui, label) + 3
    mag = "M" + ev["mag"] if ev["mag"] and ev["kind"] != "distant" else ""
    age = "demo" if demo else bousai_ago(ev["time"], now)
    if mag and used + 2 + bousai_text_width(ui, mag) <= w:
        left.append(render.Padding(pad = (2, 0, 0, 0), child = bousai_text(ui, mag)))
        used += 2 + bousai_text_width(ui, mag)
    kids = [render.Row(cross_align = "center", children = left)]
    if used + 4 + bousai_text_width(ui, age) <= w:
        kids.append(bousai_text(ui, age, ui["muted"]))
    return render.Box(width = w, height = bousai_font_height(ui) + 2, child = render.Row(expanded = True, main_align = "space_between", cross_align = "center", children = kids))

def quake_tint(ui, img):
    """JMA's published intensity colours cannot be remapped: grey them for the monochrome palette, dim them in low contrast."""
    if ui["palette"] == "mono":
        img = filter.Grayscale(child = img)
    if ui["contrast"] == "low":
        img = filter.Brightness(child = img, change = -0.25)
    return img

def quake_overlay(ui, view, tiles):
    """Position estimated-intensity images: tiles are (png bytes, south, west, north, east)."""
    out = []
    for src, s, w, n, e in tiles:
        x0, y0 = bousai_view_xy(view, n, w)
        x1, y1 = bousai_view_xy(view, s, e)
        out.append(bousai_place(x0, y0, quake_tint(ui, render.Image(src = src, width = max(1, x1 - x0), height = max(1, y1 - y0)))))
    return out

def quake_mesh_tiles(view, est):
    """JMA mesh PNGs overlapping the view (nearest the centre first, at most 6)."""
    found = []
    for m in est["meshes"]:
        s, w, n, e = bousai_quake_mesh_bounds(m)
        x0, y0 = bousai_view_xy(view, n, w)
        x1, y1 = bousai_view_xy(view, s, e)
        if x1 <= 0 or y1 <= 0 or x0 >= view["w"] or y0 >= view["h"]:
            continue
        found.append((abs((x0 + x1) / 2 - view["w"] / 2) + abs((y0 + y1) / 2 - view["h"] / 2), m, s, w, n, e))
    tiles = []
    for _, m, s, w, n, e in sorted(found)[:6]:
        src = bousai_get_bytes(est["dir"] + m + ".png", ttl = 7 * 86400)
        if src != None:
            tiles.append((src, s, w, n, e))
    return tiles

def quake_dots(ui, view, stations):
    """Observation points coloured by intensity (strongest drawn last, at most 90)."""
    out = []
    for lat, lon, label in reversed(stations[:90]):
        x, y = bousai_view_xy(view, lat, lon)
        if bousai_in_view(view, x, y):
            out.append(bousai_place(x - 1, y - 1, render.Box(width = 2, height = 2, color = bousai_intensity_color(ui, label))))
    return out

def quake_marks(ui, view, ev, user):
    """Epicenter as a cross, your place as a square; both haloed so they read over any layer."""
    layers = []
    ex, ey = bousai_view_xy(view, ev["lat"], ev["lon"])
    arm = 3
    red = ui["sev"][3]
    layers.append(bousai_place(ex - arm - 1, ey - 1, render.Box(width = 2 * arm + 3, height = 3, color = ui["bg"])))
    layers.append(bousai_place(ex - 1, ey - arm - 1, render.Box(width = 3, height = 2 * arm + 3, color = ui["bg"])))
    layers.append(bousai_place(ex - arm, ey, render.Box(width = 2 * arm + 1, height = 1, color = red)))
    layers.append(bousai_place(ex, ey - arm, render.Box(width = 1, height = 2 * arm + 1, color = red)))
    if user != None:
        ux, uy = bousai_view_xy(view, user["lat"], user["lon"])
        if bousai_in_view(view, ux, uy):
            layers.append(bousai_place(ux - 2, uy - 2, render.Box(width = 5, height = 5, color = ui["bg"], child = render.Box(width = 3, height = 3, color = ui["fg"]))))
    return layers

def quake_map_basemap(ev):
    lat, lon = ev["lat"], ev["lon"]
    if lat == None:
        return None
    if lat >= 20 and lat <= 47 and lon >= 120 and lon <= 155:
        return "japan"
    if lat >= -5 and lat <= 60 and lon >= 95 and lon <= 180:
        return "pacific"
    return None

def quake_map(ui, ev, user, est, demo, now, stations, base):
    """Epicenter map: land, estimated intensity (or observation points), epicenter and you."""
    strip = quake_strip(ui, ev, now, demo)
    mh = canvas.height() - (bousai_font_height(ui) + 2)
    points = [(ev["lat"], ev["lon"])]
    if user != None:
        points.append((user["lat"], user["lon"]))
    view = bousai_view_fit(points, canvas.width(), mh, pad = 4, min_zoom = 1.0, max_zoom = 4.5)
    layers = [bousai_basemap(ui, view, base)]
    if demo:
        s, w, n, e = QUAKE_DEMO_EST_BOUNDS
        layers.extend(quake_overlay(ui, view, [(base64.decode(QUAKE_DEMO_EST), s, w, n, e)]))
    elif est != None:
        layers.extend(quake_overlay(ui, view, quake_mesh_tiles(view, est)))
    else:
        layers.extend(quake_dots(ui, view, stations))
    layers.extend(quake_marks(ui, view, ev, user))
    return render.Column(children = [bousai_map_frame(ui, view, layers), strip])

# ---------------------------------------------------------------------------
# Event pages

def quake_list_row(ui, ev, now):
    """Compact row for an older quake: intensity chip, magnitude, age, and (small text) the place."""
    two = ui["line_h"] <= 7
    lh = ui["line_h"]
    label = quake_int_label(ev)
    color = quake_int_color(ui, ev)
    mag = "M" + ev["mag"] if ev["mag"] and ev["kind"] != "distant" else ""
    age = bousai_ago(ev["time"], now)
    kids = [quake_chip(ui, label, color)]
    used = bousai_text_width(ui, label) + 3
    if mag and used + 2 + bousai_text_width(ui, mag) <= canvas.width():
        kids.append(render.Padding(pad = (2, 0, 0, 0), child = bousai_text(ui, mag)))
        used += 2 + bousai_text_width(ui, mag)
    if used + 3 + bousai_text_width(ui, age) <= canvas.width():
        kids.append(render.Padding(pad = (3, 0, 0, 0), child = bousai_text(ui, age, ui["muted"])))
    name = ev["epi_en"]

    def build(f):
        top = render.Box(width = canvas.width(), height = lh, child = render.Row(expanded = True, cross_align = "center", children = kids))
        if not two:
            return top
        return render.Column(children = [top, bousai_fit(ui, name, color = ui["muted"], frames = f)])

    return (lh * (2 if two else 1), build)

def quake_event_pages(ui, config, events, count, now, tz, demo):
    ev = events[0]
    loc = bousai_location(config)
    place = bousai_quake_place(config)
    in_japan = place != None
    detail = None if demo else bousai_quake_detail(ev)
    tsunami = QUAKE_DEMO_TSUNAMI if demo else bousai_quake_tsunami_text(detail)
    local = bousai_quake_local(ev, place)
    rank = bousai_intensity_rank(ev["max_int"])

    places = []
    if rank >= 3 and ev["kind"] != "distant":
        places = bousai_quake_places(ev, bousai_area_table() if ev["kind"] == "detail" else None)

    rows = quake_name_rows(ui, ev["epi_en"])
    rows.append(quake_time_row(ui, ev, tz, now, demo))
    if ev["kind"] != "distant":
        rows.append(quake_area_row(ui, ev, local, in_japan))
    if tsunami:
        rows.append(quake_tsunami_row(ui, tsunami))
    rows.append(quake_type_row(ui, ev))
    if len(places) > 0:
        rows.append(quake_places_row(ui, places))
    extra = []
    if ev["lat"] != None and in_japan:
        extra.append(quake_distance_row(ui, ev, loc))

    if ui["size"] == "xlarge":
        mag = "M" + ev["mag"] if ev["mag"] else "M?"
        rows.insert(0, quake_row_text(ui, mag + " " + ("demo" if demo else bousai_ago(ev["time"], now))))
    band = (bousai_font_height(ui, ui["big_font"]), lambda f: quake_band(ui, ev, now, demo))
    pages = bousai_quake_pack(rows + extra, band, quake_thin_head(ui, ev, now, demo))
    if len(extra) > 0 and len(pages) > 1 and len(pages[-1]["rows"]) == len(extra):
        pages = bousai_quake_pack(rows, band, quake_thin_head(ui, ev, now, demo))

    base = quake_map_basemap(ev)
    if base != None:
        est = None
        stations = []
        if not demo:
            if rank >= 4:
                est = bousai_quake_estimate(ev)
            if est == None:
                stations = bousai_quake_stations(detail)
        user = {"lat": loc["lat"], "lon": loc["lon"]} if in_japan else None
        map_page = {"full": lambda f: quake_map(ui, ev, user, est, demo, now, stations, base)}
        pages.insert(1, map_page)

    others = [quake_list_row(ui, e, now) for e in events[1:count]]
    pages.extend(bousai_quake_pack(others, None, None))
    return pages

# ---------------------------------------------------------------------------
# Special information

def quake_special_pages(ui, sp, now, tz):
    short = "Nankai Trough" if sp["title_en"].startswith("Nankai") else "Hokkaido/Sanriku"
    color = bousai_sev_color(ui, sp["sev"])
    head = (ui["line_h"], lambda f: bousai_header(ui, short, color, frames = f))
    rows = quake_name_rows(ui, sp["kind_en"])
    rows.append(quake_row_text(ui, bousai_mdhm(sp["issued"], tz) + "  " + bousai_ago(sp["issued"], now), ui["muted"]))
    if ui["size"] == "xlarge":
        head = None
        rows.insert(0, quake_row_text(ui, short, color))
    return bousai_quake_pack(rows, head, head)

# ---------------------------------------------------------------------------

def main(config):
    ui = bousai_ui(config)
    tz = bousai_location(config)["tz"]
    now = bousai_now()
    demo = bousai_bool(config, "demo", False)
    min_int = config.get("min_int") or "1"
    count = quake_int(config, "count", 3, 1, 5)
    only_hours = quake_int(config, "only_recent", 0, 0, 720)
    overseas = bousai_bool(config, "overseas", False)

    special = []
    events = []
    unavailable = False
    if demo:
        events = [quake_demo_event()]
    else:
        special = bousai_quake_special()
        feed = bousai_quake_events()
        if feed == None:
            unavailable = True
        else:
            events = bousai_quake_filter(feed, min_int, overseas, now)
        if only_hours > 0 and len(events) > 0 and (now - events[0]["time"]).hours > only_hours:
            events = []

    if len(events) == 0 and len(special) == 0:
        if only_hours > 0 and not demo:
            return []
        if unavailable:
            return bousai_message(ui, "Quake", ["JMA quake feed", "unavailable", "Retrying soon"], ui["sev"][2])
        return bousai_message(ui, "Quake", ["No quakes of", "Int " + (bousai_intensity_norm(min_int) or "1") + " or more", "in the JMA list"])

    pages = []
    for s in special:
        pages.extend(quake_special_pages(ui, s, now, tz))
    if len(events) > 0:
        pages.extend(quake_event_pages(ui, config, events, count, now, tz, demo))
    return bousai_root(ui, bousai_quake_render(pages[:QUAKE_MAX_PAGES]))

def get_schema():
    return bousai_schema([
        schema.Dropdown(
            id = "min_int",
            name = "Minimum intensity",
            desc = "Hide earthquakes weaker than this JMA seismic intensity (shindo).",
            icon = "waveSquare",
            default = "1",
            options = [
                schema.Option(display = "Int 1 and up (all felt quakes)", value = "1"),
                schema.Option(display = "Int 2 and up", value = "2"),
                schema.Option(display = "Int 3 and up (flash reports)", value = "3"),
                schema.Option(display = "Int 4 and up", value = "4"),
                schema.Option(display = "Int 5- and up", value = "5-"),
            ],
        ),
        schema.Dropdown(
            id = "count",
            name = "Quakes to show",
            desc = "How many recent earthquakes to cycle through. The newest gets full detail and a map; older ones get one summary row each.",
            icon = "listOl",
            default = "3",
            options = [schema.Option(display = str(n), value = str(n)) for n in range(1, 6)],
        ),
        schema.Dropdown(
            id = "only_recent",
            name = "Only recent quakes",
            desc = "Skip this app when the newest qualifying earthquake is older than this. Enable AutoPin in Tronbyt so a new quake takes over the display.",
            icon = "clockRotateLeft",
            default = "0",
            options = [
                schema.Option(display = "Always show", value = "0"),
                schema.Option(display = "Within 1 hour", value = "1"),
                schema.Option(display = "Within 3 hours", value = "3"),
                schema.Option(display = "Within 6 hours", value = "6"),
                schema.Option(display = "Within 12 hours", value = "12"),
                schema.Option(display = "Within 24 hours", value = "24"),
                schema.Option(display = "Within 3 days", value = "72"),
            ],
        ),
        schema.Toggle(
            id = "overseas",
            name = "Include overseas quakes",
            desc = "Add JMA distant earthquake reports (large quakes abroad that can affect Japan's coasts).",
            icon = "earthAsia",
            default = False,
        ),
        schema.Toggle(
            id = "demo",
            name = "Show sample quake",
            desc = "Show the 2024-01-01 Noto Peninsula M7.6 (Int 7) earthquake as an embedded sample.",
            icon = "flask",
            default = False,
        ),
    ])
