# Pluk Gap-Closure Roadmap — Design Spec

## Goal

Close the meaningful feature gaps between `MarkdownQuickLook` and `pluk-inc/markdown-preview` (see gap analysis at `~/.claude/plans/i-want-you-to-swirling-pine.md`) **without** committing to a full `WKWebView` rewrite. Optimize for: stay text-based, ship usable improvements weekly, defer the architectural fork until evidence forces it.

## Strategic decisions baked into this roadmap

These are choices, not facts. If any are wrong, rework starts here:

1. **Stay on `NSTextView` + hand-rolled parser as the primary rendering path.** The text-attribute pipeline gets us 85% of the value at 15% of the cost relative to a WKWebView rewrite, and preserves our ability to render *inside* the Quick Look extension (where data-based HTML adds attachment-rewrite friction).
2. **For features that fundamentally require a browser engine** — KaTeX math and Mermaid diagrams — render them off-screen via headless `WKWebView` → `NSImage` and embed as text attachments. We pay the WebKit cost once per math/diagram block, not once per document.
3. **Defer the full WKWebView migration to a discrete spec** (`Phase 6` below). It remains the right answer if we ever want true CSS theming, inline HTML support at scale, or feature parity with pluk's app. Until then it's a tracked option, not a workstream.
4. **Treat the host app as installer + settings, not a viewer.** Building a full document viewer (find bar, toolbar, inspector, project navigator) is a months-long effort that competes with QL-surface investment. We will *not* match pluk's app feature-for-feature; we will ship a better Quick Look.
5. **Distribution upgrades are orthogonal and should happen now.** Sparkle, DMG, Homebrew — these unblock user trust and have no dependency on rendering work.

If you disagree with any of (1)–(5), stop and re-spec before executing the per-phase plans below.

## Phase overview

| Phase | Scope | Plan file | Effort | Depends on |
|---|---|---|---|---|
| **1** | Cheap markdown parser features | `2026-05-23-phase1-markdown-features.md` | ~2 weeks | — |
| **2** | Quick Look extension UX | `2026-05-23-phase2-ql-ux.md` | ~1 week | — |
| **3** | Distribution & ops | `2026-05-23-phase3-distribution.md` | ~1 week | — |
| **4** | Math & diagrams (rasterized) | `2026-05-23-phase4-math-diagrams.md` *(spec only — needs spike)* | ~3 weeks | Spike on `WKWebView` rasterization perf |
| **5** | Host app expansion (optional) | `2026-05-23-phase5-host-app-design.md` *(decision doc)* | Variable | Strategic decision |
| **6** | WKWebView migration (option) | `2026-05-23-phase6-webview-migration-design.md` *(decision doc)* | ~2 months | Strategic decision |

Phases 1–3 are independent and parallelizable. Phase 4 is best-effort once Phase 1 lands. Phases 5–6 are decision documents; they don't get plans until a "yes."

---

## Phase 1 — Markdown parser features (text-based)

Goal: close the GitHub-Flavored-Markdown + ecosystem gaps that don't require a browser engine.

### 1.1 GitHub-style alert blockquotes

Recognize blockquote-first-paragraph markers `[!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]`, `[!CAUTION]`. Render with a labeled header row ("Note", "Tip", …), tint the left border per kind, allow a custom title after the marker on the same line.

**Acceptance:**
- `> [!NOTE]\n> Body` renders with a "Note" pill, blue tint, body underneath.
- `> [!WARNING] Read this first\n> Body` renders with "Read this first" as the title.
- Unknown marker (`[!FOO]`) falls back to a regular blockquote.
- Markers must be at the *start* of the first quoted line; not in the middle of a paragraph.

### 1.2 Footnotes (`[^id]` references + `[^id]: …` definitions)

Parse footnote definitions as a separate block list, render references as superscript clickable links to anchors at the document end, render definitions as a numbered list under a "Footnotes" rule.

**Acceptance:**
- `Body[^1].\n\n[^1]: Definition.` produces a `Body¹.` paragraph plus a footnotes section at the end with a back-reference.
- Multi-paragraph definitions (indented continuation lines) are supported.
- Undefined references render the literal `[^id]` text (no crash).
- Definitions in any order; references rendered in document order, numbered 1, 2, 3.

