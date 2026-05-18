# FinderX v1 Image Compression HAT Guide

## Metadata

- Source: `docs/product/finderx-v1-prd.md`
- Repo root: `/Users/ivan/workspace/ai/finderx`
- Mode: `blank`
- Reason: local macOS app validation with generated sample images and no external services.
- Created: 2026-05-18
- Prepare status: `syntax-checked`

## Scope

Validate FinderX v1 as a macOS Finder extension app for image compression:

- Build and test the Xcode project.
- Verify the compression core with real JPEG input.
- Verify the signed app contains and registers a Finder Sync Extension.
- Guide a human through app UI and Finder right-click menu acceptance.

## Environment

- Host: local macOS.
- Build tool: Xcode command line tools.
- Test data directory: `~/Downloads/FinderX-Agent-Test`.
- App bundle: `.build/DerivedData/Build/Products/Debug/FinderX.app`.

## Prepare

Run:

```sh
bash hats/20260518-finderx-v1-image-compression/prepare.sh prepare
```

The script is idempotent. It creates a sample JPEG in `~/Downloads/FinderX-Agent-Test` and prints the commands used for verification.

For Finder UI acceptance, install the debug app with:

```sh
scripts/install_debug_app.sh
```

This keeps unsigned test products in `.build/TestDerivedData` and the Finder-loadable signed app in `.build/DerivedData`. Do not run `CODE_SIGNING_ALLOWED=NO test` against `.build/DerivedData` after installing the extension.

## Acceptance Checklist

### P0

#### P0-001 Build and tests

- Preconditions: Xcode command line tools available.
- Steps:
  1. Generate Xcode project.
  2. Run `xcodebuild ... test`.
- Expected: build succeeds and 5 `ImageCompressionCore` tests pass.

#### P0-002 Signed app and Finder Sync registration

- Preconditions: project builds locally.
- Steps:
  1. Run signed build.
  2. Register app with `pluginkit`.
  3. Query Finder Sync extensions.
- Expected: `+    dev.finderx.FinderX.FinderExtension(0.1.0)` appears.

#### P0-003 CLI compression smoke test

- Preconditions: sample JPEG exists.
- Steps:
  1. Run `finderx-compress` on sample JPEG.
  2. Inspect output size and dimensions.
- Expected: new `*-compressed*.jpg` exists, original remains, dimensions match source, output size is smaller or equal.

#### P0-004 App UI opens

- Preconditions: signed app built.
- Steps:
  1. Open FinderX.app.
  2. Choose sample image.
- Expected: compression window opens and shows image details and controls.

#### P0-005 Finder contextual menu

- Preconditions: FinderX Finder Extension enabled in macOS settings.
- Steps:
  1. Right-click sample JPEG in Finder.
  2. Select `Compress Image with FinderX...`.
- Expected: FinderX opens the compression window for selected file.

### P1

#### P1-001 Output naming and collision

- Expected: repeated compression creates `-compressed`, `-compressed 2`, etc. without overwriting the original.

#### P1-002 Compression settings

- Expected: user can see/use output format, Balanced/Lossless mode, quality, resize, and metadata controls.

#### P1-003 Mixed/batch selection

- Expected: mixed selections are allowed; unsupported files are skipped/reported rather than crashing.

### P2

#### P2-001 Comparison experience

- Expected: after single-image compression, user can inspect original vs compressed using comparison UI.

#### P2-002 Settings page

- Expected: Settings lists monitored folders and offers extension settings entry.

## Source Manifest

### Sources

- `docs/product/finderx-v1-prd.md`
- `README.md`
- `Sources/ImageCompressionCore/ImageCompressionCore.swift`
- `Sources/FinderXApp/FinderXApp.swift`
- `Sources/FinderXFinderExtension/FinderSync.swift`
- User request to run HAT copilot acceptance together.

### Produced artifacts

- `hats/20260518-finderx-v1-image-compression/guide.md`
- `hats/20260518-finderx-v1-image-compression/prepare.sh`
- `hats/20260518-finderx-v1-image-compression/human-report.md`

### Key decisions

- Host-mode acceptance is used because this is a native macOS app.
- Agent handles build/test/CLI/system registration checks.
- Human owns UI and Finder contextual menu judgment.

### Verification evidence

- To be updated in `human-report.md` during HAT copilot execution.

### Open questions / risks

- Finder contextual menu visibility depends on the user enabling the Finder Extension in macOS settings.
- Debug builds use local signing and are suitable for validation, not distribution.
