#!/bin/zsh
# check-observable-deinit.sh
# Ensures every @Observable or @MainActor class has a nonisolated deinit {}
# to avoid Swift Concurrency task-local bad-free (ASan) when the runtime
# deinits the object on the MainActor executor.
#
# Rule: If a class is attributed with @Observable or @MainActor, it must
# declare "nonisolated deinit {}" (empty or with body) in the same file.
#
# Accuracy:
#   - Only considers .swift files under Stori/ that contain @Observable or @MainActor
#     and at least one "class" declaration.
#   - In those files, counts every class (top-level and nested), because any class
#     can be deinit'd in a MainActor context when owned (transitively) by an
#     @Observable/@MainActor type (e.g. RenderVoice inside OfflineMIDIRenderer).
#   - Counts any line containing "nonisolated deinit" in the file.
#   - Reports a file when (total class count) > (nonisolated deinit count).
#
# Usage:
#   ./scripts/check-observable-deinit.sh          # Report files missing deinit
#   ./scripts/check-observable-deinit.sh --ci     # Exit 1 if any missing (for CI)
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SOURCE_DIR="$PROJECT_ROOT/Stori"
CI_MODE=false

if [[ "$1" == "--ci" ]]; then
    CI_MODE=true
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "🔍 Checking @Observable / @MainActor classes for nonisolated deinit..."
echo "   Source: $SOURCE_DIR"
echo ""

# Use awk for fast per-file parsing: count all classes (top-level and nested) and list names.
# In files that contain @Observable or @MainActor, every class can be deinit'd in a MainActor
# context (e.g. nested class inside a non-observable type that is owned by an observable type).
# So we count every "class Name" in such files and require one nonisolated deinit per class.
count_observable_classes() {
    awk '
    /^[[:space:]]*(private|fileprivate|internal|public)?[[:space:]]*(final[[:space:]]+)?class[[:space:]]+[A-Za-z0-9_]+/ {
        count++
        n = split($0, a, /class[[:space:]]+/)
        if (n >= 2) { split(a[2], b, /[[:space:]\{:\(]/); if (b[1] != "") names[count] = b[1] }
    }
    END {
        printf "%d", count
        for (i = 1; i <= count; i++) if (names[i] != "") printf "\t%s", names[i]
        printf "\n"
    }
    ' "$1"
}

MISSING=()
while IFS= read -r file; do
    relative_path="${file#$PROJECT_ROOT/}"
    [[ "$relative_path" == *Tests* ]] && continue
    [[ "$relative_path" == *StoriTests* ]] && continue

    # Only files that have @Observable or @MainActor and a class
    grep -qE '@Observable|@MainActor' "$file" 2>/dev/null || continue
    grep -qE '^[[:space:]]*(final[[:space:]]+)?class[[:space:]]+[A-Za-z0-9_]+' "$file" 2>/dev/null || continue

    result=$(count_observable_classes "$file")
    observable_classes=$(echo "$result" | cut -f1 -d$'\t' | tr -d '\n\r' | tr -cd '0-9')
    [[ -z "$observable_classes" ]] && observable_classes=0
    class_names=("${(f)$(echo "$result" | cut -f2- | tr '\t' '\n')}")
    deinit_count=$(grep -c 'nonisolated deinit' "$file" 2>/dev/null || true)
    [[ -z "$deinit_count" ]] || [[ "$deinit_count" != <-> ]] && deinit_count=0

    if (( observable_classes > deinit_count )); then
        missing_count=$((observable_classes - deinit_count))
        names_str=""
        [[ ${#class_names[@]} -gt 0 ]] && names_str=" (e.g. ${class_names[*]})"
        MISSING+=("  ${relative_path}: ${missing_count} class(es) missing nonisolated deinit${names_str}")
    fi
done < <(find "$SOURCE_DIR" -name "*.swift" -type f)

# Report
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  @Observable / @MainActor → nonisolated deinit audit"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  ${RED}Files with missing deinit: ${#MISSING[@]}${NC}"
echo ""

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "${YELLOW}⚠️  FILES NEEDING nonisolated deinit:${NC}"
    echo ""
    for m in "${MISSING[@]}"; do
        echo "$m"
    done
    echo ""
    echo "${CYAN}Fix: Add the following inside each @Observable / @MainActor class:${NC}"
    echo ""
    echo "    /// Run deinit off the executor to avoid Swift Concurrency task-local bad-free (ASan) when"
    echo "    /// the runtime deinits this object on MainActor/task-local context."
    echo "    nonisolated deinit {}"
    echo ""

    if $CI_MODE; then
        echo "${RED}CI FAILURE: ${#MISSING[@]} file(s) with @Observable/@MainActor class(es) missing nonisolated deinit.${NC}"
        exit 1
    fi
else
    echo "${GREEN}✅ All @Observable / @MainActor classes have nonisolated deinit.${NC}"
    echo ""
fi
