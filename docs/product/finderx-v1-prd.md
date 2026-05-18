# FinderX v1 PRD and Technical Plan

## Problem Statement

Finder can preview and manipulate files, but its contextual workflows are weak for image compression. Users often need to inspect large images, especially in iCloud Drive, understand basic image properties, choose a compression strategy, and save a smaller copy without losing track of the original file.

FinderX is a general-purpose macOS file extension app. The first vertical slice is image compression from Finder's right-click menu.

## Goals

- Add a Finder right-click entry for supported image files.
- Open a FinderX compression window from that menu.
- Show enough image information for compression decisions.
- Compress JPEG and PNG inputs into a new file without overwriting the original.
- Provide automatic output format selection across JPEG, PNG, and WebP when available.
- Support single-file and simplified multi-file batch flows.
- Provide a full single-image before/after comparison experience after compression.
- Let users configure Finder Sync monitored folders, including iCloud Drive.

## Non-Goals

- Quick Look enhancement is not part of v1.
- Full EXIF browser is not part of v1.
- Image editing beyond compression and optional resize is not part of v1.
- History, undo, automatic updates, and Mac App Store distribution are not v1 goals.
- Pixel-diff heatmaps, SSIM/PSNR scoring, and AI visual quality scoring are out of scope.

## Solution

FinderX ships as a macOS app with a Finder Sync Extension. The extension contributes a `Compress Image with FinderX...` contextual menu item when selected Finder items include supported images inside configured monitored folders.

When invoked, the extension passes selected file URLs to the main FinderX app. FinderX opens an independent compression window. For a single image, it shows preview, image information, compression settings, and then a full before/after comparison after compression. For multiple files, it shows a batch summary, applies shared compression settings, and records per-file success, skip, and failure results.

The default output behavior is conservative: never overwrite the source file. Output is written beside each source as `name-compressed.ext`; collisions append a Finder-like numeric suffix such as `name-compressed 2.ext`.

## User Stories

1. As a Finder user, I want to right-click an image and choose `Compress Image with FinderX...`, so that I can start compression without leaving Finder.
2. As a user with images in iCloud Drive, I want FinderX to monitor iCloud Drive, so that the right-click action appears where I actually store large files.
3. As a user, I want to configure monitored folders, so that FinderX can work in the directories I care about.
4. As a user, I want the app to guide me to enable the Finder extension, so that I can complete macOS setup without guessing.
5. As a user, I want to see file name, format, pixel dimensions, file size, transparency, metadata presence, and color space when available, so that I can decide whether compression is appropriate.
6. As a user, I want the default compression mode to reduce file size while preserving visual content and pixel dimensions, so that I get a smaller file with minimal decision-making.
7. As a user, I want an `Auto` output format, so that FinderX can choose the smallest acceptable JPEG, PNG, or WebP result.
8. As a user, I want a `Lossless` mode, so that I can avoid lossy compression when exact visual preservation matters.
9. As a user, I want optional JPEG/WebP quality control, so that I can trade quality for file size.
10. As a user, I want resize to be available but off by default, so that compression does not unexpectedly change pixel dimensions.
11. As a user, I want metadata removal to be available and off/on according to the selected default, so that I can reduce file size and privacy exposure deliberately.
12. As a user, I want source files preserved, so that a bad compression result does not destroy my original.
13. As a user, I want output files saved beside the original, so that I can find them naturally in Finder.
14. As a user, I want file-name collisions handled automatically, so that batch compression does not stop on existing outputs.
15. As a user, I want single-file compression to reveal the output in Finder, so that I can immediately use the result.
16. As a user, I want batch compression to show a result summary instead of opening many Finder windows, so that the app does not disrupt my workspace.
17. As a user, I want unsupported mixed selections to be skipped with clear reasons, so that I can batch-select files without carefully filtering first.
18. As a user, I want side-by-side comparison, so that I can inspect visual differences after compression.
19. As a user, I want slider comparison, so that I can quickly compare details in the same image region.
20. As a user, I want synchronized zoom and pan, so that I can inspect original and compressed images at the same scale and position.
21. As a user, I want a 100% view, so that I can evaluate compression artifacts accurately.
22. As a user, I want batch results to let me open a single output for detailed comparison, so that I can inspect specific files when needed.

