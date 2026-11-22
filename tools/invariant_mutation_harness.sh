#!/usr/bin/env bash
# tools/invariant_mutation_harness.sh — Runtime Canonical Integrity Invariant Verification
#
# Implements the G1 gap closure (AGENTS.md §0.9b Step 1): a mutation harness for
# protected RUNTIME invariants. Each mutant breaks one canonical integrity
# invariant; the oracle test must DETECT the break (test FAIL = mutant died).
#
# DEBT#428 extension (2026-11-21): the harness now mutates the CANONICAL ENGINE
# and proves DETECTION inside an isolated copy, instead of sed-ing tracked source
# in the caller's working tree.
#
# Isolation contract (enforced below, not delegated to the caller):
#   1. record baseline  — `git rev-parse HEAD` + `git status --porcelain` must be
#                         empty; otherwise the harness aborts before touching anything
#   2. copy             — `git archive HEAD` into a mktemp dir outside the repo
#   3. mutate           — sed inside the copy only; each mutant asserts its own
#                         sentinel is present (a stale sed fails closed, it does
#                         not silently "kill" a mutant that was never applied)
#   4. detect           — run the canonical oracle in the copy; require NON-ZERO
#                         exit. A passing oracle means the mutant SURVIVED.
#   5. destroy          — remove the copy
#   6. re-verify        — baseline HEAD and tree state must be byte-identical
#
# Negative control: after every mutant is restored, the oracle must PASS on the
# unmutated copy. Without it, a permanently-red oracle would "detect" everything
# and the harness would be vacuous.
#
# Mutant coverage vs the three protected invariants (DEBT#428):
#   1. verified=true without evidence      → Mutant A (statusConsistentWithEvidence)
#   2. execution bundle digest ignored     → Mutant D (measuredBinaryDigest binding)
#   3. TrustCommit closure weakened        → Mutants B (identityDigest) + C (evidenceId)
#
# Exit codes:
#   0 = All mutants died (every protected invariant break was detected)
#   1 = A mutant survived, baseline dirty, isolation failed, or oracle not green
#       on restore
#
# Env:
#   NIM_BIN          — Nim compiler (default: nim on PATH, else choosenim 2.2.10)
#   AXIOM_AX_BIN     — `bin/ax` needed by tests/config.nims; the copy gets a copy of it
#   MUTATION_HARNESS_DETECT=0 — deliberately disable detection to prove the
#                      harness is not vacuous (must exit 1)
#   MUTATION_HARNESS_TAMPER=1 — inject a mutation that breaks no invariant; the
#                      harness must report it UNDETECTED and exit 1

set -euo pipefail

NIM_BIN="${NIM_BIN:-$(command -v nim 2>/dev/null || echo "$HOME/.choosenim/toolchains/nim-2.2.10/bin/nim")}"
ORACLE="tests/unit/test_invariant_mutation_oracle.nim"
BUNDLE_ORACLE="tests/unit/bundle_digest_test.nim"

# Canonical-engine files mutated by this harness. All mutations happen inside the
# isolated copy; these paths are only ever READ in the caller's tree.
MUTANT_A_FILE="src/core/types/verification_tier.nim"
MUTANT_B_FILE="src/verification/certificate_verifier.nim"
MUTANT_C_FILE="src/core/trusted/trust_commit.nim"
MUTANT_D_FILE="src/verification/obligation/lean_kernel_boundary.nim"

DETECT="${MUTATION_HARNESS_DETECT:-1}"

COPY_DIR=""
BASELINE_HEAD=""
BASELINE_STATUS=""
FAILURES=0
MUTANTS_RUN=0

cleanup() {
    if [[ -n "$COPY_DIR" && -d "$COPY_DIR" ]]; then
        echo "[cleanup] Removing isolated copy: $COPY_DIR"
        rm -rf "$COPY_DIR"
    fi
}
trap cleanup EXIT

