# Markdown Quick Look

Best-effort macOS Quick Look preview app for standard Markdown files.

## Requirements

- Xcode 26.1.1 or newer
- XcodeGen 2.45.3 or newer

## Generate the project

```bash
xcodegen generate
open MarkdownQuickLook.xcodeproj
```

## Run the local verification flow

```bash
./Scripts/dev-preview.sh
```

Then:

1. Open Finder
2. Select `Fixtures/Sample.md`
3. Press `Space`

## Expected outcomes

- Success case: Finder uses the app's custom preview for `Fixtures/Sample.md`
- Limitation case: Finder keeps the built-in plain-text preview even though the app and extension built and registered correctly