## Product Decisions

- The product is a general file extension app; image compression is the first capability.
- The primary entry point is Finder contextual menu, not Quick Look.
- v1 uses a Finder Sync Extension and accepts the monitored-folder model.
- Default monitored folders are `Downloads`, `Desktop`, `Pictures`, and iCloud Drive.
- The contextual menu is a direct `Compress Image with FinderX...` item in v1 because Finder Sync contextual menu submenus are not reliable enough for acceptance. Future actions can be added as separate direct items or moved behind another entry point after validation.
- The compression UI is an independent FinderX app window, not a Finder popover.
- v1 supports JPEG and PNG input. Other image types may be shown as unsupported or skipped.
- v1 output candidates are JPEG, PNG, and WebP, subject to system encoder availability.
- `Auto` is the default output format.
- `Balanced` is the default compression mode and may use lossy JPEG/WebP compression.
- `Lossless` is available as an explicit mode.
- Resize is available but defaults to off.
- Original files are never overwritten in v1.
- Single-image comparison is a first-class v1 feature.
- Batch mode uses simplified shared settings and summary results.

## Technical Plan

### Platform

- Minimum OS: macOS 14.
- Main app: SwiftUI.
- Finder extension: Finder Sync Extension using AppKit/Foundation APIs.
- High-performance comparison view: start in SwiftUI; use AppKit via `NSViewRepresentable` if synchronized zoom, pan, or rendering performance requires it.
- Distribution target: local development and Developer ID-ready architecture. Mac App Store is not a v1 target.
- Sandbox: enabled.

### Proposed Modules

- `FinderXApp`: owns app lifecycle, Settings, compression window presentation, and extension activation guidance.
- `FinderSyncExtension`: owns contextual menu contribution, selected item collection, and handoff to the main app.
- `ImageCompressionCore`: deep, testable module for image inspection, format capability detection, encoding, output naming, and batch orchestration.
- `ImageComparisonUI`: owns single-image comparison modes, zoom, pan, and preview rendering.
- `MonitoredFolderStore`: owns default folders, user-added folders, security-scoped bookmarks, and Finder Sync directory registration.
- `CompressionJobStore`: transient in-memory job/result state for the active compression window. Persistent history is out of scope.

### Extension-to-App Handoff

The implementation should validate the most reliable handoff path early. Candidate approaches:

- Custom URL scheme for opening the main app with a job token.
- App Group container for selected-file payloads plus URL scheme or distributed notification.
- Distributed notification for foreground app coordination where appropriate.

The preferred shape is: Finder extension writes selected file URLs or security-scoped references into a shared location, then asks FinderX to open a compression window for that job. The final mechanism should be chosen during implementation after a small technical spike.

### File Access

- User-added monitored folders should be stored as security-scoped bookmarks.
- Default folders should be registered on first launch when available.
- iCloud files should be checked for readability before compression.
- If an iCloud file is not locally available or cannot be read, the UI should show a clear per-file failure or waiting state rather than failing the whole batch silently.

### Image Inspection

The app should inspect:

- File name and containing directory.
- Input format.
- Pixel width and height.
- File size.
- Transparency presence.
- Metadata presence.
- Color space when stable via system APIs.

### Compression Engine

- Use system frameworks first: Image I/O, Core Graphics, Uniform Type Identifiers.
- Detect WebP write support at runtime using available system type identifiers/encoders.
- In `Auto` mode:
  - Preserve pixel dimensions unless resize is explicitly enabled.
  - Preserve transparency constraints by default.
  - For transparent images, do not choose JPEG automatically.
  - For non-transparent images, consider JPEG and WebP; skip PNG unless lossless or beneficial.
  - Choose the smallest successful candidate that satisfies mode constraints.
- If user explicitly chooses JPEG for a transparent image, warn that transparency will be lost.

### Output Naming

- Default output path: source directory.
- Default base name: `sourceName-compressed`.
- Extension follows actual output format.
- Existing file collisions append numeric suffixes: `sourceName-compressed 2.ext`, `sourceName-compressed 3.ext`.

### Compression Window

Single-image mode:

- Original preview.
- Decision fields.
- Settings: output format, compression mode, quality, resize long edge, metadata retention.
- Compress action.
- Completion summary: output format, output size, saved bytes, saved percentage, output file name.
- Comparison modes: side by side, slider compare, synchronized zoom/pan, 100%.

Batch mode:

- Total selected count.
- Supported count and skipped count.
- Total original size.
- Shared settings.
- Per-file progress/result list.
- Total compressed size and total savings.
- Failure list with reasons.
- Reveal controls without opening many Finder windows automatically.

## Testing Decisions

Good tests should validate external behavior and stable contracts, not UI implementation details or private framework call ordering.

Core module tests:

- Format detection for JPEG, PNG, unsupported files, and mixed selections.
- Output naming and collision behavior.
- Auto format decision rules, including transparent images and WebP unavailable cases.
- Lossless versus Balanced mode constraints.
- Resize-off behavior preserves pixel dimensions.
- Batch result aggregation with success, skipped, and failed files.

Integration/manual tests:

- Finder extension appears in configured folders.
- Finder extension does not depend on Quick Look.
- iCloud Drive folder can be configured and used when files are locally readable.
- Single image opens compression window and reveals output after success.
- Batch compression summarizes results without opening multiple Finder windows.
- Extension enablement guidance works on a clean macOS user profile.

UI verification:

- Single-image comparison renders original and compressed images.
- Side-by-side and slider modes remain synchronized under zoom and pan.
- 100% view maps image pixels predictably.
- Long filenames and batch failure messages do not break layout.

## Risks and Open Questions

- Finder Sync Extensions are directory-scoped; global Finder coverage is not guaranteed.
- macOS may require explicit user action to enable the extension, and the exact settings deep link can vary by OS version.
- WebP write support must be verified at runtime on the target macOS versions.
- The extension-to-main-app handoff needs an early technical spike.
- iCloud files can be placeholders, unavailable, or slow to download.
- Compression quality expectations are subjective; v1 should avoid promising perceptual equivalence beyond the selected mode.
- Full comparison UI can become complex; implement it as a contained module so core compression remains testable.

## Suggested Next Step

Create the Xcode project skeleton with:

- macOS app target.
- Finder Sync Extension target.
- Shared Swift package or framework for `ImageCompressionCore`.
- Initial Settings screen for monitored folders.
- A technical spike proving Finder right-click menu to main-app compression window handoff.

## Source Manifest

### Sources

- User conversation in this session defining FinderX as a general macOS file extension app with image compression as v1.
- User-provided screenshot of macOS Quick Look image preview, used to discuss but defer Quick Look toolbar/content enhancement.
- Local repository state: empty git repository at `/Users/ivan/workspace/ai/finderx`.
- Workflow guidance read from `/Users/ivan/.agents/docs/agents/workflows.md`.
- Handoff policy read from `/Users/ivan/.agents/docs/agents/handoff-policy.md`.
- PRD skill guidance read from `/Users/ivan/.agents/skills/to-prd/SKILL.md`.
- Apple documentation consulted during discussion: Finder Sync Extension, Quick Look Preview Extension, Uniform Type Identifiers, and Image I/O concepts.

### Produced artifacts

- `docs/product/finderx-v1-prd.md`

### Key decisions

- Use Finder right-click menu as v1 entry point.
- Do not use Quick Look enhancement as v1 core delivery.
- Use Finder Sync Extension with configurable monitored folders.
- Default monitored folders include iCloud Drive.
- Use a standalone FinderX compression window.
- Support JPEG/PNG input and Auto output across JPEG/PNG/WebP where available.
- Default to Balanced compression with Lossless available.
- Preserve source files and write new outputs beside originals.
- Build full single-image comparison in v1.

### Verification evidence

- Repository inspection showed no existing source files, docs, ADRs, or issue configuration beyond `.git`.
- No code or tests were run because this step produced a planning document only.

### Open questions / risks

- Confirm WebP write support on the exact development machine and minimum supported macOS.
- Validate extension-to-app handoff mechanism with a technical spike.
- Validate Finder Sync extension behavior for iCloud Drive and user-added monitored folders.
- Decide whether to publish this PRD into an issue tracker after one is configured.
