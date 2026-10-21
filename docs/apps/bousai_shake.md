# Bousai Shake Monitor (`bousai_shake`)

A NIED Kyoshin Monitor strong-motion view for Tronbyt. It covers the NERV-style live shaking map, with EEW estimated-intensity and P/S-wave overlays and an optional shaking-detection state.

<!-- BEGIN GENERATED: gallery -->
| ![Original illustration of the Shake Monitor layout; not NIED imagery or a live reading.](../images/bousai_shake-illustration.png)<br>*Original illustration of the Shake Monitor layout; not NIED imagery or a live reading.* |
| :---: |
<!-- END GENERATED: gallery -->

## What it shows

The normal panel pairs a Kyoshin Monitor map with a clock, `QUIET` or `NO IMAGE`, P2PQuake status, and an eleven-colour intensity legend. NIED's station-dot scale runs from quiet blue through stronger colours to dark red; the source image colours cannot be remapped. Map view can be all Japan, a roughly 350 km region, or a roughly 170 km local window; a `+` marks the configured location when it is inside NIED's main-island map.

During an EEW, the map overlays NIED's estimated-intensity layer and P/S-wave circles. The text panel changes to `EEW WARNING` or `EEW FORECAST`, the estimated S-wave countdown (`S 12s`, then `S arrived`), maximum intensity, magnitude, and epicentre. Without an EEW, a recent P2PQuake evaluation produces `SHAKING`, its `LvN/4` confidence, and the reported prefectures. If NIED cannot be reached, an explicit unavailable card still reports any EEW or shaking status. With Only when shaking on, the app returns nothing unless an EEW or P2PQuake shaking report is active.

## Recommended Tronbyt setup

Use Render Interval Minutes **1**, matching the app recommendation. For a continuously visible monitor, leave Only when shaking off and Autopin off. For an alert card, turn Only when shaking on and Autopin on; it hides while neither an EEW nor a qualifying P2PQuake report is active. Use a four-second replay for the normal balance of movement and requests; select one frame to minimise map fetches.

<!-- BEGIN GENERATED: settings -->
## Settings

| Setting | Default | Choices | Description |
|---|---|---|---|
| **Location** (`location`) | — | Map picker | Your location in Japan. Matched to a JMA municipality on the server using JMA's own area polygons; coordinates are never sent anywhere. |
| **JMA area code (optional)** (`area_override`) | — | Free text | 7-digit JMA municipality code (e.g. 1310100). Overrides the location lookup. |
| **Map view** (`view`) | Japan | Japan (`japan`), Region around me (about 350 km) (`region`), Local around me (about 170 km) (`local`) | Whole of Japan, or a window centred on your location (the NIED map covers Japan's main islands; elsewhere the whole map is shown). |
| **Replay** (`replay`) | Last 4 seconds | Off (latest second only) (`1`), Last 4 seconds (`4`), Last 8 seconds (`8`) | Loop the last few seconds of shaking, one NIED image per second. Longer replays fetch more images per update. |
| **Only when shaking** (`only_when_shaking`) | Off | On / Off | Hide the app unless an EEW is active or P2PQuake users report shaking, so it takes over the display like an alert. Enable Tronbyt AutoPin. |

Plus the accessibility settings shared by every Bousai app — **Theme**, **Colour vision**, **Contrast**,
**Text size** and **Text weight**; see [Accessibility](../accessibility.md).

*This section is generated from the app's schema by `tools/gen_docs.py`.*
<!-- END GENERATED: settings -->

## How it works

The app first polls the shared EEW chain: Wolfx's latest report is cached for 1 second, with NIED EEW JSON as fallback and P2PQuake warning history as a last fallback. If there is no EEW it fetches P2PQuake shaking evaluations for up to 5 seconds of cache time. It then obtains NIED's latest Kyoshin timestamp (1 second), a base map (one day), one to eight real-time images (30 seconds), and, during EEW, estimated-intensity and P/S-wave images (2 seconds). Replay frames loop one source image per second.

All NIED, Wolfx, and P2PQuake requests use the shared guarded fetch. A host whose prior request stalled is skipped for a cooldown instead of failing every render: 120 seconds for Wolfx/NIED and 300 seconds for P2PQuake. The location is used only for map centring and the local EEW calculation; it is not sent to NIED or P2PQuake.

## Data sources

- NIED Kyoshin Monitor (K-NET / KiK-net) — real-time station, estimated-intensity, P/S-wave, and base-map images — `http://www.kmoni.bosai.go.jp/{webservice,data/map_img}/...` — NIED Kyoshin Monitor; [terms of use](https://www.kyoshin.bosai.go.jp/ja/about_kmoni/) restrict the images to private use and statutory exceptions.
- Wolfx — relayed JMA EEW telegram — `https://api.wolfx.jp/jma_eew.json` — JMA data via Wolfx.
- P2PQuake — EEW and user-reported shaking evaluations — `https://api.p2pquake.net/v2/history?codes=554&codes=9611&limit=30` — P2PQuake.

## Limitations

- NIED Kyoshin Monitor images are restricted to private use and statutory exceptions under the [NIED terms of use](https://www.kyoshin.bosai.go.jp/ja/about_kmoni/). They must not be copied, modified, transmitted, or redistributed outside those permissions; the public documentation therefore uses an original illustration rather than a live map image.
- This is a render-time snapshot/replay, not a continuously updated monitor; station dots, image timestamps, and P2PQuake reports can lag or be unavailable.
- P2PQuake shaking detection is a volunteer user-report evaluation, not an official confirmed observation.
- NIED's image colours cannot follow Colour vision settings; those settings apply to labels, markers, and status text.
- The map covers Japan's main islands. Outside that image coverage, the app falls back to the whole map and cannot place the location marker.