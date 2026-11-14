import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
# axiomIoBoundary

## `ax report --upstream` — upstream GitHub issue reporter (trusted executor).
##
## Contract: docs/spec/upstream_reporting_contract.md — the receipt SSOT, the
## report status machine (READY / SUBMITTED / DUPLICATE / BLOCKED / FAILED /
## RECONCILIATION_REQUIRED), the v2 identity model (§4: findingKey over the
## resolved repository + subject + proposition; evidenceDigest over the
## evidence; legacyFingerprints recording the v1 reportFingerprint values),
## the findingEvidence consumption (the engine-produced canonical evidence
## block), the §6 v1 legacy-receipt migration, the §8 error table (429
## included), and the fail-closed input rules are defined there; this module
## is the implementation.
##
## Shape:
##   - PURE parts (`func {.raises: [].}`): state/display parsing (fail-closed),
##     findingEvidence parsing + counterexample normalization, findingKey /
##     evidenceDigest / legacy-v1-fingerprint composition, receipt projection,
##     gh-outcome classification, issue title/body composition, spec-overlay
##     fact extraction. No network, no clock, no filesystem.
##   - IO parts (proc, axiomEffect): the `gh` subprocess adapter (the ONE
##     credential boundary — GitHub credentials are used ONLY through the
##     native `gh` client, AGENTS.md §2.4; no token files, no env scanning),
##     the single-writer ledger data/upstream_reports/<findingKey>.json
##     (atomic tmp+rename), and the phase orchestrator.
##   - The gh boundary is an INJECTED adapter (`GhAdapter`): production wires
##     `liveGhAdapter` (one-shot execCmdEx, poUsePath, fail-closed on
##     non-zero/empty — the tools/merge_ruleset_drift_monitor.nim pattern),
##     tests inject a scripted mock. No network in tests.

import std/[algorithm, base64, json, options, os, osproc, strutils, times]
import cli/cli_types
import core/axiom_pragmas
import core/crypto/hash_kernel
import core/parsers/safe_parsers
import core/results
import core/trusted/stdlib_shield
import core/utils/decision_algebra
import core/utils/repo_root
import verification/report_engine

# ---------------------------------------------------------------------------
# Contract constants
# ---------------------------------------------------------------------------

const
  bugVerdictDisplaySchemaVersionV3* = "bug-verdict-display-v3"
    ## Consumption-side closed spelling (docs/spec/upstream_reporting_contract.md).
    ## The producer lives in the display projection; this module only reads v3
    ## and fails closed on anything else.
  upstreamReceiptSchemaVersionV1* = "upstream-report-receipt-v1"
    ## Legacy receipt schema (§10) — read-only migration source; never written.
  upstreamReceiptSchemaVersion* = "upstream-report-receipt-v2"
  upstreamResultSchemaVersion* = "upstream-report-cli-result-v2"
  ledgerDirRelative* = "data/upstream_reports"
  defaultIssueSections* = @["Problem", "Impact", "To reproduce", "Expected behavior"]
  blocked403* = "403-permission-or-interaction-limit"
  blocked403RateLimited* = "403-rate-limit-transient-restriction"
    ## Honest 403 spelling when the gh output carries rate-limit tokens:
    ## GitHub's official REST docs state a primary/secondary rate limit
    ## answers 403 or 429 (docs.github.com/en/rest/using-the-rest-api/
    ## rate-limits-for-the-rest-api) — a rate-limited 403 is a transient
    ## restriction, not a permission denial.
  blocked403RateLimitedDetail* = "blocked: http 403 — rate limited (transient " &
    "restriction; condition change: rate-limit window reset; retry only as a " &
    "new user-directed submission attempt; no auto-retry)"
  blocked429* = "429-rate-limit-transient-restriction"
    ## §8: 429 = rate limited (primary/secondary) — the status code is itself
    ## the throttle signal, so it is a transient restriction with or without
    ## rate-limit tokens in the gh output, never a permission denial and never
    ## confirmed non-creation.
  blocked429Detail* = "blocked: http 429 — rate limited (transient restriction; " &
    "condition change: rate-limit window reset; retry only as a new " &
    "user-directed submission attempt; no auto-retry)"
  blocked404* = "404-target-unresolvable"
  blocked410* = "410-issues-disabled"
  blockedGhAuth* = "gh-auth"
  blockedDupCheck* = "duplicate-check-unavailable"
  blockedRepoResolution* = "repo-resolution-unresolved"
  blockedEvidenceMissing* = "finding-evidence-missing"
    ## §11: the common four evidence elements are a reporting precondition —
    ## a reportable-attribution unit without a findingEvidence block never
    ## reaches READY (its counterexample is honestly recorded as empty).
  blockedEvidenceEmpty* = "counterexample-empty"
    ## findingEvidence present but its counterexample lines carry no
    ## `input.<key>=<value>` bindings — same §11 precondition, same gate.
  blockedLegacyAmbiguous* = "legacy-receipt-identity-ambiguous"
    ## §6: more than one legacy receipt matches the identity triple — the
    ## migration is fail-closed BLOCKED until a human removes the ambiguity
    ## source; it re-derives every run (the original v1 files stay immutable).
  failedConfirmed* = "submission-failed-confirmed-non-creation"
  failedRemoteUnverifiable* = "remote-state-unverifiable"
  failedReadyPersist* = "ready-receipt-persist-failed"
  failedLegacyPersist* = "legacy-migration-receipt-persist-failed"
  reconciliationLedgerUnverifiable* = "ledger-submission-unverifiable"

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type
  UpstreamReportStatus* = enum
    ursReady = "READY"
    ursSubmitted = "SUBMITTED"
    ursDuplicate = "DUPLICATE"
    ursBlocked = "BLOCKED"
    ursFailed = "FAILED"
    ursReconciliationRequired = "RECONCILIATION_REQUIRED"

  GhOutcomeKind* = enum
    gokOk
    gokGhMissing
    gokAuth
    gokHttp403
    gokHttp404
    gokHttp410
    gokHttp429      ## §8: rate limited (primary/secondary) — transient
                    ## restriction (BLOCKED), never confirmed non-creation
    gokRejected     ## other 4xx — client rejected, confirmed non-creation
    gokTimeout      ## timeout / deadline tokens — creation state unknown
    gokAmbiguous    ## anything else non-zero — creation state unknown

  GhResult* = object
    exitCode*: int
    output*: string   ## merged stdout+stderr (execCmdEx semantics)

  GhAdapter* = proc (command: string): GhResult
    ## The injected `gh` boundary. Production wires `liveGhAdapter`; tests
    ## inject a scripted mock (no network in tests).

  Clock* = proc (): string

  UpstreamAttempt* = object
    ts*: string
    phase*: string
    outcome*: string
    candidateUrl*: string  ## tentative issue URL from an ambiguous create —
                           ## the NEXT run's direct `gh issue view` recovery input

  UpstreamReceipt* = object
    schemaVersion*: string
    findingKey*: string
      ## §4: SHA-256 of the canonical identity triple — the ledger filename
      ## and the issue-body anchor; counterexample-independent (v2).
    evidenceDigest*: string
      ## §4: SHA-256 of the evidence projection — changes as evidence is
      ## reinforced; findingKey stays invariant.
    legacyFingerprints*: seq[string]
      ## §4/§6: the v1 reportFingerprint value(s) inherited at migration —
      ## the re-linking record for issues created before v2.
    status*: UpstreamReportStatus
    propositionVerdict*: string
    requirementSourceStatus*: string
    bugAttribution*: string
    requestedRepository*: string
    resolvedRepository*: string
    commit*: string
    module*: string
    symbol*: string
    blobSha256*: string
    specId*: string
    ruleId*: string
    ruleVersion*: string
    specRelPath*: string
    canonicalSpecIrDigest*: string
    normalized*: seq[string]
    rawQuartet*: seq[string]
    issueNumber*: int
    issueUrl*: string
    blockedReason*: string
    attempts*: seq[UpstreamAttempt]
    submittedAt*: string

  FindingEvidence* = object
    ## The state document's canonical evidence block for one unit
    ## (root key "findingEvidence", keyed by targetSymbol) — the reporter
    ## consumes THIS as the canonical counterexample/subject-pin evidence;
    ## display-unit reverse parsing is no longer an evidence source.
    claimOutcome*: string
    rowStatus*: string
    machineVerdict*: string
    machineEstablished*: bool
    counterExampleRaw*: seq[string]
    quartetPayloadDigest*: string
    subjectCommit*: string
    subjectBlob*: string

  FindingIdentity* = object
    ## The per-unit v2 identity the whole pipeline keys on: the findingKey
    ## (ledger filename + body anchor), the evidenceDigest (evidence
    ## integrity projection), and the legacy v1 fingerprints (migration
    ## record — folded in from the matched legacy receipt / prior v2 receipt).
    findingKey*: string
    evidenceDigest*: string
    legacyFingerprints*: seq[string]

  ReportableUnit* = object
    targetSymbol*: string
    bugAttribution*: string
    propositionVerdict*: string
    requirementSourceStatus*: string
    uncertaintyKinds*: seq[string]
    machineStates*: seq[string]
    groundsRefs*: seq[string]
    ruleJudgment*: string
    groundsValidation*: string
    displayInputDigest*: string
    evidenceMissing*: bool
      ## true when the state document carries no findingEvidence block for
      ## this unit — the counterexample is then honestly empty and the §11
      ## gate blocks READY (never a blind report).
    claimOutcome*: string
    rowStatus*: string
    machineVerdict*: string
    machineEstablished*: bool
    subjectCommit*: string
    subjectBlob*: string
    specId*: string
    specRelPath*: string
    normalized*: seq[string]
      ## the findingEvidence counterExample lines normalized into the
      ## key-sorted, deduped `input.<key>=<value>` binding list
    rawQuartet*: seq[string]
      ## the findingEvidence counterExample lines, in document order
    quartetPayloadDigest*: string

  OverlayFacts* = object
    ## Deterministic projection of the committed spec overlay — the law
    ## content stays DATA here (the reporter hardcodes no proposition content).
    requestedRepository*: string
    commit*: string
    moduleName*: string
    symbol*: string
    blobSha256*: string
    specId*: string
    ruleId*: string
    ruleVersion*: string
    clauses*: seq[string]
    carrierNames*: seq[string]
    defectCarrier*: string
    lawClause*: string
    actualClause*: string

  UpstreamRunConfig* = object
    stateFilePath*: string
    repoRoot*: string
    ledgerDir*: string
    dryRun*: bool
    emitJson*: bool

  UpstreamUnitOutcome* = object
    targetSymbol*: string
    findingKey*: string
    status*: UpstreamReportStatus
    blockedReason*: string
    detail*: string
    issueNumber*: int
    issueUrl*: string
    requestedRepository*: string
    resolvedRepository*: string

  UpstreamCliFlags* = object
    stateFilePath*: string
    dryRun*: bool
    emitJson*: bool

# ---------------------------------------------------------------------------
# Pure: small string/JSON helpers
# ---------------------------------------------------------------------------

func shellQuote*(s: string): string {.raises: [].} =
  ## POSIX single-quote shell quoting (execCmdEx evaluates through the shell).
  "'" & s.replace("'", "'\\''") & "'"

func excerptOf*(s: string; maxLen: int = 200): string {.raises: [].} =
  ## Single-line bounded excerpt — receipts never embed full gh payloads.
  let flat = s.replace("\r", " ").replace("\n", " ").strip()
  if flat.len <= maxLen:
    flat
  else:
    flat[0 ..< maxLen] & "..."

func allIn*(s: string; cs: set[char]): bool {.raises: [].} =
  for c in s:
    if c notin cs:
      return false
  true

func jsonSeqOfStrings*(n: JsonNode): seq[string] {.raises: [].} =
  result = @[]
  if not n.isNil and n.kind == JArray:
    for v in n.items:
      if v.kind == JString:
        result.add(v.getStr())

# ---------------------------------------------------------------------------
# Pure: repository descriptor -> owner/repo
# ---------------------------------------------------------------------------

