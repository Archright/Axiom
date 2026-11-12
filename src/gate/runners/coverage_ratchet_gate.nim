## Coverage Ratchet Gate
##
## Enforces monotonic test-coverage invariant: coverage can only increase.
## Compares current coverage against a baseline stored in
## data/reliability_score.json.
##
## Downgrade protocol (DEBT#495 — request/authority separation):
##   AXIOM_RATCHET_DOWNGRADE + AXIOM_RATCHET_REASON are a REQUEST only. The
##   sole authority to lower the baseline is an Ed25519 signature from the
##   pinned key (core/trusted/ratchet_authority.nim) over
##   "{tree_hash}|{old}|{new}|{reason}|{expires_at}|{jti}", carried via
##   AXIOM_RATCHET_APPROVAL. Every grant/refusal is recorded in-band in
##   downgrade_history (canonical) and mirrored to .axiom/bypass_audit.jsonl.
##   Missing/corrupt baseline, unsigned or invalid downgrades → FAIL.
##
## Usage:
##   coverage_ratchet_gate <stage>          # stage = pre-commit | pre-push

import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

import std/json
import std/os
import std/osproc
import std/strutils
import std/times
import core/axiom_pragmas
import core/trusted/env_access
import core/trusted/ratchet_authority
import core/utils/repo_root
import infrastructure/logger
import infrastructure/logging_facade


# axiomIoBoundary

axiomIoBoundary()

const
  GateTag = "[coverage-ratchet-gate]"
  BaselineRelPath = "data/reliability_score.json"
  CoverageReportRelPath = "data/coverage_report.json"
  AuditLogRelPath = ".axiom/bypass_audit.jsonl"
  MeasureCoverageBin = "bin/measure_coverage"

# ─── Helpers ─────────────────────────────────────────────────────────────────

proc getUtcNowIso(): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].}  =
  ## Return current UTC time as ISO 8601 string.
  let now = utc(getTime())
  result = now.format("yyyy-MM-dd'T'HH:mm:ss'Z'")

proc getGitHeadHash(repoRoot: string): string =
  ## Get the current HEAD commit hash via git.
  try:
    let (output, exitCode) = execCmdEx("git rev-parse HEAD", workingDir = repoRoot)
    if exitCode == 0:
      return output.strip()
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
  return "unknown"

proc getGitTreeHash(repoRoot: string): string =
  ## Current git tree hash — ratchet approvals are bound to this exact tree.
  ## Empty on failure → payload cannot match any real signature → refuse.
  try:
    let (output, exitCode) = execCmdEx("git rev-parse HEAD^{tree}", workingDir = repoRoot)
    if exitCode == 0:
      return output.strip()
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
  return ""

# ─── Baseline I/O ────────────────────────────────────────────────────────────

type
  RatchetBaseline = object
    baselineCoveragePct: float
    baselineTimestamp: string
    ratchetEnabled: bool
    adminSignature: string
    auditChainHead: string
    downgradeHistory: seq[JsonNode]
    loadOk: bool

proc loadBaseline(repoRoot: string): RatchetBaseline =
  ## Load the coverage ratchet baseline from data/reliability_score.json.
  ## A missing or corrupt artifact yields loadOk=false — the caller fails
  ## closed instead of inventing a 0.0 baseline (DEBT#495 ④).
  let path = repoRoot / BaselineRelPath
  if not fileExists(path):
    return RatchetBaseline(loadOk: false)
  try:
    let data = parseJson(readFile(path))
    var loaded = RatchetBaseline(loadOk: true, ratchetEnabled: true)
    loaded.baselineCoveragePct = data{"baseline_coverage_pct"}.getFloat(0.0)
    loaded.baselineTimestamp = data{"baseline_timestamp"}.getStr("")
    loaded.ratchetEnabled = data{"ratchet_enabled"}.getBool(true)
    loaded.adminSignature = data{"admin_signature"}.getStr("")
    loaded.auditChainHead = data{"audit_chain_head"}.getStr("")
    if data.hasKey("downgrade_history"):
      for entry in data["downgrade_history"]:
        if entry.kind != JObject:
          raise newException(ValueError, "downgrade_history entry is not an object")
        loaded.downgradeHistory.add(entry)
    result = loaded
  except CatchableError:
    discard  # loadOk stays false → fail closed

