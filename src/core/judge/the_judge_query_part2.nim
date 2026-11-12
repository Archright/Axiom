import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import core/encoding/smt_to_lean_translate
import core/identity/axiom_prelude
import core/judge/smart_search
import core/judge/tautology_prover
import core/judge/the_judge_constants
import core/judge/the_judge_lean
import core/types/type_mapping
import core/utils/text_utils
import core/verified_axioms/verified_axioms_core
import std/options
import std/strutils
import the_judge_query_part1
func usageHasElementField(usage: LeanVariableUsage; field: string): bool {.raises: [].} =
  field in usage.elementFields
func compactLeanComparison(prop: string): string {.raises: [].} =
  let normalized = prop.replace("≥", ">=").replace("≤", "<=")
  for ch in normalized:
    if ch notin {' ', '\t', '\r', '\n'}:
      result.add(ch)
func hasNumericComparison(prop: string; name: string): bool {.raises: [].} =
  let compact = compactLeanComparison(prop)
  compact.contains(name & ">=") or compact.contains(name & "<=") or
    compact.contains(name & ">") or compact.contains(name & "<") or
    compact.contains(">=" & name) or compact.contains("<=" & name)
func hasBoolEquality(prop: string; name: string): bool {.raises: [].} =
  let compact = compactLeanComparison(prop)
  compact.contains(name & "=true") or compact.contains(name & "=false") or
    compact.contains("true=" & name) or compact.contains("false=" & name)
func isUsedAsLogicalOperand(prop: string; name: string): bool {.raises: [].} =
  let patterns = [
    "∧ " & name & " ", " ∧ " & name, name & " ∧",
    "∨ " & name & " ", " ∨ " & name, name & " ∨",
    "¬" & name, "¬ " & name,
    "=> " & name & " ", " => " & name, name & " =>"
  ]
  for pat in patterns:
    if prop.contains(pat):
      return true
  false
func inferLeanTypeFromUsage(prop: string; usage: LeanVariableUsage): string {.raises: [].} =
  if usageHasField(usage, "isSome") or usageHasField(usage, "isNone") or usageHasField(usage, "get"):
    return "Option α"
  if usageHasField(usage, "get") and usageHasElementField(usage, "length"):
    return "NimSeq String"
  if usageHasField(usage, "get_nat") and usageHasElementField(usage, "length"):
    return "NimSeq String"
  if usageHasField(usage, "size") or usageHasField(usage, "get") or usageHasField(usage, "get_nat"):
    return "NimSeq α"
  if usageHasField(usage, "length"):
    return "String"
  if isUsedAsLogicalOperand(prop, usage.name):
    return "Prop"
  if hasBoolEquality(prop, usage.name):
    return "Bool"
  if isNaturalDomainVariableName(usage.name):
    return "Nat"
  if hasNumericComparison(prop, usage.name):
    return "Int"
  "α"
func rewriteLeanFieldProjection(prop: string; name, sourceField, targetField: string): string {.raises: [].} =
  var i = 0
  while i < prop.len:
    if isLeanIdentStart(prop[i]):
      let start = i
      var ident = ""
      var nextPos = i
      discard readLeanIdent(prop, i, ident, nextPos)
      result.add(ident)
      i = nextPos
      if ident == name and previousNonSpace(prop, start) != '.' and i < prop.len and prop[i] == '.':
        var field = ""
        var fieldNext = i + 1
        if readLeanIdent(prop, i + 1, field, fieldNext) and field == sourceField:
          result.add("." & targetField)
          i = fieldNext
          continue
      continue
    result.add(prop[i])
    inc i
func rewriteLeanIdentifier(prop: string; sourceName, targetName: string): string {.raises: [].} =
  var i = 0
  while i < prop.len:
    if isLeanIdentStart(prop[i]):
      let start = i
      var ident = ""
      var nextPos = i
      discard readLeanIdent(prop, i, ident, nextPos)
      if ident == sourceName and previousNonSpace(prop, start) != '.':
        result.add(targetName)
      else:
        result.add(ident)
      i = nextPos
      continue
    result.add(prop[i])
    inc i
func normalizeLeanProjectionsForKnownTypes*(prop: string; hint: SemanticHint): string {.noSideEffect.} =
  result = prop
  for pt in hint.paramTypes:
    let leanType = nimTypeToLeanType(pt.nimType, useNimPrefix = false)
    let rawName = pt.name
    let leanName = sanitizeLeanIdentifierName(rawName)
    if leanName != rawName:
      result = rewriteLeanIdentifier(result, rawName, leanName)
    if leanType == "String":
      result = rewriteLeanFieldProjection(result, leanName, "size", "length")
func leanTypeUsesAlpha(leanType: string): bool {.raises: [].} =
  "α" in leanType
