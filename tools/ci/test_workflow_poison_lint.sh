#!/usr/bin/env bash
#
# test_workflow_poison_lint.sh — self-test harness for the parse-poison rule
# in tools/ci/validate_workflow_shell.sh (zero new dependencies: bash only;
# the lint itself already requires python3+PyYAML, enforced fail-closed).
#
# Proves, mechanically at the current OID:
#   1. fixture matrix — each committed fixture under
#      tests/fixtures/workflow_poison/ yields EXACTLY its designed verdict:
#        poison_21001_tokenized.yml     FAIL (length=21001, first char over cap)
#        boundary_21000_tokenized.yml   PASS (at-cap is not over-cap, > semantics)
#        boundary_20999_tokenized.yml   PASS (below cap)
#        control_30000_token_free.yml   PASS (token-free class is cap-exempt)
#        poison_regression_25954.yml    FAIL (length=25954, PR #780 shape)
#   2. attribution — every expected-FAIL line is the parse-poison rule (not an
#      accidental bash -n failure) and carries the measured scalar length.
#   3. false-positive sweep — the enforcing rule over the repo's real
#      .github/workflows/*.yml exits 0 (0 violations) and the per-file
#      tokenized-max table is emitted for the record
#      (docs/design/workflow_parse_poison_lint_wiring_design_2026-10-14.md).
#
# Run:   bash tools/ci/test_workflow_poison_lint.sh   (or: make test-workflow-poison-lint)
# Exit:  0 — all assertions held; 1 — any assertion failed (fail-closed)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LINT="$SCRIPT_DIR/validate_workflow_shell.sh"
FIXTURE_DIR="$ROOT/tests/fixtures/workflow_poison"

fail() { echo "test_workflow_poison_lint: FAIL — $*" >&2; exit 1; }

[ -f "$LINT" ] || fail "lint script missing: $LINT"
[ -d "$FIXTURE_DIR" ] || fail "fixture dir missing: $FIXTURE_DIR"

TOKEN_LIT='${{'

# fixture integrity (static): tokenized fixtures carry the token, control does not
for f in poison_21001_tokenized.yml boundary_21000_tokenized.yml \
         boundary_20999_tokenized.yml poison_regression_25954.yml; do
  grep -qF "$TOKEN_LIT" "$FIXTURE_DIR/$f" || fail "$f must be tokenized but carries no token"
done
if grep -qF "$TOKEN_LIT" "$FIXTURE_DIR/control_30000_token_free.yml"; then
  fail "control_30000_token_free.yml must be token-free"
fi

# 1+2. fixture matrix through the real lint entrypoint
set +e
OUT="$(bash "$LINT" --scan-dir "$FIXTURE_DIR" 2>&1)"
RC=$?
set -e
echo "$OUT"
[ "$RC" -eq 1 ] || fail "scan over fixtures must exit 1 (2 poison fixtures), got $RC"

assert_verdict() {
  local f="$1" want="$2" want_len="$3" line detail
  if [ "$want" = "PASS" ]; then
    grep -q "^PASS:.*$f:" <<<"$OUT" || fail "$f: expected PASS line, none found"
    if grep -q "^FAIL:.*$f:" <<<"$OUT"; then fail "$f: unexpected FAIL line"; fi
    return
  fi
  line="$(grep "^FAIL:.*$f:" <<<"$OUT" | head -1)"
  [ -n "$line" ] || fail "$f: expected FAIL line, none found"
  if grep -q "^PASS:.*$f:" <<<"$OUT"; then fail "$f: unexpected PASS line next to FAIL"; fi
  detail="$(grep -A1 "^FAIL:.*$f:" <<<"$OUT" | sed -n '2p')"
  [[ "$detail" == *"parse-poison:"* ]] || fail "$f: FAIL is not attributed to the parse-poison rule: $detail"
  [[ "$detail" == *"length=$want_len "* ]] || fail "$f: expected length=$want_len in detail, got: $detail"
}

assert_verdict "poison_21001_tokenized.yml"   FAIL 21001
assert_verdict "boundary_21000_tokenized.yml" PASS ""
assert_verdict "boundary_20999_tokenized.yml" PASS ""
assert_verdict "control_30000_token_free.yml" PASS ""
assert_verdict "poison_regression_25954.yml"  FAIL 25954

grep -q "SUMMARY: run blocks checked=5 failures=2" <<<"$OUT" \
  || fail "fixture scan summary must be 'checked=5 failures=2'"

# 3. false-positive sweep over the repo's real workflows
set +e
SWEEP="$(bash "$LINT" --max-report 2>&1)"
SWEEP_RC=$?
FULL="$(bash "$LINT" 2>&1)"
FULL_RC=$?
set -e
echo "$SWEEP"
[ "$SWEEP_RC" -eq 0 ] || fail "max-report over repo workflows failed (rc=$SWEEP_RC): $SWEEP"
n_reported="$(grep -c "^MAX:" <<<"$SWEEP" || true)"
n_workflows="$(find "$ROOT/.github/workflows" -maxdepth 1 -name '*.yml' | wc -l)"
[ "$n_reported" -eq "$n_workflows" ] || fail "max-report covered $n_reported of $n_workflows workflows"
[ "$FULL_RC" -eq 0 ] || fail "enforcing run over repo workflows exited $FULL_RC (false positive or live poison): $FULL"

echo "test_workflow_poison_lint: PASS — fixture matrix 5/5, sweep 0 violations over $n_workflows workflows"
