#!/usr/bin/env bash
#
# monitor_purity_scan.sh — PR-landing monitor purity scanner (Tier 0 reinforcement).
#
# Invariant: the PR-landing observation surface performs ZERO write/mutation
# calls to GitHub. The monitor observes (GET / GraphQL queries) and judges;
# merge/queue/ruleset authority is GitHub alone. Runtime detection of a
# mutating request is impossible — GitHub does not audit request methods —
# so the invariant is enforced statically, exactly as git_access_scan.sh
# enforces the depth-1 git-access clause.
#
# Honest scope: this scan verifies that the tracked observation surface
# contains no mutation verbs. It is Tier 0 REINFORCEMENT, not a security
# boundary — it does NOT (and cannot) enforce what the calling GitHub token
# is authorized to do at runtime. A hostile token or an unscanned code path
# is outside this gate's reach; the gate guarantees only that no mutation
# recipe exists in the tracked observation procedure.
#
# Scan surface (exact files — a missing/unreadable file FAILS, never
# silently skipped):
#   docs/agents/merge_admission_observation.md   (observation procedure SSOT)
#   tools/merge_ruleset_drift_monitor.nim        (ruleset drift monitor)
#   .opencode/skills/ci-watch/SKILL.md           (agent CI-watch skill)
#
# Forbidden patterns — GitHub mutation verbs:
#   gh api method flags:    -X POST  -X PUT  -X PATCH  -X DELETE
#   CLI mutations:          gh pr merge  --disable-auto
#   GraphQL/REST mutation names:
#     enqueuePullRequest  addPullRequestToMergeQueue  dequeuePullRequest
#     mergePullRequest  enablePullRequestAutoMerge  disablePullRequestAutoMerge
#     createRepositoryRuleset  updateRepositoryRuleset  deleteRepositoryRuleset
#     createBranchProtectionRule  updateBranchProtectionRule
#     deleteBranchProtectionRule
#
# Exemption mechanism — a scanned file that must legitimately MENTION a
# forbidden name (e.g. prose stating that auto-merge/arm is an operator
# action, not a monitor action) wraps the mention between marker lines:
#
#   <!-- monitor-purity:begin -->
#   ...lines here are exempt (mentions allowed)...
#   <!-- monitor-purity:end -->
#
# The full marker string may be preceded by a language comment token
# (`# <!-- monitor-purity:begin -->` in Nim/shell, `// <!-- ... -->` etc.).
# Prefer NOT needing it: the observation doc's command inventory should
# contain only GET/GraphQL queries. Fail-closed marker rules: a begin without
# a matching end before EOF, a nested begin, and a stray end are all
# configuration errors (exit 2) — an unclosed begin would silently exempt
# the rest of the file.
#
# Usage:   monitor_purity_scan.sh
# No arguments. Deterministic: same tree → same verdict. No network, no writes.
#
# Exit codes:
#   0 — scan complete, 0 forbidden patterns outside exempt blocks; the
#      printed inventory doubles as the current audit evidence
#   1 — forbidden mutation pattern(s) found on the scan surface (fail-closed)
#   2 — environment/configuration error (missing/unreadable scan-surface
#      file, malformed exemption markers)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT"

# ── 1. scan surface (exact tracked observation files) ───────────────────────
SCAN_SURFACE=(
  "docs/agents/merge_admission_observation.md"
  "tools/merge_ruleset_drift_monitor.nim"
  ".opencode/skills/ci-watch/SKILL.md"
)

# ── 2. forbidden mutation verbs (GitHub write surface) ─────────────────────
FORBIDDEN_RE='-X (POST|PUT|PATCH|DELETE)|gh pr merge|--disable-auto|enqueuePullRequest|addPullRequestToMergeQueue|dequeuePullRequest|mergePullRequest|enablePullRequestAutoMerge|disablePullRequestAutoMerge|createRepositoryRuleset|updateRepositoryRuleset|deleteRepositoryRuleset|createBranchProtectionRule|updateBranchProtectionRule|deleteBranchProtectionRule'

MARK_BEGIN='<!-- monitor-purity:begin -->'
MARK_END='<!-- monitor-purity:end -->'

