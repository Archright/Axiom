## WP4-h-2 — Read-only Obligation → SMT Lowering Localization Probe
##
## Purpose (read-only, NO code modification, NO production API call):
## Answer the single WP4-h-2 question for Anchor #1 (`getBitsBE`):
##   "Does the already-existing intrinsic safety obligation
##    okSafetyDiv(resultBits != 0) deterministically lower into a
##    canonical SMT proof goal?"
##
## Measurement funnel, per step:
##   Intrinsic obligation (canonical)  ->  VerificationObligation.predicate
##   Canonical proposition             ->  non-empty predicate string?
##   SMT expression                    ->  irToSmtScript (production path)
##                                        vs irToSmtWithObligations (existing
##                                        non-gating lowerer)
##   SMT script                        ->  empty / non-empty, per path
##
## It distinguishes:
##   A. lowering IS possible (obligation->SMT works when the non-gating
##      path is used)  -> the production gate is the boundary
##   B. lowering is semantically impossible (IR cannot carry the term)
##   C. the proposition itself is malformed (obligation synthesis defect)
##
## NOT a production path. Does not modify Axiom. Does not modify subject.

import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [].}

import std/[os, strutils, json, tables, options, sets, hashes, algorithm, sequtils]
import core/crypto/hash_kernel
import compiler/ast
import core/parser_utils
import core/parsers/pnode_nav
import core/logic/smt_logic
import core/trusted/ast_to_ir
import core/trusted/pnode_to_canon
import core/trusted/axiom_ir
import core/trusted/axiom_pragmas
import core/trusted/contract_synthesis
import core/trusted/axiom_ir
import core/trusted/ir_to_smt
import verification/obligation/canonical_obligation_generator
import verification/obligation/obligation_ir
import verification/obligation/obligation_types

# ---------------------------------------------------------------------------
# Ingestion (reuses wp4h1 probe pattern)
# ---------------------------------------------------------------------------

proc getProcName(nameNode: PNode): string =
  ## Extract a stable procedure name from the def node's name node.
  if nameNode == nil: return ""
  case nameNode.kind
  of nkSym:
    result = nameNode.sym.name.s
  of nkIdent:
    result = nameNode.ident.s
  of nkAccQuoted:
    result = getProcName(nameNode[0])
  of nkPostfix:
    if nameNode.len > 0: result = getProcName(nameNode[^1])
  else:
    if nameNode.len > 0:
      for ch in nameNode:
        let s = getProcName(ch)
        if s.len > 0: result = s; break
  result = result.replace("\"", "")

proc collectNimFiles(dir: string; result: var seq[string]) {.raises: [OSError].} =
  for kind, path in walkDir(dir):
    if kind == pcFile and path.endsWith(".nim"):
      result.add(path)
    elif kind == pcDir and path notin [".", ".."]:
      collectNimFiles(path, result)

# ---------------------------------------------------------------------------
# Lowering funnel (pure, read-only)
# ---------------------------------------------------------------------------

