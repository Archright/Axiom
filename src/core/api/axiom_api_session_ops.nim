import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import ../../core/trusted/axiom_pragmas
import core/api/axiom_api_helpers
import core/api/axiom_api_session_helpers
import core/api/axiom_api_session_proof
import core/api/axiom_api_session_types
import core/bmc/bmc_race
import core/contracts/z3_extraction
import core/utils/constants
import core/gateway/gateway
import core/json/json_scan_parse
import core/session/session_parser
import core/session/session_parser_gateway
import core/session/session_parser_types
import core/solver/solver_bridge
import core/solver/types
import core/types/domain_types
import core/types/results
import std/json
import std/options
import std/strutils
## Inspect Trace.
func inspectTrace*(proofJson: string): Result[InspectTraceResponse, AxiomError] {.raises: [], axiom: ["(assert (and (>= (str.len proofJson) 0) (>= (str.len raw) 0) (>= (str.len traceRef) 0) (= (str.len buf) 0) (>= raw 0)))", "proofJson.length >= 0 ∧ raw.length >= 0 ∧ traceRef.length >= 0 ∧ buf.length = 0 ∧ (raw >= 0)"].} =
  func sanitizeTraceToken(raw: string): string {.raises: [], axiom: ["(assert (and (>= (str.len raw) 0) (= (str.len buf) 0) (>= raw 0)))", "raw.length >= 0 ∧ buf.length = 0 ∧ (raw >= 0)"].} =
    var buf = newStringOfCap(raw.len)
    for ch in raw:
      if ch.isAlphaNumeric():
        buf.add(ch.toLowerAscii())
      else:
        buf.add('-')
    if buf.len == 0:
      buf.add("trace")
    buf

  func defaultInspectTraceUrl(traceRef: string): string {.raises: [], axiom: ["(assert (and (>= (str.len traceRef) 0)))", "traceRef.length >= 0"].} =
    "http://localhost:" & $traceInspectorPort & "/trace/" & sanitizeTraceToken(traceRef)

  let parseRootRes = ??jsonParseSafe(proofJson)
  let rootRes = ??jsonRequireObject(parseRootRes)
  let root = rootRes
  let verdictRawRes = ??jsonGetNonEmptyStringField(root, "verdict")
  discard ??toVerdict(verdictRawRes)
  let witnessRes = ??jsonRequireObjectField(root, "witness")
  let witness = witnessRes
  let traceRefRawRes = ??jsonGetNonEmptyStringField(witness, "traceRef")
  discard ??toTraceRef(traceRefRawRes)
  let finalStateRawRes = ??jsonGetNonEmptyStringField(witness, "finalState")
  discard ??toJsonBlob(finalStateRawRes)
  let certificateRes = ??jsonRequireObjectField(root, "certificate")
  let certificate = certificateRes
  let certIdRawRes = ??jsonGetNonEmptyStringField(certificate, "id")
  discard ??toCertificateId(certIdRawRes)
  let issuedAtRawRes = ??jsonGetNonEmptyStringField(certificate, "issuedAt")
  discard ??toTimestamp(issuedAtRawRes)
  let normalizedTraceRefRes = ??parseJsonStringAtPathOrDefault(
    proofJson,
    ["traceReport", "traceRef"],
    traceRefRawRes
  )
  let traceUrlRes = ??parseJsonStringAtPathOrDefault(
    proofJson,
    ["traceReport", "traceUrl"],
    defaultInspectTraceUrl(normalizedTraceRefRes)
  )
  let vulnerabilityKindRes = ??parseJsonStringAtPathOrDefault(
    proofJson,
    ["traceReport", "vulnerabilityKind"],
    ""
  )
  let violatedPropertyRes = ??parseJsonStringAtPathOrDefault(
    proofJson,
    ["traceReport", "violatedProperty"],
    ""
  )
  let branchPointsRes = ??parseJsonStringArrayAtPathOrDefault(
    proofJson,
    ["traceReport", "branchPoints"],
    @[]
  )
  let pathSignatureRes = ??parseJsonStringAtPathOrDefault(
    proofJson,
    ["traceReport", "pathSignature"],
    ""
  )
  let counterExampleSummaryRes = ??parseJsonStringAtPathOrDefault(
    proofJson,
    ["traceReport", "counterExampleSummary"],
    ""
  )
  let evolutionReasoningRes = ??parseJsonStringAtPathOrDefault(
    proofJson,
    ["traceReport", "evolutionReasoning"],
    ""
  )
  ok(InspectTraceResponse(
    traceUrl: traceUrlRes,
    traceRef: normalizedTraceRefRes,
    vulnerabilityKind: vulnerabilityKindRes,
    violatedProperty: violatedPropertyRes,
    branchPoints: branchPointsRes,
    pathSignature: pathSignatureRes,
    counterExampleSummary: counterExampleSummaryRes,
    evolutionReasoning: evolutionReasoningRes
  ))

