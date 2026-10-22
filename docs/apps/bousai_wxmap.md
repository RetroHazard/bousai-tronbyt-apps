# Bousai Weather Map (`bousai_wxmap`)

Weather Map covers NERV's 5 km weather-distribution forecast. It animates JMA weather, temperature, three-hour rain, or three-hour snow forecasts around the configured location. Every frame carries a top bar with a kanji weekday, the time, the regional forecast weather and temperature, and a JMA colour-scale strip along the bottom; the loop is map frames only.

<!-- BEGIN GENERATED: gallery -->
| ![Temperature forecast at regional zoom with light, extra-large bold labels](../images/bousai_wxmap-temperature-light.webp)<br>*Temperature forecast at regional zoom with light, extra-large bold labels* |
| :---: |
<!-- END GENERATED: gallery -->

## What it shows

Choose **Weather**, **Temperature**, **Rain, 3 hours**, or **Snow, 3 hours**. The app takes the current and later three-hourly target frames, up to 14 frames toward midnight of the next day. Each map frame has one opaque 6-pixel top bar: the weekday as a single hand-drawn kanji (日 月 火 水 木 金 土, 5×6 pixels), the hour, the regional forecast weather (`Clr`, `Cldy`, `Rain`, `R/S` for rain or snow, or `Snow`), and the forecast temperature in C pinned to the right edge, as in `木15h Cldy` … `21C`. Rain and snow frames show the three-hour ending window and the forecast weather for that same window instead of the hour, as in `木12-15h Rain` … `21C`; the temperature is the forecast for the end of the window. At larger text sizes only the hour/weather text scrolls; the weekday and temperature stay fixed. Along the bottom of every map frame a black-outlined strip shows the selected layer's JMA colours left to right in key order as one smooth gradient: the first and last colours sit at the ends and every pixel between two neighbouring colours is linearly interpolated.

The loop is map frames only; there are no Forecast-area or colour-key text pages (for observations use the [AMeDAS app](bousai_amedas.md)). The strip classes are: weather `Clear`, `Cloudy`, `Rain`, `Rain/snow`, `Snow`; temperature `40+` down to `<-25` C; rain `20+` down to `1-5` mm/3h; snow `6+` down to `1-3` cm/3h. A blank map says **No data** in the top bar when there is no forecast text for that frame. The app stays in rotation, has no sample mode, and reports **Outside JMA forecast grid** or **No forecast map from JMA now** instead of map frames when needed. Zoom choices are City (~30 km), Prefecture (~90 km), Region (~250 km), and Wide (~500 km); Region is the default.

## Recommended Tronbyt setup

Use the manifest's 15-minute render interval, Autopin off, and a 15-second Display Time. Weather is the default general-purpose layer; Temperature adds the forecast temperature to the top bar, while the rain/snow layers show each three-hour accumulation window. Region zoom gives the normal forecast context; use Prefecture zoom for local detail.

<!-- BEGIN GENERATED: settings -->
## Settings

| Setting | Default | Choices | Description |
|---|---|---|---|
| **Location** (`location`) | — | Map picker | Centre of the map. It chooses which map tiles are downloaded; coordinates are rounded locally to 0.001 degrees (about 100 m). Requested tiles reveal the selected map region. |
| **Layer** (`element`) | Weather | Weather (`wm`), Temperature (`temp`), Rain, 3 hours (`r3`), Snow, 3 hours (`s3`) | Weather, temperature, 3-hour rain or 3-hour snow forecast on JMA's 5 km grid. |
| **Map zoom** (`zoom`) | Region (~250 km) | City (~30 km) (`city`), Prefecture (~90 km) (`prefecture`), Region (~250 km) (`region`), Wide (~500 km) (`wide`) | How wide an area is shown around your location. |
| **Show my location** (`show_location`) | On | On / Off | Draw a marker at the centre of the map. |
| **Frame delay** (`delay`) | Normal | Fast (`300`), Normal (`500`), Slow (`900`) | How long each map frame stays on screen. |

Plus the accessibility settings shared by every Bousai app — **Theme**, **Colour vision**, **Contrast**,
**Text size** and **Text weight**; see [Accessibility](../accessibility.md).

*This section is generated from the app's schema by `tools/gen_docs.py`.*
<!-- END GENERATED: settings -->

## How it works

The weather-distribution target-time index is cached for 600 seconds. The app keeps entries no older than 90 minutes, takes the first 14, and caches fresh-base tiles for 180 seconds and older tiles for one hour. The configured point is matched locally to a JMA first-forecast-area polygon cached for seven days. That area code fetches `wdist/VPFD/<code>.json`, cached for 900 seconds, for the top-bar weather/temperature text.

The location is rounded locally and used for tiles and the first-forecast-area polygon; it is not a municipality/area-code setting. The map frames run as one duration-limited loop rather than a counter-driven rotation. All fetches are JMA; no guarded third-party request is used.

## Data sources

- Japan Meteorological Agency — weather-distribution forecast target times and 5 km tiles — `https://www.jma.go.jp/bosai/jmatile/data/wdist/targetTimes.json` and `https://www.jma.go.jp/bosai/jmatile/data/wdist/<basetime>/<member>/<validtime>/surf/<wm|temp|r3|s3>/{z}/{x}/{y}.png` — 出典：気象庁ホームページ.
- Japan Meteorological Agency — first forecast area polygons and regional three-hourly forecast — `https://www.jma.go.jp/bosai/jmatile/data/map/none/none/none/surf/click_first_area/data.geojson` and `https://www.jma.go.jp/bosai/jmatile/data/wdist/VPFD/<area-code>.json` — 出典：気象庁ホームページ.
- Japan Meteorological Agency — coastline/prefecture mask — `https://www.jma.go.jp/bosai/jmatile/data/map/none/none/none/surf/mask/{z}/{x}/{y}.png` — 出典：気象庁ホームページ.

## Limitations

- The map is a gridded JMA forecast, not a street-level forecast; top-bar weather/temperature text may be unavailable when the regional feed has no matching time or term.
- JMA tile colours cannot be recoloured; the bottom strip interpolates between them, so only the end colours appear exactly and the strip shows the scale rather than an exact match for each class. Theme, colour-vision, contrast, text size, and text weight affect the top bar and marker. The strip is a colour cue only and the classes are not written out on the device; the top bar's weather and temperature text is the non-colour cue.
- The kanji weekdays are hand-drawn 5×6 bitmaps; 水 and 金 are approximations at that size. At larger text sizes the glyph stays at 6 pixels beside the bigger text.
- Areas outside JMA's forecast grid (open sea at wider zooms or near the grid edge) are transparent in JMA's tiles and show the plain background.
- Rendering and cache timing add delay, and the 64×32 display limits map detail.
