# Base36 sizing binding — z3 boundary evidence (obligation_semantics.md §3.8)
#
# Subject: stew/base36.nim `encodedLength` / `decodedLength`. Fixture route:
# VERBATIM transcription of the two bodies (read from the nim-stew checkout,
# stew/base36.nim:55 and :60; the real extractors need the extraction pipeline):
#   encodedLength n  = (length * 277) div 179 + 1
#   decodedLength m  = (length * 179) div 277
# composed as the sizing roundtrip  decodedLength(encodedLength(n)) == n.
#
# Width commitments (docs/spec/base36_sizing_binding_contract.md:46): the
# domain bound is width-derived — 16-bit → 118, 32-bit → 7752648,
# 64-bit → 33297371974204966 (= the largest n with 277*n <= high(int64);
# at n+1 the intermediate is high(int64)+52).
#
# z3 verdicts, all via the repo's SolverAdapter on machinery-generated scripts
# (src/core/trusted/private/ir_to_smt_chunk3.nim, includeOverflowDefines=true):
#   1. full negated query (postcondition AND promoted overflow goals)
#      + int16 domain `0 <= n <= 118`  -> UNSAT: the solver DERIVES the
#      roundtrip and every overflow obligation from the precondition.
#   2. same query + int64 domain `0 <= n <= 33297371974204966` -> NOT sat
#      within the shipped deterministic budget (:rlimit 30000000); observed
#      status `unknown` (bit-blasting the chained constant-division identity
#      over 64 bits does not decide within budget — still undecided after
#      13 min with :rlimit 0; the 32-bit domain 7752648 is likewise unknown).
#      No z3 counterexample exists within the budget; the int64-width proof
#      is carried by the Lean kernel (Denotation.lean, `base36_roundtrip`).
#      Pinned here as a budget contract, not as proved.
#   3. same query with the precondition dropped -> SAT: the theorem is not
#      vacuous — the overflow region above MAX really is unprovable.

import std/[os, strutils]
import core/trusted/axiom_ir_helpers
import core/trusted/ir_to_smt
import verification/solver_adapter

proc resolveZ3(): string =
  let onPath = findExe("z3")
  if onPath.len > 0: onPath else: "<user-home>/.local/bin/z3"

proc main() =
  echo "=== Base36 Sizing Binding (z3 boundary evidence) ==="

  let bv64 = irTypeBitVec64()

  proc roundtripFunc(domainBound: int64): IRFuncDef =
    ## decodedLength(encodedLength(n)) as one IRFuncDef.
    ## domainBound > 0 asserts the width commitment `0 <= n <= domainBound`;
    ## 0 drops the precondition (unbounded query).
    let n = irVar("n", bv64)
    # encodedLength(n) = (n * 277) div 179 + 1
    let encLen = irAdd(irDiv(irMul(n, irLit(277)), irLit(179)), irLit(1))
    # decodedLength(encLen) = (encLen * 179) div 277
    var f = irFuncDef(
      name = "base36_sizing_roundtrip",
      params = @[("n", bv64)],
      ret = bv64,
      body = irDiv(irMul(encLen, irLit(179)), irLit(277))
    )
    f.postConditions = @[irEq(irVar("result", bv64), irVar("n", bv64))]
    if domainBound > 0:
      f.preConditions = @[irAnd(
        irGe(irVar("n", bv64), irLit(0)),
        irLe(irVar("n", bv64), irLit(domainBound))
      )]
    f

  # -- Block 1: script structure — goals not assumptions ---------------------
  block:
    let smt = irToSmtScript(roundtripFunc(33297371974204966'i64),
                            includeOverflowDefines = true)
    doAssert smt.contains("(not (and"),
      "the query must be a negated conjunction (postcondition AND goals)"
    doAssert smt.contains("no_overflow_mul") and smt.contains("no_underflow_mul"),
      "overflow/underflow goal conjuncts must be present"
    doAssert smt.contains("(assert (no_overflow_mul") == false and
      smt.contains("(assert (no_underflow_mul") == false,
      "overflow must never be emitted as an assumed fact"
    let domainHex = "#x" & toHex(33297371974204966'i64, 16)
    doAssert smt.contains("(assert (and (bvsge n #x0000000000000000) (bvsle n " & domainHex & ")))"),
      "the domain precondition (0 <= n <= MAX, signed) must be asserted, got: " & smt
    echo "  PASS: goal form + domain literal present, no assumed overflow"

  # -- Block 2: int16 width commitment -> UNSAT (proved) ----------------------
  block:
    let smt = irToSmtScript(roundtripFunc(118'i64), includeOverflowDefines = true)
    let adapter = newSolverAdapter(z3Path = resolveZ3(), timeoutMs = 120000,
                                   printCertificate = false)
    let outcome = adapter.solve(smt)
    doAssert outcome.status == sosUnsat,
      "with 0 <= n <= 118 the full negated query (roundtrip AND overflow goals) " &
        "must be UNSAT, got: " & $outcome.status & " diag: " & outcome.diagnostics
    echo "  PASS: int16 domain -> UNSAT (roundtrip + overflow goals derived from precondition)"

  # -- Block 3: int64 width commitment -> not sat within shipped budget -------
  block:
    let smt = irToSmtScript(roundtripFunc(33297371974204966'i64),
                            includeOverflowDefines = true)
    let adapter = newSolverAdapter(z3Path = resolveZ3(), timeoutMs = 120000,
                                   printCertificate = false)
    let outcome = adapter.solve(smt)
    doAssert outcome.status != sosSat,
      "a z3 counterexample within the shipped budget would refute the sizing " &
        "binding, got: " & $outcome.status
    doAssert outcome.status == sosUnknown,
      "observed budget-contract status is unknown (see header comment), got: " &
        $outcome.status
    echo "  PASS: int64 domain not sat within shipped budget (kernel proof is authority)"

  # -- Block 4: precondition dropped -> SAT (non-vacuity of the domain) -------
  block:
    let smt = irToSmtScript(roundtripFunc(0'i64), includeOverflowDefines = true)
    let adapter = newSolverAdapter(z3Path = resolveZ3(), timeoutMs = 120000,
                                   printCertificate = false)
    let outcome = adapter.solve(smt)
    doAssert outcome.status == sosSat,
      "without the domain precondition the negated query must be SAT (overflow " &
        "region above MAX), got: " & $outcome.status & " diag: " & outcome.diagnostics
    echo "  PASS: precondition dropped -> SAT (region above MAX is genuinely unprovable)"

  echo "=== base36 sizing binding OK ==="

main()
