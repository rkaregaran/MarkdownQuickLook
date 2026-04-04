# Markdown Quick Look

This file checks the app's best-effort preview path for standard `.md` files.

## Checklist

- Heading styling
- Paragraph spacing
- List bullets
- [Link rendering](https://openai.com)

> If Finder still shows plain text, the extension may be registered correctly and macOS may still prefer the built-in preview.

```swift
let greeting = "hello, quick look"
print(greeting)
```

## Features

| Feature | Status | Notes |
|---------|--------|-------|
| Headings | Supported | h1 through h6 |
| Lists | Supported | Bullet lists |
| Code blocks | Supported | Fenced with ``` |
| Tables | Supported | Pipe-delimited |
