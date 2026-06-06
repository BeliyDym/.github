#!/usr/bin/env bash
#
# verify_ai_review_caller.sh — validate a CONSUMING repo's ai-review.yml caller.
#
# A caller is the thin per-repo workflow that delegates PR review to the
# centralized reusable OpenRouter workflow. It does NOT contain the OpenRouter
# endpoint / bearer / response-extraction logic — that lives once in the
# reusable implementation (BeliyDym/.github/.github/workflows/ai-review.yml@v2),
# which is validated separately by verify_ai_review_openrouter.sh.
#
# This caller-side check asserts the wiring is correct:
#   - pins the reusable workflow at BeliyDym/.github/.github/workflows/ai-review.yml@<ref>
#   - passes the OPENROUTER_API_KEY secret through
#   - contains NO direct-Anthropic API call (the drift OST-647 removed)
#
# Usage:
#   scripts/verify_ai_review_caller.sh <caller-workflow-file>
#
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <caller-workflow-file>" >&2
  exit 2
fi

workflow="$1"

if [ ! -f "$workflow" ]; then
  echo "error: not a file: $workflow" >&2
  exit 2
fi

require_present() {
  local pattern="$1"
  local label="$2"
  if ! grep -Eq "$pattern" "$workflow"; then
    echo "missing: $label" >&2
    exit 1
  fi
}

require_absent() {
  local pattern="$1"
  local label="$2"
  if grep -Eq "$pattern" "$workflow"; then
    echo "stale reference: $label" >&2
    exit 1
  fi
}

# Wiring to the centralized reusable OpenRouter lane.
require_present 'uses:[[:space:]]*BeliyDym/\.github/\.github/workflows/ai-review\.yml@' 'reusable ai-review.yml @ref pin'
require_present 'OPENROUTER_API_KEY' 'OPENROUTER_API_KEY secret pass-through'

# No direct-Anthropic drift in the caller.
require_absent 'api\.anthropic\.com' 'direct Anthropic API endpoint'
require_absent 'anthropic-version' 'Anthropic API version header'
require_absent 'x-api-key' 'Anthropic x-api-key auth header'

echo "OK: $workflow is a valid OpenRouter ai-review caller."
