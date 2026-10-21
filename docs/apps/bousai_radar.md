# Bousai Rain Radar (`bousai_radar`)

Rain Radar covers NERV's observed-rain and rain-outlook feature with JMA raster maps centred on the configured location. It combines radar frames with nearby AMeDAS rain-gauge text so the display remains interpretable at 64×32.

<!-- BEGIN GENERATED: gallery -->
| ![Rain radar timeline at wide zoom, with light theme and bold labels](../images/bousai_radar-wide-light.webp)<br>*Rain radar timeline at wide zoom, with light theme and bold labels* |
| :---: |
<!-- END GENERATED: gallery -->

## What it shows

The loop is: radar maps, the **Rain gauges** text page, then the optional **Rain** colour key. The default timeline shows observed radar for the past hour, a 10-minute nowcast to +1 h, and hourly outlook frames at +3, +6, +9, +12 and +15 h. The timeline setting can instead show the past hour plus the 10-minute nowcast, or Now plus hourly +1 to +6 h. Map labels give relative time and local clock time.

The gauge page reports the latest AMeDAS 10-minute reading within 40 km: nearby wet-gauge count and maximum when rain is present, or the nearest gauge and its 10-minute and, when available, one-hour amount. The key writes every JMA rain class as text: `<1`, `1-5`, `5-10`, `10-20`, `20-30`, `30-50`, `50-80`, and `80+` mm/h. A blank map says **No rain**. There is no alert-only or sample mode; the app remains in rotation. It displays **Outside JMA radar coverage** or **No radar data from JMA now** instead of a map when applicable.

Map zoom is City (~30 km), Prefecture (~90 km), Region (~250 km), or Wide (~500 km). The optional centre cross marks the configured location.

## Recommended Tronbyt setup

Use the manifest's 5-minute render interval, Autopin off, and a 15-second Display Time for the normal full loop. Choose the default timeline for context, or the nowcast timeline when short-term rain is the priority. Use Region or Wide zoom where a broad rain band matters; City or Prefecture gives local detail.

<!-- BEGIN GENERATED: settings -->
## Settings

| Setting | Default | Choices | Description |
|---|---|---|---|
| **Location** (`location`) | — | Map picker | Centre of the map. It chooses which map tiles are downloaded; coordinates are rounded locally to 0.001 degrees (about 100 m). Requested tiles reveal the selected map region. |
| **Timeline** (`mode`) | Past hour, next hour, 15 h outlook | Past hour, next hour, 15 h outlook (`full`), Past hour and next hour (10 min) (`nowcast`), Now and the next 6 hours (hourly) (`hourly`) | Which part of the rain timeline to animate: observed radar, the one-hour nowcast and the hourly forecast. |
| **Map zoom** (`zoom`) | Prefecture (~90 km) | City (~30 km) (`city`), Prefecture (~90 km) (`prefecture`), Region (~250 km) (`region`), Wide (~500 km) (`wide`) | How wide an area is shown around your location. |
| **Show my location** (`show_location`) | On | On / Off | Draw a marker at the centre of the map. |
| **Frame delay** (`delay`) | Normal | Fast (`300`), Normal (`500`), Slow (`900`) | How long each map frame stays on screen. |
| **Show colour key** (`legend`) | On | On / Off | End the loop with a text key that explains the JMA map colours. |

Plus the accessibility settings shared by every Bousai app — **Theme**, **Colour vision**, **Contrast**,
**Text size** and **Text weight**; see [Accessibility](../accessibility.md).

*This section is generated from the app's schema by `tools/gen_docs.py`.*
<!-- END GENERATED: settings -->

## How it works

The app requests JMA N1 and N2 nowcast target-time indexes every 60 seconds and the hourly rain-forecast index every 300 seconds. Tiles based less than 20 minutes ago cache for 180 seconds; older tiles cache for an hour. It selects the closest published tile zoom that needs at most three tiles, draws JMA coast/prefecture masking, and detects JMA's transparent no-data tiles.

Location is rounded locally and used only as the centre for map and AMeDAS requests; this app has no municipality/area-code lookup. AMeDAS checks `latest_time.txt` for 60 seconds, the observation map for 300 seconds, and the station table for one day. There is no render-to-render page counter: the selected frames, gauge page, and key form one loop, trimmed to the display-duration budget with newest frames retained. All feeds are JMA; no guarded third-party fetch is used.

## Data sources

- Japan Meteorological Agency — High-resolution precipitation nowcast — `https://www.jma.go.jp/bosai/jmatile/data/nowc/targetTimes_N1.json`, `.../targetTimes_N2.json`, and `.../nowc/<basetime>/<member>/<validtime>/surf/hrpns/{z}/{x}/{y}.png` — 出典：気象庁ホームページ.
- Japan Meteorological Agency — Hourly precipitation forecast — `https://www.jma.go.jp/bosai/jmatile/data/rasrf/targetTimes.json` and `.../rasrf/<basetime>/<member>/<validtime>/surf/rasrf/{z}/{x}/{y}.png` — 出典：気象庁ホームページ.
- Japan Meteorological Agency — AMeDAS observations and station table — `https://www.jma.go.jp/bosai/amedas/data/latest_time.txt`, `.../data/map/<YYYYMMDDhhmmss>.json`, and `.../const/amedastable.json` — 出典：気象庁ホームページ.
- Japan Meteorological Agency — coastline/prefecture mask — `https://www.jma.go.jp/bosai/jmatile/data/map/none/none/none/surf/mask/{z}/{x}/{y}.png` — 出典：気象庁ホームページ.

## Limitations

- JMA raster colours cannot be recoloured. Theme, colour-vision, contrast, text size, and text weight affect labels, keys, markers, and status text; the classes are also written as text.
- A tile is a regional indication, not a point measurement. Gauge values can be unavailable, and the nearest reporting gauge can be up to 40 km away.
- A render updates only when the app comes up in rotation. Times reflect JMA data availability and cached tiles, not a continuously updating display.
- Maps, labels, and the eight-entry key are constrained by a 64×32 display.
