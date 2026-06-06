# AI PR-review provider-policy guards

Repeatable checks that enforce the fleet AI PR-review policy established in
OST-647 and triaged in OST-706.

**Policy.** PR review across the BeliyDym fleet is standardized on the
centralized reusable OpenRouter workflow
(`BeliyDym/.github/.github/workflows/ai-review.yml@v2`). Direct-provider
(Anthropic) API calls in a PR-review workflow are forbidden. The one allowed
place for native-provider secrets is a workflow whose subject under test is the
native provider CLI/adapter itself, and such a workflow must carry an explicit
`APPROVED PROVIDER-TEST EXCEPTION` marker.

## Scripts

| Script | Validates | Pass condition |
| --- | --- | --- |
| `check-provider-policy.sh <workflows-dir>...` | A whole `.github/workflows` tree | No workflow makes a direct-Anthropic PR-review API call unless it carries the approved-exception marker. |
| `verify_ai_review_openrouter.sh <file>` | The **reusable implementation** (`.github/workflows/ai-review.yml` in this repo) | Uses the OpenRouter endpoint + bearer auth + response extraction + DeepSeek default + fail-closed notice, and contains no Anthropic references. |
| `verify_ai_review_caller.sh <file>` | A consuming repo's **caller** `ai-review.yml` | Pins the reusable `ai-review.yml@<ref>`, passes `OPENROUTER_API_KEY`, and contains no direct-Anthropic call. |

A caller and the reusable implementation need different checks: the caller only
wires up the reusable workflow (it does not contain the OpenRouter endpoint
strings), so run `verify_ai_review_caller.sh` against callers and
`verify_ai_review_openrouter.sh` against the implementation in this repo.

## Examples

```bash
# Fleet guard across two repos' workflow trees:
scripts/check-provider-policy.sh \
  ../task-factory/.github/workflows \
  ../agent-orchestrator/.github/workflows

# Validate the reusable implementation in this repo:
scripts/verify_ai_review_openrouter.sh .github/workflows/ai-review.yml

# Validate a consuming repo's caller:
scripts/verify_ai_review_caller.sh ../task-factory/.github/workflows/ai-review.yml
```

All scripts exit `0` on pass, `1` on a policy violation, and `2` on a usage
error (bad/missing argument).
