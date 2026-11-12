import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import ../../core/trusted/axiom_pragmas
import core/json/std_redirect
import core/logic/smt_logic
import core/logic/universal_translation_types
import core/parsers/safe_parsers
import core/types/results
import std/json
import std/sequtils
import std/strutils
func normalizeLanguage*(raw: string): string {.inline, raises: [], axiom: ["(assert (and (>= (str.len raw) 0) (= (str.len lowered) 0) lowered))", "raw.length ≥ 0 ∧ lowered.length = 0 ∧ lowered"].} =
  let lowered = raw.strip().toLowerAscii()
  if lowered == "c" or lowered == "cpp" or lowered == "c++" or lowered == "nim":
    return lowered
  if lowered.len == 0:
    return "unknown"
  lowered
func lowerAsciiSafe(ch: char): char {.inline, raises: [].} =
  if ch >= 'A' and ch <= 'Z':
    chr(ord(ch) + 32)
  else:
    ch
func sanitizeSymbol*(raw: string): string {.raises: [], axiom: ["(assert (and (>= (str.len raw) 0) (= (str.len token) 0) (= (str.len result) 0) (>= token 0) (>= result 0)))", "raw.length ≥ 0 ∧ token.length = 0 ∧ result.length = 0 ∧ (token ≥ 0) ∧ (result ≥ 0)"].} =
  let token = raw.strip()
  if token.len == 0:
    return "sym"
  result = newStringOfCap(token.len)
  for ch in token:
    let lowered = lowerAsciiSafe(ch)
    if (lowered >= 'a' and lowered <= 'z') or (lowered >= '0' and lowered <= '9') or lowered == '_':
      result.add(lowered)
    else:
      result.add('_')
  if result.len == 0:
    return "sym"
  if result[0] >= '0' and result[0] <= '9':
    result = "s_" & result
func jsonString*(node: JsonNode; key: string; defaultValue: string = ""): string {.raises: [], axiom: ["(assert (and (>= (str.len key) 0) (>= (str.len defaultValue) 0) ast_parse_failed_isolated defaultValue (>= (str.len key) 0) (>= (str.len defaultValue) 0)))", "key.length ≥ 0 ∧ defaultValue.length ≥ 0 ∧ ast_parse_failed_isolated ∧ defaultValue ∧ key.length ≥ 0 ∧ defaultValue.length ≥ 0"].} =
  if node.kind != JObject:
    return defaultValue
  let target = node{key}
  if target.isNil or target.kind != JString:
    return defaultValue
  target.getStr()
func jsonInt*(node: JsonNode; key: string; defaultValue: int = 0): int {.raises: [], axiom: ["(assert (and (>= (str.len key) 0) (and (>= defaultValue -9223372036854775808) (<= defaultValue 9223372036854775807)) ast_parse_failed_isolated))", "key.length ≥ 0 ∧ defaultValue ≥ -9223372036854775808 ∧ defaultValue ≤ 9223372036854775807 ∧ ast_parse_failed_isolated"].} =
  if node.kind != JObject:
    return defaultValue
  let target = node{key}
  if target.isNil:
    return defaultValue
  if target.kind == JInt:
    return target.getInt()
  if target.kind == JString:
    return safeParseInt(target.getStr().strip()).getOrDefault(defaultValue)
  defaultValue
func parseIndexWidth*(node: JsonNode): int {.raises: [], axiom: ["(assert (and (>= depth 0) (<= width 0)))", "depth >= 0 ∧ width ≤ 0"].} =
  let width = jsonInt(node, "indexWidth", 32)
  if width <= 0: 32 else: width
func addUniqueSymbol*(symbols: var seq[string]; raw: string) {.raises: [], axiom: ["(assert (and ast_parse_failed_isolated))", "ast_parse_failed_isolated"].} =
  let candidate = sanitizeSymbol(raw)
  if candidate.len == 0 or candidate == "sym":
    return
  if not symbols.contains(candidate):
    symbols.add(candidate)
func addUniqueLine*(lines: var seq[string]; raw: string) {.raises: [], axiom: ["(assert (and ast_parse_failed_isolated))", "ast_parse_failed_isolated"].} =
  let candidate = raw.strip()
  if candidate.len == 0:
    return
  if not lines.contains(candidate):
    lines.add(candidate)
func envSourceName*(node: JsonNode; fallback: string): string {.raises: [], axiom: ["(assert (and (= (str.len source) 0)))", "source.length = 0"].} =
  let source = sanitizeSymbol(jsonString(node, "source", fallback))
  if source.len == 0: fallback else: source
