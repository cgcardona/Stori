#!/bin/zsh
# check-observable-deinit.sh
# Validates that classes with implicit Swift Concurrency tasks have protective deinit blocks.
#
# Background (Issue #112 / ASan Issue #84742+):
#   Classes with Swift Concurrency usage create implicit task-local storage that gets
#   double-freed during object deallocation. An empty `deinit {}` block prevents the
#   crash by ensuring proper cleanup order.
#
# Checks for:
#   1. @Observable classes (have implicit property change notification tasks)
#   2. @MainActor classes (have implicit actor isolation tasks)
#   3. Classes with Task { } blocks (explicit concurrency)
#   4. Classes with @Observable properties (inherit implicit tasks from property)
#   5. actor types (implicit actor isolation)
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
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo "🔍 Checking classes with Swift Concurrency for protective deinit blocks..."
echo "   Source directory: $SOURCE_DIR"
echo ""

VIOLATIONS=()
TOTAL_CHECKED=0
TOTAL_WITH_DEINIT=0

# Category counts
OBSERVABLE_COUNT=0
MAINACTOR_COUNT=0
TASK_COUNT=0
ACTOR_COUNT=0

# Helper function to check if a class has deinit after given line number
has_deinit_after_line() {
    local file=$1
    local class_line=$2
    
    if grep -qE 'deinit\s*\{' "$file" 2>/dev/null; then
        while IFS=: read -r dl _rest; do
            if [[ "$dl" -gt "$class_line" ]]; then
                return 0  # Found deinit
            fi
        done < <(grep -nE 'deinit\s*\{' "$file" 2>/dev/null || true)
    fi
    return 1  # No deinit found
}

# Helper function to check if class has Task blocks
has_task_blocks() {
    local file=$1
    local class_start=$2
    
    # Look for Task { patterns after class declaration
    # This is a heuristic - checks if file contains Task after class line
    if tail -n +$class_start "$file" | grep -qE 'Task\s*\{|Task\s*<|Task\.detached'; then
        return 0
    fi
    return 1
}

# Track checked classes to avoid duplicates (zsh associative array)
typeset -A checked_classes

# Process all Swift files
while IFS= read -r file; do
    relative_path="${file#$PROJECT_ROOT/}"
    
    # 1. CHECK @Observable CLASSES
    observable_lines=()
    while IFS=: read -r line_num _content; do
        observable_lines+=("$line_num")
    done < <(grep -nE '^@Observable$|^@Observable ' "$file" 2>/dev/null || true)

    for obs_line in "${observable_lines[@]}"; do
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

        if [[ -z "$class_name" ]] || [[ -n "${checked_classes[$file:$class_name]}" ]]; then
            continue
        fi

        checked_classes[$file:$class_name]=1
        TOTAL_CHECKED=$((TOTAL_CHECKED + 1))
        OBSERVABLE_COUNT=$((OBSERVABLE_COUNT + 1))

        if has_deinit_after_line "$file" "$class_line"; then
            TOTAL_WITH_DEINIT=$((TOTAL_WITH_DEINIT + 1))
        else
            VIOLATIONS+=("  ❌ ${class_name} [@Observable] (${relative_path}:${class_line})")
        fi
    done
    
    # 2. CHECK @MainActor CLASSES (without @Observable - those are already caught)
    mainactor_lines=()
    while IFS=: read -r line_num _content; do
        # Check if this @MainActor is NOT preceded by @Observable on previous lines
        is_observable=false
        for ((i=line_num-3; i<line_num; i++)); do
            if [[ $i -gt 0 ]]; then
                prev_line=$(sed -n "${i}p" "$file")
                if echo "$prev_line" | grep -qE '^@Observable$|^@Observable '; then
                    is_observable=true
                    break
                fi
            fi
        done
        
        if ! $is_observable; then
            mainactor_lines+=("$line_num")
        fi
    done < <(grep -nE '^@MainActor$|^@MainActor ' "$file" 2>/dev/null || true)

    for ma_line in "${mainactor_lines[@]}"; do
        class_line=""
        class_name=""
        for offset in 0 1 2 3; do
            target_line=$((ma_line + offset))
            line_content=$(sed -n "${target_line}p" "$file")
            if echo "$line_content" | grep -qE '^\s*(public\s+|private\s+|internal\s+|fileprivate\s+|open\s+)?(final\s+)?class\s+'; then
                class_name=$(echo "$line_content" | sed -E 's/.*class\s+([A-Za-z0-9_]+).*/\1/')
                class_line="$target_line"
                break
            fi
        done

        if [[ -z "$class_name" ]] || [[ -n "${checked_classes[$file:$class_name]}" ]]; then
            continue
        fi

        checked_classes[$file:$class_name]=1
        TOTAL_CHECKED=$((TOTAL_CHECKED + 1))
        MAINACTOR_COUNT=$((MAINACTOR_COUNT + 1))

        if has_deinit_after_line "$file" "$class_line"; then
            TOTAL_WITH_DEINIT=$((TOTAL_WITH_DEINIT + 1))
        else
            VIOLATIONS+=("  ❌ ${class_name} [@MainActor] (${relative_path}:${class_line})")
        fi
    done
    
    # 3. CHECK CLASSES WITH Task BLOCKS
    class_lines=()
    while IFS=: read -r line_num line_content; do
        if echo "$line_content" | grep -qE '^\s*(public\s+|private\s+|internal\s+|fileprivate\s+|open\s+)?(final\s+)?class\s+'; then
            class_name=$(echo "$line_content" | sed -E 's/.*class\s+([A-Za-z0-9_]+).*/\1/')
            if [[ -n "$class_name" ]] && [[ -z "${checked_classes[$file:$class_name]}" ]]; then
                class_lines+=("$line_num:$class_name")
            fi
        fi
    done < <(grep -nE '^\s*(public\s+|private\s+|internal\s+|fileprivate\s+|open\s+)?(final\s+)?class\s+' "$file" 2>/dev/null || true)
    
    for class_info in "${class_lines[@]}"; do
        class_line="${class_info%%:*}"
        class_name="${class_info##*:}"
        
        if has_task_blocks "$file" "$class_line"; then
            checked_classes[$file:$class_name]=1
            TOTAL_CHECKED=$((TOTAL_CHECKED + 1))
            TASK_COUNT=$((TASK_COUNT + 1))

            if has_deinit_after_line "$file" "$class_line"; then
                TOTAL_WITH_DEINIT=$((TOTAL_WITH_DEINIT + 1))
            else
                VIOLATIONS+=("  ❌ ${class_name} [Task{}] (${relative_path}:${class_line})")
            fi
        fi
    done
    
    # 4. CHECK ACTOR TYPES
    actor_lines=()
    while IFS=: read -r line_num line_content; do
        actor_name=$(echo "$line_content" | sed -E 's/.*actor\s+([A-Za-z0-9_]+).*/\1/')
        if [[ -n "$actor_name" ]] && [[ -z "${checked_classes[$file:$actor_name]}" ]]; then
            actor_lines+=("$line_num:$actor_name")
        fi
    done < <(grep -nE '^\s*(public\s+|private\s+|internal\s+|fileprivate\s+|open\s+)?actor\s+' "$file" 2>/dev/null || true)
    
    for actor_info in "${actor_lines[@]}"; do
        actor_line="${actor_info%%:*}"
        actor_name="${actor_info##*:}"
        
        checked_classes[$file:$actor_name]=1
        TOTAL_CHECKED=$((TOTAL_CHECKED + 1))
        ACTOR_COUNT=$((ACTOR_COUNT + 1))

        if has_deinit_after_line "$file" "$actor_line"; then
            TOTAL_WITH_DEINIT=$((TOTAL_WITH_DEINIT + 1))
        else
            VIOLATIONS+=("  ❌ ${actor_name} [actor] (${relative_path}:${actor_line})")
        fi
    done
    
