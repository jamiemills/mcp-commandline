# Validation Setup - Automated Shell Script Quality Checks

This project includes automated validation to ensure code quality using **shellcheck** and **shfmt** on every shell script change.

## Overview

Three layers of validation are in place:

1. **Pre-commit Hook** - Runs locally before each commit
2. **Manual Validation Script** - Run before pushing changes
3. **CI/CD Pipeline** - Automated validation on GitHub (GitHub Actions)

## How It Works

### Layer 1: Git Pre-commit Hook

**Location:** `.git/hooks/pre-commit`

The pre-commit hook automatically runs whenever you attempt to commit shell script changes. It prevents commits that fail validation.

**Automatically checks:**
- All staged `.sh` files with `shellcheck`
- All staged `.sh` files with `shfmt`

**What happens:**
1. You make changes to shell scripts
2. You stage changes: `git add json-to-mcp-add.sh`
3. You attempt to commit: `git commit -m "..."`
4. Hook runs automatically:
   - ✅ If checks pass → commit succeeds
   - ❌ If checks fail → commit is blocked with error message

**Example:**
```bash
$ git commit -m "Fix bug in script"

Running shell script validation...
─────────────────────────────────────────────
Running shellcheck...
✓ shellcheck passed: json-to-mcp-add.sh
✓ shellcheck passed: tests/test_cli_selection.sh
✓ shellcheck passed: tests/test_validation.sh

Running shfmt...
✓ shfmt passed: json-to-mcp-add.sh
✓ shfmt passed: tests/test_cli_selection.sh
✓ shfmt passed: tests/test_validation.sh
─────────────────────────────────────────────
All shell script validations passed!
```

### Layer 2: Manual Validation Script

**Location:** `./validate.sh`

Run this script before pushing to ensure everything passes validation:

```bash
./validate.sh
```

**What it does:**
1. Runs `shellcheck` on all shell scripts
2. Runs `shfmt` to check formatting
3. Runs the complete test suite
4. Provides a comprehensive report

**Output:**
```
╔════════════════════════════════════════════════════════════╗
║           Shell Script Validation and Testing               ║
╚════════════════════════════════════════════════════════════╝

Step 1: Running shellcheck...
✓ shellcheck passed

Step 2: Running shfmt...
✓ shfmt formatting is correct

Step 3: Running test suite...
✓ All tests passed

╔════════════════════════════════════════════════════════════╗
║                    VALIDATION SUMMARY                       ║
╚════════════════════════════════════════════════════════════╝

✓ All validations passed!

You can safely commit and push your changes.
```

### Layer 3: CI/CD Pipeline (GitHub Actions)

**Location:** `.github/workflows/validate.yml`

Automated validation runs on every push and pull request.

**Jobs:**
1. **ShellCheck** - Validates with shellcheck
2. **ShellFmt** - Checks formatting with shfmt
3. **Tests** - Runs full test suite (depends on shellcheck and shfmt passing)

**When it runs:**
- Every push to `main` or `develop` branch
- Every pull request to `main` or `develop` branch
- Only runs if shell scripts (`.sh` files) changed

**Status:** Shows in pull requests and commit history

## Installation & Setup

### Requirements

- **shellcheck** - Shell script static analysis
  ```bash
  # macOS
  brew install shellcheck

  # Ubuntu/Debian
  sudo apt-get install shellcheck

  # Other
  https://www.shellcheck.net/
  ```

- **shfmt** - Shell script formatter
  ```bash
  # macOS
  brew install shfmt

  # Ubuntu/Debian (via golang)
  go install mvdan.cc/sh/v3/cmd/shfmt@latest

  # Other
  https://github.com/mvdan/sh
  ```

- **jq** - For running tests
  ```bash
  # macOS
  brew install jq

  # Ubuntu/Debian
  sudo apt-get install jq
  ```

### Enable Pre-commit Hook

