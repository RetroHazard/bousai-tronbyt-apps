# Contributing

## Setup

- Python 3.11 or newer.
- Pixlet v0.55.0, the version embedded by Tronbyt Server v2.5. Download it from the [Pixlet releases](https://github.com/tronbyt/pixlet/releases).
- [uv](https://docs.astral.sh/uv/) for generators and image-review helpers that need Pillow.

## Workflow

1. Edit source files under `src/`; never edit generated `apps/` files.
2. Run `python3 tools/build.py --pixlet-check`.
3. Run `python3 tools/gen_docs.py` after app, schema, preview, or gallery changes.
   Check generated docs and navigation with `python3 tools/gen_docs.py --check` and `python3 tools/check_links.py`.
4. Commit the changed source, generated `apps/` output, and generated documentation together.

For a faster targeted iteration, pass an app id to the build command. See [Development](docs/development.md) for examples, generators, gallery files, and the example-app build path.

## Rules

- Use official JMA and NIED data first. Use a third-party feed only when JMA has no feed for that information, and fetch it through `bousai_guarded_get()` or `bousai_guarded_json()`.
- Accessibility settings are mandatory. Use `bousai_schema()` or include `bousai_accessibility_fields()`.
- UI text is English. Keep severity and warning states in text; colour is never the only cue.
- Do not use NERV branding, logos, artwork, or claim affiliation.
- Do not commit credentials, private server URLs or restricted provider imagery. NIED live images are not public-release assets; see [Data sources](docs/data-sources.md).

## Reporting bugs

Include the app id, settings, location or JMA area code (only as precise as you are comfortable sharing), time in JST, server/Pixlet version and a screenshot. Say whether the issue is persistent or tied to a live event/feed state. Remove credentials, tokens and private URLs. Do not attach restricted NIED imagery without permission.

## License

By contributing, you license your contribution under Apache-2.0.