proc verifyBaselineIntegrity(baseline: RatchetBaseline): seq[string] =
  ## In-band verification of downgrade_history at load time (DEBT#495 ①③).
  ## GRANTED records must carry a valid pinned-key signature over their
  ## recorded payload; refusal records are evidence only (their embedded
  ## signature may legitimately be attacker material that failed to verify);
  ## the live baseline must never sit below any baseline-affecting record.
  ## Pre-closure records (no kind, no granted field) are historical fact.
  var lastStateChangeNew = 0.0
  var hasStateChange = false
  for i, entry in baseline.downgradeHistory:
    let oldPct = entry{"old_baseline"}.getFloat(-1.0)
    let newPct = entry{"new_baseline"}.getFloat(-1.0)
    if oldPct < 0.0 or newPct < 0.0:
      result.add "history[" & $i & "]: missing old/new_baseline"
      continue
    let signature = entry{"admin_signature"}.getStr("")
    let kind = entry{"kind"}.getStr("")
    if entry{"granted"}.getBool(false):
      # Post-closure granted downgrade — crypto-verify the in-band record.
      if entry{"signing_key_id"}.getStr("") != RatchetAuthorityKeyId:
        result.add "history[" & $i & "]: unknown authority keyid"
      if signature.len == 0:
        result.add "history[" & $i & "]: granted downgrade without signature"
      else:
        let payload = entry{"payload"}.getStr("")
        if payload.len == 0:
          result.add "history[" & $i & "]: signed record missing payload"
        else:
          let expected = formatRatchetPayload(entry{"tree_hash"}.getStr(""),
              oldPct, newPct, entry{"reason"}.getStr(""),
              entry{"expires_at"}.getStr(""), entry{"jti"}.getStr(""))
          if payload != expected:
            result.add "history[" & $i & "]: payload does not match recorded fields"
          if not verifyRatchetDowngradeSignature(payload, signature):
            result.add "history[" & $i & "]: signature invalid under pinned key"
      if newPct >= oldPct:
        result.add "history[" & $i & "]: signed record is not a downgrade"
    elif kind == "auto_bump":
      if newPct < oldPct:
        result.add "history[" & $i & "]: auto_bump lowered the baseline"
    # refused records and pre-closure legacy records: information only, no
    # baseline authority, no signature requirement.
    if entry{"granted"}.getBool(false) or kind == "auto_bump":
      lastStateChangeNew = newPct
      hasStateChange = true
  # Baseline↔history coherence (DEBT#495 ③): once the audited regime has
  # produced at least one state-changing record, the live baseline MUST equal
  # the last recorded state change — any hand-edit of baseline_coverage_pct
  # without an in-band record breaks this. Rises are recorded as auto_bump,
  # falls as granted downgrades, so equality holds on every legitimate path.
  # A history with only pre-closure legacy records stays exempt (historical
  # regime recorded neither downgrades fully nor rises at all).
  if hasStateChange and baseline.baselineCoveragePct != lastStateChangeNew:
    result.add "live baseline " & $baseline.baselineCoveragePct &
               " out of sync with last recorded state change " & $lastStateChangeNew

proc saveBaseline(repoRoot: string; baseline: RatchetBaseline) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Persist the baseline. Authoritative records are appended to
  ## baseline.downgradeHistory via recordHistory BEFORE calling this.
  let path = repoRoot / BaselineRelPath
  let parentDir = path.parentDir()
  if not dirExists(parentDir):
    createDir(parentDir)

  var historyArr = newJArray()
  for entry in baseline.downgradeHistory:
    historyArr.add(entry)

  let payload = %*{
    "baseline_coverage_pct": baseline.baselineCoveragePct,
    "baseline_timestamp": getUtcNowIso(),
    "ratchet_enabled": baseline.ratchetEnabled,
    "admin_signature": baseline.adminSignature,
    "audit_chain_head": baseline.auditChainHead,
    "downgrade_history": historyArr
  }
  writeFile(path, $payload & "\n")

