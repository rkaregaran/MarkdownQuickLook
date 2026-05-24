# Phase 5: Host App Expansion — Decision Spec

> **Status:** Decision document — no implementation plan attached. The roadmap's recommendation is to ship only the three items in § "Recommended minimal subset" below and stop there. Everything else is a future-Reza problem.

## Context

Today the host app `MarkdownQuickLookApp` is an installer shell: it exists so macOS will register the Quick Look extension, plus a `StatusView` that tells the user how to use it and exposes a font-size slider. Pluk's `markdown-preview` ships an app that is a real document viewer with sidebar, inspector, find bar, customizable toolbar, "Open With" menu, share sheet, and file watcher.

Their app is one of two product surfaces (the other is Quick Look). Ours is currently vestigial. This document captures the options and the recommended cut.

The strategic question is **what is the product**:

- If the product is "Quick Look for Markdown done really well," the host app stays minimal and Phase 1+2+3 do all the work that matters. Phase 5 is mostly skipped.
- If the product is "a Markdown viewer for macOS that also has a Quick Look extension," then Phase 5 becomes a multi-month effort approaching pluk's surface area.

The roadmap's strategic decision (see `2026-05-23-pluk-gap-roadmap-design.md` § "Strategic decisions") commits to the first framing. This document records what we are *not* doing and why, and the small subset we *are* doing.

## Recommended minimal subset (~3 dev days total)

Three items justify themselves on user-facing impact per hour and don't drag in significant architecture.

### 5.A — Default-handler registration prompt

On first launch, detect whether MarkdownQuickLook is the default handler for `.md` (and the other UTIs we declared in Phase 1.9). If not, show a one-time prompt: "Make MarkdownQuickLook the default? [Yes / Not now / Don't ask again]". On Yes, call `LSSetDefaultRoleHandlerForContentType` for each UTI.

**Acceptance:**
- First launch shows the prompt only if we're not already the default for `net.daringfireball.markdown`.
- "Not now" suppresses for the rest of the session.
- "Don't ask again" sets a `UserDefaults` flag.
- Yes registers us as default and shows confirmation.

**Files:** new `MarkdownQuickLookApp/App/DefaultHandlerRegistration.swift`, modify `StatusView.swift` to host the prompt.

### 5.B — Open With editor menu

When the user opens a `.md` from Finder via "Open With → MarkdownQuickLook," our app's window typically opens. We add an "Open in editor…" menu item to the host app that lists Markdown-capable editors (filtered via Launch Services) and remembers the chosen one.

**Acceptance:**
- Menu lists apps that declare an editor role for `net.daringfireball.markdown` / `public.markdown` (use `LSCopyApplicationURLsForURL` with `LSRolesMask.editor`).
- Filters out noisy non-editors (Preview, Reader, Marked, ...). Maintain an allowlist for known-good editors that register with non-DF UTIs: VS Code, Cursor, Zed, Sublime Text, BBEdit, Nova, CotEditor, TextMate, MacVim, Xcode, TextEdit, iA Writer, Typora, MacDown, Obsidian.
- Selected editor is remembered (UserDefaults).
- Selecting "Always use X" persists the choice; otherwise the menu offers one-shot selection.

**Files:** new `MarkdownQuickLookApp/App/OpenWithEditor.swift`, modify `StatusView.swift` and the main menu.

**Caveat:** the QL preview itself does NOT get this menu (no app context). It's app-only.

### 5.C — Share-as-source (Copy → Markdown text, not file URL)

In the host app's File or Share menu, add a "Copy as Markdown" item that puts the *raw source* of the currently-shown file on the pasteboard. Why: a real product win pluk identified — users frequently want to paste a `.md` into ChatGPT / Claude, and putting the file URL on the pasteboard is useless.

**Acceptance:**
- "Copy as Markdown" menu item (⌘⇧C) puts the file's UTF-8 source on the general pasteboard.
- An `NSSharingServicePicker` fed the source string instead of the file URL, so Messages/Mail/Notes attach the content not the file.

**Files:** modify `StatusView.swift` or wherever the menu is defined.

**Out of pluk's version we don't replicate:** their toolbar Share button. We just add the menu item; no toolbar.

## Items deliberately deferred (per item)

Each entry below documents the option, the cost, the reasons it's tempting, and the reasons not to do it now. Re-evaluate when there's user demand.

### Find bar in the host app window