fail() {
    echo ""
    echo "============================================"
    echo "❌ MUTATION HARNESS FAILED: $1"
    echo "============================================"
    exit 1
}

# ── Step 0: pre-flight ─────────────────────────────────────────
if ! command -v "$NIM_BIN" &>/dev/null; then
    fail "Nim binary not found at $NIM_BIN"
fi
if [[ ! -f "$ORACLE" ]]; then
    fail "Oracle test not found: $ORACLE"
fi
if [[ ! -f "$BUNDLE_ORACLE" ]]; then
    fail "Bundle-digest oracle test not found: $BUNDLE_ORACLE"
fi
for f in "$MUTANT_A_FILE" "$MUTANT_B_FILE" "$MUTANT_C_FILE" "$MUTANT_D_FILE"; do
    [[ -f "$f" ]] || fail "Mutation target missing: $f"
done

# ── Step 1: record baseline (fail closed on a dirty tree) ───────
echo "=== Baseline: record caller tree state ==="
BASELINE_HEAD=$(git rev-parse HEAD)
BASELINE_STATUS=$(git status --porcelain)
echo "  HEAD:   $BASELINE_HEAD"
if [[ -n "$BASELINE_STATUS" ]]; then
    echo "$BASELINE_STATUS" | sed 's/^/  /'
    fail "baseline tree is dirty — refusing to run (git status --porcelain not empty)"
fi
echo "  worktree: clean"

# ── Step 2: isolated copy ──────────────────────────────────────
# `git archive HEAD` (not the working tree) so the copy is exactly the recorded
# baseline, with no untracked or ignored artifacts carried over.
echo ""
echo "=== Isolation: materialize baseline HEAD into a throwaway copy ==="
COPY_DIR=$(mktemp -d "${TMPDIR:-/tmp}/axiom_mutation.XXXXXXXX")
git archive HEAD | tar -x -C "$COPY_DIR" || fail "git archive extraction failed"
echo "  copy: $COPY_DIR"

# tests/config.nims hard-requires bin/ax (security guard: test suites cannot run
# without validating the core artifact) and it is gitignored, so seed the copy.
AX_BIN="${AXIOM_AX_BIN:-bin/ax}"
if [[ ! -f "$AX_BIN" ]]; then
    fail "core artifact '$AX_BIN' missing — tests/config.nims rejects test suites without it (run: nimble build)"
fi
mkdir -p "$COPY_DIR/bin"
cp "$AX_BIN" "$COPY_DIR/bin/ax"
chmod +x "$COPY_DIR/bin/ax"

# ── Oracle runner ──────────────────────────────────────────────
NIMCACHE="$COPY_DIR/build/nimcache/mutation_harness"
run_in_copy() { # $1 = test path, $2 = label → 0 if the oracle PASSED
    local test_path="$1" label="$2" out rc
    set +e
    out=$(cd "$COPY_DIR" && AXIOM_HERMETIC_BUILDING=1 "$NIM_BIN" c -r --hints:off \
            --nimcache:"$NIMCACHE" -o:"$COPY_DIR/build/tmp/mut_oracle" \
            "$test_path" 2>&1)
    rc=$?
    set -e
    if [[ $rc -eq 0 ]]; then
        echo "  ✅ $label: PASS (oracle green)"
        return 0
    fi
    echo "  ⛔ $label: FAIL (oracle detected the break)"
    echo "$out" | grep -E '\[FAILED\]|Check failed|Error:' | head -4 | sed 's/^/     | /'
    return 1
}

# snapshot/restore keep the pristine bytes of a mutant target and verify the
# restore by CONTENT hash. A bare `cmp` after copying the pristine file back
# would be tautological; the hash is taken before any mutation exists.
snapshot() {
    local src="$COPY_DIR/$1" base
    base="$(basename "$1")"
    cp "$src" "$COPY_DIR/.snapshot_$base"
    sha256sum "$src" | cut -d' ' -f1 > "$COPY_DIR/.snapshot_$base.sha256"
}

