import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## Evidence Truth Boundary Gate (R4) — AST-assisted authority graph.
##
## ─── What this gate IS ──────────────────────────────────────────────────────
## A static authority-graph checker built on syntax-only PNode ASTs
## (compiler/ast via core/parser_utils.parseFileAST). It enforces the three
## semantic transitions of the Evidence Truth Boundary (v3.8.1):
##
##   T1. Receipt creation      ONLY in lean_kernel_boundary.nim (single sink)
##   T2. KAA creation          ONLY in kernel_acceptance_authority.nim (bind)
##   T3. Verified production   ONLY in verification_decision_authority.nim,
##                             and vvSafe is ONLY its projection
##                             (universal_pipeline.nim, ≤1 site)
##
## ─── [T4] Run-outcome verdict vocabulary — ENUMERATED, not hand-listed ────
## The run-verdict authority (INV-X1, execution_accounting_contract.md §9) is
## the WHOLE vocabulary, not just the PASS member: `RunVerdict` (vrInconclusive
## / vrFail / vrBlocked / vrPass) and `RunVerdictBasis` (rbNone / rbProven /
## rbNoObligation / rbReused) are all produced ONLY by
## `makeRunOutcomeVerdict`. Guarding `vrPass` alone let a module fabricate
## INCONCLUSIVE / BLOCKED / FAIL in a value-producing position and pass this
## gate silently.
##
## Both the guarded identifiers and their serialized JSON spellings are
## DERIVED from the enum DECLARATIONS themselves (see `verdictVocabulary`), so
## a newly added enumerator extends the guard automatically instead of
## re-opening the gap. Two checks ride on that vocabulary:
##   [T4-a] any value-producing occurrence of a `vr*`/`rb*` identifier outside
##          verification_decision_authority.nim is a violation;
##   [T4-b] a guarded outcome JSON key (`verdict` / `basis` / `gateVerdict` /
##          `planComplete` / `executionComplete` / `verificationComplete`) may
##          never be written from a LITERAL of the guarded vocabulary — the
##          value must be projected from the authority-decided outcome, never
##          fabricated at the serialization site.
##
## Plus forbidden value-flow edges:
##   Z3Evidence/Candidate/HistoricalRecord/PersistedRecord → KAA/vdVerified/vvSafe
##   (checked here as: PersistedArtifactValidator must not reference KAA at all;
##    private constructors makeReceipt/makeKAA/makeVerifiedDecision must not be
##    referenced outside their owning modules.)
##
## ─── [I-1] Fail-closed unresolved edges (MANDATED) ──────────────────────────
## This gate does NOT perform semantic/type-checked symbol resolution.
## Therefore its policy is fail-closed by construction:
##   - ANY occurrence of a guarded authority symbol outside its allowlisted
##     module is a violation, regardless of syntactic context (call, alias,
##     wrapper, re-export). There is no "unresolvable → pass" path.
##   - A source file that fails to parse is itself a violation
##     ("unparseable — fail-closed"), never silently skipped.
## Known residual limits (documented, not waived): proc-value aliases
## (`let f = makeVerifiedDecision; f(...)`) and macro-generated code can
## launder authority past a syntax-only check. If semantic resolution becomes
## required, migrate this gate to `--genBif:on` semantic artifacts.
##
## ─── [I-2] Direct vvSafe construction prevention (MANDATED) ─────────────────
## `vvSafe` may only appear in VALUE-PRODUCING positions (assignment RHS,
## return expression, object-constructor field) inside universal_pipeline.nim,
## at most once (the projection site). Any producing occurrence anywhere else
## is a violation. Consumption positions (==/!= comparisons, case branches,
## set literals) are permitted everywhere.

import std/[algorithm, os, sets, strutils, tables]
import core/parser_utils
import compiler/ast
import core/axiom_pragmas
import core/utils/repo_root
import infrastructure/logging_facade

const
  GateName* = "evidence-truth-boundary-gate"
  GateTag* = "[evidence-truth-boundary]"

# ---------------------------------------------------------------------------
# Authority ownership map — guarded symbol → sole owning module (repo-relative)
# ---------------------------------------------------------------------------

type SymbolGuardKind = enum
  sgCreation      ## object constructor / private factory call sites
  sgProduction    ## value-producing positions only (RHS/return/constr)