## Export Proof.
func exportProof*(proofJson: string; target: string; simulateNetworkFailure: bool = false): Result[ExportProofResponse, AxiomError] {.raises: [], axiom: ["(assert (and (>= (str.len proofJson) 0) (>= (str.len target) 0) (or (= simulateNetworkFailure true) (= simulateNetworkFailure false)) (or (= simulateNetworkFailure true) (= simulateNetworkFailure false))))", "proofJson.length >= 0 ∧ target.length >= 0 ∧ simulateNetworkFailure = true ∨ simulateNetworkFailure = false ∧ simulateNetworkFailure = true ∨ simulateNetworkFailure = false"].} =
  let parsed = ??jsonParseSafe(proofJson)
  discard ??jsonRequireObject(parsed)

  case target
  of "local", "github", "s3":
    discard
  else:
    return err(axiomErrExportTargetUnsupported)

  if simulateNetworkFailure and (target == "github" or target == "s3"):
    return err(axiomErrNetworkFailure)

  ok(ExportProofResponse(url: "https://example.com/" & target & "/proof"))

## Generate Symbolic Proof From Session Id.
func generateSymbolicProofFromSessionId*(
  sessionIdRaw: string;
  stateValue: int;
  inputDelta: int;
  solverStdout: string
): Result[GenerateProofResponse, SymbolicFailure] {.raises: [], axiom: ["(assert (and (>= (str.len sessionIdRaw) 0) (and (>= stateValue -9223372036854775808) (<= stateValue 9223372036854775807)) (and (>= inputDelta -9223372036854775808) (<= inputDelta 9223372036854775807)) (>= (str.len solverStdout) 0)))", "sessionIdRaw.length >= 0 ∧ stateValue >= -9223372036854775808 ∧ stateValue <= 9223372036854775807 ∧ inputDelta >= -9223372036854775808 ∧ inputDelta <= 9223372036854775807 ∧ solverStdout.length >= 0"].} =

  template `?>>`(r: untyped): untyped =
    if r.isErr(): return err(toSymbolicFailure(r.error, payload.smt2))
    r.get()
  let sidRes = toSessionId(sessionIdRaw)
  if sidRes.isErr():
    return err(toSymbolicFailure(sidRes.error))
  let sid = sidRes.get()
  let gated = gatekeepStateInputAsSymbolicFailure(stateValue, inputDelta)
  if gated.isErr():
    return err(gated.error)
  let payload = buildRuntimeErrorZeroPayload(gated.get()[0], makeSubtractRule(gated.get()[1]))
  let parsed = parseZ3StdoutAsResult(solverStdout, payload.smt2, "state_non_negative")
  if parsed.isErr():
    return err(parsed.error)

  let todayRes = ?>>(toIsoDate("2026-03-22"))
  let titleRes = ?>>(toTitle("symbolic-proof-" & sessionIdString(sid)))
  let verdictRes = ?>>(toVerdict("safe_within_bound"))
  let claimRes = ?>>(toClaim("runtime error zero holds under encoded constraints"))
  let bridgeRes = ?>>(buildNimLeanBridgeMetadata("x = x - " & $inputDelta, "x >= 0", "state_non_negative"))
  let bridgeBlobRes = ?>>(toJsonBlob($(jsonFromNimLeanBridge(bridgeRes))))
  let traceRefRes = ?>>(toTraceRef("trace://solver/" & sessionIdString(sid)))

  let solverStatus = solverStatusString(parsed.get().evidence.status)
  let finalStateJson = "{\"solver\":\"z3\",\"logic\":\"QF_LIA\",\"status\":\"" & solverStatus & "\",\"smt2Ref\":\"solver://z3/query\"}"
  let finalStateRes = ?>>(toJsonBlob(finalStateJson))

  let evidenceKindRes = ?>>(toEvidenceKind("solver"))
  let evidenceRefRes = ?>>(toEvidenceRef("solver://z3/query"))
  let certIdRes = ?>>(toCertificateId("cert-symbolic-" & sessionIdString(sid)))
  let issuedAtRes = ?>>(toTimestamp("2026-03-22T00:00:00Z"))

  ok(GenerateProofResponse(
    proof: SessionProofArtifact(
      metadata: ProofMetadata(title: titleRes, date: todayRes, tags: @[], bridge: some(bridgeBlobRes)),
      verdict: verdictRes,
      claims: @[claimRes],
      witness: Witness(traceRef: traceRefRes, finalState: finalStateRes),
      evidence: @[Evidence(kind: evidenceKindRes, `ref`: evidenceRefRes)],
      certificate: Certificate(id: certIdRes, issuedAt: issuedAtRes)
    )
  ))

