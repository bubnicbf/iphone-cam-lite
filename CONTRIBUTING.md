# Contributing to iphone-cam-lite

Thanks for considering a contribution. This project is a small collection
of macOS shell scripts and AppleScript files, so the workflow is
intentionally lightweight.

## Prerequisites

- macOS (the launchers, AppleScript automation, and `osacompile`/`osascript`
  syntax checks are all macOS-only).
- Bash (the scripts target the `bash` that ships with macOS; avoid
  bash-4+-only features such as associative arrays or `mapfile`).
- Xcode Command Line Tools, for `osacompile`/`osascript` (`xcode-select --install`).

## Getting set up

```sh
git clone git@github.com:bubnicbf/iphone-cam-lite.git
cd iphone-cam-lite
git checkout dev
make setup
```

`make setup` makes the scripts executable and runs `scripts/check_prereqs.sh`
to confirm your Mac has what it needs.

## Branching

Base new work on `dev`, not `main` -- `dev` is the active integration
branch. Name branches by the kind of change they make:

- `bug/<short-description>` for bug fixes
- `feature/<short-description>` for new functionality
- `chore/<short-description>` for tooling, docs, tests, and other
  non-user-facing maintenance

Open pull requests against `dev`.

## Running the tests

```sh
make test
```

This runs every `scripts/test_*.sh` file via `tests/run.sh`. The test suite
is entirely mocked/synthetic: it never launches Zoom or Teams, never
changes your actual camera/microphone selection, and never restarts real
system services. Scripts under test are exercised against `PATH`-injected
mock commands and temporary directories, not your live system.

To run a single test directly:

```sh
./scripts/test_launcher_failures.sh
```

Adding a new `scripts/test_*.sh` file is picked up automatically by
`tests/run.sh` -- there's no separate list to update.

## Linting

```sh
make lint
```

This runs `bash -n` over every shell script (syntax-only, no execution) and,
on macOS with the Command Line Tools installed, compiles each `.scpt` file
with `osacompile` into a throwaway temporary location to confirm it's
syntactically valid AppleScript. If `osacompile` isn't available, linting
reports that AppleScript validation was skipped rather than failing --
please still validate `.scpt` changes by hand (e.g. by opening them in
Script Editor) before submitting.

## Style

- Shell scripts start with `set -euo pipefail` and should stay compatible
  with macOS's built-in `bash`.
- Use `scripts/test_reset_camera_services.sh` or `scripts/test_launcher_failures.sh`
  as a model for new tests: mock external commands via a temporary `PATH`
  entry rather than calling real system commands or launching real apps.
- Match the existing `.editorconfig` settings (2-space indent, LF line
  endings, trimmed trailing whitespace) -- except in Makefiles, where recipe
  lines must keep literal tab indentation.
- AppleScript changes should keep user-facing failures actionable (a
  specific, distinct message per failure case) rather than folding
  different failure modes into one generic error.

## Changelog

If your change is user-facing (a fix, a new feature, a behavior change),
add an entry under `## [Unreleased]` in `CHANGELOG.md`, following the
existing [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) style.
Purely internal changes (refactors, test-only changes) don't need an entry.

## Commits and pull requests

- Keep commits focused; prefer a short, imperative summary line (e.g.
  `fix: report launch timeouts`).
- Describe what changed and why in the PR description, and mention how you
  tested it (`make test`, `make lint`, manual verification on macOS, etc.).
- Make sure `make test` and `make lint` pass before requesting review.

## Reporting security issues

Please don't file a public issue for a security vulnerability -- see
[SECURITY.md](SECURITY.md) for how to report one privately.
