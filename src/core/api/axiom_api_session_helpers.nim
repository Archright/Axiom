import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Axiom API Session Helpers
## Internal helper functions for proof artifact JSON serialization/deserialization,
## symbolic failure construction, and Nim-Lean bridge metadata generation.
##
## Extracted from axiom_api_session_part1.nim (include-based) into a proper module.

import std/json
import std/options

import core/bmc/bmc_types
import core/types/domain_types
import core/utils/constants
import core/parsers/expression_parser
import core/session/session_parser_types
import core/gateway/gateway
import core/session/session_parser
import core/session/session_parser_gateway
import core/types/results
import core/solver/types

import core/api/axiom_api_session_types
import ../../core/trusted/axiom_pragmas

# ── Proof Artifact JSON ──

func proofArtifactToJsonNode*(proof: SessionProofArtifact): JsonNode {.raises: [].} =
  result = newJObject()
  let metadata = newJObject()
  metadata["title"] = newJString(titleString(proof.metadata.title))
  metadata["date"] = newJString(isoDateString(proof.metadata.date))
  let tags = newJArray()
  for item in proof.metadata.tags:
    tags.add(newJString(tagString(item)))
  metadata["tags"] = tags
  if proof.metadata.bridge.isSome():
    let rawBridge = jsonBlobString(proof.metadata.bridge.get())
    metadata["bridge"] = newJString(rawBridge)
  result["metadata"] = metadata
  result["verdict"] = newJString(verdictString(proof.verdict))
  let claims = newJArray()
  for item in proof.claims:
    claims.add(newJString(claimString(item)))
  result["claims"] = claims
  result["witness"] = %*{
    "traceRef": traceRefString(proof.witness.traceRef),
    "finalState": jsonBlobString(proof.witness.finalState)
  }
  let evidence = newJArray()
  for item in proof.evidence:
    evidence.add(%*{
      "kind": evidenceKindString(item.kind),
      "ref": evidenceRefString(item.`ref`)
    })
  result["evidence"] = evidence
  result["certificate"] = %*{
    "id": certificateIdString(proof.certificate.id),
    "issuedAt": timestampString(proof.certificate.issuedAt)
  }

func proofEnvelopeJson*(sessionId: string; proof: SessionProofArtifact): string {.raises: [], axiom: ["(assert (and (>= (str.len sessionId) 0) ast_parse_failed_isolated))", "sessionId.length >= 0 ∧ ast_parse_failed_isolated"].} =
  let payload = newJObject()
  payload["sessionId"] = newJString(sessionId)
  payload["proof"] = proofArtifactToJsonNode(proof)
  $payload


func parseProofMetadata(node: JsonNode): Result[ProofMetadata, AxiomError] {.raises: [], axiom: ["(assert (and (>= depth 0) (>= bridge 0)))", "depth >= 0 ∧ (bridge >= 0)"].} =
  ## Parse the metadata section of a proof artifact JSON node.
  let metadataRes = ??jsonRequireObjectField(node, "metadata")
  let metadata = metadataRes
  let titleRawRes = ??jsonGetNonEmptyStringField(metadata, "title")
  let titleRes = ??toTitle(titleRawRes)
  let dateRawRes = ??jsonGetNonEmptyStringField(metadata, "date")
  let dateRes = ??toIsoDate(dateRawRes)
  var tags: seq[Tag] = @[]
  let tagsOpt = jsonTryGetArrayField(metadata, "tags")
  if tagsOpt.isSome():
    for item in tagsOpt.get().items:
      if item.kind != JString:
        return err(axiomErrJsonWrongType)
      let tagRes = ??toTag(item.getStr())
      tags.add(tagRes)
  var bridge = none(JsonBlob)
  let bridgeNode = metadata{"bridge"}
  if not bridgeNode.isNil:
    let bridgeRaw =
      if bridgeNode.kind == JString:
        bridgeNode.getStr()
      else:
        $bridgeNode
    let bridgeRes = ??toJsonBlob(bridgeRaw)
    bridge = some(bridgeRes)
  ok(ProofMetadata(
    title: titleRes,
    date: dateRes,
    tags: tags,
    bridge: bridge
  ))