# ─── Coverage Measurement ────────────────────────────────────────────────────

proc measureCoverage(repoRoot: string): float =
  ## Run bin/measure_coverage to produce data/coverage_report.json, then read it.
  let reportPath = repoRoot / CoverageReportRelPath
  let binPath = repoRoot / MeasureCoverageBin

  if fileExists(binPath):
    try:
      let (output, exitCode) = execCmdEx(
        "./" & MeasureCoverageBin,
        workingDir = repoRoot
      )
      if exitCode != 0:
        logger.warn $GateTag & " measure_coverage exited with code " & $exitCode
    except CatchableError as e:
      logger.warn $GateTag & " Failed to run measure_coverage: " & $e.msg
  else:
    logger.info $GateTag & " measure_coverage binary not found, reading existing report."

  # Read the report
  if not fileExists(reportPath):
    logger.warn $GateTag & " No coverage report found at " & $CoverageReportRelPath &
                ". Assuming 0.0%."
    return 0.0

  try:
    let data = parseJson(readFile(reportPath))
    # Support both top-level and nested coverage percentage
    if data.hasKey("coverage_pct"):
      return data{"coverage_pct"}.getFloat(0.0)
    elif data.hasKey("coverage") and data["coverage"].hasKey("percent"):
      return data["coverage"]["percent"].getFloat(0.0)
    else:
      logger.warn $GateTag & " Coverage report missing 'coverage_pct' field."
      return 0.0
  except CatchableError as e:
    logger.warn $GateTag & " Failed to parse coverage report: " & $e.msg
    return 0.0

# ─── Authority Records & Audit Logging ───────────────────────────────────────

func jtiSeen(jti: string; history: seq[JsonNode]): bool =
  ## jti is single-use: any prior in-band record (granted or refused) burns it.
  if jti.len == 0:
    return false
  for entry in history:
    if entry{"jti"}.getStr("") == jti:
      return true

type
  DowngradeDecision = object
    ok: bool
    violation: string
    signature: string
    jti: string
    expiresAt: string
    payload: string

proc authorizeDowngrade(approvalRaw, reason, treeHash: string;
                        baselinePct, currentPct: float;
                        nowUnix: int64; history: seq[JsonNode]): DowngradeDecision =
  ## Request/authority separation (DEBT#495 ②): the env flags are a request;
  ## the ONLY grant is an unexpired, single-use Ed25519 approval from the
  ## pinned key over the exact retarget payload. Every refusal carries a
  ## machine-readable violation label for the in-band audit record.
  if approvalRaw.len == 0:
    result.violation = "approval_missing"
    return
  var approval: JsonNode
  try:
    approval = parseJson(approvalRaw)
  except CatchableError:
    result.violation = "approval_malformed"
    return
  if approval.kind != JObject:
    result.violation = "approval_malformed"
    return
  let signature = approval{"signature"}.getStr("")
  let jti = approval{"jti"}.getStr("")
  let expiresAt = approval{"expires_at"}.getStr("")
  result.signature = signature
  result.jti = jti
  result.expiresAt = expiresAt
  if signature.len == 0 or jti.len == 0 or expiresAt.len == 0:
    result.violation = "approval_incomplete"
    return
  var expiryUnix = int64(-1)
  try:
    expiryUnix = parse(expiresAt, "yyyy-MM-dd'T'HH:mm:ss'Z'", utc()).toTime.toUnix
  except CatchableError:
    result.violation = "approval_malformed"
    return
  if nowUnix >= expiryUnix:
    result.violation = "approval_expired"
    return
  if jtiSeen(jti, history):
    result.violation = "jti_reuse"
    return
  let payload = formatRatchetPayload(treeHash, baselinePct, currentPct,
                                     reason, expiresAt, jti)
  result.payload = payload
  if not verifyRatchetDowngradeSignature(payload, signature):
    result.violation = "signature_invalid"
    return
  result.ok = true

