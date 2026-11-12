## src/verification/accounting/run_accounting.nim — X1.0 Semantic Accounting
## Contract reducer + X1 canonical boundary (DEBT#458 closed)
##
## Canonical execution-accounting reducer (SSOT for the Phase X1.0 contract,
## docs/spec/execution_accounting_contract.md). Extracted into an importable
## module so unit tests can prove the join-operator algebra directly;
## tools/phase_x0_accounting.nim is the thin CLI on top.
##
## Input: `seq[JsonNode]` of per-wave report JSON objects + an eligibility map
## (unitId -> eligibility class, e.g. "elProofCandidate"). Output: RunAccounting
## with the canonical 3-axis model, the deterministic CONTESTED mapping, and the
## GateVerdict rule.
##
## All join operators are associative · commutative · idempotent, so wave
## ordering cannot affect RunAccounting (permutation-invariant). The X1.0 join
## algebra is the contract — no new production merge implementation.
##
## Phase X1 — canonical boundary installation (DEBT#458):
##   CanonicalRunResult = RunAccounting + ExecutionEvidence + RunOutcome.
##   RunOutcome is the SOLE run-verdict authority (INV-X1 inversion, Plan 1):
##   its three completeness booleans are RAW projections computed at
##   construction only (never authoritative as verdicts), while the
##   verdict/basis fields are decided EXCLUSIVELY by
##   verification_decision_authority.evaluateRunOutcome — no other code path
##   may produce a run-level PASS. run_accounting preserves raw state; it
##   never derives a gate verdict.
##   The legacy report (renderLegacyReport), the state file (renderPersist)
##   and the TrustCommit projection (UniverseIntegrityProjection) are pure
##   projections of (CanonicalRunResult, PreRunContext) — the last-wave
##   document is never a data source anywhere.
##
## Read path (restored state): this module owns the two PURE halves only —
## revalidateRestoredStateIdentity (identity re-measurement, §15.3),
## demoteRestoredReusedUnits (drop the REUSED satisfactions it cannot
## establish) and runAccountingFromJson (re-hydrate the persisted
## `runAccounting` block). The verdict on the restored state is decided by
## verification_decision_authority.evaluateRestoredStateRunOutcome — this
## module still never derives a gate verdict (§17.1).

import core/trusted/layer_declaration
axiomLayer "verification"
{.push raises: [].}

import std/[json, tables, algorithm, sequtils, strutils, options, sets]
import core/crypto/hash_kernel
import core/orchestrator/orchestrator_report_types
import core/sorter/sorter_core
import core/metrics
import core/types/asi_types
import core/utils/constants

# ---------------------------------------------------------------------------
# Canonical 3-axis model (docs/spec/execution_accounting_contract.md)
# ---------------------------------------------------------------------------

type
  RequirementDecision* = enum
    rdRequired = "REQUIRED"        ## canonical OGR says obligations exist
    rdNotRequired = "NOT_REQUIRED" ## eligibility/OGR basis says no obligation
    rdUnresolved = "UNRESOLVED"    ## no eligibility/OGR basis in the data

  VerificationOutcome* = enum
    voPending = "PENDING"            ## bottom — no terminal result
    voSatisfied = "SATISFIED"        ##
    voUnsatisfied = "UNSATISFIED"    ## top — worse-wins semilattice

  Consistency* = enum
    csConsistent = "CONSISTENT"   ## bottom
    csContested = "CONTESTED"     ## absorbing (OR)

  ExecutionEvidence* = enum
    eeNotAttempted = "NOT_ATTEMPTED"  ## bottom
    eeAttempted = "ATTEMPTED"         ## absorbing (OR)

  SatisfactionSource* = enum
    ssNone = "NONE"                ## not applicable (unit neither SATISFIED nor NOT_REQUIRED)
    ssPreSieved = "PRE_SIEVED"     ## NOT_REQUIRED (no obligation)
    ssReused = "REUSED"            ## SATISFIED via cache reuse
    ssFresh = "FRESH"              ## SATISFIED with execution witness

  GateVerdict* = enum
    gvFail = "FAIL"
    gvPass = "PASS"

  RunVerdict* = enum
    ## Run-level verdict (INV-X1 inversion — decided by VDA ONLY; the zero
    ## value is INCONCLUSIVE = "undecided" until evaluateRunOutcome runs).
    ## The vr* identifiers avoid collision with the pre-existing
    ## RequestVerdict family (request_result.nim: rvPass/rvFail/rvTimeout/
    ## rvError) — the guarded production symbol is vrPass (VDA-exclusive).
    vrInconclusive = "INCONCLUSIVE"  ## undecided, or timeout/infra/evidence failure, vacuous, skipped
    vrFail = "FAIL"                  ## proof-level failure only (counterexample/UNSATISFIED after attempt)
    vrBlocked = "BLOCKED"            ## pending ∧ attempted==0 ∧ fact-gate
    vrPass = "PASS"                  ## decided ONLY by verification_decision_authority

  RunVerdictBasis* = enum
    ## Verbal basis of a run-level PASS (NONE for non-PASS outcomes).
    rbNone = "NONE"
    rbProven = "PROVEN"              ## obligation ≥1 ∧ KAA(verified fresh evidence) exists
    rbNoObligation = "NO_OBLIGATION" ## non-empty universe ∧ all NOT_REQUIRED ∧ enumeration completed
    rbReused = "REUSED"              ## every satisfied unit's reuse basis verified ((a)-(e) conditions)

  RunOutcome* = object
    planComplete*: bool            ## unresolvedDecisionCount == 0 (RAW projection)
    executionComplete*: bool       ## every REQUIRED unit has ATTEMPTED evidence (RAW projection)
    verificationComplete*: bool    ## no pending/contested/unsatisfied/unresolved (RAW projection)
    verdict*: RunVerdict           ## set ONLY by verification_decision_authority (INV-X1 inversion)
    basis*: RunVerdictBasis        ## set ONLY by verification_decision_authority
    reusedConditionsMet*: seq[string] ## non-empty iff basis == REUSED (5-condition labels)

  UnitAccounting* = object
    unitId*: string
    requirementDecision*: RequirementDecision
    verificationOutcome*: VerificationOutcome  ## meaningful only for REQUIRED units
    consistency*: Consistency
    executionEvidence*: ExecutionEvidence
    satisfactionSource*: SatisfactionSource

  RunAccounting* = object
    requiredCount*: int
    notRequiredCount*: int
    unresolvedDecisionCount*: int
    satisfiedCount*: int
    unsatisfiedCount*: int
    pendingCount*: int
    contestedCount*: int
    satisfiedByFresh*: int
    satisfiedByReused*: int
    preSievedCount*: int
    attemptedCount*: int
    notAttemptedCount*: int
    freshExecutionCount*: int     ## |FreshExecutionObservedSet| — distinct units with terminal-verdict-proxy evidence
    executedCount*: int           ## units with a runtime verdict record
    proofFailedCount*: int        ## distinct REQUIRED units merged UNSATISFIED with a genuine proof-attempt failure (status=failed)
    timeoutUnsatCount*: int       ## distinct REQUIRED units merged UNSATISFIED with only timeout rows (raw, kept)
    reuseEligibleRowCount*: int   ## cache-hit rows passing the 5-condition REUSED re-verification
    reuseRejectedRowCount*: int   ## cache-hit rows failing the re-verification (count-only rows included)
    runOutcome*: RunOutcome
    units*: seq[UnitAccounting]   ## sorted by unitId (deterministic)
    anomalies*: seq[string]       ## sorted + deduped (order-independent)
    derivations*: seq[string]

# ---------------------------------------------------------------------------
# Join operators (exact table from the contract doc)
# ---------------------------------------------------------------------------

func joinDecision*(a, b: RequirementDecision): RequirementDecision {.raises: [].} =
  ## assert-equal; conflict → UNRESOLVED (+ anomaly recorded by the reducer).
  ## The decision VALUE is associative · commutative · idempotent; conflict
  ## anomalies are deduped by the reducer so the anomaly set is too.
  if a == b: a else: rdUnresolved

func joinOutcome*(a, b: VerificationOutcome): VerificationOutcome {.raises: [].} =
  ## worse-wins semilattice: PENDING < SATISFIED < UNSATISFIED (max by enum order).
  ## Precedent: request_result.nim:19-36 (rvPass<rvFail<rvTimeout<rvError, sup=worse wins).
  if a >= b: a else: b

func joinConsistency*(a, b: Consistency): Consistency {.raises: [].} =
  ## OR — CONTESTED absorbing (max by enum order).
  if a >= b: a else: b

func joinEvidence*(a, b: ExecutionEvidence): ExecutionEvidence {.raises: [].} =
  ## OR — ATTEMPTED absorbing (max by enum order).
  if a >= b: a else: b

func joinSource*(a, b: SatisfactionSource): SatisfactionSource {.raises: [].} =
  ## precedence-absorb: FRESH > REUSED > PRE_SIEVED (ssNone is identity/bottom).
  if a >= b: a else: b

# ---------------------------------------------------------------------------
# Per-wave JSON extraction (pure)
# ---------------------------------------------------------------------------

func safeGetStr(node: JsonNode; key: string; default = ""): string {.raises: [].} =
  if node.isNil: return default
  let v = node{key}
  if v.isNil or v.kind != JString: default
  else: v.getStr()

func safeGetBool(node: JsonNode; key: string, default = false): bool {.raises: [].} =
  if node.isNil: return default
  let v = node{key}
  if v.isNil or v.kind != JBool: default
  else: v.getBool()

