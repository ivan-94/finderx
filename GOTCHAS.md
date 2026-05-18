# FinderX Gotchas

This file captures traps discovered while implementing and accepting FinderX Finder integrations. It is written for future agents and developers who need to debug Finder menus, Finder Services, custom URL routing, and iCloud Drive files.

## Finder Sync is not Finder Services

FinderX currently has two Finder entry points:

- Finder Sync contextual menu, implemented by `Sources/FinderXFinderExtension/FinderSync.swift`.
- Finder Services menu, registered through `FinderX/Resources/Info.plist` and handled by `FinderXServicesProvider` in `Sources/FinderXApp/FinderXApp.swift`.

They look similar in Finder, but they behave differently:

- Finder Sync can show top-level right-click actions for monitored folders.
- Finder Services usually appears under `Services`.
- iCloud Drive may not invoke Finder Sync reliably, so Services is the fallback path.
- Clicking the macOS menu bar `Finder > Services > Compress with FinderX` is not the same acceptance path as right-clicking a selected file and choosing the FinderX contextual action.

When validating a bug, state which path was used. A fix can work through Finder Sync but fail through Services, or the reverse.

## iCloud Drive write access is stricter than selected-file access

The iCloud compression failure looked like a WebP encoder problem:

```text
Cannot write <name>-compressed.webp.
```

The root cause was sandbox permission. Finder gives access to the selected source file, but FinderX writes a new sibling output file next to the source. For iCloud Drive, read access to the selected file does not imply permission to create `*-compressed.webp` in the parent directory.

The debug build currently needs this entitlement for iCloud Drive sibling outputs:

```xml
<key>com.apple.security.temporary-exception.files.home-relative-path.read-write</key>
<array>
    <string>/Library/Mobile Documents/com~apple~CloudDocs/</string>
</array>
```

This is pragmatic for the local debug app. A distribution-grade design should prefer explicit user-granted output folder access, a save panel, or persisted security-scoped bookmarks instead of relying on a temporary exception.

## Hold security-scoped resources long enough

Starting security-scoped access inside a short service callback is not enough if the actual UI action happens later. FinderX must retain access while the compression UI and compression job use the URLs.

Current pattern:

- The service callback starts access for incoming selected URLs.
- `FinderXServiceRequests` stores those scoped URLs so the access does not end immediately.
- `CompressionRouter.select(_:)` also starts and retains security-scoped access for selected URLs.
- Old scoped URLs must be stopped before replacing selection.

Be careful with Swift concurrency and `@MainActor`: do not call a main actor-isolated cleanup method from a synchronous nonisolated `deinit`.

## Pasteboard file URLs have multiple shapes

Finder Services can deliver selected files in different pasteboard formats. Do not rely on only one representation.

Use this order:

1. `pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])`
2. `pasteboard.pasteboardItems` with `.fileURL` / `.URL`
3. `NSFilenamesPboardType` fallback

After collecting URLs, deduplicate them. This avoids empty Services callbacks and avoids double-processing the same selected file.

## Services cache is sticky

macOS can keep stale Services registrations around after rebuilding the app. If a menu item does not appear, appears in the wrong place, or launches the wrong build, refresh more than just the build output.

The debug install flow should:

- Build the debug app.
- Register it with Launch Services.
- Refresh Finder Services.
- Register and enable the Finder Sync extension.
- Remove or avoid stale TestDerivedData app registrations.
- Restart Finder.

Use `scripts/install_debug_app.sh --skip-tests` after tests have already passed.

## Verify installed entitlements, not just source plist

`FinderX/Resources/FinderX.entitlements` can be correct while the installed app is still old or signed without the entitlement.

Check the built app:

```sh
codesign -d --entitlements :- .build/DerivedData/Build/Products/Debug/FinderX.app
```

For this iCloud fix, the output must contain:

```text
com.apple.security.temporary-exception.files.home-relative-path.read-write
/Library/Mobile Documents/com~apple~CloudDocs/
```

## Real Finder acceptance matters

Unit tests are necessary but not sufficient for Finder integrations. The problematic path involved:

- Finder selection state.
- Finder Sync or Services dispatch.
- Launch Services routing.
- Sandbox entitlements.
- iCloud Drive.
- App UI state.

The regression test that mattered was:

1. Reveal an iCloud Drive image in Finder.
2. Right-click the selected image.
3. Choose `Services > Compress with FinderX` or the FinderX contextual item that is actually present.
4. Confirm FinderX opens with that image loaded.
5. Click `Compress`.
6. Confirm Finder shows `<name>-compressed.webp` in the same iCloud directory.

Do not treat direct app opening or shell-only checks as equivalent.

## Shell checks can be blocked by TCC

The terminal may not have macOS privacy permission to list some iCloud Drive paths:

```text
find: ... Operation not permitted
```

That does not necessarily mean FinderX failed. Confirm through Finder UI or grant terminal access deliberately. In the iCloud compression fix, FinderX succeeded and Finder showed the `.webp` output even though a shell `find` against the same directory was blocked.

## Unicode filenames can confuse shell glob checks

Chinese filenames and iCloud paths can involve Unicode normalization differences. A shell glob like:

```sh
ls *具体化与泛化-compressed*.webp
```

may fail even when Finder shows the file. Prefer Finder UI confirmation, exact file URLs from Finder, or non-glob listing through an environment that has permission.

## Temporary debug logs should be removed

It is useful to add short-lived `NSLog` / `Logger` instrumentation while diagnosing Finder callback timing and sandbox behavior. Before finishing:

```sh
rg -n "DEBUG-|NSLog" Sources FinderX
```

Remove temporary logs unless they are intentionally product logs.