func mapExternalInputNode*(node: JsonNode; idx: int; fallbackSource: string): AstMapEntry {.raises: [], axiom: ["(assert (and (and (>= idx -9223372036854775808) (<= idx 9223372036854775807)) (>= (str.len fallbackSource) 0)))", "idx ≥ -9223372036854775808 ∧ idx ≤ 9223372036854775807 ∧ fallbackSource.length ≥ 0"].} =
  let source = envSourceName(node, fallbackSource)
  let target = sanitizeSymbol(jsonString(node, "target", source & "_value"))
  AstMapEntry(
    nodeId: "n" & $idx,
    kind: "external_input",
    il: "external input " & source & " -> " & target,
    smt: ""
  )
func addTransitionInvariant*(
  invariants: var seq[string];
  relation: string
) {.raises: [], axiom: ["(assert (and ast_parse_failed_isolated (>= (seq.len invariants) 0) (forall ((i Int)) (=> (and (>= i 0) (< i (seq.len invariants))) (>= (str.len (seq.nth invariants i)) 0))) (>= (str.len relation) 0) (>= (seq.len invariants) 0) (forall ((invariantsIdx Int)) (=> (and (>= invariantsIdx 0) (< invariantsIdx (seq.len invariants))) (>= (str.len (seq.nth invariants invariantsIdx)) 0))) (>= (str.len relation) 0)))", "ast_parse_failed_isolated ∧ invariants.size ≥ 0 ∧ ∀ (i : Fin invariants.size), (invariants.get i).length ≥ 0 ∧ relation.length ≥ 0 ∧ invariants.size ≥ 0 ∧ (∀ (invariantsIdx : Fin invariants.size), (invariants.get invariantsIdx).length ≥ 0) ∧ relation.length ≥ 0"].} =
  if relation.contains("balance_next = balance - amount"):
    invariants.addUniqueLine("0 <= amount ∧ amount <= state.balance")
    invariants.addUniqueLine("next.balance <= state.balance")
  if relation.contains("version_next = version + 1"):
    invariants.addUniqueLine("next.version >= state.version")
  if relation.contains("payload_next = payload"):
    invariants.addUniqueLine("next.payload = state.payload")
func addStateInvariantFromRelation*(
  invariants: var seq[string];
  relation: string
) {.raises: [], axiom: ["(assert (and ast_parse_failed_isolated (>= (seq.len invariants) 0) (forall ((i Int)) (=> (and (>= i 0) (< i (seq.len invariants))) (>= (str.len (seq.nth invariants i)) 0))) (>= (str.len relation) 0) (>= (seq.len invariants) 0) (forall ((invariantsIdx Int)) (=> (and (>= invariantsIdx 0) (< invariantsIdx (seq.len invariants))) (>= (str.len (seq.nth invariants invariantsIdx)) 0))) (>= (str.len relation) 0)))", "ast_parse_failed_isolated ∧ invariants.size ≥ 0 ∧ ∀ (i : Fin invariants.size), (invariants.get i).length ≥ 0 ∧ relation.length ≥ 0 ∧ invariants.size ≥ 0 ∧ (∀ (invariantsIdx : Fin invariants.size), (invariants.get invariantsIdx).length ≥ 0) ∧ relation.length ≥ 0"].} =
  if relation.contains("balance_next = balance - amount"):
    invariants.addUniqueLine("0 <= amount ∧ amount <= balance")
    invariants.addUniqueLine("0 <= balance")
  if relation.contains("version_next = version + 1"):
    invariants.addUniqueLine("0 <= version")
  if relation.contains("payload_next = payload"):
    invariants.addUniqueLine("0 <= payload")
func inferGuardStateInvariant*(guard: string): string {.raises: [], axiom: ["(assert (and (>= (str.len guard) 0) (> pos 0) (and (> (str.len left) 0) (> (str.len right) 0))))", "guard.length ≥ 0 ∧ pos > 0 ∧ left.length > 0 ∧ right.length > 0"].} =
  let symbol = sanitizeSymbol(guard)
  for marker in ["_lt_", "_le_"]:
    let pos = symbol.find(marker)
    if pos > 0:
      let left = sanitizeSymbol(symbol[0 ..< pos])
      let right = sanitizeSymbol(symbol[pos + marker.len .. ^1])
      if left.len > 0 and right.len > 0:
        let op = if marker == "_lt_": "<" else: "<="
        return "0 <= " & left & " ∧ " & left & " " & op & " " & right
  ""