func buildAuthorityRecord(oldPct, newPct: float; reason, treeHash, signature,
                          keyid, jti, expiresAt, payload, violation,
                          timestampIso: string; granted: bool): JsonNode =
  ## Canonical in-band audit record (DEBT#495 ①④), field names per
  ## docs/spec/coverage_ratchet_protocol.md §Audit Trail: full signature
  ## (admin_signature) + signing_key_id, UTC ISO 8601 timestamp, single-use
  ## jti, accepted/rejected outcome. The hash-chain links are attached by
  ## recordHistory. Signature encoding is 128-char lowercase hex (the
  ## repo-wide Ed25519 convention used by tools/bypass_sign.nim).
  result = %*{
    "old_baseline": oldPct,
    "new_baseline": newPct,
    "timestamp": timestampIso,
    "reason": reason,
    "tree_hash": treeHash,
    "payload": payload,
    "admin_signature": signature,
    "signing_key_id": keyid,
    "jti": jti,
    "expires_at": expiresAt,
    "outcome": if granted: "accepted" else: "rejected",
    "granted": granted
  }
  if violation.len > 0:
    result["violation"] = newJString(violation)

proc recordHistory(baseline: var RatchetBaseline; record: JsonNode) =
  ## Append a canonical in-band record and extend the hash chain.
  let prev = baseline.auditChainHead
  record["prev_record_hash"] = newJString(prev)
  let link = ratchetRecordHash(prev, record{"jti"}.getStr(""),
                               record{"admin_signature"}.getStr(""),
                               record{"timestamp"}.getStr(""),
                               record{"granted"}.getBool(false))
  record["record_hash"] = newJString(link)
  baseline.auditChainHead = link
  baseline.downgradeHistory.add(record)

proc appendAuditLog(repoRoot: string; record: JsonNode;
                    commitHash: string): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Append a decision record to .axiom/bypass_audit.jsonl. Returns false on
  ## write failure — for granted downgrades a failed audit append REFUSES the
  ## downgrade (DEBT#495 ③②; the old best-effort warn-only path is gone).
  ## The canonical record is the in-band downgrade_history entry.
  let auditPath = repoRoot / AuditLogRelPath
  let auditDir = auditPath.parentDir()
  if not dirExists(auditDir):
    createDir(auditDir)

  var entry = newJObject()
  entry["tool"] = newJString("coverage-ratchet-gate")
  entry["action"] = newJString("baseline_downgrade")
  entry["outcome"] = newJString(if record{"granted"}.getBool(false): "accepted" else: "rejected")
  entry["granted"] = newJBool(record{"granted"}.getBool(false))
  entry["old_baseline"] = record{"old_baseline"}
  entry["new_baseline"] = record{"new_baseline"}
  entry["reason"] = newJString(record{"reason"}.getStr(""))
  if record.hasKey("violation"):
    entry["violation"] = newJString(record{"violation"}.getStr(""))
  entry["admin_signature"] = newJString(record{"admin_signature"}.getStr(""))
  entry["signing_key_id"] = newJString(record{"signing_key_id"}.getStr(""))
  entry["jti"] = newJString(record{"jti"}.getStr(""))
  entry["expires_at"] = newJString(record{"expires_at"}.getStr(""))
  entry["record_hash"] = newJString(record{"record_hash"}.getStr(""))
  entry["prev_record_hash"] = newJString(record{"prev_record_hash"}.getStr(""))
  entry["timestamp"] = newJString(record{"timestamp"}.getStr(""))
  entry["admin_user"] = newJString(currentUser())
  entry["commit_hash"] = newJString(commitHash)

  try:
    var f = open(auditPath, fmAppend)
    defer: f.close()
    f.write($entry & "\n")
    return true
  except CatchableError as e:
    logger.warn $GateTag & " Failed to write audit log: " & $e.msg
    return false