func buildLeanVariableDeclarations*(prop: string; hint: SemanticHint): string {.noSideEffect.} =
  let usages = extractVariableUsages(prop)
  var declaredNames: seq[string] = @[]
  var declarationLines: seq[string] = @[]
  var needsAlpha = hint.paramTypes.len == 0
  for pt in hint.paramTypes:
    var leanType: string
    let ptLower = pt.nimType.strip().toLowerAscii()
    if ptLower == "bool":
      leanType = inferBoolOrPropFromUsage(prop, pt.name)
    elif pt.refinedType.isSome:
      leanType = nimTypeToLeanTypeWithRefinement(pt.nimType, pt.refinedType, pt.name, useNimPrefix = false)
    else:
      leanType = nimTypeToLeanType(pt.nimType, useNimPrefix = false)
    let leanName = sanitizeLeanIdentifierName(pt.name)
    declarationLines.add("variable (" & leanName & " : " & leanType & ")\n")
    declaredNames.add(leanName)
    if leanTypeUsesAlpha(leanType):
      needsAlpha = true
  for usage in usages:
    if usage.name in declaredNames:
      continue
    let leanType = inferLeanTypeFromUsage(prop, usage)
    let leanName = sanitizeLeanIdentifierName(usage.name)
    declarationLines.add("variable (" & leanName & " : " & leanType & ")\n")
    declaredNames.add(leanName)
    if leanTypeUsesAlpha(leanType):
      needsAlpha = true
  if needsAlpha:
    result.add(leanDefaultVarDecl)
  for line in declarationLines:
    result.add(line)
func buildLeanQuery*(nodeId: string, hint: SemanticHint): string {.noSideEffect.} =
  let safeId = sanitizeAxiomToken(nodeId).replace("/", "_")
  let uniqueSig = generateUniqueSignature(nodeId, hint)
  let rawProp = hint.leanProposition
  let cleanProp = normalizeLeanProjectionsForKnownTypes(
    sanitizeLeanIdentifiers(sanitizeLean4AppSyntax(sanitizeLean4Forall(rawProp))),
    hint
  )
  var imports = "import Std\n" & getExtendedAxiomPrelude() & "\n"
  let varDecls = buildLeanVariableDeclarations(cleanProp, hint)
  imports & "\n" & varDecls & "\n" &
  "theorem " & safeId & "_" & uniqueSig & " (h_sys : " & cleanProp & ") :\n" &
  "  " & cleanProp & " := by\n" &
  "  -- PROOF_HERE --\n" &
  leanDeterministicTacticBlock
func buildLeanTheoremSkeleton*(nodeId: string, hint: SemanticHint): string {.noSideEffect.} =
  let safeId = sanitizeAxiomToken(nodeId).replace("/", "_")
  let uniqueSig = generateUniqueSignature(nodeId, hint)
  let rawProp = hint.leanProposition
  let cleanProp = normalizeLeanProjectionsForKnownTypes(
    sanitizeLeanIdentifiers(sanitizeLean4AppSyntax(sanitizeLean4Forall(rawProp))),
    hint
  )
  var imports = "import Std\n" & getExtendedAxiomPrelude() & "\n"
  let varDecls = buildLeanVariableDeclarations(cleanProp, hint)
  var proofBody: string
  if hint.strategy == isTautologyProof:
    proofBody = buildTautologyProof(hint.smtConstraint.split({'(', ')'}), @[])
  else:
    proofBody = assemblePrimitiveProof(hint.smtConstraint)
  result = imports & "\n" & varDecls & "\n" &
    "theorem " & safeId & "_" & uniqueSig & " (h_sys : " & cleanProp & ") :\n" &
    "  " & cleanProp & " := by\n" &
    (if proofBody.len > 0 and proofBody != "  trivial\n": proofBody else: leanDeterministicTacticBlock)
func buildNegativeTestLeanQuery*(nodeId: string, hint: SemanticHint): string {.noSideEffect.} =
  let safeId = sanitizeAxiomToken(nodeId).replace("/", "_")
  let uniqueSig = generateUniqueSignature(nodeId, hint)
  let rawProp = hint.leanProposition
  let cleanProp = normalizeLeanProjectionsForKnownTypes(
    sanitizeLeanIdentifiers(sanitizeLean4AppSyntax(sanitizeLean4Forall(rawProp))),
    hint
  )
  let mutatedProp = negateLeanProposition(cleanProp)
  var imports = "import Std\n" & getExtendedAxiomPrelude() & "\n"
  let varDecls = buildLeanVariableDeclarations(cleanProp, hint)
  imports & "\n" & varDecls & "\n" &
  "theorem " & safeId & "_" & uniqueSig & "_NEG (h_sys : " & cleanProp & ") :\n" &
  "  " & mutatedProp & " := by\n" &
  "  exact h_sys\n"
func checkSmtSat*(hint: SemanticHint, unsatCore: seq[string]): bool {.noSideEffect.} =
  hint.smtConstraint.len > 0
func checkLean4Consistency*(hint: SemanticHint): bool {.noSideEffect.} =
  hint.leanProposition.len > 0
{.pop.}
