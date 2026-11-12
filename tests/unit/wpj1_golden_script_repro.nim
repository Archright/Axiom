## tests/unit/wpj1_golden_script_repro.nim
## WP4-j.1 Phase D — golden obligation script reconstruction + envelope digest match.
##
## Reproduces, bit-for-bit, the SMT script that the E2E pipeline lowered for
## getBitsBE's first (golden) okSafetyDiv obligation, by calling the SAME
## lowering primitive (lowerObligationToSmt) on the SAME proposition shape the
## candidate extractor builds (semantic_target_extractor.nim:156):
##   uoNot(boEq(irVar("resultBits", BitVec64), irLit(0)))
## then computes buildZ3QueryEnvelope digests for both execution modes and both
## candidate logics, for comparison against the Z3 telemetry records observed
## in the E2E getBitsBE runs:
##   sat d067de0283743d9117ac7a7e900452bd6d7a0fab013e734e2a519ac087e30742
##   sat d9f9af27c1dfa8b3b41d266f54e1850142587bf0e03c7d112dea3eb05d0588b4
##
## Read-only probe: no product code is exercised beyond pure lowering + envelope
## construction. No solver is launched here.

import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/trusted/private/obligation_smt_lowering
import core/logic/smt_logic
import core/proof/proof_budget
import verification/solver/z3_pool

# ── the exact proposition the extractor builds for a division candidate ──
let denom = "resultBits"
let predExpr = irUnaryOp(uoNot,
  irBinOp(boEq, irVar(denom, irTypeBitVec64()), irLit(0)))

let observed = [
  "d067de0283743d9117ac7a7e900452bd6d7a0fab013e734e2a519ac087e30742",
  "d9f9af27c1dfa8b3b41d266f54e1850142587bf0e03c7d112dea3eb05d0588b4",
]

echo "=== golden proposition ==="
echo "  uoNot(boEq(irVar(\"resultBits\", BitVec64), irLit(0)))"
echo ""

for logic in [slQfBv, slQfAufbv]:
  let ctx = SmtLoweringContext(logic: logic, rlimit: z3DeterministicBudget,
                               obligationKind: "okSafetyDiv")
  let lowered = lowerObligationToSmt(predExpr, ctx)
  echo "=== lowered script (logic=" & smtLogicName(logic) & ", empty=" & $lowered.empty & ") ==="
  echo lowered.smtScript
  echo "--- symbolic operands: " & $lowered.symbolicOperands
  echo ""
  var dRaw = ""
  discard buildZ3QueryEnvelope(lowered.smtScript, timeoutMs = 8000, sentinel = "PROBE",
                               enableProofs = false, mode = zmRaw,
                               canonicalEnvelopeDigest = dRaw)
  var dInc = ""
  discard buildZ3QueryEnvelope(lowered.smtScript, timeoutMs = 8000, sentinel = "PROBE",
                               enableProofs = false, mode = zmIncremental,
                               canonicalEnvelopeDigest = dInc)
  var dRawP = ""
  discard buildZ3QueryEnvelope(lowered.smtScript, timeoutMs = 8000, sentinel = "PROBE",
                               enableProofs = true, mode = zmRaw,
                               canonicalEnvelopeDigest = dRawP)
  var dIncP = ""
  discard buildZ3QueryEnvelope(lowered.smtScript, timeoutMs = 8000, sentinel = "PROBE",
                               enableProofs = true, mode = zmIncremental,
                               canonicalEnvelopeDigest = dIncP)
  echo "  digest zmRaw:          " & dRaw
  echo "  digest zmIncremental:  " & dInc
  echo "  digest zmRaw+proofs:   " & dRawP
  echo "  digest zmInc+proofs:   " & dIncP
  for obs in observed:
    if dRaw == obs:
      echo "  >>> MATCH with observed telemetry digest (zmRaw): " & obs
    if dInc == obs:
      echo "  >>> MATCH with observed telemetry digest (zmIncremental): " & obs
    if dRawP == obs:
      echo "  >>> MATCH with observed telemetry digest (zmRaw+proofs): " & obs
    if dIncP == obs:
      echo "  >>> MATCH with observed telemetry digest (zmInc+proofs): " & obs
  echo ""

echo "=== observed E2E digests (getBitsBE-specific, both result=sat) ==="
for obs in observed:
  echo "  " & obs
