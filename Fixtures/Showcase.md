# Project Roadmap

A quick overview of where we are and what's next.

## Current Sprint

- [x] User authentication
- [x] Dashboard layout
- [ ] Search functionality
- [ ] Export to PDF

## API Endpoints

| Endpoint | Method | Status |
|----------|--------|--------|
| /api/users | GET | Live |
| /api/search | POST | In Progress |
| /api/export | GET | Planned |

## Quick Start

```swift
import MarkdownKit

let document = try Document(parsing: source)
let html = HtmlFormatter().format(document)
print(html)
```

> **Note:** This library requires macOS 14.0 or later. Earlier versions are not supported due to API availability constraints.

## Architecture

The system uses a **three-layer** design:

- **Parsing** — converts raw Markdown into an AST
- **Rendering** — transforms the AST into styled output
- **Display** — presents the result in a native view