func safeGetInt(node: JsonNode; key: string, default = 0): int {.raises: [].} =
  ## Declared here with the other accessors (not next to the ExecutionEvidence
  ## collectors) because the read-path rehydration in `runAccountingFromJson`
  ## consumes it too.
  if node.isNil: return default
  let v = node{key}
  if v.isNil or v.kind != JInt: default
  else: v.getInt()

func waveNodeReports(wave: JsonNode): seq[JsonNode] {.raises: [].} =
  ## nodeReports of one per-wave report (may be empty).
  if wave.isNil: return @[]
  let nr = wave{"nodeReports"}
  if nr.isNil or nr.kind != JArray: return @[]
  result = @[]
  for n in nr.elems:
    if not n.isNil and n.kind == JObject:
      result.add(n)

func eligibilityClass(eligibility: JsonNode; unitId: string): string {.raises: [].} =
  if eligibility.isNil or eligibility.kind != JObject: return ""
  let v = eligibility{unitId}
  if v.isNil or v.kind != JString: return ""
  v.getStr()

# ---------------------------------------------------------------------------
# Per-unit derivation
# ---------------------------------------------------------------------------

func deriveDecision(eligibility: JsonNode; unitId: string): RequirementDecision {.raises: [].} =
  ## RequirementDecision is a run-wide planning-axis property: the canonical OGR
  ## basis (eligibility map) decides obligation existence — backends do not.
  ##   elProofCandidate / ogrGenerated            → REQUIRED
  ##   elNoObligation / elUnsupported / elMalformed → NOT_REQUIRED
  ##   no basis in the data                        → UNRESOLVED
  case eligibilityClass(eligibility, unitId)
  of "elProofCandidate", "ogrGenerated": rdRequired
  of "elNoObligation", "elUnsupported", "elMalformed": rdNotRequired
  else: rdUnresolved

func statusToOutcome(status: string): VerificationOutcome {.raises: [].} =
  ## Runtime verdict → VerificationOutcome. Only meaningful for REQUIRED units.
  case status
  of "verified", "inductive_valid": voSatisfied
  of "failed", "timeout": voUnsatisfied
  else: voPending  # no_obligation / not_verifiable / pre_sieved / blocked / skipped / vacuous / unknown

func statusWitnessesInvocation(status: string; cacheHit: bool): bool {.raises: [].} =
  ## FreshExecutionObservedSet membership: a unit has evidence of a fresh
  ## invocation when its runtime verdict requires a genuine solver/proof
  ## invocation (evidenceSource = terminal_verdict_proxy — the runtime verdict
  ## proxies the invocation; the witness itself is emitted only in a later
  ## phase). Cache hits (replayed persisted verdicts) do NOT evidence a fresh
  ## invocation. Evidence hierarchy (docs/spec/execution_accounting_contract.md):
  ## dispatch-only < terminal-verdict-proxy < solver-observed < invocation-witness
  if cacheHit: return false
  case status
  of "verified", "inductive_valid", "failed", "timeout", "vacuous": true
  else: false

# ---------------------------------------------------------------------------
# REUSED basis — per-row re-verification (Plan 1, Authority Unification)
# ---------------------------------------------------------------------------
## The (status, cacheHit=true) pair alone is NEVER a satisfaction. A reuse row
## is a REUSED satisfaction only when its reuseRecord passes the 5-condition
## re-verification — the wiring of the previously unwired contract
## (docs/spec/workunit_fingerprint_cas_contract.md §6.1, reusable(U) ≡
## Fingerprint(U.inputs, U.contract, U.toolchain) == CachedFingerprint ∧
## contentDigest(CachedResult) == SHA256(CachedResult)):
##   (a) subject identity:  the unit's CURRENT transitive source fingerprint
##                          (row.subjectFingerprint) == record.subjectFingerprint
##   (b) execution identity: record.executionBundleFingerprint ==
##                          ctx.executionBundleFingerprint (identity.nim:188)
##   (c) state identity:    record.executionConfigDigest == ctx.executionConfigDigest
##                          (identity.nim:141)
##   (d) evidence artifact: record.artifactRef is a concrete cert/vault/spec
##                          path ∧ record.contentDigest is a valid digest ∧
##                          record.artifactVerified (per-READ content re-verification
##                          performed by the IO-side reader on the execution path)
##   (e) evidence validity: record.toolchainIdentity == ctx.toolchainIdentity ∧
##                          record.recordedStatus is terminal-verified ∧
##                          record.leanCompilerVerified ∧ record.validatedAtEpoch ==
##                          ctx.currentEpoch (staleness)
## Fail-closed: any missing/mismatched component → basis NOT established.

type ReuseVerificationContext* = object
  executionBundleFingerprint*: string  ## (b) current pinned canonical bundle fingerprint
  executionConfigDigest*: string       ## (c) current execution-contract digest
  toolchainIdentity*: string           ## (e) current toolchain identity (D2)
  currentEpoch*: string                ## (e) current EXECUTION semantic epoch — see NOTE below
  verifierBuildId*: string             ## (e) current content-based verifier build identity (engineBuild) — the run-level observation surface for every verdict class; "unmeasured"/"" never establishes
  platform*: string = ""              ## measured host os/arch (identity.nim.hostPlatformId); an input of (c)

# NOTE on `currentEpoch` (terminology, §A3): this is the EXECUTION semantic epoch
# — sha256(toolchainIdentity|executionConfigDigest|executionBundleFingerprint)
# — i.e. "which computation closure produced this". It is NOT the CI epoch /
# cutover generation of docs/agents/ci_epoch_cutover.md (the `.github/` topology
# generation). The two are unrelated: a CI generation number must never enter
# this value, or cache/verdict identity would move on every pipeline cutover.
# The field name is kept — it is a compile-time identifier with existing
# producers/consumers (tests/unit/phase_x10_accounting_test.nim constructs it);
# the persisted/JSON spelling is `executionEpoch`, and every NEW identifier in
# this module uses that name.

func defaultReuseVerificationContext*(): ReuseVerificationContext {.raises: [].} =
  ## Fail-closed default: no pinned values → no reuse record can verify
  ## ((b)/(c)/(e) comparisons cannot hold against the empty context).
  ReuseVerificationContext()

type ReuseVerificationResult* = object
  ok*: bool
  reasons*: seq[string]

func isSha256Hex(s: string): bool {.raises: [].} =
  if s.len != 64: return false
  for ch in s:
    if ch notin {'0'..'9', 'a'..'f', 'A'..'F'}: return false
  true

func verifyReuseRecord*(row: JsonNode; ctx: ReuseVerificationContext): ReuseVerificationResult {.
  raises: [].} =
  ## Per-row 5-condition REUSED basis verification (fail-closed).
  result.reasons = @[]
  let record = row{"reuseRecord"}
  if record.isNil or record.kind != JObject:
    result.reasons.add("reuse record missing (count-only reuse row — excluded)")
    return
  # (a) subject identity
  let currentSubject = safeGetStr(row, "subjectFingerprint")
  let recordedSubject = safeGetStr(record, "subjectFingerprint")
  if currentSubject.len == 0 or recordedSubject.len == 0 or currentSubject != recordedSubject:
    result.reasons.add("subject fingerprint mismatch (a)")
  # (b) execution identity
  if ctx.executionBundleFingerprint.len == 0:
    result.reasons.add("no pinned execution-bundle fingerprint in context (b)")
  elif safeGetStr(record, "executionBundleFingerprint") != ctx.executionBundleFingerprint:
    result.reasons.add("execution-bundle fingerprint mismatch (b)")
  # (c) state identity
  if ctx.executionConfigDigest.len == 0:
    result.reasons.add("no current execution-config digest in context (c)")
  elif safeGetStr(record, "executionConfigDigest") != ctx.executionConfigDigest:
    result.reasons.add("execution-config digest mismatch (c)")
  # (d) evidence artifact
  if safeGetStr(record, "artifactRef").len == 0:
    result.reasons.add("no concrete artifact reference (d)")
  if not isSha256Hex(safeGetStr(record, "contentDigest")):
    result.reasons.add("content digest missing/malformed (d)")
  if not safeGetBool(record, "artifactVerified"):
    result.reasons.add("artifact content digest not re-verified on read (d)")
  # (e) evidence validity
  if ctx.toolchainIdentity.len == 0:
    result.reasons.add("no current toolchain identity in context (e)")
  elif safeGetStr(record, "toolchainIdentity") != ctx.toolchainIdentity:
    result.reasons.add("toolchain identity mismatch (e)")
  if safeGetStr(record, "recordedStatus") notin ["verified", "inductive_valid"]:
    result.reasons.add("recorded status not terminal-verified (e)")
  if not safeGetBool(record, "leanCompilerVerified"):
    result.reasons.add("leanCompilerVerified not recorded (e)")
  if ctx.currentEpoch.len == 0:
    result.reasons.add("no current reuse-validation epoch in context (e)")
  elif safeGetStr(record, "validatedAtEpoch") != ctx.currentEpoch:
    result.reasons.add("validation epoch mismatch — stale reuse record (e)")
  result.ok = result.reasons.len == 0

# ---------------------------------------------------------------------------
# Execution identity envelope — the state-level half of the §15.3 conditions
# ---------------------------------------------------------------------------
## `verifyReuseRecord` re-verifies a REUSE ROW against the current context. A
## persisted/restored run STATE is the other carrier of a verdict: it is read
## back by a different process (`ax report`), possibly restored from a cache
## that outlived the run that produced it. Without an identity envelope such a
## state reaches the verdict re-reading nothing but its own recorded numbers.
##
## The envelope is the identity the run was EXECUTED under, persisted by the
## same projection that writes the state file, and re-measured on every read.

const
  executionIdentityKey* = "executionIdentity"   ## envelope key in the run document
  executionEpochKey* = "executionEpoch"        ## §A3: EXECUTION semantic epoch, never a CI epoch/generation

