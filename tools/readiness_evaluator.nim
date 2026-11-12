## tools/readiness_evaluator.nim — Axiom v1 productization readiness evaluator.
##
## Contract-first deterministic evaluation per docs/spec/productization_contract.md.
## Verdict is decided by pure functions — never by a human.
##
## This module observes evidence and projects the decision; it does not own the
## decision algebra. `Decide` in src/core/utils/decision_algebra.nim is the
## single state -> verdict mapping, and evaluateReadiness is a thin projection
## of its DecisionResult onto the frozen readiness decision schema.
##
## Purity boundary:
##   loadEvidenceFiles (IO only)
##     -> validateEvidence    (pure, {.raises: [].})
##     -> normalizeBundle     (pure, {.raises: [].})
##     -> evaluateReadiness   (pure, {.raises: [].})
##          -> Decide         (pure, {.raises: [].}, core/utils/decision_algebra)
##
## All digests are SHA-256 via core/utils/decision_algebra's canonical JSON over
## core/crypto/hash_kernel — byte-identical to tools/sha256_native.nim.

import std/[json, tables, algorithm, sequtils, options, os]
import ../src/core/utils/decision_algebra as decision_algebra
from ../src/core/utils/decision_algebra import
  InvariantState, InvariantStatus, DecisionCandidate, DecisionEvidence,
  ExecutionContract, DecisionAggregate, StatusToken, CategoryContractFail,
  Decide, decideTokens, canonicalSha256, invariantStatesJson
export decision_algebra
# U1 (ADR-0030): the trust-boundary register is consumed directly — the frozen
# hubMapping allows tools/ to import core/trusted/, and the register's
# `exists` facts must be read from their SSOT, never restated in policy data.
from ../src/core/trusted/trust_boundary import TrustBoundary, AxiomTrustBoundary

# ---------------------------------------------------------------------------
# Lightweight Result (stdlib has no Result in Nim 2.2; standalone tools must
# not depend on src/core internals, per import encapsulation).
# ---------------------------------------------------------------------------

type
  Result*[T, E] = object
    ## Lightweight Result (stdlib has no Result in Nim 2.2; the evaluator keeps
    ## its own so the decision core stays free of tool-local plumbing).
    case ok*: bool
    of true:
      value*: T
    else:
      err*: E

proc isOk*[T, E](r: Result[T, E]): bool {.inline.} =
  r.ok

proc isErr*[T, E](r: Result[T, E]): bool {.inline.} =
  not r.ok

proc get*[T, E](r: Result[T, E]): T {.inline.} =
  doAssert r.ok, "Result.get on an err result"
  r.value

proc error*[T, E](r: Result[T, E]): E {.inline.} =
  doAssert not r.ok, "Result.error on an ok result"
  r.err

template ok*[T](v: T): untyped =
  ## Delegate the return type to the caller's Result[T, E].
  block:
    type R = typeof(result)
    R(ok: true, value: v)

template err*[E](e: E): untyped =
  ## Delegate the return type to the caller's Result[T, E].
  block:
    type R = typeof(result)
    R(ok: false, err: e)

# ---------------------------------------------------------------------------
# Shared types
# ---------------------------------------------------------------------------

type
  InvState* = InvariantState
  ## Compatibility alias — the enum has exactly one definition now, in
  ## core/utils/decision_algebra. Readiness consumers keep naming InvState.

  EvaluationContext* = object
    ## §5: time and repository identity are injected explicitly so that a
    ## decision is a pure function of (policy, bundle, context).
    repoHead*: string
    repoBranch*: string
    treeDigest*: string
    workingTreeClean*: bool
    toolchainNim*: string
    toolchainZ3*: string
    toolchainLean*: string
    evaluationTime*: string

  ValidatedEvidence* = object
    invariantId*: string
    raw*: JsonNode

  ReadinessDecision* = object
    schemaVersion*: int
    policyHash*: string
    bundleDigest*: string
    invariantStates*: JsonNode   ## {"R1": "PASS", ...} in R1..R8 order
    verdict*: string             ## "GO" | "CONDITIONAL GO" | "NO-GO"
    conditions*: seq[string]
    outcome*: string             ## CONTINUE | BLOCK | UNRESOLVED (decision, separate from observed state)
    failureCategory*: string     ## CONTRACT_FAIL | EVIDENCE_FAIL | PROVENANCE_FAIL | UNKNOWN | INFRA_FAIL | ""
    decisionDigest*: string

const
  InvariantIds* = ["R1", "R2", "R3", "R4", "R5", "R6", "R7", "R8"]
  CleanTreeRequiredInvariants = ["R1", "R3", "R8"]
  DefaultPolicyHash = "axiom-readiness-v1"

# ---------------------------------------------------------------------------
# Canonical JSON / digest helpers: single implementation lives in
# core/utils/decision_algebra (canonicalJson / canonicalSha256), re-exported
# above. The evaluator must not re-derive the digest preimage.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Evidence construction helpers
# ---------------------------------------------------------------------------

proc makeObs*(key: string, value: JsonNode, scope = "", subject = ""): JsonNode =
  result = newJObject()
  result["key"] = %key
  result["value"] = value
  result["scope"] = %scope
  result["subject"] = %subject

proc makeEvidence*(invariantId: string, observations: seq[JsonNode]): JsonNode =
  result = newJObject()
  result["schemaVersion"] = %1
  result["invariantId"] = %invariantId
  let arr = newJArray()
  for o in observations:
    arr.add(o)
  result["observations"] = arr

proc parseEvidence*(raw: JsonNode): JsonNode =
  ## Structural passthrough (test convenience; keeps loader contract stable).
  raw

