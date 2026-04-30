# Table Heavy Fixture

This fixture emphasizes table parsing and layout.

| Phase | Purpose | Sample Metric |
| --- | --- | --- |
| Request | Receive the preview request | request.start |
| Prepare | Load and normalize Markdown input | prepare.duration |
| Settings | Resolve rendering preferences | settings.duration |
| Render | Convert Markdown to preview output | render.duration |
| Apply | Attach rendered output to the view | apply.duration |
| Thumbnail | Produce thumbnail content when requested | thumbnail.duration |

| Document | Size | Links | Images | Code Blocks | Notes |
| --- | ---: | ---: | ---: | ---: | --- |
| small.md | Small | 1 | 0 | 1 | README-style smoke fixture |
| large.md | Large | 1 | 0 | 0 | Prose-heavy coverage |
| code-heavy.md | Medium | 0 | 0 | 5 | Syntax highlighting workload |
| table-heavy.md | Medium | 0 | 0 | 0 | Table layout workload |
| image-heavy.md | Medium | 0 | 3 | 0 | Local, missing, and remote images |
| mixed-realistic.md | Large | 0 | 1 | 1 | Combined realistic preview |
