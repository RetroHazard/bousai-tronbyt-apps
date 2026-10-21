"""Weather warnings domain library for the Bousai suite.

Sources (all official JMA):
  * r8 warning feed  warning/data/r8/<office>.json  - advisories, warnings, urgent (Lv4) and emergency (Lv5)
    warnings, landslide alert levels. One report per dataTypeCode; the union of their active kinds is the
    current state. class20 (municipality) is authoritative, class10 is the fallback.
  * flood/data/r8/flood_xml.json - designated-river flood forecasts (schema taken from the JMA page JS).
  * XML long feed extra_l.xml - tornado watch (VPHW50/51) and record short-term heavy rain (VPOA50, and the
    new VPBS50 bulletin) entries, matched through the linked XML.

Exports for other Bousai apps (they never render widgets and return [] when a feed is unavailable):
  bousai_warnings_current(area)  - active warnings for an area, most severe first
  bousai_warnings_notices(area)  - currently valid tornado watch / record rain / river flood notices
"""

# bousai: requires core data

load("cache.star", "cache")
load("encoding/json.star", "json")
load("time.star", "time")
load("xpath.star", "xpath")

BOUSAI_WARNINGS_R8_URL = "https://www.jma.go.jp/bosai/warning/data/r8/%s.json"
BOUSAI_WARNINGS_FLOOD_URL = "https://www.jma.go.jp/bosai/flood/data/r8/flood_xml.json"
BOUSAI_WARNINGS_FEED_URL = "https://www.data.jma.go.jp/developer/xml/feed/extra_l.xml"
BOUSAI_WARNINGS_FEED_KEY = "bousai_warnings:feed:v1"
BOUSAI_WARNINGS_XML_KEY = "bousai_warnings:xml:v2:"

# Bulletins older than this are never fetched. A tornado watch carries its own ValidDateTime (about one hour);
# record short-term heavy rain has no validity, so it stays visible for two hours.
BOUSAI_WARNINGS_FEED_MAX_AGE = 6 * 3600
BOUSAI_WARNINGS_TORNADO_MAX_AGE = 3 * 3600
BOUSAI_WARNINGS_RECORD_RAIN_AGE = 2 * 3600

# Severity index (ui["sev"]) of the notices. Flood notices use the flood level / 10.
BOUSAI_WARNINGS_TORNADO_SEV = 3
BOUSAI_WARNINGS_RECORD_RAIN_SEV = 4

BOUSAI_WARNINGS_MAX_SAVED = 5

# Level -> JMA English term.
BOUSAI_WARNINGS_LEVEL_EN = {20: "Advisory", 30: "Warning", 40: "Urgent Warning", 50: "Emergency Warning"}

# r8 element -> [English name at Lv2, English name at Lv3 and above]. Terms follow the dictionary of the JMA
# warning page (e.g. 強風 Gale / 暴風 Storm, 風雪 Gale and Snow / 暴風雪 Snowstorm); the dictionary spells
# 雷 "Thunder Storm", here it is written "Thunderstorm". Insertion order is the display order.
BOUSAI_WARNINGS_ELEMENTS = {
    "rain": ["Heavy Rain", "Heavy Rain"],
    "landslide": ["Landslide", "Landslide"],
    "tide": ["Storm Surge", "Storm Surge"],
    "wind": ["Gale", "Storm"],
    "wind_snow": ["Gale and Snow", "Snowstorm"],
    "snow": ["Heavy Snow", "Heavy Snow"],
    "wave": ["High Wave", "High Wave"],
    "thunder": ["Thunderstorm", "Thunderstorm"],
    "snow_melting": ["Snow Melting", "Snow Melting"],
    "fog": ["Dense Fog", "Dense Fog"],
    "dry": ["Dry Air", "Dry Air"],
    "avalanche": ["Avalanche", "Avalanche"],
    "cold": ["Low Temperature", "Low Temperature"],
    "frost": ["Frost", "Frost"],
    "ice_accretion": ["Ice Accretion", "Ice Accretion"],
    "snow_accretion": ["Snow Accretion", "Snow Accretion"],
}