### 1.3 Table column alignment

Honor `:---`, `:---:`, `---:` in the separator row to set per-column `NSTextAlignment.left/.center/.right`. Default unspecified columns to `.natural`.

**Acceptance:**
- Each cell in a column inherits the alignment from the separator row.
- Header cell shares the alignment of its data cells.
- Existing tables (separator row with bare `---`) continue to render left-aligned.

### 1.4 Indented code blocks

A run of lines indented by ≥4 spaces (or 1 tab) outside an existing list item is a code block. Render with the same styling as fenced blocks, no language hint.

**Acceptance:**
- 4-space-indented lines become a single code block.
- The block ends at the first non-indented, non-blank line.
- A blank line between indented runs joins them into one block.
- Does not fire inside list-item continuation context (the existing list parser already eats indented continuations).

### 1.5 Reference-style links

Parse `[text][ref]` plus a definition `[ref]: url "optional title"` somewhere in the document. Resolve the link during render. Apple's `AttributedString(markdown:)` already supports this — verify it works through our pipeline; if intent attributes drop, post-process.

**Acceptance:**
- `[Apple][site]` plus `[site]: https://apple.com` produces a clickable link reading "Apple".
- Reference labels are case-insensitive.
- Unresolved references render as literal text.

### 1.6 TOML front matter (`+++ … +++`)

Recognize a `+++`-delimited block at the document head identically to YAML's `---` block. Same styled display (boxed monospace) or, per a settings flag, hide entirely.

**Acceptance:**
- `+++\nkey = "value"\n+++\n# Hello` parses front matter + heading.
- YAML and TOML produce the same `.frontMatter` block so downstream styling is unchanged.
- Mixed (`+++` with `---` end) is not recognized — both delimiters must match.

### 1.7 Code-fence info-string parsing

The opening fence's metadata after the language (e.g. ```` ```swift title="example.swift" ````, ```` ```mermaid {theme=dark} ````) is currently being lowercased into the language. Extract only the first whitespace-delimited token as the language; preserve the rest in a new `MarkdownCodeFenceInfo` struct for later use (Phase 4 will read `attributes`).