The pre-commit hook should be automatically executable. If it's not:

```bash
chmod +x .git/hooks/pre-commit
```

To disable the hook temporarily (not recommended):

```bash
git commit --no-verify
```

To permanently disable:

```bash
rm .git/hooks/pre-commit
```

## Common Workflows

### Development Workflow

```bash
# 1. Make changes to shell scripts
nano json-to-mcp-add.sh

# 2. Validate before committing (optional, hook will run)
./validate.sh

# 3. Stage and commit
git add json-to-mcp-add.sh
git commit -m "Fix: improve validation logic"

# 4. Pre-commit hook runs automatically
#    If validation fails, commit is blocked and you get error messages

# 5. Fix issues if needed
./validate.sh  # See all issues
shfmt -w json-to-mcp-add.sh  # Auto-fix formatting
shellcheck json-to-mcp-add.sh  # Check for remaining issues

# 6. Stage fixed files and retry
git add json-to-mcp-add.sh
git commit -m "Fix: improve validation logic"

# 7. Push to remote (CI/CD will run additional checks)
git push origin main
```

### Before Pushing (Recommended)

```bash
# Run full validation
./validate.sh

# If all pass, you're ready to push
git push origin main
```

### What to Do If Validation Fails

**Shellcheck errors:**
```bash
# See the errors
shellcheck json-to-mcp-add.sh

# Most errors require manual fixes based on the warnings
# Visit https://www.shellcheck.net/wiki/ for explanations
```

**Shfmt formatting issues:**
```bash
# Auto-fix formatting
shfmt -w json-to-mcp-add.sh tests/*.sh

# Then stage and commit
git add -A
git commit -m "Format: apply shfmt formatting"
```

**Test failures:**
```bash
# Run tests to see what failed
./tests/run_all_tests.sh

# Or individual suite
./tests/test_cli_selection.sh
./tests/test_validation.sh

# Fix the issues and re-run
```

## Checking Validation Status

### Local Status
```bash
# Check all scripts
shellcheck json-to-mcp-add.sh tests/*.sh

# Check formatting
shfmt -d json-to-mcp-add.sh tests/*.sh

# Run tests
./tests/run_all_tests.sh

# Run everything at once
./validate.sh
```

### CI/CD Status
View validation results in GitHub:
1. Go to **Pull Request** or **Commit**
2. Scroll to **Checks** section
3. Click on job names to see details

## Files Changed By Validators

### Shellcheck
- Read-only (identifies issues, doesn't modify)
- You must fix issues manually

### Shfmt
- Can modify files with `shfmt -w`
- You must commit the formatted files

### Tests
- Read-only (doesn't modify source files)
- May create temporary test directories (automatically cleaned up)

## Troubleshooting

### "shellcheck: command not found"
Install shellcheck:
```bash
brew install shellcheck  # macOS
sudo apt-get install shellcheck  # Linux
```

### "shfmt: command not found"
Install shfmt:
```bash
brew install shfmt  # macOS
go install mvdan.cc/sh/v3/cmd/shfmt@latest  # Linux/other
```

### Pre-commit hook not running
1. Verify it's executable: `ls -l .git/hooks/pre-commit`
2. Make executable if needed: `chmod +x .git/hooks/pre-commit`
3. Verify git is configured: `git config --list | grep hook`

### Can't commit despite passing validation locally
1. Run `./validate.sh` to double-check
2. Check if you're committing only shell script changes
3. The hook only checks staged files - ensure your changes are staged

### Want to bypass hook temporarily
```bash
git commit --no-verify -m "message"
```

⚠️ **Note:** This bypasses validation. Use sparingly and only if you have a good reason.

## See Also

- `TESTING.md` - Test suite documentation
- `TEST_REPORT.md` - Detailed test results
- `.github/workflows/validate.yml` - CI/CD configuration
- `.git/hooks/pre-commit` - Pre-commit hook implementation