proc lowerTarget(funcDefNode: PNode; moduleRel: string;
                 funcName: string): JsonNode =
  result = newJObject()
  result["target"] = %(moduleRel & "::" & funcName)

  # --- IR materialization (production ingestion path) --------------
  var irFuncDef: IRFuncDef
  var irAvailable = false
  var irStr = ""
  var irError = ""
  try:
    let canonNode = pnodeToCanon(funcDefNode)
    irFuncDef = axiomBodyCanon(canonNode)
    if irFuncDef.name.len == 0:
      irError = "axiomBodyCanon returned empty name"
    else:
      irStr = serializeIRFuncDef(irFuncDef)
      irAvailable = irStr.len > 0
  except CatchableError as e:
    irError = "IR reproduction failed: " & e.msg
  result["irAvailable"] = %irAvailable
  result["irError"] = %irError
  if not irAvailable:
    result["classification"] = %"probe-ir-unavailable"
    return

  # --- Canonical obligation generation (P3 path) -------------------
  let policy = defaultScopePolicy()
  var ogr: ObligationGenerationResult
  ogr = generateCanonicalObligations(irFuncDef, policy)
  result["ogrKind"] = %($ogr.kind)
  var canonicalObligations: seq[JsonNode] = @[]
  if ogr.kind == ogrGenerated:
    for obl in ogr.obligations.items:
      canonicalObligations.add(%*{
        "kind": $obl.kind,
        "subject": obl.subject,
        "predicate": obl.predicate,
        "predicateNonEmpty": obl.predicate.len > 0,
        "derivationRule": obl.derivationRule,
        "provenance": obl.provenance
      })
  result["canonicalObligations"] = %canonicalObligations
  result["canonicalObligationCount"] = %(if ogr.kind == ogrGenerated: ogr.obligations.len else: 0)

  # --- Pre/post conditions: BEFORE synthesis (raw IR) --------------
  result["preConditionsBeforeSynth"] = %irFuncDef.preConditions.len
  result["postConditionsBeforeSynth"] = %irFuncDef.postConditions.len

  # --- Synthesize contracts (Stage 0b path) then re-inspect --------
  var funcDefSyn = irFuncDef
  synthesizeContracts(funcDefSyn)
  result["preConditionsAfterSynth"] = %funcDefSyn.preConditions.len
  result["postConditionsAfterSynth"] = %funcDefSyn.postConditions.len

  # --- PRODUCTION SMT path: irToSmtScript (gated on postConditions) --
  let logic = slQfBv
  var prodSmt = ""
  try:
    prodSmt = irToSmtScript(irFuncDef, includeOverflowDefines = false, logic = logic)
  except CatchableError as e:
    result["productionSmtError"] = %e.msg
  result["productionSmtLen"] = %prodSmt.len
  result["productionSmtEmpty"] = %(prodSmt.len == 0)

  # --- EXISTING non-gating lowerer: irToSmtWithObligations ---------
  # Uses the SAME canonical obligations generated above. If this produces a
  # non-empty SMT script, lowering is STRUCTURALLY possible; the production
  # path just never routes ogr through it.
  var altSmt = ""
  if ogr.kind == ogrGenerated:
    try:
      altSmt = irToSmtWithObligations(irFuncDef, toSeq(ogr.obligations), logic)
    except CatchableError as e:
      result["loweringSmtError"] = %e.msg
  result["loweringSmtLen"] = %altSmt.len
  result["loweringSmtEmpty"] = %(altSmt.len == 0)
  if altSmt.len > 0:
    result["loweringSmt"] = %altSmt

  # --- Executability of the generated SMT (is it z3-valid SMT-LIB2?) ----
  # irToSmtWithObligations inserts obl.predicate verbatim into `(assert ...)`.
  # If the predicate uses Axiom's canonical form (uoNot/boEq/lit/var) rather
  # than SMT-LIB2 operators, the generated script is NOT z3-executable.
  # We statically detect this (deterministic; does not shell out to z3).
  var scriptIsSmtLib2 = false
  var nonSmtOperators: seq[string] = @[]
  if altSmt.len > 0:
    scriptIsSmtLib2 = true
    for op in ["uoNot", "uoNeg", "boEq", "boNeq", "boAnd", "boOr", "boXor",
               "boAdd", "boSub", "boMul", "boSdiv", "boSrem", "lit(", "var(",
               "floatLit(", "recCall(", "loop(", "call(", "str("]:
      if altSmt.contains(op):
        scriptIsSmtLib2 = false
        nonSmtOperators.add(op)
  result["loweringSmtIsZ3Valid"] = %scriptIsSmtLib2
  result["nonSmtLib2OperatorsInSmt"] = %nonSmtOperators

  # --- Reverse-parse the canonical predicate back to IRExpr? -----------
  # serializeIRExpr/parseIRExpr use L(...), V(...), LET(...) grammar.
  # canonicalizePredicate uses uoNot/boEq/lit/var grammar. These are two
  # DIFFERENT serializations. Attempt parseIRExpr on the canonical predicate
  # to prove reverse-parse is impossible (no such parser exists for this form).
  var reverseParse: JsonNode = newJArray()
  if ogr.kind == ogrGenerated:
    for obl in ogr.obligations.items:
      var pos = 0
      var fullyConsumed = false
      var node: IRExpr = nil
      try:
        node = parseIRExpr(obl.predicate, pos)
        fullyConsumed = (pos >= obl.predicate.len)
      except CatchableError:
        node = nil
      reverseParse.add(%*{
        "predicate": obl.predicate,
        "reverseParsed": node != nil,
        "fullyConsumed": fullyConsumed,
        "consumedPrefix": obl.predicate[0 .. min(pos, obl.predicate.len) - 1]
      })
  result["canonicalPredicateReverseParse"] = %reverseParse

  # --- Site determination -------------------------------------------
  # A: lowering possible via existing non-gating lowerer -> production gate
  # B: lowering impossible (even non-gating path empty / errors) -> IR bug
  # C: proposition itself malformed (empty predicate)
  var propositionWellFormed = true
  if ogr.kind == ogrGenerated:
    for obl in ogr.obligations.items:
      if obl.predicate.len == 0:
        propositionWellFormed = false

  # Refined classification: even when irToSmtWithObligations yields a
  # non-empty string, if that string is NOT z3-executable SMT-LIB2 (raw
  # canonical-form predicate embedded verbatim), then there is no real
  # canonical→SMT-LIB2 term-lowering path → the capability boundary is
  # the missing canonical-predicate→IRExpr/SMT-LIB2 converter, not merely
  # the production postConditions gate.
  var classification = "Unknown"
  if not propositionWellFormed:
    classification = "C-propagation-defect"
  elif ogr.kind == ogrGenerated and altSmt.len > 0 and scriptIsSmtLib2:
    classification = "A-lowering-possible-production-gated"
  elif ogr.kind == ogrGenerated and altSmt.len > 0 and not scriptIsSmtLib2:
    classification = "A2-script-pocketed-but-not-z3-executable-no-term-lowering"
  elif ogr.kind == ogrGenerated and altSmt.len == 0:
    classification = "B-lowering-impossible-or-adaptor-defect"
  result["classification"] = %classification
  result["probeType"] = %"wp4h2-lowering-localization"
  result["notCanonicalExecutionPath"] = %true
  result["notProductionAPI"] = %true

