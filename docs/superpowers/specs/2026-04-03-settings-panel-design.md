# Settings Panel Design: Text Size & Font

## Summary

Add a settings panel to the MarkdownQuickLookApp host app that lets users adjust text size (7 discrete levels) and font family (3 curated options) for Markdown Quick Look previews.

## Requirements

- Text size slider with 7 stops: XS, S, M (default), L, XL, XXL, XXXL
- Font picker with 3 options: System (San Francisco), Serif (New York), Monospaced (SF Mono)
- Code blocks always render in monospaced font regardless of font setting
- Settings apply on next Quick Look preview (no live extension updates needed)
- Settings UI lives directly on the existing install status screen in the host app

## Architecture: Settings struct passed through renderer

### Settings Model (`MarkdownRendering` framework)

`MarkdownRenderSettings` struct with two properties:

**`TextSizeLevel` enum** — 7 cases with scale factors:

| Level | Scale | Body | H1 | H2 | H3 | H4 | Code |
|-------|-------|------|-----|-----|-----|-----|------|
| extraSmall | 0.80 | 12pt | 24pt | 19pt | 16pt | 14pt | 10pt |
| small | 0.90 | 14pt | 27pt | 22pt | 18pt | 15pt | 12pt |
| medium (default) | 1.00 | 15pt | 30pt | 24pt | 20pt | 17pt | 13pt |
| large | 1.10 | 17pt | 33pt | 26pt | 22pt | 19pt | 14pt |
| extraLarge | 1.25 | 19pt | 38pt | 30pt | 25pt | 21pt | 16pt |
| extraExtraLarge | 1.40 | 21pt | 42pt | 34pt | 28pt | 24pt | 18pt |
| extraExtraExtraLarge | 1.55 | 23pt | 47pt | 37pt | 31pt | 26pt | 20pt |

**`FontFamily` enum** — 3 cases:
- `system` — San Francisco (NSFont.systemFont)
- `serif` — New York (NSFont with "New York" design)
- `monospaced` — SF Mono (NSFont.monospacedSystemFont)

The struct:
- Provides `static var default` returning `(.medium, .system)`
- Is `Codable` for UserDefaults serialization
- Scale factor also applies proportionally to `LayoutConstants` (lineSpacing, paragraphSpacing, hangingIndent)

### Shared Preferences (App Group)

**App group identifier:** `group.com.rzkr.MarkdownQuickLook`

Added as an entitlement to both the host app (`MarkdownQuickLookApp`) and the extension (`MarkdownQuickLookPreviewExtension`) in `project.yml`.

**`MarkdownSettingsStore`** class in `MarkdownRendering` framework:
- Reads/writes `MarkdownRenderSettings` to `UserDefaults(suiteName: "group.com.rzkr.MarkdownQuickLook")`
- Stores as a single JSON-encoded blob under key `"renderSettings"`
- Returns `MarkdownRenderSettings.default` if nothing stored or decoding fails
- Conforms to `ObservableObject` with `@Published var settings` for SwiftUI binding in host app
- Extension reads via `MarkdownSettingsStore().settings` at render time (no observation needed)

### Renderer Integration

`MarkdownDocumentRenderer` changes:
- `init(settings: MarkdownRenderSettings = .default)` — stored as a property
- `headingFont(for:level:)` — uses `settings.scaleFactor` and `settings.fontFamily`
- `paragraphAttributes()` — uses scaled body size and selected font family
- `quoteAttributes()` — uses scaled body size and selected font family
- `hangingIndentAttributes()` — uses scaled body size and selected font family
- Code block styling — uses `settings.scaleFactor` only (always monospaced font)
- `LayoutConstants` values scale proportionally with text size level

In `PreviewViewController.renderPayload()`: read settings from `MarkdownSettingsStore()` and pass into `MarkdownDocumentRenderer(settings:)`.

Existing tests remain unchanged since `settings` defaults to `.default`. New tests verify non-default settings produce correct font sizes and families.

### Settings UI in Host App

Controls added directly to `StatusView`, below existing install status content, separated by a section header ("Preview Settings"):

**Text size** — `Slider` with 7 discrete stops. Small "Aa" on left end, large "Aa" on right end (Apple convention). Current level name displayed (e.g. "Large").

**Font** — `Picker` with `.segmented` style. Three options: "System", "Serif", "Mono".

**Preview snippet** — Below the controls, a small live preview showing a heading and short paragraph rendered with current settings using `MarkdownDocumentRenderer`. Lets user see the effect before opening a Quick Look preview.

Controls bind to `MarkdownSettingsStore` as `@ObservedObject`. Changes persist immediately to shared UserDefaults.

## Files Changed

| File | Change |
|------|--------|
| `project.yml` | Add app group entitlement to host app and extension targets |
| `MarkdownRendering/Sources/MarkdownRenderSettings.swift` | New: settings struct, enums, defaults |
| `MarkdownRendering/Sources/MarkdownSettingsStore.swift` | New: UserDefaults persistence with ObservableObject |
| `MarkdownRendering/Sources/MarkdownDocumentRenderer.swift` | Accept settings, use scaled sizes and font family |
| `MarkdownQuickLookPreviewExtension/PreviewViewController.swift` | Read settings from store, pass to renderer |
| `MarkdownQuickLookApp/App/StatusView.swift` | Add settings controls and preview snippet |
| `MarkdownRendering/Tests/MarkdownRenderSettingsTests.swift` | New: test scale factors, codable, defaults |
| `MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift` | Add tests for non-default settings |

## Out of Scope

- Live preview updates in the Quick Look extension (settings apply on next preview)
- Full system font picker (curated list only)
- Per-element font customization (single font choice applies to all non-code text)
- Spacing/padding customization beyond what scales with text size
