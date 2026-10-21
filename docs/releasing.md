# Preparing a public release

[Development](development.md) · [Changelog](../CHANGELOG.md)

These are manual maintainer instructions. The validation workflow does **not** publish repositories, tags or releases.

## Before publishing

1. Review [LICENSE](../LICENSE), [NOTICE](../NOTICE) and [provider terms](data-sources.md). The code's Apache-2.0 license
   does not license external data. Do not include private NIED renders, credentials, tokens or server URLs.
2. Run the validation commands from the repository root:

   ```sh
   python3 tools/build.py --pixlet-check --zip
   python3 tools/build.py --check
   python3 tools/gen_docs.py
   python3 tools/gen_docs.py --check
   python3 tools/check_links.py
   python3 tools/build.py --examples --pixlet-check --zip
   ```

3. Read the generated README and per-app pages. Open the preview animations, confirm captions clearly identify sample
   alerts and live snapshots, and check representative accessibility variants. Sample alerts are not current warnings.
4. Exercise the three configuration examples in [Examples](examples.md). App checks and gallery generation use live
   services; record provider failures rather than claiming an offline or deterministic runtime check.
5. Review the staged files. Commit `src/`, generated `apps/`, documentation/images, examples, tools and workflow files.
   `dist/`, `build/`, `.starcache/` and `__pycache__/` are ignored. Keep the license and notice in distributed archives.

The builder uses `src/apps/bousai_shake/preview.webp` as an original, information-only store preview. It must not be
replaced with a live NIED capture. The gallery likewise uses `docs/images/bousai_shake-illustration.png`. The `--gif`
option can produce private NIED render output; do not add that output to a public release without permission.

## First GitHub publication

Only run this when you intend to make the repository public. From the local repository, after committing:

```sh
gh repo create bousai-tronbyt-apps --public --source=. --remote=origin --push
```

This creates the repository under the authenticated account. If it already exists, add the intended remote and push
instead. Review the repository in a browser, confirm the README images resolve and let the validation workflow run.
The local checks do not prove that GitHub-hosted runners can reach every upstream service.

Suggested description: **English-language Japan weather and disaster-information apps for 64×32 Tronbyt displays.**
Suggested topics: `tronbyt`, `pixlet`, `starlark`, `japan`, `weather`, `earthquake`, `led-matrix`.

## Versioned releases

When a version is ready:

- Move the relevant changelog entries from Unreleased into a version/date section.
- Commit the changelog, choose and push the version tag, and create a GitHub Release for it.
- Attach the generated **`dist/bousai_*.zip`** app packages. Each contains app source, manifest, preview, LICENSE and NOTICE.
  GitHub's source archive supplies the complete source/docs tree; the starter app ZIP remains in `build/examples/` if wanted.
- Include compatibility, installation guidance, upstream-data restrictions and known verification limits in the release notes.
- Download a published package and render its `.star` from an extracted directory before announcing the release.

There is no automatic release publishing in this repository. Do not describe a local commit as a hosted release.