# r8 kind status -> English. 解除 (cancelled) and 発表警報・注意報はなし (none issued) are not active.
BOUSAI_WARNINGS_INACTIVE = ["解除", "発表警報・注意報はなし"]
BOUSAI_WARNINGS_STATUS_EN = {
    "発表": "Issued",
    "継続": "Continued",
    "警報から注意報": "Downgraded from Warning",
    "特別警報から警報": "Downgraded from Emergency Warning",
    "特別警報から注意報": "Downgraded from Emergency Warning",
}

# Designated-river flood forecast item.code -> level (table of the JMA warning page JS; 50 and 52 are shown as
# "flood occurrence" colours by the JMA flood page).
BOUSAI_WARNINGS_FLOOD_LEVEL = {"20": 20, "21": 20, "22": 20, "30": 30, "31": 30, "40": 40, "41": 40, "50": 50, "51": 50, "52": 50, "53": 50}

# Fallback when an unknown item.code arrives: level from the Japanese item.name (old and Lv-style names).
BOUSAI_WARNINGS_FLOOD_NAMES = [
    ["レベル５", 50],
    ["氾濫発生", 50],
    ["氾濫特別警報", 50],
    ["レベル４", 40],
    ["氾濫危険", 40],
    ["レベル３", 30],
    ["氾濫警戒", 30],
    ["氾濫警報", 30],
    ["レベル２", 20],
    ["氾濫注意", 20],
]
BOUSAI_WARNINGS_FLOOD_INFO_EN = {20: "flood caution", 30: "flood warning", 40: "flood danger", 50: "flood occurrence"}

BOUSAI_WARNINGS_FULLWIDTH = [["０", "0"], ["１", "1"], ["２", "2"], ["３", "3"], ["４", "4"], ["５", "5"], ["６", "6"], ["７", "7"], ["８", "8"], ["９", "9"]]

# ---------------------------------------------------------------------------
# Areas

def bousai_warnings_ascii(s):
    """Replace full-width digits by ASCII digits."""
    for pair in BOUSAI_WARNINGS_FULLWIDTH:
        s = s.replace(pair[0], pair[1])
    return s

def bousai_warnings_parse_codes(text):
    """Split a free-text list of 7-digit JMA municipality codes.

    Accepts commas, spaces, semicolons, newlines and full-width digits. Returns [codes, rejected]; codes are
    unique and capped at BOUSAI_WARNINGS_MAX_SAVED.
    """
    flat = bousai_warnings_ascii(text or "")
    for sep in ["，", "、", "；", ";", "\n", "\t", "　", " "]:
        flat = flat.replace(sep, ",")
    codes = []
    rejected = []
    for raw in flat.split(","):
        c = raw.strip()
        if not c:
            continue
        if len(c) == 7 and c.isdigit():
            if c not in codes and len(codes) < BOUSAI_WARNINGS_MAX_SAVED:
                codes.append(c)
        elif c not in rejected:
            rejected.append(c)
    return [codes, rejected]

def bousai_warnings_area_for_code(code, table = None):
    """bousai_area()-shaped dict for a 7-digit JMA municipality code (lat/lon are None); None when unknown."""
    table = table or bousai_area_table()
    if not table:
        return None
    c20 = (table.get("class20s") or {}).get(code)
    if c20 == None:
        return None
    c15_code = c20.get("parent") or ""
    c15 = (table.get("class15s") or {}).get(c15_code) or {}
    c10_code = c15.get("parent") or ""
    c10 = (table.get("class10s") or {}).get(c10_code) or {}
    office_code = c10.get("parent") or ""
    office = (table.get("offices") or {}).get(office_code) or {}
    return {
        "class20": code,
        "class15": c15_code,
        "class10": c10_code,
        "office": office_code,
        "center": office.get("parent") or "",
        "pref": code[:2],
        "class20_en": c20.get("enName") or code,
        "class15_en": c15.get("enName") or "",
        "class10_en": c10.get("enName") or "",
        "office_en": office.get("enName") or "",
        "lat": None,
        "lon": None,
    }