func extractOwnerRepo*(repositoryDescriptor: string): string {.raises: [].} =
  ## First `owner/repo` token in the overlay's descriptive repository string
  ## (e.g. "status-im/nim-libp2p (local READ-ONLY clone /home/x; origin
  ## iftech/nim-libp2p fork of status-im/nim-libp2p)" -> "status-im/nim-libp2p").
  ## The token charset is restricted so the extracted value is always
  ## shell-safe and unambiguous (multi-slash path tokens are rejected).
  const ownerChars = {'A'..'Z', 'a'..'z', '0'..'9', '_', '.', '-'}
  for tok in repositoryDescriptor.split({' ', '\t', '(', ')', ';', ','}):
    let slash = tok.find('/')
    if slash <= 0 or slash == tok.len - 1:
      continue
    if allIn(tok, ownerChars + {'/'}):
      return tok
  ""

func safeSpecRelPath*(rel: string): bool {.raises: [].} =
  ## The overlay path must stay inside config/spec (no traversal, no escapes).
  if rel.len == 0 or rel.startsWith("/") or rel.contains("\\"):
    return false
  for part in rel.split('/'):
    if part == "..":
      return false
  true

# ---------------------------------------------------------------------------
# Pure: counterexample normalization (findingEvidence consumption)
# ---------------------------------------------------------------------------

func extractInputBindings*(line: string): seq[string] {.raises: [].} =
  ## `input.<key>=<value>` tokens from one counterexample/quartet line.
  const stopChars = {' ', '\t', '\n', '\r', ',', '"', ')', ']', ';', '\''}
  const keyChars = {'A'..'Z', 'a'..'z', '0'..'9', '_', '.', '-'}
  result = @[]
  var i = 0
  while true:
    let p = line.find("input.", i)
    if p < 0:
      return
    var j = p + "input.".len
    var key = ""
    while j < line.len and line[j] in keyChars:
      key.add(line[j])
      inc j
    if key.len > 0 and j < line.len and line[j] == '=':
      var k = j + 1
      var value = ""
      while k < line.len and line[k] notin stopChars:
        value.add(line[k])
        inc k
      if value.len > 0:
        result.add(key & "=" & value)
        i = k
        continue
    i = p + "input.".len

func normalizeEvidenceCounterexample*(lines: seq[string]): tuple[
    normalized: seq[string]; raw: seq[string]] {.raises: [].} =
  ## The findingEvidence `counterExample` lines -> the key-sorted, deduped
  ## `input.<key>=<value>` binding list (the evidenceDigest/receipt's
  ## counterexample input) plus the raw source lines in document order (the
  ## receipt's rawQuartet). Lines without bindings are dropped from
  ## `normalized` but kept in `raw` — never silently rewritten.
  for line in lines:
    let bindings = extractInputBindings(line)
    if bindings.len > 0:
      result.raw.add(line)
      for b in bindings:
        if b notin result.normalized:
          result.normalized.add(b)
  result.normalized.sort(cmp)

func bindingKey*(binding: string): string {.raises: [].} =
  let eq = binding.find('=')
  if eq > 0:
    binding[0 ..< eq]
  else:
    ""

func bindingValue*(binding: string): string {.raises: [].} =
  let eq = binding.find('=')
  if eq > 0:
    binding[eq + 1 ..< binding.len]
  else:
    ""

# ---------------------------------------------------------------------------
# Pure: state / display parsing (fail-closed)
# ---------------------------------------------------------------------------

func isReportableUnit*(bugAttribution, propositionVerdict: string): bool {.raises: [].} =
  ## UNKNOWN / NOT_DISPROVED units are never reported upstream (contract).
  (bugAttribution == "BUG_FOUND" or bugAttribution == "BUG_SUSPECTED") and
    propositionVerdict == "DISPROVED"

func parseFindingEvidence*(node: JsonNode): Result[FindingEvidence, string] {.raises: [].} =
  ## One unit's canonical evidence entry: `stateJson.findingEvidence[<targetSymbol>]`
  ## with the fixed producer interface (claimOutcome, rowStatus, machineVerdict,
  ## machineEstablished, counterExample, quartetPayloadDigest, subjectCommit,
  ## subjectBlob). Shape violations fail closed — the evidence block is the
  ## reporting precondition (§11), never guessed around.
  if node.isNil or node.kind != JObject:
    return err("findingEvidence entry is not a JSON object")
  let cxNode = node{"counterExample"}
  if not cxNode.isNil and cxNode.kind != JArray:
    return err("findingEvidence.counterExample is not an array")
  let meNode = node{"machineEstablished"}
  if not meNode.isNil and meNode.kind != JBool:
    return err("findingEvidence.machineEstablished is not a boolean")
  ok(FindingEvidence(
    claimOutcome: node{"claimOutcome"}.getStr(""),
    rowStatus: node{"rowStatus"}.getStr(""),
    machineVerdict: node{"machineVerdict"}.getStr(""),
    machineEstablished: (if meNode.isNil: false else: meNode.getBool()),
    counterExampleRaw: jsonSeqOfStrings(cxNode),
    quartetPayloadDigest: node{"quartetPayloadDigest"}.getStr(""),
    subjectCommit: node{"subjectCommit"}.getStr(""),
    subjectBlob: node{"subjectBlob"}.getStr("")))

func parseReportableUnit*(unitNode: JsonNode): ReportableUnit {.raises: [].} =
  ## The display unit's attribution/proposition fields. The counterexample and
  ## the subject pin are NOT read here — they arrive only through the state
  ## document's findingEvidence block (merged in selectReportableUnits).
  ReportableUnit(
    targetSymbol: unitNode{"targetSymbol"}.getStr(""),
    bugAttribution: unitNode{"bugAttribution"}.getStr(""),
    propositionVerdict: unitNode{"propositionVerdict"}.getStr(""),
    requirementSourceStatus: unitNode{"requirementSourceStatus"}.getStr(""),
    uncertaintyKinds: jsonSeqOfStrings(unitNode{"uncertaintyKinds"}),
    machineStates: jsonSeqOfStrings(unitNode{"machineStates"}),
    groundsRefs: jsonSeqOfStrings(unitNode{"groundsRefs"}),
    ruleJudgment: unitNode{"ruleJudgment"}.getStr(""),
    groundsValidation: unitNode{"groundsValidation"}.getStr(""),
    displayInputDigest: unitNode{"displayInputDigest"}.getStr(""),
    specId: unitNode{"adoptedSpecRef"}{"specId"}.getStr(""),
    specRelPath: unitNode{"adoptedSpecRef"}{"specRelPath"}.getStr(""))

func selectDisplayBlock*(stateJson: JsonNode): Result[JsonNode, string] {.raises: [].} =
  ## The persisted display block: `reportJson.display` (the writer's
  ## placement), with the root-level `display` accepted as the same
  ## contract's historical placement. Neither -> fail-closed error.
  if stateJson.isNil or stateJson.kind != JObject:
    return err("proof state is not a JSON object")
  let nested = stateJson{"reportJson"}{"display"}
  if not nested.isNil and nested.kind == JObject:
    return ok(nested)
  let flat = stateJson{"display"}
  if not flat.isNil and flat.kind == JObject:
    return ok(flat)
  err("missing reportJson.display block (fail-closed)")

func selectReportableUnits*(stateJson: JsonNode): Result[seq[ReportableUnit], string] {.raises: [].} =
  ## The full fail-closed input gate: display presence, display schema
  ## identity, the reportability conjunction, and the findingEvidence
  ## consumption. The counterexample, the quartet payload digest and the
  ## subject pin come ONLY from the state root's findingEvidence block keyed
  ## by targetSymbol — a reportable unit without that block keeps an honestly
  ## empty counterexample (evidenceMissing) and is gated before READY by the
  ## orchestrator (§11: the common four evidence elements are a reporting
  ## precondition). A malformed evidence block fails closed.
  let displayRes = selectDisplayBlock(stateJson)
  if displayRes.isErr:
    return err(displayRes.error)
  let display = displayRes.get()
  let version = display{"schemaVersion"}.getStr("")
  if version != bugVerdictDisplaySchemaVersionV3:
    return err("display schemaVersion '" & version & "' != contract '" &
      bugVerdictDisplaySchemaVersionV3 & "' (fail-closed)")
  let unitsNode = display{"units"}
  if unitsNode.isNil or unitsNode.kind != JArray:
    return err("display.units is missing or not an array (fail-closed)")
  var reportable: seq[ReportableUnit] = @[]
  for unitNode in unitsNode.items:
    if unitNode.isNil or unitNode.kind != JObject:
      continue
    var unit = parseReportableUnit(unitNode)
    if isReportableUnit(unit.bugAttribution, unit.propositionVerdict):
      let evNode = stateJson{"findingEvidence"}{unit.targetSymbol}
      if evNode.isNil:
        unit.evidenceMissing = true
      else:
        let evidenceRes = parseFindingEvidence(evNode)
        if evidenceRes.isErr:
          return err("findingEvidence for '" & unit.targetSymbol & "': " &
            evidenceRes.error)
        let evidence = evidenceRes.get()
        unit.claimOutcome = evidence.claimOutcome
        unit.rowStatus = evidence.rowStatus
        unit.machineVerdict = evidence.machineVerdict
        unit.machineEstablished = evidence.machineEstablished
        unit.subjectCommit = evidence.subjectCommit
        unit.subjectBlob = evidence.subjectBlob
        unit.quartetPayloadDigest = evidence.quartetPayloadDigest
        let (norm, raw) = normalizeEvidenceCounterexample(evidence.counterExampleRaw)
        unit.normalized = norm
        unit.rawQuartet = raw
      reportable.add(unit)
  if reportable.len == 0:
    return err("no reportable finding (fail-closed: UNKNOWN/NOT_DISPROVED " &
      "units are never reported upstream)")
  ok(reportable)

# ---------------------------------------------------------------------------
# Pure: overlay facts + clause algebra (the law content stays overlay DATA)
# ---------------------------------------------------------------------------

func clauseCallName*(clause: string): string {.raises: [].} =
  ## The identifier immediately before the clause's first '(' — e.g.
  ## "bvSliceLenActual(e) == (e - 1)" -> "bvSliceLenActual"; "" when the
  ## clause is not a named call form.
  let open = clause.find('(')
  if open <= 0:
    return ""
  var start = open
  while start > 0 and clause[start - 1] in {'A'..'Z', 'a'..'z', '0'..'9', '_'}:
    dec start
  if start == open:
    return ""
  clause[start ..< open]

func clauseVarName*(clause: string): string {.raises: [].} =
  let open = clause.find('(')
  if open < 0:
    return ""
  let close = clause.find(')', open + 1)
  if close < 0:
    return ""
  clause[open + 1 ..< close].strip()

func evalLinearRhs*(rhs: string; varName: string; value: int): Option[int] {.raises: [].} =
  ## Evaluates the single-variable linear forms the overlay IR uses:
  ## "<v>", "<v> - K", "<v> + K" (optionally parenthesized). Anything else
  ## evaluates to none — never guessed.
  let s = rhs.strip()
  let inner =
    if s.startsWith("(") and s.endsWith(")"):
      s[1 ..< s.len - 1].strip()
    else:
      s
  if inner == varName:
    return some(value)
  for op in [" - ", " + "]:
    let prefix = varName & op
    if inner.startsWith(prefix):
      let tail = inner[prefix.len ..< inner.len].strip()
      let k = strictParseInt(tail)
      if k.isErr():
        return none(int)
      if op == " - ":
        return some(value - k.get())
      return some(value + k.get())
  none(int)

func evalClauseValue*(clause: string; varName: string; value: int): Option[int] {.raises: [].} =
  ## "bvSliceLenActual(e) == (e - 1)" at e=4 -> some(3).
  let sep = "=="
  let p = clause.find(sep)
  if p < 0:
    return none(int)
  evalLinearRhs(clause[p + sep.len ..< clause.len], varName, value)

func pinnedByte*(grounding: string): string {.raises: [].} =
  ## "b pinned at 1" -> "1" (first integer after the marker; "" when absent).
  const marker = "pinned at "
  let p = grounding.find(marker)
  if p < 0:
    return ""
  var i = p + marker.len
  var digits = ""
  while i < grounding.len and grounding[i] in {'0'..'9'}:
    digits.add(grounding[i])
    inc i
  digits