func parseProofEvidenceArray(node: JsonNode): Result[seq[Evidence], AxiomError] {.raises: [].} =
  ## Parse the evidence array from a proof artifact JSON node.
  var evidence: seq[Evidence] = @[]
  let evidenceOpt = jsonTryGetArrayField(node, "evidence")
  if evidenceOpt.isSome():
    for item in evidenceOpt.get().items:
      let kindRes = ??toEvidenceKind(??jsonGetNonEmptyStringField(item, "kind"))
      let refRes = ??toEvidenceRef(??jsonGetNonEmptyStringField(item, "ref"))
      evidence.add(Evidence(kind: kindRes, `ref`: refRes))
  ok(evidence)

func parseClaimsArray(node: JsonNode): Result[seq[Claim], AxiomError] {.raises: [].} =
  ## Parse the claims array from a proof artifact JSON node.
  var claims: seq[Claim] = @[]
  let claimsOpt = jsonTryGetArrayField(node, "claims")
  if claimsOpt.isSome():
    for item in claimsOpt.get().items:
      if item.kind != JString:
        return err(axiomErrJsonWrongType)
      let claimRes = ??toClaim(item.getStr())
      claims.add(claimRes)
  ok(claims)

func parseProofArtifactNode*(node: JsonNode): Result[SessionProofArtifact, AxiomError] {.raises: [].} =
  let metadata = ??parseProofMetadata(node)
  let verdictRes = ??toVerdict(??jsonGetNonEmptyStringField(node, "verdict"))
  let claimsRes = ??parseClaimsArray(node)
  let witnessNode = ??jsonRequireObjectField(node, "witness")
  let traceRefRes = ??toTraceRef(??jsonGetNonEmptyStringField(witnessNode, "traceRef"))
  let finalStateRes = ??toJsonBlob(??jsonGetNonEmptyStringField(witnessNode, "finalState"))
  let evidence = ??parseProofEvidenceArray(node)
  let certificateNode = ??jsonRequireObjectField(node, "certificate")
  let certIdRes = ??toCertificateId(??jsonGetNonEmptyStringField(certificateNode, "id"))
  let issuedAtRes = ??toTimestamp(??jsonGetNonEmptyStringField(certificateNode, "issuedAt"))
  ok(SessionProofArtifact(
    metadata: metadata,
    verdict: verdictRes,
    claims: claimsRes,
    witness: Witness(
      traceRef: traceRefRes,
      finalState: finalStateRes
    ),
    evidence: evidence,
    certificate: Certificate(
      id: certIdRes,
      issuedAt: issuedAtRes
    )
  ))

func parseStoredProofResponse*(proofJson: string): Result[GenerateProofResponse, AxiomError] {.raises: [], axiom: ["(assert (and (>= (str.len proofJson) 0)))", "proofJson.length >= 0"].} =
  let rootRes = ??jsonParseSafe(proofJson)
  let nodeRes = ??jsonRequireObject(rootRes)
  let root = nodeRes
  let proofPayload = root{"proof"}
  let proofNode =
    if not proofPayload.isNil and proofPayload.kind == JObject:
      proofPayload
    else:
      root
  let proofRes = ??parseProofArtifactNode(proofNode)
  ok(GenerateProofResponse(proof: proofRes))

# ── Nim-Lean Bridge Metadata ──

