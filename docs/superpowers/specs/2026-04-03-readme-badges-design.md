# README Badge And Download Callout Design

## Goal

Improve the public README so GitHub visitors can quickly confirm that the project is active, tested, downloadable, and MIT licensed.

## Scope

This change updates the README presentation only. It does not change app behavior, packaging, release contents, or GitHub Actions workflow logic.

## Badge Row

Add a compact badge row directly under the `# Markdown Quick Look` heading in `README.md`.

The row should include:

- Release workflow status
- Latest GitHub release
- Total GitHub release downloads
- MIT license
- macOS requirement (`macOS 14+`)

## Badge Style

Use Markdown image links rather than HTML.

Use a hybrid approach:

- GitHub-hosted badge for the `Release` workflow status
- Shields badges for latest release, downloads, license, and macOS requirement

The badges should be concise and readable in GitHub's standard README rendering without wrapping into multiple noisy sections on common desktop widths.

## Install Callout

Add a clear `Download latest release` link near the top of the `Install` section before the numbered steps.

The link should point to the repository's Releases page rather than a hard-coded asset URL so it always resolves to the newest available package.

## Content Constraints

- Keep the existing README structure intact
- Do not add marketing copy
- Do not duplicate release instructions elsewhere in the file
- Do not add unsupported claims such as notarization or signed-distribution trust indicators

## Success Criteria

- A first-time visitor can immediately see build status, latest release presence, download availability, license, and supported macOS floor
- The Install section has a clear top-level path to the latest downloadable app
- The README remains compact and credible rather than badge-heavy