type SymbolGuard = object
  name: string
  owner: string
  kind: SymbolGuardKind
  ctorCallOnly: bool

const runVerdictOwner = "src/verification/obligation/verification_decision_authority.nim"
const verdictVocabularySource = "src/verification/accounting/run_accounting.nim"
  ## Enum declarations that DEFINE the run-outcome verdict vocabulary. Read
  ## (not hardcoded) so the guard follows the vocabulary automatically.

## Key schema of the `runOutcome` block (execution_accounting_contract.md §9,
## "Fixed-key schema change (Plan 1, approved)"). These six keys carry an
## authority-bearing or completeness-bearing value; [T4-b] forbids writing any
## of them from a literal of the guarded vocabulary. The three RAW
## completeness projections (`planComplete` / `executionComplete` /
## `verificationComplete`) are the same class as the VDA-decided verdict keys
## and are guarded identically.
const guardedOutcomeKeys = [
  "verdict", "basis", "gateVerdict",
  "planComplete", "executionComplete", "verificationComplete"
]

## Enum type names whose fields make up the run-outcome verdict vocabulary.
const verdictVocabularyTypes = ["RunVerdict", "RunVerdictBasis"]

const ownedSymbols: seq[SymbolGuard] = @[
  # T1: Receipt — single issuance point. Public TYPE may be referenced as a
  # type annotation anywhere (signatures); only its CONSTRUCTOR CALL is
  # owner-exclusive (ctorCallOnly = true).
  SymbolGuard(name: "LeanKernelCheckReceipt",
              owner: "src/verification/obligation/lean_kernel_boundary.nim",
              kind: sgCreation, ctorCallOnly: true),
  # Private factory — ANY reference outside the owner is a violation.
  SymbolGuard(name: "makeReceipt",
              owner: "src/verification/obligation/lean_kernel_boundary.nim",
              kind: sgCreation, ctorCallOnly: false),
  # T2: KAA — only bind(receipt) → makeKAA
  SymbolGuard(name: "KernelAcceptanceAttestation",
              owner: "src/verification/obligation/kernel_acceptance_authority.nim",
              kind: sgCreation, ctorCallOnly: true),
  SymbolGuard(name: "makeKAA",
              owner: "src/verification/obligation/kernel_acceptance_authority.nim",
              kind: sgCreation, ctorCallOnly: false),
  # T3: Verified decision — only evaluate's private constructor
  SymbolGuard(name: "makeVerifiedDecision", owner: runVerdictOwner,
              kind: sgCreation, ctorCallOnly: false),
  SymbolGuard(name: "vdVerified", owner: runVerdictOwner,
              kind: sgProduction, ctorCallOnly: false),
  # Run-level verdict CONSTRUCTOR (Plan 1 — Authority Unification): the run
  # outcome is built ONLY inside this private constructor.
  SymbolGuard(name: "makeRunOutcomeVerdict", owner: runVerdictOwner,
              kind: sgCreation, ctorCallOnly: false),
  # [I-2]: vvSafe — projection of vdVerified only
  SymbolGuard(name: "vvSafe", owner: "src/verification/universal_pipeline.nim",
              kind: sgProduction, ctorCallOnly: false),
]
  ## NOTE: the `vr*` / `rb*` verdict-vocabulary guards are NOT listed here.
  ## They are appended at scan time from the enum declarations in
  ## verdictVocabularySource (see verdictVocabulary) so a newly added
  ## enumerator cannot silently escape the guard.

## Modules that may reference KAA symbols as CONSUMERS (accessors only).
const kaaConsumerAllowlist = [
  "src/verification/obligation/verification_decision_authority.nim",
]

## Modules forbidden from referencing KAA at all (forbidden value-flow).
const kaaForbiddenModules = [
  "src/verification/obligation/persisted_artifact_validator.nim",
]

# ---------------------------------------------------------------------------
# certZ3Verified legacy migration layer — the ONLY permitted string reference
# ---------------------------------------------------------------------------

const forbiddenCertZ3VerifiedInCanonical = [
  "src/verification/cert_writer.nim",
  "src/verification/proof_state_builder.nim",
  "src/verification/verified_set_hydration.nim",
  "src/verification/state_persistence.nim",
  "src/verification/cert_promotion.nim",
  "src/verification/certificate_verifier.nim",
  "src/verification/certificate_manager.nim",
  "src/verification/certificate_hydration.nim",
  "src/verification/proof_state_projection.nim",
  "src/verification/analyzer/stage_08_reporter.nim",
  "src/verification/analyzer/stage_02_fingerprint.nim",
]

