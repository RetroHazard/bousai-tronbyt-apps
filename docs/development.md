# Development

## Layout and build model

| Path | Purpose |
| --- | --- |
| `src/lib/bousai_*.star` | Shared core, map, data, and domain libraries. |
| `src/apps/<id>/` | Source for a suite app: `<id>.star`, `manifest.yaml`, and an optional `preview.json`. |
| `apps/<id>/` | Generated, uploadable app files. Do not edit these files. |
| `examples/<id>/` | Source for standalone examples. Their generated output is under `build/examples/<id>/`. |

A source app declares its libraries near the top of its `.star` file:

```starlark
# bousai: requires core map
```

`tools/build.py` resolves those names as `src/lib/bousai_<name>.star`, follows library requirements recursively, and inlines the result into one `.star` file. This is deliberate: Tronbyt loads the first `.star` file in an app directory, while Pixlet `load()` can only load files in that same directory. A source app therefore cannot upload with its shared library files alongside it.

## Building

Run the builder from the repository root.

```sh
python3 tools/build.py                         # all suite apps and previews
python3 tools/build.py bousai_forecast         # one suite app
python3 tools/build.py --check                 # verify generated apps/ has no drift
python3 tools/build.py --pixlet-check          # build and run pixlet check
python3 tools/build.py --zip                   # also write dist/<id>.zip
python3 tools/build.py --gif /tmp/bousai-gifs  # also write 8x GIFs for review
python3 tools/build.py --no-render             # inline and copy manifests, without previews
```

`--check` writes nothing and fails when a generated `apps/<id>/<id>.star` is missing or differs from the formatted source build. It does not compare live preview pixels. `--pixlet-check` runs `pixlet check` on each built app. `--zip` packages each generated app with LICENSE and NOTICE; `--gif DIR` renders magnified GIFs; and `--no-render` skips `.webp` preview rendering.
An optional source `preview.webp` is copied instead of rendering a store preview. Shake uses this for an original information-only card: NIED imagery must not be redistributed. GIF renders still use the live app; keep any NIED output private.

Examples use the same source layout but a separate output tree:

```sh
python3 tools/build.py --examples bousai_hello --pixlet-check
python3 tools/build.py --examples --zip
```

These commands build `examples/<id>/` into `build/examples/<id>/`; example ZIP files are written below `build/examples/`.

The builder validates each manifest before it builds. `manifest.yaml` must contain `id`, `name`, `summary`, `desc`, `author`, `fileName`, and `packageName`. For app id `bousai_hello`, the required identity values are:

```yaml
id: bousai-hello
fileName: bousai_hello.star
packageName: bousai_hello
```

In other words, `id` replaces `_` with `-`; `fileName` is the source filename; and `packageName` is the underscore form. The source module must also start with a non-empty module docstring.

## Generated data and visual review

`tools/gen_data.py` regenerates `src/lib/bousai_data.star` from JMA reference tables, including JMA English dictionaries, forecast weather-code telops, warning-code mappings, and forecast-office mappings. `tools/gen_maps.py` regenerates `src/lib/bousai_mapdata.star`, which embeds Natural Earth land bitmaps used by overview maps.

```sh
python3 tools/gen_data.py
uv run --with pillow tools/gen_maps.py
```

Both generators fetch their source data and rewrite generated library files, so review their diffs. To inspect a rendered animation, use the contact-sheet helper:

```sh
uv run --with pillow tools/contact_sheet.py in.gif out.png [max_frames]
```

It keeps distinct GIF frames and tiles up to `max_frames` frames into one PNG.

## Shared library API

All public shared names start with `bousai_`. App-specific domain libraries add their own APIs; the two foundation libraries below are the usual starting point.

### `src/lib/bousai_core.star`

