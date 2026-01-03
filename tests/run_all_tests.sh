#!/bin/bash

# Master test runner - runs all test suites

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

TOTAL_PASSED=0
TOTAL_FAILED=0

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║         MCP Command-line Tool - Complete Test Suite        ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Run CLI Selection tests
echo "Running: CLI Selection Tests"
echo "─────────────────────────────────────────────────────────────"
if "$SCRIPT_DIR/test_cli_selection.sh" >/dev/null 2>&1; then
	echo -e "${GREEN}✓ CLI Selection tests passed${NC}"
	TOTAL_PASSED=$((TOTAL_PASSED + 1))
else
	echo -e "${RED}✗ CLI Selection tests failed${NC}"
	"$SCRIPT_DIR/test_cli_selection.sh"
	TOTAL_FAILED=$((TOTAL_FAILED + 1))
fi

echo ""

# Run Validation tests
echo "Running: Validation and Edge Cases Tests"
echo "─────────────────────────────────────────────────────────────"
if "$SCRIPT_DIR/test_validation.sh" >/dev/null 2>&1; then
	echo -e "${GREEN}✓ Validation tests passed${NC}"
	TOTAL_PASSED=$((TOTAL_PASSED + 1))
else
	echo -e "${RED}✗ Validation tests failed${NC}"
	"$SCRIPT_DIR/test_validation.sh"
	TOTAL_FAILED=$((TOTAL_FAILED + 1))
fi

echo ""

# Run CLI Differences tests
echo "Running: CLI Differences Tests (Headers, Scope, Transport)"
echo "─────────────────────────────────────────────────────────────"
if "$SCRIPT_DIR/test_cli_differences.sh" >/dev/null 2>&1; then
	echo -e "${GREEN}✓ CLI Differences tests passed${NC}"
	TOTAL_PASSED=$((TOTAL_PASSED + 1))
else
	echo -e "${RED}✗ CLI Differences tests failed${NC}"
	"$SCRIPT_DIR/test_cli_differences.sh"
	TOTAL_FAILED=$((TOTAL_FAILED + 1))
fi

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                      SUMMARY                               ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
TOTAL_SUITES=$((TOTAL_PASSED + TOTAL_FAILED))
echo "Test suites run:    $TOTAL_SUITES"
if [ $TOTAL_FAILED -eq 0 ]; then
	echo -e "Test suites passed: ${GREEN}$TOTAL_PASSED${NC}"
	echo -e "Test suites failed: ${GREEN}0${NC}"
else
	echo -e "Test suites passed: $TOTAL_PASSED"
	echo -e "Test suites failed: ${RED}$TOTAL_FAILED${NC}"
fi
echo ""

if [ $TOTAL_FAILED -eq 0 ]; then
	echo -e "${GREEN}All tests passed!${NC}"
	exit 0
else
	echo -e "${RED}Some tests failed!${NC}"
	exit 1
fi