func jsonFromNimLeanBridge*(res: NimLeanBridgeResponse): JsonNode {.raises: [], axiom: ["(assert (and (>= (str.len res_bridgeId) 0) (>= (str.len res_ruleText) 0) (>= (str.len res_invariantText) 0) (>= (str.len res_theoremName) 0) (>= (str.len res_transitionOperator) 0) (and (>= res_delta -9223372036854775808) (<= res_delta 9223372036854775807)) (>= (str.len res_invariantKind) 0) (and (>= res_invariantValue -9223372036854775808) (<= res_invariantValue 9223372036854775807)) (>= (str.len res_leanNamespace) 0) (>= (str.len res_leanInvariantExpr) 0) (>= (str.len res_leanTransitionExpr) 0) (>= (str.len res_leanTheoremExpr) 0)))", "res_bridgeId.length >= 0 ∧ res_ruleText.length >= 0 ∧ res_invariantText.length >= 0 ∧ res_theoremName.length >= 0 ∧ res_transitionOperator.length >= 0 ∧ res_delta >= -9223372036854775808 ∧ res_delta <= 9223372036854775807 ∧ res_invariantKind.length >= 0 ∧ res_invariantValue >= -9223372036854775808 ∧ res_invariantValue <= 9223372036854775807 ∧ res_leanNamespace.length >= 0 ∧ res_leanInvariantExpr.length >= 0 ∧ res_leanTransitionExpr.length >= 0 ∧ res_leanTheoremExpr.length >= 0"].} =
  %*{
    "bridgeId": res.bridgeId,
    "ruleText": res.ruleText,
    "invariantText": res.invariantText,
    "theoremName": res.theoremName,
    "transitionOperator": res.transitionOperator,
    "delta": res.delta,
    "invariantKind": res.invariantKind,
    "invariantValue": res.invariantValue,
    "leanNamespace": res.leanNamespace,
    "leanInvariantExpr": res.leanInvariantExpr,
    "leanTransitionExpr": res.leanTransitionExpr,
    "leanTheoremExpr": res.leanTheoremExpr
  }

## Build Nim Lean Bridge Metadata.

func resolveTransitionExprs(
  op: TransitionOperator; delta: int
): tuple[operator: string; leanExpr: string] {.raises: [], axiom: ["(assert (and (>= (str.len ruleText) 0) (>= (str.len invariantText) 0) (>= (str.len theoremName) 0)))", "ruleText.length >= 0 ∧ invariantText.length >= 0 ∧ theoremName.length >= 0"].} =
  ## Resolve transition operator and Lean expression from a transition op.
  case op
  of transitionSub:
    ("transitionSub", "def Transition (state : Nat) : Nat := if " & $delta & " <= state then state - " & $delta & " else state")
  of transitionAdd:
    ("transitionAdd", "def Transition (state : Nat) : Nat := state + " & $delta)

func resolveInvariantExprs(
  inv: InvariantRule; invariantValue: int
): tuple[kind: string; leanExpr: string] {.raises: [].} =
  ## Resolve invariant kind and Lean expression from an invariant spec.
  case inv.kind
  of invariantMinValue:
    ("invariantMinValue", "def Invariant (state : Nat) : Prop := state >= " & $invariantValue)
  of invariantMaxValue:
    ("invariantMaxValue", "def Invariant (state : Nat) : Prop := state <= " & $invariantValue)

func buildNimLeanBridgeMetadata*(
  ruleText: string;
  invariantText: string;
  theoremName: string
): Result[NimLeanBridgeResponse, AxiomError] {.raises: [].} =
  let parsed = parseUserCodeAndInvariantToRule(ruleText, invariantText)
  if parsed.isErr():
    return err(parsed.error)
  let rule = parsed.get()
  let resolvedTheorem =
    if theoremName.len == 0: "state_never_negative"
    else: theoremName
  let (transitionOperator, leanTransitionExpr) = resolveTransitionExprs(rule.op, rule.delta)
  let (invariantKind, leanInvariantExpr) = resolveInvariantExprs(rule.invariant, rule.invariant.minValue)
  let invariantValue = case rule.invariant.kind
    of invariantMinValue: rule.invariant.minValue
    of invariantMaxValue: rule.invariant.maxValue
  let leanTheoremExpr = "theorem " & resolvedTheorem & " : forall state : Nat, Invariant state := by"
  let bridgeId = "nim-lean:" & transitionOperator & ":" & $rule.delta & ":" & invariantKind & ":" & $invariantValue
  return ok(NimLeanBridgeResponse(
    bridgeId: bridgeId,
    ruleText: ruleText,
    invariantText: invariantText,
    theoremName: resolvedTheorem,
    transitionOperator: transitionOperator,
    delta: rule.delta,
    invariantKind: invariantKind,
    invariantValue: invariantValue,
    leanNamespace: "Axiom.Verification",
    leanInvariantExpr: leanInvariantExpr,
    leanTransitionExpr: leanTransitionExpr,
    leanTheoremExpr: leanTheoremExpr
  ))

