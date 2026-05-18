# AGENTS.md

## Agent Workflows

Before creating PRDs, issues, HAT artifacts, review reports, PRs, or handing work to another agent, read:

- `~/.agents/docs/agents/workflows.md`
- `~/.agents/docs/agents/handoff-policy.md`

Persistent artifacts must include a Source Manifest so downstream agents can reread the original sources instead of relying only on summaries.

## Project Snapshot

FinderX is a macOS file extension app. The long-term shape is a general Finder companion, but the first vertical slice is image compression from Finder's right-click menu.

Current primary flow:

1. User right-clicks a supported image in a monitored Finder folder.
2. `FinderXFinderExtension` contributes the direct contextual menu item `Compress with FinderX`.
3. The extension opens the main app with `finderx://compress?file=...`.
4. The app shows image information, compression settings, and a preview/comparison workflow.
5. Compression always creates a new file beside the source; the original is never overwritten.

Supported input formats are JPEG, PNG, and WebP. Output formats are Auto, JPEG, PNG, and WebP. Default output naming is `sourceName-compressed.ext`; collisions append Finder-like numeric suffixes such as `sourceName-compressed 2.ext`.

## Source Manifest

Use these sources to rebuild project context:

- `README.md`: current build, install, and verification commands.
- `Sources/FinderXFinderExtension/FinderSync.swift`: Finder Sync menu registration, monitored folders, selected URL handling.
- `Sources/FinderXApp/FinderXApp.swift`: SwiftUI app lifecycle, single-window UI, URL handling, compression panel.
- `Sources/ImageCompressionCore/ImageCompressionCore.swift`: image inspection, output naming, compression, WebP command encoder, batch reports.
- `Sources/FinderXCompressCLI/main.swift`: CLI smoke test entry point for the compression core.
- `Tests/ImageCompressionCoreTests/ImageCompressionCoreTests.swift`: core regression tests.
- `scripts/generate_xcodeproj.rb`: authoritative Xcode project generator.
- `scripts/install_debug_app.sh`: authoritative local Finder acceptance installer.
- `docs/product/finderx-v1-prd.md`: original PRD and technical plan. It is useful background, but it is partially stale: latest input support includes WebP and the menu title is `Compress with FinderX`.
- `hats/20260518-finderx-v1-image-compression/`: manual acceptance guide/report, including the debugging history for Finder Sync registration, entitlements, UI refinements, and WebP support.

## Architecture

- `FinderXApp`: macOS SwiftUI app. It is an accessory/agent-style utility, hidden from the Dock via `LSUIElement`. It uses a single `Window("FinderX", id: "main")`, opens from `finderx://compress`, and hides after focus loss with a delay so Finder menu selection is not interrupted.
- `FinderXFinderExtension`: Finder Sync Extension. It is directory-scoped, builds the contextual menu, filters supported images, falls back from `selectedItemURLs()` to `targetedURL()`, and hands files to the app through the custom URL scheme.
- `ImageCompressionCore`: pure/testable image layer. It owns image metadata inspection, supported format detection, output URL collision handling, compression options, automatic output choice, WebP command encoding, and batch aggregation.
- `FinderXCompressCLI`: command-line smoke path through the same compression core.
- Tests currently focus on stable core contracts rather than Finder private framework behavior.

## Product Decisions

- Primary entry point is Finder contextual menu, not Quick Look.
- The menu item is direct, not a submenu. Finder Sync contextual submenus were unreliable during acceptance.
- v1 generates new files only. Do not add in-place overwrite behavior unless that decision is explicitly reopened.
- Pixel dimensions are preserved by default. Resize exists, but defaults to Original/off.
- `Auto` should choose the smallest viable output while respecting transparency and mode constraints.
- `Balanced` is the default mode and may use lossy JPEG/WebP compression.
- `Lossless` is explicit.
- Metadata handling is a deliberate option, not an implicit side effect.
- Single-image UI should be compact and Apple-like: actual tool first, no landing page, no decorative marketing layout.

