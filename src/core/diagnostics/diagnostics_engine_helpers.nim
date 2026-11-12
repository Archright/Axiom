import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
import ../../core/trusted/axiom_pragmas
import core/sorter/sorter_core
import core/utils/text_utils
import std/strutils
type
  LogicComplexityProfile* = object
    complexityWeight*: int
    quantifierCount*: int
    nonLinearArithmeticCount*: int
    hotspots*: seq[string]

  TimeoutDiagnosis* = object
    nodeId*: SorterNodeId
    timeoutMs*: int
    complexityWeight*: int
    quantifierCount*: int
    nonLinearArithmeticCount*: int
    dependencyDepth*: int
    impactedNodeCount*: int
    remediationHint*: string
    mathematicalRationale*: string
    hotspots*: seq[string]
    selfHealingGuidance*: seq[string]

  SelfHealingDirective* = object
    nodeId*: SorterNodeId
    remediationHint*: string
    proofObligation*: string
    refactoringGuidance*: seq[string]

  StructuralDiagnosis* = object
    nodeId*: SorterNodeId
    diagnosticLabels*: seq[string]
    remediationHint*: string
    mathematicalRationale*: string
    childNodeCount*: int
    logicalDepth*: int
    interfaceDistance*: int
    couplingScore*: int
    astNodeId*: string
    parentNodeType*: string
    childIndices*: seq[int]
func countOccurrences(haystack: string; needle: string): int {.axiomTryImpl.} =
  if haystack.len == 0 or needle.len == 0:
    return 0
  var searchStart = 0
  while searchStart < haystack.len:
    let foundAt = haystack.find(needle, searchStart)
    if foundAt < 0:
      break
    inc result
    searchStart = foundAt + needle.len

  ## axiom-smt: (assert (and (>= (str.len smtlib2) 0)))
  ## axiom-lean: smtlib2.length ≥ 0
func tokenizeSmtlib2(smtlib2: string): seq[string] {.axiomTryImpl.} =
  let normalized = smtlib2.multiReplace(
    ("(", " "),
    (")", " "),
    ("\n", " "),
    ("\r", " "),
    ("\t", " ")
  )
  for token in normalized.splitWhitespace():
    result.add(token.strip())

func isNumericToken(token: string): bool {.axiomTryImpl.} =
  if token.len == 0:
    return false
  var cursor = 0
  if token[0] in {'-', '+'}:
    cursor = 1
  if cursor >= token.len:
    return false
  while cursor < token.len:
    if token[cursor] notin {'0' .. '9'}:
      return false
    inc cursor
  result = true

func hasLoopStructureString*(sourceCode: string): bool {.axiomTryImpl.} =
  let tokens = tokenizeLowered(sourceCode)
  result = "while" in tokens or "for" in tokens