# ---------------------------------------------------------------------------
# Context
# ---------------------------------------------------------------------------

proc makeContext*(
    repoHead = "",
    repoBranch = "main",
    treeDigest = "",
    workingTreeClean = true,
    toolchainNim = "", toolchainZ3 = "", toolchainLean = "",
    evaluationTime = "2026-08-17T00:00:00Z"): EvaluationContext =
  EvaluationContext(repoHead: repoHead, repoBranch: repoBranch,
                    treeDigest: treeDigest, workingTreeClean: workingTreeClean,
                    toolchainNim: toolchainNim, toolchainZ3: toolchainZ3,
                    toolchainLean: toolchainLean, evaluationTime: evaluationTime)

proc defaultContext*(): EvaluationContext =
  makeContext()

# ---------------------------------------------------------------------------
# Internal observation helpers
# ---------------------------------------------------------------------------

proc obsListOf(raw: JsonNode): seq[JsonNode] =
  result = @[]
  if raw != nil and raw.kind == JObject and raw.hasKey("observations"):
    let arr = raw["observations"]
    if arr.kind == JArray:
      for it in arr.items:
        if it.kind == JObject and it.hasKey("key"):
          result.add(it)

proc obsKey(o: JsonNode): string = o["key"].getStr()
proc obsScope(o: JsonNode): string =
  if o.hasKey("scope"): o["scope"].getStr() else: ""
proc obsSubject(o: JsonNode): string =
  if o.hasKey("subject"): o["subject"].getStr() else: ""
proc obsValue(o: JsonNode): JsonNode =
  if o.hasKey("value"): o["value"] else: newJNull()

proc stringListValue(v: JsonNode): seq[string] =
  result = @[]
  if v == nil: return
  case v.kind
  of JString:
    if v.getStr() != "":
      result.add(v.getStr())
  of JArray:
    for it in v.items:
      if it.kind == JString and it.getStr() != "":
        result.add(it.getStr())
  else: discard

proc stringValue(v: JsonNode): string =
  if v != nil and v.kind == JString: v.getStr() else: ""

proc boolValue(v: JsonNode, default: bool): bool =
  if v != nil and v.kind == JBool: v.getBool() else: default

proc floatValue(v: JsonNode, default: float): float =
  if v != nil:
    if v.kind == JFloat: return v.getFloat()
    if v.kind == JInt: return float(v.getInt())
  default

proc isNumber(v: JsonNode): bool =
  v != nil and (v.kind == JFloat or v.kind == JInt)

proc isString(v: JsonNode): bool =
  v != nil and v.kind == JString

proc findObs(obs: seq[JsonNode], key: string, scope = "", subject = ""): Option[JsonNode] =
  ## Standardized find: 'scope' and 'subject' filter only when non-empty.
  for o in obs:
    if obsKey(o) != key: continue
    if scope != "" and obsScope(o) != scope: continue
    if subject != "" and obsSubject(o) != subject: continue
    return some(obsValue(o))
  none(JsonNode)

proc allValues(obs: seq[JsonNode], key: string): seq[JsonNode] =
  for o in obs:
    if obsKey(o) == key:
      result.add(obsValue(o))

# ---------------------------------------------------------------------------
# Validation (pure) — any doubt -> err -> invariant UNKNOWN at evaluation.
# ---------------------------------------------------------------------------

proc validateEvidence*(
    raw: JsonNode, ctx: EvaluationContext,
    policy: JsonNode = newJObject()): Result[ValidatedEvidence, string] =
  if raw == nil or raw.kind != JObject:
    return err("evidence is not a JSON object")
  if not raw.hasKey("schemaVersion") or raw["schemaVersion"].getInt(0) != 1:
    return err("schemaVersion != 1")
  let invId = stringValue(raw{"invariantId"})
  if invId notin InvariantIds:
    return err("invariantId '" & invId & "' is not one of R1..R8")

  # collection / freshness: the collector freezes generatedAt/freshUntil; the
  # evaluator only checks evaluationTime <= freshUntil (time only affects
  # validity, never the verdict directly).
  if not raw.hasKey("collection") or raw["collection"].kind != JObject:
    return err("missing collection envelope")
  let col = raw["collection"]
  if not col.hasKey("generatedAt") or stringValue(col["generatedAt"]) == "":
    return err("missing collection.generatedAt")
  if not col.hasKey("freshUntil") or stringValue(col["freshUntil"]) == "":
    return err("missing collection.freshUntil")
  if ctx.evaluationTime != "" and ctx.evaluationTime > stringValue(col["freshUntil"]):
    return err("stale evidence (evaluationTime > freshUntil)")

  # repository identity (only when declared)
  if raw.hasKey("repoIdentity") and raw["repoIdentity"].kind == JObject:
    let ri = raw["repoIdentity"]
    if ri.hasKey("head") and ctx.repoHead != "" and stringValue(ri["head"]) != ctx.repoHead:
      return err("repoIdentity.head mismatch")
    if ri.hasKey("treeDigest") and ctx.treeDigest != "" and
       stringValue(ri["treeDigest"]) != ctx.treeDigest:
      return err("repoIdentity.treeDigest mismatch")
    if ri.hasKey("workingTreeClean"):
      let declaredClean = boolValue(ri["workingTreeClean"], true)
      if invId in CleanTreeRequiredInvariants and not declaredClean:
        return err("evidence for " & invId & " requires a clean working tree")
      if declaredClean != ctx.workingTreeClean and invId notin CleanTreeRequiredInvariants:
        return err("repoIdentity.workingTreeClean mismatch")

  # toolchain identity (when declared)
  if raw.hasKey("toolchain") and raw["toolchain"].kind == JObject:
    let tc = raw["toolchain"]
    if tc.hasKey("nim") and ctx.toolchainNim != "" and stringValue(tc["nim"]) != ctx.toolchainNim:
      return err("toolchain.nim mismatch")
    if tc.hasKey("z3") and ctx.toolchainZ3 != "" and stringValue(tc["z3"]) != ctx.toolchainZ3:
      return err("toolchain.z3 mismatch")
    if tc.hasKey("lean") and ctx.toolchainLean != "" and stringValue(tc["lean"]) != ctx.toolchainLean:
      return err("toolchain.lean mismatch")

  # substance: an evidence file needs observations and at least one source
  if obsListOf(raw).len == 0:
    return err("no observations recorded")
  if not raw.hasKey("sources") or raw["sources"].kind != JArray or raw["sources"].len == 0:
    return err("no sources recorded")

  ok(ValidatedEvidence(invariantId: invId, raw: raw))

