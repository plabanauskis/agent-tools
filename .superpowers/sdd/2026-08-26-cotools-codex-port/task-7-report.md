# Task 7 — Node Trail Brand Assets

## Design rationale

The assets retain the cctools silhouettes: a chat bubble, a three-row
session picker, and an isometric box. The Node Trail treatment is limited to
three small #10A37F points: horizontal chat dots, vertical session dots, and
light nodes on the box top. Wordmarks use a green underline beneath the `co`
prefix. This gives the new prefix a repeatable accent without adding an
unrelated symbol; no OpenAI mark is embedded, traced, or imitated.

Light marks use #16181D and dark marks use #F4F1EA. The social cards have a
#14161B ground, a deliberately faint oversized silhouette, centered lockup,
specified two-line copy, and the cotools repository footer.

## Files

- `tools/cochat/assets/{icon.svg,icon-dark.svg,logo.svg,logo-dark.svg,og-image.svg,og-image.png}`
- `tools/cosession/assets/{icon.svg,icon-dark.svg,logo.svg,logo-dark.svg,og-image.svg,og-image.png}`
- `tools/cobox/assets/{icon.svg,icon-dark.svg,logo.svg,logo-dark.svg,og-image.svg,og-image.png}`
- `tests/assets.test.sh`

## TDD evidence

The artifact-contract test was written before any assets existed. It first
failed solely because all requested asset paths were absent:

```text
$ bash tests/assets.test.sh
FAIL: missing asset: tools/cochat/assets/icon.svg
FAIL: missing asset: tools/cochat/assets/icon-dark.svg
FAIL: missing asset: tools/cochat/assets/logo.svg
FAIL: missing asset: tools/cochat/assets/logo-dark.svg
FAIL: missing asset: tools/cochat/assets/og-image.svg
FAIL: missing asset: tools/cochat/assets/og-image.png
FAIL: missing asset: tools/cosession/assets/icon.svg
FAIL: missing asset: tools/cosession/assets/icon-dark.svg
FAIL: missing asset: tools/cosession/assets/logo.svg
FAIL: missing asset: tools/cosession/assets/logo-dark.svg
FAIL: missing asset: tools/cosession/assets/og-image.svg
FAIL: missing asset: tools/cosession/assets/og-image.png
FAIL: missing asset: tools/cobox/assets/icon.svg
FAIL: missing asset: tools/cobox/assets/icon-dark.svg
FAIL: missing asset: tools/cobox/assets/logo.svg
FAIL: missing asset: tools/cobox/assets/logo-dark.svg
FAIL: missing asset: tools/cobox/assets/og-image.svg
FAIL: missing asset: tools/cobox/assets/og-image.png
```

After authoring the SVGs and rendering the PNGs with the specified `convert`
commands, the focused verification was:

```text
$ bash tests/assets.test.sh
assets.test.sh: PASS (Node Trail asset contract)

$ identify tools/*/assets/og-image.png
tools/cobox/assets/og-image.png PNG 1280x640 1280x640+0+0 16-bit sRGB
tools/cochat/assets/og-image.png PNG 1280x640 1280x640+0+0 16-bit sRGB
tools/cosession/assets/og-image.png PNG 1280x640 1280x640+0+0 16-bit sRGB
```

The test parses every SVG, validates all source and rendered dimensions,
checks transparent icon/wordmark canvases, verifies rendered accent and
light/dark inks, rejects legacy names and #D97757, validates opaque social
backgrounds, and pixel-compares each checked-in PNG with a fresh ImageMagick
render from its SVG source.

## Visual inspection

I opened `/tmp/cotools-node-trail-marks.png` and
`/tmp/cotools-node-trail-social.png` with the image viewer. I confirmed every
light/dark icon and wordmark remains recognizable, the points are restrained
and consistently placed, the `co` underline is clear, social headlines have
safe wrapping and footer clearance, and the background motifs are faint rather
than competing with the content. During inspection I corrected two renderer
issues: ImageMagick collapses negative SVG `letter-spacing`, and ignores the
group-opacity treatment used for faint background marks. The sources therefore
use default letter spacing and a pre-blended #202226 silhouette fill.

## Full verification

```text
$ bash scripts/check.sh
... all bash -n, shellcheck, and shfmt entries ok ...
assets.test.sh: PASS (Node Trail asset contract)
29 passed, 0 failed
8 passed, 0 failed
8 passed, 0 failed
51 passed, 0 failed
18 passed, 0 failed
7 passed, 0 failed
61 passed, 0 failed
SKIP: cobox smoke (no sysbox)
check.sh: ALL CHECKS PASSED
```

## Self-review and concerns

`git diff --check` is clean. The assets are all standalone SVGs with semantic
titles, `role="img"`, and accurate aria-labels. No external artwork or raster
generative backend was used; PNGs are reproducible ImageMagick renders.

Concern: the `co` highlight is an accent underline rather than colored glyphs.
This preserves a renderer-portable wordmark while still marking the exact
prefix in every lockup. The local rendering environment has no sysbox runtime,
so the existing cobox image smoke test was skipped by its documented gate.

## Commit

`design: add Node Trail brand assets` (the final SHA is recorded in the task handoff).
