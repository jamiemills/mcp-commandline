#!/bin/bash

# Manual validation script for shell scripts and tests
# Run this before pushing changes to ensure code quality

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║           Shell Script Validation and Testing               ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

CHECKS_FAILED=0

# Check if shellcheck is installed
if ! command -v shellcheck &>/dev/null; then
	echo -e "${YELLOW}⚠ shellcheck not found. Skipping shellcheck validation.${NC}"
	echo "  Install with: brew install shellcheck (macOS) or apt install shellcheck (Linux)"
else
	echo "Step 1: Running shellcheck..."
	echo "─────────────────────────────────────────────────────────────"
	if shellcheck "$SCRIPT_DIR/json-to-mcp-add.sh" "$SCRIPT_DIR/tests"/*.sh; then
		echo -e "${GREEN}✓ shellcheck passed${NC}"
	else
		echo -e "${RED}✗ shellcheck failed${NC}"
		CHECKS_FAILED=1
	fi
	echo ""
fi

# Check if shfmt is installed
if ! command -v shfmt &>/dev/null; then
	echo -e "${YELLOW}⚠ shfmt not found. Skipping shfmt validation.${NC}"
	echo "  Install with: brew install shfmt (macOS) or via go install mvdan.cc/sh/v3/cmd/shfmt@latest"
else
	echo "Step 2: Running shfmt..."
	echo "─────────────────────────────────────────────────────────────"
	if shfmt -d "$SCRIPT_DIR/json-to-mcp-add.sh" "$SCRIPT_DIR/tests"/*.sh >/dev/null 2>&1; then
		echo -e "${GREEN}✓ shfmt formatting is correct${NC}"
	else
		echo -e "${RED}✗ shfmt found formatting issues${NC}"
		echo ""
		echo "To fix, run: shfmt -w json-to-mcp-add.sh tests/*.sh"
		echo ""
		CHECKS_FAILED=1
	fi
	echo ""
fi

# Run tests
echo "Step 3: Running test suite..."
echo "─────────────────────────────────────────────────────────────"
if [ -f "$SCRIPT_DIR/tests/run_all_tests.sh" ]; then
	if "$SCRIPT_DIR/tests/run_all_tests.sh"; then
		echo -e "${GREEN}✓ All tests passed${NC}"
	else
		echo -e "${RED}✗ Some tests failed${NC}"
		CHECKS_FAILED=1
	fi
else
	echo -e "${YELLOW}⚠ Test suite not found${NC}"
fi
echo ""

# Summary
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                    VALIDATION SUMMARY                       ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

if [ $CHECKS_FAILED -eq 0 ]; then
	echo -e "${GREEN}✓ All validations passed!${NC}"
	echo ""
	echo "You can safely commit and push your changes."
	echo ""
	exit 0
else
	echo -e "${RED}✗ Some validations failed!${NC}"
	echo ""
	echo "Please fix the issues above before committing."
	echo ""
	exit 1
fi
