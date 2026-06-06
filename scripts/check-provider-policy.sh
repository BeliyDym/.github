#!/usr/bin/env bash
#
# check-provider-policy.sh — fleet AI-provider policy guard.
#
# Policy (established in OST-647, triaged in OST-706):
#   PR-review across the BeliyDym fleet is standardized on the centralized
#   reusable OpenRouter workflow:
#       BeliyDym/.github/.github/workflows/ai-review.yml@v2
#   Direct-provider (Anthropic) API calls in a PR-review workflow are FORBIDDEN —
#   they re-introduce the provider drift that OST-647 removed.
#
#   The ONE allowed place for native-provider secrets is a workflow whose
#   subject under test is the native provider CLI/adapter itself (e.g.
#   agent-orchestrator's integration-tests.yml, which exercises the
#   agent-claude-code / agent-codex / agent-aider / agent-opencode adapters).
#   Such a workflow MUST carry an explicit approved-exception marker so the
#   guard can tell a documented exception apart from undocumented drift.
#
# What this script does:
#   1. Walks every *.yml / *.yaml under the given workflows directory.
#   2. Flags any workflow that makes a DIRECT-Anthropic API call
#      (api.anthropic.com, anthropic-version, or x-api-key + ANTHROPIC_API_KEY)
#      UNLESS that workflow carries the approved-exception marker.
#   3. Exits non-zero and lists every violation; exits zero when clean.
#
# It deliberately does NOT forbid the mere string "ANTHROPIC_API_KEY":
# an approved integration-test workflow legitimately passes that secret. The
# forbidden thing is a direct Anthropic *API call* in a workflow that is not a
# documented native-provider test.
#
# Usage:
#   scripts/check-provider-policy.sh <workflows-dir> [<workflows-dir> ...]
#
# Example:
#   scripts/check-provider-policy.sh task-factory/.github/workflows \
#                                    agent-orchestrator/.github/workflows
#
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: $0 <workflows-dir> [<workflows-dir> ...]" >&2
  exit 2
fi

# A workflow is an APPROVED native-provider exception when it carries this
# marker (case-insensitive). Keep this in sync with the comment authored in
# agent-orchestrator/.github/workflows/integration-tests.yml (OST-706).
EXCEPTION_MARKER='APPROVED PROVIDER-TEST EXCEPTION'

# Direct-Anthropic API-call signals. Any one of these in a workflow means the
# workflow itself is talking to the Anthropic API directly (not via the
# centralized OpenRouter reusable workflow).
is_direct_anthropic_call() {
  local file="$1"
  # Endpoint or version header => unambiguous direct call.
  if grep -Eq 'api\.anthropic\.com|anthropic-version' "$file"; then
    return 0
  fi
  # x-api-key paired with ANTHROPIC_API_KEY => direct Anthropic auth.
  if grep -Eq 'x-api-key' "$file" && grep -Eq 'ANTHROPIC_API_KEY' "$file"; then
    return 0
  fi
  return 1
}

has_exception_marker() {
  grep -Fiq "$EXCEPTION_MARKER" "$1"
}

violations=0
scanned=0

for dir in "$@"; do
  if [ ! -d "$dir" ]; then
    echo "error: not a directory: $dir" >&2
    exit 2
  fi

  # Iterate yml/yaml workflow files. Null-delimited to survive odd names.
  while IFS= read -r -d '' file; do
    scanned=$((scanned + 1))
    if is_direct_anthropic_call "$file"; then
      if has_exception_marker "$file"; then
        echo "ALLOWED (documented exception): $file"
      else
        echo "VIOLATION (undocumented direct-Anthropic PR-review call): $file" >&2
        violations=$((violations + 1))
      fi
    fi
  done < <(find "$dir" -type f \( -name '*.yml' -o -name '*.yaml' \) -print0)
done

echo "---"
echo "scanned $scanned workflow file(s); $violations violation(s)"

if [ "$violations" -ne 0 ]; then
  echo "FAIL: undocumented direct-Anthropic PR-review workflow(s) found." >&2
  echo "Fix: migrate to the reusable OpenRouter lane" >&2
  echo "     (BeliyDym/.github/.github/workflows/ai-review.yml@v2), OR — if this" >&2
  echo "     is a native-provider integration test — add the approved-exception" >&2
  echo "     marker: \"$EXCEPTION_MARKER\"." >&2
  exit 1
fi

echo "PASS: no undocumented direct-Anthropic PR-review workflows."