func defectLawClause*(clauses: seq[string]; carrierNames: seq[string];
    pinnedB: string): string {.raises: [].} =
  ## The adopted law for the defect carrier: a non-carrier named clause. When
  ## the carrier grounding pins a byte value, the law whose name ends with
  ## that value is selected (the overlay family's Law<b> convention);
  ## otherwise the unique law clause; otherwise "" (never guessed).
  var laws: seq[string] = @[]
  for clause in clauses:
    let name = clauseCallName(clause)
    if name.len == 0:
      continue
    var isCarrier = false
    for cn in carrierNames:
      if cn == name:
        isCarrier = true
        break
    if not isCarrier:
      laws.add(clause)
  if laws.len == 1:
    return laws[0]
  if pinnedB.len > 0:
    for clause in laws:
      if clauseCallName(clause).endsWith(pinnedB):
        return clause
  ""

func extractOverlayFacts*(overlay: JsonNode; unit: ReportableUnit): OverlayFacts {.raises: [].} =
  var facts = OverlayFacts()
  let subject = overlay{"subject"}
  facts.requestedRepository = extractOwnerRepo(subject{"repository"}.getStr(""))
  facts.commit = subject{"commit"}.getStr("")
  facts.blobSha256 = subject{"blobSha256"}.getStr("")
  facts.clauses = jsonSeqOfStrings(overlay{"canonicalSpecIR"})
  let overlaySpecId = overlay{"specId"}.getStr("")
  facts.specId = if overlaySpecId.len > 0: overlaySpecId else: unit.specId
  facts.ruleId = overlay{"ruleId"}.getStr("")
  facts.ruleVersion = overlay{"ruleVersion"}.getStr("")
  let overlayModule = subject{"module"}.getStr("")
  let sepIdx = unit.targetSymbol.rfind("::")
  if sepIdx > 0:
    if overlayModule.len > 0:
      facts.moduleName = overlayModule
    else:
      facts.moduleName = unit.targetSymbol[0 ..< sepIdx]
    facts.symbol = unit.targetSymbol[sepIdx + 2 ..< unit.targetSymbol.len]
  else:
    facts.moduleName = overlayModule
    facts.symbol = unit.targetSymbol
  let carriers = overlay{"carriers"}
  if not carriers.isNil and carriers.kind == JArray:
    for c in carriers.items:
      let name = c{"name"}.getStr("")
      if name.len == 0:
        continue
      facts.carrierNames.add(name)
      let groundingSym = c{"groundingSymbol"}.getStr("")
      if c{"kind"}.getStr("") == "defect" and facts.defectCarrier.len == 0 and
          (groundingSym.len == 0 or groundingSym == facts.symbol):
        facts.defectCarrier = name
        for clause in facts.clauses:
          if clauseCallName(clause) == name:
            facts.actualClause = clause
            break
  var pinnedB = ""
  if facts.defectCarrier.len > 0 and not carriers.isNil and carriers.kind == JArray:
    for c in carriers.items:
      if c{"name"}.getStr("") == facts.defectCarrier:
        pinnedB = pinnedByte(c{"grounding"}.getStr(""))
        break
  facts.lawClause = defectLawClause(facts.clauses, facts.carrierNames, pinnedB)
  facts

# ---------------------------------------------------------------------------
# Pure: identity — findingKey, evidenceDigest, legacy v1 fingerprint
# ---------------------------------------------------------------------------

func canonicalSpecIrDigest*(clauses: seq[string]): string {.raises: [].} =
  ## sha256 over the canonicalSpecIR clause array joined canonically
  ## (docs/spec/upstream_reporting_contract.md). Clause order is semantic.
  sha256Hex(clauses.join("\n"))

func composeFindingKey*(resolvedRepository, targetSymbol: string;
    specId, ruleId, ruleVersion, specIrDigest: string): string {.raises: [].} =
  ## The v2 finding identity (contract §4): canonical JSON (sorted keys at
  ## every level — decision_algebra.canonicalSha256) over the RESOLVED
  ## repository, the subject, and the adopted proposition identity. The
  ## counterexample is evidence, not identity — it never enters this
  ## projection — and timestamps, run IDs, paths, claim/evidence IDs, commit
  ## and blob SHAs are structurally excluded. One defect -> one findingKey
  ## across runs and evidence reinforcement.
  canonicalSha256(%*{
    "repository": resolvedRepository,
    "subject": targetSymbol,
    "proposition": {
      "specId": specId,
      "ruleId": ruleId,
      "ruleVersion": ruleVersion,
      "canonicalSpecIRDigest": specIrDigest}})

func composeEvidenceDigest*(claimOutcome, machineVerdict, rowStatus,
    quartetPayloadDigest: string; machineEstablished: bool;
    normalized: seq[string]; subjectCommit, subjectBlob: string): string {.
    raises: [].} =
  ## The evidence integrity projection (contract §4): canonical JSON over the
  ## engine-observed evidence plus the normalized counterexample and the
  ## subject pin. Reinforcing evidence moves THIS digest; the findingKey
  ## above stays invariant.
  canonicalSha256(%*{
    "claimOutcome": claimOutcome,
    "machineVerdict": machineVerdict,
    "rowStatus": rowStatus,
    "quartetPayloadDigest": quartetPayloadDigest,
    "machineEstablished": machineEstablished,
    "counterexample": normalized,
    "subjectCommit": subjectCommit,
    "subjectBlob": subjectBlob})

func composeReportFingerprint*(resolvedRepository, targetSymbol: string;
    specId, ruleId, ruleVersion, specIrDigest: string;
    normalized: seq[string]): string {.raises: [].} =
  ## The v1 report fingerprint expression (contract §4 legacyFingerprints:
  ## the findingKey identity plus the counterexample member) — RETAINED only
  ## as the legacy identity definition: the §6 migration recomputes it when a
  ## legacy receipt carries no reportFingerprint field. The ledger identity
  ## is composeFindingKey; no live reporting path keys on this value.
  canonicalSha256(%*{
    "repository": resolvedRepository,
    "subject": targetSymbol,
    "proposition": {
      "specId": specId,
      "ruleId": ruleId,
      "ruleVersion": ruleVersion,
      "canonicalSpecIRDigest": specIrDigest},
    "counterexample": normalized})

func legacySubjectIdentity*(r: UpstreamReceipt): string {.raises: [].} =
  ## A receipt's subject identity reconstructed in the findingKey `subject`
  ## spelling (`module::symbol`; bare symbol when the module is absent).
  if r.module.len > 0 and r.symbol.len > 0:
    r.module & "::" & r.symbol
  else:
    r.symbol

func legacyReceiptMatchesIdentity*(r: UpstreamReceipt; resolvedRepository,
    targetSymbol, specId, ruleId, ruleVersion, specIrDigest: string): bool {.
    raises: [].} =
  ## §6: the legacy lookup's identity triple — resolved repository, subject,
  ## and proposition (specId/ruleId/ruleVersion/canonicalSpecIRDigest) in
  ## canonical (exact) equality. v1 receipts only: a v2-schema receipt keyed
  ## under a legacy filename would contradict its own findingKey-named file.
  r.schemaVersion == upstreamReceiptSchemaVersionV1 and
    r.resolvedRepository == resolvedRepository and
    legacySubjectIdentity(r) == targetSymbol and
    r.specId == specId and
    r.ruleId == ruleId and
    r.ruleVersion == ruleVersion and
    r.canonicalSpecIrDigest == specIrDigest

func mergeLegacyFingerprints*(existing, additional: seq[string]): seq[string] {.
    raises: [].} =
  ## Sorted, deduped union — deterministic across runs regardless of
  ## directory-scan order (§0.2 determinism).
  result = existing
  for fp in additional:
    if fp.len > 0 and fp notin result:
      result.add(fp)
  result.sort(cmp)

func legacyReceiptFingerprints*(legacy: UpstreamReceipt; resolvedRepository,
    targetSymbol, specId, ruleId, ruleVersion, specIrDigest: string): seq[string] {.
    raises: [].} =
  ## The v1 fingerprint(s) a matched legacy receipt carries: the parsed
  ## reportFingerprint field (mapped at v1 parse time), with a deterministic
  ## recomputation as the fallback for a receipt missing the field.
  if legacy.legacyFingerprints.len > 0:
    return legacy.legacyFingerprints
  @[composeReportFingerprint(resolvedRepository, legacySubjectIdentity(legacy),
    specId, ruleId, ruleVersion, specIrDigest, legacy.normalized)]

func identityAnchors*(findingKeyVal: string; legacyFingerprints: seq[string]):
    seq[string] {.raises: [].} =
  ## The remote identity anchors of one finding: the findingKey first, then
  ## every legacy v1 fingerprint — pre-v2 issues embed the
  ## `reportFingerprint:` line, so dedup must search those values too.
  if findingKeyVal.len > 0:
    result.add(findingKeyVal)
  for fp in legacyFingerprints:
    if fp.len > 0 and fp != findingKeyVal and fp notin result:
      result.add(fp)

func bodyCarriesIdentity*(body: string; anchors: seq[string]): bool {.raises: [].} =
  ## True when the issue body embeds ANY of the finding's identity anchors —
  ## the confirmation that a remote hit is OUR finding (findingKey for v2
  ## bodies, the v1 reportFingerprint line for pre-v2 bodies).
  for anchor in anchors:
    if body.contains(anchor):
      return true
  false

# ---------------------------------------------------------------------------
# Pure: gh outcome classification + URL parsing
# ---------------------------------------------------------------------------

func looksLikeTimeout*(output: string): bool {.raises: [].} =
  let low = output.toLowerAscii()
  low.contains("timed out") or low.contains("timeout") or
    low.contains("context deadline") or low.contains("client.timeout")

func classifyGhOutcome*(exitCode: int; output: string): GhOutcomeKind {.raises: [].} =
  ## The gh failure table: 127 -> missing binary; HTTP 401 -> auth;
  ## 403/404/410/429 -> the contract's blocked reasons; any other 4xx ->
  ## rejected (confirmed non-creation); 5xx / timeout / anything else
  ## ambiguous -> creation state unknown (never read as confirmed
  ## non-creation).
  if exitCode == 0:
    return gokOk
  if exitCode == 127:
    return gokGhMissing
  let low = output.toLowerAscii()
  if low.contains("http 401"):
    return gokAuth
  if low.contains("http 403"):
    return gokHttp403
  if low.contains("http 404"):
    return gokHttp404
  if low.contains("http 410"):
    return gokHttp410
  if low.contains("http 429"):
    ## §8: 429 = rate limited (primary/secondary) — classified BEFORE the
    ## generic "http 4" rejection catch: the status code is itself the
    ## throttle signal, so it is a transient restriction even without
    ## rate-limit tokens in the output, never confirmed non-creation.
    return gokHttp429
  if low.contains("http 4"):
    return gokRejected
  if low.contains("http 5"):
    return gokAmbiguous
  if looksLikeTimeout(low):
    return gokTimeout
  gokAmbiguous

func ghOutputIndicatesRateLimit*(output: string): bool {.raises: [].} =
  ## The rate-limit indicators in gh output, case-insensitive: "rate limit"
  ## (also covering the "secondary rate limit" / "api rate limit" spellings
  ## it is a substring of), "too many requests", "retry after". GitHub's
  ## official REST docs state a primary/secondary rate limit answers 403 or
  ## 429 (docs.github.com/en/rest/using-the-rest-api/
  ## rate-limits-for-the-rest-api), so a 403 carrying these tokens is a
  ## rate-limit restriction — recorded honestly, never as a permission denial.
  let low = output.toLowerAscii()
  low.contains("rate limit") or low.contains("too many requests") or
    low.contains("retry after")

func blockedReasonFor*(kind: GhOutcomeKind; output = ""): string {.raises: [].} =
  ## The contract's blocked reason for a classified gh outcome. `output`
  ## (the merged gh stdout+stderr) sharpens 403 honesty: with rate-limit
  ## tokens it records the rate-limit restriction; without them (or with
  ## no output) it stays the permission/creation-restriction reason. A 429
  ## is always the rate-limit restriction (§8) — tokens in the output are
  ## not required.
  case kind
  of gokOk: ""
  of gokGhMissing, gokAuth: blockedGhAuth
  of gokHttp403:
    (if ghOutputIndicatesRateLimit(output): blocked403RateLimited else: blocked403)
  of gokHttp404: blocked404
  of gokHttp410: blocked410
  of gokHttp429: blocked429
  of gokRejected: failedConfirmed
  of gokTimeout, gokAmbiguous: ""

