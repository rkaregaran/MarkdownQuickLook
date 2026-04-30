# Renderer Performance Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce renderer latency for larger Markdown documents by optimizing measured inline Markdown and syntax highlighting hotspots without changing rendered output.

**Architecture:** Keep the existing parser and rendering model. Add a local renderer benchmark script, then introduce conservative fast paths in `MarkdownDocumentRenderer` and move syntax highlighting into a focused helper with precompiled regex state.

**Tech Stack:** Swift 5, AppKit, XCTest, XcodeGen, `xcodebuild`, `xcrun swiftc`, zsh.

---

## File Structure

- `Scripts/benchmark-renderer.sh`: local developer benchmark for committed fixtures and generated scaled stress fixtures.
- `MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift`: characterization tests for inline rendering and syntax highlighting behavior.
- `MarkdownRendering/Sources/MarkdownDocumentRenderer.swift`: inline markdown fast path and delegation to syntax highlighter helper.
- `MarkdownRendering/Sources/MarkdownSyntaxHighlighter.swift`: internal helper that applies current code-block highlighting with precompiled regexes.

## Required Baseline Commands

Run these before starting task implementation:

```bash
xcodebuild -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS' -derivedDataPath .derivedData/renderer-optimization-baseline CODE_SIGNING_ALLOWED=NO test
```

Expected: `** TEST SUCCEEDED **`.

```bash
./Scripts/profile-performance.sh
```

Expected: script prints `Performance profiling build is ready.` and lists the derived-data preview and thumbnail extension paths.

---

### Task 1: Add Repeatable Renderer Benchmark Script

**Files:**
- Create: `Scripts/benchmark-renderer.sh`

- [ ] **Step 1: Add the benchmark script**

Create `Scripts/benchmark-renderer.sh` with this exact content:

```zsh
#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="$ROOT/.derivedData/renderer-benchmark"
PRODUCTS_DIR="$DERIVED_DATA_PATH/Build/Products/Debug"
BENCH_SOURCE="/tmp/MarkdownQuickLookFixtureBench.swift"
BENCH_BINARY="/tmp/MarkdownQuickLookFixtureBench"
SCALED_DIR="/tmp/markdownquicklook-scaled-fixtures"
SCALE_COUNT="${MARKDOWN_QUICKLOOK_BENCH_SCALE:-100}"
ITERATIONS="${MARKDOWN_QUICKLOOK_BENCH_ITERATIONS:-25}"
WARMUPS="${MARKDOWN_QUICKLOOK_BENCH_WARMUPS:-3}"

cd "$ROOT"

xcodebuild \
  -project MarkdownQuickLook.xcodeproj \
  -scheme MarkdownRenderingTests \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  build >/tmp/markdownquicklook-renderer-benchmark-build.log

cat > "$BENCH_SOURCE" <<'SWIFT'
import AppKit
import Foundation
import MarkdownRendering

struct FixtureStats {
    let fixture: String
    let bytes: Int
    let lines: Int
    let outputCharacters: Int
    let prepare: [Double]
    let render: [Double]
    let total: [Double]
}

func milliseconds(from start: UInt64, to end: UInt64) -> Double {
    Double(end - start) / 1_000_000.0
}

func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    let middle = sorted.count / 2
    if sorted.count % 2 == 0 {
        return (sorted[middle - 1] + sorted[middle]) / 2
    }
    return sorted[middle]
}

func percentile(_ values: [Double], _ p: Double) -> Double {
    let sorted = values.sorted()
    let index = Int((Double(sorted.count - 1) * p).rounded())
    return sorted[max(0, min(sorted.count - 1, index))]
}

func format(_ value: Double) -> String {
    String(format: "%.3f", value)
}

@main
enum Benchmark {
    @MainActor
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count >= 3 else {
            FileHandle.standardError.write(Data("Usage: MarkdownQuickLookFixtureBench <warmups> <iterations> <fixture>...\n".utf8))
            Foundation.exit(2)
        }

        let warmups = Int(arguments[0]) ?? 3
        let iterations = Int(arguments[1]) ?? 25
        let paths = Array(arguments.dropFirst(2))
        var stats: [FixtureStats] = []

        for path in paths {
            let url = URL(fileURLWithPath: path)
            let data = try Data(contentsOf: url)
            let text = String(data: data, encoding: .utf8) ?? ""
            let renderer = MarkdownDocumentRenderer()

            for _ in 0..<warmups {
                let document = try renderer.prepareDocument(fileAt: url)
                _ = renderer.render(document: document)
            }

            var prepareTimes: [Double] = []
            var renderTimes: [Double] = []
            var totalTimes: [Double] = []
            var outputCharacters = 0

            for _ in 0..<iterations {
                let prepareStart = DispatchTime.now().uptimeNanoseconds
                let document = try renderer.prepareDocument(fileAt: url)
                let prepareEnd = DispatchTime.now().uptimeNanoseconds
                let payload = renderer.render(document: document)
                let renderEnd = DispatchTime.now().uptimeNanoseconds

                prepareTimes.append(milliseconds(from: prepareStart, to: prepareEnd))
                renderTimes.append(milliseconds(from: prepareEnd, to: renderEnd))
                totalTimes.append(milliseconds(from: prepareStart, to: renderEnd))
                outputCharacters = payload.attributedContent.length
            }

            stats.append(
                FixtureStats(
                    fixture: url.lastPathComponent,
                    bytes: data.count,
                    lines: text.components(separatedBy: .newlines).count,
                    outputCharacters: outputCharacters,
                    prepare: prepareTimes,
                    render: renderTimes,
                    total: totalTimes
                )
            )
        }

        print("fixture\tbytes\tlines\toutputChars\tprepareMedianMs\tprepareP95Ms\trenderMedianMs\trenderP95Ms\ttotalMedianMs\ttotalP95Ms")
        for item in stats {
            print([
                item.fixture,
                String(item.bytes),
                String(item.lines),
                String(item.outputCharacters),
                format(median(item.prepare)),
                format(percentile(item.prepare, 0.95)),
                format(median(item.render)),
                format(percentile(item.render, 0.95)),
                format(median(item.total)),
                format(percentile(item.total, 0.95))
            ].joined(separator: "\t"))
        }
    }
}
SWIFT

xcrun swiftc \
  -parse-as-library \
  "$BENCH_SOURCE" \
  -F "$PRODUCTS_DIR" \
  -I "$PRODUCTS_DIR" \
  -framework MarkdownRendering \
  -o "$BENCH_BINARY"

rm -rf "$SCALED_DIR"
mkdir -p "$SCALED_DIR"

for name in large table-heavy image-heavy code-heavy mixed-realistic; do
  source_fixture="$ROOT/Fixtures/Performance/$name.md"
  scaled_fixture="$SCALED_DIR/${name}-${SCALE_COUNT}x.md"
  : > "$scaled_fixture"

  for i in $(seq 1 "$SCALE_COUNT"); do
    printf "\n\n<!-- repetition %03d -->\n\n" "$i" >> "$scaled_fixture"
    cat "$source_fixture" >> "$scaled_fixture"
  done
done

fixtures=(
  "$ROOT/Fixtures/Performance/small.md"
  "$ROOT/Fixtures/Performance/large.md"
  "$ROOT/Fixtures/Performance/table-heavy.md"
  "$ROOT/Fixtures/Performance/image-heavy.md"
  "$ROOT/Fixtures/Performance/code-heavy.md"
  "$ROOT/Fixtures/Performance/mixed-realistic.md"
  "$SCALED_DIR/large-${SCALE_COUNT}x.md"
  "$SCALED_DIR/table-heavy-${SCALE_COUNT}x.md"
  "$SCALED_DIR/image-heavy-${SCALE_COUNT}x.md"
  "$SCALED_DIR/code-heavy-${SCALE_COUNT}x.md"
  "$SCALED_DIR/mixed-realistic-${SCALE_COUNT}x.md"
)

DYLD_FRAMEWORK_PATH="$PRODUCTS_DIR" "$BENCH_BINARY" "$WARMUPS" "$ITERATIONS" "${fixtures[@]}"
```

- [ ] **Step 2: Make the script executable**

Run:

```bash
chmod +x Scripts/benchmark-renderer.sh
```

Expected: no output.

- [ ] **Step 3: Syntax-check the script**

Run:

```bash
zsh -n Scripts/benchmark-renderer.sh
```

Expected: no output and exit code `0`.

- [ ] **Step 4: Run the benchmark baseline**

Run:

```bash
MARKDOWN_QUICKLOOK_BENCH_ITERATIONS=10 ./Scripts/benchmark-renderer.sh
```

Expected: tab-separated output with rows for all six committed fixtures and five generated `100x` fixtures. Save the output in the terminal transcript for comparison; do not commit `/tmp` files.

- [ ] **Step 5: Commit the benchmark script**

Run:

```bash
git add Scripts/benchmark-renderer.sh
git commit -m "chore: add renderer benchmark script"
```

---

### Task 2: Add Inline Rendering Characterization Tests

**Files:**
- Modify: `MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift`

- [ ] **Step 1: Add inline fast-path guard tests**

Add these tests near the existing inline-code and strikethrough tests:

```swift
func testRenderPlainTextWithoutInlineMarkersKeepsBodyAttributes() throws {
    let payload = try renderDocument("Plain paragraph without inline markers.").payload
    let rendered = renderedTextStorage(from: payload.attributedContent)
    let fullRange = NSRange(location: 0, length: rendered.length)
    let font = rendered.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    let color = rendered.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
    let paragraphStyle = rendered.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle

    XCTAssertEqual(rendered.string, "Plain paragraph without inline markers.")
    XCTAssertEqual(fullRange.length, rendered.string.count)
    XCTAssertEqual(font?.pointSize, 15)
    XCTAssertEqual(color, NSColor.labelColor)
    XCTAssertEqual(paragraphStyle?.paragraphSpacing, 8)
}

func testRenderPlainTextDashReplacementStillWorksWithoutInlineParsing() throws {
    let payload = try renderDocument("Before -- middle --- after").payload

    XCTAssertEqual(payload.attributedContent.string, "Before – middle — after")
}

func testRenderDashReplacementDoesNotChangeInlineCode() throws {
    let payload = try renderDocument("Use `--flag` before --- launch").payload

    XCTAssertEqual(payload.attributedContent.string, "Use --flag before — launch")
}

func testRenderInlineMarkdownFeatureMixAfterFastPath() throws {
    let payload = try renderDocument("Read [docs](https://example.com), **bold**, *italic*, `code`, and ~~old~~ text.").payload
    let rendered = renderedTextStorage(from: payload.attributedContent)
    let nsString = rendered.string as NSString

    let docsRange = nsString.range(of: "docs")
    let boldRange = nsString.range(of: "bold")
    let italicRange = nsString.range(of: "italic")
    let codeRange = nsString.range(of: "code")
    let oldRange = nsString.range(of: "old")

    let link = rendered.attribute(.link, at: docsRange.location, effectiveRange: nil) as? URL
    let boldFont = rendered.attribute(.font, at: boldRange.location, effectiveRange: nil) as? NSFont
    let italicFont = rendered.attribute(.font, at: italicRange.location, effectiveRange: nil) as? NSFont
    let codeFont = rendered.attribute(.font, at: codeRange.location, effectiveRange: nil) as? NSFont
    let strike = rendered.attribute(.strikethroughStyle, at: oldRange.location, effectiveRange: nil) as? Int

    XCTAssertEqual(link, URL(string: "https://example.com"))
    XCTAssertTrue(boldFont?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    XCTAssertTrue(italicFont?.fontDescriptor.symbolicTraits.contains(.italic) == true)
    XCTAssertTrue(codeFont?.isFixedPitch == true)
    XCTAssertEqual(strike, NSUnderlineStyle.single.rawValue)
}
```

- [ ] **Step 2: Run tests to establish guards**

Run:

```bash
xcodebuild -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS' -derivedDataPath .derivedData/inline-guards CODE_SIGNING_ALLOWED=NO test
```

Expected: `** TEST SUCCEEDED **`. These are characterization guards and should pass before the optimization.

- [ ] **Step 3: Commit the tests**

Run:

```bash
git add MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift
git commit -m "test: guard inline renderer behavior"
```

---

### Task 3: Implement Inline Markdown Fast Path

**Files:**
- Modify: `MarkdownRendering/Sources/MarkdownDocumentRenderer.swift`

- [ ] **Step 1: Replace inline rendering with conservative fast path**

Replace `inlineMarkdownAttributedString(from:baseURL:baseAttributes:)` with:

```swift
private func inlineMarkdownAttributedString(
    from text: String,
    baseURL: URL,
    baseAttributes: [NSAttributedString.Key: Any]
) -> NSMutableAttributedString {
    let interval = MarkdownPerformanceInstrumentation.begin("renderer.inlineMarkdown")
    defer { MarkdownPerformanceInstrumentation.end(interval) }

    let shouldParseInlineMarkdown = requiresInlineMarkdownParsing(text)
    let shouldReplaceDashes = containsDashReplacementCandidate(text)
    let shouldApplyStrikethrough = containsStrikethroughCandidate(text)
    let shouldApplyInlineCode = containsInlineCodeCandidate(text)

    if shouldParseInlineMarkdown {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let parsed = (try? AttributedString(markdown: text, options: options, baseURL: baseURL)) ?? AttributedString(text)
        let attributed = NSMutableAttributedString(attributedString: NSAttributedString(parsed))
        attributed.addAttributes(baseAttributes, range: NSRange(location: 0, length: attributed.length))

        if shouldApplyStrikethrough {
            applyStrikethrough(to: attributed, from: parsed)
        }

        if shouldReplaceDashes {
            applyDashes(to: attributed, from: parsed)
        }

        if shouldApplyInlineCode {
            applyInlineCodeBackground(to: attributed, from: parsed)
        }

        return attributed
    }

    let attributed = NSMutableAttributedString(string: text, attributes: baseAttributes)

    if shouldReplaceDashes {
        applyDashes(to: attributed, skippingCodeRanges: IndexSet())
    }

    return attributed
}
```

