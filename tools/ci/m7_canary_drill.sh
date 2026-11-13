#!/usr/bin/env bash
#
# m7_canary_drill.sh — canary deny drill for the diagnostic credential (M7 위임 실행).
#
# Contract: docs/spec/diagnostic_execution_delegation.md §5. With the SAME
# permission configuration as the operational watch credential (the in-job
# minted diagnostic installation token), this drill ATTEMPTS merge-affecting
# writes against TEST targets and captures the denial. The denial is the
# terminal evidence: the watch identity's write path is structurally absent
# (permission ceiling), not procedurally abstained.
#
# Evidence captured per attempt (raw, verbatim):
#   - HTTP status line + code
#   - X-GitHub-Request-Id        (GitHub's per-request audit anchor)
#   - X-Accepted-GitHub-Permissions  — AUXILIARY ONLY: it states the ENDPOINT's
#     requirements, never the token's grant (docs/spec/
#     diagnostic_execution_delegation.md §5; never cited as scope evidence)
#   - response body
#
# Verdict vocabulary (closed set — M6 어휘 규율):
#   PERMISSION_LACK_PROVEN  403 + canonical GitHub Apps denial body
#                           ("Resource not accessible by integration"). The 403
#                           precedes mergeability/ruleset evaluation — the
#                           denial reason is PERMISSION-LACK, NOT
#                           branch-protection / check-incomplete / merge-state.
#   WRITE_SUCCEEDED         2xx — the credential CAN change merge-affecting
#                           state. CRITICAL (exit 1); remediation printed.
#   UNKNOWN                 everything else (non-403, 404, 405/409/422 reaching
#                           evaluation, network/5xx, ambiguous bodies). UNKNOWN
#                           is never success and never a proven denial — the
#                           drill fails closed on it (exit 3).
#
# Structural guards (fail-closed, exit 2):
#   - AXIOM_DIAG_TOKEN must be set. The drill NEVER reads `gh auth` / keyring /
#     GITHUB_TOKEN — a canary is only meaningful with the credential under test.
#   - Production ruleset id 26702792 is refused as a PUT target. TRUST ANCHOR
#     (policy v1.19.0 hybrid authority rotation, 2026-11-07): the live
#     fetchers resolve the admission ruleset BY NAME, but this guard keeps a
#     numeric constant — a canary must never discover its own protection
#     target at runtime. The guard VERIFIES the anchor before drilling: it
#     GETs the ruleset and checks name=="main" ∧ enforcement=="active" ∧
#     required_status_checks non-empty ∧ merge_queue MERGE — a fetch failure
#     or a mismatch fails closed (REFUSED/UNKNOWN) because the drill's
#     protection premise would be unverified. 20303214 was the OLD
#     repository's id (preserved as <legacy-repo>; 404s here).
#   - The canary PR's base branch must NOT be the repository default branch —
#     a successful write would mutate production. TEST PRs only.
#
# --dry-run: prints the exact request plan + judgment rubric, performs NO
# network I/O, requires no token, exits 0.
#
# Usage:
#   m7_canary_drill.sh --canary-pr <N> [--repo <owner/repo>] [--ruleset-id <id>]
#                      [--dry-run] [--timeout <seconds>]
#   --ruleset-id  TEST ruleset id for the optional ruleset-write leg (PUT-back
#                 of the verbatim GET body — a no-op write if it succeeded).
#                 NEVER the production ruleset (refused).
#
# Exit codes: 0 = PERMISSION_LACK_PROVEN · 1 = WRITE_SUCCEEDED (critical)
#             2 = usage/configuration error · 3 = UNKNOWN (fail-closed)

set -euo pipefail

REPO=""
CANARY_PR=""
RULESET_ID=""
DRY_RUN=0
TIMEOUT=30
# TRUST ANCHOR — see the header comment. Deliberately NOT resolved by name:
# a canary must never discover its own protection target at runtime.
PROD_RULESET_ID="27097366"

usage() {
  echo "usage: m7_canary_drill.sh --canary-pr <N> [--repo <owner/repo>] [--ruleset-id <id>] [--dry-run] [--timeout <s>]" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="${2:?--repo requires a value}"; shift 2 ;;
    --canary-pr) CANARY_PR="${2:?--canary-pr requires a value}"; shift 2 ;;
    --ruleset-id) RULESET_ID="${2:?--ruleset-id requires a value}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --timeout) TIMEOUT="${2:?--timeout requires a value}"; shift 2 ;;
    *) usage ;;
  esac
done

[ -n "$CANARY_PR" ] || usage
printf '%s' "$CANARY_PR" | grep -Eq '^[0-9]+$' || usage
if [ -n "$REPO" ]; then
  printf '%s' "$REPO" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' || usage