def bousai_warnings_region_name(area):
    """English name of the area's class10 region, with the office when that disambiguates it."""
    region = area.get("class10_en") or ""
    office = area.get("office_en") or ""
    if region and office and office not in region:
        return "%s, %s" % (region, office)
    return region or office or (area.get("class20_en") or "")

# ---------------------------------------------------------------------------
# r8 warnings

def bousai_warnings_reports(office):
    """Decoded r8 reports of a JMA office (one per dataTypeCode), or None when unavailable."""
    if not office:
        return None
    data = bousai_get_json(BOUSAI_WARNINGS_R8_URL % office, ttl = 60)
    if type(data) != "list":
        return None
    return data

def bousai_warnings_collect(reports, code, key):
    """Union of the active kinds of one area code across every report.

    Returns [found, kinds]: found is True when the area is listed in any report (even with nothing active);
    kinds maps kind code -> [status, reportDatetime of the newest report mentioning it].
    """
    found = False
    kinds = {}
    for rep in reports:
        if type(rep) != "dict":
            continue
        stamp = rep.get("reportDatetime") or ""
        for item in (rep.get("warning") or {}).get(key) or []:
            if item.get("areaCode") != code:
                continue
            found = True
            for kind in item.get("kinds") or []:
                kcode = kind.get("code")
                status = kind.get("status") or ""
                if not kcode or status in BOUSAI_WARNINGS_INACTIVE:
                    continue
                prev = kinds.get(kcode)
                if prev == None or stamp > prev[1]:
                    kinds[kcode] = [status, stamp]
    return [found, kinds]

def bousai_warnings_build(reports, area):
    """Active warnings of an area from decoded r8 reports. Returns [items, area name used].

    Uses the municipality (class20) when any report lists it, otherwise the class10 region.
    """
    c20 = area.get("class20") or ""
    found = False
    kinds = {}
    name = area.get("class20_en") or c20
    if c20:
        res = bousai_warnings_collect(reports, c20, "class20Items")
        found, kinds = res[0], res[1]
    if not found:
        res = bousai_warnings_collect(reports, area.get("class10") or "", "class10Items")
        kinds = res[1]
        name = bousai_warnings_region_name(area)

    best = {}
    for kcode, state in kinds.items():
        info = BOUSAI_WARN_CODES.get(kcode)
        if info == None:
            continue
        element, level = info[0], info[1]
        cur = best.get(element)
        if cur == None or level > cur["level"] or (level == cur["level"] and state[1] > cur["stamp"]):
            best[element] = {"element": element, "level": level, "status": state[0], "stamp": state[1]}

    order = {}
    for i, element in enumerate(BOUSAI_WARNINGS_ELEMENTS.keys()):
        order[element] = i

    now = time.now()
    items = []
    for element, b in best.items():
        names = BOUSAI_WARNINGS_ELEMENTS.get(element) or [element.replace("_", " ").title()] * 2
        element_en = names[0] if b["level"] <= 20 else names[1]
        level = b["level"]
        items.append({
            "element": element,
            "element_en": element_en,
            "level": level,
            "sev": level // 10,
            "label_en": "%s: %s" % (BOUSAI_WARNINGS_LEVEL_EN.get(level) or "Warning", element_en),
            "status": BOUSAI_WARNINGS_STATUS_EN.get(b["status"]) or "Active",
            "issued": bousai_parse_time(b["stamp"]) or now,
            "area_en": name,
        })
    return [sorted(items, key = lambda w: (-w["level"], order.get(w["element"], 99))), name]

