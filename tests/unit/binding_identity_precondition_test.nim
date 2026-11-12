## binding_identity_precondition_test.nim
##
## Regression guard for the PRECONDITION that the binding-identity decision
## (docs/adr/0030-binding-identity-precondition.md) rests on.
##
## The decision argues that a lexical binding is identified by the SOURCE and
## that the IR already carries it, so Axiom needs no invented binding id. It
## also argues that name-uniqueness alone cannot carry that identity, because a
## scope the translator drops entirely leaves the IR showing a unique name for a
## source that shadowed it. That makes `translationLossFree` a LOAD-BEARING
## PRECONDITION of the uniqueness check, and the ordering
##
##     scope translation-loss-free?  ── no ──▶ reject (fail-closed)
##                              └── yes ──▶ unique letName? ──▶ nested SMT let
##
## the only ordering that cannot accept a lossy translation whose bindings were
## silently deleted.
##
## These cases assert the CURRENT behaviour, before the binding identity slice
## lands, so the implementation cannot silently move the precondition. They hold
## before AND after that change.
##
## 1. A source whose `block:` region the translator drops is NOT
##    translation-loss-free, and every candidate derived from it is rejected by
##    the census — never promoted, whatever the name shape of the surviving IR.
##    Two probes pin the loss itself: a `marker` probe whose block-local binding
##    has a name of its own shows that name disappearing from the IR, and a
##    `shadow` probe whose block-local binding reuses the outer name shows the
##    IR still reporting a single, therefore unique, binder.
## 2. A function whose IR carries a duplicated `letName` is rejected. Today it
##    is rejected by the catch-all `semantic.unresolved-fact` route, because
##    `collectFreeVars` (src/core/trusted/private/obligation_smt_lowering.nim:60-63)
##    treats every `irVar` as free and does not model binders, so a body-local
##    name counts as undeclared. The post-change expectation — that a dedicated
##    binding channel rejects it under its OWN reason instead of borrowing the
##    census token — is stated as a NAMED check that FAILS TODAY ON PURPOSE and
##    is reported in its own bucket, never folded into the pass/fail tally.
## 3. A binding whose RHS references a name the subject never declares keeps the
##    `semantic.unresolved-fact` rejection. The binding-identity slice changes
##    which names are IN SCOPE; it must not turn an unknown name into a bound one.
##
## Run: nim c -r --hints:off --warnings:off --nimcache:/tmp/bindident \
##          tests/unit/binding_identity_precondition_test.nim

import std/[macros, os, strutils, options]
import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/trusted/ast_to_ir
import core/trusted/axiom_pragmas
import verification/admissibility
import verification/cert_promotion
import verification/obligation/candidate_eligibility

const
  UnresolvedFactToken = $crrSemanticUnresolvedFact
    ## Census token for a meaning that is not determined at census time. Cases 1
    ## and 3 must keep producing exactly this string.

# ───────────────────────────────────────────────────────────────────────────
# Compile-time probes. convertFuncDef takes a compile-time NimNode, so a source
# fixture must be fed through a macro — the shape tests/unit/ast_to_ir_test.nim:272
# already establishes. Each probe returns its measurements as one `|`-separated
# string so the runtime asserts on observed output rather than a restated oracle.
# ───────────────────────────────────────────────────────────────────────────

macro shadowedBlockProbe(): untyped =
  ## Source (see the fixture below) declares TWO `x` bindings — one at proc scope,
  ## one inside `block:`. The translator has no `ckBlockStmt` arm
  ## (src/core/trusted/ast_to_ir.nim:1078-1143, else-branch :1134-1137), so the
  ## inner one is deleted and only `x` survives.
  let src = quote do:
    proc shadowedBlock(y: int): int =
      let x = 1
      block:
        let x = 2
        discard x
      result = x div y
  let fd = convertFuncDef(src)
  let entry = RuntimeAxiomEntry(
    name: "shadowedBlock", sourcePath: "subject/shadowed_block.nim",
    isKernel: false, effectKind: Pure, bmcSkippable: false,
    expectedObligation: false)
  let rec = classifyCandidateForCensus(entry, fd)
  let census = buildCandidacyCensus(@[rec])
  result = newStrLitNode(
    $fd.translationLossFree & "|" &
    collectLetNames(fd.body).join(",") & "|" &
    $rec.eligibility & "|" &
    $rec.censusEligible & "|" &
    rejectionToken(rec.rejection) & "|" &
    $rec.generatedObligationCount & "|" &
    $rec.nonTrivialObligationCount & "|" &
    $census.terminal & "|" &
    $census.proofCandidateCount)

