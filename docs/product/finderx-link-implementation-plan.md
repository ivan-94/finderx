# FinderX Link Implementation Plan

## Context

FinderX already has a Finder Sync Extension and a custom `finderx` URL scheme. The current extension contributes `Compress with FinderX` for supported image files and opens the main app through `finderx://compress?...`.

This plan adds a second Finder contextual action, `Copy FinderX Link`, for copying a portable FinderX deep link to a selected file. Opening that link routes through FinderX and then delegates the file opening to macOS default app handling.

## Goals

- Add `Copy FinderX Link` to the Finder right-click menu for a single ordinary file.
- Copy a `finderx://open?...` URL to the clipboard.
- Support iCloud Drive files with a migratable relative path.
- Open copied links through FinderX without showing the FinderX compression UI.
- Preserve the existing `finderx://compress?...` behavior.
- Keep the implementation testable by sharing URL generation and parsing logic.

## Non-Goals

- Do not support folders, packages, or multi-file links in the first version.
- Do not provide a fully top-level Finder Sync item for locations where Finder does not invoke Finder Sync, such as iCloud Drive on the tested macOS environment.
- Do not add provider-specific migration support for Dropbox, OneDrive, Google Drive, external disks, or network mounts.
- Do not let links specify an app, execute commands, or call shell processes.
- Do not show a success notification or launch FinderX when copying a link.

## User-Facing Behavior

When the user right-clicks one ordinary file in a monitored Finder directory and Finder invokes the Finder Sync Extension, FinderX shows:

```text
Copy FinderX Link
```

When the file is also a supported image, FinderX shows both actions:

```text
Compress with FinderX
Copy FinderX Link
```

When the user clicks `Copy FinderX Link`, FinderX silently writes the generated URL to `NSPasteboard.general` as both plain text and URL pasteboard content.

For iCloud Drive files, Finder may not invoke Finder Sync contextual menus. FinderX therefore also registers Finder Services named `Compress with FinderX` and `Copy FinderX Link`; they appear under Finder's `Services` menu for selected files. The copy service uses the same URL generation and pasteboard behavior. The compression service opens FinderX with the selected supported image files through the existing compression flow.

When the user opens a copied `finderx://open?...` link, FinderX resolves it to a local file and calls `NSWorkspace.shared.open(fileURL)`. macOS chooses the default app, equivalent to opening the file from Finder. FinderX does not show its main window for this route.

## URL Contract

### Non-iCloud File

```text
finderx://open?file=/Users/ivan/Downloads/a.pdf
```

### iCloud Drive File

```text
finderx://open?icloud=Documents/a.pdf&file=/Users/ivan/Library/Mobile%20Documents/com~apple~CloudDocs/Documents/a.pdf
```

The `icloud` value is relative to the user-visible iCloud Drive root:

```text
~/Library/Mobile Documents/com~apple~CloudDocs
```

The `file` value remains as a local absolute fallback path. Values are percent-encoded by `URLComponents`; filenames, case, spaces, and Unicode are otherwise preserved.

## Resolve Rules

For `finderx://open`:

1. If `icloud` is present, join it with the current machine's iCloud Drive root.
2. If the resolved iCloud path exists and is an ordinary file, open it.
3. Otherwise, if `file` is present and resolves to an absolute ordinary file path, open it.
4. Otherwise, ignore the link and write an `OSLog` entry.

If multiple `icloud` or `file` query items are present, use the first value of each supported parameter and log that duplicate values were ignored.

The resolver must reject missing parameters, relative fallback paths, directories, packages, and unknown hosts. It must not invoke `Process`, shell commands, or app-selection parameters.

## Implementation Steps

1. Add a small shared linking module.
   - Suggested path: `Sources/FinderXLinking/FinderXLink.swift`.
   - Include URL creation for open links.
   - Include URL resolution for open links.
   - Include iCloud Drive root detection in one place.

2. Wire the shared module into Xcode project generation.
   - Update `scripts/generate_xcodeproj.rb` if target membership is generated from script state.
   - Ensure both `FinderX` and `FinderXFinderExtension` can use the shared code.
   - Add a test target or extend an existing test target for link behavior.

3. Update the Finder Sync Extension.
   - Keep the existing image detection and compression menu behavior.
   - Add single-file ordinary-file detection.
   - Build the contextual menu from independent eligible actions.
   - Add `copyFinderXLink` action.
   - Copy the URL string to pasteboard as `.string` and `.URL`.
   - Log generated-link success or failure without showing UI.

4. Update the main app URL router.
   - Keep `finderx://compress?...` on the existing compression path.
   - Add `finderx://open?...` handling.
   - Resolve through the shared linker.
   - Open the resolved file through `NSWorkspace.shared.open`.
   - Do not call `AppPresentation.show()` for open links.

5. Add a Finder Service fallback.
   - Register `Copy FinderX Link` in `NSServices`.
   - Register `Compress with FinderX` in `NSServices`.
   - Set `NSApp.servicesProvider` from the app delegate.
   - Accept one file URL from the copy service pasteboard.
   - Accept selected file URLs from the compression service pasteboard.
   - Reuse the shared linker and copy the same pasteboard payload as the Finder Sync action.
   - Reuse the compression router for selected supported image files.