def bousai_warnings_current(area):
    """Active weather warnings for an area (area = bousai_area(config) dict), most severe first.

    Returns a list of dicts, [] when nothing is active, the area is None or the JMA feed is unavailable:
      element    r8 element id: rain, landslide, tide, wind, wind_snow, snow, wave, thunder, snow_melting, fog,
                 dry, avalanche, cold, frost, ice_accretion, snow_accretion
      element_en JMA English name, level dependent for wind ("Gale" Lv2 / "Storm" Lv3+) and wind_snow
                 ("Gale and Snow" / "Snowstorm")
      level      20 advisory, 30 warning, 40 urgent warning (Lv4), 50 emergency warning (Lv5)
      sev        2..5 index into ui["sev"] (level // 10)
      label_en   e.g. "Urgent Warning: Heavy Rain"
      status     "Issued", "Continued" or "Downgraded from ..."
      issued     Pixlet time of the newest r8 report that carries the warning
      area_en    municipality (class20), or "<class10 region>, <office>" when the municipality is not listed
    One entry per element (the highest level). Landslide is the JMA landslide alert level
    (Lv2 advisory ... Lv4 landslide alert information ... Lv5).
    """
    if not area:
        return []
    reports = bousai_warnings_reports(area.get("office"))
    if reports == None:
        return []
    return bousai_warnings_build(reports, area)[0]

# ---------------------------------------------------------------------------
# Designated-river flood forecasts (flood_xml.json)

def bousai_warnings_flood_level(entry):
    """Flood level (20..50) of a flood_xml.json entry, None when the entry is not an active forecast."""
    if (entry.get("infoType") or "") in ["取消", "訓練", "試験"]:
        return None
    item = entry.get("item")
    if type(item) != "dict":
        item = {}
    if (item.get("status") or "") == "解除":
        return None
    level = BOUSAI_WARNINGS_FLOOD_LEVEL.get(str(item.get("code") or ""))
    if level != None:
        return level
    name = item.get("name") or ""
    if name.endswith("解除"):
        return None
    name = bousai_warnings_ascii(name)
    for pair in BOUSAI_WARNINGS_FLOOD_NAMES:
        if bousai_warnings_ascii(pair[0]) in name:
            return pair[1]
    return None

def bousai_warnings_flood_notices(data, area):
    """Notices for the active designated-river flood forecasts that touch an area.

    Entry schema (from the JMA page JS): infoType, reportDatetime, riverCode, riverName, officeCodes,
    class10Codes, class20Codes, item {code, name}. A forecast matches on the municipality (class20Codes) or
    on the class10 region (class10Codes). Returns one notice per (level, match kind).
    """
    if type(data) != "list" or not area:
        return []
    c20 = area.get("class20") or ""
    c10 = area.get("class10") or ""
    groups = {}
    for i, entry in enumerate(data):
        if type(entry) != "dict":
            continue
        level = bousai_warnings_flood_level(entry)
        if level == None:
            continue
        hit = ""
        if c20 and c20 in (entry.get("class20Codes") or []):
            hit = "city"
        elif c10 and c10 in (entry.get("class10Codes") or []):
            hit = "region"
        if not hit:
            continue
        key = "%d:%s" % (level, hit)
        g = groups.setdefault(key, {"level": level, "hit": hit, "rivers": [], "issued": None})
        river = str(entry.get("riverCode") or entry.get("riverName") or i)
        if river not in g["rivers"]:
            g["rivers"].append(river)
        t = bousai_parse_time(entry.get("reportDatetime"))
        if t != None and (g["issued"] == None or t > g["issued"]):
            g["issued"] = t
    now = time.now()
    out = []
    for g in groups.values():
        n = len(g["rivers"])
        plural = "" if n == 1 else "s"
        text = "%d river%s: %s" % (n, plural, BOUSAI_WARNINGS_FLOOD_INFO_EN[g["level"]])
        if g["hit"] == "region":
            text = "Nearby: %d river%s, %s" % (n, plural, BOUSAI_WARNINGS_FLOOD_INFO_EN[g["level"]])
        out.append({
            "kind_en": "River Flood " + BOUSAI_WARNINGS_LEVEL_EN[g["level"]],
            "text_en": text,
            "issued": g["issued"] or now,
            "sev": g["level"] // 10,
        })
    return out