# ---------------------------------------------------------------------------
# Normalization (pure)
# ---------------------------------------------------------------------------

type ObsKey = tuple[k, scope, subject: string]

proc mergeKeyOf(o: JsonNode): ObsKey =
  (obsKey(o), obsScope(o), obsSubject(o))

proc observeSelf(o: JsonNode): bool =
  ## Helper used by normalization to skip degenerate observations (no key).
  obsKey(o) != ""

proc normalizeBundle*(evidences: seq[JsonNode], policy: JsonNode = newJObject()): Result[JsonNode, string] =
  ## Merges all envelopes per invariant; detects contradictions on the
  ## (key, scope, subject) identity; produces a canonical bundle digest.
  ## Invariants with no evidence files stay absent -> UNKNOWN at evaluation.
  var
    merged = initTable[string, Table[ObsKey, JsonNode]]()
    conflicts = initTable[string, seq[string]]()
    commandsLists = initTable[string, seq[JsonNode]]()
  for ev in evidences:
    if ev == nil or ev.kind != JObject: continue
    let invId = stringValue(ev{"invariantId"})
    if invId notin InvariantIds: continue
    if not merged.hasKey(invId):
      merged[invId] = initTable[ObsKey, JsonNode]()
    var m = merged[invId]
    for o in obsListOf(ev):
      if not observeSelf(o): continue
      let k = mergeKeyOf(o)
      if m.hasKey(k):
        if m[k] != obsValue(o):
          var c = conflicts.mgetOrPut(invId, @[])
          if k.k notin c:
            c.add(k.k)
          conflicts[invId] = c
      else:
        m[k] = obsValue(o)
    merged[invId] = m
    # §4 envelope-level `commands` array (reproduction commands with exit
    # codes) rides alongside observations. Command ORDER is semantic content,
    # so each envelope's list is preserved whole, in evidence order — the
    # per-invariant merge is an array of per-envelope lists, never flattened
    # and never sorted.
    if ev.hasKey("commands") and ev["commands"].kind == JArray:
      commandsLists.mgetOrPut(invId, @[]).add(ev["commands"])

  let invariants = newJObject()
  for invId in InvariantIds:
    if not merged.hasKey(invId):
      continue
    let invNode = newJObject()
    var obsOut = newJArray()
    var keys = toSeq(merged[invId].keys)
    keys.sort(proc(a, b: ObsKey): int =
      cmp(a.k & "\x1f" & a.scope & "\x1f" & a.subject,
          b.k & "\x1f" & b.scope & "\x1f" & b.subject))
    for k in keys:
      let o = newJObject()
      o["key"] = %k.k
      o["scope"] = %k.scope
      o["subject"] = %k.subject
      o["value"] = merged[invId][k]
      obsOut.add(o)
    invNode["observations"] = obsOut
    if commandsLists.hasKey(invId):
      let ca = newJArray()
      for c in commandsLists[invId]:
        ca.add(c)
      invNode["commands"] = ca
    if conflicts.hasKey(invId):
      invNode["contradiction"] = %true
      let cj = newJArray()
      for c in conflicts[invId]:
        cj.add(%c)
      invNode["conflicts"] = cj
    else:
      invNode["contradiction"] = %false
      invNode["conflicts"] = newJArray()
    invariants[invId] = invNode

  let bundle = newJObject()
  bundle["schemaVersion"] = %1
  bundle["invariants"] = invariants
  bundle["bundleDigest"] = %(canonicalSha256(invariants))
  bundle["policyId"] = %DefaultPolicyHash
  ok(bundle)

# ---------------------------------------------------------------------------
# Rule implementations (pure semantics — the decision core)
# ---------------------------------------------------------------------------

proc policyCriticality(policy: JsonNode, invId: string): string =
  ## criticality from policy data; unknown policy entry -> non-critical.
  if policy != nil and policy.kind == JObject and policy.hasKey("invariants"):
    let invs = policy["invariants"]
    if invs.kind == JObject and invs.hasKey(invId) and invs[invId].kind == JObject:
      let cr = stringValue(invs[invId]{"criticality"})
      if cr != "": return cr
  "non-critical"

proc contractCommandsOf(policy: JsonNode): seq[string] =
  result = @[]
  if policy != nil and policy.kind == JObject:
    for section in ["r1", "r5"]:
      if policy.hasKey(section) and policy[section].kind == JObject and
         policy[section].hasKey("contractCommands"):
        let a = policy[section]["contractCommands"]
        if a.kind == JArray:
          for it in a.items:
            if it.kind == JString and it.getStr() != "" and it.getStr() notin result:
              result.add(it.getStr())
  if result.len == 0:
    result = @["ax prove", "ax report", "ax status"]