func executionIdentityToJson*(ctx: ReuseVerificationContext): JsonNode {.raises: [].} =
  ## Serialization of the execution identity envelope. Deterministic and
  ## self-describing: a reader can see WHICH identity was pinned, so a missing
  ## or diverging field is diagnosable rather than silent.
  %*{
    "executionBundleFingerprint": ctx.executionBundleFingerprint,
    "executionConfigDigest": ctx.executionConfigDigest,
    "toolchainIdentity": ctx.toolchainIdentity,
    executionEpochKey: ctx.currentEpoch,
    "verifierBuildId": ctx.verifierBuildId,
    "platform": ctx.platform
  }

type
  RestoredStateRevalidation* = object
    ## Outcome of re-validating a restored state against the CURRENT context.
    established*: bool       ## true iff every state-level condition holds
    reasons*: seq[string]    ## sorted; empty iff established

func revalidateRestoredStateIdentity*(
  stateJson: JsonNode;
  ctx: ReuseVerificationContext
): RestoredStateRevalidation {.raises: [].} =
  ## READ-TIME identity re-validation of a restored/persisted run state.
  ##
  ## §15.3 conditions (b)(c)(e) applied to the state as a whole — the row-level
  ## (a) subject identity and (d) evidence artifact stay with verifyReuseRecord.
  ## A state that carries no envelope establishes nothing (fail-closed): an
  ## unbound record is not evidence about the current context.
  ##
  ## Fail-closed on BOTH directions: a value the current context cannot measure
  ## (empty) and a value that simply differs are both "not established".
  var reasons: seq[string] = @[]
  let env = if stateJson.isNil: nil else: stateJson{executionIdentityKey}
  if env.isNil or env.kind != JObject:
    reasons.add("state carries no execution identity envelope — a restored state " &
      "cannot be bound to the current context")
  else:
    let recordedBundleFp = safeGetStr(env, "executionBundleFingerprint")
    let recordedConfigDigest = safeGetStr(env, "executionConfigDigest")
    let recordedToolchain = safeGetStr(env, "toolchainIdentity")
    let recordedExecutionEpoch = safeGetStr(env, executionEpochKey)
    if ctx.executionBundleFingerprint.len == 0:
      reasons.add("no current execution-bundle fingerprint in context (b)")
    elif recordedBundleFp != ctx.executionBundleFingerprint:
      reasons.add("execution-bundle fingerprint mismatch (b)")
    if ctx.executionConfigDigest.len == 0:
      reasons.add("no current execution-config digest in context (c)")
    elif recordedConfigDigest != ctx.executionConfigDigest:
      reasons.add("execution-config digest mismatch (c)")
    if ctx.toolchainIdentity.len == 0:
      reasons.add("no current toolchain identity in context (e)")
    elif recordedToolchain != ctx.toolchainIdentity:
      reasons.add("toolchain identity mismatch (e)")
    if ctx.currentEpoch.len == 0:
      reasons.add("no current execution epoch in context (e)")
    elif recordedExecutionEpoch != ctx.currentEpoch:
      reasons.add("execution epoch mismatch — stale restored state (e)")
    let recordedVerifierBuildId = safeGetStr(env, "verifierBuildId")
    if ctx.verifierBuildId.len == 0:
      reasons.add("no current verifier build identity in context (e)")
    elif ctx.verifierBuildId == "unmeasured":
      reasons.add("verifier build identity is 'unmeasured' in context (e)")
    elif recordedVerifierBuildId != ctx.verifierBuildId:
      reasons.add("verifier build identity mismatch (e)")
  reasons.sort()
  result.reasons = reasons
  result.established = reasons.len == 0

func appendSortedUniqueAnomaly(anomalies: JsonNode; entry: string): seq[string] {.raises: [].} =
  ## Append one anomaly keeping the reducer's sorted + deduped convention
  ## (order-independent anomaly set).
  var items: seq[string] = @[]
  if not anomalies.isNil and anomalies.kind == JArray:
    for item in anomalies.elems:
      if item.kind == JString: items.add(item.getStr())
  items.add(entry)
  items.sort()
  result = @[]
  for item in items:
    if result.len == 0 or result[^1] != item:
      result.add(item)

func projectRawCompleteness(acc: RunAccounting): RunOutcome {.raises: [].} =
  ## RAW completeness projections (contract §9) — pure functions of the
  ## canonical rows, shared by the two construction sites so the reducer and
  ## the read-path re-hydration cannot drift apart:
  ##   - `reduceRunAccounting` (execution path, at construction),
  ##   - `runAccountingFromJson` (read path, over a restored document).
  result.planComplete = acc.unresolvedDecisionCount == 0
  var requiredNotAttempted = 0
  for u in acc.units:
    if u.requirementDecision == rdRequired and u.executionEvidence == eeNotAttempted:
      inc requiredNotAttempted
  result.executionComplete = requiredNotAttempted == 0
  # Fail-closed — no pending/contested/unsatisfied/unresolved. PENDING is
  # included because a REQUIRED unit that never reached a terminal state is
  # unverified (the contract's stated implication is the asserted minimum).
  result.verificationComplete =
    acc.pendingCount == 0 and acc.contestedCount == 0 and
    acc.unsatisfiedCount == 0 and acc.unresolvedDecisionCount == 0

func demoteRestoredReusedUnits*(
  stateJson: JsonNode;
  reval: RestoredStateRevalidation
): int {.raises: [].} =
  ## Demotion half of the restored-state fail-closed projection: every
  ## REUSED-sourced SATISFIED unit of a state whose identity could NOT be
  ## re-validated against the current context (§15.3) loses its satisfaction →
  ## PENDING + ssNone + anomaly.
  ##
  ## NO VERDICT IS WRITTEN HERE. The run verdict/basis/gateVerdict belong to
  ## verification_decision_authority (INV-X1 inversion, contract §9): this
  ## function returns the demoted count and leaves the demoted accounting for
  ## the authority to re-decide. `summary` is untouched too — it is RAW
  ## telemetry by contract, not a verdict; demoting it here would fabricate
  ## counts the run never produced.
  ##
  ## Genuine fresh-execution units are untouched: only REUSED-sourced units are
  ## cache-derived, so a real fresh execution keeps its SATISFIED row and its
  ## place in FreshExecutionObservedSet.
  ##
  ## The returned count is the deciding observable of the read path: 0 means the
  ## state carried no REUSED satisfaction at all, which is exactly the case a
  ## reused-vs-fresh fixture cannot reach (and the case in which the demotion
  ## says nothing about the verdict).
  result = 0
  if reval.established:
    ## Nothing to fail closed: an established re-validation is the ONE path that
    ## preserves the state exactly as recorded (contract §17.1). Encoding it
    ## here keeps the projection total instead of relying on every caller to
    ## remember the branch.
    return
  if stateJson.isNil or stateJson.kind != JObject: return
  let ra = stateJson{"runAccounting"}
  if ra.isNil or ra.kind != JObject: return
  let units = ra{"units"}
  if not units.isNil and units.kind == JArray:
    for row in units.elems:
      if row.isNil or row.kind != JObject: continue
      if row{"satisfactionSource"}.getStr("") != $ssReused: continue
      if row{"verificationOutcome"}.getStr("") != $voSatisfied: continue
      row["verificationOutcome"] = %($voPending)
      row["satisfactionSource"] = %($ssNone)
      inc result
  if result > 0:
    # Keep the reducer's counting invariants intact:
    # satisfiedCount == satisfiedByFresh + satisfiedByReused, and
    # requiredCount == satisfied + unsatisfied + pending. A REUSED-sourced
    # unit is REQUIRED ∧ SATISFIED by construction (reducer assigns
    # ssReused only to those), so every demotion is one required unit moving
    # from satisfied to pending.
    ra["satisfiedCount"] = %max(0, safeGetInt(ra, "satisfiedCount") - result)
    ra["satisfiedByReused"] = %max(0, safeGetInt(ra, "satisfiedByReused") - result)
    ra["pendingCount"] = %(safeGetInt(ra, "pendingCount") + result)
  ra["anomalies"] = %appendSortedUniqueAnomaly(
    ra{"anomalies"},
    "restored state identity not re-validated — " & reval.reasons.join("; "))

func decisionFromStr(s: string): RequirementDecision {.raises: [].} =
  case s
  of $rdRequired: rdRequired
  of $rdNotRequired: rdNotRequired
  of $rdUnresolved: rdUnresolved
  else: rdUnresolved

func outcomeFromStr(s: string): VerificationOutcome {.raises: [].} =
  case s
  of $voSatisfied: voSatisfied
  of $voUnsatisfied: voUnsatisfied
  of $voPending: voPending
  else: voPending

func consistencyFromStr(s: string): Consistency {.raises: [].} =
  case s
  of $csConsistent: csConsistent
  of $csContested: csContested
  else: csConsistent

func evidenceFromStr(s: string): ExecutionEvidence {.raises: [].} =
  case s
  of $eeAttempted: eeAttempted
  of $eeNotAttempted: eeNotAttempted
  else: eeNotAttempted

func sourceFromStr(s: string): SatisfactionSource {.raises: [].} =
  case s
  of $ssPreSieved: ssPreSieved
  of $ssReused: ssReused
  of $ssFresh: ssFresh
  of $ssNone: ssNone
  else: ssNone

func stringSeq(node: JsonNode; key: string): seq[string] {.raises: [].} =
  result = @[]
  let arr = node{key}
  if arr.isNil or arr.kind != JArray: return
  for item in arr.elems:
    if item.kind == JString: result.add(item.getStr())