| API | Purpose |
| --- | --- |
| `bousai_get_json(url, ttl = 60, params = None)` | Fetch and decode JSON; return `None` for a non-200 response or invalid JSON. |
| `bousai_get_bytes(url, ttl = 60)` | Fetch bytes; return `None` for a non-200 response. |
| `bousai_guarded_get(url, ttl = 60, params = None, cooldown = 300)` | Fetch a potentially stalling third-party host with a per-host crash-loop guard. |
| `bousai_guarded_json(url, ttl = 60, params = None, cooldown = 300)` | Guarded fetch followed by JSON decoding. |
| `bousai_schema(fields, location = True, location_desc = "Your location in Japan. Matched to a JMA municipality on the server using JMA's own area polygons; coordinates are never sent anywhere.")` | Build an app schema with optional Location and JMA-area override fields, the supplied fields, and the accessibility fields. |
| `bousai_accessibility_fields()` | Return the Theme, Colour vision, Contrast, Text size, and Text weight schema fields. |
| `bousai_bool(config, key, default = False)` | Read a Pixlet boolean setting consistently from string or boolean config values. |
| `bousai_ui(config)` | Resolve theme, colour-vision palette, contrast, fonts, text weight, and animation delay into a UI dictionary. |
| `bousai_rgb(c)` / `bousai_hex(rgb)` | Convert between a hex colour and `(r, g, b)`; `bousai_hex` pads hex bytes without unsupported `%` width formatting. |
| `bousai_mix(a, b, t)` / `bousai_luma(c)` / `bousai_on(c)` | Blend colours, measure luminance, and select legible black or white text. |
| `bousai_text(ui, s, color = None, font = None)` | Render text while honouring the configured bold setting. |
| `bousai_text_width(ui, s, font = None)` / `bousai_font_height(ui, font = None)` | Measure text for 64×32 layouts. |
| `bousai_budget_frames()` | Return the animation frame budget from `canvas.max_duration_ms()`, defaulting to 150 frames (15 seconds). |
| `bousai_ticker(ui, s, width, color = None, font = None, frames = None)` | Scroll overlong text within an explicit frame budget. |
| `bousai_fit(ui, s, width = None, color = None, font = None, align = "start", frames = None)` | Render one fitted line, using a bounded ticker only when needed. |
| `bousai_header(ui, title, color = None, right = None, frames = None)` | Create a title band with an optional right-side label. |
| `bousai_row(ui, item, frames = None)` | Turn a string or `(text, color)` pair into a standard text row. |
| `bousai_hold_frames(pages, min_ms = 2500)` / `bousai_hold(widget, frames)` | Allocate and enforce page display time, with a 2.5-second minimum. |
| `bousai_pages(ui, header, rows, footer = None)` | Paginate rows to the current canvas and text size. |
| `bousai_root(ui, child)` / `bousai_message(ui, title, lines, color = None)` | Wrap a page in the themed Pixlet root, or render a full-screen status/error message. |
| `bousai_badge(ui, label, color, width = None, font = None)` / `bousai_blink(ui, widget, width, height, on_frames = 6, off_frames = 3)` | Make labelled severity badges and contrast-aware blink emphasis. |
| `bousai_sev_color(ui, level)` | Look up a severity colour for levels 0–5. |
| `bousai_intensity_norm(v)` / `bousai_intensity_rank(label)` / `bousai_intensity_color(ui, label)` / `bousai_intensity_from_value(x)` | Normalise, rank, colour, and derive JMA seismic-intensity labels. |
| `bousai_now()` / `bousai_parse_time(s)` | Get JST now or parse JMA, P2PQuake, Wolfx, and NIED timestamps. |
| `bousai_tz(config)` / `bousai_hhmm(t, tz = BOUSAI_JST)` / `bousai_mdhm(t, tz = BOUSAI_JST)` / `bousai_ago(t, now = None)` | Resolve a configured timezone and make compact time labels. |
| `bousai_fixed(x, digits = 1)` | Format a number with exactly the requested decimal digits. |
| `bousai_distance_km(lat1, lon1, lat2, lon2)` / `bousai_bearing_name(lat1, lon1, lat2, lon2)` | Calculate great-circle distance and a 16-point bearing label. |
| `bousai_location(config)` | Decode the configured Location into rounded latitude, longitude, label, and timezone. |
| `bousai_area_table()` | Fetch JMA `area.json`, cached for one day. |
| `bousai_locate_class20(lat, lon)` | Locate a JMA municipality using JMA bounding boxes and polygons. |
| `bousai_area(config)` | Resolve a location or JMA-area override to class20, class15, class10, office, centre, prefecture, English names, and coordinates. |
| `bousai_land_filter(ui, child)` | Tint an embedded land bitmap for the selected theme. |

The HTTP APIs are named `bousai_get_json` and `bousai_get_bytes`; there are no separate `bousai_get` or `bousai_json` functions.

### `src/lib/bousai_map.star`

| API | Purpose |
| --- | --- |
| `bousai_world_px(lat, lon, zoom)` | Convert latitude and longitude to fractional-zoom Web Mercator world pixels. |
| `bousai_view(lat, lon, zoom, width = None, height = None)` | Create a canvas-centred map view. |
| `bousai_view_fit(points, width = None, height = None, pad = 3, min_zoom = 2.0, max_zoom = 9.0)` | Create the smallest zoom-out view containing latitude/longitude points. |
| `bousai_unproject(x, y, zoom)` | Convert Web Mercator world pixels back to latitude and longitude. |
| `bousai_view_xy(view, lat, lon)` / `bousai_in_view(view, x, y)` | Project a point into a view and test whether it lies on canvas. |
| `bousai_place(x, y, child)` | Position a widget at a pixel offset. |
| `bousai_basemap(ui, view, name = "japan")` | Place a tinted embedded Natural Earth land silhouette. |
| `bousai_tile_layer(view, url_template, tile_zoom, ttl = 300, max_tiles = 9)` | Fetch and position a bounded set of slippy-map tiles. |
| `bousai_jmatile_times(path, ttl = 60)` | Fetch a JMA tile target-time index. |
| `bousai_jmatile_url(kind, basetime, validtime, element, member = "none")` | Construct a JMA tile URL template. |
| `bousai_mask_layer(view, tile_zoom)` | Add the JMA coastline and prefecture-border overlay. |
| `bousai_marker(ui, view, lat, lon, color, size = 3)` | Draw a theme-aware square location marker. |
| `bousai_cross(ui, view, lat, lon, color, arm = 2)` | Draw a theme-aware cross marker for an epicentre or location. |
| `bousai_map_frame(ui, view, layers)` | Clip stacked map layers to the map view. |