const certZ3VerifiedLegacyLayers = [
  "src/core/types/certificate_types.nim",
  "src/core/types/verification_tier.nim",
]

# ---------------------------------------------------------------------------
# [T4] Verdict vocabulary — derived from the enum DECLARATIONS (SSOT)
# ---------------------------------------------------------------------------

type VerdictVocabulary = object
  symbols: seq[string]          ## guarded enum field names (`vr*` / `rb*`)
  spellings: HashSet[string]    ## their serialized JSON spellings
  missing: seq[string]          ## type names not located — fail-closed

func declaredName(node: PNode): string {.raises: [].} =
  ## Name carried by a declaration node. An EXPORTED declaration (`RunVerdict*`)
  ## wraps the name in `nkPostfix`(`nkIdent("*")`, name) — never as a bare
  ## `nkIdent` son — so the innermost wrapping is unwrapped here. The NAME is
  ## the LAST identifier son, which holds for the exported form in either
  ## prefix/postfix spelling.
  var cur = node
  while cur != nil:
    case cur.kind
    of nkIdent:
      return cur.ident.s
    of nkPostfix, nkPrefix:
      var found = ""
      for i in 0 ..< cur.safeLen:
        if cur[i].kind == nkIdent:
          found = cur[i].ident.s
      return found
    else:
      return ""
  ""

proc collectEnumFields(node: PNode; typeName: string;
                       acc: var seq[tuple[name, value: string]]) {.raises: [].} =
  ## Locate `typeName = enum` anywhere in the tree and collect (field, value)
  ## for every enumerator. `nkTypeDef`'s subtype is its LAST son, so a
  ## non-enum type of the same name can never masquerade as the vocabulary.
  if node == nil:
    return
  if node.kind == nkTypeDef and node.safeLen >= 2 and
      declaredName(node[0]) == typeName:
    let subtype = node[node.safeLen - 1]
    if subtype.kind == nkEnumTy:
      for i in 0 ..< subtype.safeLen:
        let field = subtype[i]
        if field.kind == nkEnumFieldDef and field.safeLen >= 1:
          let name = declaredName(field[0])
          if name.len == 0:
            continue
          let spelling =
            if field.safeLen >= 2 and field[1].kind == nkStrLit: field[1].strVal
            else: ""
          acc.add((name: name, value: spelling))
  for i in 0 ..< node.safeLen:
    collectEnumFields(node[i], typeName, acc)

proc verdictVocabulary(repoRoot: string): VerdictVocabulary {.raises: [CatchableError].} =
  ## The run-outcome verdict vocabulary, read from its single declaration
  ## site. Fail-closed: a declaration that cannot be located is reported as
  ## missing so the caller FAILS rather than silently scanning with an EMPTY
  ## vocabulary (an empty guard set would make [T4] vacuous — §0.9).
  let sourcePath = repoRoot / verdictVocabularySource
  if not fileExists(sourcePath):
    result.missing = @["<file absent: " & verdictVocabularySource & ">"]
    return
  let ast = parseFileAST(sourcePath)
  if ast == nil:
    result.missing = @["<unparseable: " & verdictVocabularySource & ">"]
    return
  for typeName in verdictVocabularyTypes:
    var fields: seq[tuple[name, value: string]] = @[]
    collectEnumFields(ast, typeName, fields)
    if fields.len == 0:
      result.missing.add("<not found: " & typeName & ">")
      continue
    for f in fields:
      result.symbols.add f.name
      if f.value.len > 0:
        result.spellings.incl f.value
  result.symbols.sort()
  result.missing.sort()

# ---------------------------------------------------------------------------
# [T4-b] Guarded outcome keys may never be written from a literal
# ---------------------------------------------------------------------------

const serializationWrappers = ["$", "%", "newJString", "newJBool"]
  ## Peeled off a keyed write's value before it is judged, so that
  ## `outcome["verdict"] = %"BLOCKED"` is judged as the literal it is.