## Generate KInduction Proof From Session Id.
func generateKInductionProofFromSessionId*(
  sessionIdRaw: string;
  k: int;
  stateValue: int;
  inputDelta: int;
  baseStdout: string;
  stepStdout: string
): Result[GenerateProofResponse, SymbolicFailure] {.raises: [CatchableError], axiom: ["(assert ast_parse_failed_isolated)", "ast_parse_failed_isolated"].} =
  let sidRes = toSessionId(sessionIdRaw)
  if sidRes.isErr():
    return err(toSymbolicFailure(sidRes.error))
  let sid = sidRes.get()
  let gated = gatekeepStateInputAsSymbolicFailure(stateValue, inputDelta)
  if gated.isErr():
    return err(gated.error)
  let payload = buildKInductionPayload(k, gated.get()[0], makeSubtractRule(gated.get()[1]))
  let baseParsed = parseZ3StdoutAsResult(baseStdout, payload.baseSmt2, "k_induction_base")
  let stepParsed = parseZ3StdoutAsResult(stepStdout, payload.stepSmt2, "k_induction_step")

  var baseStatus: SolverStatus = solverUnknown
  var stepStatus: SolverStatus = solverUnknown
  var baseCounter = none(SolverCounterExample)
  var stepCounter = none(SolverCounterExample)

  if baseParsed.isOk():
    baseStatus = baseParsed.get().evidence.status
  else:
    let e = baseParsed.error
    if e.code == axiomErrSolverSatCounterExample:
      baseStatus = solverSat
      baseCounter = e.counterExample
    else:
      return err(e)

  if stepParsed.isOk():
    stepStatus = stepParsed.get().evidence.status
  else:
    let e = stepParsed.error
    if e.code == axiomErrSolverSatCounterExample:
      stepStatus = solverSat
      stepCounter = e.counterExample
    else:
      return err(e)

  let todayRes = toIsoDate("2026-03-23")
  if todayRes.isErr():
    return err(toSymbolicFailure(todayRes.error))
  let titleRes = toTitle("k-induction-proof-" & sessionIdString(sid))
  if titleRes.isErr():
    return err(toSymbolicFailure(titleRes.error))
  let baseStream = readSolverStream(baseStdout)
  let stepStream = readSolverStream(stepStdout)
  ## A stream that answered twice has not produced a decidable answer, so the
  ## status it contributes to the verdict, the claim and the witness node is
  ## `unknown`. Collapsing it here — once — is what keeps three projections of
  ## one stream from reaching three conclusions; `sat` is exempt because a
  ## counter-example is adverse evidence that is never withheld.
  if baseStream.isAnomalous and baseStatus != solverSat:
    baseStatus = solverUnknown
  if stepStream.isAnomalous and stepStatus != solverSat:
    stepStatus = solverUnknown
  ## Derived from the two observed responses, never from the absence of a
  ## counter-example: absence is also what an `unknown` answer and an unparsed
  ## stream look like, so inferring a discharge from it asserts a stronger claim
  ## than the evidence produced (docs/adr/0017-trust-claim-authority.md).
  let hasCounterExample = baseStatus == solverSat or stepStatus == solverSat
  let discharged = baseStatus == solverUnsat and stepStatus == solverUnsat
  let verdictRes = toVerdict(
    if hasCounterExample:
      "race_detected"
    elif discharged:
      "safe_within_bound"
    else:
      "inconclusive")
  if verdictRes.isErr():
    return err(toSymbolicFailure(verdictRes.error))
  let claimRes = toClaim(
    if hasCounterExample:
      "k-induction found reachable violation"
    elif discharged:
      "k-induction base and step are unsat"
    else:
      "k-induction base and step were not both unsat")
  if claimRes.isErr():
    return err(toSymbolicFailure(claimRes.error))
  let bridgeRes = buildNimLeanBridgeMetadata("x = x - " & $inputDelta, "x >= 0", "k_induction_state_non_negative")
  if bridgeRes.isErr():
    return err(toSymbolicFailure(bridgeRes.error))
  let bridgeBlobRes = toJsonBlob($(jsonFromNimLeanBridge(bridgeRes.get())))
  if bridgeBlobRes.isErr():
    return err(toSymbolicFailure(bridgeBlobRes.error))
  let traceRefRes = toTraceRef("trace://solver/induction/" & sessionIdString(sid))
  if traceRefRes.isErr():
    return err(toSymbolicFailure(traceRefRes.error))

  let finalStateNode = buildKInductionFinalStateNode(
    k, baseStatus, stepStatus, baseCounter, stepCounter,
    payload.request.baseCase.finalStateSymbol,
    payload.request.stepCase.finalStateSymbol
  )
  let finalStateRes = toJsonBlob($finalStateNode)
  if finalStateRes.isErr():
    return err(toSymbolicFailure(finalStateRes.error))

  let evidenceKindRes = toEvidenceKind("solver")
  if evidenceKindRes.isErr():
    return err(toSymbolicFailure(evidenceKindRes.error))
  let queryEvidenceRefRes = toEvidenceRef("solver://z3/query")
  if queryEvidenceRefRes.isErr():
    return err(toSymbolicFailure(queryEvidenceRefRes.error))
  let baseEvidenceRefRes = toEvidenceRef("solver://z3/base")
  if baseEvidenceRefRes.isErr():
    return err(toSymbolicFailure(baseEvidenceRefRes.error))
  let stepEvidenceRefRes = toEvidenceRef("solver://z3/step")
  if stepEvidenceRefRes.isErr():
    return err(toSymbolicFailure(stepEvidenceRefRes.error))
  let baseModelEvidenceRefRes = toEvidenceRef("solver://z3/model/base")
  if baseModelEvidenceRefRes.isErr():
    return err(toSymbolicFailure(baseModelEvidenceRefRes.error))
  let stepModelEvidenceRefRes = toEvidenceRef("solver://z3/model/step")
  if stepModelEvidenceRefRes.isErr():
    return err(toSymbolicFailure(stepModelEvidenceRefRes.error))
  let certIdRes = toCertificateId("cert-k-induction-" & sessionIdString(sid))
  if certIdRes.isErr():
    return err(toSymbolicFailure(certIdRes.error))
  let issuedAtRes = toTimestamp("2026-03-23T00:00:00Z")
  if issuedAtRes.isErr():
    return err(toSymbolicFailure(issuedAtRes.error))

  let evidence = buildKInductionEvidenceList(
    evidenceKindRes.get(), queryEvidenceRefRes.get(), baseEvidenceRefRes.get(),
    stepEvidenceRefRes.get(), baseModelEvidenceRefRes.get(), stepModelEvidenceRefRes.get(),
    baseStatus, stepStatus
  )

  ok(GenerateProofResponse(
    proof: SessionProofArtifact(
      metadata: ProofMetadata(title: titleRes.get(), date: todayRes.get(), tags: @[], bridge: some(bridgeBlobRes.get())),
      verdict: verdictRes.get(),
      claims: @[claimRes.get()],
      witness: Witness(traceRef: traceRefRes.get(), finalState: finalStateRes.get()),
      evidence: evidence,
      certificate: Certificate(id: certIdRes.get(), issuedAt: issuedAtRes.get())
    )
  ))