## Development Workflow

Regenerate the Xcode project after changing target/project structure:

```sh
ruby scripts/generate_xcodeproj.rb
```

Run tests with isolated DerivedData:

```sh
xcodebuild -project FinderX.xcodeproj -scheme FinderX -destination platform=macOS -derivedDataPath .build/TestDerivedData CODE_SIGNING_ALLOWED=NO test
```

For local Finder acceptance, use:

```sh
scripts/install_debug_app.sh
```

or, after code-only changes when tests were already run:

```sh
scripts/install_debug_app.sh --skip-tests
```

The installer intentionally runs unsigned tests in `.build/TestDerivedData`, builds the Finder-loadable signed debug app in `.build/DerivedData`, bundles WebP support, registers/enables the Finder Sync Extension, and restarts Finder.

Critical rule: do not run `CODE_SIGNING_ALLOWED=NO test` against `.build/DerivedData` after installing the extension. That can overwrite the signed app/extension bundle and make the Finder contextual menu disappear.

## Finder Acceptance

Check extension registration:

```sh
pluginkit -m -p com.apple.FinderSync -v | grep dev.finderx.FinderX.FinderExtension
```

A leading `+` means the extension is enabled.

If the menu disappears:

1. Run `scripts/install_debug_app.sh --skip-tests`.
2. Confirm PluginKit shows `+ dev.finderx.FinderX.FinderExtension(0.1.0)`.
3. Restart Finder if the script was run with `--no-restart-finder`.
4. Kill stale app instances if the UI or behavior looks old:

```sh
pkill -f FinderX.app
```

Finder Sync is monitored-folder scoped. Current defaults are:

- `~/Downloads`
- `~/Desktop`
- `~/Pictures`
- `~/Library/Mobile Documents/com~apple~CloudDocs` when present

Inside a sandboxed Finder Sync extension, `FileManager.default.homeDirectoryForCurrentUser` can resolve to the extension container. Use POSIX home via `getpwuid(getuid())` for monitored folder paths.

## WebP Notes

macOS ImageIO may read WebP but not advertise WebP writing on the target machine. FinderX therefore supports WebP output with a bundled `cwebp` helper.

`scripts/install_debug_app.sh` expects Homebrew WebP at:

```sh
/opt/homebrew/bin/cwebp
```

The script copies `cwebp` and its dylibs into `FinderX.app/Contents/Resources/cwebp`, patches dylib load paths, signs the helper and libraries, then signs the app. Runtime code must not assume `PATH` contains `cwebp`.

Keep WebP support in all three places when editing formats:

- Finder menu filter in `FinderSync.swift`
- app file picker / UI in `FinderXApp.swift`
- inspection and compression in `ImageCompressionCore.swift`

## Sandboxing And File Access

The app is sandboxed. It currently relies on entitlements for common monitored folders and user-selected files. If the app opens from Finder but reports that it cannot read a selected image, inspect:

- app entitlements
- extension entitlements
- whether the file is inside a monitored folder
- whether an iCloud file is locally available

Do not treat a Finder-opened read failure as only a compression-core bug; it is often an entitlement or security-scoped access issue.

## UI Guardrails

- FinderX should behave like a transient utility: single window, no Dock presence, hide on focus loss.
- Repeated Finder menu actions should reuse the same window.
- Single image mode should show the selected image fully scaled to fit its preview area by default.
- Avoid wide, crowded horizontal control bars. Prefer native macOS hierarchy: file header, compact facts, preview, right inspector, primary Compress button.
- The first screen is the working tool, not a marketing or onboarding screen.

## Commit Hygiene

There may be uncommitted user or agent changes in this repository. Do not revert unrelated work. Before committing, inspect `git status --short` and only stage files relevant to the current task.

If asked to push, use the configured remote:

```sh
git@github.com:ivan-94/finderx.git
```
