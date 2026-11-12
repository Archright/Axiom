#!/usr/bin/env bash
#
# git_access_scan.sh — depth-1 Git invariant scanner (product invariant clause 1).
#
# Invariant: the CI verification path performs ZERO history/parent object
# access (`^1`, `^2`, `HEAD~`, rev-list, merge-base, log-range, describe,
# `@{`). Every Git object the verification path touches must exist within
# `fetch-depth: 1` (tip commit + its full tree graph — commit/tree/blobs at
# the tip) — clause 2. Breakers are the patterns that need parent/history
# objects, which a depth-1 clone does not provide.
#
# Scan scope — the CI execution closure:
#   * every `run:` block of .github/workflows/*.yml (all workflows, sorted)
#   * every local script a run block invokes (`bash tools/ci/*.sh`, `sh ...`,
#     direct `.sh` executables) — resolvable scripts are scanned with the same
#     breaker rules; compiled artifacts (`./bin/*`) and dynamically-resolved
#     paths are recorded UNRESOLVED (static scan N/A) and REPORTED — never
#     silently passed. Their executed git access is covered by the audit
#     evidence table (L3-d1 PR body) instead.
#
# Depth classification (per workflow): a workflow whose checkouts all use
# fetch-depth: 1 (or omit it — actions/checkout default is 1) is a DEPTH-1
# path → breaker patterns are violations (exit 1). A workflow declaring
# `fetch-depth: 0` anywhere is full-history BY DECLARATION — its history
# access has its objects provided by that depth-0 checkout, so it is
# inventory-only (printed, never a breaker). This matches the L3 plan's
# scope: the depth-1 verification path = admission-check.yml +
# certificate-mint.yml; repository_surface.yml / runner-pool-acceptance.yml
# stay depth-0 by design and are outside the clause-1 boundary.
#
# Clause 3 — bounded-ancestry acquisition (sanctioned, Amendment F item 6 /
# docs/spec/certification_continuity_contract.md §11): the candidate-tree
# identity check (`merge-tree(B, SUBJECT_HEAD) == tree(github.sha)`) needs
# the merge base of its two side tips, which a depth-1 object set does not
# carry. The sanctioned ancestry consumers are EXACTLY two, both bounded and
# deterministic: `git merge-tree --write-tree` (computes the merge base
# in-process; reports unresolvable ancestry as rc=128) and
# `git fetch --deepen=<N>` with a fixed round cap (the fetch contract's
# 8x64 bound). Neither is a breaker pattern: they are not arbitrary history
# walks. Their sites are inventoried like every other git invocation (the
# inventory IS the audit evidence). Any OTHER history/parent access —
# rev-list, log, describe, HEAD~, ^N, @{...}, three-dot ranges, explicit
# ancestry probes — remains a clause-1 breaker on depth-1 paths. This
# refines clause 1 from "zero history-object access" to "zero UNBOUNDED
# history walks"; the bounded form is what the product contract sanctions.
#
# Breaker patterns — precise list (plan-verbatim):
#   HEAD~  \^\^?[0-9]  rev-list  merge-base  git log  git describe  @{  \.\.\.
# `git show <sha>:<path>` (path show) is NOT a breaker. `\^\^?[0-9]` is
# deliberately tight: `HEAD^{tree}` (tip-tree peel — the audit's core op,
# depth-1 covered) does NOT match.
#
# Usage:   git_access_scan.sh
# No arguments. Deterministic: same tree → same verdict. No network, no writes.
#
# Exit codes:
#   0 — scan complete, 0 breakers on any depth-1 path; the printed inventory
#      (site list) doubles as the current audit evidence
#   1 — breaker(s) found on a depth-1 path (fail-closed)
#   2 — environment/configuration error (missing scope, unreadable file)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT"

[ -d .github/workflows ] || {
  echo "git_access_scan: .github/workflows missing under $ROOT (configuration error — fail closed)" >&2
  exit 2
}

# Breaker: needs parent/history objects absent from a depth-1 clone.
#   @{...} refs (e.g. @{upstream}), three-dot ranges (A...B diff needs
#   merge-base), ^NUM parent revs, HEAD~N, rev-list / merge-base / git log /
#   git describe walks.
BREAKER_RE='HEAD~|(\^|\^\^)[0-9]|rev-list|merge-base|git[[:space:]]+log|git[[:space:]]+describe|@\{|\.\.\.'

