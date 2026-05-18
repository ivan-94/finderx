# FinderX

FinderX is a macOS file extension app. The first vertical slice adds image compression from Finder.

## Current Targets

- `FinderX`: SwiftUI macOS app with a compression window and settings screen.
- `FinderXFinderExtension`: Finder Sync Extension that contributes `Compress with FinderX` and `Copy FinderX Link`.
- `ImageCompressionCore`: shared image inspection, output naming, and compression engine.
- `FinderXLinking`: shared FinderX deep-link creation and resolution.
- `FinderXCompressCLI`: command-line smoke-test entry point for the same compression core.
- `ImageCompressionCoreTests`: core behavior tests.
- `FinderXLinkingTests`: deep-link behavior tests.

## Build

Generate the Xcode project after changing `scripts/generate_xcodeproj.rb`:

```sh
ruby scripts/generate_xcodeproj.rb
```

For Finder acceptance on a local machine, use the debug installer:

```sh
scripts/install_debug_app.sh
```

This intentionally runs unsigned tests in `.build/TestDerivedData`, then builds the locally signed Finder-loadable app in `.build/DerivedData`, bundles the local `cwebp` encoder for WebP output, refreshes Launch Services and Finder Services, registers and enables the Finder Sync Extension, and restarts Finder. Do not run `CODE_SIGNING_ALLOWED=NO test` against `.build/DerivedData` after installing the extension; that can overwrite the signed app bundle and make the contextual menu disappear.

WebP output requires Homebrew `webp` on the development machine:

```sh
brew install webp
```

Build a shareable DMG installer:

```sh
scripts/build_installer.sh
```

The default output is an ad-hoc signed internal-sharing DMG under `dist/`.
It builds for the current Mac architecture so the app matches the bundled
Homebrew `cwebp` helper. For wider distribution, build with a Developer ID
Application certificate and notarize the resulting DMG:

```sh
scripts/build_installer.sh --signing-identity "Developer ID Application: Your Team"
```

Build with local signing:

```sh
xcodebuild -project FinderX.xcodeproj -scheme FinderX -destination platform=macOS -derivedDataPath .build/DerivedData build
```

Run tests:

```sh
xcodebuild -project FinderX.xcodeproj -scheme FinderX -destination platform=macOS -derivedDataPath .build/TestDerivedData CODE_SIGNING_ALLOWED=NO test
```

If `xcodebuild test` cannot contact `testmanagerd` from a sandboxed agent session, run the same command outside the sandbox.

## FinderX Links

Right-clicking one ordinary file in a monitored Finder folder shows `Copy FinderX Link`. The action silently copies a `finderx://open?...` URL to the clipboard as both text and URL pasteboard content.

For iCloud Drive files, Finder may not invoke Finder Sync contextual menus. FinderX also registers Finder Services for `Compress with FinderX` and `Copy FinderX Link`; use Finder's `Services` menu when the top-level Finder Sync items are not available.

iCloud Drive files include a migratable `icloud` relative path plus an absolute `file` fallback. Opening a copied link resolves the iCloud path first, falls back to the absolute path when needed, and delegates the file to macOS default app handling without showing the FinderX compression window.

## Smoke Test Compression

Create a sample JPEG:

```sh
swift -module-cache-path .build/module-cache scripts/create_sample_image.swift /private/tmp/FinderX-Agent-Test/finderx-e2e-source.jpg
```

Compress it with the built CLI:

```sh
.build/DerivedData/Build/Products/Debug/finderx-compress /private/tmp/FinderX-Agent-Test/finderx-e2e-source.jpg
```

Verify dimensions:

```sh
sips -g pixelWidth -g pixelHeight /private/tmp/FinderX-Agent-Test/finderx-e2e-source.jpg '/private/tmp/FinderX-Agent-Test/finderx-e2e-source-compressed.jpg'
```

## Finder Extension Verification

After a locally signed build, register the app bundle and check for the Finder Sync extension:

```sh
scripts/install_debug_app.sh --skip-tests
```

Expected match:

```text
+    dev.finderx.FinderX.FinderExtension(0.1.0)
```

The leading `+` indicates the extension is enabled. If it is missing, run `scripts/install_debug_app.sh --skip-tests` again.
