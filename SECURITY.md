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

Private vulnerability reporting is not currently enabled. Open an issue marked
`SECURITY` without exploit details and ask the maintainer for a private contact.

After the maintainer provides a private channel, include:

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
