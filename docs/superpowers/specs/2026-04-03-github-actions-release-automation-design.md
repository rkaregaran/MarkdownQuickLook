# GitHub Actions Release Automation Design

## Goal

Add GitHub Actions-based CI and release automation so every commit that lands on `main`:

- runs the existing macOS test/build checks
- produces the existing release zip via `Scripts/build-release.sh`
- creates a distinct rolling GitHub Release entry
- uploads a downloadable `MarkdownQuickLook-macOS.zip` asset to that release

This must cover both:

- direct pushes to `main`
- pull request merges into `main`

## Constraints

- Keep the release model intentionally simple
- Reuse the repo's existing build and packaging scripts rather than duplicating logic in YAML
- Do not add signing, notarization, App Store packaging, DMGs, or semantic-version management
- Treat `main` as the only release source
- Generate a new rolling release for every `main` push; do not overwrite a shared "latest" prerelease
- Keep release assets aligned with the current local release flow:
  - `dist/MarkdownQuickLook-macOS.zip`
  - zip expands to top-level `MarkdownQuickLook.app` and `LICENSE`

## Current Repo Context

The repo already has the local pieces needed for CI/CD:

- `Scripts/build-release.sh`
  Purpose: builds a Release app, stages `dist/MarkdownQuickLook.app`, copies `LICENSE`, and creates `dist/MarkdownQuickLook-macOS.zip`
- `Scripts/dev-preview.sh`
  Purpose: local debug verification and Quick Look registration flow
- `Scripts/check-preview-runtime.sh`
  Purpose: validates extension runtime packaging
- `project.yml`
  Purpose: generates the Xcode project
- test schemes:
  - `MarkdownRenderingTests`
  - `MarkdownQuickLookPreviewExtensionTests`
  - `MarkdownQuickLookAppTests`

The GitHub workflow should call those existing entry points instead of re-implementing their behavior.

## Recommended Trigger Model

### Single Release Workflow on `push` to `main`

Use one workflow that runs on:

- `push`
  - branches: `main`

This covers both user requirements without special-case branching:

- a merged PR becomes a push to `main`
- a direct push is already a push to `main`

This means the workflow does not try to inspect PR approval state itself. Approval is a repository-policy concern enforced through branch protection and merge settings. The automation simply treats "commit landed on `main`" as the release signal.

## Release Identity

### Rolling Tag Format

Each workflow run should create a unique tag using UTC timestamp plus short SHA:

`main-YYYYMMDD-HHMMSS-<shortsha>`

Example:

`main-20260403-192733-25059ff`

### Release Type

Each published entry should be a new prerelease, not a full semver release.

Why:

- the user explicitly wants rolling builds
- the repo does not yet have semantic-version management
- prerelease status accurately signals that these are automation-driven snapshots of `main`

### Release Title

Keep it simple and derivable from the tag, for example:

`Rolling release main-20260403-192733-25059ff`

## Workflow Shape

### File

Add:

- `.github/workflows/release.yml`

### Runner

Use a GitHub-hosted macOS runner.

Recommended initial choice:

- `runs-on: macos-latest`

Rationale:

- this repo already targets macOS builds
- GitHub currently documents `macos-latest` as a standard GitHub-hosted runner label
- keeping the first version simple matters more than pinning runner migration strategy up front

### Permissions

Grant the workflow only the repository permissions it needs:

- `contents: write`

This is required to create tags and GitHub Releases with the workflow `GITHUB_TOKEN`.

### Concurrency

Serialize release creation for `main` so rapid consecutive merges do not race on release publishing steps:

- concurrency group: `release-main`
- `cancel-in-progress: false`

This preserves the rule that every `main` push gets its own release instead of having a newer run cancel an older one.

## Job Steps

The workflow should have one release job with these responsibilities.

### 1. Check out the repo

Use the standard checkout action so the workflow runs against the pushed `main` commit.

### 2. Install repo prerequisites

Install `XcodeGen` on the runner before invoking repo scripts.

The workflow should prefer a straightforward installation step such as Homebrew rather than introducing extra setup layers.

### 3. Log and validate Xcode environment

Run `xcodebuild -version` and fail early if the runner image is too old for the repo requirement.

Reason:

- this repo documents `Xcode 26.1.1 or newer`
- runner images change over time
- a clear early failure is better than a later opaque compile failure

### 4. Generate the project

Run:

`xcodegen generate`

Even though `Scripts/build-release.sh` also regenerates the project, keeping project generation explicit in CI makes failures easier to localize in logs.

### 5. Run automated tests

Run the three existing test schemes:

- `xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS'`
- `xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookPreviewExtensionTests -destination 'platform=macOS'`
- `xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookAppTests -destination 'platform=macOS'`

Release creation must stop if any of these fail.

### 6. Build the release artifact

Run:

`./Scripts/build-release.sh`

This preserves one source of truth for:

- Release build configuration
- runtime packaging checks
- zip construction
- `LICENSE` inclusion

### 7. Derive the rolling tag

Generate a UTC timestamp in the workflow and combine it with the short commit SHA to form the tag and release title.

The tag should be computed inside the workflow so each `main` push gets a unique release even when two merges land close together on the same calendar day.

### 8. Create the GitHub Release

Create a new prerelease for that tag using the workflow `GITHUB_TOKEN`.

The release body can stay simple and machine-generated. It should at minimum include:

- commit SHA
- workflow run reference
- note that this is an automated rolling build from `main`

Optional but acceptable:

- GitHub-generated release notes

### 9. Upload release assets

Upload:

- `dist/MarkdownQuickLook-macOS.zip`

The zip already contains both:

- `MarkdownQuickLook.app`
- `LICENSE`

No additional asset is required for the first version.

## Failure Semantics

- If project generation fails: no release
- If any test fails: no release
- If `Scripts/build-release.sh` fails: no release
- If release creation fails after the zip is built: the workflow fails and the logs remain the recovery path

The workflow should not attempt complicated cleanup or rollback logic for the initial version.

## Documentation Changes

### README

Add a short maintainer-facing section explaining:

- pushes to `main` automatically create a rolling prerelease
- release assets are generated by GitHub Actions
- local release packaging remains available through `./Scripts/build-release.sh`

This should stay below the end-user install section.

### Optional Maintainer Note

If useful, add a short note about repository settings expectations:

- Actions enabled
- branch protection on `main` if PR approval should be mandatory before merge

## Out of Scope

- semantic versioning
- manual release drafting workflows
- notarization or Developer ID signing
- changelog management
- deleting or pruning old rolling releases
- multi-platform artifacts
- guaranteeing that a PR was approved in workflow logic itself

## Exit Criteria

This design is complete when:

- the repo contains a GitHub Actions workflow that runs on every push to `main`
- that workflow runs the existing test suite and release build
- every successful `main` push creates a distinct rolling prerelease
- the release contains `MarkdownQuickLook-macOS.zip`
- the uploaded zip expands to top-level `MarkdownQuickLook.app` and `LICENSE`
- the README explains that `main` pushes publish rolling releases