- [ ] **Step 2: Add helper methods below `inlineMarkdownAttributedString`**

Add:

```swift
private func requiresInlineMarkdownParsing(_ text: String) -> Bool {
    text.rangeOfCharacter(from: Self.inlineMarkdownMarkerCharacters) != nil
}

private func containsDashReplacementCandidate(_ text: String) -> Bool {
    text.contains("--")
}

private func containsInlineCodeCandidate(_ text: String) -> Bool {
    text.contains("`")
}

private func containsStrikethroughCandidate(_ text: String) -> Bool {
    text.contains("~~")
}
```

- [ ] **Step 3: Add the static marker set inside `MarkdownDocumentRenderer`**

Add this near the top of the class, below `private let settings`:

```swift
private static let inlineMarkdownMarkerCharacters = CharacterSet(charactersIn: "[]()*_`~<>!\\")
```

- [ ] **Step 4: Split dash replacement so plain text can use it without `AttributedString` runs**

Replace the body of `applyDashes(to:from:)` with:

```swift
private func applyDashes(to attributed: NSMutableAttributedString, from source: AttributedString) {
    var codeRanges = IndexSet()
    for run in source.runs {
        if let intent = run.inlinePresentationIntent, intent.contains(.code) {
            let nsRange = NSRange(run.range, in: source)
            codeRanges.insert(integersIn: nsRange.location..<(nsRange.location + nsRange.length))
        }
    }

    applyDashes(to: attributed, skippingCodeRanges: codeRanges)
}

private func applyDashes(to attributed: NSMutableAttributedString, skippingCodeRanges initialCodeRanges: IndexSet) {
    var codeRanges = initialCodeRanges
    let replacements: [(pattern: String, replacement: String)] = [
        ("---", "\u{2014}"),
        ("--", "\u{2013}")
    ]

    for (pattern, replacement) in replacements {
        var searchRange = NSRange(location: 0, length: attributed.length)
        while searchRange.location < attributed.length {
            let range = (attributed.string as NSString).range(of: pattern, range: searchRange)
            guard range.location != NSNotFound else { break }

            if !codeRanges.contains(integersIn: range.location..<(range.location + range.length)) {
                attributed.replaceCharacters(in: range, with: replacement)
                let delta = replacement.count - range.length
                var adjusted = IndexSet()
                for r in codeRanges.rangeView {
                    if r.lowerBound > range.location {
                        adjusted.insert(integersIn: (r.lowerBound + delta)..<(r.upperBound + delta))
                    } else {
                        adjusted.insert(integersIn: r)
                    }
                }
                codeRanges = adjusted
                searchRange = NSRange(location: range.location + replacement.count, length: attributed.length - range.location - replacement.count)
            } else {
                searchRange = NSRange(location: range.location + range.length, length: attributed.length - range.location - range.length)
            }
        }
    }
}
```

- [ ] **Step 5: Run inline behavior tests**

Run:

```bash
xcodebuild -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS' -derivedDataPath .derivedData/inline-fast-path CODE_SIGNING_ALLOWED=NO test
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Measure inline optimization**

Run:

```bash
MARKDOWN_QUICKLOOK_BENCH_ITERATIONS=25 ./Scripts/benchmark-renderer.sh
```

Expected: tab-separated output. Compare `large-100x.md` and `mixed-realistic-100x.md` `totalMedianMs` against Task 1 baseline.

- [ ] **Step 7: Commit inline optimization**

Run:

```bash
git add MarkdownRendering/Sources/MarkdownDocumentRenderer.swift
git commit -m "perf: add inline markdown fast path"
```

---

### Task 4: Add Syntax Highlighting Characterization Tests

**Files:**
- Modify: `MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift`

- [ ] **Step 1: Add syntax highlighting tests**

Add these tests near the existing code block tests:

```swift
func testRenderSyntaxHighlightingColorsSwiftTokens() throws {
    let payload = try renderDocument(
        """
        ```swift
        struct Widget {
            let count = 42
            let label = "Ready"
        }
        ```
        """
    ).payload
    let rendered = renderedTextStorage(from: payload.attributedContent)
    let nsString = rendered.string as NSString

    let structRange = nsString.range(of: "struct")
    let widgetRange = nsString.range(of: "Widget")
    let numberRange = nsString.range(of: "42")
    let stringRange = nsString.range(of: "\"Ready\"")

    let structColor = rendered.attribute(.foregroundColor, at: structRange.location, effectiveRange: nil) as? NSColor
    let widgetColor = rendered.attribute(.foregroundColor, at: widgetRange.location, effectiveRange: nil) as? NSColor
    let numberColor = rendered.attribute(.foregroundColor, at: numberRange.location, effectiveRange: nil) as? NSColor
    let stringColor = rendered.attribute(.foregroundColor, at: stringRange.location, effectiveRange: nil) as? NSColor
    let keywordFont = rendered.attribute(.font, at: structRange.location, effectiveRange: nil) as? NSFont

    XCTAssertEqual(structColor, NSColor.systemPink)
    XCTAssertEqual(widgetColor, NSColor.systemPurple)
    XCTAssertEqual(numberColor, NSColor.systemBlue)
    XCTAssertEqual(stringColor, NSColor.systemGreen)
    XCTAssertTrue(keywordFont?.fontDescriptor.symbolicTraits.contains(.bold) == true)
}

func testRenderSyntaxHighlightingDoesNotOverwriteCommentColor() throws {
    let payload = try renderDocument(
        """
        ```swift
        // let Widget = 42
        let value = 1
        ```
        """
    ).payload
    let rendered = renderedTextStorage(from: payload.attributedContent)
    let nsString = rendered.string as NSString

    let commentKeywordRange = nsString.range(of: "let Widget")
    let realKeywordRange = nsString.range(of: "let value")

    let commentColor = rendered.attribute(.foregroundColor, at: commentKeywordRange.location, effectiveRange: nil) as? NSColor
    let realKeywordColor = rendered.attribute(.foregroundColor, at: realKeywordRange.location, effectiveRange: nil) as? NSColor

    XCTAssertEqual(commentColor, NSColor.secondaryLabelColor)
    XCTAssertEqual(realKeywordColor, NSColor.systemPink)
}
```

- [ ] **Step 2: Run tests before extraction**

Run:

```bash
xcodebuild -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS' -derivedDataPath .derivedData/syntax-guards CODE_SIGNING_ALLOWED=NO test
```

Expected: `** TEST SUCCEEDED **`. These tests characterize current behavior before extraction.

- [ ] **Step 3: Commit syntax tests**

Run:

```bash
git add MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift
git commit -m "test: guard syntax highlighting behavior"
```

---

### Task 5: Extract Cached Syntax Highlighter

**Files:**
- Create: `MarkdownRendering/Sources/MarkdownSyntaxHighlighter.swift`
- Modify: `MarkdownRendering/Sources/MarkdownDocumentRenderer.swift`

- [ ] **Step 1: Create syntax highlighter helper**

Create `MarkdownRendering/Sources/MarkdownSyntaxHighlighter.swift` with this exact content:

```swift
import AppKit
import Foundation

enum MarkdownSyntaxHighlighter {
    private static let stringRegex = try! NSRegularExpression(pattern: "\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'")
    private static let numberRegex = try! NSRegularExpression(pattern: "\\b\\d+\\.?\\d*\\b")
    private static let typeRegex = try! NSRegularExpression(pattern: "\\b[A-Z][a-zA-Z0-9]+\\b")
    private static let hashCommentRegex = try! NSRegularExpression(pattern: "#[^\\n]*")
    private static let htmlCommentRegex = try! NSRegularExpression(pattern: "<!--[\\s\\S]*?-->")
    private static let slashCommentRegex = try! NSRegularExpression(pattern: "//[^\\n]*")
    private static let blockCommentRegex = try! NSRegularExpression(pattern: "/\\*[\\s\\S]*?\\*/")

    static func apply(to attributed: NSMutableAttributedString, language: String?, font: NSFont) {
        let code = attributed.string
        let fullRange = NSRange(location: 0, length: attributed.length)
        let boldFont = NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .semibold)

        let commentColor = NSColor.secondaryLabelColor
        let stringColor = NSColor.systemGreen
        let keywordColor = NSColor.systemPink
        let numberColor = NSColor.systemBlue
        let typeColor = NSColor.systemPurple
        var colored = IndexSet()

        func applyRegex(_ regex: NSRegularExpression, color: NSColor, bold: Bool = false) {
            for match in regex.matches(in: code, range: fullRange) {
                let range = match.range
                guard !colored.contains(integersIn: range.location..<(range.location + range.length)) else { continue }
                attributed.addAttribute(.foregroundColor, value: color, range: range)
                if bold {
                    attributed.addAttribute(.font, value: boldFont, range: range)
                }
                colored.insert(integersIn: range.location..<(range.location + range.length))
            }
        }

        for regex in commentRegexes(for: language) {
            applyRegex(regex, color: commentColor)
        }

        applyRegex(stringRegex, color: stringColor)

        if let keywordRegex = keywordRegex(for: language) {
            applyRegex(keywordRegex, color: keywordColor, bold: true)
        }

        applyRegex(numberRegex, color: numberColor)
        applyRegex(typeRegex, color: typeColor)
    }

    private static func commentRegexes(for language: String?) -> [NSRegularExpression] {
        switch normalizedLanguage(language) {
        case "python", "ruby", "bash", "sh", "zsh", "yaml", "yml":
            return [hashCommentRegex]
        case "html", "xml":
            return [htmlCommentRegex]
        default:
            return [slashCommentRegex, blockCommentRegex]
        }
    }

    private static func keywordRegex(for language: String?) -> NSRegularExpression? {
        keywordRegexes[normalizedLanguage(language)]
    }

    private static func normalizedLanguage(_ language: String?) -> String {
        language?.lowercased() ?? "default"
    }

    private static func buildKeywordRegexes() -> [String: NSRegularExpression] {
        var result: [String: NSRegularExpression] = [:]
        for (language, keywords) in keywordLists {
            let escaped = keywords.map { NSRegularExpression.escapedPattern(for: $0) }
            let pattern = "\\b(" + escaped.joined(separator: "|") + ")\\b"
            result[language] = try! NSRegularExpression(pattern: pattern)
        }
        return result
    }

    private static let keywordLists: [String: [String]] = [
        "swift": ["import", "let", "var", "func", "class", "struct", "enum", "protocol",
                  "if", "else", "guard", "switch", "case", "default", "for", "while", "repeat",
                  "return", "throw", "throws", "try", "catch", "in", "where", "as", "is",
                  "true", "false", "nil", "self", "Self", "super", "init", "deinit",
                  "public", "private", "internal", "fileprivate", "open", "static", "override",
                  "async", "await", "some", "any", "typealias", "associatedtype", "extension",
                  "final", "lazy", "weak", "unowned", "mutating", "nonmutating",
                  "convenience", "required", "optional", "dynamic", "indirect",
                  "break", "continue", "fallthrough", "do", "defer", "inout"],
        "python": ["import", "from", "def", "class", "if", "elif", "else", "for", "while",
                   "return", "yield", "try", "except", "finally", "raise", "with", "as",
                   "True", "False", "None", "and", "or", "not", "in", "is", "lambda",
                   "pass", "break", "continue", "global", "nonlocal", "assert", "del",
                   "async", "await", "self"],
        "ruby": ["import", "from", "def", "class", "if", "elif", "else", "for", "while",
                 "return", "yield", "try", "except", "finally", "raise", "with", "as",
                 "True", "False", "None", "and", "or", "not", "in", "is", "lambda",
                 "pass", "break", "continue", "global", "nonlocal", "assert", "del",
                 "async", "await", "self"],
        "javascript": ["import", "export", "from", "let", "const", "var", "function", "class",
                       "if", "else", "switch", "case", "default", "for", "while", "do",
                       "return", "throw", "try", "catch", "finally", "new", "delete", "typeof",
                       "true", "false", "null", "undefined", "this", "super",
                       "async", "await", "yield", "of", "in", "instanceof",
                       "break", "continue", "void", "interface", "type", "enum", "extends", "implements"],
        "js": ["import", "export", "from", "let", "const", "var", "function", "class",
               "if", "else", "switch", "case", "default", "for", "while", "do",
               "return", "throw", "try", "catch", "finally", "new", "delete", "typeof",
               "true", "false", "null", "undefined", "this", "super",
               "async", "await", "yield", "of", "in", "instanceof",
               "break", "continue", "void", "interface", "type", "enum", "extends", "implements"],
        "typescript": ["import", "export", "from", "let", "const", "var", "function", "class",
                       "if", "else", "switch", "case", "default", "for", "while", "do",
                       "return", "throw", "try", "catch", "finally", "new", "delete", "typeof",
                       "true", "false", "null", "undefined", "this", "super",
                       "async", "await", "yield", "of", "in", "instanceof",
                       "break", "continue", "void", "interface", "type", "enum", "extends", "implements"],
        "ts": ["import", "export", "from", "let", "const", "var", "function", "class",
               "if", "else", "switch", "case", "default", "for", "while", "do",
               "return", "throw", "try", "catch", "finally", "new", "delete", "typeof",
               "true", "false", "null", "undefined", "this", "super",
               "async", "await", "yield", "of", "in", "instanceof",
               "break", "continue", "void", "interface", "type", "enum", "extends", "implements"],
        "go": ["package", "import", "func", "type", "struct", "interface", "map",
               "if", "else", "switch", "case", "default", "for", "range", "select",
               "return", "go", "defer", "chan", "var", "const",
               "true", "false", "nil", "break", "continue", "fallthrough"],
        "rust": ["use", "mod", "fn", "let", "mut", "const", "static", "struct", "enum", "trait", "impl",
                 "if", "else", "match", "for", "while", "loop", "in",
                 "return", "pub", "self", "Self", "super", "crate",
                 "true", "false", "as", "ref", "move", "async", "await", "where",
                 "break", "continue", "unsafe", "dyn", "type"],
        "java": ["import", "package", "class", "interface", "enum", "extends", "implements",
                 "if", "else", "switch", "case", "default", "for", "while", "do",
                 "return", "throw", "try", "catch", "finally", "new",
                 "true", "false", "null", "this", "super", "void",
                 "public", "private", "protected", "static", "final", "abstract",
                 "break", "continue", "instanceof", "synchronized", "volatile",
                 "var", "val", "fun", "when", "object", "companion", "data", "sealed"],
        "kotlin": ["import", "package", "class", "interface", "enum", "extends", "implements",
                   "if", "else", "switch", "case", "default", "for", "while", "do",
                   "return", "throw", "try", "catch", "finally", "new",
                   "true", "false", "null", "this", "super", "void",
                   "public", "private", "protected", "static", "final", "abstract",
                   "break", "continue", "instanceof", "synchronized", "volatile",
                   "var", "val", "fun", "when", "object", "companion", "data", "sealed"],
        "c": ["#include", "#import", "#define", "#ifdef", "#ifndef", "#endif", "#pragma",
              "int", "char", "float", "double", "void", "long", "short", "unsigned", "signed",
              "if", "else", "switch", "case", "default", "for", "while", "do",
              "return", "break", "continue", "goto", "sizeof", "typedef",
              "struct", "union", "enum", "class", "namespace", "template", "typename",
              "const", "static", "extern", "volatile", "register", "auto",
              "true", "false", "NULL", "nullptr", "this",
              "public", "private", "protected", "virtual", "override", "final",
              "new", "delete", "throw", "try", "catch", "using"],
        "cpp": ["#include", "#import", "#define", "#ifdef", "#ifndef", "#endif", "#pragma",
                "int", "char", "float", "double", "void", "long", "short", "unsigned", "signed",
                "if", "else", "switch", "case", "default", "for", "while", "do",
                "return", "break", "continue", "goto", "sizeof", "typedef",
                "struct", "union", "enum", "class", "namespace", "template", "typename",
                "const", "static", "extern", "volatile", "register", "auto",
                "true", "false", "NULL", "nullptr", "this",
                "public", "private", "protected", "virtual", "override", "final",
                "new", "delete", "throw", "try", "catch", "using"],
        "c++": ["#include", "#import", "#define", "#ifdef", "#ifndef", "#endif", "#pragma",
                "int", "char", "float", "double", "void", "long", "short", "unsigned", "signed",
                "if", "else", "switch", "case", "default", "for", "while", "do",
                "return", "break", "continue", "goto", "sizeof", "typedef",
                "struct", "union", "enum", "class", "namespace", "template", "typename",
                "const", "static", "extern", "volatile", "register", "auto",
                "true", "false", "NULL", "nullptr", "this",
                "public", "private", "protected", "virtual", "override", "final",
                "new", "delete", "throw", "try", "catch", "using"],
        "objc": ["#include", "#import", "#define", "#ifdef", "#ifndef", "#endif", "#pragma",
                 "int", "char", "float", "double", "void", "long", "short", "unsigned", "signed",
                 "if", "else", "switch", "case", "default", "for", "while", "do",
                 "return", "break", "continue", "goto", "sizeof", "typedef",
                 "struct", "union", "enum", "class", "namespace", "template", "typename",
                 "const", "static", "extern", "volatile", "register", "auto",
                 "true", "false", "NULL", "nullptr", "this",
                 "public", "private", "protected", "virtual", "override", "final",
                 "new", "delete", "throw", "try", "catch", "using"],
        "objective-c": ["#include", "#import", "#define", "#ifdef", "#ifndef", "#endif", "#pragma",
                        "int", "char", "float", "double", "void", "long", "short", "unsigned", "signed",
                        "if", "else", "switch", "case", "default", "for", "while", "do",
                        "return", "break", "continue", "goto", "sizeof", "typedef",
                        "struct", "union", "enum", "class", "namespace", "template", "typename",
                        "const", "static", "extern", "volatile", "register", "auto",
                        "true", "false", "NULL", "nullptr", "this",
                        "public", "private", "protected", "virtual", "override", "final",
                        "new", "delete", "throw", "try", "catch", "using"],
        "bash": ["if", "then", "else", "elif", "fi", "for", "while", "do", "done",
                 "case", "esac", "in", "function", "return", "local", "export",
                 "echo", "exit", "set", "unset", "readonly", "shift", "source",
                 "true", "false"],
        "sh": ["if", "then", "else", "elif", "fi", "for", "while", "do", "done",
               "case", "esac", "in", "function", "return", "local", "export",
               "echo", "exit", "set", "unset", "readonly", "shift", "source",
               "true", "false"],
        "zsh": ["if", "then", "else", "elif", "fi", "for", "while", "do", "done",
                "case", "esac", "in", "function", "return", "local", "export",
                "echo", "exit", "set", "unset", "readonly", "shift", "source",
                "true", "false"],
        "default": ["if", "else", "for", "while", "return", "function", "class", "import",
                    "true", "false", "null", "nil", "let", "var", "const", "def", "fn"]
    ]

    private static let keywordRegexes = buildKeywordRegexes()
}
```

