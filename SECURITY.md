# Security Policy

## Supported Versions

We currently provide security updates for the latest release branch.

| Version | Supported |
| ------- | --------- |
| main    | yes       |
| older   | no        |

## Reporting a Vulnerability

Please do not open public issues for security vulnerabilities.

Use one of these channels:

1. GitHub Security Advisories (preferred): open a private vulnerability report in this repository.
2. If private advisories are unavailable, open an issue and clearly mark it as `SECURITY` with minimal exploit detail, then we will follow up privately.

When reporting, include:

- A clear description of the vulnerability
- Steps to reproduce
- Impact assessment
- Affected files/commands
- Suggested fix (optional)

## Response Timeline

- Initial acknowledgment: within 72 hours
- Triage decision: within 7 days
- Fix target: as soon as practical based on severity

## Scope

Security-sensitive areas in WinMole include:

- Path validation and safe deletion helpers in `lib/core/file_ops.ps1`
- Protected path checks in `lib/core/base.ps1`
- Cleanup commands in `bin/*.ps1`
- Any operation that can delete files or require elevated privileges

## Safe Disclosure

Please avoid publishing proof-of-concept exploits before a fix is available.
We appreciate responsible disclosure and will credit reporters who want public acknowledgment.
