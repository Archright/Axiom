import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import core/judge/smart_search
import core/results
import core/utils/ident_utils
import core/utils/text_utils
import verification/solver/z3_pool
import std/strutils
type
  VacuityGateDecision* = object
    accepted*: bool
    reason*: string
    entropyPassed*: bool
    bindingPassed*: bool
    counterExamplePassed*: bool
    semanticTermCount*: int
    propositionSymbols*: seq[string]
    sourceSymbols*: seq[string]
    boundSymbols*: seq[string]
    isVacuousReject*: bool
# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
func isIdentPart(c: char): bool =
  c.isAlphaAscii() or c.isDigit() or c == '_' or c == '.'

# @axiom-hint: lean="symbol.length ≥ 0" smt="(assert (and (>= (str.len symbol) 0)))"
func isReservedSymbol(symbol: string): bool =
  let lower = symbol.toLowerAscii()
  lower in [
    "assert", "and", "or", "not", "true", "false", "forall", "exists",
    "theorem", "lemma", "def", "example", "import", "std", "by", "exact",
    "trivial", "rfl", "simp", "simpa", "using", "have", "show", "from",
    "fun", "match", "with", "if", "then", "else", "let", "in", "prop",
    "type", "nat", "int", "bool", "string", "char", "real", "fin",
    "qid", "set-logic", "check-sat", "declare-const", "declare-fun",
    "qf_lia", "all", "source", "context", "leanstral", "staticrule",
    "hintcomment", "intervalabstraction", "structuralinduction",
    "patternmatching"
  ]

# @axiom-hint: lean="source.length ≥ 0" smt="(assert (and (>= (str.len source) 0)))"
# @axiom-hint: lean="dotIdx > 0 ∧ i < source.length ∧ ((i ≥ 0) ∧ (i < source))" smt="(assert (and (> dotIdx 0) (< i (str.len source)) (and (>= i 0) (< i source))))"
func extractSemanticIdentifiers*(source: string): seq[string] =
  var i = 0
  while i < source.len:
    if isIdentStart(source[i]):
      let start = i
      inc i
      while i < source.len and isIdentPart(source[i]):
        inc i
      let token = source[start ..< i].strip(chars = {'.', '_'}).toLowerAscii()
      if token.len > 0 and not isReservedSymbol(token):
        result.addUnique(token)
        let dotIdx = token.find('.')
        if dotIdx > 0:
          let baseToken = token[0 ..< dotIdx]
          if baseToken.len > 0 and not isReservedSymbol(baseToken):
            result.addUnique(baseToken)
    else:
      inc i

# @axiom-hint: lean="source.length ≥ 0" smt="(assert (and (>= (str.len source) 0)))"
func normalizeOperators(source: string): string =
  source
    .replace("≥", ">=")
    .replace("≤", "<=")
    .replace("≠", "!=")
    .replace("∧", " and ")
    .replace("∨", " or ")
    .replace("∀", " forall ")
    .replace("∃", " exists ")
    .replace("¬", " not ")
func compactLower(source: string): string =
  for ch in source.normalizeOperators().toLowerAscii():
    if ch notin {' ', '\t', '\r', '\n'}:
      result.add(ch)

# @axiom-hint: lean="source.length ≥ 0" smt="(assert (and (>= (str.len source) 0)))"
# @axiom-hint: lean="isIdentStart() ∧ .() ∧ i < normalized.length ∧ i < normalized.length ∧ isIdentPart() ∧ i < normalized.length ∧ .() ∧ source.length ≥ 0" smt="(assert (and (isIdentStart ) (. ) (< i (str.len normalized)) (and (< i (str.len normalized)) (isIdentPart )) (and (< i (str.len normalized)) (. )) (>= (str.len source) 0)))"
# @axiom-hint: lean="i < normalized.length ∧ source.length ≥ 0" smt="(assert (and (< i (str.len normalized)) (>= (str.len source) 0)))"
func tokenizeRelations(source: string): seq[string] =
  let normalized = source.normalizeOperators()
  var i = 0
  while i < normalized.len:
    let c = normalized[i]
    if isIdentStart(c):
      let start = i
      inc i
      while i < normalized.len and isIdentPart(normalized[i]):
        inc i
      result.add(normalized[start ..< i].toLowerAscii())
    elif c.isDigit():
      let start = i
      inc i
      while i < normalized.len and normalized[i].isDigit():
        inc i
      result.add(normalized[start ..< i])
    elif c in {'=', '>', '<'}:
      if i + 1 < normalized.len and normalized[i + 1] == '=':
        result.add(normalized[i .. i + 1])
        i += 2
      else:
        result.add($c)
        inc i
    else:
      inc i