**What:** A real find bar with Next/Prev, Match Contains/Begins With (pluk has these toggles).
**Cost:** ~1 day if `NSTextView`'s native find bar is fine; ~3–4 days if we want pluk's custom UI.
**Why later:** Phase 2.4 already enables the native find bar in the QL preview. The QL surface is where most users find from. The host app is rarely opened; it doesn't need its own find UI.

### Customizable toolbar (View → Customize Toolbar…)

**What:** `NSToolbar` with `allowsUserCustomization`, items for Print/Copy/Zoom/Sidebar/Open With/Inspector/Share/Search.
**Cost:** ~1 week.
**Why later:** Toolbars only matter in a real document viewer with sustained dwell time. Our app is launched once, hangs out for install, mostly closes.

### Inspector panel (file metadata)

**What:** A right-side panel showing file path, size, dates, word count, heading count.
**Cost:** ~2–3 days.
**Why later:** Nice but cosmetic. Finder's Get Info already shows the file metadata. Word/heading counts are derivable from our parser output (cheap) but the UI scaffolding is real work.

### Project Navigator (sibling files browser)

**What:** Left sidebar showing other `.md` files in the same directory, with file watcher to react to renames/adds/deletes.
**Cost:** ~1 week.
**Why later:** This is the feature pluk shipped most recently (CHANGELOG 0.0.19, 0.0.21). It's polished, but it's a "real app" feature. We're not a real app.

### TOC sidebar (host app)

**What:** Like our QL TOC sidebar but in the host app.
**Cost:** ~2 days (mostly reuse).
**Why later:** Reasonably cheap. If we ever ship the host app as a real viewer, port the existing `TableOfContentsViewModel` over. Until then, redundant.

### Print support

**What:** ⌘P prints the rendered preview.
**Cost:** ~2 days for clean PDF output via `NSPrintOperation` against the `NSTextView`.
**Why later:** Niche. Users print Markdown rarely.

### File watcher for the host app window

**What:** Same as Phase 2 Task 4 but for the app's currently-shown document.
**Cost:** trivial once Phase 2.4 lands — same `FileWatcher` reusable.
**Why later:** Cheap, but only useful if we have a real viewer, which we don't.

### Document model / "currently open file"

**What:** A real `NSDocument`-style architecture so the app can have multiple windows, recent-files menu, restore on relaunch.
**Cost:** ~2 weeks.
**Why later:** Premature. Don't build this until there's an actual user complaint that the app doesn't behave like a document app.

### Welcome / first-launch experience

**What:** A polished onboarding flow that introduces Quick Look, sets defaults, offers to enable extensions.
**Cost:** ~3 days.
**Why later:** The existing `StatusView` + Phase 5.A's default-handler prompt cover this functionally. A designed onboarding is a "ship a real product" task.

## What would change the calculus

This recommendation flips to "expand the host app" if any of these happen:

1. **A WKWebView migration (Phase 6) is greenlit.** The host app would inherit the rendering pipeline naturally; toolbar/find/sidebar work would be paid back over both surfaces.
2. **More than 20% of installs report opening the host app for sustained use** (we currently have no telemetry; the assumption is < 1%).
3. **A "default Markdown viewer for macOS" niche emerges** that we want to claim. Quick Look is becoming less central in newer macOS UX patterns (Stage Manager, etc.).
4. **A clear competitor (Marked, Typora, Obsidian-as-viewer) ships a feature that gets repeatedly requested.** Reactive expansion is fine.

## Tracking

If/when we decide to do one of the deferred items, file a separate spec:

- `docs/superpowers/specs/YYYY-MM-DD-host-app-find-bar-design.md`
- `docs/superpowers/specs/YYYY-MM-DD-host-app-toolbar-design.md`
- etc.

Each should reference back to this document and include the cost/value rationale that changed.

## Acceptance for this phase (the minimal subset)

After 5.A, 5.B, 5.C ship:

- A clean-install macOS user, on first launch of `MarkdownQuickLook.app`, is offered to make it the default `.md` handler. They can dismiss permanently. The choice sticks.
- The app's main menu has "Open in editor…" with at least the locally-installed editors that handle Markdown.
- "Copy as Markdown" / `Share menu → recipient` deliver the raw source, not the file URL.
- Total LOC change in the app target: under ~500 lines.
- Existing `MarkdownQuickLookAppTests` continues to pass; new tests cover 5.A's gating logic and 5.B's editor filter.
