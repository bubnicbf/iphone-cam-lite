# Contributing to iphone-cam-lite

Thanks for considering a contribution. This project is a native macOS
Swift menu bar app built with the Swift Package Manager (no Xcode
project file) — see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for why
SwiftPM and how the modules fit together.

## Prerequisites

- macOS Ventura (13) or newer.
- Xcode 15+ or a standalone Swift 5.9+ toolchain (`swift --version`).
- No other runtime dependency: the app has no third-party package
  dependencies, and the only remaining shell script
  (`scripts/package_app.sh`) is used for packaging a `.app` bundle, not
  for building or testing.

## Getting set up

```sh
git clone git@github.com:bubnicbf/iphone-cam-lite.git
cd iphone-cam-lite
git checkout dev
swift build
swift test
```

`swift build` resolves the local package graph
(`Packages/{Logging,SystemChecks,CameraCore,AppAutomation}` plus the root
`App` target) and builds everything; `swift test` runs all three test
targets. The equivalent `make build` / `make test` targets are also
available — see the Makefile.

## Branching

Base new work on `dev`, not `main` — `dev` is the active integration
branch. Name branches by the kind of change they make:

- `bug/<short-description>` for bug fixes
- `feature/<short-description>` for new functionality
- `chore/<short-description>` for tooling, docs, tests, and other
  non-user-facing maintenance

Open pull requests against `dev`.

## Running the tests

```sh
make test          # everything
make test-unit      # CameraCoreTests + AdapterFixtureTests
make test-ui         # UITests
```

See [docs/TESTING.md](docs/TESTING.md) for exactly what each of the three
`Tests/` directories covers. The suite is entirely hermetic: it never
launches Zoom or Teams, never changes your actual camera/microphone
selection, and never restarts real system services — every external
boundary (application launching, process probing, AppleScript
invocation, settings persistence, system checks) is injected as a
protocol with a fake implementation used in tests.

To run a single test target directly:

```sh
swift test --filter CameraCoreTests
```

Adding a new test file to an existing `Tests/*Target*` directory is
picked up automatically by SwiftPM — there's no separate list to update.

## Linting

```sh
make lint
```

Builds the package graph and validates
`Resources/PrivacyInfo.xcprivacy`. There is no `osacompile`/AppleScript
linting step anymore for day-to-day development: the two `.scpt` files
under `Packages/AppAutomation` are a documented transitional bridge (see
`docs/ARCHITECTURE.md`) and are expected to change rarely; validate a
`.scpt` edit by hand (e.g. opening it in Script Editor) before
submitting, same as before.

## Style

- Follow strict Swift concurrency: `@MainActor` for UI-facing view
  models, `async`/`await` over completion handlers, and
  `Task.checkCancellation()` in any loop that polls or waits.
- No force-unwraps, `fatalError`, arbitrary `sleep`/`Task.sleep` calls, or
  unbounded polling loops in production code — timeouts and retries are
  bounded and cancellation-aware (see `CameraCore.RetryPolicy`,
  `CameraCore.ApplicationReadiness`).
- New code at an external boundary (process execution, AppleScript,
  system state, persistence) goes behind a protocol with an injectable
  fake, following the existing pattern in `Packages/AppAutomation` and
  `Packages/SystemChecks`.
- Preserve the typed `SelectionError` distinctions
  (`Packages/CameraCore/Sources/CameraCore/SelectionError.swift`) — don't
  fold a new failure mode into an existing case if it's meaningfully
  different, and don't introduce a new generic/catch-all case where a
  specific one already fits.
- Device-name matching is exact after trimming leading/trailing
  whitespace only — never a substring or case-insensitive match; don't
  change this without updating `DeviceNameTests.swift`.
- Match the existing `.editorconfig` settings (2-space indent, LF line
  endings, trimmed trailing whitespace).
- Never automate Teams (or any app's) sign-in, account picker, or any
  part of authentication — see the fixture test that locks this in
  (`TeamsDeviceSelectionAdapterTests.swift`).

## Changelog

If your change is user-facing (a fix, a new feature, a behavior change),
add an entry under `## [Unreleased]` in `CHANGELOG.md`, following the
existing [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) style.
Purely internal changes (refactors, test-only changes) don't need an
entry.

## Commits and pull requests

- Keep commits focused; prefer a short, imperative, Conventional-Commit-style
  summary line (e.g. `fix: report launch timeouts`,
  `feat: add diagnostics camera reset`).
- Describe what changed and why in the PR description, and mention how
  you tested it (`make test`, `make lint`, manual verification on macOS,
  etc.).
- Make sure `make test` and `make lint` pass before requesting review.

## Reporting security issues

Please don't file a public issue for a security vulnerability -- see
[SECURITY.md](SECURITY.md) for how to report one privately.
