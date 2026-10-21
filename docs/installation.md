# Installation and operation

[Back to README](../README.md)

## Requirements

- A working Tronbyt Server and 64×32 display. Device firmware is not supplied by this repository.
- Internet access **from the server** to the providers listed in [Data sources](data-sources.md).
- A location in Japan for local products. National earthquake reports can still be useful outside Japan, but most
  weather, risk and warning products are Japan-only.
- Tested renderer: Pixlet v0.55.0 (embedded in Tronbyt Server v2.5.1). No API keys are required.

## Upload one app

1. Download the repository and extract it if necessary.
2. In Tronbyt, select your device, then **Add app → Upload app**.
3. Choose **`apps/<id>/<id>.star`**. These files already include their shared libraries; do not upload the files in `src/`.
4. Configure **Location** and the app's settings. Save and enable it in the rotation.
5. If available, turn on **Show sample alert** to see the layout. Turn it **off** when finished.

Start with `bousai_forecast` for a continuously visible app. Alert apps may intentionally produce no image when idle.
An optional **JMA area code** overrides the municipality lookup in apps that offer it; `1310100` is Chiyoda, Tokyo.
Map apps instead select tiles around the location, so an area code does not reposition their maps.

For ZIP uploads, install Pixlet and run:

```sh
python3 tools/build.py --zip
```

Upload **`dist/<id>.zip`**, containing the single-file app, manifest and preview. `dist/` is generated and is not committed.
The software license and upstream data notices remain in [LICENSE](../LICENSE) and [NOTICE](../NOTICE) at the repository root.

## Custom app repository

After hosting the repository on a supported git host:

1. Copy its clone URL (the repository root, not a file URL or the `src/` folder).
2. Tronbyt → **Settings → Content → Repository URL** → enter that URL.
3. Refresh the repository content and add the Bousai apps to your device.

Tronbyt reads **`apps/`**. This is why generated files and previews are committed.
Changing the server-wide repository URL can replace the catalogue you previously used; save its old value first.
Uploaded apps can be used without changing this setting.

## Alerts: Autopin and render intervals

Tronbyt **Autopin** pins an app when a successful render produces output and releases it when a render returns nothing.
It is not a push-notification mechanism. An app that always produces a card can remain pinned indefinitely.

| App | Render Interval Minutes | Autopin | Required app setting |
|---|---|---|---|
| EEW | **0** | On | **Show when idle** off; sample alert off |
| Tsunami | 1 | On | **Show when idle** off; sample alert off |
| Home | 1 | Only with alert-only mode | **Only show alerts** on; choose the alert threshold |
| Warnings | 1–5 | Only with alert-only mode | **Alert only** on; choose minimum level, e.g. Lv4 |
| Quake | 1–5 | Only with recent-only mode | **Only recent** on |
| Volcano | 5 | Only with alert-only mode | **Alert only** on; choose level and radius |
| Typhoon | 10 | Off | Storms can last days |
| Shake | 1 | Only with shaking-only mode | **Only when shaking** on |
| Lightning / Tornado / Risk | 5–10 | Only with active-only mode | **Only when active** on |
| Forecast / AMeDAS / Radar / Snow / Weather Map / Timeline | App recommendation | Off | Continuous display |

**Render Interval Minutes** controls how often an image may be refreshed, not how long it stays on screen.
**Display Time Seconds** controls the dwell time. Start at **15 seconds** so the app's default animation budget can be
shown; larger text uses more pages. Some apps rotate additional pages over successive renders, not in one loop.

EEW uses interval **0** to recalculate its countdown whenever the server checks the app. That still does not provide
continuous event delivery. Rotation length, scheduling, cached data and upstream latency affect alert arrival.
A countdown starts at server render time, not device playback time. It may already be stale on arrival.

Do not enable Autopin with a sample alert: the sample is deliberately always active.
Long-lived warnings, volcano alerts and typhoons can otherwise monopolise the display. Choose thresholds and radius
for your intended use; see [example rotations](examples.md).

## Updating

- **Uploaded app:** upload the newer built `.star` or ZIP and check your settings.
- **Custom repository:** refresh repository content through Tronbyt and check updated settings.
- Never edit a built `apps/<id>/<id>.star` and then rebuild: the build overwrites it. Edit `src/` for a maintained change.

## Troubleshooting

| Symptom | Check |
|---|---|
| Alert app is missing from rotation | It may be correctly hidden while idle. Enable its optional idle card for diagnosis, or use sample mode temporarily. |
| Sample keeps taking over the display | Turn sample mode off. Check Autopin and any optional idle card. |
| Forecast is for the wrong place | Check Location and any JMA area-code override. Saved warning places are separate from the primary location. |
| Outside-Japan / coverage card | Choose a location in the product's coverage. Forecasts and map products are not global. |
| Feed unavailable / no data | Check server connectivity and provider status. No data can mean no active event; read the particular app's guide. |
| Entire render fails on a timeout | Pixlet cannot catch transport errors. Third-party guards may skip a stalled host on later renders; they cannot rescue the first failed render. |
| Map colours ignore my palette | JMA/NIED raster colours are retained. Accessibility settings change labels, markers and keys, not upstream map pixels. |
| Text scrolls or extra information is missing | Try standard text or a longer dwell. Extra-large/bold text shows fewer lines and requires more pages. |
| Alert is late | Shorten the rotation and remove unnecessary apps. The feed and render model still impose latency; use official alert channels. |
| Older r8 warning feed fails to load | Bousai uses JMA's warning system introduced in May 2026; do not switch back to the frozen legacy feed. |
| Uploaded source reports missing symbols | Upload `apps/<id>/<id>.star`, not `src/apps/<id>/<id>.star`. |

When reporting a problem, include app ID, settings, location or area code (only as precise as you are comfortable sharing),
time and timezone, server/Pixlet versions, render error and a screenshot. Remove server credentials, tokens and private URLs.
See [Contributing](../CONTRIBUTING.md).