# ---------------------------------------------------------------------------
# U1 — trust-boundary register as an observation key (ADR-0030 Residual U1)
#
# A readiness GO for a subject-language lane requires every trust boundary
# registered for that lane (policy r1.trustBoundaryLanes) to have
# exists:true in src/core/trusted/trust_boundary.nim. Fail-closed in every
# unconfirmed direction: unregistered lane, boundary absent from the register,
# and exists:false all block the lane. The register is read-only here —
# category and exists are never flipped by readiness; that is a human decision.
# ---------------------------------------------------------------------------

proc trustLaneClaimsOf(obs: seq[JsonNode]): seq[string] =
  ## Distinct subject-language lanes claimed for readiness GO via the
  ## `subjectLane` observation key. No claim -> no lane gate (lane scope is
  ## claimed into readiness, never assumed).
  for v in allValues(obs, "subjectLane"):
    for s in stringListValue(v):
      if s notin result:
        result.add(s)

proc policyLaneBoundaries(policy: JsonNode, lane: string): seq[string] =
  ## policy.r1.trustBoundaryLanes[lane] — the register components whose
  ## existence the lane's GO requires. Empty = lane not registered.
  if policy != nil and policy.kind == JObject and policy.hasKey("r1") and
     policy["r1"].kind == JObject:
    let lanes = policy["r1"]{"trustBoundaryLanes"}
    if lanes != nil and lanes.kind == JObject and lanes.hasKey(lane):
      return stringListValue(lanes[lane])
  result = @[]

proc trustLaneViolations*(obs: seq[JsonNode], policy: JsonNode,
                          register: openArray[TrustBoundary]): seq[string] =
  ## Violation reasons for the claimed lanes, derived only from
  ## (policy lane mapping x register `exists`). Empty = no claimed lane is
  ## blocked. Takes the register as a parameter so tests can mutate it and
  ## prove the gate reads the register instead of a restated copy.
  for lane in trustLaneClaimsOf(obs):
    let required = policyLaneBoundaries(policy, lane)
    if required.len == 0:
      result.add("subjectLane '" & lane & "': not registered in policy " &
                 "r1.trustBoundaryLanes (no GO for unregistered lane)")
      continue
    for comp in required:
      var declared = false
      for b in register:
        if b.component == comp:
          declared = true
          if not b.exists:
            result.add("subjectLane '" & lane & "': trust boundary '" & comp &
                       "' is exists:false in the trust register (no GO)")
          break
      if not declared:
        result.add("subjectLane '" & lane & "': trust boundary '" & comp &
                   "' is not declared in the trust register (no GO)")

proc ruleR1(obs: seq[JsonNode], policy: JsonNode): InvState =
  ## documented + contract commands must exist on the CLI surface; and a
  ## claimed subject-language lane whose register boundaries are not all
  ## exists:true cannot PASS (U1) — readiness cannot GO a lane the register
  ## says does not exist.
  var documented: seq[string] = @[]
  for v in allValues(obs, "documentedCommand"):
    for s in stringListValue(v):
      if s notin documented:
        documented.add(s)
  var required = documented
  for c in contractCommandsOf(policy):
    if c notin required:
      required.add(c)
  if trustLaneViolations(obs, policy, AxiomTrustBoundary).len > 0:
    return stFail
  if required.len == 0:
    return stUnknown
  for cmd in required:
    let exists = findObs(obs, "commandExists", scope = "surface", subject = cmd)
    if exists.isNone or not boolValue(exists.get, false):
      return stFail
  stPass

proc ruleR2(obs: seq[JsonNode]): InvState =
  if obs.len == 0:
    return stUnknown
  let dual = findObs(obs, "certGreenDualEvidenceRequired")
  if dual.isSome and not boolValue(dual.get, true):
    return stFail
  for o in obs:
    if obsKey(o) == "z3OnlyCanProduceCertGreen":
      let sc = obsScope(o)
      if (sc == "" or sc == "canonical") and boolValue(obsValue(o), true):
        return stFail
  let vac = findObs(obs, "summaryVerifiedIncludesVacuous")
  if vac.isSome and boolValue(vac.get, true):
    return stFail
  # Z3-only vs dual must be distinguishable in the output
  # (any observed surface that collapses them -> FAIL)
  var distAll = true
  var distSeen = false
  for o in obs:
    if obsKey(o) == "z3VsDualDistinguishable":
      distSeen = true
      if not boolValue(obsValue(o), true):
        distAll = false
  if distSeen and not distAll:
    return stFail
  let doc = findObs(obs, "verifiedSemanticsDocumented")
  if doc.isSome and not boolValue(doc.get, true):
    return stFail
  stPass

proc ruleR3(obs: seq[JsonNode]): InvState =
  if obs.len == 0:
    return stUnknown
  let eq = findObs(obs, "canonicalProjectionHashEqual")
  if eq.isSome and not boolValue(eq.get, true):
    return stFail
  for key in ["canonicalInputHash", "configHash", "solverIdentity",
              "cachePolicy", "canonicalExecutionFingerprint"]:
    let v = findObs(obs, key)
    if v.isNone or stringValue(v.get) == "":
      return stUnknown
  # Relocation/cross-path determinism (policy observationKeys.R3): only an
  # observed bool counts. Absent/unmeasured -> UNKNOWN (fail-closed, never a
  # silent PASS); a confirmed false -> FAIL.
  var relocationMeasured = true
  for key in ["subjectRunProjectionHashEqual", "pathIndependentProjectionEqual"]:
    let rel = findObs(obs, key)
    if rel.isNone or rel.get.kind != JBool:
      relocationMeasured = false
    elif not rel.get.getBool():
      return stFail
  if not relocationMeasured:
    return stUnknown
  let envC = findObs(obs, "environmentControlled")
  if envC.isSome and not boolValue(envC.get, true):
    return stFail
  stPass