# ── 1. run-block extractor ──────────────────────────────────────────────────
# Emits "yamlno:content" for every line belonging to a `run:` block (multi-line
# `run: |` / `run: >` forms) plus single-line `run: <cmd>` bodies. Keys at the
# same-or-lesser column end the block. Space-indented YAML only (repo
# convention); tab-indented content would end the current block — fail-closed.
# ────────────────────────────────────────────────────────────────────────────
run_blocks_of() {
  awk '
    {
      if (in_run) {
        if ($0 ~ /^[[:space:]]*$/) { print NR ":" ; next }
        fc = match($0, /[^ ]/)
        # any same-or-lesser column construct (key, `- name:`, comment) ends
        # the block — run-block content is always indented deeper than `run:`
        if (fc <= rcol) { in_run = 0 }
        else { print NR ":" $0; next }
      }
      if (in_run) next
      if (match($0, /^[ ]*run:/)) {
        rcol = index($0, "run:")
        rest = $0
        sub(/^[ ]*run:[ ]*/, "", rest)
        if (rest == "") next
        if (rest ~ /^\|/ || rest ~ /^>/) { in_run = 1; next }
        print NR ":" rest
      }
    }
  ' "$1"
}

# git-command token — `git <subcommand>` at command position (option prefix
# like `-C <dir>` allowed). `github`, `/.git` dir paths, and prose like
# "git dir" do NOT match — only actual git invocations with a known
# subcommand count as sites.
GIT_SUBCMDS='rev-parse|show|hash-object|merge-base|merge-tree|rev-list|log|describe|diff|ls-tree|fetch|clone|checkout|init|status|commit|push|pull|remote|branch|tag|notes|clean|stash|worktree|cat-file|mv|rm'
has_git_token() {
  local re="(^|[^A-Za-z0-9_/.])git[[:space:]]+(-[A-Za-z0-9]+([[:space:]]+[^[:space:]|;&]+)*[[:space:]]+)?($GIT_SUBCMDS)([[:space:]-]|\$)"
  [[ "$1" =~ $re ]]
}

# ── 2. script invocation resolver (bash tools/ci/*.sh, sh ..., .sh direct) ──
# Emits "path" for each resolvable script; records UNRESOLVED elsewhere.
resolve_script_candidates() {
  local no="$1" content="$2"
  if is_mention_line "$content"; then
    return
  fi
  # command-position script/helper invocations (git_access_scan own scope:
  # bash/sh/`./`-style paths; `make`/compiled-runner scope is covered by the
  # executed-access audit table, not statically resolvable here).
  local re_sh='(^|[;&|(][[:space:]]*)(bash|sh|source)[[:space:]]+([A-Za-z0-9_.{}$/-]+)'
  local re_sheet='(^|[;&|(][[:space:]]*)\./([A-Za-z0-9_.{}$/-]+\.sh)'
  local re_bin='bin/[A-Za-z0-9_.-]+'
  if [[ "$content" =~ $re_sh ]]; then
    candidate="${BASH_REMATCH[3]}"
    case "$candidate" in -*) ;; *) echo "$candidate" ;; esac
  fi
  if [[ "$content" =~ $re_sheet ]]; then
    echo "./${BASH_REMATCH[2]}"
  fi
  # compiled artifact mention at invocation position: `bin/<name>` (also via
  # assignment like `ax="$WORKSPACE/bin/ax"` — conservative, reported).
  if [[ "$content" =~ $re_bin ]]; then
    candidate="${BASH_REMATCH[0]}"
    candidate="${candidate%%[.!:,)]}"
    echo "$candidate"
  fi
}

# ── 3. inline mention filter — a line whose first command is a text emitter ──
# and mentions git inside a quoted string is a mention, not an invocation.
is_mention_line() {
  local re='^[[:space:]]*(\|\||&&)?[[:space:]]*(fail|echo|printf)[[:space:]]*"'
  [[ "$1" =~ $re ]]
}

# ── main ────────────────────────────────────────────────────────────────────
TOTAL_SITES=0
TOTAL_BREAKERS=0
UNRESOLVED_NOTES=""
SCANNED_SCRIPTS=""
declare -a RESOLVABLE_SCRIPTS=()

echo "== git_access_scan: depth-1 Git invariant (clause 1) — inventory = audit evidence =="