# ---------------------------------------------------------------------------
# Bulletins from the XML long feed: tornado watch and record short-term heavy rain

def bousai_warnings_feed():
    """Tornado watch / record rain entries of the JMA long feed, newest first; None when the feed is unavailable.

    Each entry: {kind: "tornado" | "record", href, updated, code}. `code` is the issuing office code that
    ends the XML file name (e.g. 390000 for Kochi). Only the small filtered list is cached (120 s), the 2.8 MB
    feed itself is parsed at most once per cache period.
    """
    cached = cache.get(BOUSAI_WARNINGS_FEED_KEY)
    if cached:
        return json.decode(cached, default = None)
    body = bousai_get_bytes(BOUSAI_WARNINGS_FEED_URL, ttl = 120)
    if body == None:
        return None
    doc = xpath.loads(body)
    nodes = doc.query_all_nodes("//entry[title='竜巻注意情報' or title='竜巻注意情報（目撃情報付き）' or title='記録的短時間大雨情報' or title='府県気象防災速報']")
    now = time.now()
    out = []
    for n in nodes:
        title = n.query("title") or ""
        href = n.query("link/@href") or n.query("id") or ""
        content = n.query("content") or ""
        updated = n.query("updated") or ""
        if not href or not updated:
            continue
        kind = ""
        if title.startswith("竜巻注意情報"):
            kind = "tornado"
        elif title == "記録的短時間大雨情報" or "（記録的短時間大雨）" in content:
            kind = "record"
        t = bousai_parse_time(updated)
        if not kind or t == None or (now - t).seconds > BOUSAI_WARNINGS_FEED_MAX_AGE:
            continue
        tail = href.split("/")[-1].replace(".xml", "")
        out.append({
            "kind": kind,
            "href": href,
            "updated": updated,
            "code": tail.split("_")[-1],
        })
    cache.set(BOUSAI_WARNINGS_FEED_KEY, json.encode(out), ttl_seconds = 120)
    return out

def bousai_warnings_parse_bulletin(text):
    """Plain-value summary of a JMA tornado watch / record rain XML document (None when it cannot be parsed)."""
    if not text:
        return None
    doc = xpath.loads(text)
    places = []
    for n in doc.query_all_nodes("//MeteorologicalInfo/Item"):
        code = n.query("Area/Code") or ""
        amount = "*[local-name()='Precipitation']"
        mm = n.query("Kind/Property/PrecipitationPart/" + amount) or ""
        if code and mm:
            places.append({"code": code, "mm": mm, "cond": n.query("Kind/Property/PrecipitationPart/" + amount + "/@condition") or ""})
    return {
        "status": doc.query("//Control/Status") or "",
        "info_type": doc.query("//Head/InfoType") or "",
        "issued": doc.query("//Head/ReportDateTime") or "",
        "valid": doc.query("//Head/ValidDateTime") or "",
        "codes": doc.query_all("//Headline/Information/Item/Areas/Area/Code") or [],
        "sight_codes": doc.query_all("//Headline/Information[@type='竜巻注意情報（目撃情報あり）']/Item/Areas/Area/Code") or [],
        "tags": doc.query_all("//Headline/Information/Item/Kind/Condition") or [],
        "headline": doc.query("//Headline/Text") or "",
        "places": places,
    }

def bousai_warnings_detail(entry):
    """Parsed XML of a feed entry (cached six hours, the documents never change); None when unavailable."""
    key = BOUSAI_WARNINGS_XML_KEY + entry["href"].split("/")[-1]
    cached = cache.get(key)
    if cached:
        return json.decode(cached, default = None)
    body = bousai_get_bytes(entry["href"], ttl = 3600)
    if body == None:
        return None
    detail = bousai_warnings_parse_bulletin(body)
    if detail != None:
        cache.set(key, json.encode(detail), ttl_seconds = 6 * 3600)
    return detail

