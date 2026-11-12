#!/usr/bin/env bash
# tools/invariant_mutation_harness.sh — Runtime Canonical Integrity Invariant Verification
#
# Implements the G1 gap closure: mutation harness for protected RUNTIME invariants.
# Each mutant breaks a runtime canonical integrity invariant; the oracle test must
# detect the break (FAIL = mutant died).
#
# Design:
#   - For each of mutants A/B/C, injects a targeted mutation into the canonical module
#   - Runs the oracle unit test (nim c -r)
#   - Expects oracle FAIL when mutant is injected (invariant broken → test detects it)
#   - Restores source on every exit via trap + git checkout
#   - Verifies working tree is clean after all mutants are tested
#
# Exit codes:
#   0 = All mutants died (oracles detected every invariant break)
#   1 = A mutant survived (oracle passed when it should have failed) or other error

set -euo pipefail

NIM_BIN="${NIM_BIN:-$(command -v nim 2>/dev/null || echo "$HOME/.choosenim/toolchains/nim-2.2.10/bin/nim")}"
ORACLE="tests/unit/test_invariant_mutation_oracle.nim"

# Files that get mutated during the harness (restored by cleanup trap)
MUTANT_FILES="src/core/types/verification_tier.nim src/verification/certificate_verifier.nim src/core/trusted/trust_commit.nim"

# Track whether we are in a mutant-injected state (for safety)
INJECTED=false

cleanup() {
    if [[ "$INJECTED" == true ]]; then
        echo "[cleanup] Restoring source files..."
        git checkout $MUTANT_FILES 2>/dev/null || true
        INJECTED=false
    fi
}
trap cleanup EXIT

# ── Pre-flight ─────────────────────────────────────────────────
if ! command -v "$NIM_BIN" &>/dev/null; then
    echo "FATAL: Nim binary not found at $NIM_BIN"
    exit 1
fi

if [[ ! -f "$ORACLE" ]]; then
    echo "FATAL: Oracle test not found: $ORACLE"
    exit 1
fi

# ── Helper: run oracle and check result ────────────────────────
run_oracle() {
    local expected="$1"   # "pass" or "fail"
    local label="$2"

    set +e
    NIM_OUTPUT=$("$NIM_BIN" c -r --hints:off "$ORACLE" 2>&1)
    NIM_EXIT_CODE=$?
    set -e

    if [[ "$expected" == "pass" && $NIM_EXIT_CODE -eq 0 ]]; then
        echo "  ✅ $label: PASS (oracle green)"
        return 0
    elif [[ "$expected" == "fail" && $NIM_EXIT_CODE -ne 0 ]]; then
        echo "  ✅ $label: FAIL (oracle detected broken invariant — mutant died)"
        return 0
    else
        echo "  ❌ $label: UNEXPECTED (nim exit=$NIM_EXIT_CODE, expected=$expected)"
        echo "$NIM_OUTPUT" | tail -10
        return 1
    fi
}

# ── Helper: inject / restore ───────────────────────────────────
inject_mutant_a() {
    # Mutant A: weaken statusConsistentWithEvidence so certGreen without evidence passes.
    # Target: src/core/types/verification_tier.nim — change the certGreen evidence check
    # from "return ev.z3Passed and ev.leanVerified" to "return true".
    sed -i 's/return ev\.z3Passed and ev\.leanVerified/return true/' src/core/types/verification_tier.nim
}

inject_mutant_b() {
    # Mutant B: weaken identityDigest binding so a tampered digest is accepted.
    # Target: src/verification/certificate_verifier.nim — change the identityDigest
    # comparison from "if storedDigest.len == 0 or rebuilt != storedDigest:" to "if false:".
    sed -i 's/if storedDigest\.len == 0 or rebuilt != storedDigest:/if false:/' src/verification/certificate_verifier.nim
}

