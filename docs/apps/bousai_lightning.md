# Bousai Lightning (`bousai_lightning`)

Lightning covers NERV's JMA Thunder Nowcast and LIDEN strike display. It shows JMA thunder activity around the selected location and optionally overlays recent cloud-to-ground and cloud-to-cloud detections.

<!-- BEGIN GENERATED: gallery -->
| ![Thunder nowcast at wide zoom with the tritanopia palette and high-contrast labels](../images/bousai_lightning-wide-tritan.webp)<br>*Thunder nowcast at wide zoom with the tritanopia palette and high-contrast labels* |
| :---: |
<!-- END GENERATED: gallery -->

## What it shows

The map loop has analysis frames at -30, -20 and -10 minutes, **Now**, then forecasts every 10 minutes to +60 minutes. Each map has a relative-time label and local clock. The **Thunder** key writes the JMA levels as `1 Possible`, `2 Thunder`, `3 Strong`, and `4 Violent`; it also explains that a square is cloud-to-ground (CG) and a cross is cloud-to-cloud (CC).

With **Show LIDEN strikes** enabled, analysis frames overlay the two preceding five-minute LIDEN files. The **Strikes** page gives the latest observation time, CG and CC counts within 50 km over 10 minutes, nearest-strike distance/bearing, and age where available. If strike files are unavailable it says **LIDEN offline** and **No strike data**. Empty frames say **No thunder**.

**Only when active** returns no output only when every thunder tile is blank and there are no displayed strike marks. With it off, the app remains in rotation and shows the clear-state map/status. It has no sample mode. It shows **Outside JMA thunder coverage** or **No thunder data from JMA now** when it cannot form the map. Zoom choices are City (~30 km), Prefecture (~90 km), Region (~250 km), and Wide (~500 km).

## Recommended Tronbyt setup

Use the manifest's 5-minute render interval. For alert behaviour, turn on **Only when active**, turn on Autopin, and use a 15-second Display Time; a visible thunder tile or strike can then take over the device until the next clear render. Leave Autopin and **Only when active** off when the normal clear-state loop is wanted. Prefecture zoom is the default; Wide is useful for approaching storms.

<!-- BEGIN GENERATED: settings -->
## Settings

| Setting | Default | Choices | Description |
|---|---|---|---|
| **Location** (`location`) | — | Map picker | Centre of the map. It chooses which map tiles are downloaded; coordinates are rounded locally to 0.001 degrees (about 100 m). Requested tiles reveal the selected map region. |
| **Show LIDEN strikes** (`strikes`) | On | On / Off | Mark cloud-to-ground (square) and cloud-to-cloud (cross) lightning detected in the last 10 minutes and count them as text. |
| **Only when active** (`only_when_active`) | Off | On / Off | Hide this app (so Tronbyt skips it) while no thunder activity or strike is on the map around you. Use AutoPin to bring it forward when thunder appears. |
| **Map zoom** (`zoom`) | Prefecture (~90 km) | City (~30 km) (`city`), Prefecture (~90 km) (`prefecture`), Region (~250 km) (`region`), Wide (~500 km) (`wide`) | How wide an area is shown around your location. |
| **Show my location** (`show_location`) | On | On / Off | Draw a marker at the centre of the map. |
| **Frame delay** (`delay`) | Normal | Fast (`300`), Normal (`500`), Slow (`900`) | How long each map frame stays on screen. |
| **Show colour key** (`legend`) | On | On / Off | End the loop with a text key that explains the JMA map colours. |

Plus the accessibility settings shared by every Bousai app — **Theme**, **Colour vision**, **Contrast**,
**Text size** and **Text weight**; see [Accessibility](../accessibility.md).

*This section is generated from the app's schema by `tools/gen_docs.py`.*
<!-- END GENERATED: settings -->

## How it works

JMA's N3 target-time index is cached for 60 seconds. From its newest analysis it selects the three preceding 10-minute analyses, Now, and available +10 to +60-minute forecasts. Thunder tiles use a 180-second cache while their base time is under 20 minutes old and a one-hour cache afterwards.

When strike marks are enabled, the app reads JMA LIDEN GeoJSON files for the 35 minutes through Now, newest first, using a 2.5 MB per-render parsing budget. Recent strike files use a 120-second cache; older files use one hour. The selected location is rounded locally and used only to centre tiles and calculate nearby strikes; this app has no municipality/area-code lookup. There is no page counter: frames, the strike page, and key make one duration-limited loop. All sources are JMA, so no guarded third-party fetch is used.

## Data sources

- Japan Meteorological Agency — Thunder Nowcast — `https://www.jma.go.jp/bosai/jmatile/data/nowc/targetTimes_N3.json` and `https://www.jma.go.jp/bosai/jmatile/data/nowc/<basetime>/<member>/<validtime>/surf/thns/{z}/{x}/{y}.png` — 出典：気象庁ホームページ.
- Japan Meteorological Agency — LIDEN lightning discharges — `https://www.jma.go.jp/bosai/jmatile/data/nowc/<validtime>/none/<validtime>/surf/liden/data.geojson` — 出典：気象庁ホームページ.
- Japan Meteorological Agency — coastline/prefecture mask — `https://www.jma.go.jp/bosai/jmatile/data/map/none/none/none/surf/mask/{z}/{x}/{y}.png` — 出典：気象庁ホームページ.

## Limitations

- JMA tile colours cannot be recoloured. Theme, colour-vision, contrast, text size, and text weight affect labels, keys, marks, and status text; activity levels and strike type are also written or shaped explicitly.
- **Only when active** tests the tiles and marks in the current view. A blank JMA tile is not proof that lightning cannot occur nearby, and a failed tile request stays visible rather than being treated as clear.
- LIDEN marks are limited to 40 CG and 40 CC marks per frame, and parsing stops after 2.5 MB.
- The display is render-time, not continuous monitoring; the 64×32 map cannot show precise strike geometry.