macro markerBlockProbe(): untyped =
  ## Same shape, but the block-local binding has a name of its own. Its
  ## disappearance from the IR is the direct evidence that the block region was
  ## dropped rather than merely renamed.
  let src = quote do:
    proc markerBlock(y: int): int =
      let x = 1
      block:
        let innerMarker = 2
        discard innerMarker
      result = x div y
  let fd = convertFuncDef(src)
  result = newStrLitNode($fd.translationLossFree & "|" &
                         collectLetNames(fd.body).join(","))

macro blockFreeControlProbe(): untyped =
  ## Same subject WITHOUT the block. A plain `let` at proc scope survives, so the
  ## loss in the block probes is attributable to the dropped region and not to
  ## the presence of a binding at all.
  let src = quote do:
    proc blockFree(y: int): int =
      let x = 1
      result = x div y
  let fd = convertFuncDef(src)
  result = newStrLitNode($fd.translationLossFree & "|" &
                         collectLetNames(fd.body).join(","))

proc main() =
  var passed = 0
  var failed = 0
  var pendingFails = 0
  var staleMarkers = 0

  ## Non-aborting: every check runs and is reported, so one failure never hides
  ## the state of the others.
  template check(name: string, cond: untyped) =
    block:
      if (cond):
        inc passed
        echo "  PASS: " & name
      else:
        inc failed
        echo "  FAIL: " & name

  ## Post-change expectations that CANNOT hold yet. Reported in their own bucket
  ## so an unimplemented binding channel never reads as a green suite, and never
  ## flips the exit code either — these are declared-unimplemented, not broken.
  ## If one ever goes green the binding channel has landed and the marker is
  ## stale, which counts as a failure of the marker itself.
  template pendingCheck(name: string, cond: untyped) =
    block:
      if (cond):
        inc staleMarkers
        echo "  STALE-MARKER: " & name &
             " — already green; the binding channel landed, retire this marker"
      else:
        inc pendingFails
        echo "  PENDING-FAIL: " & name &
             " — not implemented yet (turns green with the binding-identity slice)"

  func censusEntry(name: string): RuntimeAxiomEntry =
    RuntimeAxiomEntry(
      name: name,
      sourcePath: "subject/" & name & ".nim",
      isKernel: false,
      effectKind: Pure,
      bmcSkippable: false,
      expectedObligation: false)

  # ══════════════════════════════════════════════════════════════════════════
  echo "=== 1. translation-loss-free is a precondition, not a report ==="
  # ══════════════════════════════════════════════════════════════════════════
  block:
    let shadow = shadowedBlockProbe().split('|')
    let marker = markerBlockProbe().split('|')
    let control = blockFreeControlProbe().split('|')

    check "a block-local binding is deleted outright (marker name absent from the IR)",
      marker[1] == "x"
    check "the deletion marks the function translation-loss-free = false",
      marker[0] == "false"
    check "control without the block stays translation-loss-free and keeps its binding",
      control[0] == "true" and control[1] == "x"

    check "shadowing source: the function is translation-loss-free = false",
      shadow[0] == "false"
    check "shadowing source: the IR carries a single, therefore unique, binding name",
      shadow[1] == "x"
    check "shadowing source: name-uniqueness ALONE would therefore admit this candidate",
      shadow[1].split(',').len == 1

    check "base eligibility accepts the candidate (so rule S is the only gate left)",
      shadow[2] == $elProofCandidate
    check "the candidate really does carry exactly one non-trivial obligation",
      shadow[5] == "1" and shadow[6] == "1"
    check "lossy translation ⇒ not census-eligible",
      shadow[3] == "false"
    check "lossy translation ⇒ rejected with semantic.unresolved-fact",
      shadow[4] == UnresolvedFactToken
    check "lossy translation ⇒ census terminal is NO_ELIGIBLE_OBLIGATION",
      shadow[7] == CensusTerminalNoEligibleObligation
    check "lossy translation ⇒ zero proof candidates survive",
      shadow[8] == "0"

  # ══════════════════════════════════════════════════════════════════════════
  echo ""
  echo "=== 2. duplicated letName is rejected ==="
  # ══════════════════════════════════════════════════════════════════════════
  block:
    let bv = irTypeBitVec64()
    var dupDef = irFuncDef("dup_let_name", @[("y", bv)], bv,
      irLet("x", irLit(1),
        irLet("x", irVar("y", bv), irDiv(irVar("y", bv), irVar("x", bv)))),
      false)
    dupDef.bindingUniverseComplete = true

    let dupNames = collectLetNames(dupDef.body)

    check "fixture really does carry a duplicated letName",
      dupNames.len == 2 and dupNames[0] == "x" and dupNames[1] == "x"
    check "fixture scope is reported translation-loss-free (the case name-uniqueness must catch)",
      dupDef.translationLossFree

    let rec = classifyCandidateForCensus(censusEntry("dup_let_name"), dupDef)
    check "duplicate letName ⇒ base eligibility still accepts the candidate",
      rec.eligibility == elProofCandidate
    check "duplicate letName ⇒ the obligation is non-trivial",
      rec.nonTrivialObligationCount > 0
    check "duplicate letName ⇒ not census-eligible",
      rec.censusEligible == false
    check "duplicate letName ⇒ today's rejection reason is semantic.unresolved-fact",
      rec.rejection == some(crrSemanticUnresolvedFact)

    let census = buildCandidacyCensus(@[rec])
    check "duplicate letName ⇒ the census terminal is NO_ELIGIBLE_OBLIGATION",
      census.terminal == CensusTerminalNoEligibleObligation
    check "duplicate letName ⇒ zero proof candidates survive",
      census.proofCandidateCount == 0

    pendingCheck "post-change: a duplicated letName is rejected by the binding " &
                 "channel itself, not re-labelled semantic.unresolved-fact",
      rejectionToken(rec.rejection) != UnresolvedFactToken

  # ══════════════════════════════════════════════════════════════════════════
  echo ""
  echo "=== 3. unknown name in a binding RHS keeps the unresolved-fact rejection ==="
  # ══════════════════════════════════════════════════════════════════════════
  block:
    let bv = irTypeBitVec64()
    var unknownDef = irFuncDef("unknown_rhs", @[("y", bv)], bv,
      irLet("x", irVar("unknownBits", bv),
        irDiv(irVar("y", bv), irVar("unknownBits", bv))),
      false)
    unknownDef.bindingUniverseComplete = true

    check "fixture declares only y, so unknownBits is genuinely undeclared",
      unknownDef.params.len == 1 and unknownDef.params[0].name == "y"

    let rec = classifyCandidateForCensus(censusEntry("unknown_rhs"), unknownDef)
    check "unknown name in the binding RHS ⇒ base eligibility still accepts",
      rec.eligibility == elProofCandidate
    check "unknown name in the binding RHS ⇒ the obligation is non-trivial",
      rec.nonTrivialObligationCount > 0
    check "unknown name in the binding RHS ⇒ rejected with semantic.unresolved-fact",
      rec.rejection == some(crrSemanticUnresolvedFact)
    check "unknown name in the binding RHS ⇒ not census-eligible",
      rec.censusEligible == false

    let census = buildCandidacyCensus(@[rec])
    check "unknown name ⇒ the census terminal is NO_ELIGIBLE_OBLIGATION",
      census.terminal == CensusTerminalNoEligibleObligation
    check "unknown name ⇒ zero proof candidates survive",
      census.proofCandidateCount == 0

  echo ""
  echo "=== Results: " & $passed & " passed, " & $failed & " failed ==="
  echo "=== Declared-unimplemented: " & $pendingFails & " pending, " &
       $staleMarkers & " stale ==="
  if failed > 0:
    quit(1)
  if staleMarkers > 0:
    quit(1)
  if pendingFails > 0:
    echo "(pending checks are declared-unimplemented, not regressions — they do " &
         "not affect the exit code)"
  echo "ALL CHECKS PASSED"

main()