func extractIssueUrl*(output: string): tuple[number: int; url: string] {.raises: [].} =
  ## The created-issue URL gh prints to stdout:
  ## https://github.com/<owner>/<repo>/issues/<N>.
  result = (0, "")
  const marker = "/issues/"
  var idx = 0
  while true:
    let m = output.find(marker, idx)
    if m < 0:
      return
    let start = output.rfind("http", 0, m)
    if start < 0:
      idx = m + marker.len
      continue
    var stop = m + marker.len
    while stop < output.len and output[stop] in {'0'..'9'}:
      inc stop
    if stop == m + marker.len:
      idx = m + marker.len
      continue
    let numStr = output[m + marker.len ..< stop]
    let n = safeParseInt(numStr)
    if n.isOk():
      result = (n.get(), output[start ..< stop])
    else:
      result = (0, "")
    return

func issueNumberFromUrl*(url: string): int {.raises: [].} =
  extractIssueUrl(url).number

proc parseIssueView*(output: string): Result[tuple[number: int; url: string;
    state: string; body: string; createdAt: string], string] {.raises: [].} =
  ## `gh issue view --json number,url,state[,body],createdAt` payload. The
  ## createdAt timestamp is the §6 backfill source for a migrated legacy
  ## receipt's submittedAt (GitHub is the authority for that instant).
  try:
    let n = parseJson(output)
    if n.isNil or n.kind != JObject:
      return err("issue view payload is not a JSON object")
    ok((n{"number"}.getInt(0), n{"url"}.getStr(""),
        n{"state"}.getStr(""), n{"body"}.getStr(""),
        n{"createdAt"}.getStr("")))
  except CatchableError as e:
    err("unparsable issue view payload: " & e.msg)

proc parseIssueRefList*(output: string): Result[seq[tuple[number: int; url: string]], string] {.raises: [].} =
  ## `gh search issues --json number,url` / `gh issue list --json number,url,state`
  ## payload (a JSON array of issue references).
  try:
    let n = parseJson(output)
    if n.isNil or n.kind != JArray:
      return err("issue list payload is not a JSON array")
    var refs: seq[tuple[number: int; url: string]] = @[]
    for it in n.items:
      refs.add((it{"number"}.getInt(0), it{"url"}.getStr("")))
    ok(refs)
  except CatchableError as e:
    err("unparsable issue list payload: " & e.msg)

proc decodeGhContentsJson*(output: string): Result[string, string] {.raises: [].} =
  ## `gh api repos/<r>/contents/<path>` payload (base64 content) -> file bytes.
  try:
    let n = parseJson(output)
    if n.isNil or n.kind != JObject:
      return err("contents payload is not a JSON object")
    if n{"encoding"}.getStr("") != "base64":
      return err("unsupported contents encoding: " & n{"encoding"}.getStr(""))
    let content = n{"content"}.getStr("").replace("\n", "").replace("\r", "")
    if content.len == 0:
      return err("empty contents payload")
    ok(decode(content))
  except CatchableError as e:
    err("unparsable contents payload: " & e.msg)

func extractTemplateSections*(body: string): seq[string] {.raises: [].} =
  ## "## <header>" lines, in document order — the target repo's bug-report
  ## structure the composed body mirrors.
  for line in body.splitLines():
    let t = line.strip()
    if t.startsWith("## ") and t.len > 3:
      result.add(t[3 ..< t.len].strip())

# ---------------------------------------------------------------------------
# Pure: issue title/body composition
# ---------------------------------------------------------------------------

func deriveReproSnippet*(facts: OverlayFacts; normalized: seq[string]): seq[string] {.raises: [].} =
  ## The "To reproduce" snippet. The committed bytesview overlay family gets a
  ## concrete runnable snippet whose numbers are projected from the overlay's
  ## own clauses at the recorded binding; every other subject gets a
  ## self-contained replay block quoting the overlay data verbatim. No
  ## proposition content is hardcoded — the law/model clauses stay DATA.
  let binding = if normalized.len > 0: normalized[0] else: ""
  let varName = clauseVarName(facts.actualClause)
  var eVal = none(int)
  if varName.len > 0 and binding.len > 0 and bindingKey(binding) == varName:
    let pv = strictParseInt(bindingValue(binding))
    if pv.isOk():
      eVal = some(pv.get())
  if facts.moduleName.endsWith("bytesview.nim") and eVal.isSome:
    let e = $eVal.get()
    let observed =
      if facts.actualClause.len > 0:
        evalClauseValue(facts.actualClause, varName, eVal.get())
      else:
        none(int)
    let expected =
      if facts.lawClause.len > 0:
        evalClauseValue(facts.lawClause, varName, eVal.get())
      else:
        none(int)
    var lines: seq[string] = @[]
    lines.add("```nim")
    lines.add("import " & facts.moduleName.replace(".nim", ""))
    lines.add("")
    lines.add("let bv = BytesView.init(@[byte 1, 2, 3, 4, 5, 6])")
    lines.add("let sliced = bv.toOpenArray(1, " & e & ")  # view-relative slice, e = " & e)
    lines.add("echo sliced.len")
    if observed.isSome and expected.isSome:
      lines.add("# observed: " & $observed.get() & "  expected: " & $expected.get() &
        " (inclusive view-relative slice convention)")
    lines.add("```")
    return lines
  var lines: seq[string] = @[]
  lines.add("```")
  lines.add("pinned replay of the recorded counterexample:")
  lines.add("  module: " & facts.moduleName & " :: " & facts.symbol)
  if facts.commit.len > 0:
    lines.add("  commit: " & facts.commit)
  if binding.len > 0:
    lines.add("  binding: " & binding)
  if facts.actualClause.len > 0:
    lines.add("  observed model: " & facts.actualClause)
  if facts.lawClause.len > 0:
    lines.add("  adopted law: " & facts.lawClause)
  lines.add("```")
  lines

func composeIssueTitle*(facts: OverlayFacts; normalized: seq[string]): string {.raises: [].} =
  ## Concise deterministic title. When the overlay's law/model clauses are
  ## evaluable at the recorded binding, the observed-vs-expected numbers are
  ## projected from overlay DATA.
  let binding = if normalized.len > 0: normalized[0] else: ""
  let varName = clauseVarName(facts.actualClause)
  var title = ""
  if varName.len > 0 and binding.len > 0 and bindingKey(binding) == varName:
    var eVal = none(int)
    let pv = strictParseInt(bindingValue(binding))
    if pv.isOk():
      eVal = some(pv.get())
    if eVal.isSome and facts.actualClause.len > 0 and facts.lawClause.len > 0:
      let observed = evalClauseValue(facts.actualClause, varName, eVal.get())
      let expected = evalClauseValue(facts.lawClause, varName, eVal.get())
      if observed.isSome and expected.isSome:
        title = facts.symbol & ": observed " & $observed.get() &
          " where the adopted law expects " & $expected.get() &
          " at " & binding & " (" & facts.ruleId & ")"
  if title.len == 0:
    let bindings = normalized.join(", ")
    title = facts.symbol & ": adopted proposition violated" &
      (if bindings.len > 0: " under binding " & bindings else: "") &
      " (" & facts.ruleId & ")"
  if title.len > 140:
    title = title[0 ..< 137] & "..."
  title

func composeIssueBody*(facts: OverlayFacts; unit: ReportableUnit;
    requestedRepository, resolvedRepository: string; identity: FindingIdentity;
    sections: seq[string]): string {.raises: [].} =
  ## The self-contained issue body: the target repo's bug-report structure
  ## (mirrored from its template when present), the violated proposition
  ## stated plainly, an EXPLICIT requirement basis (the INFERRED disclaimer
  ## for BUG_SUSPECTED — never a claimed project promise), uncertainty, and
  ## the machine-searchable identity lines — findingKey (§9 anchor),
  ## evidenceDigest, and the legacy v1 fingerprints when present (pre-v2
  ## dedup searches those values). No Axiom engine/certificate internals
  ## (display digests, machine-state spellings, grounds validation prose)
  ## ever enter the body.
  var b = ""
  for section in sections:
    let key = section.toLowerAscii()
    if key in ["problem", "description"]:
      b.add("## " & section & "\n\n")
      b.add("Subject: `" & facts.moduleName & "::" & facts.symbol & "`\n")
      b.add("Repository: " & resolvedRepository)
      if requestedRepository.len > 0 and requestedRepository != resolvedRepository:
        b.add(" (requested as " & requestedRepository & " — canonical after redirect)")
      b.add("\n")
      if facts.commit.len > 0:
        b.add("Commit: " & facts.commit & "\n")
      if facts.moduleName.len > 0 and facts.blobSha256.len > 0:
        b.add("Module: " & facts.moduleName & " (sha256: " & facts.blobSha256 & ")\n")
      b.add("Adopted proposition (spec " & facts.specId & ", rule " & facts.ruleId & "):\n")
      if facts.actualClause.len > 0:
        b.add("- observed model: `" & facts.actualClause & "`\n")
      if facts.lawClause.len > 0:
        b.add("- adopted law: `" & facts.lawClause & "`\n")
      if unit.normalized.len > 0:
        b.add("- recorded binding: " & unit.normalized.join(", ") & "\n")
      b.add("\n")
    elif key == "impact":
      b.add("## " & section & "\n\n")
      b.add("Behavior at the recorded binding differs from the adopted law " &
        "without any error signal; callers relying on the law's convention " &
        "receive a wrong result silently.\n\n")
    elif key in ["to reproduce", "steps to reproduce", "reproduction steps"]:
      b.add("## " & section & "\n\n")
      for line in deriveReproSnippet(facts, unit.normalized):
        b.add(line & "\n")
      b.add("\n")
    elif key in ["expected behavior", "expected"]:
      b.add("## " & section & "\n\n")
      if facts.lawClause.len > 0:
        b.add("Under the adopted law `" & facts.lawClause & "` the expected " &
          "result at the recorded binding is fixed by the law; the observed " &
          "model deviates (see " & sections[0] & ").\n\n")
      else:
        b.add("The adopted proposition (spec " & facts.specId & ") is " &
          "violated at the recorded binding.\n\n")
    else:
      b.add("## " & section & "\n\n")
      b.add("Adopted proposition (spec " & facts.specId & ", rule " &
        facts.ruleId & ") violated at the recorded binding.\n\n")
  b.add("## Requirement basis\n\n")
  if unit.bugAttribution == "BUG_SUSPECTED":
    b.add("The expected behavior stated in this report is INFERRED and " &
      "adopted by the verifying run. The project has NOT been shown to " &
      "guarantee this behavior — this report does not claim such a promise. " &
      "Requirement source status: " & unit.requirementSourceStatus & ".\n\n")
  else:
    b.add("The violated proposition was measured against the project's own " &
      "recorded requirement basis (status: " & unit.requirementSourceStatus &
      ") and confirmed by a replayed counterexample on the pinned commit.\n\n")
  b.add("## Uncertainty\n\n")
  if unit.uncertaintyKinds.len > 0:
    b.add("- uncertainty kinds: " & unit.uncertaintyKinds.join(", ") & "\n")
  b.add("- requirement source status: " & unit.requirementSourceStatus & "\n")
  b.add("\n")
  b.add("findingKey: " & identity.findingKey & "\n")
  b.add("evidenceDigest: " & identity.evidenceDigest & "\n")
  if identity.legacyFingerprints.len > 0:
    b.add("legacyFingerprints: " & identity.legacyFingerprints.join(", ") & "\n")
  b

# ---------------------------------------------------------------------------
# Pure: receipt projection (the ledger SSOT record)
# ---------------------------------------------------------------------------