proc ruleR4(obs: seq[JsonNode], policy: JsonNode): InvState =
  if obs.len == 0:
    return stUnknown
  var required: seq[string] = @[]
  if policy != nil and policy.kind == JObject and policy.hasKey("r4") and
     policy["r4"].kind == JObject:
    let rf = policy["r4"]["requiredFields"]
    if rf.kind == JArray:
      for it in rf.items:
        if it.kind == JString and it.getStr() != "":
          required.add(it.getStr())
  if required.len == 0:
    required = @["claim", "attestation", "inputHash", "provenance",
                 "toolchainIdentity", "proofDigest"]
  for f in required:
    var present = false
    for o in obs:
      if obsKey(o) == "certFieldPresent" and obsSubject(o) == f:
        if boolValue(obsValue(o), false):
          present = true
        else:
          return stFail
    if not present:
      return stFail
  let recon = findObs(obs, "provenanceReconstructible")
  if recon.isSome and not boolValue(recon.get, true):
    return stFail
  stPass

proc ruleR5(obs: seq[JsonNode], policy: JsonNode): InvState =
  if obs.len == 0:
    return stUnknown
  var anyExitCodeObs = false
  var failure = false
  for cmd in contractCommandsOf(policy):
    let exists = findObs(obs, "commandExists", scope = "surface", subject = cmd)
    if exists.isNone or not boolValue(exists.get, false):
      failure = true
    let help = findObs(obs, "helpSurface", subject = cmd)
    if help.isSome and not boolValue(help.get, true):
      failure = true
  for o in obs:
    if obsKey(o) == "successExitCode" and isNumber(obsValue(o)):
      anyExitCodeObs = true
      let subject = obsSubject(o)
      let success = int(floatValue(obsValue(o), 0.0))
      for need in ["verificationFailureExitCode", "internalErrorExitCode",
                   "invalidInputExitCode"]:
        let nv = findObs(obs, need, subject = subject)
        if nv.isNone:
          failure = true
        elif isNumber(nv.get):
          let code = int(floatValue(nv.get, 0.0))
          if code == success:
            failure = true
  let ver = findObs(obs, "jsonSchemaVersion")
  if ver.isSome and (not isString(ver.get) or stringValue(ver.get) == ""):
    failure = true
  let split = findObs(obs, "stdoutStderrSplit")
  if split.isSome and not boolValue(split.get, true):
    failure = true
  if not anyExitCodeObs:
    return stUnknown
  if failure:
    return stFail
  stPass

proc ruleR6(obs: seq[JsonNode]): InvState =
  if obs.len == 0:
    return stUnknown
  for o in obs:
    let k = obsKey(o)
    if k == "failureConvertsToSuccess" and boolValue(obsValue(o), false):
      return stFail
    if k == "exceptionSwallowed" and boolValue(obsValue(o), false):
      return stFail
  stPass

proc ruleR7(obs: seq[JsonNode], policy: JsonNode): tuple[state: InvState, promote: bool] =
  ## R7 is non-critical for low coverage, but scope overclaim PROMOTES to
  ## R1/R2 FAIL (fixed evaluator rule, not policy data).
  result = (stUnknown, false)
  if obs.len == 0:
    return
  var claimed: seq[string] = @[]
  var emitted: seq[string] = @[]
  var coverages: seq[float] = @[]
  for o in obs:
    case obsKey(o)
    of "claimedScope":
      for s in stringListValue(obsValue(o)):
        if s notin claimed: claimed.add(s)
    of "verifiedEmitterScope":
      for s in stringListValue(obsValue(o)):
        if s notin emitted: emitted.add(s)
    of "measuredCoverage":
      if isNumber(obsValue(o)):
        coverages.add(floatValue(obsValue(o), 0.0))
    else: discard
  if claimed.len > 0 and emitted.len > 0:
    for tok in emitted:
      if tok notin claimed:
        result.promote = true
        break
  if coverages.len == 0:
    if claimed.len == 0:
      result.state = stFail
    return  # UNKNOWN if no measurement
  if claimed.len == 0:
    result.state = stFail
    return
  var threshold = 0.5
  if policy != nil and policy.kind == JObject and policy.hasKey("r7") and
     policy["r7"].kind == JObject:
    threshold = floatValue(policy["r7"]{"vkdMinThreshold"}, 0.5)
  var minCov = coverages[0]
  for c in coverages:
    if c < minCov:
      minCov = c
  if minCov < threshold:
    result.state = stFail
  else:
    result.state = stPass

# ---------------------------------------------------------------------------
# R8 — §10.6 prepare-sequence machine verification
#
# The product contract fixes the Rust subject prepare order (§10.6): cargo
# fetch --locked -> cargo metadata --format-version=1 --locked -> cargo build
# --frozen. Evidence records the reproduction commands verbatim at the
# envelope level (§4 commands: [{cmd, exitCode, outputDigest}]). The gate is
# EXACT string matching on cmd: §10.6 pins the strings verbatim and collectors
# record command lines verbatim (tools/collect_evidence_probe.nim), so any
# normalization (flag reordering, whitespace) would weaken the fixed-order
# guarantee. Commands outside the prepare sequence recorded alongside are
# tolerated; each required command must appear exactly once, in the required
# relative order, with exitCode 0. Missing / duplicated / out-of-order /
# nonzero-exit / malformed / fully absent commands -> FAIL (fail-closed
# toward NOT GO).
# ---------------------------------------------------------------------------