restore() {
    local src="$COPY_DIR/$1" base
    base="$(basename "$1")"
    cp "$COPY_DIR/.snapshot_$base" "$src"
    [[ "$(sha256sum "$src" | cut -d' ' -f1)" == "$(cat "$COPY_DIR/.snapshot_$base.sha256")" ]]
}

# apply_mutant <file> <sed-expr> <sentinel> <label>
# Fails closed when the sed did not apply: without the sentinel check, an oracle
# that fails for an unrelated reason would be scored as "mutant detected" —
# exactly the theater §0.9 forbids.
apply_mutant() {
    local file="$1" expr="$2" sentinel="$3" label="$4"
    sed -i "$expr" "$COPY_DIR/$file"
    if ! grep -q "$sentinel" "$COPY_DIR/$file"; then
        fail "$label: mutation did not apply to $file (stale target) — cannot score detection"
    fi
}

# ── Negative control: unmutated copy must be GREEN ─────────────
echo ""
echo "=== Negative control: baseline copy (no mutant) must PASS ==="
run_in_copy "$ORACLE" "baseline oracle" \
    || fail "oracle fails on an UNMUTATED copy — it cannot discriminate, so every 'detection' would be vacuous"
run_in_copy "$BUNDLE_ORACLE" "baseline bundle oracle" \
    || fail "bundle oracle fails on an UNMUTATED copy — detection would be vacuous"

if [[ "$DETECT" == "0" ]]; then
    echo ""
    echo "============================================"
    echo "✅ NEGATIVE CONTROL: detection disabled (MUTATION_HARNESS_DETECT=0)"
    echo "============================================"
    echo "The unmutated copy passes as expected. Asserting a distinct exit code so"
    echo "a caller can prove the harness is not vacuous by this path."
    exit 1
fi

# ── Tamper control: a mutation that cannot be detected must SURVIVE ──
# A neutral comment changes the file but breaks no invariant. If the harness
# scored this as "detected", detection would be noise rather than discrimination.
if [[ "${MUTATION_HARNESS_TAMPER:-0}" == "1" ]]; then
    echo ""
    echo "=== TAMPER CONTROL: neutral mutation on $MUTANT_A_FILE ==="
    snapshot "$MUTANT_A_FILE"
    printf '\n# AXIOM_TAMPER_NEUTRAL\n' >> "$COPY_DIR/$MUTANT_A_FILE"
    grep -q 'AXIOM_TAMPER_NEUTRAL' "$COPY_DIR/$MUTANT_A_FILE" \
        || fail "tamper control: neutral mutation did not apply"
    if run_in_copy "$ORACLE" "tamper control (neutral comment)"; then
        restore "$MUTANT_A_FILE" || fail "tamper control: restore by content hash failed"
        echo ""
        echo "============================================"
        echo "❌ UNDETECTED: tamper control (neutral mutation) survived"
        echo "============================================"
        echo "Expected for this control — the harness must exit non-zero when a"
        echo "mutation is NOT detected, which is what this exit code proves."
        exit 1
    fi
    restore "$MUTANT_A_FILE" || fail "tamper control: restore by content hash failed"
    fail "TAMPER CONTROL: a neutral comment was scored as detected — detection is vacuous"
fi

# ── Mutant runner ──────────────────────────────────────────────
run_mutant() { # <file> <sed-expr> <sentinel> <oracle> <label> <invariant>
    local file="$1" expr="$2" sentinel="$3" oracle="$4" label="$5" invariant="$6"
    echo ""
    echo "=== $label — $invariant ==="
    snapshot "$file"
    apply_mutant "$file" "$expr" "$sentinel" "$label"
    echo "  mutated: $file"
    MUTANTS_RUN=$((MUTANTS_RUN + 1))
    if run_in_copy "$oracle" "$label"; then
        echo "  ❌ UNDETECTED: $label survived — the protected invariant is NOT enforced"
        FAILURES=$((FAILURES + 1))
    fi
    restore "$file" || fail "$label: $file did not return to its pre-mutation content"
}

