# Security Policy

## Supported Versions

iphone-cam-lite is a small personal-use automation tool — now a native
macOS Swift menu bar app rather than a service with a long-term support
cycle. In practice, security fixes are made against the latest released
version:

| Version | Supported          |
| ------- | ------------------ |
| 0.1.2   | :white_check_mark: |
| 0.1.1   | :x:                 |
| 0.1.0   | :x:                 |

Earlier tagged versions are not maintained. If you're running an older
version, please upgrade to the latest release (or the `dev` branch) before
reporting an issue, in case it has already been fixed. See
[CHANGELOG.md](CHANGELOG.md) for what changed in the unreleased native
Swift rewrite.

## Reporting a Vulnerability

Please do not open a public GitHub issue for a security vulnerability.

Instead, use GitHub's private vulnerability reporting for this repository:
open the **Security** tab on the [iphone-cam-lite repository](https://github.com/bubnicbf/iphone-cam-lite),
then **Report a vulnerability**. This opens a private advisory that only
you and the maintainer can see, and lets you attach details, logs, or
proof-of-concept material without exposing them publicly.

When reporting, please include:

- The version or commit you're running (`git rev-parse HEAD`, or the release
  tag/archive name).
- The platform and macOS version.
- Steps to reproduce, and what you expected vs. what happened.

Before attaching logs, screenshots, or automation output, please redact
anything sensitive that isn't relevant to the report -- for example
Microsoft/Zoom account details or sign-in state, meeting IDs or links,
calendar or contact information visible in a screenshot, and personal
device or computer names.

This project is maintained on a best-effort, volunteer basis. There is no
guaranteed response time or SLA, but reports are read and taken seriously,
and a fix or mitigation will be prioritized once a report is confirmed.
