# Security Policy

## Supported Versions

Security updates are provided for the most recent release and for `master`.

| Version          | Supported |
| ---------------- | --------- |
| `master`         | yes       |
| v0.1.1 (current) | yes       |
| older tags       | no        |

WinMole deletes files and, for some operations, runs with administrator rights,
so the areas most worth scrutiny are `lib/core/file_ops.ps1`, the protected-path
checks in `lib/core/base.ps1`, and the delete path in `cmd/analyze`. Reports
about a path that should be protected but is not are especially welcome.

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
