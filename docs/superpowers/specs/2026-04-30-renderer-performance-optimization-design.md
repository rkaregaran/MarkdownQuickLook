# Renderer Performance Optimization Design

## Context

The performance instrumentation branch added DEBUG-only signposts and a local profiling workflow. Initial sample analysis showed that `qlmanage -p` and `qlmanage -t` currently route `.md` files through Apple's text Quick Look path in this environment, so renderer benchmarking was done directly against `MarkdownDocumentRenderer`.

Committed performance fixtures are useful smoke samples, but too small to prioritize optimization. Scaled temporary fixtures showed render time dominates prepare time:

| Fixture | Size | Prepare Median | Render Median | Total Median | Total p95 |
|---|---:|---:|---:|---:|---:|
| `large-100x.md` | 159 KB | 10.2 ms | 85.5 ms | 95.7 ms | 101.1 ms |
| `mixed-realistic-100x.md` | 141 KB | 8.9 ms | 83.5 ms | 92.5 ms | 104.9 ms |
| `code-heavy-100x.md` | 102 KB | 4.6 ms | 58.8 ms | 63.1 ms | 69.9 ms |
| `table-heavy-100x.md` | 103 KB | 8.9 ms | 32.7 ms | 41.6 ms | 47.0 ms |
| `image-heavy-100x.md` | 50 KB | 4.0 ms | 26.2 ms | 30.3 ms | 42.8 ms |

Nested signpost analysis of the scaled renderer run showed the cumulative cost order:

| Span | Count | Total |
|---|---:|---:|
| `renderer.renderDocument` | 140 | 7,918 ms |
| `renderer.inlineMarkdown` | 142,800 | 4,129 ms |
| `renderer.syntaxHighlight` | 16,800 | 1,581 ms |
| `renderer.prepareDocument` | 140 | 1,042 ms |
| `renderer.parseBlocks` | 140 | 938 ms |
| `renderer.tableRender` | 8,400 | 769 ms |
| `renderer.imageLoad` | 8,400 | 527 ms |
| `renderer.readFile` | 140 | 87 ms |

## Goal

Reduce renderer latency for larger Markdown documents by optimizing the measured hot paths while preserving rendering behavior and keeping the implementation small enough to audit.

## Non-Goals

- Do not rewrite the Markdown parser.
- Do not introduce a third-party rendering or syntax-highlighting library.
- Do not add app-facing caches in the first optimization pass.
- Do not mix renderer optimization with LaunchServices, Finder, or PlugInKit routing fixes.
- Do not optimize file I/O unless later measurements show it becomes material.

## Recommended Approach

Use conservative fast paths and cached helper state inside `MarkdownRendering`.

The first pass should optimize `inlineMarkdownAttributedString(from:baseURL:baseAttributes:)` by avoiding expensive inline Markdown parsing and post-processing when the input cannot use those features. Plain text should become a direct `NSMutableAttributedString` creation with base attributes. Text with inline markers should continue through the existing `AttributedString(markdown:)` path. Post-processing should only run when its marker is present: strikethrough for `~~`, dash replacement for `--`, and inline code styling for backticks.

The second pass should optimize syntax highlighting by extracting a focused `MarkdownSyntaxHighlighter` helper. It should precompile reusable regexes and language keyword patterns instead of rebuilding them for every code block. It should preserve the current color and precedence behavior: comments and strings first, then keywords, numbers, and capitalized identifiers.

## Components

### Renderer Inline Fast Path

File: `MarkdownRendering/Sources/MarkdownDocumentRenderer.swift`

Responsibilities:
- Detect whether inline Markdown parsing is needed.
- Preserve current rendering for links, emphasis, bold, inline code, strikethrough, dash replacement, and headings.
- Avoid `AttributedString(markdown:)` for plain text.
- Avoid `source.runs` scans when the related feature cannot appear.

Candidate helper decisions:
- `requiresInlineMarkdownParsing(_:)` returns true for characters that can affect inline parsing: `[`, `]`, `(`, `)`, `*`, `_`, "`", `~`, `<`, `>`, `!`, `\\`.
- `containsDashReplacementCandidate(_:)` returns true for `--`.
- `containsInlineCodeCandidate(_:)` returns true for backticks.
- `containsStrikethroughCandidate(_:)` returns true for `~~`.

### Syntax Highlighter Helper

File: `MarkdownRendering/Sources/MarkdownSyntaxHighlighter.swift`

Responsibilities:
- Apply the same syntax highlighting attributes currently applied by `MarkdownDocumentRenderer`.
- Cache compiled `NSRegularExpression` instances for comments, strings, numbers, keywords, and types.
- Cache keyword regexes by normalized language.
- Keep overlap prevention behavior through a colored range set.

The helper should not know about document parsing, block rendering, preview controllers, or Quick Look lifecycle.

### Benchmark Harness

File: `Scripts/benchmark-renderer.sh`

Responsibilities:
- Build the Debug `MarkdownRendering` product.
- Compile a temporary Swift benchmark executable against the built framework.
- Run committed fixtures and generated scaled fixtures.
- Print tab-separated timing rows for fixture name, bytes, lines, output characters, prepare median/p95, render median/p95, and total median/p95.

The benchmark should generate scaled files under `/tmp` and should not commit generated fixtures or benchmark binaries.

## Testing Strategy

### Behavior Tests

Add focused renderer tests before implementation:
- Plain text still renders with body font, color, and paragraph style.
- Plain text containing no inline markers does not lose paragraph behavior.
- Bold, italic, links, inline code, strikethrough, and dash replacement still match current behavior.
- Heading inline code still scales to heading size.
- Syntax highlighting still colors comments, strings, keywords, numbers, and capitalized identifiers without overwriting earlier matches.

### Performance Verification

Use the benchmark script before and after each optimization step:
- Baseline the branch before code changes.
- Measure after inline fast path.
- Measure after syntax highlighter extraction.

Success criteria:
- At least 30% lower total median on `large-100x.md` and `mixed-realistic-100x.md`.
- Clear reduction in cumulative `renderer.inlineMarkdown` and `renderer.syntaxHighlight` signpost totals.
- No regressions in `MarkdownRenderingTests`.
- Preview extension tests still pass because preview uses the same renderer.

## Risks

- The inline fast path can accidentally skip Markdown parsing for syntax that should be interpreted. Mitigation: keep the marker detector conservative.
- Precompiled regexes can change behavior if language normalization is wrong. Mitigation: test representative languages and keep unknown-language generic behavior.
- Microbenchmarks can overfit repeated generated fixtures. Mitigation: use them only for direction, and keep committed real fixtures in the benchmark report.
- The current Quick Look CLI route is not exercising the app extension in this environment. Mitigation: keep renderer optimization separate from a future Quick Look routing investigation.

## Implementation Order

1. Add renderer benchmark script and capture baseline.
2. Add behavior tests around inline fast-path correctness.
3. Implement inline markdown fast path and conditional post-processing.
4. Measure and commit.
5. Add syntax highlighting behavior tests.
6. Extract cached syntax highlighter helper.
7. Measure and commit.
8. Run full rendering, preview, and app verification.