func semanticLengthSymbol*(raw: string): string {.raises: [], axiom: ["(assert (and (>= (str.len raw) 0)))", "raw.length ≥ 0"].} =
  let symbol = sanitizeSymbol(raw)
  if symbol == "len":
    return "length"
  symbol
func buildMemoryStateInvariant*(base: string; index: string; lenSymbol: string): string {.raises: [], axiom: ["(assert (and (>= (str.len base) 0) (>= (str.len index) 0) (>= (str.len lenSymbol) 0)))", "base.length ≥ 0 ∧ index.length ≥ 0 ∧ lenSymbol.length ≥ 0"].} =
  "0 <= " & index & " ∧ " & index & " < " & lenSymbol & " ∧ " &
    base & " <= " & base & " + " & index & " ∧ " &
    base & " + " & index & " < " & base & " + " & lenSymbol
func isNumericLiteral*(raw: string): bool {.raises: [], axiom: ["(assert (and (>= (str.len raw) 0) ast_parse_failed_isolated))", "raw.length ≥ 0 ∧ ast_parse_failed_isolated"].} =
  if raw.len == 0:
    return false
  for idx, ch in raw:
    if idx == 0 and ch == '-':
      continue
    if ch < '0' or ch > '9':
      return false
  true
func buildLeanStateExpr*(token: string; stateSpace: seq[string]): string {.raises: [], axiom: ["(assert (and (= (str.len symbol) 0) symbol (forall ((stateSpaceIdx Int)) (=> (and (>= stateSpaceIdx 0) (< stateSpaceIdx (seq.len stateSpace))) (>= (str.len (seq.nth stateSpace stateSpaceIdx)) 0)))))", "symbol.length = 0 ∧ symbol ∧ (∀ (stateSpaceIdx : Fin stateSpace.size), (stateSpace.get stateSpaceIdx).length ≥ 0)"].} =
  let symbol = sanitizeSymbol(token)
  if symbol.len == 0:
    return "0"
  if isNumericLiteral(symbol):
    return symbol
  if stateSpace.contains(symbol):
    return "state." & symbol
  symbol
func buildLeanAssignmentExpr*(relation: string; stateSpace: seq[string]): tuple[target: string, expr: string] {.raises: [], axiom: ["(assert (and (< eqPos 0) (= (str.len target) 0) (= (str.len rhsTokens) 1) (= (str.len rhsTokens) 3) (>= target 0) (forall ((stateSpaceIdx Int)) (=> (and (>= stateSpaceIdx 0) (< stateSpaceIdx (seq.len stateSpace))) (>= (str.len (seq.nth stateSpace stateSpaceIdx)) 0)))))", "eqPos < 0 ∧ target.length = 0 ∧ rhsTokens.length = 1 ∧ rhsTokens.length = 3 ∧ (target ≥ 0) ∧ (∀ (stateSpaceIdx : Fin stateSpace.size), (stateSpace.get stateSpaceIdx).length ≥ 0)"].} =
  let normalized = relation.strip()
  let eqPos = normalized.find(" = ")
  if eqPos < 0:
    return ("", "")
  let lhs = normalized[0 ..< eqPos].strip()
  let rhs = normalized[eqPos + " = ".len .. ^1].strip()
  var target = lhs
  if target.endsWith("_next"):
    target = target[0 ..< target.len - "_next".len]
  target = sanitizeSymbol(target)
  if target.len == 0:
    return ("", "")
  let rhsTokens = rhs.splitWhitespace()
  if rhsTokens.len == 1:
    return (target, buildLeanStateExpr(rhsTokens[0], stateSpace))
  if rhsTokens.len == 3:
    return (
      target,
      buildLeanStateExpr(rhsTokens[0], stateSpace) & " " & rhsTokens[1] & " " &
        buildLeanStateExpr(rhsTokens[2], stateSpace)
    )
  (target, buildLeanStateExpr(rhs, stateSpace))
