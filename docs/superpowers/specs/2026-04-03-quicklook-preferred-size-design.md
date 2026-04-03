# Quick Look Preferred Size Heuristic Design

## Goal

Improve the initial Quick Look panel size for Markdown previews so longer documents open in a taller panel by default.

## Scope

This change applies only to the modern Quick Look preview extension.

It does not attempt to take over full window management from macOS. The system Quick Look host still owns the actual panel and may clamp, ignore, or override the extension's preferred size.

## Behavior

The preview extension should set `preferredContentSize` on its `QLPreviewingController` view controller.

Use a heuristic rather than expensive layout measurement:

- Loading and error states use a fixed comfortable default size
- Rendered previews use a fixed preferred width
- Rendered previews request a taller preferred height for longer documents
- Preferred height is capped so extremely long documents still rely on scrolling

## Sizing Rules

Use the following intent:

- Loading/error default size: approximately `900 x 800`
- Rendered width: approximately `900`
- Rendered base height: approximately `900`
- Rendered long-document cap: approximately `1400`

The exact heuristic can be based on rendered text length or line count as long as it is deterministic, inexpensive, and easy to test.

## Implementation Direction

Add a small sizing helper in the preview extension layer rather than embedding sizing math directly inside the SwiftUI view.

The view controller should:

- apply the loading/error preferred size before preview data is ready
- update the preferred size again after rendered content is available

## Testing

Add unit coverage for:

- default loading/error preferred size
- short documents staying near base height
- longer documents requesting a taller preferred height
- very long documents capping at the configured maximum

Tests should verify the controller's preferred size directly instead of trying to automate Quick Look panel behavior.

## Non-Goals

- Dynamically resizing the host Quick Look window while the user is reading
- Perfect content measurement based on font layout
- Replacing scrolling for long Markdown documents

## Success Criteria

- Markdown previews open with a noticeably more usable default size
- Longer documents request a taller starting panel than short documents
- The sizing logic remains simple, deterministic, and covered by unit tests