func runAccountingFromJson*(node: JsonNode): RunAccounting {.raises: [].} =
  ## Read-path mirror of `toJson`: re-hydrate a persisted `runAccounting` block
  ## into the typed reducer output, so the verdict authority can be handed the
  ## same shape it receives on the execution path (contract §9 — the run verdict
  ## is a function of RunAccounting, never of a document).
  ##
  ## Fail-closed throughout: a missing or malformed field reads as its zero
  ## value, and an unrecognized axis string reads as that axis's bottom value,
  ## so a corrupt document can never assert a stronger state than it carries.
  ##
  ## The RAW completeness projections are RE-DERIVED from the re-hydrated rows
  ## (`projectRawCompleteness`) rather than read back from the document: they
  ## are pure functions of those rows, so trusting the persisted copy would let
  ## a document whose demoted rows disagree with its own stored projections
  ## claim completeness it no longer has.
  if node.isNil or node.kind != JObject: return
  result.requiredCount = safeGetInt(node, "requiredCount")
  result.notRequiredCount = safeGetInt(node, "notRequiredCount")
  result.unresolvedDecisionCount = safeGetInt(node, "unresolvedDecisionCount")
  result.satisfiedCount = safeGetInt(node, "satisfiedCount")
  result.unsatisfiedCount = safeGetInt(node, "unsatisfiedCount")
  result.pendingCount = safeGetInt(node, "pendingCount")
  result.contestedCount = safeGetInt(node, "contestedCount")
  result.satisfiedByFresh = safeGetInt(node, "satisfiedByFresh")
  result.satisfiedByReused = safeGetInt(node, "satisfiedByReused")
  result.preSievedCount = safeGetInt(node, "preSievedCount")
  result.attemptedCount = safeGetInt(node, "attemptedCount")
  result.notAttemptedCount = safeGetInt(node, "notAttemptedCount")
  result.freshExecutionCount = safeGetInt(node, "freshExecutionCount")
  result.executedCount = safeGetInt(node, "executedCount")
  result.proofFailedCount = safeGetInt(node, "proofFailedCount")
  result.timeoutUnsatCount = safeGetInt(node, "timeoutUnsatCount")
  result.reuseEligibleRowCount = safeGetInt(node, "reuseEligibleRowCount")
  result.reuseRejectedRowCount = safeGetInt(node, "reuseRejectedRowCount")
  result.anomalies = stringSeq(node, "anomalies")
  result.derivations = stringSeq(node, "derivations")
  let units = node{"units"}
  if not units.isNil and units.kind == JArray:
    for row in units.elems:
      if row.isNil or row.kind != JObject: continue
      result.units.add(UnitAccounting(
        unitId: safeGetStr(row, "unitId"),
        requirementDecision: decisionFromStr(safeGetStr(row, "requirementDecision")),
        verificationOutcome: outcomeFromStr(safeGetStr(row, "verificationOutcome")),
        consistency: consistencyFromStr(safeGetStr(row, "consistency")),
        executionEvidence: evidenceFromStr(safeGetStr(row, "executionEvidence")),
        satisfactionSource: sourceFromStr(safeGetStr(row, "satisfactionSource"))
      ))
  result.runOutcome = projectRawCompleteness(result)

# ---------------------------------------------------------------------------
# Reducer
# ---------------------------------------------------------------------------

