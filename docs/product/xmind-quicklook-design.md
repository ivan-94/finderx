# XMind Quick Look Design

## Source Manifest

- User request in this session: support `.xmind` Finder thumbnails and Quick View.
- User-approved scope decisions in this session: FinderX provides the capability itself; P0 uses embedded XMind thumbnails only; no custom fallback UI; no settings or menu; do not depend on XMind.app.
- `AGENTS.md`: FinderX architecture, workflow, install and verification rules.
- `README.md`: current targets and debug install/test commands.
- `scripts/generate_xcodeproj.rb`: authoritative Xcode target generator.
- `scripts/install_debug_app.sh`: authoritative local Finder acceptance installer.
- `FinderX/Resources/Info.plist`: app services, URL scheme, document type declarations.

## P0 Scope

FinderX provides Finder thumbnails and Quick View previews for `.xmind` files by reading the thumbnail image already stored inside the XMind ZIP container.

The feature is automatic after installing FinderX. It adds no main-window UI, no Finder menu item, and no settings. FinderX declares viewer support for `.xmind` but does not take over double-click opening.

## Behavior

- Supported files: `.xmind` files and the XMind document UTI.
- Thumbnail source: known embedded thumbnail paths such as `Thumbnails/thumbnail.png`, with small PNG/JPEG path variants.
- Finder thumbnail: returns the embedded image to the system thumbnail provider.
- Quick View: displays the same image as the preview content.
- Missing thumbnail, damaged ZIP, unsupported compression, or decode failure: return no preview and let the system default behavior take over.
- iCloud files: support files that are available locally; do not actively materialize placeholders.
- Caching: rely on system Quick Look/thumbnail caching; FinderX does not write its own thumbnail cache.

## Architecture

Add a pure Swift framework:

- `XMindPreviewCore`: parses the `.xmind` ZIP central directory, finds candidate thumbnail entries, reads stored or deflated image data, validates that ImageIO can identify dimensions, and returns data plus type metadata.

Add two app extensions:

- `FinderXXMindThumbnailExtension`: Quick Look Thumbnail Extension using `QLThumbnailProvider`.
- `FinderXXMindPreviewExtension`: Quick Look Preview Extension using data-based `QLPreviewProvider`.

Both extensions depend on `XMindPreviewCore`. The main app embeds both extensions.

## Testing

Unit tests cover the core parser:

- Extracts a real PNG thumbnail from a generated `.xmind` fixture.
- Supports JPEG thumbnail candidates.
- Returns nil when no candidate thumbnail exists.
- Returns nil for damaged ZIP input.
- Does not process non-`.xmind` files.

Project verification remains:

```sh
xcodebuild -project FinderX.xcodeproj -scheme FinderX -destination platform=macOS -derivedDataPath .build/TestDerivedData CODE_SIGNING_ALLOWED=NO test
```

Local Finder acceptance remains:

```sh
scripts/install_debug_app.sh --skip-tests
```

The installer also refreshes Launch Services and PluginKit so the Quick Look extensions are discoverable from `/Applications/FinderX.app`.