# @axiom-hint: lean="token.length ≥ 0" smt="(assert (and (>= (str.len token) 0)))"
func isSemanticAtom(token: string): bool =
  token.len > 0 and token notin ["=", ">=", "<=", ">", "<", "=>", ":", ":="] and
    not isReservedSymbol(token)

# @axiom-hint: lean="source.length ≥ 0" smt="(assert (and (>= (str.len source) 0)))"
func semanticTermCount(source: string): int =
  var seen: seq[string] = @[]
  for token in tokenizeRelations(source):
    if isSemanticAtom(token):
      seen.addUnique(token)
  seen.len
func isSelfRelation(source: string): bool =
  let tokens = tokenizeRelations(source)
  for i in 0 ..< max(tokens.len - 2, 0):
    let left = tokens[i]
    let op = tokens[i + 1]
    let right = tokens[i + 2]
    if op in ["=", ">=", "<="] and isSemanticAtom(left) and left == right:
      return true
  for i in 0 ..< max(tokens.len - 2, 0):
    let op = tokens[i]
    let left = tokens[i + 1]
    let right = tokens[i + 2]
    if op in ["=", ">=", "<="] and isSemanticAtom(left) and left == right:
      return true
  false
func hasMeaningfulRelation(source: string): bool =
  let tokens = tokenizeRelations(source)
  for i in 0 ..< max(tokens.len - 2, 0):
    let left = tokens[i]
    let op = tokens[i + 1]
    let right = tokens[i + 2]
    if op in ["=", ">=", "<=", ">", "<"] and isSemanticAtom(left) and
        isSemanticAtom(right) and left != right:
      return true
  for i in 0 ..< max(tokens.len - 2, 0):
    let op = tokens[i]
    let left = tokens[i + 1]
    let right = tokens[i + 2]
    if op in ["=", ">=", "<=", ">", "<"] and isSemanticAtom(left) and
        isSemanticAtom(right) and left != right:
      return true
  false

func stripComments*(source: string): string =
  for line in source.splitLines():
    let stripped = line.strip()
    if stripped.startsWith("--") or stripped.startsWith("#"):
      continue
    let commentIdx = line.find("--")
    if commentIdx >= 0:
      result.add(line[0 ..< commentIdx])
      result.add("\n")
    else:
      result.add(line)
      result.add("\n")

# @axiom-hint: lean="stripped.length = 0" smt="(assert (and (= (str.len stripped) 0)))"
func leanVacuityReason*(leanSource: string): string =
  let stripped = leanSource.strip()
  if stripped.len == 0:
    return "theorem source is empty"
  let compact = compactLower(stripped)
  if compact == "true" or compact == "bytrivial" or compact == "trivial":
    return "proposition is trivially True"
  if ":true:=" in compact or ":true:=by" in compact or "exacttrue.intro" in compact:
    return "proposition is trivially True"
  if "bytrivial" in compact and ":true" in compact:
    return "proposition is trivially True"
  if isSelfRelation(stripped):
    return "self-equality tautology"
  ""

# @axiom-hint: lean="smtConstraint.length ≥ 0" smt="(assert (and (>= (str.len smtConstraint) 0)))"
# @axiom-hint: lean="stripped.length = 0" smt="(assert (and (= (str.len stripped) 0)))"
func smtVacuityReason*(smtConstraint: string): string =
  let stripped = smtConstraint.strip()
  if stripped.len == 0:
    return ""
  let compact = compactLower(stripped)
  if compact == "(asserttrue)" or compact == "true":
    return "SMT constraint is vacuous (assert true)"
  if isSelfRelation(stripped):
    return "SMT constraint is a self-relation tautology"
  ""