func receiptToJson*(r: UpstreamReceipt): JsonNode {.raises: [].} =
  var attempts = newJArray()
  for a in r.attempts:
    attempts.add(%*{
      "ts": a.ts,
      "phase": a.phase,
      "outcome": a.outcome,
      "candidateUrl": a.candidateUrl})
  var issue: JsonNode = newJNull()
  if r.issueNumber > 0:
    issue = %*{"number": r.issueNumber, "url": r.issueUrl}
  var blocked: JsonNode = newJNull()
  if r.blockedReason.len > 0:
    blocked = %r.blockedReason
  var submittedAt: JsonNode = newJNull()
  if r.submittedAt.len > 0:
    submittedAt = %r.submittedAt
  %*{
    "schemaVersion": r.schemaVersion,
    "findingKey": r.findingKey,
    "evidenceDigest": r.evidenceDigest,
    "legacyFingerprints": r.legacyFingerprints,
    "status": $r.status,
    "verdict": {
      "propositionVerdict": r.propositionVerdict,
      "requirementSourceStatus": r.requirementSourceStatus,
      "bugAttribution": r.bugAttribution},
    "subject": {
      "requestedRepository": r.requestedRepository,
      "resolvedRepository": r.resolvedRepository,
      "commit": r.commit,
      "module": r.module,
      "symbol": r.symbol,
      "blobSha256": r.blobSha256},
    "proposition": {
      "specId": r.specId,
      "ruleId": r.ruleId,
      "ruleVersion": r.ruleVersion,
      "specRelPath": r.specRelPath,
      "canonicalSpecIRDigest": r.canonicalSpecIrDigest},
    "counterexample": {
      "normalized": r.normalized,
      "rawQuartet": r.rawQuartet},
    "issue": issue,
    "blockedReason": blocked,
    "attempts": attempts,
    "submittedAt": submittedAt}

func receiptFromJson*(n: JsonNode): Result[UpstreamReceipt, string] {.raises: [].} =
  ## Accepts the v2 authoritative receipt and the v1 schema (§10: a v1
  ## receipt is a read-only migration source). A v1 payload's
  ## `reportFingerprint` maps into `legacyFingerprints` (§6 re-linking
  ## record); anything else fails closed.
  if n.isNil or n.kind != JObject:
    return err("receipt is not a JSON object")
  let schemaVersion = n{"schemaVersion"}.getStr("")
  if schemaVersion != upstreamReceiptSchemaVersion and
      schemaVersion != upstreamReceiptSchemaVersionV1:
    return err("receipt schemaVersion '" & schemaVersion &
      "' is neither '" & upstreamReceiptSchemaVersion & "' nor '" &
      upstreamReceiptSchemaVersionV1 & "'")
  var legacyFingerprints: seq[string] = @[]
  if schemaVersion == upstreamReceiptSchemaVersionV1:
    let v1Fingerprint = n{"reportFingerprint"}.getStr("")
    if v1Fingerprint.len > 0:
      legacyFingerprints.add(v1Fingerprint)
  else:
    legacyFingerprints = jsonSeqOfStrings(n{"legacyFingerprints"})
  let statusStr = n{"status"}.getStr("")
  var status: UpstreamReportStatus
  try:
    status = parseEnum[UpstreamReportStatus](statusStr)
  except CatchableError:
    return err("unknown receipt status: " & statusStr)
  var attempts: seq[UpstreamAttempt] = @[]
  let attemptsNode = n{"attempts"}
  if not attemptsNode.isNil and attemptsNode.kind == JArray:
    for a in attemptsNode.items:
      attempts.add(UpstreamAttempt(
        ts: a{"ts"}.getStr(""),
        phase: a{"phase"}.getStr(""),
        outcome: a{"outcome"}.getStr(""),
        candidateUrl: a{"candidateUrl"}.getStr("")))
  var issueNumber = 0
  var issueUrl = ""
  let issue = n{"issue"}
  if not issue.isNil and issue.kind == JObject:
    issueNumber = issue{"number"}.getInt(0)
    issueUrl = issue{"url"}.getStr("")
  var blockedReason = ""
  let blocked = n{"blockedReason"}
  if not blocked.isNil and blocked.kind == JString:
    blockedReason = blocked.getStr("")
  var submittedAt = ""
  let submittedNode = n{"submittedAt"}
  if not submittedNode.isNil and submittedNode.kind == JString:
    submittedAt = submittedNode.getStr("")
  ok(UpstreamReceipt(
    schemaVersion: schemaVersion,
    findingKey: n{"findingKey"}.getStr(""),
    evidenceDigest: n{"evidenceDigest"}.getStr(""),
    legacyFingerprints: legacyFingerprints,
    status: status,
    propositionVerdict: n{"verdict"}{"propositionVerdict"}.getStr(""),
    requirementSourceStatus: n{"verdict"}{"requirementSourceStatus"}.getStr(""),
    bugAttribution: n{"verdict"}{"bugAttribution"}.getStr(""),
    requestedRepository: n{"subject"}{"requestedRepository"}.getStr(""),
    resolvedRepository: n{"subject"}{"resolvedRepository"}.getStr(""),
    commit: n{"subject"}{"commit"}.getStr(""),
    module: n{"subject"}{"module"}.getStr(""),
    symbol: n{"subject"}{"symbol"}.getStr(""),
    blobSha256: n{"subject"}{"blobSha256"}.getStr(""),
    specId: n{"proposition"}{"specId"}.getStr(""),
    ruleId: n{"proposition"}{"ruleId"}.getStr(""),
    ruleVersion: n{"proposition"}{"ruleVersion"}.getStr(""),
    specRelPath: n{"proposition"}{"specRelPath"}.getStr(""),
    canonicalSpecIrDigest: n{"proposition"}{"canonicalSpecIRDigest"}.getStr(""),
    normalized: jsonSeqOfStrings(n{"counterexample"}{"normalized"}),
    rawQuartet: jsonSeqOfStrings(n{"counterexample"}{"rawQuartet"}),
    issueNumber: issueNumber,
    issueUrl: issueUrl,
    blockedReason: blockedReason,
    attempts: attempts,
    submittedAt: submittedAt))

func baseReceipt*(unit: ReportableUnit; facts: OverlayFacts;
    identity: FindingIdentity; requested, resolved, specIrDigest: string):
    UpstreamReceipt {.raises: [].} =
  ## The fresh v2 receipt projection. The identity block (findingKey,
  ## evidenceDigest, legacyFingerprints) comes from the caller's
  ## FindingIdentity; the subject pin (commit + blob) is supplied by the
  ## findingEvidence block, not the overlay. The status starts READY — every
  ## caller overrides it before persistence.
  UpstreamReceipt(
    schemaVersion: upstreamReceiptSchemaVersion,
    findingKey: identity.findingKey,
    evidenceDigest: identity.evidenceDigest,
    legacyFingerprints: identity.legacyFingerprints,
    status: ursReady,
    propositionVerdict: unit.propositionVerdict,
    requirementSourceStatus: unit.requirementSourceStatus,
    bugAttribution: unit.bugAttribution,
    requestedRepository: requested,
    resolvedRepository: resolved,
    commit: unit.subjectCommit,
    module: facts.moduleName,
    symbol: facts.symbol,
    blobSha256: unit.subjectBlob,
    specId: facts.specId,
    ruleId: facts.ruleId,
    ruleVersion: facts.ruleVersion,
    specRelPath: unit.specRelPath,
    canonicalSpecIrDigest: specIrDigest,
    normalized: unit.normalized,
    rawQuartet: unit.rawQuartet)

func carryForwardReceiptEvidence*(fresh: var UpstreamReceipt;
    prior: UpstreamReceipt) {.raises: [].} =
  ## A re-run replaces the fingerprint-keyed ledger receipt (contract §10),
  ## but the replacement must never destroy prior evidence: the recorded
  ## submission timestamp, the structured issue identity (number+URL — the
  ## direct re-query anchor for every later transition, BLOCKED/RR/FAILED
  ## included), the full attempt history (incl. the reconciliation
  ## candidateUrl recovery input), and the verdict record of the ORIGINAL
  ## submission (contract §6 verdict succession — a migrated v1 record or
  ## the create-time projection; the fresh display projection can drift and
  ## never rewrites it) carry forward. A freshly verified submission
  ## timestamp (set by this run) wins over the prior one.
  if fresh.submittedAt.len == 0 and prior.submittedAt.len > 0:
    fresh.submittedAt = prior.submittedAt
  if fresh.issueNumber == 0 and prior.issueNumber > 0:
    fresh.issueNumber = prior.issueNumber
    fresh.issueUrl = prior.issueUrl
  if prior.propositionVerdict.len > 0:
    fresh.propositionVerdict = prior.propositionVerdict
  if prior.requirementSourceStatus.len > 0:
    fresh.requirementSourceStatus = prior.requirementSourceStatus
  if prior.bugAttribution.len > 0:
    fresh.bugAttribution = prior.bugAttribution
  fresh.attempts = prior.attempts & fresh.attempts

# ---------------------------------------------------------------------------
# Pure: CLI flag parsing + result projection
# ---------------------------------------------------------------------------

func parseUpstreamFlags*(args: seq[string]): Result[UpstreamCliFlags, string] {.raises: [].} =
  ## `ax report --upstream [--state-file <path>] [--dry-run] [--json]` —
  ## fail-closed on unknown options (never silently ignored).
  var flags = UpstreamCliFlags()
  var i = 0
  while i < args.len:
    if args[i] == "--upstream":
      inc i
    elif args[i] == "--json":
      flags.emitJson = true
      inc i
    elif args[i] == "--dry-run":
      flags.dryRun = true
      inc i
    elif args[i] == "--state-file":
      if i + 1 >= args.len:
        return err("--state-file requires a path argument")
      flags.stateFilePath = args[i + 1]
      inc i, 2
    else:
      return err("unknown option for `ax report --upstream`: " & args[i])
  ok(flags)

func unitOutcomeToJson*(o: UpstreamUnitOutcome): JsonNode {.raises: [].} =
  var issue: JsonNode = newJNull()
  if o.issueNumber > 0:
    issue = %*{"number": o.issueNumber, "url": o.issueUrl}
  %*{
    "targetSymbol": o.targetSymbol,
    "findingKey": o.findingKey,
    "status": $o.status,
    "blockedReason": o.blockedReason,
    "detail": o.detail,
    "issue": issue,
    "requestedRepository": o.requestedRepository,
    "resolvedRepository": o.resolvedRepository}

func upstreamExitCode*(outcomes: seq[UpstreamUnitOutcome]): int {.raises: [].} =
  ## 0 iff every unit reached a terminal-success state (READY preview,
  ## SUBMITTED, or DUPLICATE-link); BLOCKED / FAILED / RECONCILIATION_REQUIRED
  ## are reported truthfully with exit 1.
  for o in outcomes:
    case o.status
    of ursReady, ursSubmitted, ursDuplicate:
      discard
    else:
      return 1
  0

# ---------------------------------------------------------------------------
# gh command builders (pure — unit-tested shapes)
# ---------------------------------------------------------------------------

func ghRepoCmd*(requested: string): string {.raises: [].} =
  "gh api repos/" & shellQuote(requested)

func ghIssueViewCmd*(number: int; repo: string; includeBody: bool): string {.raises: [].} =
  ## createdAt is fetched on every view: the §6 legacy-migration backfill
  ## reuses the verification view's payload for the submittedAt source.
  let fields = if includeBody: "number,url,state,body,createdAt"
               else: "number,url,state,createdAt"
  "gh issue view " & $number & " -R " & shellQuote(repo) & " --json " & fields

func ghSearchCmd*(repo: string; fingerprint: string): string {.raises: [].} =
  "gh search issues --repo " & shellQuote(repo) & " --json number,url " &
    shellQuote(fingerprint)

func ghListCmd*(repo: string; fingerprint: string): string {.raises: [].} =
  "gh issue list -R " & shellQuote(repo) & " --search " & shellQuote(fingerprint) &
    " --json number,url,state"

func ghTemplateCmd*(resolved: string): string {.raises: [].} =
  "gh api repos/" & shellQuote(resolved) & "/contents/.github/ISSUE_TEMPLATE/bug_report.md"

func ghCreateCmd*(resolved: string; title: string; bodyFile: string): string {.raises: [].} =
  ## Non-interactive create: --title + --body-file skip the interactive
  ## template prompts.
  "gh issue create -R " & shellQuote(resolved) & " --title " & shellQuote(title) &
    " --body-file " & shellQuote(bodyFile)

# ---------------------------------------------------------------------------
# IO: adapters, clock, overlay, ledger
# ---------------------------------------------------------------------------