func reduceRunAccounting*(
  waves: seq[JsonNode];
  eligibility: JsonNode;
  reuseContext: ReuseVerificationContext
): RunAccounting {.raises: [].} =
  ## Component-wise, per-unit-keyed merge across waves. All joins are
  ## associative · commutative · idempotent ⇒ wave ordering cannot affect the
  ## result (permutation-invariant, byte-identical JSON).
  var derivations: seq[string] = @[]

  # Collect the unit universe: eligibility keys ∪ per-wave nodeReport nodeIds.
  var unitSet: Table[string, bool] = initTable[string, bool]()
  if not eligibility.isNil and eligibility.kind == JObject:
    for key in eligibility.keys:
      unitSet[key] = true
  for wave in waves:
    for nr in waveNodeReports(wave):
      let uid = safeGetStr(nr, "nodeId")
      if uid.len > 0:
        unitSet[uid] = true

  var unitIds: seq[string] = @[]
  for uid in unitSet.keys: unitIds.add(uid)
  unitIds.sort()

  # Per-unit merged state.
  var decision: Table[string, RequirementDecision] = initTable[string, RequirementDecision]()
  var outcome: Table[string, VerificationOutcome] = initTable[string, VerificationOutcome]()
  var consistency: Table[string, Consistency] = initTable[string, Consistency]()
  var evidence: Table[string, ExecutionEvidence] = initTable[string, ExecutionEvidence]()
  var source: Table[string, SatisfactionSource] = initTable[string, SatisfactionSource]()
  var hasRuntimeVerdict: Table[string, bool] = initTable[string, bool]()
  var invocationWitness: Table[string, bool] = initTable[string, bool]()
  var decisionConflicts: Table[string, bool] = initTable[string, bool]()
  var runtimeNoObligation: Table[string, bool] = initTable[string, bool]()
  # Plan 1 — REUSED basis per-row re-verification state.
  var reuseAnyEligible: Table[string, bool] = initTable[string, bool]()
  var reuseAnyRejected: Table[string, bool] = initTable[string, bool]()
  var reuseRejectionReasons: Table[string, HashSet[string]] = initTable[string, HashSet[string]]()
  var hasFailedRow: Table[string, bool] = initTable[string, bool]()
  var hasTimeoutRow: Table[string, bool] = initTable[string, bool]()
  var reuseEligibleRows = 0
  var reuseRejectedRows = 0

  for uid in unitIds:
    decision[uid] = deriveDecision(eligibility, uid)
    outcome[uid] = voPending
    consistency[uid] = csConsistent
    evidence[uid] = eeNotAttempted
    source[uid] = ssNone

  # Merge each wave's nodeReports into the per-unit state.
  for wave in waves:
    for nr in waveNodeReports(wave):
      let uid = safeGetStr(nr, "nodeId")
      if uid.len == 0 or not unitSet.hasKey(uid): continue
      let status = safeGetStr(nr, "status")
      let cacheHit = safeGetBool(nr, "cacheHit")

      # RequirementDecision: run-wide, assert-equal (all waves must agree).
      let waveDecision = deriveDecision(eligibility, uid)
      let mergedDecision = joinDecision(decision.getOrDefault(uid, rdUnresolved), waveDecision)
      if mergedDecision != decision.getOrDefault(uid, rdUnresolved):
        decisionConflicts[uid] = true
      decision[uid] = mergedDecision

      # VerificationOutcome: worse-wins semilattice. Plan 1 (Authority
      # Unification): a cacheHit row is a REUSED satisfaction ONLY when the
      # reuse record passes the 5-condition re-verification against the
      # current context; otherwise the row is fail-closed PENDING (basis not
      # established — the pair (status, cacheHit=true) alone never produces a
      # satisfaction). A genuine (cacheHit=false) failed/timeout still joins
      # UNSATISFIED (worse wins over the cache row's SATISFIED when the same
      # unit has both).
      let rowOutcome = if cacheHit: voPending else: statusToOutcome(status)
      if cacheHit:
        let reuseVerdict = verifyReuseRecord(nr, reuseContext)
        if reuseVerdict.ok:
          reuseAnyEligible[uid] = true
          inc reuseEligibleRows
        else:
          reuseAnyRejected[uid] = true
          inc reuseRejectedRows
          for reason in reuseVerdict.reasons:
            reuseRejectionReasons.mgetOrPut(uid, initHashSet[string]()).incl(reason)
      else:
        if status == "failed": hasFailedRow[uid] = true
        elif status == "timeout": hasTimeoutRow[uid] = true
      outcome[uid] = joinOutcome(outcome.getOrDefault(uid, voPending), rowOutcome)

      # ExecutionEvidence: ATTEMPTED only for a fresh-invocation verdict row.
      # Cache-hit rows carry no fresh execution (REUSED — X2 attribution).
      if not cacheHit:
        evidence[uid] = joinEvidence(evidence.getOrDefault(uid, eeNotAttempted), eeAttempted)

      # Runtime verdict record → consistency axis is defined (default CONSISTENT).
      # Cache-hit rows ARE verdict records (the unit reached a terminal
      # disposition via reuse) — they count toward executedCount even though
      # their ExecutionEvidence is NOT_ATTEMPTED.
      hasRuntimeVerdict[uid] = true

      # Invocation witness (FreshExecutionObservedSet membership).
      if statusWitnessesInvocation(status, cacheHit):
        invocationWitness[uid] = true

      # CONTESTED detection: runtime no_obligation report on the unit.
      if status == "no_obligation":
        runtimeNoObligation[uid] = true

  # Consistency: CONTESTED iff canonical OGR REQUIRED ∧ runtime no_obligation
  # report (the deterministic mapping — fail-closed, never satisfying).
  for uid in unitIds:
    if decision.getOrDefault(uid, rdUnresolved) == rdRequired and runtimeNoObligation.getOrDefault(uid, false):
      consistency[uid] = csContested

  # Plan 1 — unit-level REUSED basis: a unit with cache-hit row(s) is
  # REUSED-satisfied only when ALL its cache-hit rows passed the 5-condition
  # re-verification; any rejected row → the basis is NOT established and the
  # unit stays fail-closed PENDING (VDA must not decide PASS on it).
  for uid in unitIds:
    if reuseAnyEligible.getOrDefault(uid, false) or reuseAnyRejected.getOrDefault(uid, false):
      if reuseAnyEligible.getOrDefault(uid, false) and not reuseAnyRejected.getOrDefault(uid, false):
        outcome[uid] = joinOutcome(outcome.getOrDefault(uid, voPending), voSatisfied)
      else:
        outcome[uid] = joinOutcome(outcome.getOrDefault(uid, voPending), voPending)

  # SatisfactionSource: SATISFIED → FRESH/REUSED by execution witness;
  # NOT_REQUIRED (no obligation) → PRE_SIEVED; else NONE.
  for uid in unitIds:
    if decision.getOrDefault(uid, rdUnresolved) == rdRequired and outcome.getOrDefault(uid, voPending) == voSatisfied:
      source[uid] = if invocationWitness.getOrDefault(uid, false): ssFresh else: ssReused
    elif decision.getOrDefault(uid, rdUnresolved) == rdNotRequired:
      source[uid] = ssPreSieved

  # Assemble per-unit rows (sorted by unitId → deterministic).
  var units: seq[UnitAccounting] = @[]
  for uid in unitIds:
    units.add(UnitAccounting(
      unitId: uid,
      requirementDecision: decision.getOrDefault(uid, rdUnresolved),
      verificationOutcome: outcome.getOrDefault(uid, voPending),
      consistency: consistency.getOrDefault(uid, csConsistent),
      executionEvidence: evidence.getOrDefault(uid, eeNotAttempted),
      satisfactionSource: source.getOrDefault(uid, ssNone)
    ))

  # Canonical counts.
  # VerificationOutcome totals are over REQUIRED units only ("defined only for
  # REQUIRED units" — the row value for non-REQUIRED units is telemetry-only).
  result.units = units
  for u in units:
    case u.requirementDecision
    of rdRequired: inc result.requiredCount
    of rdNotRequired: inc result.notRequiredCount
    of rdUnresolved: inc result.unresolvedDecisionCount
    if u.requirementDecision == rdRequired:
      case u.verificationOutcome
      of voSatisfied: inc result.satisfiedCount
      of voUnsatisfied: inc result.unsatisfiedCount
      of voPending: inc result.pendingCount
    if u.consistency == csContested: inc result.contestedCount
    case u.satisfactionSource
    of ssFresh: inc result.satisfiedByFresh
    of ssReused: inc result.satisfiedByReused
    of ssPreSieved: inc result.preSievedCount
    of ssNone: discard
    case u.executionEvidence
    of eeAttempted: inc result.attemptedCount
    of eeNotAttempted: inc result.notAttemptedCount
    if invocationWitness.getOrDefault(u.unitId, false): inc result.freshExecutionCount
    if hasRuntimeVerdict.getOrDefault(u.unitId, false): inc result.executedCount

  # Plan 1 — raw FAIL/INCONCLUSIVE split over REQUIRED units: the
  # timeout→UNSATISFIED aggregation stays the raw fact (never rewritten);
  # the split preserves whether the UNSATISFIED rows were proof-level
  # failures (status=failed) or timeout-only — VDA interprets it.
  for uid in unitIds:
    if decision.getOrDefault(uid, rdUnresolved) != rdRequired: continue
    if hasFailedRow.getOrDefault(uid, false): inc result.proofFailedCount
    elif hasTimeoutRow.getOrDefault(uid, false): inc result.timeoutUnsatCount
  result.reuseEligibleRowCount = reuseEligibleRows
  result.reuseRejectedRowCount = reuseRejectedRows

  # Decision conflicts → anomalies (deduped + sorted → order-independent).
  for uid in unitIds:
    if decisionConflicts.getOrDefault(uid, false):
      result.anomalies.add("RequirementDecision conflict for unit " & uid &
        " (waves disagree) — resolved to UNRESOLVED")

  # Plan 1 — REUSED basis rejections: every unit with a rejected cache-hit
  # row gets one anomaly carrying the union of failure reasons (order-
  # independent: reasons sorted, one anomaly per unit).
  for uid in unitIds:
    if reuseAnyRejected.getOrDefault(uid, false):
      var reasons = reuseRejectionReasons.getOrDefault(uid, initHashSet[string]()).toSeq()
      reasons.sort()
      result.anomalies.add("REUSED basis not established for unit " & uid &
        " (" & reasons.join("; ") & ")")

  # Invariant checks (fail-closed; violations surface as anomalies).
  if result.requiredCount != result.satisfiedCount + result.unsatisfiedCount + result.pendingCount:
    result.anomalies.add("invariant violation: VerificationOutcome total != requiredCount")
  if result.satisfiedCount != result.satisfiedByFresh + result.satisfiedByReused:
    result.anomalies.add("invariant violation: satisfiedCount != satisfiedByFresh + satisfiedByReused")
  if result.attemptedCount + result.notAttemptedCount != units.len:
    result.anomalies.add("invariant violation: ExecutionEvidence total != unit count")
  if result.freshExecutionCount > result.attemptedCount:
    result.anomalies.add("invariant violation: freshExecutionCount > attemptedCount")
  if result.contestedCount > result.requiredCount:
    result.anomalies.add("invariant violation: contestedCount > requiredCount")
  if result.unsatisfiedCount != result.proofFailedCount + result.timeoutUnsatCount:
    result.anomalies.add("invariant violation: unsatisfiedCount != proofFailedCount + timeoutUnsatCount")
  if result.satisfiedByReused > result.reuseEligibleRowCount:
    result.anomalies.add("invariant violation: satisfiedByReused > reuseEligibleRowCount")

  result.anomalies.sort()
  # Dedupe consecutive duplicates after sort.
  var uniqueAnomalies: seq[string] = @[]
  for a in result.anomalies:
    if uniqueAnomalies.len == 0 or uniqueAnomalies[^1] != a:
      uniqueAnomalies.add(a)
  result.anomalies = uniqueAnomalies

  # runOutcome — RAW completeness projections only (INV-X1 inversion: the
  # verdict/basis fields are decided EXCLUSIVELY by
  # verification_decision_authority.evaluateRunOutcome — run_accounting
  # preserves raw state and never derives a gate verdict). The formula is the
  # shared `projectRawCompleteness` (contract §9) — the same one the read-path
  # re-hydration applies over a restored document, so the two construction
  # sites cannot drift apart.
  result.runOutcome = projectRawCompleteness(result)

  # Derivations (documented in the artifact under "derivations").
  derivations.add("RequirementDecision is derived from the eligibility/OGR basis only " &
    "(canonical OGR authority — backends do not decide obligation existence); " &
    "units without a basis are UNRESOLVED, never NOT_REQUIRED")
  derivations.add("VerificationOutcome is defined only for REQUIRED units; " &
    "runtime statuses verified/inductive_valid → SATISFIED, failed/timeout → UNSATISFIED, " &
    "no_obligation/not_verifiable/pre_sieved/blocked/skipped/vacuous/absent → PENDING; " &
    "cacheHit=true rows are SATISFIED (REUSED) only when the replay record passes the " &
    "5-condition re-verification (subject fingerprint, execution-bundle fingerprint, " &
    "execution-config digest, artifact content digest, toolchain identity) against the " &
    "current context — otherwise fail-closed PENDING (Plan 1, REUSED basis)")
  derivations.add("Consistency: CONTESTED iff canonical OGR REQUIRED ∧ runtime no_obligation " &
    "report (deterministic mapping); other runtime verdicts default to CONSISTENT")
  derivations.add("ExecutionEvidence ATTEMPTED iff the unit has a per-wave fresh-invocation " &
    "verdict record; cache-hit rows carry no fresh invocation → NOT_ATTEMPTED (DEBT#459); " &
    "units never processed by the runtime are NOT_ATTEMPTED")
  derivations.add("SatisfactionSource: SATISFIED + invocation witness → FRESH; " &
    "SATISFIED + verified reuse (5-condition basis) → REUSED; NOT_REQUIRED (no obligation) → " &
    "PRE_SIEVED; else NONE")
  derivations.add("proofFailedCount = distinct REQUIRED units merged UNSATISFIED with a " &
    "genuine proof-attempt failure (status=failed); timeoutUnsatCount = distinct REQUIRED " &
    "units merged UNSATISFIED with only timeout rows — the timeout→UNSATISFIED aggregation " &
    "is preserved as the raw fact; the split lets VDA separate FAIL (proof-level) from " &
    "INCONCLUSIVE (timeout) without rewriting timeout semantics")
  derivations.add("freshExecutionCount = |FreshExecutionObservedSet| = distinct units with " &
    "evidenceSource=terminal_verdict_proxy (a runtime verdict proxying a genuine solver/proof " &
    "invocation; cache hits excluded). Evidence hierarchy: dispatch-only < terminal-verdict-proxy " &
    "< solver-observed < invocation-witness; invocation-witness emission is an X2 entry condition. " &
    "It is NOT obligationAttemptedCount (obligation-WEIGHTED — loop_driver.nim:934 adds the node's " &
    "whole obligationCount — and never incremented on the parallel path) — DEBT#458")
  derivations.add("executedCount = units with a runtime verdict record; cache-hit rows are " &
    "verdict records with NOT_ATTEMPTED evidence, so executedCount = attemptedCount + " &
    "cache-hit-reused rows (DEBT#459)")
  derivations.add("RunVerdict/basis (INV-X1 inversion): run_accounting preserves raw state — " &
    "planComplete/executionComplete/verificationComplete are RAW projections; the run-level " &
    "verdict/basis are decided EXCLUSIVELY by verification_decision_authority.evaluateRunOutcome.")
  result.derivations = derivations

func reduceRunAccounting*(
  waves: seq[JsonNode];
  eligibility: JsonNode
): RunAccounting {.raises: [].} =
  ## 2-arg convenience form — fail-closed default reuse context: cache-hit
  ## rows without a verifiable reuse record classify PENDING, never SATISFIED.
  reduceRunAccounting(waves, eligibility, defaultReuseVerificationContext())

{.pop.}