# @axiom-hint: lean="source.length ≥ 0" smt="(assert (and (>= (str.len source) 0)))"
# @axiom-hint: lean="startIdx < 0 ∧ startIdx = i ∧ source ∧ startIdx < 0 → result = source ∧ (lines ≥ 0) ∧ (startIdx ≥ 0)" smt="(assert (and (< startIdx 0) (= startIdx i) source (=> (< startIdx 0) (= result source)) (>= lines 0) (>= startIdx 0)))"
func proofSubjectSource(source: string): string =
  let lines = source.splitLines()
  var startIdx = -1
  for i, line in lines:
    let stripped = line.strip().toLowerAscii()
    if stripped.startsWith("theorem ") or stripped.startsWith("lemma ") or
        stripped.startsWith("example ") or stripped.startsWith("def "):
      startIdx = i
  if startIdx < 0:
    return source
  lines[startIdx .. ^1].join("\n")

# @axiom-hint: lean="proofIdx < 0 ∧ subject ∧ proofIdx < 0 → result = subject" smt="(assert (and (< proofIdx 0) subject (=> (< proofIdx 0) (= result subject))))"
func proofSemanticPayload(source: string): string =
  let subject = proofSubjectSource(source)
  let proofIdx = subject.find(":=")
  if proofIdx < 0:
    return subject
  var parenDepth = 0
  for i in countdown(proofIdx - 1, 0):
    let c = subject[i]
    if c == ')':
      inc parenDepth
    elif c == '(':
      dec parenDepth
    elif c == ':' and parenDepth == 0:
      return subject[i + 1 ..< proofIdx]
  subject

# @axiom-hint: lean="(propSymbols ≥ 0) ∧ (∀ (propSymbolsIdx : Fin propSymbols.size), (propSymbols.get propSymbolsIdx).length ≥ 0) ∧ (∀ (sourceSymbolsIdx : Fin sourceSymbols.size), (sourceSymbols.get sourceSymbolsIdx).length ≥ 0)" smt="(assert (and (>= propSymbols 0) (forall ((propSymbolsIdx Int)) (=> (and (>= propSymbolsIdx 0) (< propSymbolsIdx (seq.len propSymbols))) (>= (str.len (seq.nth propSymbols propSymbolsIdx)) 0))) (forall ((sourceSymbolsIdx Int)) (=> (and (>= sourceSymbolsIdx 0) (< sourceSymbolsIdx (seq.len sourceSymbols))) (>= (str.len (seq.nth sourceSymbols sourceSymbolsIdx)) 0)))))"
func collectBoundSymbols(propSymbols, sourceSymbols: seq[string]): seq[string] =
  for symbol in propSymbols:
    if symbol in sourceSymbols:
      result.addUnique(symbol)

# @axiom-hint: lean="leanSource.length ≥ 0 ∧ smtConstraint.length ≥ 0 ∧ nodeId.length ≥ 0 ∧ sourceContext.length ≥ 0" smt="(assert (and (>= (str.len leanSource) 0) (>= (str.len smtConstraint) 0) (>= (str.len nodeId) 0) (>= (str.len sourceContext) 0)))"
# @axiom-hint: lean="leanReason.length > 0 ∧ smtReason.length > 0 ∧ bindingRequired ∧ (result ≥ 0)" smt="(assert (and (> (str.len leanReason) 0) (> (str.len smtReason) 0) bindingRequired (>= result 0)))"
func sourceHasAxiomDenseProofPragma(source: string): bool =
  for line in source.splitLines():
    let stripped = line.strip().toLowerAscii()
    if stripped.contains("{.pragma: axiomDenseProof"):
      return true
  false

func hasSecurityConstraintsInSource*(sourceContext: string;
                                      smtConstraint: string = ""): bool =
  if (sourceContext & "\n" & smtConstraint).strip().len == 0: return false
  let stripped = stripComments(sourceContext)
  let lower = (stripped & "\n" & smtConstraint).toLowerAscii()
  if "assert" in lower or "doassert" in lower: return true
  if "if " in lower or "if\t" in lower: return true
  if hasMeaningfulRelation(stripped) or hasMeaningfulRelation(smtConstraint): return true
  false

