# Markdown Quick Look App Design

## Goal

Build a minimal macOS app that ships a modern Quick Look Preview Extension and makes a best-effort attempt to render standard `.md` files as formatted Markdown in Finder Quick Look instead of the default plain-text preview.

## Constraints

- The implementation must use the modern app + Quick Look Preview Extension model, not the legacy `.qlgenerator` plugin system.
- The extension will target the existing Markdown UTI `net.daringfireball.markdown`.
- This is explicitly a best-effort design, not a supported guarantee that macOS will replace the built-in Markdown/plain-text preview path.
- The first version only needs Finder Quick Look preview behavior. Thumbnails, editing, and custom document packaging are out of scope.
- The host app exists primarily to install and register the extension, with only minimal utility UI.

## Why This Shape

Apple’s current Quick Look Preview Extension model is documented as providing previews for documents an app owns. That does not cleanly match the requirement to “overtake” existing `.md` handling. The design therefore aims for the narrowest modern implementation that can plausibly work on a given machine while clearly isolating the unsupported assumption: claiming `net.daringfireball.markdown` as a preview target.

This keeps the system-specific risk localized to extension registration and Finder behavior, while the rendering and UI remain reusable if the project later pivots to a supported custom document type.

## Architecture

The project will contain three focused units:

### 1. Host App

Responsibilities:

- Ship the Quick Look Preview Extension
- Declare Markdown as a supported document type for viewing
- Provide a small app window with status text, caveats, and local test instructions

Design notes:

- The app registers `net.daringfireball.markdown` in `CFBundleDocumentTypes`
- It uses viewer semantics and a non-owner rank of `Alternate`, so the app advertises compatibility without asserting true ownership of Markdown
- The app UI is intentionally simple and static, not a full editor

### 2. Shared Markdown Renderer

Responsibilities:

- Read Markdown file contents from a file URL
- Parse Markdown into a renderable representation
- Expose a small API the preview extension can consume without Quick Look-specific knowledge

Design notes:

- Prefer Apple-native Markdown parsing first, using `AttributedString(markdown:)` or equivalent AppKit/Foundation support
- Keep this layer independent from both the app and the extension so it can be reused later if the project switches to a supported custom document type
- If native parsing proves too limited, the renderer boundary allows a parser swap without restructuring the extension

### 3. Quick Look Preview Extension

Responsibilities:

- Declare `QLSupportedContentTypes = [net.daringfireball.markdown]`
- Receive the target file URL from Quick Look
- Build and display a formatted preview view

Design notes:

- The preview UI is a native SwiftUI/AppKit view hosted by the extension entry point
- The extension loads quickly and fails clearly if parsing the Markdown file is impossible
- All Quick Look-specific integration code stays confined to the extension target

## Data Flow

1. Finder or another Quick Look client requests a preview for a `.md` file.
2. If macOS chooses this extension for `net.daringfireball.markdown`, the extension receives the file URL.
3. The extension asks the shared renderer to load and parse the file.
4. The renderer returns a renderable result for headings, paragraphs, lists, links, code spans, code blocks, and block quotes as supported by the chosen native parser.
5. The extension displays that result in a scrollable preview view.

If macOS does not choose the extension, the system falls back to the built-in preview path. That is an expected product limitation, not necessarily an implementation failure.

## UX

### Host App

The host app window communicates only the essentials:

- what the app installs
- which content type the extension targets
- that the behavior is best-effort
- how to test it locally

The UI does not need preferences, editing, file import, or document browsing in v1.

### Preview UI

The preview prioritizes readability over fidelity:

- scrollable layout
- clear heading hierarchy
- body text with sensible spacing
- visible links
- monospaced rendering for code
- a neutral background that feels native in Quick Look

If some Markdown constructs are unsupported by the native parser, the preview may degrade gracefully rather than blocking the whole render.

## Error Handling

The renderer and preview extension handle these cases explicitly:

- file cannot be read
- file contents are empty
- Markdown parsing fails
- extension is invoked for a file whose content type claims Markdown but whose contents are malformed

Expected behavior:

- show a compact error or fallback text inside the preview rather than crashing or hanging
- keep error strings actionable and tied to the actual file state
- avoid hiding all content if partial rendering is possible

## Verification Strategy

The project must include a repeatable local verification path.

### Build/Registration Verification

- Build the app and embedded preview extension from Xcode or `xcodebuild`
- Confirm the app bundle and extension bundle are produced correctly
- Provide a script that prints or performs the local registration/reload steps needed for Quick Look iteration

### Behavior Verification

- Include at least one sample Markdown fixture in the repo
- Open the sample in Finder Quick Look and observe whether the custom preview appears
- Document the expected two valid outcomes:
  - Finder uses the custom Markdown preview
  - Finder continues using the built-in plain-text preview even though the app and extension are configured correctly

### Diagnostic Verification

- Include commands or a helper script for clearing Quick Look caches and retrying
- Keep this logic in tooling rather than requiring users to remember manual steps

## Project Structure

The initial structure keeps responsibilities isolated:

- `MarkdownQuickLookApp/`
  - host app sources
- `MarkdownQuickLookPreviewExtension/`
  - extension entry point and preview UI
- `MarkdownRendering/`
  - shared renderer code
- `Fixtures/`
  - sample Markdown files for testing
- `Scripts/`
  - local build/test/reload helpers

The exact Xcode layout can vary, but the code preserves these boundaries.

## Out of Scope

- Legacy `.qlgenerator` support
- Thumbnail generation
- Markdown editing
- Full Markdown spec fidelity
- WebKit-based HTML rendering in v1
- A guaranteed override of macOS built-in `.md` preview behavior

## Risks

### Primary Risk

The main risk is platform behavior rather than code correctness: Finder may continue preferring its built-in preview flow for `.md` even when the modern Preview Extension is valid and correctly registered.

### Secondary Risks

- Native Markdown parsing may not render all constructs well enough for Quick Look
- Quick Look extension registration and cache behavior can make testing appear flaky
- The host app may be installable and correct while still not changing real Finder behavior

## Exit Criteria

The design is considered implemented successfully when:

- a macOS app builds with an embedded Quick Look Preview Extension
- the extension targets `net.daringfireball.markdown`
- the extension can render a Markdown file into a formatted native preview view
- the repo contains a documented local verification path
- the project makes the best-effort nature of `.md` takeover explicit in both code structure and user-facing messaging

## Future Refactor Path

If the project later moves to the fully supported model, the migration target should be:

- keep the host app
- keep the shared renderer
- replace the claimed content type with an app-owned custom document UTI and extension

That migration requires only plist/registration changes and minimal extension wiring changes, not a rewrite of the renderer or preview UI.