## Collect Session From Observed Messages.
func collectSessionFromObservedMessages*(clientRaw: string; observedCount: int): Result[AxiomSession, AxiomError] {.raises: [], axiom: ["(assert (and (>= session 0)))", "(session >= 0)"].} =
  let base = ??makeAxiomSession(
    "00000000-0000-4000-8000-000000000000",
    "Session Title",
    "2026-03-08T00:00:00Z",
    "2026-03-08T00:00:00Z",
    clientRaw,
    "internal",
    "default",
    true
  )
  let sessionBase = base

  let tsRes = ??toTimestamp("2026-03-08T00:00:00Z")
  let ts = tsRes
  let roleRes = ??toRole("user")
  let role = roleRes

  var msgs: seq[Message] = @[]
  for i in 0 ..< observedCount:
    let idRes = ??toMessageId("m" & $i)
    let id = idRes
    let textRes = ??toMessageText("x")
    let text = textRes
    let content = @[MessageContent(kind: contentText, text: text)]
    msgs.add(Message(id: id, ts: ts, role: role, content: content, meta: none(MessageMeta)))

  var session = sessionBase
  session.messages = msgs
  return ok(session)

## Export Session As Import Block.
func exportSessionAsImportBlock*(session: AxiomSession): string {.raises: [].} =
  let json = "{\"schemaVersion\":\"" & schemaVersionString(session.schemaVersion) &
    "\",\"sessionId\":\"" & sessionIdString(session.sessionId) &
    "\",\"title\":\"" & titleString(session.title) &
    "\",\"messages\":[]}"
  "```json\n" & json & "\n```"