# ---------------------------------------------------------------------------
# JSON serialization (deterministic)
# ---------------------------------------------------------------------------

func toJson*(ra: RunAccounting): JsonNode {.raises: [].} =
  var unitRows = newJArray()
  for u in ra.units:
    var row = newJObject()
    row["unitId"] = %u.unitId
    row["requirementDecision"] = %($u.requirementDecision)
    row["verificationOutcome"] = %($u.verificationOutcome)
    row["consistency"] = %($u.consistency)
    row["executionEvidence"] = %($u.executionEvidence)
    row["satisfactionSource"] = %($u.satisfactionSource)
    unitRows.add(row)
  var anomalies = newJArray()
  for a in ra.anomalies: anomalies.add(%a)
  var derivs = newJArray()
  for d in ra.derivations: derivs.add(%d)
  result = %*{
    "requiredCount": ra.requiredCount,
    "notRequiredCount": ra.notRequiredCount,
    "unresolvedDecisionCount": ra.unresolvedDecisionCount,
    "satisfiedCount": ra.satisfiedCount,
    "unsatisfiedCount": ra.unsatisfiedCount,
    "pendingCount": ra.pendingCount,
    "contestedCount": ra.contestedCount,
    "satisfiedByFresh": ra.satisfiedByFresh,
    "satisfiedByReused": ra.satisfiedByReused,
    "preSievedCount": ra.preSievedCount,
    "attemptedCount": ra.attemptedCount,
    "notAttemptedCount": ra.notAttemptedCount,
    "freshExecutionCount": ra.freshExecutionCount,
    "executedCount": ra.executedCount,
    "proofFailedCount": ra.proofFailedCount,
    "timeoutUnsatCount": ra.timeoutUnsatCount,
    "reuseEligibleRowCount": ra.reuseEligibleRowCount,
    "reuseRejectedRowCount": ra.reuseRejectedRowCount,
    "runOutcome": %*{
      "planComplete": ra.runOutcome.planComplete,
      "executionComplete": ra.runOutcome.executionComplete,
      "verificationComplete": ra.runOutcome.verificationComplete
    },
    "units": unitRows,
    "anomalies": anomalies,
    "derivations": derivs
  }

# ---------------------------------------------------------------------------
# X1 canonical boundary — CanonicalRunResult (DEBT#458 closed)
#
# CanonicalRunResult is the authoritative execution source:
#   RunAccounting      — 3-axis + evidence per-unit rows + canonical fields
#                        (X1.0 contract, unchanged)
#   ExecutionEvidence  — per-wave dispatched sets + per-unit ATTEMPTED(observed);
#                        timings are ExecutionMetrics (doc-level separation only)
#   RunOutcome         — deriveRunOutcome() RAW completeness projection; the
#                        run-level verdict/basis are decided EXCLUSIVELY by
#                        VerificationDecisionAuthority (INV-X1 inversion)
#
# INV-X1 (inverted, Plan 1): RunOutcome's raw completeness projections are
# derivable exclusively from canonical inputs, computed at construction once;
# the verdict/basis fields are never independently mutated — the ONLY code
# path that sets them is verification_decision_authority.evaluateRunOutcome
# (the sole run-verdict authority). Every projection reads the
# construction-time raw state + the VDA-decided verdict.
# ---------------------------------------------------------------------------

type
  RunExecutionEvidence* = object
    ## Per-wave dispatched sets + per-unit ATTEMPTED(observed) evidence.
    ## Timings and cumulative run-wide scalars are ExecutionMetrics /
    ## doc-level run metadata (doc-level separation only) — excluded from the
    ## canonical digest.
    dispatchedPerWave*: seq[seq[string]]  ## per-wave dispatched unit sets (sorted per wave)
    attemptedUnits*: seq[string]          ## sorted union of units with ATTEMPTED(observed) evidence
    observedRows*: seq[JsonNode]          ## merged per-wave nodeReports rows (keyed union by unitId, sorted by unitId)
    waveExecutionStats*: seq[JsonNode]    ## per-wave executionStats (additive counts + nodeStats/depthStats concat)
    mergedExecutionStats*: JsonNode       ## merged executionStats — wall/hotspot (ExecutionMetrics, doc-level)
    runScalars*: JsonNode                 ## run-wide cumulative summary scalars (doc-level)
    runtimeMeta*: JsonNode                ## run-wide timing metadata (doc-level)
    gates*: JsonNode                      ## gate events (doc-level)
    refactorSummary*: JsonNode            ## refactor summary (doc-level)
    refactorEvidence*: JsonNode           ## refactor evidence (doc-level)
    blockedNodes*: seq[string]            ## union across waves (sorted)
    staleDependencyNodes*: seq[string]    ## union across waves (sorted)
    reproofNodes*: seq[string]            ## union across waves (sorted)
    timeoutNodes*: seq[string]            ## union across waves (sorted)
    timeoutImpactNodes*: seq[string]      ## union across waves (sorted)

  RunPlanInput* = object
    ## Canonical OGR planning input: the REQUIRED unit set (sorted).
    requiredUnitIds*: seq[string]

  CanonicalRunResult* = object
    runAccounting*: RunAccounting
    executionEvidence*: RunExecutionEvidence
    runOutcome*: RunOutcome  ## RAW completeness projection at construction; verdict/basis set by VDA ONLY (INV-X1)
    executionIdentity*: ReuseVerificationContext ## identity this run was EXECUTED under; persisted with the
      ## document and re-verified against the CURRENT context on every read
      ## (revalidateRestoredStateIdentity). It is deliberately NOT part of
      ## canonicalSerialize: that digest attests the ACCOUNTING result, while
      ## this envelope attests the context the accounting was produced in —
      ## keeping them separate leaves the digest stable and the staleness check
      ## a read-time concern.

# ---------------------------------------------------------------------------
# ExecutionEvidence collection (pure)
# ---------------------------------------------------------------------------

func collectUnion(waves: seq[JsonNode]; key: string): seq[string] {.raises: [].} =
  ## Union of a per-wave string-array report key, sorted (order-independent).
  var seen: Table[string, bool] = initTable[string, bool]()
  result = @[]
  for w in waves:
    let arr = w{key}
    if arr.isNil or arr.kind != JArray: continue
    for item in arr.elems:
      if item.kind != JString: continue
      let s = item.getStr()
      if s.len > 0 and not seen.hasKey(s):
        seen[s] = true
        result.add(s)
  result.sort()

func collectObservedRows(waves: seq[JsonNode]): seq[JsonNode] {.raises: [].} =
  ## Keyed union of per-wave nodeReports rows by nodeId (first occurrence),
  ## sorted by nodeId — deterministic and order-independent.
  var seen: Table[string, bool] = initTable[string, bool]()
  var rows: seq[(string, JsonNode)] = @[]
  for w in waves:
    let nr = w{"nodeReports"}
    if nr.isNil or nr.kind != JArray: continue
    for n in nr.elems:
      if n.isNil or n.kind != JObject: continue
      let uid = safeGetStr(n, "nodeId")
      if uid.len == 0 or seen.hasKey(uid): continue
      seen[uid] = true
      rows.add((uid, n))
  rows.sort(proc(a, b: (string, JsonNode)): int = cmp(a[0], b[0]))
  result = @[]
  for (_, r) in rows: result.add(r)

func lastKey(waves: seq[JsonNode]; key: string): JsonNode {.raises: [].} =
  ## Last wave's value for a doc-level report key (run-wide cumulative state).
  result = nil
  for w in waves:
    let v = w{key}
    if not v.isNil: result = v

func deriveRunOutcome*(
  planInput: RunPlanInput;
  runAccounting: RunAccounting;
  executionEvidence: RunExecutionEvidence
): RunOutcome {.raises: [].} =
  ## RAW completeness projection — INV-X1 inversion (docs/spec/execution_accounting_contract.md §9):
  ## the three completeness booleans are pure projections of canonical inputs,
  ## computed at construction only; the verdict/basis fields are NOT decided
  ## here — they remain at their undecided defaults until
  ## verification_decision_authority.evaluateRunOutcome decides them (the sole
  ## run-verdict authority). The formulas are the contract's stated ones
  ## (identical to the reducer's construction);
  ## planInput and executionEvidence are consistency guards:
  ##   - planInput: the canonical OGR REQUIRED set must match the reducer's
  ##     requiredCount, else planComplete fails closed;
  ##   - executionEvidence: every DISPATCHED unit must have an observed
  ##     (ATTEMPTED) runtime verdict row — a dispatched unit without a verdict
  ##     never reached the runtime (fail-closed execution evidence).
  result.planComplete =
    runAccounting.unresolvedDecisionCount == 0 and
    planInput.requiredUnitIds.len == runAccounting.requiredCount
  var requiredNotAttempted = 0
  for u in runAccounting.units:
    if u.requirementDecision == rdRequired and u.executionEvidence == eeNotAttempted:
      inc requiredNotAttempted
  result.executionComplete = requiredNotAttempted == 0
  # Evidence guard: dispatched ⊆ observed-attempted (ATTEMPTED rows carry
  # fresh-invocation verdicts). A dispatched unit without an ATTEMPTED row
  # never reached a fresh runtime invocation — either it was never processed
  # at all (no verdict row) or it was resolved only by cache reuse
  # (cache-hit row, NOT_ATTEMPTED — DEBT#459) — both fail executionComplete.
  var observed = initTable[string, bool]()
  for uid in executionEvidence.attemptedUnits:
    observed[uid] = true
  for waveSet in executionEvidence.dispatchedPerWave:
    for uid in waveSet:
      if uid.len > 0 and not observed.hasKey(uid):
        result.executionComplete = false
  result.verificationComplete =
    runAccounting.pendingCount == 0 and runAccounting.contestedCount == 0 and
    runAccounting.unsatisfiedCount == 0 and runAccounting.unresolvedDecisionCount == 0