proc refuseDowngrade(repoRoot: string; baseline: var RatchetBaseline;
                     decision: DowngradeDecision; reason, treeHash: string;
                     baselinePct, currentPct: float;
                     commitHash: string): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Record the refusal in-band (canonical), mirror it to the local audit log,
  ## and fail the gate. The baseline value itself never moves on a refusal.
  let record = buildAuthorityRecord(baselinePct, currentPct, reason, treeHash,
      decision.signature, RatchetAuthorityKeyId, decision.jti,
      decision.expiresAt, decision.payload, decision.violation,
      getUtcNowIso(), false)
  record["kind"] = newJString("refused")
  recordHistory(baseline, record)
  try:
    saveBaseline(repoRoot, baseline)
  except CatchableError as e:
    logError("coverage_ratchet_gate", $(GateTag) & " FAIL: refusal record could not be persisted: " & $e.msg)
    return 1
  discard appendAuditLog(repoRoot, record, commitHash)
  logError("coverage_ratchet_gate", $(GateTag) & " FAIL: downgrade refused (" & decision.violation & ").")
  logInfo("coverage_ratchet_gate", $(GateTag) & " Refusal recorded in-band (downgrade_history).")
  return 1

# ─── Core Gate Logic ─────────────────────────────────────────────────────────