## Pixlet constraints

- Pixlet's `%` formatting has no width or precision flags. Use `bousai_fixed()` for fixed decimals and `bousai_hex()` when padded hexadecimal bytes are needed.
- Starlark has no `try`/`except`. Check response shape and return a `bousai_message()` instead of assuming a feed is usable.
- Pixlet HTTP has a default five-second timeout. A transport error or timeout aborts the entire render and cannot be caught. Use the normal helpers for reliable official feeds; use `bousai_guarded_get()` or `bousai_guarded_json()` for third-party feeds (including NIED where it is used) or any host that can stall. The guard writes a per-host cache marker before the request, then skips a host for its cooldown after a prior render died mid-request.
- `pixlet check` requires a warm render in one second or less and no lint warnings. Bound requests, tile counts, parsing, and animation work accordingly.
- The entire animation must fit `canvas.max_duration_ms()`. If it is unbounded, the core assumes a 15-second budget. Use `bousai_budget_frames()` and bounded tickers rather than an unbounded marquee.
- Keep every page visible for at least 2.5 seconds. `bousai_pages()` and `bousai_hold_frames()` implement that floor for normal paged layouts; reduce page count when the floor would not fit the canvas duration.
- Never use colour as the only cue. Put a level or state in text as well (for example, `Lv4`, `Warning`, or `Int 5+`).
- An alert-only app must return `[]` while idle so Tronbyt Autopin can unpin it. It must return a real widget while an alert is active.
- Pixlet cache persists on Tronbyt Server. Cache keys are scoped to an app installation, so make keys stable within one app and do not rely on them being shared between installations.

## Adding a new app

1. Choose a lowercase underscore id, such as `bousai_example`, and create `src/apps/bousai_example/`.
2. Add `bousai_example.star` with a module docstring, a `# bousai: requires ...` line, `main(config)`, and `get_schema()`. Start with `bousai_schema()` and `bousai_ui()` so the standard location and accessibility settings work.
3. Add `manifest.yaml`. Set `id: bousai-example`, `fileName: bousai_example.star`, and `packageName: bousai_example`; provide the remaining required manifest fields.
4. Add `preview.json` when the default render needs explicit settings. Its values must be the strings accepted by `pixlet render`; a Location value is a JSON string.
5. Prefer an official JMA or NIED source. For a third-party source that JMA does not publish, use a guarded helper and handle unavailable data and locations outside Japan with a visible message.
6. Build the app and inspect it: `python3 tools/build.py bousai_example --pixlet-check`. Do not edit `apps/bousai_example/`; it is generated.
7. Add `src/apps/bousai_example/gallery.json` and `docs/apps/bousai_example.md`, then regenerate documentation as described below.

## Docs

Each suite app has `docs/apps/<id>.md`. The hand-written sections explain behaviour, setup, feeds, and limitations. Gallery and settings sections are generated blocks; do not hand-edit their contents.

`tools/gen_docs.py` is the documentation generator. It renders `src/apps/<id>/gallery.json` entries into `docs/images/` as 4× animated WebP files and writes settings tables from `pixlet schema`. Run it after changing an app, manifest, schema, preview, or gallery:

```sh
python3 tools/gen_docs.py
python3 tools/gen_docs.py --check
```

`--check` verifies generated text blocks and the presence of image assets, without re-rendering live feeds. It does not prove that existing live images match current conditions. Run `python3 tools/check_links.py` to check local Markdown navigation and image links.

A gallery file is a JSON list of one to four entries. Each entry has a `name` matching `[a-z0-9-]+`, a human-readable `caption`, and a `config` object whose values are strings accepted by `pixlet render`. Pick configurations that always return visible output, including a demo or show-idle setting for an alert-only app. For original static art, use an `image` filename in `docs/images/` instead of `config`; Shake does this to avoid redistributing NIED content.

GitHub Actions pins Pixlet v0.55.0 and verifies its download checksum, then checks generated sources, documentation, links, all apps, the starter app and documented example configurations. Live provider outages can fail render checks. Publishing is manual; see [Releasing](releasing.md).
