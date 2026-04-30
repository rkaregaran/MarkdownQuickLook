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
  build-for-testing >/tmp/markdownquicklook-renderer-benchmark-build.log

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