# ── K-Induction Helper ──

## Build KInduction Final State Node.
func buildKInductionFinalStateNode*(
  k: int;
  baseStatus: SolverStatus;
  stepStatus: SolverStatus;
  baseCounter: Option[SolverCounterExample];
  stepCounter: Option[SolverCounterExample];
  baseFinalStateSymbol: string;
  stepFinalStateSymbol: string
): JsonNode {.raises: [], axiom: ["(assert (and (and (>= k -9223372036854775808) (<= k 9223372036854775807)) (or (= baseStatus solverSat) (= baseStatus solverUnsat) (= baseStatus solverUnknown) (= baseStatus solverVacuousContradiction)) (or (= stepStatus solverSat) (= stepStatus solverUnsat) (= stepStatus solverUnknown) (= stepStatus solverVacuousContradiction)) (= hasCounterExample true) (= hasCounterExample false) (>= (str.len baseFinalStateSymbol) 0) (>= (str.len stepFinalStateSymbol) 0)))", "k >= -9223372036854775808 ∧ k <= 9223372036854775807 ∧ baseStatus = solverSat ∨ baseStatus = solverUnsat ∨ baseStatus = solverUnknown ∨ baseStatus = solverVacuousContradiction ∧ stepStatus = solverSat ∨ stepStatus = solverUnsat ∨ stepStatus = solverUnknown ∨ stepStatus = solverVacuousContradiction ∧ hasCounterExample = true ∨ hasCounterExample = false ∧ baseFinalStateSymbol.length >= 0 ∧ stepFinalStateSymbol.length >= 0"].} =
  result = newJObject()
  result["solver"] = newJString(DefaultSolverCommand)
  result["logic"] = newJString("QF_LIA")
  ## Derived from the two observed responses, never from the absence of a
  ## counter-example: "no counter-example" is also what an unparsed or
  ## `unknown` answer looks like, so inferring a discharge from it asserts a
  ## stronger claim than the evidence carries (docs/adr/0017-trust-claim-authority.md).
  ## Anything short of both obligations observed `unsat` lands on `unknown`,
  ## which a recorded solver answer cannot be mistaken for.
  let hasCounterExample = baseStatus == solverSat or stepStatus == solverSat
  let discharged = baseStatus == solverUnsat and stepStatus == solverUnsat
  result["status"] = newJString(
    if hasCounterExample: "sat"
    elif discharged: "proved"
    else: "unknown")
  result["method"] = newJString("k-induction")
  result["k"] = newJInt(k)
  var picked = none(SolverCounterExample)
  var preferredBindingName = ""
  if baseCounter.isSome():
    picked = baseCounter
    preferredBindingName = baseFinalStateSymbol
  elif stepCounter.isSome():
    picked = stepCounter
    preferredBindingName = stepFinalStateSymbol
  if picked.isSome() and picked.get().bindings.len > 0:
    var b = picked.get().bindings[0]
    for item in picked.get().bindings:
      if item.name == preferredBindingName:
        b = item
        break
    var ceNode = newJObject()
    ceNode["property"] = newJString(picked.get().violatedProperty)
    ceNode["bindingName"] = newJString(b.name)
    ceNode["bindingValue"] = newJString(b.value)
    result["counterExample"] = ceNode

{.pop.}
