#!/usr/bin/env bash
# Git pre-commit hook
# Blocks commit if formatting or linting fails

set -euo pipefail

echo "🔍 Running pre-commit checks..."

# Check required tools
require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "❌ Required command '$1' not found"
        exit 1
    }
}

require_cmd terraform
require_cmd shellcheck

# yamllint is optional
if command -v yamllint >/dev/null 2>&1; then
    HAS_YAMLLINT=true
else
    HAS_YAMLLINT=false
    echo "⚠ yamllint not found – skipping YAML lint"
fi

########################################
# Terraform formatting
########################################
if ls *.tf >/dev/null 2>&1 || find . -name "*.tf" | grep -q .; then
    echo "➡ Running terraform fmt..."
    terraform fmt -recursive
fi

########################################
# Terraform validation
########################################
if ls *.tf >/dev/null 2>&1 || find . -name "*.tf" | grep -q .; then
    echo "➡ Running terraform validate..."
    terraform init -backend=false -input=false >/dev/null
    terraform validate
fi

########################################
# Shellcheck
########################################
SHELL_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.sh$' || true)
if [[ -n "$SHELL_FILES" ]]; then
    echo "➡ Running shellcheck..."
    shellcheck $SHELL_FILES
fi

########################################
# YAML lint
########################################
if [[ "$HAS_YAMLLINT" == "true" ]]; then
    YAML_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.(yml|yaml)$' || true)
    if [[ -n "$YAML_FILES" ]]; then
        echo "➡ Running yamllint..."
        yamllint $YAML_FILES
    fi
fi

echo "✅ Pre-commit checks passed!"
exit 0