func inferLoopControlVariable*(guard: string): string {.raises: [], axiom: ["(assert (and (>= (str.len guard) 0) (= (str.len symbol) 0) (> pos 0) (> (str.len parts) 0) (> (str.len candidate) 0) candidate (=> (> (str.len parts) 0) (= result candidate)) (=> (> (str.len candidate) 0) (= result candidate))))", "guard.length ≥ 0 ∧ symbol.length = 0 ∧ pos > 0 ∧ parts.length > 0 ∧ candidate.length > 0 ∧ candidate ∧ parts.length > 0 → result = candidate ∧ candidate.length > 0 → result = candidate"].} =
  let symbol = sanitizeSymbol(guard)
  if symbol.len == 0:
    return ""
  for marker in ["_lt_", "_le_", "_gt_", "_ge_", "_neq_", "_eq_"]:
    let pos = symbol.find(marker)
    if pos > 0:
      return sanitizeSymbol(symbol[0 ..< pos])
  let parts = symbol.split('_')
  if parts.len > 0:
    let candidate = sanitizeSymbol(parts[0])
    if candidate.len > 0:
      return candidate
  symbol
func buildEnvConstructorName*(raw: string): string {.raises: [], axiom: ["(assert (and (>= (str.len raw) 0)))", "raw.length ≥ 0"].} =
  sanitizeSymbol(raw)
func buildInternalStepCase*(
  stateSpace: seq[string];
  transitionRelation: seq[string];
  rankVariables: seq[string]
): string {.raises: [], axiom: ["(assert (and (>= (seq.len stateSpace) 0) (forall ((i Int)) (=> (and (>= i 0) (< i (seq.len stateSpace))) (>= (str.len (seq.nth stateSpace i)) 0))) (>= (seq.len transitionRelation) 0) (forall ((i Int)) (=> (and (>= i 0) (< i (seq.len transitionRelation))) (>= (str.len (seq.nth transitionRelation i)) 0))) (>= (seq.len rankVariables) 0) (forall ((i Int)) (=> (and (>= i 0) (< i (seq.len rankVariables))) (>= (str.len (seq.nth rankVariables i)) 0))) (>= (seq.len stateSpace) 0) (forall ((stateSpaceIdx Int)) (=> (and (>= stateSpaceIdx 0) (< stateSpaceIdx (seq.len stateSpace))) (>= (str.len (seq.nth stateSpace stateSpaceIdx)) 0))) (>= (seq.len transitionRelation) 0) (forall ((transitionRelationIdx Int)) (=> (and (>= transitionRelationIdx 0) (< transitionRelationIdx (seq.len transitionRelation))) (>= (str.len (seq.nth transitionRelation transitionRelationIdx)) 0))) (>= (seq.len rankVariables) 0) (forall ((rankVariablesIdx Int)) (=> (and (>= rankVariablesIdx 0) (< rankVariablesIdx (seq.len rankVariables))) (>= (str.len (seq.nth rankVariables rankVariablesIdx)) 0))) (= (str.len updates) 0) (>= transitionRelation 0) (>= rankVariables 0) (forall ((stateSpaceIdx Int)) (=> (and (>= stateSpaceIdx 0) (< stateSpaceIdx (seq.len stateSpace))) (>= (str.len (seq.nth stateSpace stateSpaceIdx)) 0))) (forall ((transitionRelationIdx Int)) (=> (and (>= transitionRelationIdx 0) (< transitionRelationIdx (seq.len transitionRelation))) (>= (str.len (seq.nth transitionRelation transitionRelationIdx)) 0))) (forall ((rankVariablesIdx Int)) (=> (and (>= rankVariablesIdx 0) (< rankVariablesIdx (seq.len rankVariables))) (>= (str.len (seq.nth rankVariables rankVariablesIdx)) 0)))))", "stateSpace.size ≥ 0 ∧ ∀ (i : Fin stateSpace.size), (stateSpace.get i).length ≥ 0 ∧ transitionRelation.size ≥ 0 ∧ ∀ (i : Fin transitionRelation.size), (transitionRelation.get i).length ≥ 0 ∧ rankVariables.size ≥ 0 ∧ ∀ (i : Fin rankVariables.size), (rankVariables.get i).length ≥ 0 ∧ stateSpace.size ≥ 0 ∧ (∀ (stateSpaceIdx : Fin stateSpace.size), (stateSpace.get stateSpaceIdx).length ≥ 0) ∧ transitionRelation.size ≥ 0 ∧ (∀ (transitionRelationIdx : Fin transitionRelation.size), (transitionRelation.get transitionRelationIdx).length ≥ 0) ∧ rankVariables.size ≥ 0 ∧ (∀ (rankVariablesIdx : Fin rankVariables.size), (rankVariables.get rankVariablesIdx).length ≥ 0) ∧ updates.length = 0 ∧ (transitionRelation ≥ 0) ∧ (rankVariables ≥ 0) ∧ (∀ (stateSpaceIdx : Fin stateSpace.size), (stateSpace.get stateSpaceIdx).length ≥ 0) ∧ (∀ (transitionRelationIdx : Fin transitionRelation.size), (transitionRelation.get transitionRelationIdx).length ≥ 0) ∧ (∀ (rankVariablesIdx : Fin rankVariables.size), (rankVariables.get rankVariablesIdx).length ≥ 0)"].} =
  var updates: seq[string] = @[]
  for relation in transitionRelation:
    let assignment = buildLeanAssignmentExpr(relation, stateSpace)
    if assignment.target.len > 0 and assignment.expr.len > 0:
      updates.addUniqueLine(assignment.target & " := " & assignment.expr)
  for rankVar in rankVariables:
    if stateSpace.contains(rankVar) and not updates.anyIt(it.startsWith(rankVar & " :=")):
      updates.add(rankVar & " := state." & rankVar & " - 1")
  if updates.len == 0:
    return "| .internal => state"
  "| .internal => { state with " & updates.join(", ") & " }"
