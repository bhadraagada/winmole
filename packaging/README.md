# WinMole Package Manager Manifests

This directory contains templates and configurations for publishing WinMole to various Windows package managers.

## Directory Structure

```
packaging/
├── winget/           # WinGet manifests
├── chocolatey/       # Chocolatey package
├── scoop/            # Scoop manifest
└── README.md         # This file
```

## Quick Links

- **Main Release Guide:** [../RELEASE.md](../RELEASE.md)
- **Issue #343:** https://github.com/bhadraagada/winmole/issues/343
- **Build Scripts:** [../scripts/](../scripts/)

## Package Manager Status

| Package Manager | Status | Priority | Documentation |
|----------------|--------|----------|---------------|
| **WinGet** | 🔴 Not Published | High | [winget/README.md](winget/README.md) |
| **Chocolatey** | 🔴 Not Published | High | [chocolatey/README.md](chocolatey/README.md) |
| **Scoop** | 🔴 Not Published | Medium | [scoop/README.md](scoop/README.md) |

## Publishing Order (Recommended)

1. **Create GitHub Release** - Upload ZIP and checksums
2. **Scoop** - Easiest, fastest approval (~3-5 days)
3. **WinGet** - Official Microsoft, widest reach (~1-2 weeks)
4. **Chocolatey** - Popular with devs (~1-2 weeks)

## Prerequisites

- GitHub release with ZIP file uploaded
- SHA256 checksum available
- Version tagged in git (e.g., v1.0.0)

## Getting Started

See [RELEASE.md](../RELEASE.md) for complete instructions on:
- Building release artifacts
- Testing locally
- Submitting to each package manager
- Automation with GitHub Actions
