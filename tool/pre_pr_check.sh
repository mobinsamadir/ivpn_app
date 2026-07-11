#!/bin/bash
set -e

# 1. Temp Files Guard
echo "Running Temp Files Guard..."
TEMP_FILES=$(find . -type d -name ".git" -prune -o -type f \( -name "*.bak" -o -name "*.bak2" -o -name "dummy*.aar" -o -name "*patch*" ! -name "pre_pr_check.sh" \) -print)

if [ -n "$TEMP_FILES" ]; then
    echo "Error: Found temporary or patch files:"
    echo "$TEMP_FILES"
    exit 1
fi
echo "Temp Files Guard passed."
exit 0