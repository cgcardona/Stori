#!/bin/zsh
# check-task-captures.sh
# Detects unsafe Task patterns in @Observable/@MainActor classes that cause
# use-after-free crashes (the REAL root cause of ASan memory bugs).
#
# Checks for:
#   1. Task { } blocks without [weak self] that reference self
#   2. Task { } blocks inside deinit (always a bug)
#
# Usage:
#   ./scripts/check-task-captures.sh          # Check all Stori/ sources
#   ./scripts/check-task-captures.sh --ci     # Exit with non-zero on violations
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
CYAN='\033[0;36m'
NC='\033[0m'

echo "🔍 Checking Task capture patterns for memory safety..."
echo "   Source directory: $SOURCE_DIR"
echo ""

VIOLATIONS=()

# 1. CHECK: Task { } inside deinit (ALWAYS a bug)
# Find files with deinit, then check if any Task { is between deinit { and its closing }
while IFS= read -r file; do
    relative_path="${file#$PROJECT_ROOT/}"
    
    # Skip test files
    [[ "$relative_path" == *Tests* ]] && continue
    
    # Quick check: does file have both deinit and Task?
    if grep -q 'deinit' "$file" && grep -qE 'Task\s*\{|Task\.detached' "$file"; then
        # Parse more carefully: find deinit blocks containing Task
        in_deinit=false
        brace_depth=0
        line_num=0
        while IFS= read -r line; do
            line_num=$((line_num + 1))
            
            if [[ "$in_deinit" == "false" ]] && echo "$line" | grep -qE '^\s*(nonisolated\s+)?deinit\s*\{'; then
                in_deinit=true
                brace_depth=1
                continue
            fi
            
            if [[ "$in_deinit" == "true" ]]; then
                opens="${(S)line//[^\{]/}"
                closes="${(S)line//[^\}]/}"
                brace_depth=$((brace_depth + ${#opens} - ${#closes}))
                
                if echo "$line" | grep -qE 'Task\s*\{|Task\.detached'; then
                    VIOLATIONS+=("  ❌ CRITICAL: Task inside deinit (${relative_path}:${line_num})")
                fi
                
                [[ $brace_depth -le 0 ]] && in_deinit=false
            fi
        done < "$file"
    fi
done < <(find "$SOURCE_DIR" -name "*.swift" -type f)

# 2. CHECK: Task blocks without [weak self] in @Observable/@MainActor classes
# Strategy: Find files with @Observable or @MainActor, then find Task { lines
# that don't have [weak self], and check if self is used nearby
while IFS= read -r file; do
    relative_path="${file#$PROJECT_ROOT/}"
    
    # Skip test files
    [[ "$relative_path" == *Tests* ]] && continue
    
    # Only check @Observable or @MainActor classes
    if ! grep -qE '^@Observable|^@MainActor' "$file" 2>/dev/null; then
        continue
    fi
    
    # Find Task { lines without [weak self]
    while IFS=: read -r line_num line_content; do
        # Skip if line has [weak self]
        if echo "$line_content" | grep -qF '[weak self]'; then
            continue
        fi
        
        # Skip comment lines
        stripped=$(echo "$line_content" | sed 's/^[[:space:]]*//')
        [[ "$stripped" == //* ]] && continue
        
        # Check next ~15 lines for self. or self?. usage
        uses_self=false
        end_line=$((line_num + 15))
        check_block=$(sed -n "${line_num},${end_line}p" "$file" 2>/dev/null)
        if echo "$check_block" | grep -qE 'self\.|self\?\.'; then
            uses_self=true
        fi
        
        if $uses_self; then
            VIOLATIONS+=("  ⚠️  Task without [weak self] accessing self (${relative_path}:${line_num})")
        fi
    done < <(grep -nE 'Task\s*\{|Task\.detached\s*\{' "$file" 2>/dev/null || true)
    
done < <(find "$SOURCE_DIR" -name "*.swift" -type f)

# Report results
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Task Capture Safety Audit Results"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  ${RED}Violations found: ${#VIOLATIONS[@]}${NC}"
echo ""

if [[ ${#VIOLATIONS[@]} -gt 0 ]]; then
    echo "${RED}⚠️  VIOLATIONS FOUND:${NC}"
    echo ""
    for v in "${VIOLATIONS[@]}"; do
        echo "$v"
    done
    echo ""
    echo "${YELLOW}Fix pattern:${NC}"
    echo ""
    echo "    // BEFORE (unsafe — can cause use-after-free):"
    echo "    Task { @MainActor in"
    echo "        self.someMethod()"
    echo "    }"
    echo ""
    echo "    // AFTER (safe):"
    echo "    Task { @MainActor [weak self] in"
    echo "        self?.someMethod()"
    echo "    }"
    echo ""

    if $CI_MODE; then
        echo "${RED}CI FAILURE: ${#VIOLATIONS[@]} unsafe Task capture(s) found.${NC}"
        exit 1
    fi
else
    echo "${GREEN}✅ All Task blocks use safe capture patterns.${NC}"
    echo ""
fi