- [ ] **Step 2: Replace renderer syntax body with helper call**

In `MarkdownDocumentRenderer.swift`, replace the body of `applySyntaxHighlighting(to:language:font:)` after the instrumentation debug line with:

```swift
MarkdownSyntaxHighlighter.apply(to: attributed, language: language, font: font)
```

Keep the `renderer.syntaxHighlight` signpost and debug message in `MarkdownDocumentRenderer`.

- [ ] **Step 3: Run syntax behavior tests**

Run:

```bash
xcodebuild -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS' -derivedDataPath .derivedData/syntax-helper CODE_SIGNING_ALLOWED=NO test
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 4: Measure syntax optimization**

Run:

```bash
MARKDOWN_QUICKLOOK_BENCH_ITERATIONS=25 ./Scripts/benchmark-renderer.sh
```

Expected: `code-heavy-100x.md` render median improves relative to the Task 1 baseline. `large-100x.md` and `mixed-realistic-100x.md` should not regress by more than 5%.

- [ ] **Step 5: Commit syntax helper**

Run:

```bash
git add MarkdownRendering/Sources/MarkdownSyntaxHighlighter.swift MarkdownRendering/Sources/MarkdownDocumentRenderer.swift
git commit -m "perf: cache syntax highlighting patterns"
```

---

### Task 6: Final Verification and Results Summary

**Files:**
- No required source edits unless a prior step exposes a regression.

- [ ] **Step 1: Run full renderer tests**

Run:

```bash
xcodebuild -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS' -derivedDataPath .derivedData/final-renderer-optimization CODE_SIGNING_ALLOWED=NO test
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 2: Run preview extension tests**

