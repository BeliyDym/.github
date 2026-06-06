#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <workflow-file>" >&2
  exit 2
fi

workflow="$1"

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

require_present 'OPENROUTER_API_KEY' 'OPENROUTER_API_KEY secret contract'
require_present 'https://openrouter\.ai/api/v1/chat/completions' 'OpenRouter chat completions endpoint'
require_present 'Authorization: Bearer \$OPENROUTER_API_KEY' 'OpenRouter bearer auth'
require_present 'choices\[0\]\.message\.content|\.choices\[0\]\.message\.content' 'OpenRouter response extraction'
require_present 'deepseek/deepseek-chat' 'DeepSeek default route'
require_present 'AI review skipped - OPENROUTER_API_KEY not configured' 'missing OpenRouter key fail-closed notice'

require_absent 'ANTHROPIC_API_KEY' 'Anthropic secret name'
require_absent 'api\.anthropic\.com' 'Anthropic API endpoint'
require_absent 'anthropic-version' 'Anthropic API version header'
require_absent 'content\[0\]\.text|\.content\[0\]\.text' 'Anthropic response extraction'
