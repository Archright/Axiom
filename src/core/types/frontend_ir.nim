import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
import core/types/hubs/effect_hub
import std/strutils
export effect_hub

type
  IrNodeKind* = enum
    inkModule
    inkFunction
    inkProcedure
    inkLoop
    inkConditional
    inkAssignment
    inkCall
    inkReturn

  InvariantScope* = enum
    invPre
    invPost
    invLoop

  InvariantCondition* = object
    predicate*: string
    scope*: InvariantScope

  MemoryAccessMode* = enum
    memRead
    memWrite
    memAllocate

  MemoryBoundary* = object
    region*: string
    accessMode*: MemoryAccessMode

  EffectConstraint* = object
    kind*: EffectKind
    severity*: int  # 0 = optional hint, 1 = warning, 2 = blocking

  TypeContract* = object
    sourceType*: string
    targetType*: string
    constraints*: seq[string]

  FrontendIrNode* = object
    kind*: IrNodeKind
    name*: string
    sourceLanguage*: string
    invariants*: seq[InvariantCondition]
    memoryBoundaries*: seq[MemoryBoundary]
    effectConstraints*: seq[EffectConstraint]
    typeContracts*: seq[TypeContract]
    children*: seq[FrontendIrNode]
    sourceRef*: string
# ---------------------------------------------------------------------------
# Serialisation helpers (human-readable S-expression style)
# ---------------------------------------------------------------------------

# @axiom-hint: lean="level ≥ -9223372036854775808 ∧ level ≤ 9223372036854775807 ∧ text.length ≥ 0" smt="(assert (and (and (>= level -9223372036854775808) (<= level 9223372036854775807)) (>= (str.len text) 0)))"
func indentLine(level: int; text: string): string {.raises: [].} =
  var prefix = ""
  for i in 0 ..< level:
    prefix.add("  ")
  prefix & text

# @axiom-hint: lean="inv_predicate.length ≥ 0" smt="(assert (and (>= (str.len inv_predicate) 0)))"
# @axiom-hint: lean="invPre ∧ invPost ∧ invLoop" smt="(assert (and invPre invPost invLoop))"
func invariantToString(inv: InvariantCondition): string {.raises: [].} =
  let scopeLabel = case inv.scope
    of invPre: "pre"
    of invPost: "post"
    of invLoop: "loop"
  "(" & scopeLabel & " " & inv.predicate & ")"

# @axiom-hint: lean="mem_region.length ≥ 0" smt="(assert (and (>= (str.len mem_region) 0)))"
# @axiom-hint: lean="memRead ∧ memWrite ∧ memAllocate" smt="(assert (and memRead memWrite memAllocate))"
func memoryToString(mem: MemoryBoundary): string {.raises: [].} =
  let modeLabel = case mem.accessMode
    of memRead: "read"
    of memWrite: "write"
    of memAllocate: "alloc"
  "(" & modeLabel & " " & mem.region & ")"

# @axiom-hint: lean="eff_severity ≥ -9223372036854775808 ∧ eff_severity ≤ 9223372036854775807" smt="(assert (and (and (>= eff_severity -9223372036854775808) (<= eff_severity 9223372036854775807))))"
# @axiom-hint: lean="effPure ∧ effNoSideEffect ∧ effIO ∧ effNetwork ∧ effFileSystem ∧ effUnknown" smt="(assert (and effPure effNoSideEffect effIO effNetwork effFileSystem effUnknown))"
func effectToString(eff: EffectConstraint): string {.raises: [].} =
  let kindLabel = case eff.kind
    of effPure: "pure"
    of effNoSideEffect: "noSideEffect"
    of effIO: "io"
    of effNetwork: "network"
    of effFileSystem: "filesystem"
    of effUnknown: "unknown"
  "(" & kindLabel & " " & $eff.severity & ")"