fi
printf '%s' "$TIMEOUT" | grep -Eq '^[0-9]+$' || usage

command -v curl >/dev/null 2>&1 || { echo "m7_canary_drill: curl missing (configuration error)" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "m7_canary_drill: jq missing (configuration error)" >&2; exit 2; }

say() { printf '%s\n' "$*"; }

# ── credential guard: the drill tests EXACTLY AXIOM_DIAG_TOKEN — no fallback ──
CRED_SOURCE="AXIOM_DIAG_TOKEN"
if [ "$DRY_RUN" -eq 0 ]; then
  [ -n "${AXIOM_DIAG_TOKEN:-}" ] || {
    say "m7_canary_drill: FAIL — AXIOM_DIAG_TOKEN absent. The canary is only meaningful with the credential under test; gh auth / GITHUB_TOKEN fallbacks are structurally absent (docs/spec/diagnostic_execution_delegation.md §5)."
    exit 2
  }
fi
say "== m7_canary_drill: canary deny drill — credential-source=$CRED_SOURCE (fallbacks: none, by design) =="

API="https://api.github.com"
if [ -n "$REPO" ]; then
  BASE_URL="$API/repos/$REPO"
else
  # default: the dispatch repository (the workflow passes its own repo; local
  # runs must pass --repo explicitly — no credential-derived repo inference).
  say "m7_canary_drill: FAIL — --repo is required (no gh/credential-derived repo inference; deterministic input only)."
  exit 2
fi

# ── dry-run: request plan + rubric, zero network ────────────────────────────
if [ "$DRY_RUN" -eq 1 ]; then
  say "[dry-run] request plan (no network, no token required):"
  say "  GET    $BASE_URL                                   (control: token valid + repo readable)"
  say "  GET    $BASE_URL/pulls/$CANARY_PR                  (preflight: state==open, base.ref != default branch)"
  say "  PUT    $BASE_URL/pulls/$CANARY_PR/merge            (merge-affecting write; expect 403)"
  say "         headers: Authorization: Bearer <AXIOM_DIAG_TOKEN:redacted>, Accept: application/vnd.github+json"
  say "         body: {\"merge_method\":\"merge\",\"commit_title\":\"M7 CANARY DENY DRILL — must not succeed\"}"
  if [ -n "$RULESET_ID" ]; then
    say "  GET    $BASE_URL/rulesets/$RULESET_ID              (ruleset leg preflight: read must succeed)"
    say "  PUT    $BASE_URL/rulesets/$RULESET_ID              (verbatim GET-body PUT-back = no-op write; expect 403)"
  fi
  say "  GET    $BASE_URL/rulesets/$PROD_RULESET_ID         (prod guard verification — the Trust Anchor must BE the live surface: name=main ∧ active ∧ required checks ∧ merge_queue MERGE)"
  say "[dry-run] judgment rubric:"
  say "  403 + \"Resource not accessible by integration\"  -> PERMISSION_LACK_PROVEN (exit 0)"
  say "  2xx                                             -> WRITE_SUCCEEDED (critical, exit 1)"
  say "  everything else (404/405/409/422/5xx/ambiguous) -> UNKNOWN (fail-closed, exit 3)"
  say "[dry-run] guards: production ruleset $PROD_RULESET_ID refused; canary PR base must not be the default branch; no gh-auth fallback."
  say "[dry-run] PASS — plan well-formed"
  exit 0
fi

auth_header="Authorization: Bearer $AXIOM_DIAG_TOKEN"

# curl wrapper: captures status + headers + body into globals.
HTTP_CODE=""; RESP_HEADERS=""; RESP_BODY=""
http() {
  local method="$1" url="$2" body="${3:-}"
  local hdr_file
  hdr_file="$(mktemp)"
  local args=(-sS --max-time "$TIMEOUT" -D "$hdr_file" -o /tmp/m7_canary_body.$$ -w '%{http_code}' \
    -X "$method" -H "$auth_header" -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" "$url")
  if [ -n "$body" ]; then
    args+=(-d "$body")
  fi
  HTTP_CODE="$(curl "${args[@]}")" || HTTP_CODE="curl-error"
  RESP_HEADERS="$(cat "$hdr_file")"
  RESP_BODY="$(cat /tmp/m7_canary_body.$$ 2>/dev/null || true)"
  rm -f "$hdr_file" /tmp/m7_canary_body.$$
}

hdr() {
  printf '%s' "$RESP_HEADERS" | tr -d '\r' | awk -v k="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" \
    'tolower($1) == k":" { sub(/^[^:]*:[[:space:]]*/, ""); print; found=1 } END { if (!found) print "<absent>" }'
}

verdict() {
  say "[attempt] $1"
  say "  http-status: $HTTP_CODE"
  say "  x-github-request-id: $(hdr x-github-request-id)"
  say "  x-accepted-github-permissions (AUXILIARY — endpoint requirement, not token grant): $(hdr x-accepted-github-permissions)"
  say "  body: $(printf '%s' "$RESP_BODY" | head -c 600)"
}

overall="PERMISSION_LACK_PROVEN"

# ── control: token validity + repo readability ──────────────────────────────
http GET "$BASE_URL"
case "$HTTP_CODE" in
  200) say "[control] GET repo: 200 — token authenticated, repo readable (a later denial is authorization, not authentication)" ;;
  401) say "[control] GET repo: 401 — diagnostic credential invalid/expired (configuration error)"; exit 2 ;;
  *)   verdict "GET repo (control)"; say "[control] non-200 read — canary interpretation unsafe"; exit 3 ;;