done < <(find "$SOURCE_DIR" -name "*.swift" -type f)

# Report results
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Swift Concurrency Deinit Audit Results"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  ${CYAN}Checked by category:${NC}"
echo "    - @Observable classes:      $OBSERVABLE_COUNT"
echo "    - @MainActor classes:       $MAINACTOR_COUNT"
echo "    - Classes with Task blocks: $TASK_COUNT"
echo "    - actor types:              $ACTOR_COUNT"
echo ""
echo "  Total classes checked:          $TOTAL_CHECKED"
echo "  Classes with protective deinit: $TOTAL_WITH_DEINIT"
echo "  ${RED}Missing deinit:                 ${#VIOLATIONS[@]}${NC}"
echo ""

if [[ ${#VIOLATIONS[@]} -gt 0 ]]; then
    echo "${RED}⚠️  VIOLATIONS FOUND:${NC}"
    echo ""
    for v in "${VIOLATIONS[@]}"; do
        echo "$v"
    done
    echo ""
    echo "${YELLOW}Fix: Add a protective deinit block to each class:${NC}"
    echo ""
    echo "    // CRITICAL: Protective deinit for Swift Concurrency class (ASan Issue #84742+)"
    echo "    // Root cause: @Observable/@MainActor/Task creates implicit task-local storage"
    echo "    // that gets double-freed during deallocation. Empty deinit ensures proper cleanup."
    echo "    deinit {"
    echo "    }"
    echo ""
    echo "${CYAN}Why this matters:${NC}"
    echo "  - @Observable classes have implicit property change notification tasks"
    echo "  - @MainActor classes have implicit actor isolation mechanisms"  
    echo "  - Classes with Task {} create explicit concurrency contexts"
    echo "  - actor types have implicit actor isolation"
    echo "  All of these can cause double-free crashes without protective deinit."
    echo ""

    if $CI_MODE; then
        echo "${RED}CI FAILURE: ${#VIOLATIONS[@]} class(es) with Swift Concurrency missing protective deinit.${NC}"
        exit 1
    fi
else
    echo "${GREEN}✅ All classes with Swift Concurrency have protective deinit blocks.${NC}"
    echo ""
fi
