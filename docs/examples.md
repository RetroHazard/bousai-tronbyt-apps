# Example setups and renders

[Installation](installation.md) · [Accessibility](accessibility.md)

These are **starting points**, not safety recommendations. Set your own location and thresholds. All live examples
need internet access from the server. `demo=true` is illustrative and must be turned off for normal use.

## Everyday weather rotation

For a general-purpose private display, keep Autopin **off** on these apps:

| App | Render interval (minutes) | Display time (seconds) | Suggested app settings |
|---|---:|---:|---|
| Forecast | 30 | 15 | Today, Tomorrow, 3-hourly and 7-day pages on; Celsius |
| AMeDAS | 10 | 15 | Nearest station; enable the measurements you use |
| Rain Radar | 5 | 15 | Full timeline; prefecture view; colour key on |
| Home | 1 | 15 | Only show alerts off; choose the information sources you want |

Forecast/Home can rotate additional content across renders. An app's settings page documents exactly which pages
are enabled and which sources it requests. Longer display time is not a substitute for a shorter render interval.

## Alert-focused rotation

Add a few ordinary apps, then enable Autopin only on apps that are configured to hide while idle:

| App | Render interval (minutes) | Autopin | App settings |
|---|---:|---|---|
| EEW | 0 | On | `show_idle=false`, `demo=false`; choose `min_level` to suit your use |
| Tsunami | 1 | On | `show_idle=false`, `demo=false` |
| Warnings | 1 | On | `alert_only=true`, `min_level=40` (Lv4+), `demo=false` |
| Quake | 1 | On | `only_recent=1` (one hour), `demo=false` |

Set **Display Time Seconds** to 15 initially. Autopin is an interruption mechanism, not a push feed or a guarantee of
immediate delivery. Multiple simultaneous pinned apps are governed by Tronbyt's scheduling. Prefer fewer overlapping
alert apps rather than adding all 17 with Autopin.

Volcano levels can remain elevated for years. For a local volcano view, use `scope=radius`, choose a radius and level,
and decide whether a persistent alert should take over the display. Typhoon Autopin is usually inappropriate because
storms persist for days.

## Accessible reading setup

For a calm, high-readability starting point:

- `text_size=large` and `text_weight=bold`.
- `contrast=low` if you want blinking disabled; `high` for stronger contrast instead.
- Choose `palette=protan`, `tritan` or `mono` as appropriate.
- Increase dwell time if you need more time to read, or use fewer enabled information pages.

Large/bold text reduces the number of lines that fit. Captions, intensity labels and warning levels remain text;
upstream map raster colours are not recoloured. See the [illustrated comparisons](accessibility.md#examples).

## Reproducible CLI examples

Run from the repository root with **Pixlet v0.55.0** on `PATH`. Choose `PIXLET` for the Python build tools if needed;
for these commands, replace `pixlet` with the path to your binary.

```sh
# Illustrative EEW with an accessible theme — no actual earthquake is being reported.
pixlet render apps/bousai_eew/bousai_eew.star \
  --config examples/configs/eew-sample-accessible.json \
  -m 4 -o /tmp/bousai-eew-sample.webp

# Illustrative tsunami pages, not an active warning.
pixlet render apps/bousai_tsunami/bousai_tsunami.star \
  --config examples/configs/tsunami-sample.json \
  -m 4 -o /tmp/bousai-tsunami-sample.webp

# Live forecast for a public example location (Chiyoda, Tokyo).
pixlet render apps/bousai_forecast/bousai_forecast.star \
  --config examples/configs/tokyo-forecast.json \
  -m 4 -o /tmp/bousai-tokyo-forecast.webp
```

These JSON files are **Pixlet app settings**, not Tronbyt device-import files. They do not set Autopin, render interval
or device dwell time. Set those in Tronbyt. On Windows, choose an output path under your temporary directory instead
of `/tmp/`.

The first two examples are app-owned sample data; the forecast uses live JMA data and can differ on every run.
Sample events are modelled on historical events but are not complete or authoritative reconstructions.

To inspect an app's accepted values:

```sh
pixlet schema apps/bousai_eew/bousai_eew.star
```

To inspect an animation as still frames (requires [uv](https://docs.astral.sh/uv/)):

```sh
pixlet render apps/bousai_eew/bousai_eew.star demo=true --format gif -m 4 -o /tmp/eew.gif
uv run --with pillow tools/contact_sheet.py /tmp/eew.gif /tmp/eew-contact-sheet.png
```

For a library-based starter app, see [`examples/bousai_hello/`](../examples/bousai_hello/README.md).
