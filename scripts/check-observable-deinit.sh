#!/bin/zsh
# check-observable-deinit.sh
# Validates that every @Observable class in the Stori codebase has a protective deinit block.
#
# Background (Issue #112 / ASan Issue #84742+):
#   The @Observable macro + @MainActor + Swift Concurrency creates implicit
#   task-local storage that gets double-freed during object deallocation.
#   An empty `deinit {}` block prevents the crash by ensuring proper cleanup order.
#
# Usage:
#   ./scripts/check-observable-deinit.sh          # Check all Stori/ sources
#   ./scripts/check-observable-deinit.sh --ci      # Exit with non-zero on violations
#
# This script can be integrated as a CI check or Xcode build phase.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SOURCE_DIR="$PROJECT_ROOT/Stori"
CI_MODE=false

if [[ "$1" == "--ci" ]]; then
    CI_MODE=true
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🔍 Checking @Observable classes for protective deinit blocks..."
echo "   Source directory: $SOURCE_DIR"
echo ""

VIOLATIONS=()
TOTAL_OBSERVABLE=0
TOTAL_WITH_DEINIT=0

# Find all Swift files containing @Observable class declarations
while IFS= read -r file; do
    # Extract class names declared with @Observable in this file
    # We look for @Observable on its own line, followed by optional modifiers, then "class ClassName"
    # Using a multi-pass approach for robustness

    # Get line numbers of @Observable annotations
    observable_lines=()
    while IFS=: read -r line_num _content; do
        observable_lines+=("$line_num")
    done < <(grep -nE '^@Observable$|^@Observable ' "$file" 2>/dev/null || true)

    for obs_line in "${observable_lines[@]}"; do
        # Look at the next few lines after @Observable for a class declaration
        class_line=""
        class_name=""
        for offset in 0 1 2 3; do
            target_line=$((obs_line + offset))
            line_content=$(sed -n "${target_line}p" "$file")
            if echo "$line_content" | grep -qE '^\s*(public\s+|private\s+|internal\s+|fileprivate\s+|open\s+)?(final\s+)?class\s+'; then
                class_name=$(echo "$line_content" | sed -E 's/.*class\s+([A-Za-z0-9_]+).*/\1/')
                class_line="$target_line"
                break
            fi
        done

        if [[ -z "$class_name" ]]; then
            continue
        fi

        TOTAL_OBSERVABLE=$((TOTAL_OBSERVABLE + 1))

        # Check if the file contains a deinit block
        # We need to check if THIS class (not another class in the same file) has a deinit
        # Simple heuristic: check if deinit exists anywhere in the file after the class declaration
        has_deinit=false
        if grep -qE 'deinit\s*\{' "$file" 2>/dev/null; then
            # More precise check: find deinit after the class declaration line
            while IFS=: read -r dl _rest; do
                if [[ "$dl" -gt "$class_line" ]]; then
                    has_deinit=true
                    break
                fi
            done < <(grep -nE 'deinit\s*\{' "$file" 2>/dev/null || true)
        fi

        if $has_deinit; then
            TOTAL_WITH_DEINIT=$((TOTAL_WITH_DEINIT + 1))
        else
            relative_path="${file#$PROJECT_ROOT/}"
            VIOLATIONS+=("  ❌ ${class_name} (${relative_path}:${class_line})")
        fi
    done
done < <(find "$SOURCE_DIR" -name "*.swift" -type f)

# Report results
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  @Observable Class Audit Results"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Total @Observable classes found: $TOTAL_OBSERVABLE"
echo "  Classes with protective deinit:  $TOTAL_WITH_DEINIT"
echo "  ${RED}Missing deinit:                 ${#VIOLATIONS[@]}${NC}"
echo ""

if [[ ${#VIOLATIONS[@]} -gt 0 ]]; then
    echo "${RED}⚠️  VIOLATIONS FOUND:${NC}"
    echo ""
    for v in "${VIOLATIONS[@]}"; do
        echo "$v"
    done
    echo ""
    echo "${YELLOW}Fix: Add an empty deinit block to each class:${NC}"
    echo ""
    echo "    // CRITICAL: Protective deinit for @Observable class (ASan Issue #84742+)"
    echo "    // Prevents double-free from implicit Swift Concurrency property change notification tasks"
    echo "    deinit {"
    echo "    }"
    echo ""

    if $CI_MODE; then
        echo "${RED}CI FAILURE: ${#VIOLATIONS[@]} @Observable class(es) missing protective deinit.${NC}"
        exit 1
    fi
else
    echo "${GREEN}✅ All @Observable classes have protective deinit blocks.${NC}"
    echo ""
fi