proc r8PrepareSequenceOf(policy: JsonNode): seq[string] =
  ## policy.r8.prepareSequenceCommands — the contract-fixed prepare order as
  ## policy data (same pattern as r1/r5 contractCommands); a missing or empty
  ## policy entry falls back to the §10.6 strings so the gate never loses its
  ## anchor.
  result = @[]
  if policy != nil and policy.kind == JObject and policy.hasKey("r8") and
     policy["r8"].kind == JObject:
    let a = policy["r8"]{"prepareSequenceCommands"}
    if a != nil and a.kind == JArray:
      for it in a.items:
        if it.kind == JString and it.getStr() != "" and it.getStr() notin result:
          result.add(it.getStr())
  if result.len == 0:
    result = @["cargo fetch --locked",
               "cargo metadata --format-version=1 --locked",
               "cargo build --frozen"]

proc r8SequenceViolations*(commands: JsonNode, policy: JsonNode): seq[string] =
  ## Violation reasons for the R8 prepare sequence, derived only from the
  ## bundle's merged `commands` lists (one per R8 evidence envelope, in
  ## evidence order) x policy r8.prepareSequenceCommands. Empty = the recorded
  ## evidence satisfies the sequence. Same consumer pattern as
  ## trustLaneViolations: the rule calls this proc, the CLI surfaces its
  ## reasons verbatim; the vocabulary stays inside the evaluator.
  result = @[]
  let required = r8PrepareSequenceOf(policy)
  if commands == nil or commands.kind != JArray or commands.len == 0:
    result.add("prepare sequence: no commands recorded in R8 evidence (no GO)")
    return
  for list in commands.items:
    if list.kind != JArray:
      result.add("prepare sequence: malformed commands list recorded in R8 evidence (no GO)")
      continue
    if list.len == 0:
      result.add("prepare sequence: empty commands list recorded in R8 evidence (no GO)")
      continue
    var filtered: seq[tuple[cmd: string, exitCode: int]] = @[]
    for entry in list.items:
      if entry.kind != JObject or not isString(entry{"cmd"}):
        result.add("prepare sequence: commands entry without a cmd string (no GO)")
        continue
      let cmd = entry["cmd"].getStr()
      if cmd notin required:
        continue
      if not isNumber(entry{"exitCode"}):
        result.add("prepare sequence: '" & cmd & "' has no integer exitCode (no GO)")
        continue
      filtered.add((cmd, int(floatValue(entry["exitCode"], 0))))
    for r in required:
      var hits = 0
      for f in filtered:
        if f.cmd == r: inc hits
      if hits == 0:
        result.add("prepare sequence: '" & r & "' missing from recorded commands (no GO)")
      elif hits > 1:
        result.add("prepare sequence: '" & r & "' recorded " & $hits &
                   " times, expected exactly once (no GO)")
    if filtered.len == required.len:
      for i in 0..<required.len:
        if filtered[i].cmd != required[i]:
          result.add("prepare sequence: '" & required[i] & "' expected at position " &
                     $(i + 1) & ", '" & filtered[i].cmd & "' recorded (out of order, no GO)")
    for f in filtered:
      if f.exitCode != 0:
        result.add("prepare sequence: '" & f.cmd & "' exits " & $f.exitCode &
                   ", exit 0 required (no GO)")

proc ruleR8(obs: seq[JsonNode], commands: JsonNode, policy: JsonNode): InvState =
  if obs.len == 0:
    return stUnknown
  for o in obs:
    case obsKey(o)
    of "installFollowed":
      if not boolValue(obsValue(o), true): return stFail
    of "manualStepsRequired":
      if boolValue(obsValue(o), true): return stFail
    of "cleanRunSucceeded":
      if obsValue(o).kind == JBool and not obsValue(o).getBool(): return stFail
    of "documentedRunSteps":
      if obsValue(o).kind == JBool and not obsValue(o).getBool(): return stFail
    else: discard
  if r8SequenceViolations(commands, policy).len > 0:
    return stFail
  stPass

# ---------------------------------------------------------------------------
# Decision algebra (§3) — ONE mapping, consumed by every readiness surface.
#
# `decideState` / `decideTokens` in core/utils/decision_algebra own the whole
# table. The procs below are projections of it for the two public shapes
# callers use (generic state enum vs. DecisionCandidate); neither judges a
# state on its own, so a critical invariant can no longer be reported as
# NO-GO by one path and UNRESOLVED by another as two authorities.
# ---------------------------------------------------------------------------

proc failureCategoryOf(invId: string): string =
  ## Conservative, documented mapping of a critical invariant to its failure
  ## domain. Unknown/edge ids conservatively map to CONTRACT_FAIL.
  case invId
  of "R1", "R2", "R3", "R8": CategoryContractFail
  of "R4": "EVIDENCE_FAIL"
  of "R5", "R6": "PROVENANCE_FAIL"
  else: CategoryContractFail

proc toStatusTokens*[T: enum](
    states: openArray[tuple[id: string, state: T]],
    policy: JsonNode): seq[StatusToken] =
  ## Projects the readiness view of a candidate — policy criticality and each
  ## invariant's failure domain — onto the closed inputs Decide consumes.
  for (invId, st) in states:
    result.add((id: invId,
                critical: policyCriticality(policy, invId) == "critical",
                token: $st,
                failureDomain: failureCategoryOf(invId)))

proc decisionFromStates*[T: enum](
    states: openArray[tuple[id: string, state: T]],
    policy: JsonNode): DecisionAggregate =
  ## Exported generic so property tests can reuse it with their own enum type.
  decideTokens(toStatusTokens(states, policy))