proc main() =
  if paramCount() < 2:
    echo "usage: wp4h2_lowering_localization <subjectRoot> <outDir>"
    quit(1)
  let subjectRoot = paramStr(1)
  let outDir = paramStr(2)
  try: createDir(outDir)
  except CatchableError: discard

  generateAxiomInit()

  var nimFiles: seq[string] = @[]
  let libRoot = subjectRoot / "stew"
  var fileFailures: seq[string] = @[]
  if dirExists(libRoot):
    try:
      collectNimFiles(libRoot, nimFiles)
    except CatchableError:
      discard
  nimFiles.sort()

  # Targets: Anchor #1 + rank-2 comparison
  const targets = [
    ("stew/bitops2.nim", "getBitsBE"),
    ("stew/base36.nim", "decodedLength")
  ]

  var foundFlag: array[2, bool]
  var outputs: seq[JsonNode] = @[]

  for fullPath in nimFiles:
    let moduleRel = if fullPath.startsWith(subjectRoot & "/"):
      fullPath[subjectRoot.len + 1 .. ^1]
    else:
      fullPath
    var sourceText = ""
    try:
      sourceText = readFile(fullPath)
    except CatchableError:
      fileFailures.add(moduleRel)
      continue
    let ast = parseStringAST(sourceText)
    if ast.isNil:
      fileFailures.add(moduleRel)
      continue
    for node in findNodesP(ast, {nkProcDef, nkFuncDef}):
      let name = getProcName(node[0])
      if name.len == 0: continue
      for i, t in targets:
        if moduleRel == t[0] and name == t[1] and not foundFlag[i]:
          var output: JsonNode = lowerTarget(node, moduleRel, name)
          outputs.add(output)
          foundFlag[i] = true

  var report = newJObject()
  report["experimentId"] = %"act2-wp4h2-lowering-localization"
  report["phase"] = %"ACT-2.3/WP4-h-2"
  report["subjectRoot"] = %subjectRoot
  report["subjectRevision"] = %"c75502ceedb5ed2a37b7b5e4744fc71313682859"
  report["toolchainIdentity"] = %"Nim 2.2.10"
  report["fileParseFailures"] = %fileFailures
  report["targets"] = %outputs

  try: writeFile(outDir / "lowering-localization.json", report.pretty)
  except CatchableError: discard
  echo "wrote ", outDir / "lowering-localization.json"

main()