**Acceptance:**
- ```` ```mermaid {theme=dark} ```` → language `mermaid`, attributes string `{theme=dark}`.
- ```` ```swift title="example.swift" ```` → language `swift`, attributes `title="example.swift"`.
- Backwards compatible: ```` ```python ```` still produces language `python`, attributes empty.

### 1.8 Em/en dash polish

Keep our existing smart-typography behavior but document it as a setting (`renderSettings.smartDashes`) so power users can disable. Pluk doesn't do this — it's a real differentiator, but we shouldn't surprise users who paste `---` and get `—`.

**Acceptance:**
- Toggle via UserDefaults default (`smartDashesEnabled`, default `true`).
- When disabled, `---` outside code spans renders literally.

### 1.9 More UTI / file extension support

Today the QL extension only fires for `net.daringfireball.markdown`. Pluk fires for `public.markdown`, `net.daringfireball.markdown`, `net.ia.markdown`, `com.unknown.md`, plus their own exported UTIs for `.mdown`/`.mkd`/`.mkdn`/`.mdwn`/`.mdtxt`/`.mdtext`. The simple win: add the three third-party UTIs to all three Info.plists. The deeper win: export our own UTIs for the rare extensions.

**Acceptance:**
- `Info.plist`s for preview extension, thumbnail extension, and app declare `public.markdown`, `net.daringfireball.markdown`, `net.ia.markdown`, `com.unknown.md`.
- A file saved by iA Writer (UTI `net.ia.markdown`) gets our preview from Finder spacebar.
- Optional: declare exported `com.rzkr.MarkdownQuickLook.mdown`, `…mkd`, `…mkdn`, `…mdwn` for the long-tail extensions, with `UTExportedTypeDeclarations` in the app's Info.plist.

### 1.10 RTL paragraph direction

Detect paragraphs whose first strong character is RTL (Arabic / Hebrew) and set `NSParagraphStyle.baseWritingDirection = .rightToLeft`. Skip detection for code blocks.

**Acceptance:**
- A paragraph starting with Arabic text renders right-to-left.
- An English paragraph continues to render LTR even in an Arabic-majority document.
- Headings and list items respect the same per-block detection.

---

## Phase 2 — Quick Look extension UX

Goal: bring the QL surface up to a level where it stands on its own as the product, not just a parser host.

### 2.1 Code-block "Copy" affordance

`NSTextView`'s native context menu already supports copy. We add a *block-aware* copy: a hover state on each code block that shows a small "Copy" button anchored to the top-right of the block. Clicking copies the block's literal text (not the rendered/highlighted form).

Approach: track code-block ranges during render (a sidecar `[(NSRange, code: String)]` returned from the renderer alongside the attributed string). A tracking-area overlay on top of the `NSTextView` shows the button when the cursor is over a code block.

**Acceptance:**
- Hover over a code block: a "Copy" capsule fades in within ~80ms.
- Click: pasteboard receives the raw code (no leading/trailing whitespace, no language hint).
- Button briefly switches to "Copied" then back.
- Selecting the entire preview and copying does NOT include the literal text "Copy" / "Copied" anywhere in the copied content (anti-leakage — pluk shipped a regression fix for exactly this; see their CHANGELOG 0.0.25).
- Keyboard-only users can still copy via the standard select-all + ⌘C path; the new button is purely additive.

### 2.2 Text zoom (⌘+ / ⌘− / ⌘0)

Today the host app has a font-size slider; the QL preview itself has no zoom. Add menu-less key bindings inside the QL preview's `NSTextView` (intercepted in `keyDown(with:)`): ⌘= / ⌘+ zoom in, ⌘− zoom out, ⌘0 reset. Steps map to the existing `MarkdownTextSizeLevel` (7 levels). Persist current level to the shared App Group UserDefaults so it survives next preview.

**Acceptance:**
- ⌘+ on a preview increases text size one level; ⌘− decreases; ⌘0 returns to default.
- Setting persists across previews of different files.
- Out-of-bounds (⌘+ at max) is a no-op (or system beep), not a crash.

### 2.3 Atomic-save reload

When an editor (VS Code, Vim w/ writebackup, etc.) saves by writing to a temp file and renaming over the original, `FSEventStream` reports the inode/path change and our cached preview is stale. The Quick Look extension can subscribe to `DispatchSource.makeFileSystemObjectSource` while a preview is on screen, watch for `.write | .rename | .delete`, and re-render when the file's contents change.

Implementation note: `QLPreviewingController` previews are short-lived (spacebar dismissed), but `presentedItemDidChange` is the natural hook. We add an `NSFilePresenter` to `PreviewViewController` that re-fires `preparePreviewOfFile(at:)` on change.

**Acceptance:**
- Open a file in QL, edit it externally, save: preview updates within ~500ms without dismissing spacebar.
- Atomic save (write-to-tmp + rename) updates the preview against the original path.
- Test mocks the file presenter notification, no real FS race.

### 2.4 Native find (⌘F) in QL preview

`NSTextView`'s built-in find bar works if the view's `usesFindBar` is `true` and `isIncrementalSearchingEnabled` is set. Today our `MarkdownTextView` inherits these defaults but may not have them enabled. One-line fix plus a test that ⌘F shows the bar.

**Acceptance:**
- ⌘F in the preview shows the native NSTextView find bar at the top.
- ⌘G / ⌘⇧G cycle next/previous match.
- Escape dismisses the bar.

### 2.5 Link click handling

`NSTextView` opens links via `NSWorkspace.shared.open` by default when `isEditable = false` and `isSelectable = true`. Verify this works inside the QL extension (sandbox can block). If it doesn't, override `textView(_:clickedOnLink:at:)` in a delegate and call `NSWorkspace.shared.open` explicitly.

**Acceptance:**
- Clicking an HTTP link in QL opens it in the default browser.
- Clicking a `file://` link to a sibling `.md` opens it in our app (default handler) or the user's choice.
- Clicking a `mailto:` link composes in Mail.

### 2.6 Inline image attachment polish

