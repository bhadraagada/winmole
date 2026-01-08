## Pull Request

### Description

Brief description of what this PR does.

### Type of Change

- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature (non-breaking change that adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Documentation update
- [ ] Refactoring (no functional changes)
- [ ] CI/CD changes

### Related Issues

Fixes #(issue number)

### Changes Made

- Change 1
- Change 2
- Change 3

### Testing

Describe the tests you ran to verify your changes:

- [ ] Ran `Invoke-Pester -Path .\tests\` and all tests pass
- [ ] Tested with `-DryRun` to verify behavior
- [ ] Tested on Windows 10/11
- [ ] Manual testing performed

### Screenshots (if applicable)

Add screenshots to help explain your changes.

### Checklist

- [ ] My code follows the project's code style (see CONTRIBUTING.md)
- [ ] I have performed a self-review of my code
- [ ] I have commented my code, particularly in hard-to-understand areas
- [ ] I have updated the documentation (if needed)
- [ ] My changes generate no new warnings
- [ ] I have added tests that prove my fix is effective or that my feature works
- [ ] New and existing tests pass locally with my changes
- [ ] I have checked that this PR does not introduce security vulnerabilities

### Safety Checklist (for cleanup/deletion features)

- [ ] Uses `Remove-SafeItem` or other safe helpers (not raw `Remove-Item`)
- [ ] Respects `Test-ProtectedPath` for system directories
- [ ] Tested with `-WhatIf` or `-DryRun` first
- [ ] Does not affect user documents, photos, or personal files