## Apply Redaction Policy To Session.
func applyRedactionPolicyToSession*(session: AxiomSession): Result[AxiomSession, AxiomError] {.raises: [], axiom: ["(assert (and (>= depth 0) (>= policy 0) (>= applied 0)))", "depth >= 0 ∧ (policy >= 0) ∧ (applied >= 0)"].} =
  let policyRes = ??toPolicyName("default")
  let policy = policyRes
  var s = session
  s.redaction.applied = true
  s.redaction.policy = policy
  return ok(s)

## Redact Sensitive Text.
func redactSensitiveText*(s: string): string {.raises: [], axiom: ["(assert (and (>= (- j i) 12) (< i (str.len s)) (= i j) (and (>= i 0) (< i s))))", "j - i >= 12 ∧ i < s.length ∧ i = j ∧ ((i >= 0) ∧ (i < s))"].} =
  var i = 0
  while i < s.len:
    if i + 3 <= s.len and s[i ..< min(s.len, i + 3)] == "sk-":
      var j = i + 3
      while j < s.len and (isAlphaNumeric(s[j]) or s[j] == '_' or s[j] == '-'):
        inc j
      if j - i >= 12:
        result.add("[REDACTED]")
        i = j
        continue
    if i + 4 <= s.len and s[i ..< min(s.len, i + 4)] == "ghp_":
      var j = i + 4
      while j < s.len and (isAlphaNumeric(s[j]) or s[j] == '_' or s[j] == '-'):
        inc j
      if j - i >= 12:
        result.add("[REDACTED]")
        i = j
        continue
    result.add(s[i])
    inc i

## Validate Markdown Code Blocks Have Lang.
func validateMarkdownCodeBlocksHaveLang*(markdown: string): Result[bool, AxiomError] {.raises: [], axiom: ["(assert (and (< i (str.len markdown)) (= inFence true) (= inFence false) (= i j) (>= inFence 0) (and (>= i 0) (< i markdown))))", "i < markdown.length ∧ inFence = true ∧ inFence = false ∧ i = j ∧ (inFence >= 0) ∧ ((i >= 0) ∧ (i < markdown))"].} =
  var inFence = false
  var i = 0
  while i < markdown.len:
    if markdown[i] == '`' and i + 2 < markdown.len and markdown[i + 1] == '`' and markdown[i + 2] == '`':
      var j = i + 3
      if j < markdown.len and markdown[j] == ' ':
        while j < markdown.len and markdown[j] == ' ':
          inc j
      if not inFence:
        if j >= markdown.len or markdown[j] == '\n' or markdown[j] == '\r':
          return err(axiomErrInvalidValue)
        inFence = true
      else:
        inFence = false
      i = j
      continue
    inc i
  return ok(true)
## Inspect Trace.
# @axiom-hint: lean="proofJson.length >= 0 ∧ raw.length >= 0 ∧ traceRef.length >= 0" smt="(assert (and (>= (str.len proofJson) 0) (>= (str.len raw) 0) (>= (str.len traceRef) 0)))"
# @axiom-hint: lean="buf.length = 0 ∧ (raw >= 0)" smt="(assert (and (= (str.len buf) 0) (>= raw 0)))"