proc verdictFromStates*[T: enum](
    states: openArray[tuple[id: string, state: T]],
    policy: JsonNode): tuple[verdict: string, conditions: seq[string]] =
  let agg = decisionFromStates(states, policy)
  (agg.verdict, agg.conditions)

proc classifyOutcome*[T: enum](
    states: openArray[tuple[id: string, state: T]],
    policy: JsonNode): tuple[outcome, category: string] =
  ## Same single decision as verdictFromStates, read along the outcome axis
  ## (continual revalidation §4): a CONFIRMED FAIL on a critical invariant is
  ## BLOCK with its failure category, an UNKNOWN / NOT_RUN on a critical
  ## invariant is UNRESOLVED (revalidation needed) and never a confirmed BLOCK,
  ## otherwise CONTINUE. UNKNOWN ≠ FAIL structurally: the observed state is
  ## never conflated with a confirmed contract failure, and an unestablished
  ## critical invariant does not auto-BLOCK the product. The verdict for that
  ## case is NO-GO either way (§3), so outcome never contradicts verdict.
  let agg = decisionFromStates(states, policy)
  (agg.outcome, agg.failureCategory)

# ---------------------------------------------------------------------------
# evaluateReadiness — the deterministic decision core.
# ---------------------------------------------------------------------------

type Obs = tuple[key, scope, subject: string, val: JsonNode]

proc obsAsTuple(o: JsonNode): Obs =
  (obsKey(o), obsScope(o), obsSubject(o), obsValue(o))

proc rawStateOf(policy: JsonNode, invId: string, invNode: JsonNode): tuple[state: InvState, promote: bool] =
  result = (stUnknown, false)
  if invNode == nil or invNode.kind != JObject:
    return
  if invNode.hasKey("contradiction") and invNode["contradiction"].getBool():
    return  # contradiction -> UNKNOWN
  let obs = obsListOf(invNode)
  case invId
  of "R1": result.state = ruleR1(obs, policy)
  of "R2": result.state = ruleR2(obs)
  of "R3": result.state = ruleR3(obs)
  of "R4": result.state = ruleR4(obs, policy)
  of "R5": result.state = ruleR5(obs, policy)
  of "R6": result.state = ruleR6(obs)
  of "R7":
    let (st, promo) = ruleR7(obs, policy)
    result.state = st
    result.promote = promo
  of "R8": result.state = ruleR8(obs, invNode{"commands"}, policy)
  else: discard

proc evaluateReadiness*(policy: JsonNode, bundle: JsonNode): ReadinessDecision =
  ## Pure decision: same (policy, bundle) always produces the same decision.
  var
    states = initTable[string, InvState]()
    promoteR1 = false
    promoteR2 = false
    invariants = newJObject()
  if bundle != nil and bundle.kind == JObject and bundle.hasKey("invariants"):
    invariants = bundle["invariants"]
  for invId in InvariantIds:
    var invNode: JsonNode = nil
    if invariants.kind == JObject and invariants.hasKey(invId):
      invNode = invariants[invId]
    let (st, promo) = rawStateOf(policy, invId, invNode)
    states[invId] = if invNode == nil: stNotRun else: st
    if invId == "R7" and promo:
      promoteR1 = true
      promoteR2 = true
  if promoteR1:
    states["R1"] = stFail
  if promoteR2:
    states["R2"] = stFail

  var candidate = DecisionCandidate(policyId: DefaultPolicyHash)
  for invId in InvariantIds:
    candidate.invariants.add(InvariantStatus(
      id: invId,
      state: states[invId],
      critical: policyCriticality(policy, invId) == "critical",
      failureDomain: failureCategoryOf(invId)))

  let policyHash = canonicalSha256(policy)
  let bundleDigest = if bundle != nil and bundle.kind == JObject and
                      bundle.hasKey("bundleDigest"): bundle["bundleDigest"].getStr() else: ""
  let decision = Decide(candidate,
                        DecisionEvidence(schemaVersion: 1, digest: bundleDigest),
                        ExecutionContract(contractId: policyHash))

  result = ReadinessDecision(
    schemaVersion: 1,
    policyHash: policyHash,
    bundleDigest: decision.evidenceDigest,
    invariantStates: invariantStatesJson(candidate.invariants),
    verdict: decision.verdict,
    conditions: decision.conditions,
    outcome: decision.outcome,
    failureCategory: decision.failureCategory,
    decisionDigest: decision.decisionDigest)

proc decisionJson*(d: ReadinessDecision): JsonNode =
  result = newJObject()
  result["schemaVersion"] = %d.schemaVersion
  result["policyHash"] = %d.policyHash
  result["bundleDigest"] = %d.bundleDigest
  result["invariantStates"] = d.invariantStates
  result["verdict"] = %d.verdict
  result["outcome"] = %d.outcome
  result["failureCategory"] = %d.failureCategory
  let ca = newJArray()
  for c in d.conditions:
    ca.add(%c)
  result["conditions"] = ca
  result["decisionDigest"] = %d.decisionDigest

# ---------------------------------------------------------------------------
# IO layer — the only impure code except the CLI itself.
# ---------------------------------------------------------------------------

proc loadEvidenceFiles*(dir: string): Result[seq[JsonNode], string] =
  if not dirExists(dir):
    return err("evidence directory does not exist: " & dir)
  var parsed: seq[JsonNode] = @[]
  for f in walkFiles(dir & "/*.json"):
    try:
      parsed.add(parseFile(f))
    except CatchableError as e:
      return err("unparsable evidence file " & f & ": " & e.msg)
  ok(parsed)

