# Mixed Realistic Preview Fixture

## Summary

This fixture resembles a small engineering note for local profiling. It combines prose, task lists, tabular status, code, and an image reference while keeping the content safe for public sharing.

## Preview Checklist

- Confirm the fixture opens in the Quick Look preview.
- Compare timing values across repeated local runs.
- Keep environment notes outside the fixture file.

- [x] Include representative Markdown blocks
- [x] Reference an existing screenshot
- [ ] Add run-specific findings in a separate local note

> Local profiling works best when the input document is stable and the measurements are collected consistently.

## Phase Summary

| Phase | Expected Work |
| --- | --- |
| Request | Begin a preview request measurement |
| Prepare | Load Markdown and prepare renderer input |
| Render | Convert Markdown to preview output |
| Apply | Display the rendered preview |

## Instrumentation Sample

```swift
import Foundation

let measurement = MarkdownPerformanceInstrumentation.begin("preview.request")
defer { measurement.end() }

func renderPreview(markdown: String) {
    print("Rendering \(markdown.count) characters")
}
```

## Screenshot Reference

![Quick Look preview screenshot](../../Screenshots/quick-look-preview.png)

The fixture is intentionally realistic enough to exercise common rendering paths without embedding private project details.
