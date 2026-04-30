# Large Markdown Fixture

## Overview

This prose-heavy fixture provides enough structure to exercise parsing, rendering, and layout paths without relying on private or environment-specific information. It includes **bold text**, *emphasis*, inline `configuration` references, and a [safe example link](https://example.com).

The first section is intentionally ordinary. It gives the renderer several paragraphs to measure while keeping the content easy to inspect during local performance profiling.

## Document Flow

The document flow includes nested list content so layout can measure indentation and line wrapping.

- Request lifecycle
  - Create a preview request
  - Prepare the source content
  - Render the generated HTML
- User settings
  - Read stored options
  - Apply defaults when needed

> A repeatable fixture should be stable, safe to share, and clear enough to debug when timings move.

## Ordered Steps

1. Open the fixture in a local preview workflow.
2. Capture timing information for request, prepare, render, and apply phases.
3. Compare the measurements with earlier local runs.
4. Note any meaningful regression before changing parser or renderer behavior.

- [x] Include prose-heavy content
- [x] Include inline formatting
- [ ] Record environment-specific observations outside the fixture

## Closing Notes

This final section keeps the fixture realistic while avoiding client, personal, or private content. The paragraph gives the renderer one more block to process after lists and checklist items, which helps local profiling exercise the end of the document pipeline.