proc loadEvidenceFromJson*(root: JsonNode): seq[JsonNode] =
  ## Accepts a JArray of envelopes, {"evidence": [...]}, or a single envelope.
  result = @[]
  if root == nil:
    return
  if root.kind == JArray:
    for it in root.items:
      result.add(it)
  elif root.kind == JObject:
    if root.hasKey("evidence") and root["evidence"].kind == JArray:
      for it in root["evidence"].items:
        result.add(it)
    else:
      result.add(root)

# ---------------------------------------------------------------------------
# CLI entry point (single-shot, deterministic)
# ---------------------------------------------------------------------------

when isMainModule:
  ##   tools/readiness_evaluator --policy config/readiness_policy.json \
  ##     --evidence-dir data/readiness/evidence \
  ##     --repo-head <sha> --tree-digest <digest> --working-tree-clean true \
  ##     --toolchain-nim 2.2.10 --toolchain-z3 4.13.3 --toolchain-lean 4.29.0 \
  ##     --eval-time <ISO8601> [--out decision.json]
  ##
  ##   tools/readiness_evaluator --bundle-file fixtures.json ... (single file)
  var
    policyPath = ""
    evidenceDir = ""
    bundleFilePath = ""
    repoHead = ""
    treeDigest = ""
    branch = "main"
    workingTreeClean = true
    nimT = ""
    z3T = ""
    leanT = ""
    evalTime = ""
    outPath = ""
  let args = commandLineParams()
  var i = 0
  proc needValue(a: string): string =
    if i >= args.len - 1:
      stderr.writeLine("missing value for " & a)
      quit(2)
    inc i
    args[i]
  while i < args.len:
    let a = args[i]
    case a
    of "--policy": policyPath = needValue(a)
    of "--evidence-dir": evidenceDir = needValue(a)
    of "--bundle-file": bundleFilePath = needValue(a)
    of "--repo-head": repoHead = needValue(a)
    of "--tree-digest": treeDigest = needValue(a)
    of "--branch": branch = needValue(a)
    of "--working-tree-clean": workingTreeClean = needValue(a) == "true"
    of "--toolchain-nim": nimT = needValue(a)
    of "--toolchain-z3": z3T = needValue(a)
    of "--toolchain-lean": leanT = needValue(a)
    of "--eval-time": evalTime = needValue(a)
    of "--out": outPath = needValue(a)
    of "--help", "-h":
      echo "usage: readiness_evaluator --policy P --eval-time ISO [--evidence-dir D|--bundle-file F] [--out F]"
      quit(0)
    else:
      stderr.writeLine("unknown option: " & a)
      quit(1)
    inc i

  if policyPath == "" or evalTime == "":
    stderr.writeLine("usage: readiness_evaluator --policy P --eval-time ISO [--evidence-dir D|--bundle-file F] --out F")
    quit(1)
  if evidenceDir == "" and bundleFilePath == "":
    stderr.writeLine("either --evidence-dir or --bundle-file is required")
    quit(1)

  var policy: JsonNode
  try:
    policy = parseFile(policyPath)
  except CatchableError as e:
    stderr.writeLine("cannot load policy: " & e.msg)
    quit(1)

  let ctx = makeContext(repoHead = repoHead, repoBranch = branch,
                        treeDigest = treeDigest,
                        workingTreeClean = workingTreeClean,
                        toolchainNim = nimT, toolchainZ3 = z3T,
                        toolchainLean = leanT, evaluationTime = evalTime)

  var raws: seq[JsonNode] = @[]
  if bundleFilePath != "":
    try:
      let root = parseFile(bundleFilePath)
      raws = loadEvidenceFromJson(root)
    except CatchableError as e:
      stderr.writeLine("cannot read bundle file: " & e.msg)
      quit(1)
  else:
    let filesRes = loadEvidenceFiles(evidenceDir)
    if filesRes.isErr:
      stderr.writeLine("LOAD ERROR: " & filesRes.error)
      quit(1)
    raws = filesRes.get

  var valid: seq[JsonNode] = @[]
  var diag: seq[string] = @[]
  for raw in raws:
    let v = validateEvidence(raw, ctx)
    if v.isErr:
      let id = stringValue(raw{"invariantId"})
      diag.add("INVALID " & (if id != "": id else: "<no-id>") & ": " & v.error)
    else:
      valid.add(raw)
  for line in diag:
    stderr.writeLine(line)

  let bundleRes = normalizeBundle(valid)
  if bundleRes.isErr:
    stderr.writeLine("NORMALIZE ERROR: " & bundleRes.error)
    quit(1)
  let bundle = bundleRes.get
  let decision = evaluateReadiness(policy, bundle)
  let outJson = decisionJson(decision)

  stderr.writeLine("bundle files: " & $raws.len &
                   " valid: " & $valid.len &
                   " invalid: " & $diag.len)
  stderr.writeLine("verdict: " & decision.verdict)
  for invId in InvariantIds:
    stderr.writeLine("  " & invId & " = " & $decision.invariantStates[invId].getStr())
  if decision.invariantStates["R1"].getStr() == "FAIL":
    for v in trustLaneViolations(obsListOf(bundle{"invariants"}{"R1"}), policy,
                                 AxiomTrustBoundary):
      stderr.writeLine("  R1 reason: " & v)
  if decision.invariantStates["R8"].getStr() == "FAIL":
    let r8Node = bundle{"invariants"}{"R8"}
    if r8Node != nil:
      for v in r8SequenceViolations(r8Node{"commands"}, policy):
        stderr.writeLine("  R8 reason: " & v)

  if outPath != "":
    try:
      writeFile(outPath, pretty(outJson))
      stderr.writeLine("wrote decision to " & outPath)
    except CatchableError as e:
      stderr.writeLine("cannot write out: " & e.msg)
      quit(1)
  else:
    echo pretty(outJson)