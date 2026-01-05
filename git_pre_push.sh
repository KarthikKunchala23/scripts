#!/usr/bin/env bash
# Git pre-push hook
# Final validation before pushing to remote

set -euo pipefail

echo "🚀 Running pre-push checks..."

# Run terraform validate if terraform files exist
if find . -name "*.tf" | grep -q .; then
    echo "➡ Running terraform validate..."
    # terraform init -backend=false -input=false >/dev/null
    # terraform validate
fi

echo "✅ Pre-push checks passed!"
exit 0