esac

# ── preflight: canary PR open + base is NOT the default branch ──────────────
http GET "$BASE_URL/pulls/$CANARY_PR"
if [ "$HTTP_CODE" != "200" ]; then
  verdict "GET pulls/$CANARY_PR (preflight)"
  say "[preflight] canary PR unreadable — refusing to drill (configuration error)"
  exit 2
fi
PR_STATE="$(jq -r '.state // "unknown"' <<<"$RESP_BODY")"
PR_BASE_REF="$(jq -r '.base.ref // "unknown"' <<<"$RESP_BODY")"
DEFAULT_BRANCH="$(jq -r '.base.repo.default_branch // "main"' <<<"$RESP_BODY")"
if [ "$PR_STATE" != "open" ]; then
  say "[preflight] canary PR #$CANARY_PR state=$PR_STATE — must be open (configuration error)"
  exit 2
fi
if [ "$PR_BASE_REF" = "$DEFAULT_BRANCH" ]; then
  say "[preflight] REFUSED — canary PR #$CANARY_PR base is '$PR_BASE_REF' (the default branch). A canary write must never target production. Use a TEST PR against a TEST base branch."
  exit 2
fi
say "[preflight] canary PR #$CANARY_PR: state=open base=$PR_BASE_REF (non-default TEST base — structural production guard held)"

# ── prod guard verification: the Trust Anchor must BE the live surface ──────
# The refusal guard below trusts PROD_RULESET_ID; that premise is OBSERVED,
# never assumed (policy v1.19.0 hybrid authority rotation, 2026-11-07): the
# ruleset must currently be named "main", active, carry required_status_checks
# and the merge_queue MERGE path. A failed read is UNKNOWN (exit 3 — the
# drill cannot attribute denials while its own protection premise is
# unobserved); a mismatch is REFUSED (exit 2 — the anchor is stale and must
# be rotated by a human, never reinterpreted dynamically).
http GET "$BASE_URL/rulesets/$PROD_RULESET_ID"
if [ "$HTTP_CODE" = "200" ]; then
  GUARD_NAME="$(jq -r '.name // ""' <<<"$RESP_BODY")"
  GUARD_ENF="$(jq -r '.enforcement // ""' <<<"$RESP_BODY")"
  GUARD_CHECKS="$(jq -r '[.rules[]? | select(.type == "required_status_checks") | .parameters.required_status_checks[]? | .context] | length' <<<"$RESP_BODY" 2>/dev/null || echo 0)"
  GUARD_MQ="$(jq -r '[.rules[]? | select(.type == "merge_queue") | .parameters.merge_method?] | first // ""' <<<"$RESP_BODY" 2>/dev/null)"
  if [ "$GUARD_NAME" != "main" ] || [ "$GUARD_ENF" != "active" ] || \
     [ "$GUARD_CHECKS" -eq 0 ] || [ "$GUARD_MQ" != "MERGE" ]; then
    verdict "GET rulesets/$PROD_RULESET_ID (prod guard verification)"
    say "[guard] REFUSED — the production ruleset anchor $PROD_RULESET_ID no longer matches the admission surface (name=$GUARD_NAME enforcement=$GUARD_ENF required_checks=$GUARD_CHECKS merge_method=$GUARD_MQ). Rotate the anchor deliberately — the drill refuses to reinterpret it."
    exit 2
  fi
  say "[guard] prod ruleset $PROD_RULESET_ID verified: name=main enforcement=active required_checks=$GUARD_CHECKS merge_method=MERGE — the protection premise holds"
else
  verdict "GET rulesets/$PROD_RULESET_ID (prod guard verification)"
  say "[guard] UNKNOWN — the production ruleset could not be read; the drill's protection premise is unobserved (fail-closed)."
  exit 3