func buildCanonicalRunResult*(
  waves: seq[JsonNode];
  eligibility: JsonNode;
  dispatchedPerWave: seq[seq[string]];
  reuseContext: ReuseVerificationContext
): CanonicalRunResult {.raises: [].} =
  ## CanonicalRunResult construction — the authoritative execution source.
  ## RunAccounting via the X1.0 reducer (byte-identical join algebra) with
  ## per-row REUSED re-verification (Plan 1); ExecutionEvidence from the
  ## per-wave dispatched sets + observed rows; RunOutcome's raw completeness
  ## projections derived at construction only (INV-X1 inversion — the
  ## verdict/basis are decided by VDA only).
  result.runAccounting = reduceRunAccounting(waves, eligibility, reuseContext)
  result.executionIdentity = reuseContext
  var ev: RunExecutionEvidence
  ev.dispatchedPerWave = dispatchedPerWave
  ev.observedRows = collectObservedRows(waves)
  ev.attemptedUnits = @[]
  for row in ev.observedRows:
    let uid = safeGetStr(row, "nodeId")
    # DEBT#459: cache-hit rows carry NOT_ATTEMPTED evidence (no fresh
    # invocation) — excluded from attemptedUnits so the ExecutionEvidence
    # layer agrees with attemptedCount. A dispatched cache-hit unit is then
    # not "observed as attempted", which drives executionComplete=false for
    # warm (reuse-only) runs — fail-closed fresh-execution evidence.
    if uid.len > 0 and not safeGetBool(row, "cacheHit"):
      ev.attemptedUnits.add(uid)
  # observedRows are sorted by nodeId ⇒ attemptedUnits is sorted.
  ev.blockedNodes = collectUnion(waves, "blockedNodes")
  ev.staleDependencyNodes = collectUnion(waves, "staleDependencyNodes")
  ev.reproofNodes = collectUnion(waves, "reproofNodes")
  ev.timeoutNodes = collectUnion(waves, "timeoutNodes")
  ev.timeoutImpactNodes = collectUnion(waves, "timeoutImpactNodes")
  for w in waves:
    let es = w{"executionStats"}
    if not es.isNil and es.kind == JObject:
      ev.waveExecutionStats.add(es)
      ev.mergedExecutionStats = es  # last wave wins (run-wide cumulative; ExecutionMetrics)
    let s = w{"summary"}
    if not s.isNil and s.kind == JObject:
      ev.runScalars = s  # last wave's cumulative full-function metrics (run-wide)
  ev.runtimeMeta = lastKey(waves, "runtimeMeta")
  ev.gates = lastKey(waves, "gates")
  ev.refactorSummary = lastKey(waves, "refactorSummary")
  ev.refactorEvidence = lastKey(waves, "refactorEvidence")
  result.executionEvidence = ev
  # planInput: the canonical OGR REQUIRED set (elProofCandidate/ogrGenerated).
  var requiredIds: seq[string] = @[]
  if not eligibility.isNil and eligibility.kind == JObject:
    for key, val in eligibility.fields:
      let cls = if val.kind == JString: val.getStr() else: ""
      if cls == "elProofCandidate" or cls == "ogrGenerated":
        requiredIds.add(key)
  requiredIds.sort()
  result.runOutcome = deriveRunOutcome(
    RunPlanInput(requiredUnitIds: requiredIds), result.runAccounting, result.executionEvidence)

func buildCanonicalRunResult*(
  waves: seq[JsonNode];
  eligibility: JsonNode;
  dispatchedPerWave: seq[seq[string]]
): CanonicalRunResult {.raises: [].} =
  ## 3-arg convenience form — fail-closed default reuse context (unverifiable
  ## reuse rows classify PENDING, never SATISFIED).
  buildCanonicalRunResult(waves, eligibility, dispatchedPerWave, defaultReuseVerificationContext())

func gateVerdictProjection*(runOutcome: RunOutcome): GateVerdict {.raises: [].} =
  ## GateVerdict is a serialization projection of the VDA-decided run verdict:
  ## PASS iff verdict == vrPass; every other verdict (FAIL/BLOCKED/
  ## INCONCLUSIVE/undecided) projects to FAIL (fail-closed).
  if runOutcome.verdict == vrPass: gvPass else: gvFail

func runOutcomeToJson*(runOutcome: RunOutcome): JsonNode {.raises: [].} =
  ## Fixed-key serialization (Plan 1 key schema): the RAW completeness
  ## projections + the VDA-decided verdict/basis + the gateVerdict projection
  ## + the REUSED condition fields (present whenever basis == REUSED).
  var reuseConditions = newJArray()
  if runOutcome.basis == rbReused:
    for c in runOutcome.reusedConditionsMet: reuseConditions.add(%c)
  %*{
    "planComplete": runOutcome.planComplete,
    "executionComplete": runOutcome.executionComplete,
    "verificationComplete": runOutcome.verificationComplete,
    "verdict": $runOutcome.verdict,
    "basis": $runOutcome.basis,
    "gateVerdict": $gateVerdictProjection(runOutcome),
    "reuseConditions": reuseConditions
  }

func canonicalSerialize*(runResult: CanonicalRunResult): string {.raises: [].} =
  ## Code-level contract function (docs/spec/execution_accounting_contract.md):
  ## deterministic serialization of the FULL RunResult, JCS RFC 8785 spirit —
  ## unit rows sorted by unitId (the reducer already sorts), per-wave
  ## dispatched sets sorted and the set list sorted lexicographically, fixed
  ## key order, no timestamps / run-dependent fields. Report key ordering,
  ## timestamps and CLI metadata cannot affect it. Doc-level presentation
  ## fields (observedRows, executionStats, runScalars, runtimeMeta, gates,
  ## refactor records) are excluded from the canonical digest.
  var dispatched: seq[string] = @[]
  for wave in runResult.executionEvidence.dispatchedPerWave:
    var s = wave
    s.sort()
    dispatched.add(s.join("|"))
  dispatched.sort()
  var attempted = runResult.executionEvidence.attemptedUnits
  attempted.sort()
  var ev = newJObject()
  ev["dispatchedPerWave"] = %dispatched
  ev["attemptedUnits"] = %attempted
  var root = newJObject()
  root["runAccounting"] = runResult.runAccounting.toJson()
  root["executionEvidence"] = ev
  root["runOutcome"] = runOutcomeToJson(runResult.runOutcome)
  result = root.pretty()

func canonicalRunDigest*(runResult: CanonicalRunResult): string {.raises: [].} =
  ## Whole-tree canonical hash of the RUN RESULT (not the report document):
  ## sha256Hex(canonicalSerialize(runResult)).
  sha256Hex(canonicalSerialize(runResult))

func statusStringToNodeStatus(status: string): OrchestrationNodeStatus {.raises: [].} =
  ## Terminal-verdict decode of the legacy report status strings.
  case status
  of "verified": orchestrationVerified
  of "inductive_valid": orchestrationInductiveValid
  of "failed": orchestrationProofFailed
  of "timeout": orchestrationTimedOut
  of "blocked": orchestrationBlocked
  of "vacuous_contradiction": orchestrationVacuousContradiction
  of "pre_sieved": orchestrationPreSievedUnverifiable
  of "skipped_by_theory": orchestrationSkippedByTheory
  of "not_verifiable": orchestrationNotVerifiable
  of "no_obligation": orchestrationNoObligation
  else: orchestrationBlocked  # unknown → blocked (fail-closed, never verified)

func UniverseIntegrityProjection*(runResult: CanonicalRunResult): seq[OrchestrationNodeReport] {.raises: [].} =
  ## TrustCommit projection from the MERGED rows (nodeId/status/assuranceTier).
  ## TrustCommit now reads the canonical projection instead of the last-wave
  ## report — wave-1 verified units reach the TrustCommit (natural consequence
  ## of the canonical boundary migration, NOT a separate algorithm fix).
  result = @[]
  for row in runResult.executionEvidence.observedRows:
    let uid = safeGetStr(row, "nodeId")
    if uid.len == 0: continue
    result.add(OrchestrationNodeReport(
      nodeId: sorterNodeId(uid),
      status: statusStringToNodeStatus(safeGetStr(row, "status")),
      cacheHit: safeGetBool(row, "cacheHit"),
      assuranceTier: safeGetStr(row, "assuranceTier")
    ))

