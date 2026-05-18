# FinderX 原地压缩 + Diff 确认 — 实现计划

## Context

FinderX 当前始终将压缩结果写入 `-compressed` 后缀的新文件，原文件完全保留。用户希望在保留此安全行为的同时，增加一个可选的"原地压缩"模式：压缩到临时文件 → 在 UI 中展示 diff 对比 → 用户确认后才替换原文件。

这个功能的需求已经通过 `/grill-me` 逐条对齐，所有决策已确认。本计划基于对齐结果制定。

---

## 对齐结果摘要

| # | 决策 | 选项 |
|---|------|------|
| 1 | 原地压缩策略 | 先写临时文件 → 用户确认 → `replaceItem` 原子替换 |
| 2 | 入口方式 | 设置面板加 "Overwrite original" toggle，单图时显示 |
| 3 | Diff 视图 | 内嵌在主视图，复用现有 `ImageComparisonView` |
| 4 | 扩展名处理 | 跟着输出格式变（PNG→WebP 则 `.png`→`.webp`） |
| 5 | 批量支持 | 批量不支持原地压缩，多选时 toggle 隐藏 |
| 6 | 确认按钮 | 「Replace Original」「Cancel」 |
| 7 | Cancel 后行为 | 删除临时文件，回到参数设置界面 |
| 8 | 替换策略 | `FileManager.replaceItem(at:withItemAt:)` 原子替换 |
| 9 | 替换失败 | `IssueBanner` 红色错误提示，保留 diff 视图可重试 |
| 10 | 替换成功后 | 回到参数设置界面，`.alert` 提示成功（含大小变化） |
| 11 | 临时文件位置 | 系统临时目录 `NSTemporaryDirectory()` |
| 12 | Toggle 默认 | 默认关闭，不持久化 |
| 13 | 临时文件清理 | App 关闭时主动清理 |
| 14 | Finder Extension | 暂不支持原地压缩 |
| 15 | 压缩中按钮 | 保持现有禁用状态，文案不变 |
| 16 | 确认界面布局 | 左侧 `ImageComparisonView`，右侧确认操作面板 |
| 17 | Security Scope | 替换前保持 `startAccessingSecurityScopedResource` |
| 18 | 临时文件命名 | `finderx-inplace-{UUID}.{ext}` |
| 19 | 压缩失败处理 | 与现有行为一致，未触碰原文件 |
| 20 | 替换后 URL | 更新为新的 URL（扩展名可能变），重新 inspect |

---

## 技术方案

### 1. ImageCompressionCore 扩展

**文件**: `Sources/ImageCompressionCore/ImageCompressionCore.swift`

新增类型和方法：

- **`InplaceCompressionSession`** — 持有临时文件 URL、原文件 URL、压缩结果元数据，负责生命周期管理。
  - `init(sourceURL: URL, options: CompressionOptions)` — 执行压缩到临时目录，存储临时文件路径。
  - `commit() throws` — 调用 `FileManager.replaceItem(at: sourceURL, withItemAt: tempURL)` 原子替换。
  - `discard()` — 删除临时文件。
  - `deinit` 中自动 `discard()`（防止泄漏）。

- **`ImageCompressor.compressInPlace(_:options:)`** — 返回 `InplaceCompressionSession`，内部复用现有 `compress()` 的编码逻辑，但输出到临时目录。

### 2. SwiftUI App 界面变更

**文件**: `Sources/FinderXApp/FinderXApp.swift`

- `CompressionViewModel` 新增 `@Published var overwriteOriginal = false` 和原地压缩状态机。
- `CompressionInspector` 新增 "Overwrite original" toggle（单图时显示）。
- `SingleImageView` 新增原地压缩确认布局分支。
- 新增 `InplaceConfirmationView`（左侧对比 + 右侧操作面板）。
- 替换成功后 `.alert` 提示。

### 3. 测试

**文件**: `Tests/ImageCompressionCoreTests/ImageCompressionCoreTests.swift`

新增 Core 层原地压缩相关测试。

