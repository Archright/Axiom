import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

import std/unittest
import std/[strutils, options, sequtils, algorithm, tables, sets, os]
import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/axiom_pragmas
import core/parser_utils
import core/trusted/pnode_to_canon
import core/trusted/ast_to_ir
import core/crypto/hash_kernel
import infrastructure/external_ir_materializer
import verification/batch_uap/ir_pipeline_runner
import verification/obligation/candidate_eligibility
import verification/obligation/canonical_obligation_generator
import core/sorter/sorter_core_index_base
import cli/frontier_selection

setExternalSubjectMode(true)

# ---------------------------------------------------------------------------
# Synthetic Nim source fixtures
# ---------------------------------------------------------------------------

# Test 3, 6, 7, 8: a single pure func with no postconditions → elNoObligation
const SourceSingleFunc = """
func decodedLength(s: string): int =
  let n = s.len
  n + 1
"""

# Test 2: two defs of the same function name → ambiguous overload
const SourceAmbiguousOverload = """
func process(x: int): int =
  x + 1

func process(x: string): string =
  x & "done"
"""

# Test 3: a simple function with no postconditions → elNoObligation
# (irMul body → ogrNoApplicableObligation → elNoObligation)
const SourceNoObligation = """
func double(a: int): int =
  a * 2
"""

# Test 1 & 4: a function with division → generates okSafetyDiv → elProofCandidate
const SourceProofCandidateFunc = """
func divide(a, b: int): int =
  a div b
"""

# Test 5: same source used for cache vs file fallback comparison
const SourceForCacheTest = """
func addOne(x: int): int =
  x + 1
"""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func makeSymRef*(relativeModulePath, functionName: string): SubjectSymbolRef =
  SubjectSymbolRef(relativeModulePath: relativeModulePath, functionName: functionName)

func resolverFromContent*(content: string): ModuleContentResolver =
  proc(m: string): Option[string] {.raises: [], noSideEffect.} =
    some(content)

func computeRegistryDigest*(entries: seq[RuntimeAxiomEntry]): string =
  ## 7-field recipe: (name, irSerialized, sourcePath, isKernel, effectKind,
  ## bmcSkippable, origin), sorted by (name, sourcePath), concat, sha256Hex.
  var tuples: seq[string] = @[]
  for e in entries:
    tuples.add(e.name & "|" & e.irSerialized & "|" & e.sourcePath & "|" &
               $e.isKernel & "|" & $e.effectKind & "|" & $e.bmcSkippable & "|" & $e.origin)
  tuples.sort()
  sha256Hex(tuples.join(""))

# ---------------------------------------------------------------------------
# Suite
# ---------------------------------------------------------------------------

