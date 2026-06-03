# BeliyDym org `.github`

Organization-default repository. Two things live here:

- **`profile/README.md`** — the public org profile page shown on
  `github.com/BeliyDym`. (Leave it alone unless you're editing the profile.)
- **`.github/workflows/ai-review.yml`** — the canonical **reusable AI PR-review
  workflow** every active repo inherits (see below).

---

## Multi-vendor AI PR review

Every active BeliyDym project gets **three independent AI reviewers per PR**,
each from a different model lineage so a blind spot in one is caught by another
(IRON lens-split doctrine). Authorized by IRON Council 3/3 (OST-626, verdict
`Q1=C Q2=C Q3=C`).

| Reviewer | Lineage | How it's wired | Cost / secret |
|---|---|---|---|
| **Gemini Code Assist** | Google | GitHub App + per-repo `.gemini/config.yaml` + `.gemini/styleguide.md` | Free app, no secret |
| **Claude review bot** | Anthropic | **This reusable workflow** (`workflow_call`), called from each repo | Metered — needs `ANTHROPIC_API_KEY` repo secret |
| **GitHub Copilot** | Microsoft / GitHub | Native `copilot-pull-request-reviewer` App, zero config | Free app, no secret |

> The OpenAI Codex connector (`chatgpt-codex-connector`) is **intentionally
> NOT** part of this setup. Its only differentiator was a hand-fed `AGENTS.md`
> context file — exactly the per-repo drift this single-source rollout exists to
> eliminate. Three lineages already cover the blind-spot diversity.

### Why hybrid (workflow centralized, App config per-repo)

The Claude bot is **executable logic**, so it lives in ONE place here and every
repo inherits edits — no N-copy drift. The Gemini/Copilot pieces are **GitHub
Apps** that read their config from each repo's own tree (`.gemini/`), so those
files *must* be per-repo. There is no other physically-correct architecture:
Apps can't read config out of a `workflow_call`.

---

## Onboard a new repo (3 lines + 1 secret + 2 files)

### 1. Add the caller workflow

Create `.github/workflows/ai-review.yml` in the consuming repo:

```yaml
name: AI Review

on:
  push:
    branches:
      - 'fix/**'
      - 'feat/**'
      - 'sprint/**'
      - 'docs/**'
      - 'chore/**'
      - 'hotfix/**'

concurrency:
  group: ai-review-${{ github.ref }}
  cancel-in-progress: true

jobs:
  ai-review:
    uses: BeliyDym/.github/.github/workflows/ai-review.yml@v1
    permissions:
      contents: read
      pull-requests: write
      issues: write
    with:
      project_label: "YOUR_PROJECT (one-line description)"
      # base_branch: "master"          # ONLY if the repo's default branch is master
      # enforce_bugfix_ledger: false   # set false unless the repo keeps a BUGFIXES.md ledger
    secrets:
      ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
```

**Always pin `@v1`** (an immutable tag), never `@main`. A bad edit to a
floating `@main` would hit every repo at once; the tag is the blast-radius
firewall.

### 2. Add the `ANTHROPIC_API_KEY` secret

Repo → Settings → Secrets and variables → Actions → New repository secret:
`ANTHROPIC_API_KEY`. **This is SJ-owned** — if you don't have it, request it;
do not invent one. Without it the Claude reviewer fails *closed* (posts HIGH +
`needs-human-review`), it never silent-passes.

### 3. Add the Gemini config (per-repo, tuned to the stack)

- `.gemini/config.yaml` — review threshold, comment cap, ignore globs.
- `.gemini/styleguide.md` — repo-specific review criteria (RLS rules for
  Supabase repos, ISR/route rules for Next.js, etc.).

Copy from a similar repo and tune. See FE8's `.gemini/` as the reference.

### 4. Enable the Apps

Install/enable **Gemini Code Assist** and **GitHub Copilot** on the repo (org
App settings). Remove the **`chatgpt-codex-connector`** App from the repo if it
was previously installed.

---

## Reusable workflow inputs

| Input | Default | When to override |
|---|---|---|
| `base_branch` | `main` | Repos whose default branch is `master` (e.g. `fe8-quiz`, `task-factory`) |
| `diff_cap` | `80000` | Rarely — larger diffs cost more tokens; truncation is flagged PARTIAL REVIEW |
| `project_label` | repo name | Always set it to a human label for a better review prompt |
| `bot_marker` | `<!-- AI_REVIEW_BOT_<REPO>_v1 -->` | Rarely — only if a repo needs a custom marker |
| `enforce_bugfix_ledger` | `true` | Set `false` for repos without a `BUGFIXES.md` convention |
| `model` | `claude-sonnet-4-20250514` | To bump the Claude model for a specific repo |
| `max_tokens` | `1024` | Rarely |

Secret: `ANTHROPIC_API_KEY` (declared `required: false` so a missing key fails
closed rather than erroring at the call boundary).

---

## Invariants (do not weaken)

The reusable workflow preserves, from FE8's reference `fe8-review-bot.yml`:

- **Secret redaction** before any AI call — 8 regex families
  (OpenAI / Anthropic / GitHub [classic `gh*_` **and** fine-grained
  `github_pat_`] / Stripe / Supabase-JWT [full `header.payload.signature`, not
  just the header] / AWS / PEM [the **whole** `BEGIN…END` block incl. the base64
  body, not just the marker lines] / hex). This regex sieve is **defense-in-depth,
  not a guarantee** — the **sensitive-file denylist below is the real backstop**.
  A novel secret format the regexes don't yet cover can still slip through; that
  is an accepted residual risk, mitigated by the denylist + fail-closed posture.
- **Sensitive-file denylist** — touching `.env`/`.pem`/`secrets/`/etc. skips the
  AI entirely and forces HIGH. This is the primary secret-leak control; redaction
  is the secondary net for secrets pasted into otherwise-innocent paths.
- **No script injection** — every dynamic value (`github.ref_name`, repo name,
  `inputs.*`, diffstat, PR number) is routed through a step `env:` block and read
  as `$VAR` / `process.env`, never interpolated as `${{ }}` into `run:` shell text
  or `actions/github-script` JS source. An attacker-named branch (`fix/$(id)`) or
  changed-file path (`$(id).txt`) cannot execute in the runner (CWE-94), which
  matters because `ANTHROPIC_API_KEY` is in scope.
- **Fail-closed** — API error, parse failure, missing key, OR a response whose
  `risk` is not exactly `HIGH`/`MEDIUM`/`LOW` → HIGH + `needs-human-review`.
  Never silent-pass (a malformed-but-valid-JSON response cannot downgrade to
  `risk:low`).
- **Bugfix ledger gate** — on `fix/*` branches (when `enforce_bugfix_ledger`),
  the changed-file list must contain the root `BUGFIXES.md` **exactly** (anchored,
  `.` escaped); a decoy like `docs/BUGFIXES.md.bak` does **not** satisfy it and the
  review is forced HIGH + `needs-bugfix-ledger`.
- **Anti-spoof** — only a comment authored by `github-actions[bot]` carrying
  this repo's marker is updated; otherwise a fresh comment is posted.
- **Label hygiene** — stale `risk:*` / `needs-*` / `partial-review` labels are
  stripped before fresh labels are applied. Managed labels are **auto-created**
  (idempotent `createLabel`) on first run, so a freshly-onboarded repo needs no
  manual label setup and never ends red on a missing label.

---

## Rollback

- **Per repo:** delete `.github/workflows/ai-review.yml`, delete `.gemini/` (if
  newly added), remove the `ANTHROPIC_API_KEY` secret. The reviewers stop; no
  other repo is affected.
- **Central:** keep old tags for audit history; ship a **new** tag (`v2`) and
  bump consumers deliberately — never silently move `v1`.
- **FE8** is the golden reference and stays on its in-repo `fe8-review-bot.yml`;
  it is not affected by this reusable workflow.

---

## Active repos covered

`ovu-app`, `IronTrade`, `baby-wiltor`, `loopcafe`, `loop-order-system`, `FE8`
(reference, in-repo copy), `fe8-quiz`, `IronClaw`, `task-factory`, `ADOAR`,
`ovu-seo`, `agent-orchestrator`, `hermes-agent`, `GeoAgent`.

**Never** on forks/templates: `skiff-*`, `prosemirror-tables`, `cipher`,
`time-picker`, `react-express-typescript`.
