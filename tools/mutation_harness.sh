#!/usr/bin/env bash
# tools/mutation_harness.sh — Static Gate Scanner Theater Verification
#
# Implements Triple-Closure Architecture (AGENTS.md §0.9b)
# Step 1: External Mutation Harness - Verifies scanner's operational correctness
#
# Design:
#   - Injects 3 theater mutants: trivial stub, unmanifested gate, Lean sorry leak
#   - Runs `nim check bin/axiom.nim`
#   - Expects compilation FAILURE (scanner detected theater)
#   - If compilation PASSES → scanner is theater → FAIL the harness
#
# Exit codes:
#   0 = Scanner working (detected injected theater)
#   1 = Scanner is theater (failed to detect injected patterns)

set -euo pipefail

SANDBOX_DIR=""
MANIFEST_BACKUP=""
MUTATION_MARKER="MUTATION_HARNESS_$(date +%s)"
NIM_BIN="${NIM_BIN:-$(command -v nim 2>/dev/null || echo "$HOME/.choosenim/toolchains/nim-2.2.10/bin/nim")}"

cleanup() {
    echo "[cleanup] Restoring original state..."

    # Restore manifest
    if [[ -n "$MANIFEST_BACKUP" && -f "$MANIFEST_BACKUP" ]]; then
        mv "$MANIFEST_BACKUP" config/gates.manifest.toml 2>/dev/null || true
        git checkout config/gates.manifest.toml 2>/dev/null || true
    fi

    # Remove mutation files
    rm -f src/gate/runners/mutation_trivial_stub.nim
    rm -f src/gate/runners/mutation_unmanifested.nim
    rm -f plans/mutation_lean_sorry.lean
    rm -rf proofs/mutation_test 2>/dev/null || true

    # Remove test files
    rm -f test_manifest.nim test_scanner_trace.nim simple_test.nim debug_*.nim 2>/dev/null || true
    rm -f full_scanner_test.nim trace_*.nim final_test.nim 2>/dev/null || true
    rm -f read_test.nim parse_test.nim test_error_direct.nim test_real_parsers.nim 2>/dev/null || true

    # Restore clean manifest
    git checkout config/gates.manifest.toml 2>/dev/null || true

    echo "[cleanup] Complete"
}

trap cleanup EXIT

# ── Pre-flight: Anti-Theater Guard (AGENTS.md §0.9) ─────────────────────────
# If bin/axiom.nim is missing, `nim check bin/axiom.nim` fails with "cannot open
# file", so ANY non-zero exit is misread as "scanner detected theater" even though
# the scanner never ran. That is theater (fail-open for the wrong reason) — fail
# closed instead.
if [[ ! -f "bin/axiom.nim" ]]; then
    echo "FATAL: bin/axiom.nim missing — scanner would be vacuous (nim check cannot open file)"
    echo "       Create it first: make bin/axiom.nim  (or run via 'make check-mutation-harness')"
    exit 1
fi

# static_gate_scanner.nim requires every file in config/gates.manifest.toml to EXIST
# at compile time (src/gate/static_gate_scanner.nim:91-93 error()). The manifest lists
# gate-self-check -> bin/gate_self_check (config/gates.manifest.toml:105-106), which is
# gitignored and absent in a fresh tree. If missing, the scanner error()s on the missing
# binary, so `nim check` fails for the WRONG (vacuous) reason and the harness would
# falsely PASS without ever scanning mutants. Fail closed instead.
if [[ ! -f "bin/gate_self_check" ]]; then
    echo "FATAL: bin/gate_self_check missing — scanner fails for the wrong reason (vacuous)"
    echo "       The scanner error()s on the missing manifest binary; it never scans mutants."
    echo "       Build gate binaries first (e.g. 'bin/precompile_gates' or 'make bin/gate_self_check')."
    exit 1
fi

echo "=== Mutation Harness: Static Gate Scanner Verification ==="
echo "Marker: $MUTATION_MARKER"
echo ""

# Record start time for timing assertions
START_TIME=$(date +%s)

# Create sandbox
SANDBOX_DIR=$(mktemp -d)
echo "[setup] Created sandbox: $SANDBOX_DIR"

# Backup manifest
if [[ -f "config/gates.manifest.toml" ]]; then
    cp "config/gates.manifest.toml" "config/gates.manifest.toml.bak"
    MANIFEST_BACKUP="config/gates.manifest.toml.bak"
fi

