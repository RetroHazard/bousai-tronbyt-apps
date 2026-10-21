# Data sources and privacy

Bousai is not official warning equipment. The app software is Apache-2.0, but that license does **not** grant rights to redistribute the data, images or other source material below. Follow each provider's terms and use official channels for safety decisions.

## Source reference

The source inventory was made with:

```sh
grep -RIn 'http' src/lib/*.star src/apps/*/*.star
```

The command finds URL literals and HTTP call sites. The table also records URL patterns built from those literals (for example, report files and slippy-map tiles). TTL is the HTTP cache time in the code; `fresh/old` means the TTL is selected from the data timestamp. Apps listed are direct users and apps that include the stated domain library.

All JMA rows carry the attribution **出典：気象庁ホームページ** and are subject to the [JMA terms of use](https://www.jma.go.jp/jma/kishou/info/coment.html).

| Provider and product | URL pattern | Apps | Cache TTL | Attribution / terms |
| --- | --- | --- | --- | --- |
| JMA — common area metadata | `https://www.jma.go.jp/bosai/common/const/area.json` | eew, forecast, home, quake, timeline, warnings | 1 day | 出典：気象庁ホームページ; [JMA terms](https://www.jma.go.jp/jma/kishou/info/coment.html) |
| JMA — municipality bounds for local area resolution | `https://www.jma.go.jp/bosai/common/const/class20relm.json`; `https://www.jma.go.jp/bosai/common/const/geojson/class20s/<class20>.json` | eew, forecast, home, quake, timeline, warnings | 1 day; 30 days | 出典：気象庁ホームページ; [JMA terms](https://www.jma.go.jp/jma/kishou/info/coment.html) |
| JMA — forecast data and constants | `https://www.jma.go.jp/bosai/forecast/data/forecast/<office>.json`; `https://www.jma.go.jp/bosai/forecast/const/week_area.json`; `https://www.jma.go.jp/bosai/forecast/const/en_amedas.json` | forecast, home | 10 min; 1 day; 1 day | 出典：気象庁ホームページ; [JMA terms](https://www.jma.go.jp/jma/kishou/info/coment.html) |
| JMA — regional three-hour forecast | `https://www.jma.go.jp/bosai/jmatile/data/wdist/VPFD/<class10>.json` | forecast, home, wxmap | 10 min in forecast/home; 15 min in wxmap | 出典：気象庁ホームページ; [JMA terms](https://www.jma.go.jp/jma/kishou/info/coment.html) |
| JMA — official English forecast | `https://www.data.jma.go.jp/multi/data/VPFD51/<office>_en.json` | forecast, home | 10 min | 出典：気象庁ホームページ; [JMA terms](https://www.jma.go.jp/jma/kishou/info/coment.html) |
| JMA — AMeDAS station and point observations | `https://www.jma.go.jp/bosai/amedas/const/amedastable.json`; `https://www.jma.go.jp/bosai/amedas/data/latest_time.txt`; `https://www.jma.go.jp/bosai/amedas/data/point/<station>/<YYYYMMDD_HH>.json`; `https://www.jma.go.jp/bosai/amedas/data/map/<timestamp>.json` | amedas, forecast, home, radar, snow, wxmap | station table 1 day; marker 1 min; newest point block 2 min; older point blocks 1 h; map 5 min | 出典：気象庁ホームページ; [JMA terms](https://www.jma.go.jp/jma/kishou/info/coment.html) |
| JMA — JMA tile indexes | `https://www.jma.go.jp/bosai/jmatile/data/nowc/targetTimes_N1.json`; `.../nowc/targetTimes_N2.json`; `.../nowc/targetTimes_N3.json`; `.../rasrf/targetTimes.json`; `.../risk/targetTimes.json`; `.../snow/targetTimes.json`; `.../wdist/targetTimes.json` | radar, lightning, tornado, risk, snow, wxmap | nowcast 1 min; risk 2 min; rain/snow 5 min; weather distribution 10 min | 出典：気象庁ホームページ; [JMA terms](https://www.jma.go.jp/jma/kishou/info/coment.html) |
| JMA — raster map products | `https://www.jma.go.jp/bosai/jmatile/data/<kind>/<basetime>/<member>/<validtime>/surf/<element>/<z>/<x>/<y>.png` where kinds are `nowc`, `rasrf`, `risk`, `snow`, `wdist`; elements include `hrpns`, `thns`, `trns`, `land`, `inund`, `flood_mesh`, snow and weather-distribution elements | radar, lightning, tornado, risk, snow, wxmap | fresh base time 3 min; older tiles 1 h; risk ensemble member 3 min | 出典：気象庁ホームページ; [JMA terms](https://www.jma.go.jp/jma/kishou/info/coment.html) |
| JMA — map mask and first-forecast-area geometry | `https://www.jma.go.jp/bosai/jmatile/data/map/none/none/none/surf/mask/<z>/<x>/<y>.png`; `https://www.jma.go.jp/bosai/jmatile/data/map/none/none/none/surf/click_first_area/data.geojson` | quake, tsunami, typhoon, volcano, radar, lightning, tornado, risk, snow, wxmap | mask 7 days; first-area geometry 7 days | 出典：気象庁ホームページ; [JMA terms](https://www.jma.go.jp/jma/kishou/info/coment.html) |
| JMA — LIDEN lightning strikes | `https://www.jma.go.jp/bosai/jmatile/data/nowc/<validtime>/none/<validtime>/surf/liden/data.geojson` | lightning | newest 20 min: 2 min; older files: 1 h | 出典：気象庁ホームページ; [JMA terms](https://www.jma.go.jp/jma/kishou/info/coment.html) |
| JMA — earthquake reports and estimated-intensity meshes | `https://www.jma.go.jp/bosai/quake/data/list.json`; `https://www.jma.go.jp/bosai/quake/data/<report>.json`; `https://www.jma.go.jp/bosai/estimated_intensity_map/data/list.json`; `https://www.jma.go.jp/bosai/estimated_intensity_map/data/<event>/<mesh>.png` | quake, home, timeline | list 30 s; report 1 day; estimated-map list 5 min; mesh 7 days | 出典：気象庁ホームページ; [JMA terms](https://www.jma.go.jp/jma/kishou/info/coment.html) |
| JMA — earthquake special-information English data | `https://www.data.jma.go.jp/multi/data/VYSE50/en.json`; `https://www.data.jma.go.jp/multi/data/VYSE60/en.json`; `https://www.data.jma.go.jp/multi/data/other/temporary_info_config.json` | quake, home | 2 min; 2 min; 1 day | 出典：気象庁ホームページ; [JMA terms](https://www.jma.go.jp/jma/kishou/info/coment.html) |
| JMA — tsunami reports and coastlines | `https://www.jma.go.jp/bosai/tsunami/data/list.json`; `https://www.jma.go.jp/bosai/tsunami/data/clearweb.json`; `https://www.jma.go.jp/bosai/tsunami/data/<report>.json`; `https://www.jma.go.jp/bosai/common/const/geojson/tsunami.json` | tsunami, home, timeline | list/clear 30 s; report 1 day; coastline 7 days | 出典：気象庁ホームページ; [JMA terms](https://www.jma.go.jp/jma/kishou/info/coment.html) |
| JMA — tropical-cyclone analysis and forecast | `https://www.jma.go.jp/bosai/typhoon/data/targetTc.json`; `https://www.jma.go.jp/bosai/typhoon/data/<tc>/specifications.json`; `https://www.jma.go.jp/bosai/typhoon/data/<tc>/forecast.json` | typhoon, home, timeline | target list 5 min; analysis/forecast 10 min | 出典：気象庁ホームページ; [JMA terms](https://www.jma.go.jp/jma/kishou/info/coment.html) |
| JMA — volcanic warning, eruption and ashfall data | `https://www.jma.go.jp/bosai/volcano/data/warning.json`; `.../eruption.json`; `.../eruption/<event>.json`; `.../ashfall/japan.json`; `.../ashfall/<volcano>.json`; `https://www.data.jma.go.jp/multi/data/VFVO50/en.json` | volcano, home, timeline | warning 1 min; eruption list 30 s; event and ashfall 5 min; English data 10 min | 出典：気象庁ホームページ; [JMA terms](https://www.jma.go.jp/jma/kishou/info/coment.html) |
| JMA — weather warning, flood and bulletin feeds | `https://www.jma.go.jp/bosai/warning/data/r8/<office>.json`; `https://www.jma.go.jp/bosai/flood/data/r8/flood_xml.json`; `https://www.data.jma.go.jp/developer/xml/feed/extra_l.xml`; linked JMA XML documents | warnings, home, timeline | warning/flood 1 min; Atom feed 2 min; linked documents 1 h (parsed warning summary also caches 6 h) | 出典：気象庁ホームページ; [JMA terms](https://www.jma.go.jp/jma/kishou/info/coment.html) |
| JMA — earthquake/volcano Atom feed | `https://www.data.jma.go.jp/developer/xml/feed/eqvol_l.xml`; linked JMA XML documents | timeline | feed 2 min; linked documents 1 h (parsed summary 5 days) | 出典：気象庁ホームページ; [JMA terms](https://www.jma.go.jp/jma/kishou/info/coment.html) |
| Wolfx — relayed JMA EEW | `https://api.wolfx.jp/jma_eew.json` | eew, shake, home | 1 s; guarded-host cooldown 2 min after a failed render | [Wolfx API endpoint](https://api.wolfx.jp/jma_eew.json); use subject to the provider's current terms |
| NIED — Kyoshin Monitor EEW and image layers | `http://www.kmoni.bosai.go.jp/webservice/server/pros/latest.json`; `.../webservice/hypo/eew/<timestamp>.json`; `.../data/map_img/CommonImg/base_map_<b|w>.gif`; `.../RealTimeImg/jma_s/<YYYYMMDD>/<timestamp>.jma_s.gif`; `.../EstShindoImg/eew/<YYYYMMDD>/<timestamp>.eew.gif`; `.../PSWaveImg/eew/<YYYYMMDD>/<timestamp>.eew.gif` | eew, shake, home | EEW JSON 1 s; base map 1 day; real-time image 30 s; estimated/P-S image 2 s; guarded-host cooldown 2 min | [Kyoshin Monitor terms](https://www.kyoshin.bosai.go.jp/ja/about_kmoni/) |
| P2PQuake — history API | `https://api.p2pquake.net/v2/history?codes=556&limit=30`; `.../v2/history?codes=554&codes=9611&limit=30` | eew, shake, home, timeline | EEW history 2 s; shaking history 5 s; timeline history 2 min; guarded-host cooldown 5 min | [P2PQuake API](https://api.p2pquake.net/); use subject to the provider's current terms |

## NIED data rights and EEW distribution

NIED's [Kyoshin Monitor terms](https://www.kyoshin.bosai.go.jp/ja/about_kmoni/) prohibit copying, modifying, transmitting or redistributing Kyoshin Monitor images beyond private use and statutory exceptions. Do not use Bousai's NIED-derived map images for public rebroadcasting, publication or redistribution without rights that permit it. This restriction applies independently of the Apache-2.0 license for Bousai's software.

NIED also identifies regulatory restrictions concerning public provision of EEW-derived forecasts in Japan. Anyone operating a public or commercial EEW service must check applicable rules before doing so; this document gives no legal assurance.

## Embedded source material

These assets make no runtime network request but are source material used by the suite:

| Material | Use | Rights / attribution |
| --- | --- | --- |
| [Natural Earth](https://www.naturalearthdata.com/about/terms-of-use/) land data | Embedded basemaps generated by `tools/gen_maps.py` | Public domain. |
| JMA tables | Generated into `src/lib/bousai_data.star` by `tools/gen_data.py` | 出典：気象庁ホームページ; [JMA terms](https://www.jma.go.jp/jma/kishou/info/coment.html). |

## Privacy

Requests are made by the Tronbyt server running the app. The configured latitude and longitude are rounded locally to 0.001° before Bousai uses them. Bousai does not send the raw configured coordinates to a geocoding service.

- Municipality resolution downloads JMA public area metadata and polygon files. Subsequent JMA requests use derived area, forecast-office or station codes; a JMA area code can reveal a coarse municipality or forecast area.
- Map apps convert the rounded coordinates to slippy-map tile coordinates and request the tile `z/x/y` at the selected zoom. Those coordinates reveal the selected map tile, not an address. AMeDAS map/point requests use a station ID chosen locally; LIDEN, map indexes and public feeds do not carry a location parameter.
- Wolfx, NIED and P2PQuake calls request shared EEW, image or history resources by report timestamp/code only; no Bousai location is included in their URL patterns.
- The HTTP user-agent identifies the software and links to JMA. No location, account identifier or data is sent to Bousai authors, and Bousai has no author-operated telemetry or collection endpoint.