# @axiom-hint: lean="leanSource.length ≥ 0 \u2227 smtConstraint.length ≥ 0 \u2227 informationGain ≥ 0.0" smt="(assert (and (>= (str.len leanSource) 0) (>= (str.len smtConstraint) 0) (>= informationGain 0.0)))"
func validateVacuityParts*(
  leanSource: string;
  smtConstraint: string;
  nodeId: string = "";
  sourceContext: string = "";
  informationGain: float = 0.0;
  reduceResultIsVacuous: bool = false
): VacuityGateDecision =
  let hasSecurityConstraints = hasSecurityConstraintsInSource(sourceContext, smtConstraint)

  # Phase 0: #reduce-based vacuity detection
  if reduceResultIsVacuous:
    if hasSecurityConstraints:
      result.isVacuousReject = true
      result.reason = "Vacuous: goal reduces to True despite security constraints in source"
      return
    else:
      result.isVacuousReject = true
      result.reason = "Vacuous: goal reduces to True without security constraints"
      return

  let proofSubject = proofSemanticPayload(leanSource)
  let combined = proofSubject & "\n" & smtConstraint
  result.propositionSymbols = extractSemanticIdentifiers(combined)
  result.sourceSymbols = extractSemanticIdentifiers(sourceContext & "\n" & nodeId)
  result.boundSymbols = collectBoundSymbols(result.propositionSymbols, result.sourceSymbols)
  result.semanticTermCount = semanticTermCount(combined)

  let leanReason = leanVacuityReason(proofSubject)
  if leanReason.len > 0:
    result.reason = leanReason
    return

  let smtReason = smtVacuityReason(smtConstraint)
  if smtReason.len > 0:
    result.reason = smtReason
    return

  if not hasSecurityConstraints:
    result.reason = "security constraint gate failed: source and SMT constraints contain no non-trivial assertions or relations"
    return

  ## Phase 3: Entropy-based proof grading replaces semantic term count heuristic.
  let denseProofRelaxed = sourceHasAxiomDenseProofPragma(sourceContext)
  let gainThreshold = if denseProofRelaxed: 0.85 else: 1.0
  result.entropyPassed = informationGain >= gainThreshold or result.semanticTermCount >= 2
  if not result.entropyPassed:
    result.reason = "entropy gate failed: information gain " & $informationGain & " < 1.0 and semantic term count < 2"
    return

  let bindingRequired = sourceContext.strip().len > 0 or nodeId.strip().len > 0
  result.bindingPassed = if bindingRequired: result.boundSymbols.len > 0 else: true
  if not result.bindingPassed:
    result.reason = "symbolic binding failed: proposition is not bound to source symbols"
    return

  result.counterExamplePassed =
    if smtConstraint.strip().len > 0:
      hasMeaningfulRelation(smtConstraint)
    else:
      hasMeaningfulRelation(proofSubject)
  if not result.counterExamplePassed:
    result.reason = "counter-example gate failed: negation has no deterministic witness shape"
    return

  result.accepted = true

# @axiom-hint: lean="nodeId.length ≥ 0 ∧ sourceContext.length ≥ 0" smt="(assert (and (>= (str.len nodeId) 0) (>= (str.len sourceContext) 0)))"
func validateSemanticHintVacuity*(
  hint: SemanticHint;
  nodeId: string = "";
  sourceContext: string = ""
): VacuityGateDecision =
  ## For modules carrying {.axiomPure.} or {.axiomDenseProof.} pragma,
  ## run the same non-triviality checks as ordinary semantic hints.
  validateVacuityParts(hint.leanProposition, hint.smtConstraint, nodeId, sourceContext, informationGain = hint.informationGain)

# @axiom-hint: lean="nodeId.length ≥ 0 ∧ sourceContext.length ≥ 0" smt="(assert (and (>= (str.len nodeId) 0) (>= (str.len sourceContext) 0)))"
func semanticHintVacuityReason*(
  hint: SemanticHint;
  nodeId: string = "";
  sourceContext: string = ""
): string =
  let decision = validateSemanticHintVacuity(hint, nodeId, sourceContext)
  if decision.accepted:
    ""
  else:
    "vacuity_gate: " & decision.reason

# @axiom-hint: lean="theoremSource.length ≥ 0 ∧ smtConstraint.length ≥ 0 ∧ nodeId.length ≥ 0 ∧ sourceContext.length ≥ 0" smt="(assert (and (>= (str.len theoremSource) 0) (>= (str.len smtConstraint) 0) (>= (str.len nodeId) 0) (>= (str.len sourceContext) 0)))"
func leanSourceVacuityReason*(
  theoremSource: string;
  smtConstraint: string;
  nodeId: string = "";
  sourceContext: string = ""
): string =
  let decision = validateVacuityParts(theoremSource, smtConstraint, nodeId, sourceContext)
  if decision.accepted:
    ""
  else:
    decision.reason