# ── 3. surface presence check — fail-closed, loud ───────────────────────────
SURFACE_OK=1
for f in "${SCAN_SURFACE[@]}"; do
  if [ ! -f "$f" ]; then
    echo "monitor_purity_scan: SCAN SURFACE MISSING: $f (fail-closed — the surface is exact; a missing file is not a pass)" >&2
    SURFACE_OK=0
  elif [ ! -r "$f" ]; then
    echo "monitor_purity_scan: SCAN SURFACE UNREADABLE: $f (fail-closed)" >&2
    SURFACE_OK=0
  fi
done
if [ "$SURFACE_OK" -eq 0 ]; then
  echo "monitor_purity_scan: FAIL — scan surface incomplete (configuration error)" >&2
  exit 2
fi

# ── 4. scan (line state machine: violation detection + exempt markers) ──────
TOTAL_FILES=0
TOTAL_VIOLATIONS=0
TOTAL_EXEMPT_LINES=0

echo "== monitor_purity_scan: PR-landing monitor purity (Tier 0 reinforcement) — inventory = audit evidence =="

for f in "${SCAN_SURFACE[@]}"; do
  echo "-- $f"
  FILE_VIOLATIONS=0
  FILE_EXEMPT=0
  EXEMPT=0
  N=0
  while IFS= read -r LINE || [ -n "$LINE" ]; do
    N=$((N + 1))
    if [[ "$LINE" == *"$MARK_BEGIN"* ]]; then
      if [ "$EXEMPT" -eq 1 ]; then
        echo "monitor_purity_scan: CONFIG ERROR — nested $MARK_BEGIN at $f:$N (fail-closed)" >&2
        exit 2
      fi
      EXEMPT=1
      continue
    fi
    if [[ "$LINE" == *"$MARK_END"* ]]; then
      if [ "$EXEMPT" -eq 0 ]; then
        echo "monitor_purity_scan: CONFIG ERROR — stray $MARK_END at $f:$N (fail-closed)" >&2
        exit 2
      fi
      EXEMPT=0
      continue
    fi
    if [ "$EXEMPT" -eq 1 ]; then
      FILE_EXEMPT=$((FILE_EXEMPT + 1))
      continue
    fi
    if [[ "$LINE" =~ $FORBIDDEN_RE ]]; then
      echo "  [VIOLATION] $f:$N | $(echo "$LINE" | sed 's/^[[:space:]]*//')  (pattern: ${BASH_REMATCH[0]})"
      FILE_VIOLATIONS=$((FILE_VIOLATIONS + 1))
    fi
  done < "$f"
  if [ "$EXEMPT" -eq 1 ]; then
    echo "monitor_purity_scan: CONFIG ERROR — unterminated $MARK_BEGIN in $f (EOF inside exempt block — fail-closed: an open block would exempt the rest of the file)" >&2
    exit 2
  fi
  TOTAL_FILES=$((TOTAL_FILES + 1))
  TOTAL_VIOLATIONS=$((TOTAL_VIOLATIONS + FILE_VIOLATIONS))
  TOTAL_EXEMPT_LINES=$((TOTAL_EXEMPT_LINES + FILE_EXEMPT))
  if [ "$FILE_VIOLATIONS" -eq 0 ]; then
    echo "  (0 forbidden mutation patterns)"
  fi
  if [ "$FILE_EXEMPT" -gt 0 ]; then
    echo "  (exempt lines inside monitor-purity markers: $FILE_EXEMPT)"
  fi
done

# ── 5. summary ──────────────────────────────────────────────────────────────
echo "== summary: files=$TOTAL_FILES violations=$TOTAL_VIOLATIONS exempt-lines=$TOTAL_EXEMPT_LINES =="

if [ "$TOTAL_VIOLATIONS" -gt 0 ]; then
  echo "monitor_purity_scan: FAIL — GitHub mutation verb(s) found on the PR-landing observation surface (monitor purity violated, fail-closed)" >&2
  exit 1
fi
echo "monitor_purity_scan: PASS — 0 mutation verbs on the observation surface (inventory above = audit evidence; Tier 0 reinforcement — not a token-authority boundary)"
exit 0
