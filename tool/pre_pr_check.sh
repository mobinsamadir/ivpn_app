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

# 2. Flutter Analyze
echo "Running Flutter Analyze..."
flutter analyze --no-fatal-infos lib test

# 3. Flutter Unit Tests
echo "Running Flutter Unit Tests..."
flutter test test/

# 4. Kotlin Syntax Warning (Soft-Fail)
echo "Running Kotlin Syntax Warning (Soft-Fail)..."
if curl -sSLO https://github.com/pinterest/ktlint/releases/download/1.3.0/ktlint; then
    chmod a+x ktlint
    # Run ktlint but don't fail the script if it finds issues
    set +e
    ./ktlint "android/**/*.kt"
    KTLINT_EXIT_CODE=$?
    set -e

    if [ $KTLINT_EXIT_CODE -ne 0 ]; then
        echo "::warning::ktlint found issues in legacy Kotlin code. Needs manual fix later."
    fi
else
    echo "::warning::Failed to download ktlint from GitHub Actions."
fi

exit 0
