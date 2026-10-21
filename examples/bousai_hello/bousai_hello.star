"""
Applet: Bousai Hello
Summary: Minimal JMA forecast example
Description: A small example app that resolves a Tronbyt location to a JMA area and shows the first daily weather code from JMA's official forecast feed in English.
Author: Bousai Apps
"""

# bousai: requires core data

# JMA publishes the daily/weekly forecast as one JSON file per meteorological office.
HELLO_FORECAST_URL = "https://www.jma.go.jp/bosai/forecast/data/forecast/%s.json"


def hello_forecast(area):
    """Return the first daily weather code for this area's class10 region, or None."""
    data = bousai_get_json(HELLO_FORECAST_URL % area["office"], ttl = 600)
    if type(data) != "list" or len(data) == 0 or type(data[0]) != "dict":
        return None

    # The first response item is the three-day forecast. Its first time series
    # contains one weatherCodes list for each JMA class10 forecast area.
    daily = data[0]
    series = daily.get("timeSeries") or []
    if len(series) == 0 or type(series[0]) != "dict":
        return None
    for item in series[0].get("areas") or []:
        if type(item) != "dict":
            continue
        if (item.get("area") or {}).get("code") != area["class10"]:
            continue
        codes = item.get("weatherCodes") or []
        if codes:
            return {
                "code": str(codes[0]),
                "report": daily.get("reportDatetime") or "",
            }
    return None


def hello_weather_name(code):
    """Use the generated JMA English weather-code table, with a useful fallback."""
    entry = BOUSAI_WEATHER_EN.get(code)
    return entry[0] if entry else "Weather code " + code


def main(config):
    # bousai_ui reads the accessibility settings added by bousai_schema.
    ui = bousai_ui(config)

    # Match the core's JMA coverage bounds before resolving polygons. An explicit
    # JMA-area override remains usable even when the map location is elsewhere.
    location = bousai_location(config)
    override = (config.get("area_override") or "").strip()
    if not override and (location["lat"] < 20.0 or location["lat"] > 46.5 or location["lon"] < 122.0 or location["lon"] > 154.5):
        return bousai_message(ui, "Bousai Hello", ["Outside Japan", "Choose a JMA location"])

    # Check the shared JMA area table separately. This distinguishes a feed-down
    # state from a point (or area-code override) that cannot resolve to an area.
    if bousai_area_table() == None:
        return bousai_message(ui, "Bousai Hello", ["JMA area data", "is unavailable"])
    area = bousai_area(config)
    if area == None:
        return bousai_message(ui, "Bousai Hello", ["No JMA area", "Check location or code"])

    forecast = hello_forecast(area)
    if forecast == None:
        # A non-200 response, bad JSON, or a changed/missing local entry all
        # become the same feed-down screen. Starlark has no try/except.
        return bousai_message(ui, "Bousai Hello", ["JMA forecast", "is unavailable"])

    updated = bousai_parse_time(forecast["report"])
    rows = [
        ("Area: " + area["class20_en"], ui["fg"]),
        ("Forecast: " + area["class10_en"], ui["muted"]),
        ("Today: " + hello_weather_name(forecast["code"]), ui["accent"]),
    ]
    if updated:
        rows.append(("Updated " + bousai_hhmm(updated) + " JST", ui["muted"]))

    # bousai_pages paginates at each configured text size; bousai_root applies
    # the selected theme and the shared 100 ms animation cadence.
    return bousai_root(ui, bousai_pages(ui, ("Bousai Hello", ui["accent"]), rows))


def get_schema():
    # This adds Location, optional JMA-area override, and every standard
    # accessibility control. There are no example-specific settings.
    return bousai_schema([])