We already load local images. Two small wins:
- Honor `width=`/`height=` HTML attributes in `<img>` if present in raw HTML inside an `![]()` alt (a common pattern in GitHub READMEs is `<img src="..." width="200">`). Today raw HTML drops; we'd add a minimal `<img>` shim before falling back.
- Sandbox-safety: confirm `NSImage(contentsOf:)` succeeds for paths that resolve to siblings of the QL'd file but are not the file itself. The QL extension gets read access to the previewed file's directory; verify via fixture.

**Acceptance:**
- An `<img src="diagram.png" width="300">` in raw HTML renders the image at 300pt wide instead of being dropped.
- A relative-path image (`![](images/diagram.png`) loads regardless of where the parent file lives.

---

## Phase 3 — Distribution & ops

Goal: be installable and updatable like a real Mac app.

### 3.1 Switch artifact from `.zip` to `.dmg`

Replace the `Scripts/build-release.sh` zip step with a DMG step using `create-dmg` (npm / brew) or `hdiutil`. Sign the DMG with our existing Developer ID identity, notarize, staple. Update `release.yml` to upload the DMG and update README install instructions.

**Acceptance:**
- `Scripts/build-release.sh` produces a signed, notarized DMG.
- Drag-to-Applications metaphor inside the DMG (background image + symlink).
- DMG passes `spctl -a -v` and `xcrun stapler validate`.

### 3.2 Sparkle auto-update

Add Sparkle 2.x as a Swift package dependency to the host app. Wire `SUUpdater` into the install-experience screen with a "Check for Updates…" menu item. Generate an EdDSA keypair, store the private key in macOS Keychain, embed the public key as `SUPublicEDKey` in Info.plist. Publish an appcast at a stable URL.

**Acceptance:**
- App's "Check for Updates" menu item works.
- Sparkle validates EdDSA signature before installing.
- Appcast hosted at a stable URL (GitHub Pages, or a custom domain if we have one).
- Update flow doesn't re-prompt for permissions (sandbox + XPC helper services).

### 3.3 Homebrew cask

Submit a cask to homebrew/cask. The cask reads our GitHub Releases for new versions and downloads the DMG.

**Acceptance:**
- `brew install --cask markdown-quicklook` (final name TBD) installs the app.
- `brew upgrade` picks up new releases.
- Pre-condition: 3.1 (DMG) and reasonably-named tags.

### 3.4 `CHANGELOG.md`

Adopt Keep-a-Changelog format checked into the repo root. Release script reads the topmost `## [version] - date` block to seed the GitHub release notes and (in Phase 3.2) the Sparkle release-notes HTML.

**Acceptance:**
- `CHANGELOG.md` exists with retroactive entries for the last 5 releases.
- `Scripts/build-release.sh --version X.Y.Z` validates that a matching entry exists before tagging.
- GitHub release body is populated from the changelog entry, not from `git log`.

### 3.5 Versioned releases (replace rolling)

Today every push to `main` cuts a rolling release. Replace with: only tags push releases, and tags require a `Version.xcconfig` (or equivalent) version bump that matches the `CHANGELOG.md` entry.

**Acceptance:**
- Push to `main` runs CI tests only, no release.
- Push of a `v0.X.Y` tag runs CI + release.
- README install link points to "Latest" GitHub release, which is always the most recent tag.

---

## Phase 4 — Math & diagrams (deferred, spec-only here)

Goal: render KaTeX-style math and Mermaid diagrams inside the existing `NSTextView` pipeline using off-screen WebKit rasterization. See `2026-05-23-phase4-math-diagrams-design.md` for full architecture.

**Why not a separate plan yet:** the perf characteristics of headless `WKWebView` snapshot are unknown for our use case. Land a spike first (rasterize one KaTeX block; measure cold-start and per-block cost) before committing to the full implementation.