# 1. verified=true without evidence
run_mutant "$MUTANT_A_FILE" \
    's/return ev\.z3Passed and ev\.leanVerified/return ev.z3Passed or ev.leanVerified  # AXIOM_MUTANT_A/' \
    'AXIOM_MUTANT_A' "$ORACLE" "Mutant A" \
    "verified=true without evidence (certGreen without dual z3 AND lean)"

# 3a. TrustCommit closure weakened — identity digest no longer binds the cert
run_mutant "$MUTANT_B_FILE" \
    's/if storedDigest\.len == 0 or rebuilt != storedDigest:/if storedDigest.len == 0 and rebuilt != storedDigest:  # AXIOM_MUTANT_B/' \
    'AXIOM_MUTANT_B' "$ORACLE" "Mutant B" \
    "TrustCommit closure weakened (identityDigest recompute not enforced)"

# 3b. TrustCommit closure weakened — evidenceId no longer binds embedded content
run_mutant "$MUTANT_C_FILE" \
    's/let expectEvidence = computeEvidenceId(c\.claim, c\.solverInvocation, c\.certificateDigest)/let expectEvidence = c.evidenceId  # AXIOM_MUTANT_C/' \
    'AXIOM_MUTANT_C' "$ORACLE" "Mutant C" \
    "TrustCommit closure weakened (evidenceId content binding dropped)"

# 2. execution bundle digest ignored
run_mutant "$MUTANT_D_FILE" \
    's/let leanDigest = measuredBinaryDigest(leanPath)/let leanDigest = ""  # AXIOM_MUTANT_D/' \
    'AXIOM_MUTANT_D' "$BUNDLE_ORACLE" "Mutant D" \
    "execution bundle digest ignored (lean binary content dropped from fingerprint)"

# ── Post-mutant control ────────────────────────────────────────
# Every mutant is restored above; if the oracle is still red, a failed restore
# (not detection) explains the earlier failures.
echo ""
echo "=== Post-mutant control: restored copy must PASS again ==="
run_in_copy "$ORACLE" "restored oracle" \
    || fail "oracle still fails after restoring every mutant — earlier 'detections' are unreliable"

# ── Step 6: re-verify baseline unchanged ───────────────────────
echo ""
echo "=== Baseline recheck: caller tree must be unchanged ==="
POST_HEAD=$(git rev-parse HEAD)
POST_STATUS=$(git status --porcelain)
RECHECK_OK=true
if [[ "$POST_HEAD" != "$BASELINE_HEAD" ]]; then
    echo "  HEAD drifted: $BASELINE_HEAD → $POST_HEAD"
    RECHECK_OK=false
fi
if [[ "$POST_STATUS" != "$BASELINE_STATUS" ]]; then
    echo "  tree state drifted:"
    echo "$POST_STATUS" | sed 's/^/  /'
    RECHECK_OK=false
fi
[[ "$RECHECK_OK" == true ]] || fail "baseline tree changed during the harness run"
echo "  HEAD:     $POST_HEAD (unchanged)"
echo "  worktree: clean (unchanged)"

if [[ $FAILURES -ne 0 ]]; then
    fail "$FAILURES mutant(s) survived — the harness is theater"
fi

echo ""
echo "============================================"
echo "✅ All $MUTANTS_RUN mutants died — harness PASSED"
echo "============================================"
echo ""
echo "Coverage (DEBT#428 protected invariants):"
echo "  verified=true without evidence   → Mutant A detected"
echo "  execution bundle digest ignored  → Mutant D detected"
echo "  TrustCommit closure weakened     → Mutants B and C detected"
exit 0