def bousai_warnings_area_hit(area, codes):
    """How the area codes of a bulletin relate to an area: "city", "region" or "" (no match).

    7-digit codes are municipalities: a bulletin that lists municipalities matches only when the area's own
    (same 5-digit municipality stem) is listed. Otherwise 6-digit class15 / class10 / prefecture-wide codes decide.
    """
    c20 = area.get("class20") or ""
    sevens = [c for c in codes if len(c) == 7]
    if sevens:
        for c in sevens:
            if c20 and c[:5] == c20[:5]:
                return "city"
        return ""
    for key in ["class15", "class10"]:
        if area.get(key) and area.get(key) in codes:
            return "region"
    office = area.get("office") or ""
    pref = area.get("pref") or ""
    for c in codes:
        if c == office or (len(c) == 6 and pref and c[:2] == pref and c[2:] == "0000"):
            return "region"
    return ""

def bousai_warnings_amount(cond, mm):
    """'About 120 mm/h' style text for an amount (JMA condition 約 / 以上) and millimetres of rain in one hour."""
    prefix = {"約": "About ", "以上": "Over "}.get(cond) or ""
    return "%s%s mm/h" % (prefix, mm)

def bousai_warnings_rain_lines(headline):
    """Places and amounts of a legacy record rain headline: [{name, mm, cond}] (names stay Japanese)."""
    out = []
    for raw in bousai_warnings_ascii(headline or "").split("\n"):
        line = raw.strip()
        i = line.find("ミリ")
        j = line.find("付近")
        if i <= 0 or j <= 0 or j > i:
            continue
        digits = ""
        for p in range(i - 1, -1, -1):
            if line[p] in "0123456789":
                digits = line[p] + digits
            else:
                break
        if not digits:
            continue
        cond = ""
        if line[:i].endswith(digits) and line[:i - len(digits)].endswith("約"):
            cond = "約"
        elif line[i:].startswith("ミリ以上"):
            cond = "以上"
        out.append({"name": line[:j], "mm": digits, "cond": cond})
    return out

def bousai_warnings_municipality(table, pref, name):
    """[code, English name] of the class20 area called `name` (Japanese) in a prefecture; longest prefix wins."""
    best = ["", ""]
    best_len = 0
    for code, c in (table.get("class20s") or {}).items():
        if code[:2] != pref:
            continue
        n = c.get("name") or ""
        if n and len(n) > best_len and (name == n or name.startswith(n)):
            best = [code, c.get("enName") or code]
            best_len = len(n)
    return best

def bousai_warnings_record_rain(detail, area, table):
    """[match, text] for a record rain bulletin and an area, or None when it does not concern the area.

    match is "city" (the area's own municipality is named; the text is just the amount) or "region" (elsewhere in
    its region / prefecture; the text names the place).
    """
    c20 = area.get("class20") or ""
    c10 = area.get("class10") or ""
    if detail["places"]:
        # New VPBS50 bulletin: class20 codes with the 1-hour analysed rainfall in the body.
        if "記録雨" not in detail["tags"]:
            return None
        city = None
        region = None
        for p in detail["places"]:
            code = p["code"]
            if c20 and code[:5] == c20[:5]:
                city = city or p
            elif table:
                c15 = (table.get("class20s") or {}).get(code, {}).get("parent") or ""
                if c10 and (table.get("class15s") or {}).get(c15, {}).get("parent") == c10:
                    region = region or p
        hit = city or region
        if hit == None:
            return None
        name = ""
        if city == None and table:
            name = (table.get("class20s") or {}).get(hit["code"], {}).get("enName") or ""
        text = bousai_warnings_amount(hit["cond"], bousai_warnings_ascii(hit["mm"]))
        return ["city" if city != None else "region", text + (" near " + name if name else "")]

    # Legacy VPOA50: area codes of the regions (class10 / prefecture) and the places in the Japanese headline.
    codes = detail["codes"]
    if not bousai_warnings_area_hit(area, codes):
        return None
    lines = bousai_warnings_rain_lines(detail["headline"])
    pref = area.get("pref") or ""
    city = None
    first = None
    for line in lines:
        if not table:
            break
        res = bousai_warnings_municipality(table, pref, line["name"])
        if not res[0]:
            continue
        line["en"] = res[1]
        first = first or line
        if c20 and res[0][:5] == c20[:5]:
            city = city or line
    hit = city or first
    if hit == None:
        return ["region", "Record heavy rain in " + bousai_warnings_region_name(area)]
    text = bousai_warnings_amount(hit["cond"], hit["mm"])
    return ["city", text] if city != None else ["region", text + " near " + hit["en"]]

