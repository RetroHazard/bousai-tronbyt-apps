# Feature coverage

[Back to README](../README.md)

Reference: the [NERV Disaster Prevention app's about page](https://nerv.app/en/about.html).
Bousai is an independent implementation for a 64×32 display, not a port of NERV or a replacement for its service.
The comparison describes display features, **not equivalent delivery speed, reliability or safety certification**.

| Reference feature | Bousai app | Scope / difference |
|---|---|---|
| EEW forecasts and warnings, multiple events | [EEW](apps/bousai_eew.md) | Relayed JMA information; events cycle rather than a touch interface. No push delivery. |
| Estimated intensity at your location and S-wave countdown | [EEW](apps/bousai_eew.md), [Home](apps/bousai_home.md) | Unofficial estimate using Si & Midorikawa PGV / intensity relationships and JMA2001 travel-time data. Render-time countdown, not a continuously connected timer. |
| Strong-Motion Monitor, P/S waves and intensity overlay | [Shake](apps/bousai_shake.md) | NIED images for private display use; no imagery redistributed in this repository. |
| Shaking detection | [Shake](apps/bousai_shake.md), [Home](apps/bousai_home.md) | P2PQuake user-report evaluation, not NERV's proprietary detector. Unconfirmed reports are not instrument observations. |
| Intensity flash, epicentre and detailed area reports | [Quake](apps/bousai_quake.md) | National reports plus local intensity, tsunami comment and map. |
| Estimated intensity distribution | [Quake](apps/bousai_quake.md) | JMA mesh images when issued; reduced to the LED resolution. |
| Nankai Trough / Hokkaido-Sanriku information | [Quake](apps/bousai_quake.md), [Home](apps/bousai_home.md) | Dedicated information cards. |
| Tsunami warnings, arrival times/heights, high tide and observations (including offshore) | [Tsunami](apps/bousai_tsunami.md) | Static coast map and pages instead of an interactive map. Active-warning paths were sample-tested, not observed live during development. |
| Volcano levels and warnings, eruption flash and ashfall | [Volcano](apps/bousai_volcano.md) | Eruption-flash and ashfall paths were sample-tested, not observed live during development. |
| Observed rain and forecasts to 15 hours | [Radar](apps/bousai_radar.md) | Animated JMA tiles. |
| Local and saved-place weather warnings | [Warnings](apps/bousai_warnings.md) | JMA's May 2026 Lv2–Lv5 system, including landslide. |
| Landslide / inundation / flood risk map | [Risk](apps/bousai_risk.md) | JMA Kikikuru tiles, with level text. |
| Designated river flood forecasts | [Warnings](apps/bousai_warnings.md) | River notices are counted; river names are only supplied in Japanese. Not live-observed during development. |
| River gauge water levels | — | Not implemented. No supported free, documented gauge-data feed was identified; JMA is not the river-gauge data provider. |
| Typhoon analysis and five-day forecast | [Typhoon](apps/bousai_typhoon.md) | Strength, pressure, wind/gust, movement, distance, track and probability circles. |
| Synoptic weather charts | — | Not implemented: isobars/fronts and chart labels are not useful at 64×32. Forecast text and weather maps cover some related information, not the charts themselves. |
| English forecasts, summary, sunrise/sunset, three-hourly and seven-day views | [Forecast](apps/bousai_forecast.md) | JMA's own English text and weather codes; no machine translation service. |
| Five-kilometre weather distribution forecasts | [Weather Map](apps/bousai_wxmap.md) | Weather, temperature, three-hour rain and snow. |
| Ten-minute AMeDAS observations | [AMeDAS](apps/bousai_amedas.md) | Nearest or overridden station; not all stations measure every field. |
| Thunder nowcast and LIDEN lightning | [Lightning](apps/bousai_lightning.md) | Includes cloud-to-ground and cloud-to-cloud strikes. |
| Snow depth, analysed and forecast snowfall | [Snow](apps/bousai_snow.md) | JMA snow tiles and available nearby gauges. |
| Tornado nowcast / watch information | [Tornado](apps/bousai_tornado.md), [Warnings](apps/bousai_warnings.md) | Map levels and textual notices are distinct products. |
| J-ALERT national protection messages | — | Not implemented: no supported public machine-readable feed was identified for armed-attack/terrorism messages. |
| Prioritised home panel | [Home](apps/bousai_home.md) | Prioritises enabled sources by severity, class and age; lower-priority items may be omitted or rotated. |
| Past 72-hour timeline, including warnings lifted | [Timeline](apps/bousai_timeline.md) | JMA Atom/XML history; history fills over renders within a fetch budget. |
| Notifications by urgency | Tronbyt Autopin | No sound or mobile push notifications. Apps must hide while idle; [setup](installation.md#alerts-autopin-and-render-intervals). |
| Crisis Mapping / community shelter reports | — | Not implemented: the NERV-hosted user-posting service is not a public data feed, and the LED has no posting interface. |
| Theme, colour-vision palette, contrast, size and weight | [All apps](accessibility.md) | Text labels supplement colours. Provider raster maps retain their original colours. |
| Screen-reader layout | — | Not provided by an image-only LED matrix. |
| English / Japanese interface | English only | English JMA dictionaries are used. No CJK font is bundled for a Japanese app UI. |
| Location privacy | [All apps](data-sources.md#privacy) | Area lookup happens on the server. Providers see area/station/product requests or tile coordinates; not a blanket claim of location anonymity. |
| Mobile widgets, Supporters' Club | — | Not applicable to this display software. |

## Verification boundary

The suite has been rendered against live feeds and illustrative sample modes with Pixlet v0.55.0.
EEW active reports, tsunami warnings, eruption flashes, ashfall, river-flood and record-rain notices were not all
observed live during development. Sample renders exercise layouts and parsing examples; they do not prove real-world
alert delivery. No claim of official warning-equipment status is made.