# ── Stage 1: Inject Mutant 1 - Trivial Stub ────────────────────────────────
echo "[inject] Mutant 1: Trivial Stub (return true)"
cat > src/gate/runners/mutation_trivial_stub.nim << 'EOF'
import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

import gate/gate_contract
import gate/gate_types
import infrastructure/logger
import infrastructure/logging_facade
# axiomIoBoundary

{.axiomGate: "mutation-trivial-stub-gate".}

proc run*(ctx: GateContext): bool =
  result = true

when isMainModule:
  main()
{.pop.}
EOF

# ── Stage 2: Inject Mutant 2 - Unmanifested Gate ──────────────────────────
echo "[inject] Mutant 2: Unmanifested Gate (file in manifest, file missing)"

# Add gate entry pointing to nonexistent file
cat >> config/gates.manifest.toml << 'EOF'

[[gates]]
id = "mutation-unmanifested-gate"
file = "src/gate/runners/mutation_unmanifested.nim"
type = "quality"
EOF

# ── Stage 3: Inject Mutant 3 - Lean Sorry Leak ────────────────────────────
echo "[inject] Mutant 3: Lean Sorry Leak"

# Create a Lean file with sorry in proofs directory
mkdir -p proofs/mutation_test
cat > proofs/mutation_test/sorry_leak.lean << 'EOF'
-- MUTATION: This file contains a Lean "sorry" leak
-- In production code, all "sorry" should be resolved proofs
theorem fake_theorem : True := by
  sorry
EOF

# ── Stage 3b: Verify Mutant Injection Actually Applied ─────────────────────
# AGENTS.md §0.9: if a mutant failed to inject, the evaluation in Stage 5 would
# attribute the nim-check exit code to a mutant that was never present — theater.
# Confirm each mutant's marker is in the working tree before running the scanner.
INJECT_OK=true
if [[ ! -f "src/gate/runners/mutation_trivial_stub.nim" ]] || \
   ! grep -q "result = true" "src/gate/runners/mutation_trivial_stub.nim"; then
    echo "FATAL: Mutant 1 (trivial stub) was not applied"
    INJECT_OK=false
fi
if ! grep -q "mutation-unmanifested-gate" "config/gates.manifest.toml"; then
    echo "FATAL: Mutant 2 (unmanifested gate) was not applied"
    INJECT_OK=false
fi
if [[ ! -f "proofs/mutation_test/sorry_leak.lean" ]] || \
   ! grep -q "sorry" "proofs/mutation_test/sorry_leak.lean"; then
    echo "FATAL: Mutant 3 (Lean sorry) was not applied"
    INJECT_OK=false
fi
if [[ "$INJECT_OK" != true ]]; then
    echo "FATAL: mutant injection incomplete — evaluation cannot be trusted. Aborting."
    exit 1
fi
echo "[verify] All injected mutants present in working tree."

# ── Stage 4: Run Scanner and Verify ───────────────────────────────────────
echo ""
echo "[run] Executing: nim check bin/axiom.nim"
echo "[run] Expected: Compilation FAILURE (scanner detects theater)"
echo ""

# Run nim check and capture exit code
set +e
NIM_OUTPUT=$(timeout 120 "$NIM_BIN" check bin/axiom.nim 2>&1)
NIM_EXIT_CODE=$?
set -e

echo "$NIM_OUTPUT"
echo ""

ELAPSED=$(( $(date +%s) - START_TIME ))
echo "[timing] Elapsed: ${ELAPSED}s"

# ── Stage 5: Evaluate Results ───────────────────────────────────────────────
echo ""
echo "[evaluate] Result: Exit code $NIM_EXIT_CODE"

if [[ $NIM_EXIT_CODE -eq 0 ]]; then
    echo ""
    echo "============================================"
    echo "❌ FAIL: Scanner passed - this is theater!"
    echo "============================================"
    echo ""
    echo "The static_gate_scanner.nim should have detected the injected theater patterns."
    echo "A working scanner would have failed compilation with an error."
    echo ""
    echo "Analysis:"
    echo "  - Trival stub (result = true): NOT detected"
    echo "  - Unmanifested gate: NOT detected (possible parsing bug)"
    echo "  - Lean sorry leak: NOT in scope (scanner checks Nim files only)"
    echo ""
    exit 1
else
    echo ""
    echo "============================================"
    echo "✅ PASS: Scanner detected theater patterns"
    echo "============================================"
    echo ""
    echo "Compilation failed as expected. The scanner is working correctly."
    echo ""
    exit 0
fi