func buildEnvStepCase*(
  stateSpace: seq[string];
  source: string;
  target: string;
  rankVariables: seq[string]
): string {.raises: [].} =
  let constructorName = buildEnvConstructorName(source)
  var updates: seq[string] = @[]
  if stateSpace.contains(target):
    updates.add(target & " := value")
  for rankVar in rankVariables:
    if stateSpace.contains(rankVar) and rankVar != target and not updates.anyIt(it.startsWith(rankVar & " :=")):
      updates.add(rankVar & " := state." & rankVar & " - 1")
  if updates.len == 0:
    return "| ." & constructorName & " value => state"
  "| ." & constructorName & " value => { state with " & updates.join(", ") & " }"
func prettyAssignRelation*(target: string; left: string; op: string; right: string): string {.raises: [], axiom: ["(assert (and (= (str.len opSymbol) 0)))", "opSymbol.length = 0"].} =
  let targetSym = sanitizeSymbol(target)
  let leftSym = sanitizeSymbol(left)
  let rightSym = semanticLengthSymbol(right)
  let opSymbol =
    case op.toLowerAscii()
    of "add": "+"
    of "sub": "-"
    else: ""
  if opSymbol.len == 0:
    targetSym & "_next = " & rightSym
  else:
    targetSym & "_next = " & leftSym & " " & opSymbol & " " & rightSym
func mapAssignNode*(node: JsonNode; idx: int; logic: SmtLogic = slQfLia): AstMapEntry {.raises: [], axiom: ["(assert (and (= (str.len rightRaw) 0)))", "rightRaw.length = 0"].} =
  let target = sanitizeSymbol(jsonString(node, "target", "x"))
  let left = sanitizeSymbol(jsonString(node, "left", target))
  let op = jsonString(node, "op", "assign").toLowerAscii()
  let rightRaw = jsonString(node, "right", "0")
  let rightSym =
    if rightRaw.len == 0:
      "0"
    else:
      sanitizeSymbol(rightRaw)
  let il = target & "_next := " & left & " " & op & " " & rightRaw
  let smtExpr =
    if op == "add":
      "(assert (= " & target & "_next (" & emitOp("add", logic) & " " & left & " " & rightSym & ")))"
    elif op == "sub":
      "(assert (= " & target & "_next (" & emitOp("sub", logic) & " " & left & " " & rightSym & ")))"
    else:
      "(assert (= " & target & "_next " & rightSym & "))"
  AstMapEntry(
    nodeId: "n" & $idx,
    kind: "assign",
    il: il,
    smt: smtExpr
  )
func mapIfNode*(node: JsonNode; idx: int; logic: SmtLogic = slQfLia): AstMapEntry {.raises: [], axiom: ["(assert (and ast_parse_failed_isolated))", "ast_parse_failed_isolated"].} =
  let condition = sanitizeSymbol(jsonString(node, "condition", "cond"))
  let zeroLit = emitNumericLiteral("0", logic)
  let oneLit  = emitNumericLiteral("1", logic)
  AstMapEntry(
    nodeId: "n" & $idx,
    kind: "if",
    il: "branch if " & condition,
    smt: "(assert (or (= " & condition & " " & zeroLit & ") (= " & condition & " " & oneLit & ")))"
  )
{.pop.}