def bousai_warnings_bulletin_notices(area, now, entries, details, table):
    """Pure matching step for tornado watch / record rain notices.

    entries are feed entries, details maps href -> parsed XML (bousai_warnings_parse_bulletin), table is the JMA
    area table (or None). Returns notices {kind_en, text_en, issued, sev} that are still valid at `now`.
    """
    pref = area.get("pref") or ""
    cancelled = {}
    for e in entries:
        d = details.get(e["href"])
        if d != None and d["info_type"] == "取消":
            t = bousai_parse_time(d["issued"]) or bousai_parse_time(e["updated"])
            key = e["kind"] + e["code"]
            if t != None and (cancelled.get(key) == None or t > cancelled[key]):
                cancelled[key] = t

    found = []
    for e in entries:
        d = details.get(e["href"])
        if d == None or e["code"][:2] != pref or d["info_type"] == "取消" or d["status"] in ["訓練", "試験"]:
            continue
        issued = bousai_parse_time(d["issued"]) or bousai_parse_time(e["updated"])
        if issued == None:
            continue
        cut = cancelled.get(e["kind"] + e["code"])
        if cut != None and cut > issued:
            continue
        if e["kind"] == "tornado":
            valid = bousai_parse_time(d["valid"]) if d["valid"] else issued + time.parse_duration("1h")
            if valid == None or now > valid or not bousai_warnings_area_hit(area, d["codes"]):
                continue
            text = "Until %s JST" % valid.in_location("Asia/Tokyo").format("15:04")
            sighted = bousai_warnings_area_hit(area, d.get("sight_codes") or []) if d.get("sight_codes") else ""
            if sighted:
                text = "Tornado seen. " + text
            found.append({"kind_en": "Tornado Watch", "text_en": text, "issued": issued, "sev": BOUSAI_WARNINGS_TORNADO_SEV, "key": "tornado" + e["code"], "rank": 1 if sighted else 0})
        else:
            if (now - issued).seconds > BOUSAI_WARNINGS_RECORD_RAIN_AGE:
                continue
            res = bousai_warnings_record_rain(d, area, table)
            if res == None:
                continue
            found.append({"kind_en": "Record Short-Term Heavy Rain", "text_en": res[1], "issued": issued, "sev": BOUSAI_WARNINGS_RECORD_RAIN_SEV, "key": "record" + res[1], "rank": 1 if res[0] == "city" else 0})

    # VPHW50 and VPHW51 are issued together for the same watch; keep the newest of each key, preferring the richer one.
    best = {}
    for n in found:
        cur = best.get(n["key"])
        if cur == None or (n["issued"], n["rank"]) > (cur["issued"], cur["rank"]):
            best[n["key"]] = n
    out = []
    for n in best.values():
        out.append({"kind_en": n["kind_en"], "text_en": n["text_en"], "issued": n["issued"], "sev": n["sev"]})
    return out