# @axiom-hint: lean="decision_accepted = true ∨ decision_accepted = false ∧ decision_reason.length ≥ 0 ∧ decision_entropyPassed = true ∨ decision_entropyPassed = false ∧ decision_bindingPassed = true ∨ decision_bindingPassed = false ∧ decision_counterExamplePassed = true ∨ decision_counterExamplePassed = false ∧ decision_semanticTermCount ≥ -9223372036854775808 ∧ decision_semanticTermCount ≤ 9223372036854775807 ∧ decision_propositionSymbols.size ≥ 0 ∧ decision_sourceSymbols.size ≥ 0 ∧ decision_boundSymbols.size ≥ 0" smt="(assert (and (or (= decision_accepted true) (= decision_accepted false)) (>= (str.len decision_reason) 0) (or (= decision_entropyPassed true) (= decision_entropyPassed false)) (or (= decision_bindingPassed true) (= decision_bindingPassed false)) (or (= decision_counterExamplePassed true) (= decision_counterExamplePassed false)) (and (>= decision_semanticTermCount -9223372036854775808) (<= decision_semanticTermCount 9223372036854775807)) (>= (seq.len decision_propositionSymbols) 0) (>= (seq.len decision_sourceSymbols) 0) (>= (seq.len decision_boundSymbols) 0)))"
# @axiom-hint: lean="decision_accepted = true ∨ decision_accepted = false ∧ decision_entropyPassed = true ∨ decision_entropyPassed = false ∧ decision_bindingPassed = true ∨ decision_bindingPassed = false ∧ decision_counterExamplePassed = true ∨ decision_counterExamplePassed = false" smt="(assert (and (or (= decision_accepted true) (= decision_accepted false)) (or (= decision_entropyPassed true) (= decision_entropyPassed false)) (or (= decision_bindingPassed true) (= decision_bindingPassed false)) (or (= decision_counterExamplePassed true) (= decision_counterExamplePassed false))))"
func vacuityEvidenceLine*(decision: VacuityGateDecision): string =
  "[Entropy: " & (if decision.entropyPassed: "Pass" else: "Fail") &
    ", Binding: " & (if decision.bindingPassed: "Valid" else: "Invalid") &
    ", Counter-Ex: " & (if decision.counterExamplePassed: "Found" else: "Missing") & "]"
# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"

type VacuityProofStatus* = object
  leanReplayPass*: bool
  z3NonTrivialityPass*: bool
  negativeMutationPass*: bool
  nonVerifiedFallback*: bool
  fallbackReason*: string

func isGenuinelyProven*(status: VacuityProofStatus): bool =
  status.leanReplayPass and status.z3NonTrivialityPass and status.negativeMutationPass

proc verifyNonTrivialityWithFallback*(
  invariantClauses: seq[string];
  stateVars: seq[tuple[name: string, smtType: string]];
  sourceContext: string;
  timeoutMs: int = 5000
): tuple[nonTrivial: bool, fallback: bool, reason: string] =
  if not hasSecurityConstraintsInSource(sourceContext):
    return (false, false, "missing security constraints")
  if invariantClauses.len == 0:
    return (false, false, "missing invariant clauses")
  var varDecls: seq[string] = @[]
  for v in stateVars:
    varDecls.add("(declare-const " & v.name & " " & v.smtType & ")")
  let invBody = if invariantClauses.len == 0: "true"
                else: "(and " & invariantClauses.join(" ") & ")"
  let smtQuery = varDecls.join("\n") & "\n" &
    "(assert (not " & invBody & "))\n" &
    "(check-sat)"
  var vacCanonicalDigest, vacTransportDigest: string
  let z3Result = z3ExecPersistent(smtQuery, timeoutMs,
    canonicalEnvelopeDigest = vacCanonicalDigest, transportPayloadDigest = vacTransportDigest)
  if not z3Result.isOk:
    let error = z3Result.error().strip().toLowerAscii()
    let reason = if error.len > 0: "z3_error: " & error else: "z3_timeout_or_error"
    return (false, true, reason)
  let output = z3Result.get().strip().toLowerAscii()
  if output == "unsat":
    return (false, false, "invariant is trivially true")
  if output == "sat":
    return (true, false, "")
  return (false, true, "z3_unknown_or_timeout: " & output)