proc liveGhAdapter*(command: string): GhResult {.axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## One-shot gh execution, fail-closed semantics exactly like
  ## tools/merge_ruleset_drift_monitor.nim: merged stdout+stderr, exit code
  ## judged by the caller. An exec-environment failure (gh missing through
  ## the shell, fork failure) surfaces as exit 127.
  var output = ""
  var code = 127
  try:
    (output, code) = execCmdEx(command,
      options = {poStdErrToStdOut, poUsePath, poEvalCommand})
  except CatchableError:
    output = "gh exec failure: " & command
    code = 127
  GhResult(exitCode: code, output: output)

proc systemClock*(): string {.raises: [].} =
  try:
    now().utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'")
  except CatchableError:
    "1970-01-01T00:00:00Z"

proc loadSpecOverlay*(repoRoot: string; specRelPath: string): Result[JsonNode, string] {.axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if not safeSpecRelPath(specRelPath):
    return err("unsafe spec overlay path (fail-closed): " & specRelPath)
  let path = joinPath(joinPath(repoRoot, "config"), joinPath("spec", specRelPath))
  if not fileExists(path):
    return err("spec overlay not found (fail-closed): " & path)
  try:
    ok(parseFile(path))
  except CatchableError as e:
    err("spec overlay unparsable (fail-closed): " & e.msg)

proc ledgerReceiptPath*(ledgerDir: string; findingKey: string): string {.raises: [].} =
  ## §10: the authoritative receipt location — data/upstream_reports/<findingKey>.json.
  joinPath(ledgerDir, findingKey & ".json")

proc loadReceipt*(path: string): Result[Option[UpstreamReceipt], string] {.axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## None when absent; fail-closed error when present but unreadable (the
  ## single-writer dedup contract must never degrade into a blind create).
  if not fileExists(path):
    return ok(none(UpstreamReceipt))
  try:
    let parsed = parseFile(path)
    let receipt = receiptFromJson(parsed)
    if receipt.isErr:
      return err("ledger receipt unreadable (fail-closed): " & receipt.error)
    ok(some(receipt.get()))
  except CatchableError as e:
    err("ledger receipt unreadable (fail-closed): " & e.msg)

proc saveReceiptAtomic*(receipt: UpstreamReceipt; path: string): Result[void, string] {.axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Atomic single-writer receipt persistence: tmp + rename (the
  ## vault_manifest.nim / selection_state.nim pattern).
  let tmpPath = path & ".tmp"
  try:
    createDir(path.parentDir())
    writeFile(tmpPath, receiptToJson(receipt).pretty() & "\n")
    safeMoveFile(tmpPath, path)
    Result[void, string](ok: true)
  except CatchableError as e:
    try:
      if fileExists(tmpPath):
        removeFile(tmpPath)
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
    err("receipt write failed: " & e.msg)

proc loadLegacyReceipts*(ledgerDir: string; excludePath: string):
    Result[seq[tuple[path: string; receipt: UpstreamReceipt]], string] {.
    axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## §6 legacy lookup candidates: every readable receipt file in the ledger
  ## directory except the authoritative `<findingKey>.json` itself, sorted
  ## by path (deterministic scan order). An unreadable entry is a hard
  ## error (fail-closed) — a corrupt legacy receipt could carry the matching
  ## identity, and skipping it silently would license a duplicate create.
  var found: seq[tuple[path: string; receipt: UpstreamReceipt]] = @[]
  if not dirExists(ledgerDir):
    return ok(found)
  try:
    for kind, path in walkDir(ledgerDir):
      if kind != pcFile or path == excludePath or not path.endsWith(".json"):
        continue
      let loaded = loadReceipt(path)
      if loaded.isErr:
        return err(extractFilename(path) & ": " & loaded.error)
      if loaded.get().isSome:
        found.add((path, loaded.get().get()))
  except CatchableError as e:
    return err("legacy receipt scan failed: " & e.msg)
  found.sort(proc (a, b: tuple[path: string; receipt: UpstreamReceipt]): int =
    cmp(a.path, b.path))
  ok(found)

# ---------------------------------------------------------------------------
# Orchestrator
# ---------------------------------------------------------------------------

proc runUpstreamReport*(stateJson: JsonNode; cfg: UpstreamRunConfig; gh: GhAdapter;
    clock: Clock): Result[seq[UpstreamUnitOutcome], string] {.raises: [CatchableError],
    axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## The full pipeline per reportable unit:
  ##   units (fail-closed) -> findingEvidence gate (§11: no evidence, no
  ##   report — no gh call, no write) -> overlay -> gh preflight -> repository
  ##   resolution (redirect-following; requested+resolved recorded) ->
  ##   findingKey + evidenceDigest (§4 v2 identity) -> ledger read at
  ##   <findingKey>.json (§6 miss: legacy v1 receipt lookup by identity
  ##   triple — evidence succession, legacyFingerprints record, v2 rewrite;
  ##   multi-match -> fail-closed BLOCKED) -> prior-state safety (a READY
  ##   receipt can only be the pre-create intent left before a possible
  ##   crash — it never regenerates on an unconfirmed re-query, nor do
  ##   RR / FAILED(remote-unverifiable)) -> prior-identity re-query (direct
  ##   `gh issue view` of ANY recorded structured issue or attempt candidate
  ##   — search indexes are never trusted for dedup; regeneration is
  ##   forbidden while a prior identity stays unverifiable; a migrated
  ##   receipt's submittedAt backfills from the issue's created_at) -> remote
  ##   duplicate check over ALL identity anchors (findingKey + legacy
  ##   fingerprints; search + list; ALWAYS before any create) -> [dry-run:
  ##   truthful preview, NOTHING persisted] -> compose -> create -> verify ->
  ##   persist immediately.
  ## The state document arrives already loaded (the CLI wrapper owns the
  ## loadReportProofState identity re-validation); tests inject fixtures.
  let unitsRes = selectReportableUnits(stateJson)
  if unitsRes.isErr:
    return err("upstream report: " & unitsRes.error)
  let units = unitsRes.get()

  let repoRoot = cfg.repoRoot
  if repoRoot.len == 0 or not fileExists(joinPath(repoRoot, ".axiom_root")):
    return err("upstream report must be executed within an Axiom repository " &
      "worktree (.axiom_root not found at " & repoRoot & ")")

  var outcomes: seq[UpstreamUnitOutcome] = @[]
  var preflighted = false
  var preflightOk = false

  for u in units:
    var unit = u
    var attempts: seq[UpstreamAttempt] = @[]
    proc attempt(phase: string; outcome: string; candidateUrl: string = "") =
      attempts.add(UpstreamAttempt(
        ts: clock(),
        phase: phase,
        outcome: excerptOf(outcome),
        candidateUrl: candidateUrl))

    template persistAndRecord(receipt: UpstreamReceipt; ledgerPath: string;
                              outcomeBlocked: string; outcomeIssueNumber: int;
                              outcomeIssueUrl: string; outcomeDetail: string) =
      ## Persist the SSOT receipt, then record the unit outcome truthfully.
      ## Dry-run records the truthful preview outcome and never writes (and
      ## never fails for it). A persistence failure expands into a hard error
      ## carrying the receipt identity (`return` returns from the orchestrator):
      ## an SSOT write failure is never reported as terminal success.
      ## (Parameter names avoid the UpstreamUnitOutcome field names — template
      ## substitution would otherwise rewrite the constructor keys.)
      var detailLine = outcomeDetail
      var persistError = ""
      if cfg.dryRun:
        detailLine.add(" (dry-run — receipt not persisted)")
      else:
        let saved = saveReceiptAtomic(receipt, ledgerPath)
        if saved.isErr:
          persistError = saved.error
          detailLine.add(" (receipt persist failed: " & saved.error & ")")
      outcomes.add(UpstreamUnitOutcome(
        targetSymbol: unit.targetSymbol,
        findingKey: receipt.findingKey,
        status: receipt.status,
        blockedReason: outcomeBlocked,
        detail: detailLine,
        issueNumber: outcomeIssueNumber,
        issueUrl: outcomeIssueUrl,
        requestedRepository: receipt.requestedRepository,
        resolvedRepository: receipt.resolvedRepository))
      if persistError.len > 0:
        var issueDesc = ""
        if receipt.issueNumber > 0 and receipt.issueUrl.len > 0:
          issueDesc = ", issue " & $receipt.issueNumber & " " & receipt.issueUrl
        return err("upstream report: receipt persistence FAILED (" &
          $receipt.status & ", findingKey " & receipt.findingKey &
          issueDesc & "): " & persistError)

    # ── findingEvidence gate (§11: the common four evidence elements are a ──
    # ── reporting precondition; a gated unit performs NO gh call and writes ──
    # ── NOTHING — the state re-derives the gate on every run) ──
    if unit.evidenceMissing:
      outcomes.add(UpstreamUnitOutcome(
        targetSymbol: unit.targetSymbol,
        status: ursBlocked,
        blockedReason: blockedEvidenceMissing,
        detail: "no findingEvidence block for '" & unit.targetSymbol &
          "' — the common four evidence elements (bug_verdict_glossary.md " &
          "§2.2) are a reporting precondition; the counterexample is " &
          "recorded as empty and READY is unreachable"))
      continue
    if unit.normalized.len == 0:
      outcomes.add(UpstreamUnitOutcome(
        targetSymbol: unit.targetSymbol,
        status: ursBlocked,
        blockedReason: blockedEvidenceEmpty,
        detail: "findingEvidence present but its counterExample lines carry " &
          "no `input.<key>=<value>` bindings — the common four evidence " &
          "elements (bug_verdict_glossary.md §2.2) are a reporting " &
          "precondition; READY is unreachable"))
      continue

    # ── gh preflight (once; §2.4 — credentials ONLY via the native gh client) ──
    if not preflighted:
      let pf = gh("gh auth status")
      preflightOk = classifyGhOutcome(pf.exitCode, pf.output) == gokOk
      preflighted = true
    if not preflightOk:
      outcomes.add(UpstreamUnitOutcome(
        targetSymbol: unit.targetSymbol,
        status: ursBlocked,
        blockedReason: blockedGhAuth,
        detail: "gh auth preflight failed (gh missing or unauthenticated)"))
      continue

    # ── spec overlay (committed, repo-local; fail-closed) ──
    let overlayRes = loadSpecOverlay(repoRoot, unit.specRelPath)
    if overlayRes.isErr:
      return err(overlayRes.error)
    let facts = extractOverlayFacts(overlayRes.get(), unit)
    if facts.requestedRepository.len == 0:
      return err("upstream report: repository not resolvable from spec " &
        "overlay " & unit.specRelPath & " (fail-closed)")
    let specIrDigest = canonicalSpecIrDigest(facts.clauses)

    # ── resolve the target repository through GitHub (redirect-following) ──
    let repoApi = gh(ghRepoCmd(facts.requestedRepository))
    attempt("resolve-repository", "exit=" & $repoApi.exitCode & " " & repoApi.output)
    let repoKind = classifyGhOutcome(repoApi.exitCode, repoApi.output)
    var resolved = ""
    var hasIssues = true
    if repoKind == gokOk and repoApi.output.strip().len > 0:
      try:
        let repoJson = parseJson(repoApi.output)
        resolved = repoJson{"full_name"}.getStr("")
        let hi = repoJson{"has_issues"}
        if not hi.isNil and hi.kind == JBool:
          hasIssues = hi.getBool(false)
      except CatchableError:
        resolved = ""
    if resolved.len == 0:
      let reason =
        if repoKind == gokOk or blockedReasonFor(repoKind, repoApi.output).len == 0:
          blockedRepoResolution
        else:
          blockedReasonFor(repoKind, repoApi.output)
      outcomes.add(UpstreamUnitOutcome(
        targetSymbol: unit.targetSymbol,
        status: ursBlocked,
        blockedReason: reason,
        detail: "repository " & facts.requestedRepository &
          " not resolvable through GitHub",
        requestedRepository: facts.requestedRepository))
      continue
    # ── findingKey + evidenceDigest (v2 identity; deterministic, §4) ──
    let findingKey = composeFindingKey(resolved, unit.targetSymbol,
      facts.specId, facts.ruleId, facts.ruleVersion, specIrDigest)
    var identity = FindingIdentity(
      findingKey: findingKey,
      evidenceDigest: composeEvidenceDigest(unit.claimOutcome,
        unit.machineVerdict, unit.rowStatus, unit.quartetPayloadDigest,
        unit.machineEstablished, unit.normalized, unit.subjectCommit,
        unit.subjectBlob))
    let ledgerPath = ledgerReceiptPath(cfg.ledgerDir, identity.findingKey)

    # ── ledger read (single-writer idempotency; fail-closed) ──
    let existingRes = loadReceipt(ledgerPath)
    if existingRes.isErr:
      return err(existingRes.error)
    var prior = existingRes.get()
    var migratedFromLegacy = false
    if prior.isNone:
      # ── §6 legacy receipt lookup (v1 migration) ──
      # <findingKey>.json missed: scan the ledger's legacy receipts (file
      # name = v1 fingerprint) and inherit the evidence of the ONE receipt
      # whose identity triple (resolved repository + subject + proposition)
      # matches. The original v1 file stays immutable; the inherited state is
      # rewritten as a v2 receipt at the authoritative <findingKey>.json.
      let legacyRes = loadLegacyReceipts(cfg.ledgerDir, ledgerPath)
      if legacyRes.isErr:
        return err("upstream report: legacy receipt scan failed (" &
          legacyRes.error & ") — fail-closed, no create")
      var legacyMatches: seq[tuple[path: string; receipt: UpstreamReceipt]] = @[]
      for entry in legacyRes.get():
        if legacyReceiptMatchesIdentity(entry.receipt, resolved,
            unit.targetSymbol, facts.specId, facts.ruleId, facts.ruleVersion,
            specIrDigest):
          legacyMatches.add(entry)
      if legacyMatches.len > 1:
        # Multiple receipts claim this identity — fail-closed BLOCKED. The
        # verdict is recorded WITHOUT persisting (a persisted BLOCKED receipt
        # would fall through to create on a later run); the ambiguity
        # re-derives every run until the ambiguous legacy files are resolved
        # by a human (the v1 originals stay immutable).
        var matchedNames = ""
        for m in legacyMatches:
          if matchedNames.len > 0:
            matchedNames.add(", ")
          matchedNames.add(extractFilename(m.path))
        outcomes.add(UpstreamUnitOutcome(
          targetSymbol: unit.targetSymbol,
          findingKey: identity.findingKey,
          status: ursBlocked,
          blockedReason: blockedLegacyAmbiguous,
          detail: $legacyMatches.len & " legacy receipts match the identity " &
            "triple (" & matchedNames & ") — migration is ambiguous; " &
            "resolve the conflicting legacy receipts before reporting " &
            "(no create, nothing persisted)"))
        continue
      if legacyMatches.len == 1:
        let legacy = legacyMatches[0].receipt
        attempt("legacy-migrate", "inherited legacy receipt " &
          extractFilename(legacyMatches[0].path) &
          (if legacy.issueNumber > 0: " (issue " & $legacy.issueNumber & " " &
            legacy.issueUrl & ")" else: "") &
          (if cfg.dryRun: " (dry-run — migrated receipt not persisted)"
           else: ""))
        var migrated = baseReceipt(unit, facts, identity,
          facts.requestedRepository, resolved, specIrDigest)
        migrated.status = legacy.status
        carryForwardReceiptEvidence(migrated, legacy)
        # verdict succession: the receipt records the verdict the original
        # submission observed — the v1 record wins over the fresh display
        # projection only as the historical record of that submission.
        if legacy.propositionVerdict.len > 0:
          migrated.propositionVerdict = legacy.propositionVerdict
        if legacy.requirementSourceStatus.len > 0:
          migrated.requirementSourceStatus = legacy.requirementSourceStatus
        if legacy.bugAttribution.len > 0:
          migrated.bugAttribution = legacy.bugAttribution
        identity.legacyFingerprints = mergeLegacyFingerprints(
          identity.legacyFingerprints,
          legacyReceiptFingerprints(legacy, resolved, unit.targetSymbol,
            facts.specId, facts.ruleId, facts.ruleVersion, specIrDigest))
        migrated.legacyFingerprints = identity.legacyFingerprints
        if not cfg.dryRun:
          let migratedSaved = saveReceiptAtomic(migrated, ledgerPath)
          if migratedSaved.isErr:
            return err("upstream report: legacy migration receipt persist " &
              "FAILED (" & failedLegacyPersist & ", " & $migrated.status &
              ", findingKey " & identity.findingKey & "): " &
              migratedSaved.error)
        prior = some(migrated)
        migratedFromLegacy = true
    # Legacy fingerprints survive every later transition: fold the prior
    # receipt's record into the identity every receipt in this run is built
    # from (the §6 re-linking record is durable, not per-run).
    if prior.isSome:
      identity.legacyFingerprints = mergeLegacyFingerprints(
        identity.legacyFingerprints, prior.get().legacyFingerprints)
    let anchors = identityAnchors(identity.findingKey,
      identity.legacyFingerprints)
    let priorReceipt = if prior.isSome: prior.get() else: UpstreamReceipt()
    # A READY receipt in the ledger can only be the pre-create intent (dry-run
    # never persists, and no other transition persists READY): the process may
    # have died between the intent save and the create, so its creation state
    # is unresolved exactly like RR / FAILED(remote-unverifiable).
    let priorUnresolved = prior.isSome and
      (prior.get().status == ursReady or
      prior.get().status == ursReconciliationRequired or
      (prior.get().status == ursFailed and
        prior.get().blockedReason == failedRemoteUnverifiable))

    if not hasIssues:
      if priorUnresolved:
        # An unresolved creation (RR, or FAILED remote-unverifiable) must not
        # lose its reconciliation safety while issues are disabled — demoting
        # it to BLOCKED would let a later has_issues=true run regenerate over
        # the still-unverified candidate. The state stays
        # RECONCILIATION_REQUIRED with the attempt evidence carried forward.
        attempt("reconcile", "issues disabled while a creation stays unresolved")
        var recReceipt = baseReceipt(unit, facts, identity,
          facts.requestedRepository, resolved, specIrDigest)
        recReceipt.status = ursReconciliationRequired
        recReceipt.attempts = attempts
        carryForwardReceiptEvidence(recReceipt, priorReceipt)
        persistAndRecord(recReceipt, ledgerPath, "", 0, "",
          "issues are disabled on " & resolved &
          " — the unresolved prior creation keeps " & $ursReconciliationRequired &
          "; create stays forbidden")
        continue
      var blockedReceipt = baseReceipt(unit, facts, identity,
        facts.requestedRepository, resolved, specIrDigest)
      blockedReceipt.status = ursBlocked
      blockedReceipt.blockedReason = blocked410
      blockedReceipt.attempts = attempts
      carryForwardReceiptEvidence(blockedReceipt, priorReceipt)
      persistAndRecord(blockedReceipt, ledgerPath, blocked410, 0, "",
        "issues are disabled on " & resolved)
      continue

    var handled = false
    if prior.isSome:
      let receipt = prior.get()
      if receipt.issueNumber > 0:
        # The ledger carries a structured issue identity (SUBMITTED,
        # DUPLICATE, or one carried through a BLOCKED/RR/FAILED transition):
        # verify it through a DIRECT gh issue view before linking — a search
        # index is never trusted for an identity we already observed, and a
        # re-create is forbidden while it cannot be re-verified.
        let viewRes = gh(ghIssueViewCmd(receipt.issueNumber, resolved, false))
        attempt("verify-ledger-submission",
          "exit=" & $viewRes.exitCode & " " & viewRes.output)
        var verified = false
        var viewCreatedAt = ""
        if classifyGhOutcome(viewRes.exitCode, viewRes.output) == gokOk:
          let parsed = parseIssueView(viewRes.output)
          if parsed.isOk and parsed.get().number == receipt.issueNumber:
            verified = true
            viewCreatedAt = parsed.get().createdAt
        if verified:
          var dupReceipt = baseReceipt(unit, facts, identity,
            facts.requestedRepository, resolved, specIrDigest)
          dupReceipt.status = ursDuplicate
          dupReceipt.issueNumber = receipt.issueNumber
          dupReceipt.issueUrl = receipt.issueUrl
          if priorReceipt.submittedAt.len == 0 and viewCreatedAt.len > 0:
            # §6: a receipt whose submittedAt was never observed (a migrated
            # legacy record, or a later recovery of it) backfills from the
            # GitHub issue's created_at — GitHub is the authority for that
            # instant; an observation is recorded, never invented.
            attempt("legacy-backfill",
              "submittedAt <- issue created_at " & viewCreatedAt)
          elif migratedFromLegacy and priorReceipt.submittedAt.len == 0:
            attempt("legacy-backfill",
              "created_at unavailable in the issue view payload — " &
              "submittedAt stays unset")
          dupReceipt.attempts = attempts
          carryForwardReceiptEvidence(dupReceipt, priorReceipt)
          if dupReceipt.submittedAt.len == 0 and viewCreatedAt.len > 0:
            dupReceipt.submittedAt = viewCreatedAt
          persistAndRecord(dupReceipt, ledgerPath, "", receipt.issueNumber,
            receipt.issueUrl, "duplicate of ledger-recorded submission")
          handled = true
        else:
          var recReceipt = baseReceipt(unit, facts, identity,
            facts.requestedRepository, resolved, specIrDigest)
          recReceipt.status = ursReconciliationRequired
          attempt("reconcile", reconciliationLedgerUnverifiable)
          if migratedFromLegacy and priorReceipt.submittedAt.len == 0:
            attempt("legacy-backfill",
              "skipped — the ledger issue could not be re-verified (no " &
              "created_at observation; submittedAt stays unset)")
          recReceipt.attempts = attempts
          carryForwardReceiptEvidence(recReceipt, priorReceipt)
          persistAndRecord(recReceipt, ledgerPath, "",
            0, "", reconciliationLedgerUnverifiable &
            " — next run must re-query before any re-create")
          handled = true
      elif receipt.status == ursReconciliationRequired or
          (receipt.status == ursFailed and
            receipt.blockedReason == failedRemoteUnverifiable):
        # NEVER blind-retry: recover the recorded candidate first (an
        # ambiguous create outcome, or a create whose remote verification
        # failed — both leave a candidateUrl attempt record).
        var candidateUrl = ""
        for a in receipt.attempts:
          if a.candidateUrl.len > 0:
            candidateUrl = a.candidateUrl
        if candidateUrl.len > 0:
          let candidateNumber = issueNumberFromUrl(candidateUrl)
          if candidateNumber > 0:
            let viewRes = gh(ghIssueViewCmd(candidateNumber, resolved, true))
            attempt("reconcile-candidate",
              "exit=" & $viewRes.exitCode & " " & viewRes.output, candidateUrl)
            if classifyGhOutcome(viewRes.exitCode, viewRes.output) == gokOk:
              let parsed = parseIssueView(viewRes.output)
              if parsed.isOk and bodyCarriesIdentity(parsed.get().body, anchors):
                var dupReceipt = baseReceipt(unit, facts, identity,
                  facts.requestedRepository, resolved, specIrDigest)
                dupReceipt.status = ursDuplicate
                dupReceipt.issueNumber = parsed.get().number
                dupReceipt.issueUrl = parsed.get().url
                dupReceipt.attempts = attempts
                carryForwardReceiptEvidence(dupReceipt, priorReceipt)
                persistAndRecord(dupReceipt, ledgerPath, "",
                  parsed.get().number, parsed.get().url,
                  "duplicate — recovered from a previous ambiguous attempt")
                handled = true
    if handled:
      continue

    # ── mandatory remote duplicate check (ALWAYS before any create) ──
    # The identity anchors (findingKey + every legacy v1 fingerprint) are all
    # queried — pre-v2 issues embed the reportFingerprint line, so a v2 run
    # must find them too.
    var dupUrl = ""
    var dupNumber = 0
    var dupCheckBlocked = ""
    block anchorSearch:
      for anchor in anchors:
        for cmd in [ghSearchCmd(resolved, anchor), ghListCmd(resolved, anchor)]:
          let res = gh(cmd)
          attempt("duplicate-check", "exit=" & $res.exitCode & " " & res.output)
          let kind = classifyGhOutcome(res.exitCode, res.output)
          if kind != gokOk:
            let reason = blockedReasonFor(kind, res.output)
            dupCheckBlocked = if reason.len > 0: reason else: blockedDupCheck
            break anchorSearch
          let refs = parseIssueRefList(res.output)
          if refs.isErr:
            dupCheckBlocked = blockedDupCheck
            break anchorSearch
          for r in refs.get():
            if r.url.len > 0 and r.number > 0:
              dupUrl = r.url
              dupNumber = r.number
              break
          if dupUrl.len > 0:
            break anchorSearch
    if dupCheckBlocked.len == 0 and dupNumber > 0:
      # Confirm the hit actually carries OUR identity before linking.
      let viewRes = gh(ghIssueViewCmd(dupNumber, resolved, true))
      attempt("duplicate-verify", "exit=" & $viewRes.exitCode & " " & viewRes.output)
      if classifyGhOutcome(viewRes.exitCode, viewRes.output) == gokOk:
        let parsed = parseIssueView(viewRes.output)
        if parsed.isOk and bodyCarriesIdentity(parsed.get().body, anchors):
          var dupReceipt = baseReceipt(unit, facts, identity,
            facts.requestedRepository, resolved, specIrDigest)
          dupReceipt.status = ursDuplicate
          dupReceipt.issueNumber = dupNumber
          dupReceipt.issueUrl = dupUrl
          dupReceipt.attempts = attempts
          carryForwardReceiptEvidence(dupReceipt, priorReceipt)
          persistAndRecord(dupReceipt, ledgerPath, "", dupNumber, dupUrl,
            "duplicate of an existing upstream issue")
          continue
        # a hit without our fingerprint is not ours — keep going
      else:
        dupCheckBlocked = blockedDupCheck
    if dupCheckBlocked.len > 0:
      if priorUnresolved:
        # An ambiguous/unverifiable creation is already on record — demoting
        # it to BLOCKED would bury the candidate recovery input under a
        # status the next run does not reconcile from. The state stays
        # RECONCILIATION_REQUIRED with the failed re-query recorded in the
        # attempt history.
        attempt("reconcile", "duplicate check unavailable during reconciliation")
        var recReceipt = baseReceipt(unit, facts, identity,
          facts.requestedRepository, resolved, specIrDigest)
        recReceipt.status = ursReconciliationRequired
        recReceipt.attempts = attempts
        carryForwardReceiptEvidence(recReceipt, priorReceipt)
        persistAndRecord(recReceipt, ledgerPath, "", 0, "",
          "duplicate check unavailable during reconciliation — state stays " &
          $ursReconciliationRequired &
          " (candidate recovery input preserved); create forbidden")
        continue
      var blockedReceipt = baseReceipt(unit, facts, identity,
        facts.requestedRepository, resolved, specIrDigest)
      blockedReceipt.status = ursBlocked
      blockedReceipt.blockedReason = dupCheckBlocked
      blockedReceipt.attempts = attempts
      carryForwardReceiptEvidence(blockedReceipt, priorReceipt)
      persistAndRecord(blockedReceipt, ledgerPath, dupCheckBlocked, 0, "",
        "duplicate check unavailable — creating is forbidden (would risk a duplicate)")
      continue

    if priorUnresolved:
      # The remote re-query observed no issue carrying our fingerprint: §5
      # allows RECONCILIATION_REQUIRED -> SUBMITTED | DUPLICATE only, and a
      # search index is not authoritative for freshly created issues —
      # regeneration stays forbidden while the ambiguity is unresolved.
      attempt("reconcile", "remote re-query found no confirmed issue")
      var recReceipt = baseReceipt(unit, facts, identity,
        facts.requestedRepository, resolved, specIrDigest)
      recReceipt.status = ursReconciliationRequired
      recReceipt.attempts = attempts
      carryForwardReceiptEvidence(recReceipt, priorReceipt)
      persistAndRecord(recReceipt, ledgerPath, "", 0, "",
        "reconciliation unresolved — the remote re-query did not confirm the " &
        "issue; regeneration is forbidden (state stays " &
        $ursReconciliationRequired & ")")
      continue

    # ── dry-run: READY is the terminal state; nothing persisted ──
    if cfg.dryRun:
      attempt("dry-run", "READY preview — no external write performed")
      let title = composeIssueTitle(facts, unit.normalized)
      outcomes.add(UpstreamUnitOutcome(
        targetSymbol: unit.targetSymbol,
        findingKey: identity.findingKey,
        status: ursReady,
        detail: "READY (dry-run preview): " & title,
        requestedRepository: facts.requestedRepository,
        resolvedRepository: resolved))
      continue

    # ── issue body: mirror the target repo's bug-report template when present ──
    var sections = defaultIssueSections
    let tplRes = gh(ghTemplateCmd(resolved))
    attempt("fetch-issue-template", "exit=" & $tplRes.exitCode & " " & tplRes.output)
    if classifyGhOutcome(tplRes.exitCode, tplRes.output) == gokOk:
      let decoded = decodeGhContentsJson(tplRes.output)
      if decoded.isOk:
        let tplSections = extractTemplateSections(decoded.get())
        if tplSections.len > 0:
          sections = tplSections
      # template absent (404) -> default sections: the normal path
    let title = composeIssueTitle(facts, unit.normalized)
    let body = composeIssueBody(facts, unit, facts.requestedRepository,
      resolved, identity, sections)
    let tmpBody = joinPath(getTempDir(), "axiom-upstream-body-" &
      identity.findingKey & ".md")
    try:
      writeFile(tmpBody, body)
    except CatchableError as e:
      return err("upstream report: cannot write issue body tmpfile: " & e.msg)

    # Persist the READY intent BEFORE the external write — a crash mid-create
    # still leaves a findingKey-keyed receipt the next run reconciles from.
    var readyReceipt = baseReceipt(unit, facts, identity,
      facts.requestedRepository, resolved, specIrDigest)
    readyReceipt.attempts = attempts
    carryForwardReceiptEvidence(readyReceipt, priorReceipt)
    let readySaved = saveReceiptAtomic(readyReceipt, ledgerPath)
    if readySaved.isErr:
      # fail-closed: the READY intent could not be recorded, so the external
      # write is forbidden — an ambiguous create outcome would leave no
      # ledger state to reconcile from. (Persisting a FAILED receipt instead
      # would hit the same broken ledger: report the refusal as a hard error.)
      attempt("ready-intent", "receipt persist failed: " & readySaved.error)
      try:
        removeFile(tmpBody)
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)
      return err("upstream report: READY intent persistence FAILED (" &
        failedReadyPersist & ", findingKey " & identity.findingKey & "): " &
        readySaved.error & " — the external create is forbidden (fail-closed)")

    # ── the external write ──
    let createRes = gh(ghCreateCmd(resolved, title, tmpBody))
    attempt("create-issue", "exit=" & $createRes.exitCode & " " & createRes.output)
    try:
      removeFile(tmpBody)
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

    let createKind = classifyGhOutcome(createRes.exitCode, createRes.output)
    var receipt = baseReceipt(unit, facts, identity,
      facts.requestedRepository, resolved, specIrDigest)
    var detail = ""
    case createKind
    of gokOk:
      let found = extractIssueUrl(createRes.output)
      if found.number > 0:
        let viewRes = gh(ghIssueViewCmd(found.number, resolved, false))
        attempt("verify-submission", "exit=" & $viewRes.exitCode & " " & viewRes.output,
          candidateUrl = found.url)
        if classifyGhOutcome(viewRes.exitCode, viewRes.output) == gokOk:
          let parsed = parseIssueView(viewRes.output)
          if parsed.isOk:
            receipt.status = ursSubmitted
            receipt.issueNumber = parsed.get().number
            receipt.issueUrl = parsed.get().url
            receipt.submittedAt = clock()
            detail = "issue created and verified"
          else:
            receipt.status = ursFailed
            receipt.blockedReason = failedRemoteUnverifiable
            detail = "failed: " & failedRemoteUnverifiable
        else:
          receipt.status = ursFailed
          receipt.blockedReason = failedRemoteUnverifiable
          detail = "failed: " & failedRemoteUnverifiable
      else:
        # exit 0 without a printed URL: the creation state is unknown.
        attempt("create-outcome", "exit=0 without an issue URL — ambiguous")
        receipt.status = ursReconciliationRequired
        detail = "creation state unresolved — next run must re-query before re-create"
    of gokGhMissing, gokAuth:
      receipt.status = ursBlocked
      receipt.blockedReason = blockedGhAuth
      detail = "blocked: " & blockedGhAuth
    of gokHttp403:
      let reason = blockedReasonFor(createKind, createRes.output)
      receipt.status = ursBlocked
      receipt.blockedReason = reason
      detail =
        if reason == blocked403RateLimited:
          blocked403RateLimitedDetail
        else:
          "blocked: " & reason
    of gokHttp404:
      receipt.status = ursBlocked
      receipt.blockedReason = blocked404
      detail = "blocked: " & blocked404
    of gokHttp410:
      receipt.status = ursBlocked
      receipt.blockedReason = blocked410
      detail = "blocked: " & blocked410
    of gokHttp429:
      # §8: rate limited (primary/secondary) — a transient restriction in its
      # own right (the status code is the throttle signal), BLOCKED with the
      # honest rate-limit reason; no auto-retry.
      receipt.status = ursBlocked
      receipt.blockedReason = blocked429
      detail = blocked429Detail
    of gokRejected:
      receipt.status = ursFailed
      receipt.blockedReason = failedConfirmed
      detail = "failed: " & failedConfirmed
    of gokTimeout, gokAmbiguous:
      # timeout / ambiguous: the creation state is unknown — the NEXT run
      # must re-query (ledger reconciliation + direct candidate recovery)
      # before any re-create.
      let found = extractIssueUrl(createRes.output)
      attempt("create-outcome", "exit=" & $createRes.exitCode & " " & createRes.output,
        candidateUrl = (if found.number > 0: found.url else: ""))
      receipt.status = ursReconciliationRequired
      detail = "creation state unresolved — next run must re-query before re-create"
    receipt.attempts = attempts
    carryForwardReceiptEvidence(receipt, priorReceipt)
    # Persist IMMEDIATELY (contract), exactly once — a persistence failure
    # after the external write is a hard error carrying the issue identity,
    # and the on-disk READY intent (its save succeeded, or the create never
    # ran) keeps the next run on the no-regeneration recovery path.
    persistAndRecord(receipt, ledgerPath, receipt.blockedReason,
      receipt.issueNumber, receipt.issueUrl, detail)

  ok(outcomes)

# ---------------------------------------------------------------------------
# CLI surface
# ---------------------------------------------------------------------------

proc runUpstreamReportCli*(args: seq[string]; stateFilePath: string):
    Result[AxCommandCliResult, string] {.raises: [CatchableError],
    axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## CLI surface for `ax report --upstream`, called from runReportCli after
  ## the shared --state-file resolution (single resolution authority).
  let flagsRes = parseUpstreamFlags(args)
  if flagsRes.isErr:
    return err(flagsRes.error)
  let flags = flagsRes.get()
  let statePath =
    if flags.stateFilePath.len > 0: flags.stateFilePath
    else: stateFilePath
  let repoRoot = findRepoRoot()
  if repoRoot.len == 0 or not fileExists(joinPath(repoRoot, ".axiom_root")):
    return err("ax report --upstream must be executed within an Axiom " &
      "repository worktree. Set AXIOM_ROOT env var or run from project root.")
  let cfg = UpstreamRunConfig(
    stateFilePath: statePath,
    repoRoot: repoRoot,
    ledgerDir: joinPath(repoRoot, ledgerDirRelative),
    dryRun: flags.dryRun,
    emitJson: flags.emitJson)
  let stateRes = loadReportProofState(statePath)
  if stateRes.isErr:
    return err("upstream report: " & stateRes.error)
  let outcomesRes = runUpstreamReport(stateRes.get(), cfg, liveGhAdapter, systemClock)
  if outcomesRes.isErr:
    return err(outcomesRes.error)
  let outcomes = outcomesRes.get()
  var logLines: seq[string] = @[]
  logLines.add("upstream report: " & $outcomes.len & " reportable finding(s)" &
    (if flags.dryRun: " (dry-run — no external write)" else: ""))
  for o in outcomes:
    var line = "  " & o.targetSymbol & " -> " & $o.status
    if o.issueUrl.len > 0:
      line.add(" " & o.issueUrl)
    if o.blockedReason.len > 0:
      line.add(" (" & o.blockedReason & ")")
    logLines.add(line)
  var outputJson = ""
  if flags.emitJson:
    var arr = newJArray()
    for o in outcomes:
      arr.add(unitOutcomeToJson(o))
    outputJson = $(%*{
      "schemaVersion": upstreamResultSchemaVersion,
      "dryRun": flags.dryRun,
      "results": arr})
  ok(AxCommandCliResult(
    outputJson: outputJson,
    logLines: logLines,
    exitCode: upstreamExitCode(outcomes),
    emitJson: flags.emitJson))

{.pop.}