def bousai_warnings_notices(area):
    """Currently valid notices for an area (area = bousai_area(config) dict), most severe then newest first.

    Returns a list of dicts, [] when there are none, the area is None or the feeds are unavailable:
      kind_en  "Tornado Watch", "Record Short-Term Heavy Rain" or "River Flood <Advisory|Warning|Urgent Warning|
               Emergency Warning>"
      text_en  short English text (tornado: validity in JST; record rain: amount and place; flood: river count)
      issued   Pixlet time the bulletin was issued
      sev      2..5 index into ui["sev"]: tornado watch 3, record rain 4, river flood level // 10
    Tornado watch is kept while its XML ValidDateTime has not passed (about one hour), record rain for two
    hours after issue. Matching uses the municipality (class20), falling back to the class10 region.
    """
    if not area:
        return []
    out = bousai_warnings_flood_notices(bousai_get_json(BOUSAI_WARNINGS_FLOOD_URL, ttl = 60), area)
    entries = bousai_warnings_feed()
    if entries:
        now = time.now()
        pref = area.get("pref") or ""
        details = {}
        for e in entries:
            age = (now - bousai_parse_time(e["updated"])).seconds
            limit = BOUSAI_WARNINGS_TORNADO_MAX_AGE if e["kind"] == "tornado" else BOUSAI_WARNINGS_RECORD_RAIN_AGE
            if e["code"][:2] == pref and age <= limit:
                details[e["href"]] = bousai_warnings_detail(e)
        if details:
            wanted = [e for e in entries if details.get(e["href"]) != None]
            out.extend(bousai_warnings_bulletin_notices(area, now, wanted, details, bousai_area_table()))
    return sorted(out, key = lambda n: (-n["sev"], -n["issued"].unix))

# ---------------------------------------------------------------------------
# One place (location) for the app, and the demo sample

def bousai_warnings_place(area):
    """Everything the app shows for one location: {area, name, ok, current, notices}.

    ok is False when the r8 warning feed could not be read (the lists are then empty).
    """
    reports = bousai_warnings_reports(area.get("office"))
    items = []
    name = area.get("class20_en") or ""
    if reports != None:
        res = bousai_warnings_build(reports, area)
        items, name = res[0], res[1]
    return {"area": area, "name": name, "ok": reports != None, "current": items, "notices": bousai_warnings_notices(area)}

def bousai_warnings_sample_warning(element, element_en, level, minutes_ago, status, area_en):
    """One bousai_warnings_current()-shaped entry for the demo sample."""
    return {
        "element": element,
        "element_en": element_en,
        "level": level,
        "sev": level // 10,
        "label_en": "%s: %s" % (BOUSAI_WARNINGS_LEVEL_EN[level], element_en),
        "status": status,
        "issued": time.now() - time.parse_duration("%dm" % minutes_ago),
        "area_en": area_en,
    }

def bousai_warnings_demo():
    """Embedded sample for the demo toggle: [main place, saved place] shaped like bousai_warnings_place().

    Modelled on a July-2025-type prolonged heavy rain event, written in the 2026 level system: Lv4 Heavy Rain
    and Landslide urgent warnings, a Lv4 designated-river flood forecast and a record short-term heavy rain
    report, plus a Lv3 storm warning and Lv2 advisories. Not an actual bulletin; place names are fictional.
    """
    now = time.now()
    city = "Sample City"
    main = {
        "area": {"class20": "", "class20_en": city},
        "name": city,
        "ok": True,
        "current": [
            bousai_warnings_sample_warning("rain", "Heavy Rain", 40, 38, "Issued", city),
            bousai_warnings_sample_warning("landslide", "Landslide", 40, 22, "Issued", city),
            bousai_warnings_sample_warning("wind", "Storm", 30, 95, "Continued", city),
            bousai_warnings_sample_warning("wave", "High Wave", 20, 140, "Continued", city),
            bousai_warnings_sample_warning("thunder", "Thunderstorm", 20, 140, "Continued", city),
        ],
        "notices": [
            {"kind_en": "Record Short-Term Heavy Rain", "text_en": "About 110 mm/h", "issued": now - time.parse_duration("41m"), "sev": 4},
            {"kind_en": "River Flood Urgent Warning", "text_en": "2 rivers: flood danger", "issued": now - time.parse_duration("16m"), "sev": 4},
        ],
    }
    town = "Sample Town"
    saved = {
        "area": {"class20": "", "class20_en": town},
        "name": town,
        "ok": True,
        "current": [bousai_warnings_sample_warning("rain", "Heavy Rain", 30, 52, "Issued", town)],
        "notices": [],
    }
    return [main, saved]
