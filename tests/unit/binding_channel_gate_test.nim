## binding_channel_gate_test.nim
##
## The binding channel's eligibility gate: which subjects reach the census as
## proof candidates once a binding's defining expression — rather than the whole
## function — is what has to be faithful.
##
## The gate is four ordered checks, and the order is the subject of this file:
##
##   (a) proposition region loss-free  → reject
##   (b) binding RHS loss-free          → reject
##   (c) free var resolvable           → reject semantic.unresolved-fact
##   (d) no duplicated binding name     → reject
##
## (a) before (d) is load-bearing and is what fixture 3 pins: `ckBlockStmt` has
## no case arm, so `let d = y; block: let d = 2` reaches the IR with the inner
## binding DELETED and the surviving `d` looking unique. Uniqueness alone would
## admit that source. Only (a) rejects it, because the dropped statement is
## exactly what made the name look unique.
##
## Every fixture is translated through the census's own pipeline
## (parseStringAST → pnodeToCanon → axiomBodyCanon), so the IR the gate sees is
## the IR the census would see. Assertions are on eligibility outcomes and on
## the gate's own verdict — never on lowered SMT text, which another workstream
## owns.
##
## Run: nim c -r --hints:off --warnings:off --nimcache:/tmp/bindchan \
##          tests/unit/binding_channel_gate_test.nim

import std/[json, options, sequtils, strutils]
import compiler/ast
import core/parser_utils
import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/trusted/ast_to_ir
import core/trusted/pnode_to_canon
import core/trusted/axiom_pragmas
import verification/obligation/candidate_eligibility
import verification/obligation/canonical_obligation_generator
import verification/obligation/obligation_ir
import verification/obligation/obligation_types

proc findProcDef(root: PNode; name: string): PNode =
  ## First `proc`/`func` named `name`, including the `*` export postfix form.
  if root.isNil: return nil
  if root.kind == nkProcDef and root.len > 0:
    let head = root[0]
    if head.kind == nkIdent and head.ident.s == name: return root
    if head.kind == nkPostfix and head.len > 1 and head[1].kind == nkIdent and
       head[1].ident.s == name:
      return root
  for i in 0 ..< root.len:
    let found = findProcDef(root[i], name)
    if not found.isNil: return found
  nil

proc irOf(name, source: string): IRFuncDef =
  axiomBodyCanon(pnodeToCanon(findProcDef(parseStringAST(source), name)))

proc entryFor(name: string): RuntimeAxiomEntry =
  RuntimeAxiomEntry(name: name, sourcePath: "subject/" & name & ".nim",
                    isKernel: false, effectKind: Pure, bmcSkippable: false,
                    expectedObligation: false)

proc verdictOf(fd: IRFuncDef): BindingUniverseVerdict =
  let gen = generateCanonicalObligations(fd, defaultScopePolicy())
  if gen.kind != ogrGenerated:
    # No obligation set means no semantic universe to resolve; the census rejects
    # such a candidate on the base class long before rule S.
    return buvResolved
  bindingUniverseVerdict(fd, gen.obligations.items)

const
  # Faithful everywhere; the obligation's free variable is a declared parameter.
  ControlSource = """
proc gateControl(y: int): int =
  let x = y
  result = x div y
"""

  # The obligation's divisor is a body-local binding, and the function is lossy
  # in an expression that is neither a binding region nor a guard. The lossy
  # operand is a layout intrinsic: parenthesized operands now translate
  # faithfully (the ckPar arm), but `sizeof` is marked loss and preserved as an
  # irCall this IR cannot evaluate.
  ScopedLossSource = """
proc gateScoped(y: int): int =
  let d = y + 1
  result = y div d + sizeof(y)
"""

  # The same loss, inside a binding's defining expression.
  LossyBindingSource = """
proc gateLossyBinding(y: int): int =
  let d = sizeof(y)
  result = y div d
"""

  # Shadowing across a dropped statement: the inner `d` never reaches the IR.
  ShadowedSource = """
proc gateShadow(y: int): int =
  let d = y
  block:
    let d = 2
    discard d
  result = y div d
"""

  # One name, two source bindings, both reaching the IR.
  DuplicateNameSource = """
proc gateDuplicate(y: int): int =
  let d = y
  let d = y + 1
  result = y div d
"""

  # A binding that reads a name the subject never declares.
  UnknownRhsSource = """
proc gateUnknown(y: int): int =
  let d = y
  let e = d + unknownBits
  result = y div e
"""

  # A chain of bindings: the obligation names the last one, whose RHS names the
  # middle one, whose RHS names the parameter.
  TransitiveChainSource = """
proc gateChain(y: int): int =
  let a = y
  let b = a + 1
  let c = b + 1
  result = y div c
"""

