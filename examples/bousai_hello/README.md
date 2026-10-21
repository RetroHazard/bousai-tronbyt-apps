# Bousai Hello

`bousai_hello.star` is a small standalone example of the Bousai shared libraries. It uses `bousai_schema()` for Location and accessibility settings, resolves that Location to JMA area codes with `bousai_area()`, fetches JMA's official regional forecast JSON, and displays the first daily weather code in JMA English. It shows a visible message for a location outside Japan or an unavailable forecast feed.

## Files

- `bousai_hello.star` contains the documented app source. Its `# bousai: requires core data` line asks the builder to inline the core helpers and generated JMA English weather-code table.
- `manifest.yaml` supplies the Tronbyt app metadata.
- `preview.json` supplies a Tokyo location for the generated preview.

## Build and upload

Build and validate the example from the repository root:

```sh
python3 tools/build.py --examples bousai_hello --pixlet-check
```

The self-contained app, manifest, and preview are written to `build/examples/bousai_hello/`. Upload `build/examples/bousai_hello/bousai_hello.star` in the Tronbyt web UI, or create an uploadable ZIP with:

```sh
python3 tools/build.py --examples bousai_hello --zip
```

That writes `build/examples/bousai_hello.zip`.