inject_mutant_c() {
    # Mutant C: weaken validateCommit so it always returns ok().
    # Target: src/core/trusted/trust_commit.nim — replace every "return err(" inside
    # validateCommit with "discard" so all structural checks are bypassed.
    sed -i 's/return err("trust_commit: unsupported kind")/discard  # MUTANT_C/' src/core/trusted/trust_commit.nim
    sed -i 's/return err("trust_commit: empty evidenceId")/discard  # MUTANT_C/' src/core/trusted/trust_commit.nim
    sed -i 's/return err("trust_commit: empty claim")/discard  # MUTANT_C/' src/core/trusted/trust_commit.nim
    sed -i 's/return err("trust_commit: empty solverInvocation")/discard  # MUTANT_C/' src/core/trusted/trust_commit.nim
    sed -i 's/return err("trust_commit: quarantine commit missing reason")/discard  # MUTANT_C/' src/core/trusted/trust_commit.nim
    sed -i 's/return err("trust_commit: quarantine commit missing originalStatus")/discard  # MUTANT_C/' src/core/trusted/trust_commit.nim
    sed -i 's/return err("trust_commit: empty scopeDigest")/discard  # MUTANT_C/' src/core/trusted/trust_commit.nim
    sed -i 's/return err("trust_commit: empty configDigest")/discard  # MUTANT_C/' src/core/trusted/trust_commit.nim
    sed -i 's/return err("trust_commit: evidenceId does not match embedded content")/discard  # MUTANT_C/' src/core/trusted/trust_commit.nim
}

restore_sources() {
    git checkout $MUTANT_FILES 2>/dev/null || true
    INJECTED=false
}

# ── Baseline: clean source → oracle must PASS ──────────────────
echo "=== Baseline: Oracle on clean source ==="
run_oracle "pass" "Baseline (unmutated)"

# ═══════════════════════════════════════════════════════════════
# Mutant A — verified⇒evidence invariant
# ═══════════════════════════════════════════════════════════════
echo ""
echo "=== Mutant A: verified⇒evidence (statusConsistentWithEvidence weakened) ==="
inject_mutant_a
INJECTED=true
run_oracle "fail" "Mutant A — oracle must FAIL (invariant broken)"
restore_sources
run_oracle "pass" "Mutant A — restored source, oracle must PASS"

# ═══════════════════════════════════════════════════════════════
# Mutant B — identityDigest binding invariant
# ═══════════════════════════════════════════════════════════════
echo ""
echo "=== Mutant B: identityDigest binding (comparison weakened) ==="
inject_mutant_b
INJECTED=true
run_oracle "fail" "Mutant B — oracle must FAIL (invariant broken)"
restore_sources
run_oracle "pass" "Mutant B — restored source, oracle must PASS"

# ═══════════════════════════════════════════════════════════════
# Mutant C — validateCommit structural invariant
# ═══════════════════════════════════════════════════════════════
echo ""
echo "=== Mutant C: validateCommit structural fail-closed (weakened) ==="
inject_mutant_c
INJECTED=true
run_oracle "fail" "Mutant C — oracle must FAIL (invariant broken)"
restore_sources
run_oracle "pass" "Mutant C — restored source, oracle must PASS"

# ── Final verification ──────────────────────────────────────────
echo ""
echo "=== Final verification: working tree clean ==="
DIRTY=$(git status --porcelain)
# Only flag modifications to tracked files (M/D), not new untracked files (??).
# New oracle test files are expected deliverables of this harness.
TRACKED_DIRTY=$(echo "$DIRTY" | grep -E '^[MD]' | grep -v "^.M.*data/debt_registry.json" || true)
if [[ -n "$TRACKED_DIRTY" ]]; then
    echo "❌ Working tree has unexpected modifications to tracked files:"
    echo "$TRACKED_DIRTY"
    exit 1
fi
echo "✅ Working tree clean — no tracked source files left mutated"

echo ""
echo "============================================"
echo "✅ All 3 mutants died — harness PASSED"
echo "============================================"
exit 0
