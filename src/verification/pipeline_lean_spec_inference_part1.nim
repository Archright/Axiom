import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import ../core/trusted/axiom_pragmas
import core/parsers/pnode_nav
import core/logic/universal_translation_types
import core/utils/text_utils
import std/options
import std/strutils
import compiler/ast
# axiomIoBoundary
# axiomIoBoundary

## axiom-smt: (assert (and (>= depth 0) (>= lower 0) (>= upper 0)))
## axiom-lean: depth >= 0 ∧ (lower ≥ 0) ∧ (upper ≥ 0)
proc inferGuaranteedRange*(translation: UniversalTranslation): string {.axiom, axiomImpl.} =
  var lower = "unbounded"
  var upper = "unbounded"
  for entry in translation.ilEntries:
    let tokens = tokenizeLowered(entry.il)
    if "sub" in tokens:
      if lower == "unbounded":
        lower = "state - delta"
    if "add" in tokens:
      if upper == "unbounded":
        upper = "state + delta"
  "[" & lower & ", " & upper & "]"

## axiom-smt: (assert (and (= (str.len result) 0)))
## axiom-lean: result.length = 0
proc inferAssumptions*(translation: UniversalTranslation; activeInvariant: string): seq[string] {.axiom, axiomImpl.} =
  if translation.memoryAccessCount > 0:
    result.add("0 <= index < length")
    result.add("base + offset stays within allocated memory range")
    result.add("pointer != null")
  if translation.controlFlowCount > 0:
    result.add("control predicates are deterministic")
  if activeInvariant.strip().len > 0:
    result.add("active invariant: " & activeInvariant)
  if result.len == 0:
    result.add("state transition is total")

## axiom-smt: (assert (and (>= depth 0)))
## axiom-lean: depth >= 0
proc inferLoopDepth*(translation: UniversalTranslation): int {.axiom, axiomImpl.} =
  for entry in translation.ilEntries:
    let kind = entry.kind.toLowerAscii()
    if kind in ["loop", "while", "for"]:
      inc result

## axiom-smt: (assert (and (>= depth 0)))
## axiom-lean: depth >= 0
proc inferBranchDepth*(translation: UniversalTranslation): int {.axiom, axiomImpl.} =
  for entry in translation.ilEntries:
    let kind = entry.kind.toLowerAscii()
    if kind in ["if", "branch", "conditional"]:
      inc result

## axiom-smt: (assert (and (<= branchDepth 0) (>= target 0)))
## axiom-lean: branchDepth ≤ 0 ∧ (target ≥ 0)
proc buildConditionalTarget*(branchDepth: int): string {.axiom, axiomImpl.} =
  if branchDepth <= 0:
    return "True"
  var target = "True"
  for i in countdown(branchDepth, 1):
    target = "(if b" & $i & " then True else " & target & ")"
  target

## axiom-smt: (assert (and (= (option.isSome objOpt) true) (= (option.isSome nameOpt) true) (> (str.len name) 0) (<= bracePos 0) (> (str.len candidate) 0)))
## axiom-lean: objOpt.isSome = true ∧ nameOpt.isSome = true ∧ name.length > 0 ∧ bracePos ≤ 0 ∧ candidate.length > 0
proc inferStructuredStateName*(sourceCode: string; language: string; ast: Option[PNode] = none(PNode)): string {.axiom, axiomImpl.} =
  ## AST-based inference of structured state name from source code.
  ## For Nim, parses the AST to find object_declaration or type_declaration nodes.
  ## Falls back to empty string if AST is unavailable (callers should provide AST).
  let normalized = language.toLowerAscii()
  if normalized == "nim" and ast.isSome:
    let astNode = ast.get
    for typeDecl in findNodesP(astNode, {nkTypeDef}):
      let objOpt = findFirstNodeP(typeDecl, {nkObjectTy})
      if objOpt.isSome:
        let nameOpt = findFirstNodeP(typeDecl, {nkIdent, nkSym})
        if nameOpt.isSome:
          let name = pNodeText(nameOpt.get)
          if name.len > 0:
            return sanitizeToken(name)
    for objDecl in findNodesP(astNode, {nkObjectTy}):
      let nameOpt = findFirstNodeP(objDecl, {nkIdent, nkSym})
      if nameOpt.isSome:
        let name = pNodeText(nameOpt.get)
        if name.len > 0:
          return sanitizeToken(name)
    return ""
  elif normalized == "c" or normalized == "cpp" or normalized == "c++":
    for rawLine in sourceCode.splitLines():
      let trimmed = rawLine.strip()
      if not trimmed.startsWith("struct ") or trimmed.find('{') < 0:
        continue
      let remain = trimmed["struct ".len .. ^1].strip()
      let bracePos = remain.find('{')
      if bracePos <= 0:
        continue
      let candidate = remain[0 ..< bracePos].strip()
      if candidate.len > 0:
        return sanitizeToken(candidate)
  ""

## axiom-smt: (assert (and (>= (str.len aliasName) 0) (>= (str.len structuredStateName) 0) (and (>= branchDepth -9223372036854775808) (<= branchDepth 9223372036854775807)) (>= (str.len theorem) 0) (= (str.len params) 0)))
## axiom-lean: aliasName.length ≥ 0 ∧ structuredStateName.length ≥ 0 ∧ branchDepth ≥ -9223372036854775808 ∧ branchDepth ≤ 9223372036854775807 ∧ theorem.length ≥ 0 ∧ params.length = 0
proc buildGoalAliasName*(theorem: string): string {.axiom, axiomImpl.} =
  theorem & "_goal"

## axiom-smt: (assert (and (= (str.len raw) 0) (= result raw) (>= result 0)))
## axiom-lean: raw.length = 0 ∧ result = raw ∧ (result ≥ 0)
proc upperFirstAscii*(raw: string): string {.axiom, axiomImpl.} =
  if raw.len == 0:
    return "Pipeline"
  result = raw
  if result[0] >= 'a' and result[0] <= 'z':
    result[0] = chr(ord(result[0]) - 32)

## axiom-smt: (assert (and (> (str.len structuredStateName) 0) structuredStateName (=> (> (str.len structuredStateName) 0) (= result structuredStateName))))
## axiom-lean: structuredStateName.length > 0 ∧ structuredStateName ∧ structuredStateName.length > 0 → result = structuredStateName
proc buildStateTypeName*(structuredStateName: string; functionName: string): string {.axiom, axiomImpl.} =
  if structuredStateName.len > 0:
    return structuredStateName
  upperFirstAscii(sanitizeToken(functionName)) & "State"

## axiom-smt: (assert (and (>= (str.len modulePath) 0) (>= (str.len functionName) 0)))
## axiom-lean: modulePath.length ≥ 0 ∧ functionName.length ≥ 0
proc buildLeanNamespace*(modulePath: string; functionName: string): string {.axiom, axiomImpl.} =
  sanitizeToken(modulePath.replace('/', '_').replace('\\', '_')) & "_" &
    sanitizeToken(functionName) & "_uap"
{.pop.}

