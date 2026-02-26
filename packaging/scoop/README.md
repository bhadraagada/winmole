# Scoop Package for WinMole

## Quick Submission Guide

### 1. Prerequisites
- GitHub release created with ZIP file
- SHA256 hash from release build

### 2. Update Manifest
Edit `winmole.json`:
- Update `version` to new version
- Update `url` with correct download URL
- Update `hash` with SHA256 from `SHA256SUMS.txt`

### 3. Submit to Scoop

```powershell
# Fork ScoopInstaller/Main
git clone https://github.com/YOUR_USERNAME/Main scoop-main
cd scoop-main

# Copy manifest
Copy-Item path\to\winmole.json bucket\

# Commit and push
git add bucket/winmole.json
git commit -m "winmole: Add version 1.0.0"
git push

# Create PR on GitHub
# Go to: https://github.com/ScoopInstaller/Main/compare
```

### 4. Test Locally Before Submitting

```powershell
# Add local bucket
scoop bucket add local path\to\packaging\scoop

# Install from local
scoop install local/winmole

# Test
winmole --version
winmole clean --dry-run

# Uninstall
scoop uninstall winmole
```

## Manifest Fields Explained

- **version**: Release version (without 'v' prefix)
- **url**: Direct download URL from GitHub releases
- **hash**: SHA256 hash from build
- **bin**: The main executable/script
- **shortcuts**: Start menu shortcuts
- **checkver**: Auto-detect new versions
- **autoupdate**: Template for auto-updating

## Updating for New Releases

When releasing v1.0.1:

1. Update version: `"version": "1.0.1"`
2. Update URL: `v1.0.0` → `v1.0.1`
3. Update hash: Get from new `SHA256SUMS.txt`
4. Submit PR with title: `winmole: Update to version 1.0.1`

## Resources

- **Scoop Wiki**: https://github.com/ScoopInstaller/Main/wiki
- **Manifest Format**: https://github.com/ScoopInstaller/Scoop/wiki/App-Manifests
- **Contributing**: https://github.com/ScoopInstaller/Main/blob/master/.github/CONTRIBUTING.md
