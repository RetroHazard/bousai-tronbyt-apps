# Bousai Risk Map (`bousai_risk`)

Risk Map covers NERV's Kikikuru heavy-rain risk map. It shows JMA landslide, inundation, or river-mesh flood risk around the configured location rather than a municipality warning list.

<!-- BEGIN GENERATED: gallery -->
| ![Landslide risk map at wide zoom with the previous hour of change](../images/bousai_risk-wide-landslide.webp)<br>*Landslide risk map at wide zoom with the previous hour of change* |
| :---: |
<!-- END GENERATED: gallery -->

## What it shows

Choose **Landslide**, **Inundation**, or **Flood (river mesh)**. The default timeline shows selected maps from the previous hour on a 20-minute grid followed by Now; **Now only** shows just the latest analysis. Each frame has a relative time and local clock. The status page writes the update time and whether `Lv2+ risk` is in the map region.

The optional key writes every Kikikuru class: `Lv2 Caution`, `Lv3 Warning`, `Lv4 Danger`, and `Lv5 Imminent`. A blank frame says **No Lv2+**. With **Only when active**, the app returns no output only when all selected tiles are blank; off, it remains in rotation and shows the no-risk state. There is no sample mode. It displays **Outside JMA Kikikuru coverage** or **No risk map from JMA now** when applicable. Zoom choices are City (~30 km), Prefecture (~90 km), Region (~250 km), and Wide (~500 km).

## Recommended Tronbyt setup

Use the manifest's 10-minute render interval. For an alert card, enable **Only when active**, enable Autopin, and use a 15-second Display Time. Use Landslide for slope risk, Inundation for urban/lowland surface-water risk, and Flood for JMA's river mesh. Wide or Region zoom makes a rare active area more likely to be visible; the default Prefecture zoom gives local context.

<!-- BEGIN GENERATED: settings -->
## Settings

| Setting | Default | Choices | Description |
|---|---|---|---|
| **Location** (`location`) | — | Map picker | Centre of the map. It chooses which map tiles are downloaded; coordinates are rounded locally to 0.001 degrees (about 100 m). Requested tiles reveal the selected map region. |
| **Risk type** (`element`) | Landslide | Landslide (`land`), Inundation (`inund`), Flood (river mesh) (`flood`) | Which Kikikuru risk map to show: landslide, inundation or flood (JMA's river mesh). |
| **Timeline** (`history`) | Last hour and now | Last hour and now (`hour`), Now only (`now`) | Show only the latest risk map, or also the last hour in 20 minute steps. |
| **Only when active** (`only_when_active`) | Off | On / Off | Hide this app (so Tronbyt skips it) while the risk map around you shows no Lv2 or higher area. Use AutoPin to bring it forward when a risk appears. |
| **Map zoom** (`zoom`) | Prefecture (~90 km) | City (~30 km) (`city`), Prefecture (~90 km) (`prefecture`), Region (~250 km) (`region`), Wide (~500 km) (`wide`) | How wide an area is shown around your location. |
| **Show my location** (`show_location`) | On | On / Off | Draw a marker at the centre of the map. |
| **Frame delay** (`delay`) | Normal | Fast (`300`), Normal (`500`), Slow (`900`) | How long each map frame stays on screen. |
| **Show colour key** (`legend`) | On | On / Off | End the loop with a text key that explains the JMA map colours. |

Plus the accessibility settings shared by every Bousai app — **Theme**, **Colour vision**, **Contrast**,
**Text size** and **Text weight**; see [Accessibility](../accessibility.md).

*This section is generated from the app's schema by `tools/gen_docs.py`.*
<!-- END GENERATED: settings -->

## How it works

JMA's Kikikuru target-time index is cached for 120 seconds. The app selects the latest tile and, for the history setting, available prior frames from the preceding hour at 20-minute positions. Member tiles cache for 180 seconds; other tiles use 180 seconds while the base time is under 20 minutes old and one hour afterwards. The renderer detects transparent JMA tiles, so a genuinely clear tile can produce the no-risk banner.

Location is rounded locally and only centres the map; this app has no municipality/area-code lookup. It does not use a render counter: map frames, the risk-status page, and the key run in one duration-limited sequence. Only JMA endpoints are used, with no guarded third-party fetch.

## Data sources

- Japan Meteorological Agency — Kikikuru landslide, inundation, and flood-risk target times and tiles — `https://www.jma.go.jp/bosai/jmatile/data/risk/targetTimes.json` and `https://www.jma.go.jp/bosai/jmatile/data/risk/<basetime>/<member>/<validtime>/surf/<land|inund|flood_mesh>/{z}/{x}/{y}.png` — 出典：気象庁ホームページ.
- Japan Meteorological Agency — coastline/prefecture mask — `https://www.jma.go.jp/bosai/jmatile/data/map/none/none/none/surf/mask/{z}/{x}/{y}.png` — 出典：気象庁ホームページ.

## Limitations

- `Lv2+` describes map pixels in the current region, not an official warning issued for the configured municipality. Use Bousai Warnings for warning products.
- JMA map colours cannot be recoloured. Theme, colour-vision, contrast, text size, and text weight affect labels, key, marker, and status text; every level is written as text.
- **Only when active** does not hide on failed requests, and map-tile coverage is coarser than the exact 64×32 viewport.
- Renders update in rotation. Feed and cache latency, the selected zoom, and the 64×32 map limit the time and spatial precision.