---

## 文件修改清单

| 文件 | 修改类型 | 说明 |
|------|---------|------|
| `Sources/ImageCompressionCore/ImageCompressionCore.swift` | 新增 + 修改 | 新增 `InplaceCompressionSession`、新增 `ImageCompressor.compressInPlace()` |
| `Sources/FinderXApp/FinderXApp.swift` | 大幅修改 | ViewModel 新增状态和方法、Inspector 新增 toggle、SingleImageView 新增布局分支、新增确认视图和 alert |
| `Tests/ImageCompressionCoreTests/ImageCompressionCoreTests.swift` | 新增测试 | `compressInPlace` 成功、commit 替换、discard 清理、扩展名变化 |

---

## 风险

- `replaceItem` 在 sandbox 中对某些目录（如 iCloud Drive）可能受限。回退方案：先 `copyItem` 到同目录临时名，再 `removeItem` 原文件，再 `moveItem`。
- Security Scoped Resource 在替换操作期间需要保持活跃。

---

## Source Manifest

### Sources

- `AGENTS.md`: project workflow, FinderX architecture, Finder acceptance, WebP, sandboxing, and UI guardrails.
- `GOTCHAS.md`: Finder Sync vs Services behavior, stale service registration, security-scoped access, and real Finder acceptance traps.
- `docs/inplace-compression-plan.md`: original implementation plan and aligned decisions.
- `Sources/ImageCompressionCore/ImageCompressionCore.swift`: compression, output naming, WebP encoding, and new in-place session behavior.
- `Sources/FinderXApp/FinderXApp.swift`: SwiftUI compression UI, routing, security-scoped selection state, and replacement confirmation flow.
- `Tests/ImageCompressionCoreTests/ImageCompressionCoreTests.swift`: regression tests for compression core contracts.
- `scripts/generate_xcodeproj.rb`: Xcode project generator used by install/debug flow.

### Produced artifacts

- `Sources/ImageCompressionCore/ImageCompressionCore.swift`: added in-place compression session, temp output naming, commit/discard lifecycle, and extension-change replacement handling.
- `Sources/FinderXApp/FinderXApp.swift`: added overwrite toggle, diff confirmation UI, router-backed replacement success alert, and selection/security-scope synchronization.
- `Tests/ImageCompressionCoreTests/ImageCompressionCoreTests.swift`: added in-place compression tests for temp creation, commit, extension changes, discard, deinit cleanup, and target-collision refusal.
- `scripts/generate_xcodeproj.rb`: added the missing `fileutils` require needed by the installer.

### Key decisions

- Original files are replaced only after a successful temporary compression and explicit `Replace Original` confirmation.
- The temporary output file uses `finderx-inplace-{UUID}.{ext}` inside a matching temporary directory.
- Extension-changing replacements refuse to overwrite an existing target sibling.
- Replacement success alert state lives at the router/root level so it survives detail view recreation after the selected URL changes.

### Verification evidence

- `xcodebuild -project FinderX.xcodeproj -scheme FinderX -destination platform=macOS -derivedDataPath .build/TestDerivedData CODE_SIGNING_ALLOWED=NO test` passed.
- `scripts/install_debug_app.sh --skip-tests` passed after the `fileutils` script fix.
- PluginKit showed `+ dev.finderx.FinderX.FinderExtension(0.1.0)` registered from `.claude/worktrees/inplace-compression/.build/DerivedData/.../FinderXFinderExtension.appex`.
- Real UI acceptance used `~/Downloads/FinderX-Agent-Test/inplace-alert.jpg`: enabled `Overwrite original`, compressed to a temp WebP, saw the diff confirmation, clicked `Replace Original`, saw the `Replaced` alert, and confirmed the UI reloaded `inplace-alert.webp`.

### Open questions / risks

- Finder Sync and Finder Services should continue to be validated separately because macOS can route them through different registration paths.
- iCloud Drive write behavior remains entitlement-sensitive; acceptance should still include an iCloud file before release.