while IFS= read -r WF; do
  WF_NAME="$(basename "$WF")"
  FULL_HISTORY=0
  if grep -qE '^[[:space:]]*fetch-depth:[[:space:]]*0([[:space:]]|$)' "$WF"; then
    FULL_HISTORY=1
  fi
  if [ "$FULL_HISTORY" -eq 1 ]; then
    CLASS="full-history (fetch-depth: 0 declared — inventory only)"
  else
    CLASS="depth-1 (breakers enforced)"
  fi
  echo "-- $WF [$CLASS]"

  LINES="$(run_blocks_of "$WF")"
  SITE_COUNT=0
  while IFS= read -r BLOCK_LINE; do
    [ -n "$BLOCK_LINE" ] || continue
    NO="${BLOCK_LINE%%:*}"
    CONTENT="${BLOCK_LINE#*:}"
    # git invocations → inventory (a git-command token; `github` is not git)
    if has_git_token "$CONTENT" && ! is_mention_line "$CONTENT"; then
      TOTAL_SITES=$((TOTAL_SITES + 1))
      SITE_COUNT=$((SITE_COUNT + 1))
      echo "  site $WF:$NO | $CONTENT"
      # breaker patterns — only meaningful on git-access lines
      if [ "$FULL_HISTORY" -eq 0 ] && printf '%s\n' "$CONTENT" | grep -qE "$BREAKER_RE"; then
        BREAKER_LINE="$(printf '%s\n' "$CONTENT" | grep -oE "$BREAKER_RE" | head -n 1)"
        echo "  [BREAKER] $WF:$NO | $CONTENT  (pattern: $BREAKER_LINE)"
        TOTAL_BREAKERS=$((TOTAL_BREAKERS + 1))
      fi
    fi
    # script/helper resolution
    RESOLVED="$(resolve_script_candidates "$NO" "$CONTENT")"
    if [ -n "$RESOLVED" ]; then
      CAND="$RESOLVED"
      case "$CAND" in
        bin/*|./bin/*)
          UNRESOLVED_NOTES="$UNRESOLVED_NOTES
  [UNRESOLVED] $WF:$NO — $CAND (compiled artifact; static scan N/A — executed-access coverage via audit table)"
          ;;
        *\$*)
          UNRESOLVED_NOTES="$UNRESOLVED_NOTES
  [UNRESOLVED] $WF:$NO — $CAND (dynamic/env path; static scan N/A — audit coverage required)"
          ;;
        *)
          CAND="${CAND#./}"
          if [ -f "$CAND" ]; then
            RESOLVABLE_SCRIPTS+=("$CAND")
            echo "  [script] $WF:$NO invokes $CAND (scanned)"
          else
            UNRESOLVED_NOTES="$UNRESOLVED_NOTES
  [UNRESOLVED] $WF:$NO — $CAND (missing in tree; cannot scan)"
          fi
          ;;
      esac
    fi
  done <<< "$LINES"

  if [ "$SITE_COUNT" -eq 0 ]; then
    echo "  (no git invocations in run blocks)"
  fi
done < <(find .github/workflows -maxdepth 1 -name '*.yml' -type f | sort)

# ── 4. scan resolvable scripts (same breaker/inventory rules) ───────────────
if [ "${#RESOLVABLE_SCRIPTS[@]}" -gt 0 ]; then
  for SCRIPT in $(printf '%s\n' "${RESOLVABLE_SCRIPTS[@]}" | sort -u); do
    echo "-- script: $SCRIPT (invoked by CI run blocks)"
    SCRIPT_SITES=0
    SCRIPT_NO=0
    while IFS= read -r SLINE; do
      SCRIPT_NO=$((SCRIPT_NO + 1))
      if [[ "$SLINE" == *git* ]] && ! is_mention_line "$SLINE"; then
        SCRIPT_SITES=$((SCRIPT_SITES + 1))
        TOTAL_SITES=$((TOTAL_SITES + 1))
        echo "  site $SCRIPT:$SCRIPT_NO | $(echo "$SLINE" | sed 's/^[[:space:]]*//')"
      fi
      if printf '%s\n' "$SLINE" | grep -qE "$BREAKER_RE"; then
        BREAKER_LINE="$(printf '%s\n' "$SLINE" | grep -oE "$BREAKER_RE" | head -n 1)"
        echo "  [BREAKER] $SCRIPT:$SCRIPT_NO | $(echo "$SLINE" | sed 's/^[[:space:]]*//')  (pattern: $BREAKER_LINE)"
        TOTAL_BREAKERS=$((TOTAL_BREAKERS + 1))
      fi
    done < "$SCRIPT"
    if [ "$SCRIPT_SITES" -eq 0 ]; then
      echo "  (no git invocations)"
    fi
  done
fi

# ── 5. summary ──────────────────────────────────────────────────────────────
echo "== summary: git sites=$TOTAL_SITES breakers=$TOTAL_BREAKERS =="

if [ -n "$UNRESOLVED_NOTES" ]; then
  echo "UNRESOLVED (reported — not silently passed; executed-access coverage is the audit table):$UNRESOLVED_NOTES"
fi

if [ "$TOTAL_BREAKERS" -gt 0 ]; then
  echo "git_access_scan: FAIL — depth-1 history/parent access found (clause 1 violated, fail-closed)" >&2
  exit 1
fi
echo "git_access_scan: PASS — 0 history/parent access on depth-1 CI paths (inventory above = audit evidence)"
exit 0