func summaryProjection(runResult: CanonicalRunResult; preRun: JsonNode): JsonNode {.raises: [].} =
  ## summary ← merged rows (per-unit-aggregatable counts) + run-wide scalars.
  ## Every field is per-unit-aggregatable or run-wide — no last-wave-specific
  ## field is a data source (ownership matrix in the contract doc).
  result = newJObject()
  # PreRunContext skeleton fields (pre-loop topology data).
  if not preRun.isNil:
    let s = preRun{"summary"}
    if not s.isNil and s.kind == JObject:
      for key in ["topologyScanComplete", "symbolCount", "plannedNodeCount",
                  "queuePreviewCount", "effectiveQueueLimit", "effectiveDiagnosisDepth",
                  "structuralBottleneckCount", "repairPriorityCount", "bodyLoadCount",
                  "symbolFirstPass", "totalSourceFunctions"]:
        let v = s{key}
        if not v.isNil: result[key] = v
  # Per-unit counts from the merged rows.
  var rawVerified, inductiveValid, vacuous, failed, timeout, blocked, preSieved, classified = 0
  var reused = 0  ## DEBT#459: cache-hit rows are REUSED satisfactions, not failures
  var tierCounts = initTable[string, int]()
  var statusCounts = initTable[string, int]()
  for row in runResult.executionEvidence.observedRows:
    let status = safeGetStr(row, "status")
    let rowCacheHit = safeGetBool(row, "cacheHit")
    if rowCacheHit:
      # RAW telemetry (Plan 1, §15.2): cache-hit rows count under reusedCount
      # regardless of reuse-record eligibility — the summary does not depend
      # on the reuse record and is NOT a verdict (the REUSED satisfaction is
      # decided separately by the 5-condition re-verification + VDA).
      inc reused
    else:
      case status
      of "verified": inc rawVerified
      of "inductive_valid": inc inductiveValid
      of "vacuous_contradiction": inc vacuous
      of "failed": inc failed
      of "timeout": inc timeout
      of "blocked": inc blocked
      of "pre_sieved", "not_verifiable", "no_obligation": inc preSieved
      else: discard
    let tier = safeGetStr(row, "assuranceTier")
    if tier.len > 0:
      inc classified
      tierCounts[tier] = tierCounts.getOrDefault(tier) + 1
    let statusKey = if rowCacheHit: "reused"
                    elif status == "skipped_by_theory": "skipped"
                    elif status == "vacuous_contradiction": "vacuous"
                    elif status == "pre_sieved" or status == "not_verifiable" or
                         status == "no_obligation": "pre_sieved"
                    else: status
    statusCounts[statusKey] = statusCounts.getOrDefault(statusKey) + 1
  let verifiedCount = int(computeVerified(rawVerified, inductiveValid, vacuous))
  result["failedCount"] = %failed
  result["reusedCount"] = %reused
  result["vacuousCount"] = %vacuous
  result["timeoutCount"] = %timeout
  result["blockedCount"] = %blocked
  result["preSieved"] = %preSieved
  result["classifiedNodes"] = %classified
  # Additive counts (summed across waves — per-unit-aggregatable).
  var solverInvocationCount, cacheHitCount, execTimeoutCount = 0
  for es in runResult.executionEvidence.waveExecutionStats:
    solverInvocationCount += safeGetInt(es, "solverInvocationCount")
    cacheHitCount += safeGetInt(es, "cacheHitCount")
    execTimeoutCount += safeGetInt(es, "timeoutCount")
  result["solverInvocationCount"] = %solverInvocationCount
  result["cacheHitCount"] = %cacheHitCount
  # stale/reproof counts: per-unit-aggregatable (union across waves).
  result["staleCount"] = %runResult.executionEvidence.staleDependencyNodes.len
  result["reproofCount"] = %runResult.executionEvidence.reproofNodes.len
  # verificationSuccessRate — from the merged counts.
  let denom = verifiedCount + failed + vacuous + timeout + blocked
  result["verificationSuccessRate"] = if denom > 0:
      %(initAsiRatio(verifiedCount.float / float(denom)).get(defaultAsiRatio()).toFloat)
    else: %0.0
  var tc = newJObject()
  for k in ["z3-verified", "dual-verified", "lean-verified", "none", "k-induction", "uf-abstract", "unknown"]:
    tc[k] = %tierCounts.getOrDefault(k, 0)
  result["tierCounts"] = tc
  var sc = newJObject()
  for k in ["verified", "inductive_valid", "failed", "skipped", "timeout", "blocked",
            "vacuous", "pre_sieved", "reused"]:
    sc[k] = %statusCounts.getOrDefault(k, 0)
  result["statusCounts"] = sc
  # Run-wide cumulative scalars (runResult.runScalars — doc-level metadata).
  if not runResult.executionEvidence.runScalars.isNil:
    for key in ["verified", "verifiedRatio", "vsr", "completionRate", "netVerifiedFunctions",
                "vacuousDemotions", "tautologyDemotions", "refactorRepaired", "asi"]:
      let v = runResult.executionEvidence.runScalars{key}
      if not v.isNil: result[key] = v

func executionStatsProjection(runResult: CanonicalRunResult): JsonNode {.raises: [].} =
  ## executionStats ← ExecutionEvidence — deterministic cross-wave aggregate:
  ## nodeStats concat, depthStats concat, additive counts summed, wall/hotspot
  ## from the merged executionStats (ExecutionMetrics — doc-level separation).
  result = newJObject()
  var solverInvocationCount, cacheHitCount, timeoutCount, obligationGeneratedCount,
      obligationAttemptedCount, targetsWithObligations, eligibleTargets = 0
  var nodeStats = newJArray()
  var depthStats = newJArray()
  for es in runResult.executionEvidence.waveExecutionStats:
    solverInvocationCount += safeGetInt(es, "solverInvocationCount")
    cacheHitCount += safeGetInt(es, "cacheHitCount")
    timeoutCount += safeGetInt(es, "timeoutCount")
    obligationGeneratedCount += safeGetInt(es, "obligationGeneratedCount")
    obligationAttemptedCount += safeGetInt(es, "obligationAttemptedCount")
    targetsWithObligations += safeGetInt(es, "targetsWithObligations")
    eligibleTargets += safeGetInt(es, "eligibleTargets")
    let ns = es{"nodeStats"}
    if not ns.isNil and ns.kind == JArray:
      for n in ns.elems: nodeStats.add(n)
    let ds = es{"depthStats"}
    if not ds.isNil and ds.kind == JArray:
      for d in ds.elems: depthStats.add(d)
  result["solverInvocationCount"] = %solverInvocationCount
  result["cacheHitCount"] = %cacheHitCount
  result["timeoutCount"] = %timeoutCount
  result["obligationGeneratedCount"] = %obligationGeneratedCount
  result["obligationAttemptedCount"] = %obligationAttemptedCount
  result["targetsWithObligations"] = %targetsWithObligations
  result["eligibleTargets"] = %eligibleTargets
  result["nodeStats"] = nodeStats
  result["depthStats"] = depthStats
  # wall/hotspot from the merged executionStats (doc-level ExecutionMetrics).
  let merged = runResult.executionEvidence.mergedExecutionStats
  if not merged.isNil:
    for key in ["totalWallTimeMs", "totalSolverTimeMs", "serialBaselineMs",
                "parallelSpeedupRatio", "cpuEfficiency", "maxWorkerCount",
                "hotspotNodeId", "hotspotLabel", "hotspotElapsedMs"]:
      let v = merged{key}
      if not v.isNil: result[key] = v

func renderLegacyReport*(
  runResult: CanonicalRunResult;
  preRun: JsonNode;
  projections: JsonNode
): JsonNode {.raises: [].} =
  ## PURE projection of the full legacy report from (CanonicalRunResult,
  ## PreRunContext, post-loop projections). The last-wave document is NEVER a
  ## data source. Ownership matrix (docs/spec/execution_accounting_contract.md):
  ##   nodeReports ← RunAccounting (keyed union across waves)
  ##   executionStats ← ExecutionEvidence (cross-wave aggregate)
  ##   summary ← merged rows + run-wide scalars
  ##   closure / crossValidation / leanVerify / scopeObservability ←
  ##   projections (post-loop; scopeObservability = §13.1 out-of-scope
  ##   failure channel + discoveredBeyond record)
  ##   diagnostics / verificationQueue / structuralBottlenecks /
  ##   repairPriorityDependencies / eligibility / census ← PreRunContext
  ##   schemaVersion / runtimeMeta ← constant / metadata
  result = newJObject()
  # ── PreRunContext passthrough (pre-loop skeleton data) ──
  if not preRun.isNil:
    for key in ["diagnostics", "verificationQueue", "structuralBottlenecks",
                "repairPriorityDependencies", "eligibility", "census",
                "declaredRequired"]:
      let v = preRun{key}
      if not v.isNil: result[key] = v
  # ── nodeReports ← merged rows (keyed union across waves) ──
  var nodeReports = newJArray()
  for row in runResult.executionEvidence.observedRows:
    nodeReports.add(row)
  result["nodeReports"] = nodeReports
  # ── per-wave union node lists ──
  result["blockedNodes"] = %runResult.executionEvidence.blockedNodes
  result["staleDependencyNodes"] = %runResult.executionEvidence.staleDependencyNodes
  result["reproofNodes"] = %runResult.executionEvidence.reproofNodes
  result["timeoutNodes"] = %runResult.executionEvidence.timeoutNodes
  result["timeoutImpactNodes"] = %runResult.executionEvidence.timeoutImpactNodes
  # ── executionStats ← ExecutionEvidence cross-wave aggregate ──
  result["executionStats"] = executionStatsProjection(runResult)
  # ── summary ← merged rows + run-wide scalars ──
  result["summary"] = summaryProjection(runResult, preRun)
  # ── doc-level run metadata ──
  let ev = runResult.executionEvidence
  result["runtimeMeta"] = if ev.runtimeMeta.isNil: newJObject() else: ev.runtimeMeta
  result["gates"] = if ev.gates.isNil: newJArray() else: ev.gates
  result["refactorSummary"] = if ev.refactorSummary.isNil: newJObject() else: ev.refactorSummary
  result["refactorEvidence"] = if ev.refactorEvidence.isNil: newJObject() else: ev.refactorEvidence
  # ── schemaVersion ← constant ──
  result["schemaVersion"] = %axiomReportSchemaVersion
  # ── post-loop projections (closure / crossValidation / leanVerify) ──
  if not projections.isNil:
    for key in ["closure", "crossValidation", "leanVerify", "scopeObservability"]:
      let v = projections{key}
      if not v.isNil: result[key] = v
  # ── additive canonical keys ──
  result["runAccounting"] = runResult.runAccounting.toJson()
  result["runOutcome"] = runOutcomeToJson(runResult.runOutcome)
  result[executionIdentityKey] = executionIdentityToJson(runResult.executionIdentity)
  result["canonicalRunDigest"] = %canonicalRunDigest(runResult)
