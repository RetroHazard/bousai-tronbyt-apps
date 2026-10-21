# Changelog

## Unreleased

Initial public-release preparation. No hosted release or version tag has been published yet.

### Apps

- Seventeen English-language 64×32 Tronbyt apps: Home, EEW, Shake, Quake, Tsunami, Volcano, Warnings, Typhoon,
  Radar, Lightning, Tornado, Risk, Snow, Weather Map, Forecast, AMeDAS and Timeline.
- Shared theme, colour-vision palette, contrast, text-size and text-weight controls.
- JMA polygon-based municipality matching and optional area-code overrides where applicable.
- Illustrative sample alerts for apps whose rare active states are otherwise hard to preview.
- Single-file generated apps for upload or custom-repository installation; per-app ZIP builder.

### Documentation and examples

- Illustrated app catalogue and per-app guides with schema-generated settings tables.
- Installation, Autopin, example rotations, CLI configurations and accessibility comparisons.
- Feature-coverage matrix, source/terms/privacy reference and Apache-2.0 license/NOTICE.
- Developer guide, contributing instructions and a runnable JMA forecast starter app.
- CI workflow for source/output consistency, documentation checks and live Pixlet validation.
- Original information-only Shake preview instead of redistributing restricted NIED images.

### Verification limits

- Tested with Pixlet v0.55.0, matching Tronbyt Server v2.5.1's embedded renderer.
- Active EEW, tsunami warning, eruption-flash, ashfall, river-flood and record-rain paths were not all observed live;
  illustrative samples do not prove end-to-end warning delivery.
- No local Tronbyt Server installation test was performed. Do not treat these apps as official warning equipment.
