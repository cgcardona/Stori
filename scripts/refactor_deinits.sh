#!/bin/zsh
# Batch refactor all deinit blocks to DAW-grade standards
set -e

echo "🔍 Finding all files with empty or protective deinits..."

# Pattern 1: Empty deinit blocks (just delete them)
echo "\n📋 Pattern 1: Empty deinit blocks"
rg -l "deinit \{\s*\}" Stori/ --type swift | while read file; do
    echo "  - $file"
done

# Pattern 2: Protective deinit with folklore (delete the whole deinit)
echo "\n📋 Pattern 2: Protective deinit with folklore"
rg -l "CRITICAL.*Protective deinit.*@Observable.*@MainActor" Stori/ --type swift | while read file; do
    echo "  - $file"
done

# Pattern 3: Has Task cancellation (needs CancellationBag refactor)
echo "\n📋 Pattern 3: Manual task cancellation (needs CancellationBag)"
rg -l "deinit \{.*Task.*cancel" Stori/ --type swift | while read file; do
    echo "  - $file"
done

echo "\n✅ Audit complete. Run with APPLY=1 to apply changes."

if [[ "$APPLY" == "1" ]]; then
    echo "\n🔧 Applying refactors..."
    # Implementation would go here
    echo "⚠️  Manual review required - patterns are too complex for automatic refactoring"
fi