# @axiom-hint: lean="tc_sourceType.length ≥ 0 ∧ tc_targetType.length ≥ 0 ∧ tc_constraints.size ≥ 0" smt="(assert (and (>= (str.len tc_sourceType) 0) (>= (str.len tc_targetType) 0) (>= (seq.len tc_constraints) 0)))"
# @axiom-hint: lean="parts.length > 0" smt="(assert (and (> (str.len parts) 0)))"
func typeContractToString(tc: TypeContract): string {.raises: [].} =
  var parts: seq[string] = @[]
  for c in tc.constraints:
    parts.add(c)
  "(" & tc.sourceType & " -> " & tc.targetType &
    (if parts.len > 0: " " & parts.join(" ") else: "") & ")"

## To SExpr.
func toSExpr*(node: FrontendIrNode; level: int = 0): string {.raises: [].} =
  ## Convert an IR node to a language-neutral S-expression string.
  let kindLabel = case node.kind
    of inkModule: "module"
    of inkFunction: "function"
    of inkProcedure: "procedure"
    of inkLoop: "loop"
    of inkConditional: "conditional"
    of inkAssignment: "assignment"
    of inkCall: "call"
    of inkReturn: "return"

  var header = "(" & kindLabel
  if node.name.len > 0:
    header.add(" " & node.name)
  header.add(")")

  result = indentLine(level, header) & "\n"

  if node.sourceLanguage.len > 0:
    result.add(indentLine(level + 1, "; lang: " & node.sourceLanguage) & "\n")

  for inv in node.invariants:
    result.add(indentLine(level + 1, "; inv: " & invariantToString(inv)) & "\n")

  for mem in node.memoryBoundaries:
    result.add(indentLine(level + 1, "; mem: " & memoryToString(mem)) & "\n")

  for eff in node.effectConstraints:
    result.add(indentLine(level + 1, "; eff: " & effectToString(eff)) & "\n")

  for tc in node.typeContracts:
    result.add(indentLine(level + 1, "; type: " & typeContractToString(tc)) & "\n")

  for child in node.children:
    result.add(toSExpr(child, level + 1))

# ---------------------------------------------------------------------------
# Lean 4 contract extraction
# ---------------------------------------------------------------------------

## To Lean Contract.
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
# @axiom-hint: lean="preConds.length > 0 ∧ postConds.length > 0 ∧ loopInvs.length > 0 ∧ invPre ∧ invPost ∧ invLoop ∧ effPure ∧ effNoSideEffect ∧ effIO ∧ effNetwork ∧ effFileSystem ∧ effUnknown ∧ memRead ∧ memWrite ∧ memAllocate ∧ (result ≥ 0)" smt="(assert (and (> (str.len preConds) 0) (> (str.len postConds) 0) (> (str.len loopInvs) 0) invPre invPost invLoop effPure effNoSideEffect effIO effNetwork effFileSystem effUnknown memRead memWrite memAllocate (>= result 0)))"
func toLeanContract*(node: FrontendIrNode): string {.raises: [].} =
  ## Extract a Lean 4-friendly logical contract from an IR node.
  ## Returns a plain-text block that can be embedded in a Leanstral prompt.
  if node.name.len == 0:
    return ""

  result = "Logical Contract for '" & node.name & "':\n"

  var preConds: seq[string] = @[]
  var postConds: seq[string] = @[]
  var loopInvs: seq[string] = @[]

  for inv in node.invariants:
    case inv.scope
    of invPre:
      preConds.add(inv.predicate)
    of invPost:
      postConds.add(inv.predicate)
    of invLoop:
      loopInvs.add(inv.predicate)

  if preConds.len > 0:
    result.add("  Pre:  " & preConds.join(" /\\ ") & "\n")
  if postConds.len > 0:
    result.add("  Post: " & postConds.join(" /\\ ") & "\n")
  if loopInvs.len > 0:
    result.add("  Loop: " & loopInvs.join(" /\\ ") & "\n")

  if node.effectConstraints.len > 0:
    var effs: seq[string] = @[]
    for eff in node.effectConstraints:
      let label = case eff.kind
        of effPure: "pure"
        of effNoSideEffect: "noSideEffect"
        of effIO: "IO"
        of effNetwork: "network"
        of effFileSystem: "filesystem"
        of effUnknown: "unknown"
      effs.add(label)
    result.add("  Effects: " & effs.join(", ") & "\n")

  if node.memoryBoundaries.len > 0:
    var mems: seq[string] = @[]
    for mem in node.memoryBoundaries:
      let label = case mem.accessMode
        of memRead: "read"
        of memWrite: "write"
        of memAllocate: "alloc"
      mems.add(label & "(" & mem.region & ")")
    result.add("  Memory: " & mems.join(", ") & "\n")

