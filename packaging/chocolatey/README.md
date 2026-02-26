# Chocolatey Package for WinMole

## Quick Submission Guide

### 1. Prerequisites
- Chocolatey account at https://community.chocolatey.org/
- API key from your account settings
- GitHub release with ZIP file

### 2. Update Package Files

**winmole.nuspec:**
- Update `<version>1.0.0</version>`
- Update `<releaseNotes>` URL

**tools/chocolateyinstall.ps1:**
- Update `$version = '1.0.0'`
- Update `$checksum64` with SHA256 from build

**tools/VERIFICATION.txt:**
- Update all v1.0.0 references
- Update checksum

### 3. Build Package Locally

```powershell
# Navigate to chocolatey directory
cd packaging\chocolatey

# Pack the package
choco pack

# This creates: winmole.1.0.0.nupkg
```

### 4. Test Locally

```powershell
# Install from local package
choco install winmole -source . -y

# Test functionality
winmole --version
winmole clean --dry-run

# Uninstall
choco uninstall winmole -y
```

### 5. Publish to Chocolatey

```powershell
# Set API key (one time)
choco apikey --key YOUR_API_KEY --source https://push.chocolatey.org/

# Push package
choco push winmole.1.0.0.nupkg --source https://push.chocolatey.org/

# Package will enter moderation queue
```

## Package Structure

```
chocolatey/
├── winmole.nuspec                 # Package metadata
└── tools/
    ├── chocolateyinstall.ps1      # Installation script
    ├── chocolateyuninstall.ps1    # Uninstallation script
    └── VERIFICATION.txt           # Verification instructions
```

## Moderation Process

1. **Submit**: Push package to Chocolatey
2. **Auto-scan**: Automated virus/malware scan (~5 minutes)
3. **Moderation**: Human review (~1-2 weeks for first package)
4. **Approval**: Package becomes available
5. **Trusted**: After 3+ approved packages, auto-moderation enabled

## Updating for New Releases

When releasing v1.0.1:

1. Update version in 3 files:
   - `winmole.nuspec`: `<version>1.0.1</version>`
   - `tools/chocolateyinstall.ps1`: `$version = '1.0.1'`
   - `tools/VERIFICATION.txt`: All URLs and hash
    
2. Update checksums:
   - Get from `SHA256SUMS.txt`
   - Update in `chocolateyinstall.ps1` and `VERIFICATION.txt`

3. Build and push:
   ```powershell
   choco pack
   choco push winmole.1.0.1.nupkg --source https://push.chocolatey.org/
   ```

## Testing Checklist

Before pushing:

- [ ] Package builds without errors (`choco pack`)
- [ ] Local install works (`choco install winmole -source .`)
- [ ] WinMole commands execute properly
- [ ] PATH is added correctly
- [ ] Uninstall cleans up properly
- [ ] Checksums match GitHub release
- [ ] URLs are correct and accessible

## Common Issues

### "Package rejected - URL not accessible"
- Ensure GitHub release is public
- Test download URL in browser

### "Checksum mismatch"
- Regenerate checksum: `(Get-FileHash winmole-1.0.0-x64.zip).Hash`
- Update both install script and VERIFICATION.txt

### "Install script fails"
- Test locally first
- Check PowerShell syntax: `Test-Path tools\chocolateyinstall.ps1`

## Resources

- **Chocolatey Docs**: https://docs.chocolatey.org/en-us/create/create-packages
- **Package Guidelines**: https://docs.chocolatey.org/en-us/create/create-packages#package-naming-guidelines
- **Moderation Process**: https://docs.chocolatey.org/en-us/community-repository/moderation/
- **Create Account**: https://community.chocolatey.org/account/Register
