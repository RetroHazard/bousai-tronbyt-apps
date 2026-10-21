# Bousai Warnings (`bousai_warnings`)

Shows JMA weather warnings for the configured municipality and up to five saved municipalities, plus nearby severe-weather notices. It covers the current-and-saved-location warning view of the NERV Disaster Prevention app feature set.

<!-- BEGIN GENERATED: gallery -->
| ![Sample heavy-rain event: Lv4 warnings, record short-term heavy rain, river flood notice and a saved place](../images/bousai_warnings-sample.webp)<br>*Sample heavy-rain event: Lv4 warnings, record short-term heavy rain, river flood notice and a saved place* | ![Lv4 and above only, high contrast, large bold text](../images/bousai_warnings-lv4-contrast.webp)<br>*Lv4 and above only, high contrast, large bold text* |
| :---: | :---: |
<!-- END GENERATED: gallery -->

## What it shows

- Cards group active weather elements at each level for the main location and then saved places. `Lv2 Advisory`, `Lv3 Warning`, `Lv4 Urgent Warning` and `Lv5 Emergency Warning` are written in the band, not conveyed by colour alone. Landslide is an element in the same level system.
- The warning card gives the element names, place and newest issue time. An element is shown once at its highest active level; `Gale` becomes `Storm` at Lv3 or above and `Gale and Snow` becomes `Snowstorm`.
- Separate notices can show a tornado watch (including its JST end time and eyewitness indication), record short-term heavy rain (amount and relevant place), and a designated-river flood forecast. River names are published only in Japanese, so the app shows a count such as `2 rivers: flood danger`, not names. A region-only match is labelled `Nearby`.
- With no item at or above the selected minimum, the normal view lists `No warnings`, the checked time and each calm saved place. A location outside Japan says that JMA data covers Japan only; an unavailable r8 feed says it is retrying; invalid saved codes appear as an `Unknown codes` card. **Alert only** returns nothing unless a qualifying warning or notice exists.
- **Show sample alert** is an illustrative July-2025-type heavy-rain event expressed in the 2026 level system: Lv4 Heavy Rain and Landslide, river-flood and record-rain notices, then a saved-place warning. It is not an actual bulletin.

## Recommended Tronbyt setup

Use **Render Interval Minutes** **1–5** (the manifest recommends **1**). For urgent use, choose **Alert only**, set **Minimum level** to **Urgent warning (Lv4)** or at least **Warning (Lv3)**, and enable **Autopin** so a qualifying card takes over the display and releases it afterwards. Keep Autopin off when showing advisory or calm cards. Use a **Display Time Seconds** value of 15 or more when monitoring saved places; each warning/notice card is held for at least 2.5 seconds, subject to the display-duration budget.

<!-- BEGIN GENERATED: settings -->
## Settings

| Setting | Default | Choices | Description |
|---|---|---|---|
| **Location** (`location`) | — | Map picker | Your location in Japan. Matched to a JMA municipality on the server using JMA's own area polygons; coordinates are never sent anywhere. |
| **JMA area code (optional)** (`area_override`) | — | Free text | 7-digit JMA municipality code (e.g. 1310100). Overrides the location lookup. |
| **Minimum level** (`min_level`) | Advisory (Lv2) | Advisory (Lv2) (`20`), Warning (Lv3) (`30`), Urgent warning (Lv4) (`40`), Emergency warning (Lv5) (`50`) | Hide warnings below this level. |
| **Alert only** (`alert_only`) | Off | On / Off | Skip this app unless something at or above the minimum level is active. Enable AutoPin in Tronbyt so it takes over the display, and set the minimum level to Warning (Lv3) or higher so advisories do not. |
| **Saved locations** (`saved_areas`) | — | Free text | Extra 7-digit JMA municipality codes, comma separated (for example 2710000, 4010000). Shown after your location. |
| **Show sample alert** (`demo`) | Off | On / Off | Show an embedded heavy-rain sample: Lv4 Heavy Rain and Landslide, river flood, record rain. |

Plus the accessibility settings shared by every Bousai app — **Theme**, **Colour vision**, **Contrast**,
**Text size** and **Text weight**; see [Accessibility](../accessibility.md).

*This section is generated from the app's schema by `tools/gen_docs.py`.*
<!-- END GENERATED: settings -->

## How it works

The app resolves the rounded configured location to a JMA class20 municipality using JMA area polygons; a 7-digit area-code override or saved codes select municipalities directly. It reads the new r8 warning feed for the responsible JMA office, preferring class20 data and falling back to class10 region data. The earlier warning feed was frozen on 2026-05-28; this app uses r8 instead. r8 warnings and river-flood data are cached for 60 seconds; the JMA `extra_l.xml` notice feed for 120 seconds; linked notice XML is requested with a 1-hour TTL and its parsed result is cached for 6 hours. Cards run in severity order inside the current display-duration budget; there is no persistent page counter. There are no third-party feeds.

## Data sources

- Japan Meteorological Agency — r8 weather warnings, advisories, urgent warnings, emergency warnings and landslide alerts — `https://www.jma.go.jp/bosai/warning/data/r8/<office>.json` — 出典：気象庁ホームページ.
- Japan Meteorological Agency — designated-river flood forecasts — `https://www.jma.go.jp/bosai/flood/data/r8/flood_xml.json` — 出典：気象庁ホームページ.
- Japan Meteorological Agency — long Atom feed and linked tornado-watch / record-rain XML reports — `https://www.data.jma.go.jp/developer/xml/feed/extra_l.xml` and its linked XML URLs — 出典：気象庁ホームページ.
- Japan Meteorological Agency — area names and municipality polygons — `https://www.jma.go.jp/bosai/common/const/area.json` and `https://www.jma.go.jp/bosai/common/const/geojson/class20s/<code>.json` — 出典：気象庁ホームページ.

## Limitations

- The river product supplies forecast areas and Japanese river names; the display counts matching rivers rather than translating or naming them. It does not show river-gauge water levels.
- Tornado and record-rain notices are short-lived and depend on the linked XML being available. Tornado watches remain only until their XML validity time; record rain remains for two hours.
- Municipality matching can fall back to a broader class10 region, so a notice can be nearby rather than specific to the municipality.
- This is not official warning equipment. Render timing, feed latency and the 64×32 display can delay or condense information.