func unwrapSerializedValue(node: PNode): PNode {.raises: [].} =
  ## Innermost expression that actually reaches the written key.
  var cur = node
  while cur != nil:
    case cur.kind
    of nkPar:
      if cur.safeLen != 1: break
      cur = cur[0]
    of nkPrefix:
      if cur.safeLen != 2: break
      if cur[0].kind != nkIdent or cur[0].ident.s notin serializationWrappers: break
      cur = cur[1]
    of nkCall:
      if cur.safeLen < 2: break
      if cur[0].kind != nkIdent or cur[0].ident.s notin serializationWrappers: break
      cur = cur[1]
    else:
      break
  cur

func keyedWriteKey(node: PNode): string {.raises: [].} =
  ## Key name of a keyed WRITE (`node["k"] = v` / `k: v` in an object
  ## constructor), or "" when `node` is not one. The value is the LAST son; the
  ## key is son 0 (object constructor) or son 1 inside the subscript on an
  ## assignment LHS. `nkBracketExpr` is the `a[k]` subscript — `nkBracket` is
  ## the unrelated slice/index-range form.
  case node.kind
  of nkAsgn:
    if node.safeLen >= 2 and
        (node[0].kind == nkBracketExpr or node[0].kind == nkBracket) and
        node[0].safeLen >= 2:
      case node[0][1].kind
      of nkStrLit: return node[0][1].strVal
      of nkIdent: return node[0][1].ident.s
      else: discard
  of nkExprColonExpr:
    if node.safeLen >= 2:
      case node[0].kind
      of nkStrLit: return node[0].strVal
      of nkIdent: return node[0].ident.s
      else: discard
  else:
    discard
  ""

func fabricatedValueLabel(value: PNode; spellings: HashSet[string]): string {.raises: [].} =
  ## "" when the value is a genuine projection (field read, call, computed
  ## expression); otherwise the literal that fabricates the authority.
  let inner = unwrapSerializedValue(value)
  if inner == nil:
    return ""
  if inner.kind == nkStrLit and inner.strVal in spellings:
    return "'" & inner.strVal & "'"
  if inner.kind == nkIdent and (inner.ident.s == "true" or inner.ident.s == "false"):
    return inner.ident.s
  ""

proc collectFabricatedOutcomeWrites(node: PNode; file: string;
                                    spellings: HashSet[string];
                                    acc: var seq[string]) {.raises: [].} =
  if node == nil:
    return
  let key = keyedWriteKey(node)
  if key.len > 0 and key in guardedOutcomeKeys:
    let label = fabricatedValueLabel(node[node.safeLen - 1], spellings)
    if label.len > 0:
      acc.add(file & ":" & $node.info.line.int & " [T4] outcome key '" & key &
        "' written from literal " & label & " — the run verdict/basis/" &
        "completeness value is produced ONLY by " & runVerdictOwner &
        " and may only be PROJECTED here")
  for i in 0 ..< node.safeLen:
    collectFabricatedOutcomeWrites(node[i], file, spellings, acc)

# ---------------------------------------------------------------------------
# AST occurrence collection
# ---------------------------------------------------------------------------

type Occurrence = object
  symbol: string
  file: string          ## repo-relative
  line: int
  consumption: bool     ## comparison operand / case pattern / set member
  callee: bool          ## is the callee of a call/constructor expression

func isComparisonParent(node: PNode): bool {.raises: [].} =
  ## Parent infix ==/!= → consumption context.
  if node.kind == nkInfix and node.safeLen >= 1 and node[0].kind == nkIdent:
    let op = node[0].ident.s
    return op == "==" or op == "!="
  false

func isConsumptionParent(node: PNode; childIndex: int): bool {.raises: [].} =
  ## Consumption contexts for enum-value occurrences:
  ##   - operand of ==/!=
  ##   - case-branch pattern position (`of vvSafe:`)
  ##   - set literal member (`x in {vvSafe, vvUnknown}`)
  ##   - enum field DECLARATION (nkEnumFieldDef name position)
  if isComparisonParent(node):
    return true
  if node.kind == nkOfBranch and childIndex == 0:
    return true
  if node.kind == nkCurly:
    return true
  if node.kind == nkEnumFieldDef and childIndex == 0:
    return true
  if node.kind == nkEnumTy:
    # bare enum field declaration (`vvSafe` with no `= value`)
    return true
  false

