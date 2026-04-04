# Markdown Quick Look

This file checks the app's best-effort preview path for standard `.md` files.

## Checklist

- [x] Heading styling
- [x] Paragraph spacing
- [x] List bullets
- [ ] Ordered lists
- [x] [Link rendering](https://openai.com)

> If Finder still shows plain text, the extension may be registered correctly and macOS may still prefer the built-in preview.

```swift
let greeting = "hello, quick look"
print(greeting)
```

## Features

| Feature | Status | Notes |
|---------|--------|-------|
| Headings | Supported | h1 through h6 |
| Lists | Supported | Bullet and ordered |
| Code blocks | Supported | Fenced with syntax highlighting |
| Tables | Supported | Pipe-delimited |
| Strikethrough | Supported | ~~like this~~ |

---

## Ordered Steps

1. Select a .md file in Finder
2. Press Space to preview
3. Enjoy formatted markdown

This text has ~~strikethrough~~ and **bold** and *italic* formatting.