fi

# ── attempt 1: merge-affecting write (the exact operational write the watch
#    identity must never perform). Expect 403 + permission-lack body. ─────────
CANARY_BODY="$(jq -nc --arg t "M7 CANARY DENY DRILL — must not succeed ($(date -u +%Y-%m-%dT%H:%M:%SZ))" \
  '{merge_method: "merge", commit_title: $t}')"
http PUT "$BASE_URL/pulls/$CANARY_PR/merge" "$CANARY_BODY"
verdict "PUT pulls/$CANARY_PR/merge (merge-affecting write)"
case "$HTTP_CODE" in
  403)
    if printf '%s' "$RESP_BODY" | grep -q "Resource not accessible by integration"; then
      say "[verdict] PERMISSION_LACK_PROVEN — 403 precedes mergeability evaluation: the denial reason is permission-lack, NOT branch-protection / check-incomplete / merge-state."
    else
      say "[verdict] UNKNOWN — 403 with non-canonical body; cannot attribute the denial to permission-lack."
      overall="UNKNOWN"
    fi
    ;;
  2*)
    say "[verdict] WRITE_SUCCEEDED — the diagnostic credential CAN merge. CRITICAL: close/revert canary PR #$CANARY_PR immediately and rotate/remove the diagnostic App installation."
    overall="WRITE_SUCCEEDED"
    ;;
  405|409|422)
    say "[verdict] UNKNOWN — the request REACHED merge evaluation (mergeability/validation), i.e. endpoint authority was accepted; this is not a proven denial and not a success."
    overall="UNKNOWN"
    ;;
  *)
    say "[verdict] UNKNOWN — non-403, ambiguous response (never success)."
    overall="UNKNOWN"
    ;;
esac

# ── attempt 2 (optional): ruleset write — verbatim GET-body PUT-back ────────
if [ -n "$RULESET_ID" ]; then
  printf '%s' "$RULESET_ID" | grep -Eq '^[0-9]+$' || { say "[ruleset] malformed --ruleset-id"; exit 2; }
  if [ "$RULESET_ID" = "$PROD_RULESET_ID" ]; then
    say "[ruleset] REFUSED — ruleset $PROD_RULESET_ID is the production merge-admission surface; canary PUTs target TEST rulesets only."
    exit 2
  fi
  http GET "$BASE_URL/rulesets/$RULESET_ID"
  if [ "$HTTP_CODE" = "200" ]; then
    say "[ruleset] GET ruleset/$RULESET_ID: 200 — TEST ruleset readable; PUT-back leg armed (verbatim body = no-op write if it succeeded)"
    http PUT "$BASE_URL/rulesets/$RULESET_ID" "$RESP_BODY"
    verdict "PUT rulesets/$RULESET_ID (ruleset write, no-op content)"
    case "$HTTP_CODE" in
      403)
        if printf '%s' "$RESP_BODY" | grep -q "Resource not accessible by integration"; then
          say "[verdict] PERMISSION_LACK_PROVEN — ruleset write denied by permission ceiling (no Administration grant)."
        else
          say "[verdict] UNKNOWN — 403 with non-canonical body."
          overall="UNKNOWN"
        fi
        ;;
      2*)
        say "[verdict] WRITE_SUCCEEDED — the diagnostic credential CAN PUT rulesets (content was a no-op PUT-back; authority proven). CRITICAL: audit ruleset history and rotate/remove the diagnostic App installation."
        overall="WRITE_SUCCEEDED"
        ;;
      *)
        say "[verdict] UNKNOWN — non-403 on the ruleset write leg (never success)."
        overall="UNKNOWN"
        ;;
    esac
  else
    verdict "GET rulesets/$RULESET_ID (preflight)"
    say "[ruleset] TEST ruleset not readable — ruleset leg SKIPPED (merge leg verdict stands)"
  fi
fi

say "== m7_canary_drill: OVERALL=$overall =="
case "$overall" in
  PERMISSION_LACK_PROVEN)
    say "TERMINAL: 운영 credential과 동일 권한 구성의 진단 credential에 대한 merge-affecting 쓰기가 권한 결핍(403, permission-lack)으로 거부됨을 입증했다."
    exit 0 ;;
  WRITE_SUCCEEDED)
    say "TERMINAL: credential이 쓰기에 성공했다 — 상한 위반. 즉시 대응 필요."
    exit 1 ;;
  *)
    say "TERMINAL: UNKNOWN — 판정 불가(실패 폐쇄). 403이 아닌 응답은 성공으로 읽지 않는다(M6)."
    exit 3 ;;
esac