proc collectOccurrences(node: PNode; file: string; line: int;
                        guards: seq[SymbolGuard];
                        consumption = false, calleePos = false;
                        acc: var seq[Occurrence]) {.raises: [].} =
  ## Walk the PNode tree recording every guarded-symbol identifier together
  ## with its syntactic context (`consumption`, `calleePos`).
  if node == nil:
    return

  case node.kind
  of nkAsgn:
    if node.safeLen >= 2:
      collectOccurrences(node[0], file, line, guards, true, false, acc)
      collectOccurrences(node[1], file, line, guards, false, false, acc)
      for i in 2 ..< node.safeLen:
        collectOccurrences(node[i], file, line, guards, false, false, acc)
    return
  of nkExprColonExpr:
    # object-constructor `field: value`
    if node.safeLen >= 2:
      collectOccurrences(node[0], file, line, guards, true, false, acc)
      collectOccurrences(node[1], file, line, guards, false, false, acc)
      return
  else:
    discard

  if node.kind == nkIdent:
    let name = node.ident.s
    for guard in guards:
      if guard.name == name:
        acc.add(Occurrence(
          symbol: name,
          file: file,
          line: line,
          consumption: consumption,
          callee: calleePos
        ))
    return

  # Leaf nodes (string/number literals) have no sons — safeLen returns 0.
  if node.safeLen == 0:
    return

  for i in 0 ..< node.safeLen:
    let child = node[i]
    let childConsumption = isConsumptionParent(node, i)
    # child[0] of an nkCall is the callee position (constructor call).
    let childCallee = node.kind == nkCall and i == 0
    collectOccurrences(child, file, child.info.line.int, guards,
                       childConsumption, childCallee, acc)

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

proc relPath(repoRoot, fullPath: string): string {.raises: [].} =
  ## Repo-relative path for reporting; falls back to full path.
  let norm = repoRoot & "/"
  if fullPath.startsWith(norm):
    fullPath[norm.len .. ^1]
  else:
    fullPath

proc checkAuthorityGraphAst*(repoRoot: string): seq[string] {.
  raises: [CatchableError].} =
  ## AST-assisted authority graph scan over src/**/*.nim.
  ## [I-1]: unparseable files are violations (fail-closed), never skipped.
  var violations: seq[string] = @[]
  var vvSafeProductionByFile: Table[string, int]

  ## [T4] Guard set = static authority table + the verdict vocabulary read
  ## from its enum declarations. A vocabulary that cannot be read is itself a
  ## violation: scanning with an empty vocabulary would make every [T4] rule
  ## vacuous (§0.9).
  let vocabulary = verdictVocabulary(repoRoot)
  if vocabulary.missing.len > 0:
    violations.add(verdictVocabularySource & ": [T4] verdict vocabulary unreadable (" &
                   vocabulary.missing.join(", ") &
                   ") — fail-closed; the run-verdict guard would be vacuous")
    return violations
  var guards = ownedSymbols
  for sym in vocabulary.symbols:
    guards.add(SymbolGuard(name: sym, owner: runVerdictOwner,
                           kind: sgProduction, ctorCallOnly: false))

  let srcDir = repoRoot / "src"
  for path in walkDirRec(srcDir):
    if not path.endsWith(".nim"):
      continue
    let rel = relPath(repoRoot, path)

    var ast: PNode
    try:
      ast = parseFileAST(path)
    except CatchableError as e:
      violations.add(rel & ": [I-1] unparseable source — fail-closed (" & e.msg & ")")
      continue
    if ast == nil:
      violations.add(rel & ": [I-1] unparseable source (nil AST) — fail-closed")
      continue

    var occs: seq[Occurrence] = @[]
    collectOccurrences(ast, rel, ast.info.line.int, guards, false, false, occs)

    for occ in occs:
      for guard in guards:
        if guard.name != occ.symbol:
          continue
        case guard.kind
        of sgCreation:
          # [I-1] fail-closed: private factories (ctorCallOnly=false) may not be
          # referenced outside the owner in ANY position. Public authority
          # types (ctorCallOnly=true) may appear as type annotations, but their
          # CONSTRUCTOR CALL (callee position) is owner-exclusive.
          let violates = if guard.ctorCallOnly: occ.callee
                         else: true
          if rel != guard.owner and violates:
            violations.add(rel & ":" & $occ.line & " [T] '" & occ.symbol &
              "' " & (if guard.ctorCallOnly: "constructor call" else: "reference") &
              " outside its authority module (" & guard.owner & ")")
        of sgProduction:
          # [I-2]/[T4] fail-closed: outside the owning module, ANY non-consumption
          # occurrence (assignment RHS, return/trailing expression, argument,
          # constructor field) is a violation. Consumption contexts
          # (==/!= operands, case patterns, set members, enum declarations) are
          # permitted.
          if rel != guard.owner and not occ.consumption:
            let tag = if guard.name == "vdVerified" or guard.name == "vvSafe": "I-2"
                      else: "T4"
            violations.add(rel & ":" & $occ.line & " [" & tag & "] '" & occ.symbol &
              "' used in a value-producing position outside its authority module (" &
              guard.owner & ")")
          elif rel == guard.owner and not occ.consumption and occ.symbol == "vvSafe":
            vvSafeProductionByFile.mgetOrPut(rel, 0).inc

    # Forbidden value-flow: persisted validator must not touch KAA at all.
    if rel in kaaForbiddenModules:
      for occ in occs:
        if occ.symbol in ["KernelAcceptanceAttestation", "makeKAA"]:
          violations.add(rel & ":" & $occ.line &
            " forbidden value-flow: persistence layer references KAA authority")

    # [T4-b]: an authority-bearing outcome key written from a literal.
    collectFabricatedOutcomeWrites(ast, rel, vocabulary.spellings, violations)

  # [I-2]: at most ONE vvSafe production site (the projection site).
  for file, count in vvSafeProductionByFile:
    if count > 1:
      violations.add(file & ": [I-2] multiple vvSafe production sites (" &
        $count & ") — projection must be single-site")

  violations