**Out-of-scope for the spec:** any feature that requires interactive math/diagram behavior (Mermaid pan/zoom — pluk's CHANGELOG 0.0.16). Rasterization is a static-image path; interactivity needs a real WebView and lives in Phase 6.

---

## Phase 5 — Host app expansion (decision doc, not a plan)

Goal: decide whether to convert the host app from "installer + status screen" to a real document viewer. See `2026-05-23-phase5-host-app-design.md`.

Possible features (each costs days–weeks):
- Find bar (⌘F)
- Customizable toolbar
- Open With editor menu (filtered to real editors)
- Inspector panel (file metadata)
- Project Navigator (sibling files browser)
- Share-as-source (Copy → Markdown to pasteboard)
- Default handler registration prompt

Each could ship without the others. The decision is *how aggressive* — pluk's app is one of their two product surfaces; ours is currently a vestigial installer. The roadmap *recommends* shipping only the Open-With menu + default-handler prompt + share-as-source (combined ~3 days), and stopping there.

---

## Phase 6 — WKWebView migration option (decision doc)

Goal: hold open the option of rewriting the preview surface as a `WKWebView` rendering HTML produced by `swift-markdown`. See `2026-05-23-phase6-webview-migration-design.md`.

The roadmap explicitly does NOT recommend this today. It's tracked because:
1. If Phase 4 (math/diagrams rasterization) blows up on perf, the next best path is migration.
2. If inline HTML, full CSS theming, or per-codeblock interactive behavior becomes a must-have, migration is the right answer.
3. If we adopt swift-markdown anyway (to get footnotes / reference links for free), the rendering pipeline can be reconsidered.

---

## Cross-cutting things

These don't belong to one phase:

- **Adopt `swift-markdown` as a dependency.** Apple's cmark-gfm-backed parser. If we adopt it, items 1.2 (footnotes), 1.5 (reference links), 1.7 (info-string), and the underpinnings for 4.x all simplify. **Decision:** for Phase 1 we keep the hand-rolled parser (the changes above are small enough), and we revisit swift-markdown adoption as a precondition to Phase 6.
- **App Group UserDefaults.** Already in place (`group.com.rzkr.MarkdownQuickLook`). Phase 2's zoom level and Phase 1.8's smart-dashes flag both go here.
- **Test fixtures.** Add `Fixtures/Pluk-Parity/` with one fixture per feature (alerts, footnotes, aligned table, indented code, refs, TOML, info-string, RTL). Drive snapshot-style tests by rendering and comparing block-by-block.
- **Performance regression check.** Phase 4 risks slowing first-paint. Reuse `MarkdownPerformanceInstrumentation` in `MarkdownDocumentRenderer.swift:72–80` to keep measurements honest.

---

## Out of scope for this roadmap

Things called out in the gap analysis that we are *not* doing:

- Mermaid pan-zoom interactivity (needs Phase 6).
- KaTeX `copy-tex` (copying rendered math as LaTeX source).
- DOMPurify-style HTML sanitization (we don't render arbitrary HTML).
- Project Navigator / Inspector in QL extension (no app architecture to host them).
- Customizable toolbar (Phase 5 only).
- Definition lists, highlights `==x==`, subscript / superscript, emoji shortcodes — neither we nor pluk implement these; chase only if a real user asks.

---

## Suggested execution sequence

If you have one engineer for ~4 weeks:

1. **Week 1:** Phase 3 (distribution) end-to-end. Independent, unblocks future trust gains. Phase 2.4 (find bar enable) as a 30-minute warm-up.
2. **Week 2:** Phase 1.1–1.4 (alerts, footnotes, table alignment, indented code). Highest user-visible value per hour.
3. **Week 3:** Phase 1.5–1.10 (refs, TOML, info-string, smart dashes flag, UTIs, RTL). Phase 2.1–2.3 (copy button, zoom, atomic-save reload).
4. **Week 4:** Phase 4 spike. If perf passes, draft the Phase 4 plan; if not, write up findings and stop. Phase 2.5–2.6 (link clicks, image polish) as fillers.

Phase 5 / Phase 6 only kick off after explicit user direction.

---

## Verification (across phases)

End-to-end smoke after each phase:

```bash
# Build
xcodegen generate
./Scripts/build-release.sh

# Test
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS'
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookPreviewExtensionTests -destination 'platform=macOS'
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookAppTests -destination 'platform=macOS'

# Visual verification (this project IS a Quick Look extension; preview specs in QL)
qlmanage -p Fixtures/Pluk-Parity/alerts.md
qlmanage -p Fixtures/Pluk-Parity/footnotes.md
qlmanage -p Fixtures/Pluk-Parity/aligned-table.md
qlmanage -p Fixtures/Pluk-Parity/toml-frontmatter.md
qlmanage -p Fixtures/Pluk-Parity/rtl.md
```
