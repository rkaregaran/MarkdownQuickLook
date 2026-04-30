# Performance Instrumentation Design

## Goal

Add local developer instrumentation that helps identify the highest-impact performance work for Markdown Quick Look.

The primary product goal is faster Quick Look preview open latency: the time from a Quick Look preview request entering the extension to the rendered Markdown view being applied. Renderer and thumbnail measurements support that goal by showing which internal stages are actually responsible for user-visible delay.

## Scope

This is local developer debugging only.

In scope:

- Debug-only timing spans for preview, renderer, and thumbnail flows
- Instruments-friendly signposts using Apple's logging APIs
- Repeatable performance fixtures for before-and-after comparison
- A local profiling script that builds the app and prepares the Quick Look environment
- Unit or smoke coverage that verifies instrumentation remains inert and does not alter behavior

Out of scope:

- Production telemetry
- Network reporting
- Persistent user analytics
- User-facing performance settings
- Privacy policy changes
- Hard CI timing gates based on wall-clock performance

## Current Flow

The preview extension enters through `PreviewViewController.preparePreviewOfFile(at:)`.

The current request flow is:

1. Apply the loading preferred size.
2. Start a cancellable background prepare task through `PreviewLoadingCoordinator`.
3. Read and parse the Markdown file in `MarkdownDocumentRenderer.prepareDocument(fileAt:)`.
4. Load render settings from `MarkdownSettingsStore`.
5. Render a `MarkdownRenderPayload` on the main actor.
6. Swap the SwiftUI root view to rendered content.
7. Compute and apply the rendered preferred size.

The thumbnail extension enters through `ThumbnailProvider.provideThumbnail(for:_:)`.

The current thumbnail flow is:

1. Receive a thumbnail request with maximum size and scale.
2. Prepare the Markdown document.
3. Render the document on the main thread.
4. Draw the attributed string into the thumbnail context.

## Measurement Architecture

Add a small instrumentation layer shared by the preview extension, thumbnail extension, and renderer.

The instrumentation layer should:

- Use `OSLog` and `OSSignposter` or the closest available Apple signpost API for the deployment target.
- Compile or no-op behind a local debug condition so release behavior remains unchanged.
- Keep call sites lightweight and avoid expensive string formatting on hot paths.
- Never log Markdown file contents.
- Log only metadata that helps performance analysis: timing, result state, file size, character count, block count, and feature counts.

The primary trace is one `preview.request` interval that spans the whole preview request lifecycle. Nested spans break down the work that contributes to that request.

Recommended preview signposts:

| Signpost | Type | Purpose |
|---|---|---|
| `preview.request` | interval | End-to-end preview request wall time |
| `preview.prepare` | interval | Background file read, validation, and block parse |
| `preview.settings` | interval | App Group defaults read and settings decode |
| `preview.render` | interval | Main-actor attributed string construction |
| `preview.applyView` | interval | SwiftUI root view update and preferred size calculation |
| `preview.cancel` | event | Request cancelled by Quick Look or superseded work |
| `preview.stale` | event | Older request rejected after a newer request began |
| `preview.failure` | event | Renderer or generic failure mapped to error UI |

Recommended renderer signposts:

| Signpost | Type | Purpose |
|---|---|---|
| `renderer.prepareDocument` | interval | Full document preparation |
| `renderer.readFile` | interval | UTF-8 file read |
| `renderer.parseBlocks` | interval | Block-level parsing |
| `renderer.renderDocument` | interval | Full attributed string construction |
| `renderer.inlineMarkdown` | interval or sampled event | Inline Markdown parsing hot spots |
| `renderer.syntaxHighlight` | interval or sampled event | Regex-based code highlighting hot spots |
| `renderer.imageLoad` | interval | Local image load cost and failures |
| `renderer.tableRender` | interval or event | Table rendering count and cost |

Recommended thumbnail signposts:

| Signpost | Type | Purpose |
|---|---|---|
| `thumbnail.request` | interval | End-to-end thumbnail request wall time |
| `thumbnail.prepare` | interval | Markdown file preparation |
| `thumbnail.render` | interval | Attributed string construction |
| `thumbnail.draw` | interval | Text layout and drawing into the graphics context |
| `thumbnail.failure` | event | Failed thumbnail generation |

## Metrics

Primary metric:

- Preview request wall time from `preparePreviewOfFile(at:)` entry to rendered root view applied.

Secondary metrics:

- File size
- Source character count
- Rendered attributed string character count
- Parsed block count
- Counts by block type where cheap to collect
- Inline Markdown parse count
- Code block count
- Syntax highlighting time
- Table count and table cell count
- Image load count and image fallback count
- Settings load time
- Thumbnail request wall time
- Cancellation and stale-request counts

The first implementation should favor a small useful metric set over a large taxonomy that adds maintenance cost. Additional metadata can be added after initial profiling shows where it is useful.

## Fixtures

Add repeatable local performance fixtures under `Fixtures/Performance/`.

Recommended fixtures:

| Fixture | Purpose |
|---|---|
| `small.md` | README-sized baseline |
| `large.md` | Long prose, headings, and lists |
| `code-heavy.md` | Many fenced code blocks across supported languages |
| `table-heavy.md` | Wide and tall tables |
| `image-heavy.md` | Local image references plus missing-image fallbacks |
| `mixed-realistic.md` | Representative real-world Markdown document |

Fixture content should be deterministic and safe to commit. It should avoid private or client material.

## Local Profiling Script

Add a local developer script such as `Scripts/profile-performance.sh`.

The script should:

1. Generate the Xcode project.
2. Build the Debug app.
3. Run the existing preview runtime check.
4. Open or register the Debug app as needed.
5. Refresh Quick Look registration and caches.
6. Print the performance fixture paths.
7. Print concise instructions for using Instruments with the signpost categories.

The script should not attempt to automate every Finder interaction. Quick Look extension behavior depends on Finder, cache state, and system registration. The script should make the environment repeatable and make manual profiling steps clear.

## Tests

Add focused tests where they improve confidence without making performance brittle.

Recommended coverage:

- Instrumentation can be called in tests without changing preview or renderer outputs.
- Preview request tests still pass with instrumentation enabled.
- Renderer output tests still pass with instrumentation enabled.
- Any benchmark-style tests use broad smoke assertions only.

Avoid strict CI thresholds for timing. Local before-and-after profiling should be the source of truth for ranking performance work.

## Guardrails

Instrumentation must not change user-visible behavior.

Guardrails:

- No file contents in logs.
- No network calls.
- No persistent analytics storage.
- No user-facing controls.
- No required Instruments attachment.
- No new blocking work on the main actor beyond lightweight signpost boundaries.
- No broad refactor of renderer behavior in the instrumentation pass.
- Release builds should either compile out the instrumentation calls or route them through inert no-op helpers.

## Success Criteria

- Developers can profile a preview request and see end-to-end timing plus parse, settings, render, and view-apply breakdowns.
- Developers can profile thumbnails and see prepare, render, and draw breakdowns.
- The project includes committed fixtures that exercise common performance shapes.
- The local profiling script prepares the Debug app and explains the manual profiling loop.
- Existing rendering and preview behavior remain unchanged.
- The resulting measurements are sufficient to rank the next optimization pass by user-visible preview latency.