proc checkCertZ3VerifiedInCanonical*(repoRoot: string): seq[string] {.
  raises: [CatchableError].} =
  ## Canonical model/writer/output must NOT contain "certZ3Verified".
  ## Only the legacy migration layers may reference it.
  var violations: seq[string] = @[]
  for filePath in forbiddenCertZ3VerifiedInCanonical:
    let fullPath = repoRoot / filePath
    if not fileExists(fullPath):
      continue
    if filePath in certZ3VerifiedLegacyLayers:
      continue
    let content = try: readFile(fullPath) except CatchableError: continue
    let lines = content.splitLines()
    for i in 0 ..< lines.len:
      if "certZ3Verified" notin lines[i]:
        continue
      let stripped = lines[i].strip()
      # Allowed: comments, and case-branch PATTERN positions (`of certZ3Verified`)
      # that consume the legacy label for reclassification into certZ3Candidate.
      # Everything else (assignment, emission, string output) is a violation.
      if stripped.startsWith("#") or stripped.startsWith("of certZ3Verified"):
        continue
      violations.add(filePath & ":" & $(i + 1) & ": " & stripped)
  violations

proc runEvidenceTruthBoundaryScan*(repoRoot: string): tuple[ok: bool; violations: seq[string]] {.
  raises: [CatchableError].} =
  ## Run the full evidence truth boundary scan (AST-assisted authority graph).
  let certViolations = checkCertZ3VerifiedInCanonical(repoRoot)
  let graphViolations = checkAuthorityGraphAst(repoRoot)
  var allViolations = certViolations & graphViolations
  # Sorted so the reported artifact is a function of the CONTENT only, not of
  ## directory iteration order (§0.2).
  allViolations.sort()
  (ok: allViolations.len == 0, violations: allViolations)

proc main() {.axiomEffect: IOEffect.} =
  let repoRoot =
    if paramCount() >= 1: paramStr(1)
    else: findRepoRoot()
  let (ok, violations) = runEvidenceTruthBoundaryScan(repoRoot)
  if violations.len > 0:
    for v in violations:
      logError("evidence-truth-boundary", v)
    logError("evidence-truth-boundary",
      "FAIL — " & $violations.len & " authority-graph violation(s) ([I-1]/[I-2] fail-closed)")
    quit(1)
  logInfo("evidence-truth-boundary", "PASS — evidence truth boundary invariants hold")
  quit(0)

when isMainModule: main()

{.pop.}