func extractProcNameString*(sourceCode: string): string {.axiomTryImpl.} =
  let normalized = sourceCode.strip()
  let procPos = normalized.find("proc ")
  if procPos < 0:
    return ""
  let nameStart = procPos + 5
  var cursor = nameStart
  while cursor < normalized.len:
    let ch = normalized[cursor]
    if ch in {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_'}:
      inc cursor
    else:
      break
  if cursor <= nameStart:
    return ""
  result = normalized[nameStart ..< cursor]

func hasRecursiveShapeString*(sourceCode: string): bool {.axiomTryImpl.} =
  let procName = extractProcNameString(sourceCode)
  if procName.len == 0:
    return false
  let bodyStart = sourceCode.find("=")
  let body =
    if bodyStart >= 0 and bodyStart + 1 < sourceCode.len:
      sourceCode[bodyStart + 1 .. ^1]
    else:
      sourceCode
  let tokens = tokenizeLowered(body)
  let procIdx = tokens.find(procName.toLowerAscii())
  if procIdx >= 0 and procIdx + 1 < tokens.len and tokens[procIdx + 1] == "(":
    return true
  result = false

func hasInvariantMarker*(sourceCode: string): bool {.axiomTryImpl.} =
  let tokens = tokenizeLowered(sourceCode)
  for tok in tokens:
    if tok in ["assert", "doassert", "invariant", "require", "ensure", "precondition", "postcondition"]:
      return true
  result = false

func detectNonLinearArithmeticCount(tokens: seq[string]): int {.axiomTryImpl.} =
  if tokens.len < 3:
    return 0
  for idx, token in tokens:
    if token != "*":
      continue
    if idx + 2 >= tokens.len:
      continue
    let left = tokens[idx + 1]
    let right = tokens[idx + 2]
    if not isNumericToken(left) and not isNumericToken(right):
      inc result

## Analyze Logical Complexity.
func analyzeLogicalComplexity*(smtlib2: string): LogicComplexityProfile {.axiomTryImpl.} =
  let normalized = smtlib2.toLowerAscii()
  let tokens = tokenizeSmtlib2(normalized)
  result.quantifierCount =
    countOccurrences(normalized, "(forall") +
    countOccurrences(normalized, "(exists")
  result.nonLinearArithmeticCount = detectNonLinearArithmeticCount(tokens)
  let implicationCount = countOccurrences(normalized, "(=>")
  let iteCount = countOccurrences(normalized, "(ite")
  if result.quantifierCount > 0:
    result.hotspots.add("forall/exists quantifier")
  if result.nonLinearArithmeticCount > 0:
    result.hotspots.add("nonlinear arithmetic")
  if implicationCount > 0:
    result.hotspots.add("nested implication")
  if iteCount > 0:
    result.hotspots.add("branching ite")
  result.hotspots = deduplicateStrings(result.hotspots)
  result.complexityWeight =
    result.quantifierCount * 18 +
    result.nonLinearArithmeticCount * 22 +
    implicationCount * 4 +
    iteCount * 3

## Empty Timeout Diagnosis.
func emptyTimeoutDiagnosis*(): TimeoutDiagnosis {.inline.} =
  TimeoutDiagnosis(
    nodeId: sorterNodeId(""),
    timeoutMs: 0,
    complexityWeight: 0,
    quantifierCount: 0,
    nonLinearArithmeticCount: 0,
    dependencyDepth: 0,
    impactedNodeCount: 0,
    remediationHint: "",
    mathematicalRationale: "",
    hotspots: @[],
    selfHealingGuidance: @[]
  )

## Ha Timeout Diagnosis.
func hasTimeoutDiagnosis*(diagnosis: TimeoutDiagnosis): bool {.inline.} =
  diagnosis.remediationHint.len > 0 or diagnosis.complexityWeight > 0
func remediationHintFromSignals(
  hasLoop: bool;
  hasRecursion: bool;
  profile: LogicComplexityProfile;
  dependencyDepth: int;
  impactedNodeCount: int
): string {.axiomTryImpl.} =
  if hasLoop and profile.quantifierCount > 0:
    return "Loop invariant is missing. Separate quantifier scope into decrease formula and boundary conditions to reduce solver search space."
  if hasRecursion:
    return "Recursion depth proof is required. Explicitly declare the decrease measure and termination condition of self-calls as lemma or variant."
  if profile.nonLinearArithmeticCount > 0:
    return "Nonlinear arithmetic is the bottleneck. Decompose multiplication constraints with linear lemmas and case splits."
  if dependencyDepth >= 3 or impactedNodeCount >= 3:
    return "Dependency cross-section is too wide. Decompose with intermediate lemma functions to reduce proof burden on upper nodes."
  result = "Proof hints are insufficient. Add stronger precondition or decomposition lemma to reduce search space."
func rationaleFromSignals(
  hasLoop: bool;
  hasRecursion: bool;
  profile: LogicComplexityProfile;
  dependencyDepth: int;
  impactedNodeCount: int
): string {.axiomTryImpl.} =
  var fragments: seq[string] = @[]
  if profile.quantifierCount > 0:
    fragments.add("forall/exists quantifiers open the entire interpretation domain triggering quantifier instantiation")
  if profile.nonLinearArithmeticCount > 0:
    fragments.add("nonlinear arithmetic escapes linear decision procedure and drastically expands model search")
  if hasLoop:
    fragments.add("loop structure remains without state transition invariant weakening inductive closure")
  if hasRecursion:
    fragments.add("absence of decrease measure for recursive calls increases termination/induction obligation")
  if dependencyDepth >= 3:
    fragments.add("deep dependency chain accumulates additional constraints on upper composition proof")
  if impactedNodeCount >= 2:
    fragments.add("wide impact branches make same timeout likely to propagate to multiple upper nodes")
  if fragments.len == 0:
    return "Explicit high-complexity signals are weak but solver search space did not converge within timebox."
  fragments.join("; ")
func selfHealingGuidanceFromSignals(
  hasLoop: bool;
  hasRecursion: bool;
  profile: LogicComplexityProfile;
  dependencyDepth: int;
  impactedNodeCount: int
): seq[string] {.axiomTryImpl.} =
  if hasLoop:
    result.add("Split loop body into monotonic decrease formula and boundary conditions, promote invariant to contract near function signature.")
  if hasRecursion:
    result.add("Add decrease measure and base case lemma to recursive function for reduction to structural induction.")
  if profile.nonLinearArithmeticCount > 0:
    result.add("Replace multiplication/nonlinear constraints with linear auxiliary variables and lemmas for QF_LIA compatibility.")
  if profile.quantifierCount > 0:
    result.add("Limit quantifiers to bounded domain or finite case splits to reduce instantiation cost.")
  if dependencyDepth >= 3 or impactedNodeCount >= 3:
    result.add("Introduce intermediate composition nodes to decompose upper proof obligation into multiple smaller theorems.")
  if result.len == 0:
    result.add("Strengthen precondition and postcondition to reduce degrees of freedom the solver must reason about first.")

## Build Timeout Diagnosis.
func buildTimeoutDiagnosis*(
  nodeId: SorterNodeId;
  sourceCode: string;
  smtlib2: string;
  dependencyDepth: int;
  impactedNodeCount: int;
  timeoutMs: int
): TimeoutDiagnosis {.axiomTryImpl.} =
  let profile = analyzeLogicalComplexity(smtlib2)
  let hasLoop = hasLoopStructureString(sourceCode)
  let hasRecursion = hasRecursiveShapeString(sourceCode)
  result = TimeoutDiagnosis(
    nodeId: nodeId,
    timeoutMs: timeoutMs,
    complexityWeight:
      profile.complexityWeight +
      (if hasLoop: 9 else: 0) +
      (if hasRecursion: 11 else: 0) +
      dependencyDepth * 6 +
      max(0, impactedNodeCount - 1) * 4,
    quantifierCount: profile.quantifierCount,
    nonLinearArithmeticCount: profile.nonLinearArithmeticCount,
    dependencyDepth: dependencyDepth,
    impactedNodeCount: impactedNodeCount,
    remediationHint: remediationHintFromSignals(
      hasLoop,
      hasRecursion,
      profile,
      dependencyDepth,
      impactedNodeCount
    ),
    mathematicalRationale: rationaleFromSignals(
      hasLoop,
      hasRecursion,
      profile,
      dependencyDepth,
      impactedNodeCount
    ),
    hotspots: profile.hotspots,
    selfHealingGuidance: selfHealingGuidanceFromSignals(
      hasLoop,
      hasRecursion,
      profile,
      dependencyDepth,
      impactedNodeCount
    )
  )
  if hasLoop:
    result.hotspots.add("loop invariant gap")
  if hasRecursion:
    result.hotspots.add("recursive termination gap")
  result.hotspots = deduplicateStrings(result.hotspots)

## Generate Self Healing Directive.
func generateSelfHealingDirective*(diagnosis: TimeoutDiagnosis): SelfHealingDirective {.axiomTryImpl.} =
  SelfHealingDirective(
    nodeId: diagnosis.nodeId,
    remediationHint: diagnosis.remediationHint,
    proofObligation: diagnosis.mathematicalRationale,
    refactoringGuidance: diagnosis.selfHealingGuidance
  )

{.pop.}