proc main() =
  var passed = 0
  var failed = 0

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

  let control = irOf("gateControl", ControlSource)
  let scoped = irOf("gateScoped", ScopedLossSource)
  let lossyBinding = irOf("gateLossyBinding", LossyBindingSource)
  let shadowed = irOf("gateShadow", ShadowedSource)
  let duplicated = irOf("gateDuplicate", DuplicateNameSource)
  let unknown = irOf("gateUnknown", UnknownRhsSource)
  let chained = irOf("gateChain", TransitiveChainSource)

  echo "=== 1. (a) proposition region ==="
  block:
    check "control: no region was dropped", control.propositionRegionLossFree
    check "scoped: a loss outside the regions does NOT fail (a)",
      scoped.propositionRegionLossFree
    check "scoped: the function is genuinely lossy",
      not scoped.translationLossFree
    check "lossy binding region does not fail (a) — that is (b)'s job",
      lossyBinding.propositionRegionLossFree
    check "a dropped statement fails (a)", not shadowed.propositionRegionLossFree
    check "shadowed fixture really does show a single, therefore unique, name",
      shadowed.recordedBindings.len == 1 and
      shadowed.recordedBindings[0].name == "d"
  echo ""
  echo "=== 2. (b) binding defining expressions ==="
  block:
    check "control: bindings are loss-free",
      control.recordedBindings.len > 0 and
      control.recordedBindings.allIt(it.lossFree)
    check "scoped: every binding is loss-free", scoped.recordedBindings.allIt(it.lossFree)
    check "lossy binding: recorded as lossy, not omitted",
      lossyBinding.recordedBindings.len == 1 and
      not lossyBinding.recordedBindings[0].lossFree
    check "lossy binding → verdict (b)",
      verdictOf(lossyBinding) == buvLossyBindingRegion
  echo ""
  echo "=== 3. (c) transitive closure over params ∪ bindings ==="
  block:
    check "control: obligation free vars are declared",
      verdictOf(control) == buvResolved
    check "a body-local binding name now resolves",
      verdictOf(scoped) == buvResolved
    check "a chain of bindings resolves transitively",
      verdictOf(chained) == buvResolved
    check "a binding whose RHS names an unknown name does not resolve",
      verdictOf(unknown) == buvUnresolvedName
    check "and the census keeps the semantic.unresolved-fact token for it",
      classifyCandidateForCensus(entryFor("gateUnknown"), unknown).rejection ==
        some(crrSemanticUnresolvedFact)
  echo ""
  echo "=== 4. (d) duplicated binding name ==="
  block:
    check "the fixture really does carry one name twice",
      duplicated.recordedBindings.len == 2 and
      duplicated.recordedBindings[0].name == duplicated.recordedBindings[1].name
    check "a duplicated name → verdict (d)",
      verdictOf(duplicated) == buvAmbiguousBindingName
    check "a duplicated name is rejected, not admitted",
      classifyCandidateForCensus(entryFor("gateDuplicate"), duplicated).censusEligible ==
        false
    check "the translator lost nothing here — the gate catches it, not the translator",
      duplicated.translationLossFree and
      verdictOf(duplicated) == buvAmbiguousBindingName
  echo ""
  echo "=== 5. (a) is what rejects the shadowed source ==="
  block:
    check "shadowing source → verdict (a), reached before (d)",
      verdictOf(shadowed) == buvLossyPropositionRegion
    check "shadowing source → not census-eligible",
      classifyCandidateForCensus(entryFor("gateShadow"), shadowed).censusEligible ==
        false
    check "shadowing source keeps the semantic.unresolved-fact token",
      classifyCandidateForCensus(entryFor("gateShadow"), shadowed).rejection ==
        some(crrSemanticUnresolvedFact)
  echo ""
  echo "=== 6. eligibility outcome and honest coverage ==="
  block:
    let controlRec = classifyCandidateForCensus(entryFor("gateControl"), control)
    let scopedRec = classifyCandidateForCensus(entryFor("gateScoped"), scoped)
    check "control is census-eligible", controlRec.censusEligible
    check "control reports a COMPLETE obligation set",
      controlRec.obligationSetComplete
    check "a function lossy outside the certified regions is still eligible",
      scopedRec.censusEligible
    check "…and reports its obligation set as INCOMPLETE",
      not scopedRec.obligationSetComplete
    check "…and carries no rejection token — coverage is not a rejection",
      scopedRec.rejection == none(CandidateRejectionReason)
    check "the generated obligation is real, not zero",
      scopedRec.nonTrivialObligationCount > 0

    let census = buildCandidacyCensus(@[controlRec, scopedRec])
    check "both reach the census terminal CANDIDATE_SELECTED_FOR_PROOF",
      census.terminal == CensusTerminalCandidateSelected
    check "the census counts exactly one coverage-limited candidate",
      census.coverageLimitedCount == 1
    check "proof candidate count counts both",
      census.proofCandidateCount == 2

    let json = censusToJson(census)
    check "the per-candidate coverage flag is on the wire",
      json["candidates"][1]["obligationSetComplete"].getBool == false or
      json["candidates"][0]["obligationSetComplete"].getBool == false
    check "the aggregate coverage count is on the wire",
      json["coverageLimitedCount"].getInt == 1
  echo ""
  echo "=== 7. obligation identity does not move with the evidence ==="
  block:
    var mutated = scoped
    mutated.recordedBindings = @[IRBinding(name: "invented", value: irLit(7),
                                          anchor: "stmt[9]/let",
                                          isCompileTime: true, lossFree: false)]
    mutated.propositionRegionLossFree = false
    mutated.lossOutsideBindingRegions = true
    let before = generateCanonicalObligations(scoped, defaultScopePolicy())
    let after = generateCanonicalObligations(mutated, defaultScopePolicy())
    check "the obligation set has the same size",
      before.obligations.items.len == after.obligations.items.len
    var sameIds = before.obligations.items.len > 0
    for i in 0 ..< before.obligations.items.len:
      if before.obligations.items[i].id != after.obligations.items[i].id:
        sameIds = false
    check "every obligation keeps its identity under different evidence", sameIds
    check "IR digest unchanged",
      computeIrDigest(scoped) == computeIrDigest(mutated)
  echo ""

  echo "=== Results: " & $passed & " passed, " & $failed & " failed ==="
  if failed > 0:
    quit(1)
  echo "ALL CHECKS PASSED"

main()