Run:

```bash
xcodebuild -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookPreviewExtensionTests -destination 'platform=macOS' -derivedDataPath .derivedData/final-preview-optimization CODE_SIGNING_ALLOWED=NO test
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 3: Run app tests**

Run:

```bash
xcodebuild -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookAppTests -destination 'platform=macOS' -derivedDataPath .derivedData/final-app-optimization CODE_SIGNING_ALLOWED=NO test
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 4: Run local profiling setup**

Run:

```bash
./Scripts/profile-performance.sh
```

Expected: script prints `Performance profiling build is ready.` and verifies local preview and thumbnail extension paths.

- [ ] **Step 5: Run final benchmark**

Run:

```bash
MARKDOWN_QUICKLOOK_BENCH_ITERATIONS=25 ./Scripts/benchmark-renderer.sh
```

Expected: tab-separated output. Compare against Task 1 baseline:
- `large-100x.md` total median should be at least 30% lower.
- `mixed-realistic-100x.md` total median should be at least 30% lower.
- `code-heavy-100x.md` total median should improve or stay within 5% if syntax extraction only reduces cumulative signpost overhead.

- [ ] **Step 6: Check formatting and worktree**

Run:

```bash
git diff --check
git status --short
```

Expected: `git diff --check` has no output. `git status --short` is clean after final commit.

- [ ] **Step 7: Commit any final benchmark documentation updates**

If final implementation changed `Scripts/benchmark-renderer.sh` or added a short note to an existing doc, commit it:

```bash
git add Scripts/benchmark-renderer.sh docs/superpowers/specs/2026-04-30-renderer-performance-optimization-design.md
git commit -m "docs: record renderer optimization results"
```

If there are no doc or script changes after Task 5, skip this commit and report the benchmark numbers in the final response.