suite "External IR Materializer — regression tests":

  # ===================================================================
  # Test 1: Positive — Admission Anchor (division function → elProofCandidate)
  # ===================================================================
  test "T1: materializeSingleFunc → moMaterialized, elProofCandidate, admitted by selectProofCandidates":
    let resolver = resolverFromContent(SourceProofCandidateFunc)
    let symRef = makeSymRef("stew/base36.nim", "divide")
    let (outcome, entry) = materializeExternalIR(symRef, resolver)

    check outcome == moMaterialized
    check entry.entry.name == "divide"
    check entry.entry.irSerialized.len > 0
    check entry.entry.origin == soExternalSubject
    check entry.entry.isKernel == false

    # Classification must be elProofCandidate
    let eligibility = classifyCandidateEligibility(entry.entry, entry.funcDef)
    check eligibility == elProofCandidate

    # Through selectProofCandidates with externalCandidates → admitted
    let extCandidates = @[entry]
    let candidates = selectProofCandidates(10, 1, "1.0", initHashSet[string](), extCandidates)
    check candidates.len >= 1
    let found = candidates.anyIt(it.entry.name == "divide" and it.entry.origin == soExternalSubject)
    check found == true

  # ===================================================================
  # Test 2: Ambiguous — two overloads same name
  # ===================================================================
  test "T2: two overloads same name → moAmbiguousOverload, excluded from selectProofCandidates":
    let resolver = resolverFromContent(SourceAmbiguousOverload)
    let symRef = makeSymRef("stew/base36.nim", "process")
    let (outcome, entry) = materializeExternalIR(symRef, resolver)

    check outcome == moAmbiguousOverload

    # No entry should be produced; externalCandidates with default entry must not be admitted
    let extCandidates = @[entry]
    let candidates = selectProofCandidates(10, 1, "1.0", initHashSet[string](), extCandidates)
    # The default ExternalIrEntry has empty entry/funcDef — it should not pass eligibility
    check candidates.len == 0

  # ===================================================================
  # Test 3: Negative — elNoObligation
  # ===================================================================
  test "T3: function with elNoObligation classification → excluded from proof candidates":
    # Use a hand-crafted IRFuncDef that we know classifies as elNoObligation
    # (irMul body, no postconditions → ogrNoApplicableObligation → elNoObligation).
    let x = irVar("x", irTypeBitVec64())
    let y = irVar("y", irTypeBitVec64())
    let body = irMul(x, y)
    let funcDef = irFuncDef("double", @[("x", irTypeBitVec64()), ("y", irTypeBitVec64())], irTypeBitVec64(), body, false)
    let serialized = serializeIRFuncDef(funcDef)

    let entry = RuntimeAxiomEntry(
      name: "double",
      irSerialized: serialized,
      sourcePath: "stew/base36.nim",
      isKernel: false,
      effectKind: Pure,
      bmcSkippable: false,
      origin: soExternalSubject,
      expectedObligation: false
    )
    let eligibility = classifyCandidateEligibility(entry, funcDef)
    check eligibility == elNoObligation

    # Through selectProofCandidates → excluded (not elProofCandidate)
    let extIrEntry = ExternalIrEntry(entry: entry, funcDef: funcDef)
    let candidates = selectProofCandidates(10, 1, "1.0", initHashSet[string](), @[extIrEntry])
    let found = candidates.anyIt(it.entry.name == "double")
    check found == false

  # ===================================================================
  # Test 4: P-B0 parity (registered vs materialized)
  # ===================================================================
  test "T4: registered-style IR digest == materializer's synthesized entry IR digest":
    # Path (a): parse source → pnodeToCanon → axiomBodyCanon → serializeIRFuncDef
    let ast = parseStringAST(SourceProofCandidateFunc)
    check not ast.isNil
    let defNode = findFuncDefP(ast, "divide", "")
    check not defNode.isNil
    let canonNode = pnodeToCanon(defNode)
    let irFuncDefA = axiomBodyCanon(canonNode)
    let serA = serializeIRFuncDef(irFuncDefA)

    # Path (b): materializeExternalIR
    let resolver = resolverFromContent(SourceProofCandidateFunc)
    let symRef = makeSymRef("stew/base36.nim", "divide")
    let (outcome, entryB) = materializeExternalIR(symRef, resolver)
    check outcome == moMaterialized
    let serB = entryB.entry.irSerialized

    # irSerialized bytes must be equal
    check serA == serB

    # Eligibility must be identical
    let eligA = classifyCandidateEligibility(entryB.entry, entryB.funcDef)
    check eligA == elProofCandidate

  # ===================================================================
  # Test 5: resolver owns source location (WP4-a B-5b)
  # ===================================================================
  test "T5: resolver cache (Some) vs subject-rooted disk resolver → identical irSerialized; no CWD fallback":
    let tmpRoot = getTempDir() / "wpp_base36_root"
    createDir(tmpRoot)
    let relPath = "stew/base36_test.nim"
    let tmpAbs = tmpRoot / relPath
    createDir(parentDir(tmpAbs))
    writeFile(tmpAbs, SourceForCacheTest)
    let symRef = makeSymRef(relPath, "addOne")
    try:
      # Cache path: resolver returns Some(content)
      let cacheResolver = resolverFromContent(SourceForCacheTest)
      let (outcomeCache, entryCache) = materializeExternalIR(symRef, cacheResolver)
      check outcomeCache == moMaterialized

      # Subject-rooted disk resolver: owns tmpRoot, resolves relPath against it.
      # The resolver (NOT the materializer) decides source location.
      let diskResolver: ModuleContentResolver = proc(m: string): Option[string] {.raises: [], axiomEffect: IOEffect.} =
        try:
          if fileExists(tmpRoot / m):
            let content = readFile(tmpRoot / m)
            if content.len > 0:
              return some(content)
        except CatchableError:
          discard  # axiom:best-effort(read failure → fall through to none → moParseFailure)
        none(string)
      let (outcomeDisk, entryDisk) = materializeExternalIR(symRef, diskResolver)
      check outcomeDisk == moMaterialized

      # irSerialized must be identical across both acquisition paths
      check entryCache.entry.irSerialized == entryDisk.entry.irSerialized
      check entryCache.funcDef.name == entryDisk.funcDef.name

      # Entry must carry the resolver's bytes verbatim. The sentinel resolver
      # below returns content that exists ONLY in memory — the on-disk
      # tmpAbs file does not contain it — so equality proves the bytes came
      # from the resolver's return value, not from a re-read of the path.
      let sentinelResolver = resolverFromContent(SourceForCacheTest & "\n# resolver-sentinel\n")
      let (outcomeSentinel, entrySentinel) = materializeExternalIR(symRef, sentinelResolver)
      check outcomeSentinel == moMaterialized
      check entrySentinel.entry.sourceContent == SourceForCacheTest & "\n# resolver-sentinel\n"
      check readFile(tmpAbs) == SourceForCacheTest  # sentinel absent on disk
      check entrySentinel.entry.sourceContent != readFile(tmpAbs)
      # Both acquisition paths carry their own resolver's content.
      check entryCache.entry.sourceContent == SourceForCacheTest
      check entryDisk.entry.sourceContent == SourceForCacheTest

      # A resolver returning none → moParseFailure.  There is NO getCurrentDir()
      # based readFile fallback inside the materializer (WP4-a B-5b invariant).
      let noneResolver: ModuleContentResolver = proc(m: string): Option[string] {.raises: [], axiomEffect: IOEffect.} =
        none(string)
      let (outcomeNone, _) = materializeExternalIR(symRef, noneResolver)
      check outcomeNone == moParseFailure
    finally:
      removeFile(tmpAbs)
      removeDir(tmpRoot)

  # ===================================================================
  # Test 6: effectKind policy-assertion negatives
  # ===================================================================
  test "T6: synthesizeExternalEntry negatives — isKernel=false, origin=soExternalSubject, elNoObligation excluded":
    let symRef = makeSymRef("stew/base36.nim", "testFn")
    let funcDef = irFuncDef("testFn", @[("x", irTypeBitVec64())], irTypeBitVec64(), irLit(42), false)
    let entry = synthesizeExternalEntry(symRef, funcDef)

    # N1: isKernel must be false
    check entry.isKernel == false

    # N3: origin must be soExternalSubject (can't masquerade as kernel)
    check entry.origin == soExternalSubject

    # N2: classifyCandidateEligibility must NOT be elProofCandidate for a noObligation shape
    # (irLit body with no postconditions → ogrNoApplicableObligation → elNoObligation)
    let eligibility = classifyCandidateEligibility(entry, funcDef)
    check eligibility == elNoObligation

    # Verify it's excluded from selectProofCandidates
    let extIrEntry = ExternalIrEntry(entry: entry, funcDef: funcDef)
    let candidates = selectProofCandidates(10, 1, "1.0", initHashSet[string](), @[extIrEntry])
    let found = candidates.anyIt(it.entry.name == "testFn")
    check found == false

  # ===================================================================
  # Test 7: Registry isolation
  # ===================================================================
  test "T7: selectProofCandidates with external candidates does NOT mutate runtimeAxiomRegistry digest":
    # Snapshot registry digest before
    let digestBefore = computeRegistryDigest(runtimeAxiomRegistry)

    # Run selectProofCandidates with external candidates
    let symRef = makeSymRef("stew/base36.nim", "decodedLength")
    let resolver = resolverFromContent(SourceSingleFunc)
    let (outcome, entry) = materializeExternalIR(symRef, resolver)
    check outcome == moMaterialized

    let extCandidates = @[entry]
    let _ = selectProofCandidates(10, 1, "1.0", initHashSet[string](), extCandidates)

    # Snapshot registry digest after
    let digestAfter = computeRegistryDigest(runtimeAxiomRegistry)

    # Registry must be unchanged
    check digestBefore == digestAfter

  # ===================================================================
  # Test 8: Transient determinism
  # ===================================================================
  test "T8: materialize same symbol twice → same IR digest and eligibility; order independence":
    let symRef = makeSymRef("stew/base36.nim", "decodedLength")
    let resolver = resolverFromContent(SourceSingleFunc)

    let (outcome1, entry1) = materializeExternalIR(symRef, resolver)
    let (outcome2, entry2) = materializeExternalIR(symRef, resolver)

    check outcome1 == moMaterialized
    check outcome2 == moMaterialized

    # Same canonical candidate IDs / IR digest / eligibility
    check entry1.entry.irSerialized == entry2.entry.irSerialized
    check entry1.funcDef.name == entry2.funcDef.name
    check classifyCandidateEligibility(entry1.entry, entry1.funcDef) ==
          classifyCandidateEligibility(entry2.entry, entry2.funcDef)

    # Discovery order independence: call with candidates in different orders → same final sorted result
    let ext1 = @[entry1]
    let ext2 = @[entry2]
    let result1 = selectProofCandidates(10, 1, "1.0", initHashSet[string](), ext1)
    let result2 = selectProofCandidates(10, 1, "1.0", initHashSet[string](), ext2)

    check result1.len == result2.len
    if result1.len > 0 and result2.len > 0:
      check result1[0].entry.irSerialized == result2[0].entry.irSerialized

  # ===================================================================
  # Test 9: exact-target semantics (frontier_selection)
  # ===================================================================
  test "T9: selectFrontierNodes — exact mod::fn match, no match fallback, ambiguous fail-closed":
    # Build synthetic frontier with nodes
    let nodeA = sorterNodeId("modA::fnA")
    let nodeB = sorterNodeId("modB::fnB")

    let frontier = @[nodeA, nodeB]

    # nodeFnIdx and nodeModuleIdx maps
    var fnIdx: Table[string, string]
    var modIdx: Table[string, string]
    fnIdx["modA::fnA"] = "fnA"
    modIdx["modA::fnA"] = "modA"
    fnIdx["modB::fnB"] = "fnB"
    modIdx["modB::fnB"] = "modB"

    # Eligibility check: fnA in modA is eligible, fnB in modB is not
    let isEligible: FrontierEligibilityCheck = proc(fnName, modulePath: string): bool {.raises: [].} =
      fnName == "fnA" and modulePath == "modA"

    # (i) Unique exact mod::fn → 1 selected
    let target1 = "modA::fnA"
    let result1 = selectFrontierNodes(frontier, target1, fnIdx, modIdx, 10, isEligible)
    check result1.len == 1
    check sorterNodeIdString(result1[0]) == "modA::fnA"

    # (ii) No match → canonical NotFound (fail-closed, empty selection — WP4-e contract)
    let target2 = "modC::fnC"
    let result2 = selectFrontierNodes(frontier, target2, fnIdx, modIdx, 10, isEligible)
    check result2.len == 0

    # (iii) Legacy bare-name substring match → matched subset, then eligibility gate
    # (non-canonical path preserved; ambiguous multi-node bare-name is NOT fail-closed)
    let nodeD = sorterNodeId("modC::fnA")
    fnIdx["modC::fnA"] = "fnA"
    modIdx["modC::fnA"] = "modC"
    let frontierAmbiguous = @[nodeA, nodeD]

    let result3 = selectFrontierNodes(frontierAmbiguous, "fnA", fnIdx, modIdx, 10, isEligible)
    # Bare name "fnA" substring-matches 2 nodes; the eligibility gate then
    # keeps only modA::fnA, so exactly 1 remains.
    check result3.len == 1
    check sorterNodeIdString(result3[0]) == "modA::fnA"