6. Add tests.
   - Non-iCloud files generate `finderx://open?file=...`.
   - iCloud files generate `finderx://open?icloud=...&file=...`.
   - iCloud resolution takes priority over fallback.
   - Fallback resolution works when iCloud resolution fails.
   - Missing, relative, directory, and unknown-host inputs fail.
   - Percent-encoding handles spaces and Unicode without path mutation.

7. Update documentation and acceptance notes.
   - Add a short README note for `Copy FinderX Link`.
   - Add or update HAT guidance when preparing the implementation for human acceptance.

## Acceptance Criteria

- Right-clicking a single ordinary file in a monitored directory shows `Copy FinderX Link`.
- Right-clicking a supported image in a monitored directory shows both compression and link actions.
- Right-clicking a folder, package, empty Finder background, or multiple selection does not show `Copy FinderX Link`.
- Copying a non-iCloud file puts a `finderx://open?file=...` URL on the clipboard.
- Copying an iCloud Drive file through the Finder Service puts a `finderx://open?icloud=...&file=...` URL on the clipboard.
- Compressing an iCloud Drive image through the Finder Service opens FinderX with that image loaded.
- Opening the copied link opens the target file with the user's default app.
- Opening a copied iCloud link on another Mac with the same iCloud Drive relative path opens that machine's synced file.
- Opening invalid, stale, or directory links does not show FinderX UI and does not execute commands.
- Existing image compression flow still opens FinderX and loads selected image URLs.

## Risks

- Finder Sync menu availability remains limited to monitored directories.
- iCloud Drive may require the Finder Service fallback instead of a top-level contextual menu because Finder did not invoke the Finder Sync Extension during acceptance.
- iCloud placeholder behavior is delegated to macOS; FinderX should not promise custom download progress.
- Absolute fallback paths can expose local usernames or directory names in copied links.
- Cross-machine migration depends on iCloud Drive keeping the same relative file path.
- Tests may need dependency injection for iCloud root and file existence checks to avoid relying on the developer's real iCloud Drive.

## Source Manifest

### Sources

- User discussion in this session aligning the `Copy FinderX Link` feature scope and URL contract.
- Local repository file `Sources/FinderXFinderExtension/FinderSync.swift`, inspected for existing Finder menu behavior and `finderx://compress` handoff.
- Local repository file `Sources/FinderXApp/FinderXApp.swift`, inspected for current URL routing and compression presentation behavior.
- Local repository file `FinderX/Resources/Info.plist`, inspected for existing `finderx` URL scheme registration.
- Local repository file `README.md`, inspected for current build, Finder extension, and acceptance workflow notes.
- Existing product plan `docs/product/finderx-v1-prd.md`.
- Workflow guidance `/Users/ivan/.agents/docs/agents/workflows.md`.
- Handoff policy `/Users/ivan/.agents/docs/agents/handoff-policy.md`.

### Produced artifacts

- `docs/product/finderx-link-implementation-plan.md`

### Key decisions

- Use `finderx://open?...` for file-opening links.
- Use `icloud` for iCloud Drive relative migration and `file` for local absolute fallback.
- Prefer iCloud resolution over fallback when both are present.
- Keep link copying silent and clipboard-only.
- Keep `finderx://open` hidden from the FinderX compression UI.
- Support only single ordinary files in the first version.
- Reuse a shared linking module from the app and Finder extension.
- Add Finder Service fallbacks for iCloud Drive because Finder did not call the Finder Sync Extension for iCloud file right-clicks in manual acceptance.

### Verification evidence

- `xcodebuild -project FinderX.xcodeproj -scheme FinderX -destination platform=macOS -derivedDataPath .build/TestDerivedData CODE_SIGNING_ALLOWED=NO test` passed with 13 tests.
- `scripts/install_debug_app.sh --skip-tests` built, installed, refreshed Launch Services and Finder Services, registered and enabled the Finder Sync Extension, and restarted Finder.
- Local Finder right-click acceptance copied `finderx://open?file=/Users/ivan/Downloads/finderx-link-acceptance.txt`.
- Opening the local copied link launched the default app for the selected file.
- iCloud Finder right-click acceptance showed Finder did not invoke Finder Sync for `~/Library/Mobile Documents/com~apple~CloudDocs/...`.
- Finder Service acceptance copied `finderx://open?icloud=FinderXAcceptance/finderx-icloud-link-acceptance.txt&file=/Users/ivan/Library/Mobile%20Documents/com~apple~CloudDocs/FinderXAcceptance/finderx-icloud-link-acceptance.txt`.
- Opening the iCloud copied link launched TextEdit for the selected iCloud Drive file.
- Finder Service cache acceptance showed both `Compress with FinderX` and `Copy FinderX Link` registered from `.build/DerivedData/Build/Products/Debug/FinderX.app`, with stale `.build/TestDerivedData` services removed.
- iCloud Finder Service compression acceptance opened FinderX with `finderx-icloud-compress-source.jpg` loaded in the compression UI.

### Open questions / risks

- Validate cross-machine iCloud behavior manually because automated tests can cover path resolution but not full iCloud sync.
- Finder Service placement is under Finder's Services menu, not a top-level right-click item, when Finder Sync is unavailable for iCloud Drive.