# @axiom-hint: lean="nameEnd > 0 ∧ spacePos > 0 ∧ hasNoSideEffect ∨ hasPure ∧ inFunction = true ∧ hasNoSideEffect = true ∧ hasPure = true ∧ scope = invPost ∧ scope = invLoop ∧ inFunction = false ∧ (hasNoSideEffect ≥ 0) ∧ (lines ≥ 0) ∧ (inFunction ≥ 0) ∧ (hasPure ≥ 0) ∧ (scope ≥ 0) ∧ (result ≥ 0) ∧ (currentFunc ≥ 0)" smt="(assert (and (> nameEnd 0) (> spacePos 0) (or hasNoSideEffect hasPure) (= inFunction true) (= hasNoSideEffect true) (= hasPure true) (= scope invPost) (= scope invLoop) (= inFunction false) (>= hasNoSideEffect 0) (>= lines 0) (>= inFunction 0) (>= hasPure 0) (>= scope 0) (>= result 0) (>= currentFunc 0)))"
func parseNimToIR*(source: string; modulePath: string): FrontendIrNode {.raises: [].} =
  result = FrontendIrNode(kind: inkModule, name: modulePath, sourceLanguage: "nim")
  let lines = source.splitLines()
  var inFunction = false
  var currentFunc = ""
  for i, line in lines:
    let stripped = line.strip()
    if stripped.startsWith("proc ") or stripped.startsWith("func "):
      inFunction = true
      let nameEnd = stripped.find('(')
      if nameEnd > 0:
        currentFunc = stripped[5 ..< nameEnd].strip()
      else:
        let spacePos = stripped.find(' ', 5)
        if spacePos > 0:
          currentFunc = stripped[5 ..< spacePos].strip()
        else:
          currentFunc = stripped[5..^1].strip()
      result.children.add(
        FrontendIrNode(kind: inkFunction, name: currentFunc, sourceLanguage: "nim")
      )
    elif stripped.startsWith("{." & "push raises:") or stripped.startsWith("{.pragma "):
      var hasNoSideEffect = false
      var hasPure = false
      let raw = stripped.replace("{", "").replace("}", "")
      for part in raw.split(','):
        let p = part.strip().toLowerAscii()
        if p == "noSideEffect": hasNoSideEffect = true
        if p == "pure": hasPure = true
      if hasNoSideEffect or hasPure:
        let effect = EffectConstraint(kind: effNoSideEffect, severity: 1)
        if result.children.len > 0:
          result.children[^1].effectConstraints.add(effect)
        else:
          result.effectConstraints.add(effect)
    elif stripped.startsWith("##"):
      let bodyLower = stripped.toLowerAscii()
      if "requires" in bodyLower or "ensures" in bodyLower or "invariant" in bodyLower:
        var scope = invPre
        if "ensures" in bodyLower:
          scope = invPost
        elif "invariant" in bodyLower:
          scope = invLoop
        let inv = InvariantCondition(predicate: stripped, scope: scope)
        if result.children.len > 0:
          result.children[^1].invariants.add(inv)
        else:
          result.invariants.add(inv)
    elif inFunction and stripped.contains("return "):
      let ret = FrontendIrNode(kind: inkReturn, sourceLanguage: "nim", sourceRef: $i)
      if result.children.len > 0:
        result.children[^1].children.add(ret)
    elif inFunction and stripped == "":
      inFunction = false
      currentFunc = ""
func extractTypeContract*(ir: FrontendIrNode; procName: string): seq[InvariantCondition] {.raises: [].} =
  for node in ir.children:
    if node.name == procName:
      return node.invariants
func extractEffectConstraints*(ir: FrontendIrNode; procName: string): seq[EffectConstraint] {.raises: [].} =
  for node in ir.children:
    if node.name == procName:
      return node.effectConstraints
{.pop.}
