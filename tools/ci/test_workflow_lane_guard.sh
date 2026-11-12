#!/usr/bin/env bash
#
# test_workflow_lane_guard.sh — self-test harness for the lane-stderr emission
# rule in tools/ci/validate_workflow_shell.sh (zero new dependencies: bash +
# the lint's own python3+PyYAML requirement; git for the authenticity checks —
# the repo's own history is the negative oracle).
#
# Proves, mechanically at the current OID:
#   1. fixture matrix — the committed fixtures under
#      tests/fixtures/workflow_lane_guard/ yield EXACTLY their designed
#      verdicts:
#        lane_without_emission.yml  FAIL — <lane-stderr-guard> attribution
#          (reverted 4-lane blob 2c94c9914 shape: lane redirect, never
#          re-emitted)
#        lane_with_emission.yml     PASS — no FAIL line (2555ab966 recipe
#          shape: cat re-emission + `if: always()` upload of the lane logs)
#   2. authenticity — the REAL historical blobs, extracted from git at test
#      time (fail-closed: the objects must resolve; the bsec candidate checkout
#      uses fetch-depth: 0, so full history is available on every enforcing
#      path):
#        2c94c991418dfd89e665ce4ec3efdcc86ffd2e93:.github/workflows/admission-check.yml
#          → scan must FAIL with the <lane-stderr-guard> attribution
#        2555ab966e35e8a5023c28e87c1836b1744bd7a9:.github/workflows/admission-check.yml
#          → scan must PASS outright (emission present; exit 0)
#   3. false-positive sweep — the enforcing rule over the repo's real
#      .github/workflows/*.yml exits 0 (production has no lanes today).
#
# Rule provenance: prereg docs/evidence/merge_latency_decision_prereg_2026-10-14.md
# §8 (amendment 2026-10-15); C1 audit
# docs/evidence/slice_c_p1_evidence_audit_2026-10-15.md.
#
# Run:   bash tools/ci/test_workflow_lane_guard.sh   (or: make test-workflow-lane-guard)
# Exit:  0 — all assertions held; 1 — any assertion failed (fail-closed)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LINT="$SCRIPT_DIR/validate_workflow_shell.sh"
FIXTURE_DIR="$ROOT/tests/fixtures/workflow_lane_guard"

REVERTED_SHA="2c94c991418dfd89e665ce4ec3efdcc86ffd2e93"
RECIPE_SHA="2555ab966e35e8a5023c28e87c1836b1744bd7a9"
WF_PATH=".github/workflows/admission-check.yml"

fail() { echo "test_workflow_lane_guard: FAIL — $*" >&2; exit 1; }

[ -f "$LINT" ] || fail "lint script missing: $LINT"
[ -d "$FIXTURE_DIR" ] || fail "fixture dir missing: $FIXTURE_DIR"

# 1. fixture matrix through the real lint entrypoint
set +e
OUT="$(bash "$LINT" --scan-dir "$FIXTURE_DIR" 2>&1)"
RC=$?
set -e
echo "$OUT"
[ "$RC" -eq 1 ] || fail "scan over fixtures must exit 1 (1 guard violation), got $RC"

grep -Eq "^FAIL:\S*lane_without_emission\.yml:<lane-stderr-guard>$" <<<"$OUT" \
  || fail "lane_without_emission.yml: expected FAIL line with <lane-stderr-guard> attribution"
if grep -Eq "^FAIL:\S*lane_with_emission\.yml:" <<<"$OUT"; then
  fail "lane_with_emission.yml: unexpected FAIL line"
fi
grep -Eq "^PASS:\S*lane_with_emission\.yml:" <<<"$OUT" \
  || fail "lane_with_emission.yml: expected PASS line, none found"
grep -q "lane-guard violations=1" <<<"$OUT" \
  || fail "fixture scan summary must report lane-guard violations=1"

# 2. authenticity — real blobs from git history (fail-closed on missing objects)
for sha in "$REVERTED_SHA" "$RECIPE_SHA"; do
  git -C "$ROOT" cat-file -e "$sha:$WF_PATH" \
    || fail "git object $sha:$WF_PATH unresolvable at this checkout — full history required (bsec candidate checkout is fetch-depth: 0; local clones must not be depth-trimmed below the recipe commits)"
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/reverted" "$TMP/recipe"
git -C "$ROOT" show "$REVERTED_SHA:$WF_PATH" > "$TMP/reverted/admission-check.yml"
git -C "$ROOT" show "$RECIPE_SHA:$WF_PATH" > "$TMP/recipe/admission-check.yml"

set +e
OUT_REV="$(bash "$LINT" --scan-dir "$TMP/reverted" 2>&1)"
RC_REV=$?
OUT_REC="$(bash "$LINT" --scan-dir "$TMP/recipe" 2>&1)"
RC_REC=$?
set -e
echo "$OUT_REV"
echo "$OUT_REC"
[ "$RC_REV" -eq 1 ] || fail "reverted blob ($REVERTED_SHA) must FAIL the scan, got rc=$RC_REV"
grep -Eq "^FAIL:\S*admission-check\.yml:<lane-stderr-guard>$" <<<"$OUT_REV" \
  || fail "reverted blob: FAIL not attributed to <lane-stderr-guard>"
[ "$RC_REC" -eq 0 ] || fail "recipe blob ($RECIPE_SHA) must PASS the scan outright (emission present), got rc=$RC_REC: $OUT_REC"

# 3. false-positive sweep over the repo's real workflows
set +e
FULL="$(bash "$LINT" 2>&1)"
FULL_RC=$?
set -e
echo "$FULL"
[ "$FULL_RC" -eq 0 ] || fail "enforcing run over repo workflows exited $FULL_RC (false positive or live lane violation): $FULL"

echo "test_workflow_lane_guard: PASS — fixture matrix 2/2, authenticity reverted-FAIL/recipe-PASS, sweep 0 violations over repo workflows"