proc runCoverageRatchet(): int =
  ## Main gate logic. Returns 0 for PASS, 1 for FAIL.
  let repoRoot = findRepoRoot()
  setCurrentDir(repoRoot)

  let stage = if paramCount() >= 1: paramStr(1) else: "pre-commit"
  logger.info $GateTag & " Running in stage: " & $stage

  # 1. Load baseline — fail-closed on missing/corrupt artifact (DEBT#495 ④)
  let baseline = loadBaseline(repoRoot)
  if not baseline.loadOk:
    logError("coverage_ratchet_gate", $(GateTag) & " FAIL: baseline missing or unreadable at " &
                BaselineRelPath & " — refusing to invent a default (fail-closed).")
    return 1
  let integrityViolations = verifyBaselineIntegrity(baseline)
  if integrityViolations.len > 0:
    for violation in integrityViolations:
      logError("coverage_ratchet_gate", $(GateTag) & " FAIL: baseline integrity: " & violation)
    return 1
  logger.info $GateTag & " Baseline coverage: " & $baseline.baselineCoveragePct & "%"

  if not baseline.ratchetEnabled:
    logger.info $GateTag & " Ratchet disabled in config. PASS (no-op)."
    return 0

  # 2. Measure current coverage
  let currentPct = measureCoverage(repoRoot)
  logger.info $GateTag & " Current coverage:  " & $currentPct & "%"

  # 3. Compare
  if currentPct >= baseline.baselineCoveragePct:
    logger.info $GateTag & " PASS: coverage " & $currentPct &
                "% >= baseline " & $baseline.baselineCoveragePct & "%"
    # Auto-bump baseline upward — risk-free by construction (raises the bar,
    # never lowers it) and recorded in-band (DEBT#495 ⑤).
    if currentPct > baseline.baselineCoveragePct:
      var updated = baseline
      updated.baselineCoveragePct = currentPct
      updated.adminSignature = ""
      let bump = buildAuthorityRecord(baseline.baselineCoveragePct, currentPct,
          "auto-bump: measured coverage exceeded baseline", "", "", "", "", "",
          "", "", getUtcNowIso(), false)
      bump["kind"] = newJString("auto_bump")
      bump["risk"] = newJString("none — raises the ratchet, never lowers it")
      recordHistory(updated, bump)
      try:
        saveBaseline(repoRoot, updated)
        logger.info $GateTag & " Baseline bumped to " & $currentPct & "%"
      except CatchableError as e:
        logger.warn $GateTag & " Baseline bump not persisted: " & $e.msg &
                    " (verdict unaffected)"
    return 0
  else:
    # Coverage dropped — downgrade protocol (request ≠ authority)
    let downgradeFlag = getAxiomEnv(evRatchetDowngrade, "")
    let downgradeReason = getAxiomEnv(evRatchetReason, "")
    let approvalRaw = getAxiomEnv(evRatchetApproval, "")
    let commitHash = getGitHeadHash(repoRoot)

    if downgradeFlag != "1" or downgradeReason.len == 0:
      # Ratchet violation — no downgrade request at all
      logError("coverage_ratchet_gate", $(GateTag) & " FAIL: coverage ratchet violated.")
      logInfo("coverage_ratchet_gate", $(GateTag) & " Current: " & $currentPct & "% < baseline: " & $baseline.baselineCoveragePct & "%")
      logInfo("coverage_ratchet_gate", $(GateTag) & " To request a downgrade, set AXIOM_RATCHET_DOWNGRADE=1 and AXIOM_RATCHET_REASON=\"<reason>\"")
      logInfo("coverage_ratchet_gate", $(GateTag) & " A request alone is refused: authority requires a pinned-key Ed25519 approval in AXIOM_RATCHET_APPROVAL (see core/trusted/ratchet_authority.nim).")
      logInfo("coverage_ratchet_gate", $(GateTag) & " Or increase coverage to meet the baseline.")
      return 1

    let treeHash = getGitTreeHash(repoRoot)
    let decision = authorizeDowngrade(approvalRaw, downgradeReason, treeHash,
                                      baseline.baselineCoveragePct, currentPct,
                                      getTime().toUnix, baseline.downgradeHistory)
    if not decision.ok:
      var refusedState = baseline
      return refuseDowngrade(repoRoot, refusedState, decision, downgradeReason,
                             treeHash, baseline.baselineCoveragePct, currentPct,
                             commitHash)

    # Authorized: mandatory local audit append BEFORE any baseline mutation.
    var grantedState = baseline
    let record = buildAuthorityRecord(baseline.baselineCoveragePct, currentPct,
        downgradeReason, treeHash, decision.signature, RatchetAuthorityKeyId,
        decision.jti, decision.expiresAt, decision.payload, "",
        getUtcNowIso(), true)
    recordHistory(grantedState, record)
    if not appendAuditLog(repoRoot, record, commitHash):
      var auditFailState = baseline
      let auditFail = buildAuthorityRecord(baseline.baselineCoveragePct,
          currentPct, downgradeReason, treeHash, decision.signature,
          RatchetAuthorityKeyId, decision.jti, decision.expiresAt,
          decision.payload, "audit_write_failed", getUtcNowIso(), false)
      auditFail["kind"] = newJString("refused")
      recordHistory(auditFailState, auditFail)
      try:
        saveBaseline(repoRoot, auditFailState)
      except CatchableError:
        discard  # gate still fails below even if the refusal record is unpersistable
      logError("coverage_ratchet_gate", $(GateTag) & " FAIL: downgrade refused (audit_write_failed).")
      return 1

    grantedState.baselineCoveragePct = currentPct
    grantedState.adminSignature = decision.signature
    try:
      saveBaseline(repoRoot, grantedState)
    except CatchableError as e:
      logError("coverage_ratchet_gate", $(GateTag) & " FAIL: authorized downgrade could not be persisted: " & $e.msg)
      return 1

    logger.warn $GateTag & " COVERAGE DOWNGRADE (authorized): " & $currentPct &
                "% < previous baseline " & $baseline.baselineCoveragePct & "%"
    logger.warn $GateTag & " PASS (authorized downgrade). New baseline: " &
                $currentPct & "% — signed in-band by key " & RatchetAuthorityKeyId
    return 0

# ─── Entry Point ─────────────────────────────────────────────────────────────

when isMainModule:
  let exitCode = runCoverageRatchet()
  quit(exitCode)

{.pop.}
