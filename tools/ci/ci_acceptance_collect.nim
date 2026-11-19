## tools/ci/ci_acceptance_collect.nim — CI Acceptance Contract v2 collector.
##
## REPORTER ONLY: this tool has no merge authority, does not modify policy, does
## not add/remove required checks, and never re-runs a workflow. It issues
## read-only `gh api` GET requests and writes a JSON + Markdown acceptance
## report. The contract is docs/spec/ci_acceptance_contract.md.
##
## What is counted
##   Entry = one unique `merge_group` head_sha of an `admission-gate` workflow
##   run. Re-runs and new checks_requested runs for the same head_sha are
##   attempts of that entry, never new entries (one candidate exercises ~8
##   workflows, so workflow-run counting is not entry counting).
##   The acceptance window is exactly N post-boundary entries (default 20),
##   --mode initial (first N, default) or rolling (last N). Fewer than N is
##   INCOMPLETE (shortfall), never a smaller window. The boundary is REQUIRED
##   (`--boundary <sha>`) and is the canonical main merge commit after #145,
##   #186, and the contract have landed. There is no default and no compiled-in
##   SHA.
##
## Classification (worst-of across attempts; retries never erase an incident)
##   success
##   legitimate_policy    TRUST_SURFACE_MODIFIED / ROT_ALLOWLIST / explicit
##                        subject-pin-or-document refusal (INVALID_INPUT exit 3)
##   internal_defect      subtype soundness_failure > identity_divergence >
##                        failure_projection (see §4.3 of the contract)
##   unclassified         everything else, including missing artifact AND log,
##                        API error, unparsable identity/timestamp
##   cancelled_superseded only with a same-PR same-base replacement run
##
## Acceptance: observed_n == N AND unexpected_internal_defects == 0 AND
## unclassified == 0 AND observation_complete over the N post-boundary entries.
## legitimate_policy is reported, never failed. Fewer than N => INCOMPLETE with
## shortfall and exit 2. Fail-closed: any observation gap makes the entry
## unclassified and the collector exit 2. Exit 0 ACCEPTED, 1 FAILED,
## 2 INCOMPLETE.
##
## Authority: every measured entry needs an `admission-check` check-run from App
## 5795152 (axiom-admission-verifier); a same-name check from another App is
## authority_substitution, never a substitute success.
##
## Latency (canonical): wall = max(job.completed_at) - min(job.started_at) over
## the terminal attempt's jobs (filter=latest) that carry both timestamps.
## Legacy wall = terminal attempt updated_at - run_started_at, reported as
## non-canonical continuity only. `--recompute-baseline <run-list>` recomputes
## the canonical p50 over a supplied run list; `--baseline-live` recomputes it
## over the newest N completed admission-gate merge_group runs (optionally
## pinned by --baseline-until). Historical 546/560/574.5 numbers are
## inadmissible unless re-derived by one of those commands.
##
## I/O boundary: `gh api` GET only; artifact/log downloads go to a temp dir;
## only allowlisted evidence artifacts are downloaded (never caches/build
## trees); missing artifact/log => unclassified. Every I/O proc carries
## {.axiomEffect: IoEffect.}.
##
## Build:
##   nim c -d:release --hints:off --path:src \
##     -o:bin/ci_acceptance_collect tools/ci/ci_acceptance_collect.nim
##
## Exit: 0 ACCEPTED; 1 FAILED; 2 INCOMPLETE / observation incomplete /
## input invalid.

import std/[algorithm, json, os, osproc, strutils, times]

import core/trusted/layer_declaration
import core/trusted/axiom_pragmas_lite
axiomLayer "tools"

const
  ToolName* = "ci_acceptance_collect"
  ContractPath* = "docs/spec/ci_acceptance_contract.md"
  SchemaVersion* = "axiom.ci_acceptance.v2"
  DefaultRepo* = "Archright/Axiom"
  DefaultWindow* = 20
  BaselineWindow* = 40
  RequiredAdmissionAppId* = 5795152
  ActionsAppId* = 15368
  DefaultOutDir* = "build" / "ci_acceptance"
  MaxRunPages* = 10
  MaxCheckRunPages* = 10
  MaxJobPages* = 10
  MaxArtifactBytes* = 4_000_000
  MaxLogBytes* = 4_000_000

# ═══════════════════════════════════════════════════════════════════════════
# §1. Pure core — types
# ═══════════════════════════════════════════════════════════════════════════

type
  ClassificationKind* = enum
    ckSuccess = "success"
    ckLegitimatePolicy = "legitimate_policy"
    ckInternalDefect = "internal_defect"
    ckUnclassified = "unclassified"
    ckCancelledSuperseded = "cancelled_superseded"

  DefectSubtype* = enum
    dsNone = "none"
    dsFailureProjection = "failure_projection"
    dsIdentityDivergence = "identity_divergence"
    dsSoundnessFailure = "soundness_failure"
    dsAuthoritySubstitution = "authority_substitution"

  WindowMode* = enum
    wmInitial = "initial"
    wmRolling = "rolling"

  AcceptanceStatus* = enum
    asAccepted = "ACCEPTED"
    asIncomplete = "INCOMPLETE"
    asFailed = "FAILED"

  EvidenceText* = object
    name*: string
    text*: string

  ObservedJob* = object
    name*: string
    status*: string
    conclusion*: string
    startedAt*: string
    completedAt*: string

  ObservedAttempt* = object
    runId*: string
    attemptNumber*: int
    status*: string
    conclusion*: string
    runStartedAt*: string
    updatedAt*: string
    artifacts*: seq[EvidenceText]
    logs*: seq[EvidenceText]
    jobs*: seq[ObservedJob]
    jobsObserved*: bool
    jobsError*: string
    evidenceFetched*: bool
    evidenceError*: string
    attemptListGap*: bool

  ObservedRun* = object
    runId*: string
    workflowName*: string
    workflowPath*: string
    event*: string
    headSha*: string
    baseSha*: string
    prNumber*: int
    runAttempt*: int
    startedAt*: string
    updatedAt*: string
    createdAt*: string
    status*: string
    conclusion*: string
    attempts*: seq[ObservedAttempt]
    attemptsObserved*: bool
    gapReason*: string

  ObservedEntry* = object
    headSha*: string
    baseSha*: string
    prNumber*: int
    runIds*: seq[string]
    attempts*: seq[ObservedAttempt]
    postBoundary*: bool
    ancestryObserved*: bool
    replacementExists*: bool
    replacementObserved*: bool
    boundaryGap*: string
    admissionAppIds*: seq[int]
    admissionAppHasRequired*: bool
    admissionAppHasSuccess*: bool
    authorityObserved*: bool
    authorityGap*: string

  AttemptClass* = object
    kind*: ClassificationKind
    subtype*: DefectSubtype
    subtypeDetail*: string
    evidence*: string
    gap*: bool
    gapReason*: string
    detail*: string

  EntryClass* = object
    kind*: ClassificationKind
    subtype*: DefectSubtype
    subtypeDetail*: string
    evidence*: string
    gap*: bool
    gapReason*: string
    detail*: string

  EntryReport* = object
    runId*: string
    runIds*: seq[string]
    attemptIds*: seq[string]
    headSha*: string
    baseSha*: string
    prNumber*: int
    conclusion*: string
    classification*: ClassificationKind
    subtype*: DefectSubtype
    subtypeDetail*: string
    evidence*: string
    wallSeconds*: int
    wallObserved*: bool
    legacyWallSeconds*: int
    legacyWallObserved*: bool
    admissionAppIds*: seq[int]
    gap*: bool
    gapReason*: string
    postBoundary*: bool
    details*: seq[string]

  Acceptance* = object
    mode*: WindowMode
    status*: AcceptanceStatus
    requestedWindow*: int
    observedEntries*: int
    shortfall*: int
    success*: int
    legitimatePolicy*: int
    internalDefect*: int
    unclassified*: int
    cancelledSuperseded*: int
    identityDivergence*: int
    soundnessFailure*: int
    failureProjection*: int
    authoritySubstitution*: int
    unexpectedInternalDefects*: int
    predicateHolds*: bool
    observationComplete*: bool
    accepted*: bool
    gaps*: seq[string]
    latencyN*: int
    latencyP50*: float
    latencyMean*: float
    latencyMin*: int
    latencyMax*: int
    legacyLatencyN*: int
    legacyLatencyP50*: float
    legacyLatencyMean*: float

  AcceptanceReport* = object
    schemaVersion*: string
    contract*: string
    generatedAt*: string
    repo*: string
    boundary*: string
    entries*: seq[EntryReport]
    excludedBeforeBoundary*: int
    acceptance*: Acceptance

  RunDuration* = object
    runId*: string
    seconds*: int
    observed*: bool
    legacySeconds*: int
    legacyObserved*: bool
    gapReason*: string

  LatencyStats* = object
    n*: int
    p50*: float
    mean*: float
    minSeconds*: int
    maxSeconds*: int

# ═══════════════════════════════════════════════════════════════════════════
# §2. Pure core — timestamp and scalar parsing (no std/times, no exceptions)
# ═══════════════════════════════════════════════════════════════════════════

func digitAt(s: string, i: int): bool {.raises: [].} =
  result = i >= 0 and i < s.len and s[i] in {'0' .. '9'}

func twoDigits(s: string, i: int): int {.raises: [].} =
  result = (ord(s[i]) - ord('0')) * 10 + (ord(s[i + 1]) - ord('0'))

func daysFromCivil(year, month, day: int): int64 {.raises: [].} =
  ## Howard Hinnant's civil-date -> days-since-1970-01-01 algorithm.
  var y = year
  let m = month
  if m <= 2:
    dec y
  let era = (if y >= 0: y else: y - 399) div 400
  let yoe = y - era * 400
  let doy = (153 * (if m > 2: m - 3 else: m + 9) + 2) div 5 + day - 1
  let doe = yoe * 365 + yoe div 4 - yoe div 100 + doy
  int64(era) * 146097'i64 + int64(doe) - 719468'i64

func parseIsoUtc*(s: string): tuple[value: int64, ok: bool] {.raises: [].} =
  ## Parse GitHub's `YYYY-MM-DDTHH:MM:SSZ` (a fractional part and +00:00 are
  ## accepted; non-UTC offsets are rejected). Deterministic and exception-free.
  if s.len < 20:
    return (0'i64, false)
  for i in [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18]:
    if not digitAt(s, i):
      return (0'i64, false)
  if s[4] != '-' or s[7] != '-' or s[10] != 'T' or s[13] != ':' or s[16] != ':':
    return (0'i64, false)
  let
    year = twoDigits(s, 0) * 100 + twoDigits(s, 2)
    month = twoDigits(s, 5)
    day = twoDigits(s, 8)
    hour = twoDigits(s, 11)
    minute = twoDigits(s, 14)
    second = twoDigits(s, 17)
  if month < 1 or month > 12 or day < 1 or day > 31 or
      hour > 23 or minute > 59 or second > 60:
    return (0'i64, false)
  var pos = 19
  if pos < s.len and s[pos] == '.':
    inc pos
    let fracStart = pos
    while pos < s.len and s[pos] in {'0' .. '9'}:
      inc pos
    if pos == fracStart:
      return (0'i64, false)
  if pos >= s.len:
    return (0'i64, false)
  if s[pos] == 'Z':
    if pos != s.len - 1:
      return (0'i64, false)
  elif s[pos] == '+':
    if s.len - pos != 6 or s[pos + 3] != ':':
      return (0'i64, false)
    if twoDigits(s, pos + 1) != 0 or twoDigits(s, pos + 4) != 0:
      return (0'i64, false)
  else:
    return (0'i64, false)
  let days = daysFromCivil(year, month, day)
  let secs = days * 86400'i64 +
             int64(hour * 3600 + minute * 60 + second)
  (secs, true)

func parseDecimal*(s: string): tuple[value: int64, ok: bool] {.raises: [].} =
  if s.len == 0:
    return (0'i64, false)
  var v = 0'i64
  for ch in s:
    if ch notin {'0' .. '9'}:
      return (0'i64, false)
    let d = int64(ord(ch) - ord('0'))
    if v > (high(int64) - d) div 10:
      return (0'i64, false)
    v = v * 10 + d
  (v, true)

# ═══════════════════════════════════════════════════════════════════════════
# §3. Pure core — attempt ordering, wall clock, p50
# ═══════════════════════════════════════════════════════════════════════════

func cmpAttempt(a, b: ObservedAttempt): int {.raises: [].} =
  let (sa, oka) = parseIsoUtc(a.runStartedAt)
  let (sb, okb) = parseIsoUtc(b.runStartedAt)
  let
    ka = (if oka: sa else: low(int64))
    kb = (if okb: sb else: low(int64))
  if ka != kb:
    return cmp(ka, kb)
  if a.attemptNumber != b.attemptNumber:
    return cmp(a.attemptNumber, b.attemptNumber)
  let (ra, okra) = parseDecimal(a.runId)
  let (rb, okrb) = parseDecimal(b.runId)
  if okra and okrb and ra != rb:
    return cmp(ra, rb)
  result = cmp(a.runId, b.runId)

func terminalAttemptIndex*(e: ObservedEntry): int {.raises: [].} =
  ## Latest attempt by (run_started_at, run_attempt, run_id). -1 when the
  ## entry carries no observed attempt.
  result = -1
  var best: ObservedAttempt
  for i, a in e.attempts:
    if result < 0 or cmpAttempt(best, a) < 0:
      best = a
      result = i

func terminalAttempt*(e: ObservedEntry): ObservedAttempt {.raises: [].} =
  let idx = terminalAttemptIndex(e)
  if idx >= 0:
    result = e.attempts[idx]

func jobSpanSeconds*(jobs: seq[ObservedJob]):
    tuple[seconds: int, observed: bool, reason: string] {.raises: [].} =
  ## Canonical wall: max(completed_at) - min(started_at) over jobs whose two
  ## timestamps are both present. No such job means the wall is unobservable.
  if jobs.len == 0:
    return (0, false, "no jobs observed for the terminal attempt")
  var
    minStart = high(int64)
    maxDone = low(int64)
    paired = 0
  for j in jobs:
    let (s, okStart) = parseIsoUtc(j.startedAt)
    let (d, okDone) = parseIsoUtc(j.completedAt)
    if okStart and okDone:
      if s < minStart:
        minStart = s
      if d > maxDone:
        maxDone = d
      inc paired
  if paired == 0:
    return (0, false, "no job carries both started_at and completed_at")
  if maxDone < minStart:
    return (0, false, "max job completed_at precedes min job started_at")
  (int(maxDone - minStart), true, "")

func entryCanonicalWallSeconds*(e: ObservedEntry):
    tuple[seconds: int, observed: bool, reason: string] {.raises: [].} =
  ## Canonical per-entry wall: the terminal attempt's jobs.
  let idx = terminalAttemptIndex(e)
  if idx < 0:
    return (0, false, "entry has no observed attempts")
  let a = e.attempts[idx]
  if not a.jobsObserved:
    return (0, false,
            (if a.jobsError.len > 0: a.jobsError
             else: "terminal attempt jobs unobservable"))
  result = jobSpanSeconds(a.jobs)

func entryLegacyWallSeconds*(e: ObservedEntry):
    tuple[seconds: int, observed: bool, reason: string] {.raises: [].} =
  ## Non-canonical: run_started_at -> updated_at of the terminal attempt. Kept
  ## for continuity only; GitHub does not document a per-attempt run wall.
  let idx = terminalAttemptIndex(e)
  if idx < 0:
    return (0, false, "entry has no observed attempts")
  let a = e.attempts[idx]
  let (started, okStart) = parseIsoUtc(a.runStartedAt)
  let (updated, okUpdated) = parseIsoUtc(a.updatedAt)
  if not okStart or not okUpdated:
    return (0, false, "terminal attempt has an unparsable timestamp")
  if updated < started:
    return (0, false, "terminal attempt updated_at precedes run_started_at")
  (int(updated - started), true, "")

func p50Seconds*(values: seq[int]): float {.raises: [].} =
  ## Sorted integer seconds; odd n = middle, even n = mean of the two middle
  ## values (so a historical 574.5 is representable).
  if values.len == 0:
    return 0.0
  var v = values
  v.sort()
  result = if v.len mod 2 == 1:
             float(v[v.len div 2])
           else:
             (float(v[v.len div 2 - 1]) + float(v[v.len div 2])) / 2.0

func formatNumber*(x: float): string {.raises: [].} =
  let i = int(x)
  if x == float(i):
    $i
  else:
    $x

func formatOneDecimal*(x: float): string {.raises: [].} =
  let scaled = int(x * 10.0 + 0.5)
  $(scaled div 10) & "." & $(scaled mod 10)

func meanSeconds*(values: seq[int]): float {.raises: [].} =
  if values.len == 0:
    return 0.0
  var total = 0.0
  for v in values:
    total += float(v)
  total / float(values.len)

func latencyStats*(values: seq[int]): LatencyStats {.raises: [].} =
  if values.len == 0:
    return LatencyStats()
  var sorted = values
  sorted.sort()
  result = LatencyStats(
    n: sorted.len,
    p50: p50Seconds(sorted),
    mean: meanSeconds(values),
    minSeconds: sorted[0],
    maxSeconds: sorted[^1])

# ═══════════════════════════════════════════════════════════════════════════
# §4. Pure core — classification (§4 of the contract)
# ═══════════════════════════════════════════════════════════════════════════

const
  JudgmentCasSignature* = "judgment_cas: decision file key"

  IdentitySignatures* = [
    "PLAN_COMPONENT_MISMATCH",
    "EVIDENCE_SUBJECT_DIVERGENCE",
    "MINT_IDENTITY_DIVERGENCE",
    "run_head_mismatch"]

  CertificateRefusalCodes* = ["NO_CERT", "SUBJECT_MISMATCH"]

  SoundnessSignatures* = [
    "SOUNDNESS_FAILURE",
    "false clProved",
    "missing dependency supply",
    "dependency supply missing"]

  ProjectionSignatures* = [
    "FAILURE_PROJECTION",
    "refusal class lost",
    "refusal-class lost"]

  LegitSignatures* = [
    "TRUST_SURFACE_MODIFIED",
    "ROT_ALLOWLIST"]

  RefusalMarkers* = [
    "SUBJECT_REGISTRY_UNAVAILABLE",
    "SUBJECT_PIN_REJECTED",
    "DOCUMENT_INVALID",
    "DOCUMENT_ABSENT",
    "C_OUT_OVERLAY_REFUSAL",
    "CARRIER_UNCONSTRUCTIBLE",
    "SIZING_REFUSAL",
    "REM_REFUSAL",
    "subject-pin",
    "subject pin",
    "document invalid",
    "document absent",
    "refusal"]

func containsAny(text: string, needles: openArray[string]): bool {.raises: [].} =
  for n in needles:
    if n.len > 0 and text.contains(n):
      return true
  false

func hasIdentityDivergence*(text: string): bool {.raises: [].} =
  if containsAny(text, IdentitySignatures):
    return true
  result = text.contains(JudgmentCasSignature) and
    text.contains("freshly re-derived")

func hasSoundnessFailure*(text: string): bool {.raises: [].} =
  result = containsAny(text, SoundnessSignatures)

func emptyCanonicalDigest*(text: string): bool {.raises: [].} =
  ## Empty canonical digest: the #186 projection-defect signature.
  for rawLine in text.splitLines():
    let line = rawLine.strip()
    if line.startsWith("canonical_digest="):
      if line.len == "canonical_digest=".len:
        return true
    elif line.startsWith("canonical_digest:"):
      if line.len <= "canonical_digest:".len:
        return true
      let rest = line["canonical_digest:".len .. ^1].strip()
      if rest.len == 0 or rest == "\"\"" or rest == "''":
        return true
    elif line.contains("\"canonicalRunDigest\"") or
         line.contains("\"canonical_digest\""):
      let compact = line.replace(" ", "").replace("\t", "")
      if "\"canonicalRunDigest\":\"\"" in compact or
         "\"canonical_digest\":\"\"" in compact:
        return true
  result = false

func projectionLostAsInternal*(text: string): bool {.raises: [].} =
  ## #186 class: a prepare-phase refusal surfaced as INTERNAL_ERROR (exit 2)
  ## instead of INVALID_INPUT (exit 3).
  if not text.contains("INTERNAL_ERROR"):
    return false
  if containsAny(text, RefusalMarkers):
    return true
  let lower = text.toLowerAscii()
  containsAny(lower, ["refusal", "subject-pin", "subject registry",
                      "document invalid", "document absent", "c_out",
                      "carrier", "sizing"])

func hasFailureProjection*(text: string): bool {.raises: [].} =
  result = containsAny(text, ProjectionSignatures) or
    emptyCanonicalDigest(text) or
    projectionLostAsInternal(text)

func legitimatePolicyRefusal*(text: string): bool {.raises: [].} =
  ## Policy refusals that are accepted-by-policy: TRUST_SURFACE_MODIFIED and
  ## ROT_ALLOWLIST on their own, or an explicit subject-pin/document refusal
  ## (INVALID_INPUT, exit 3). Identity divergence is checked FIRST by the
  ## caller, so a refusal that also carries an identity signature never becomes
  ## legitimate_policy.
  if containsAny(text, LegitSignatures):
    return true
  if not text.contains("INVALID_INPUT"):
    return false
  if containsAny(text, RefusalMarkers):
    return true
  let lower = text.toLowerAscii()
  result = containsAny(lower, ["subject-pin", "subject pin", "subject registry",
                               "document invalid", "document absent", "refusal",
                               "carrier", "sizing", "c_out"])

func reasonCodeValue*(text: string): string {.raises: [].} =
  ## Extract the value of a verdict `reasonCode` field (reasonCode=CODE,
  ## reasonCode: CODE, "reasonCode": "CODE"). Empty when absent.
  var i = 0
  while i < text.len:
    let at = text.find("reasonCode", i)
    if at < 0:
      break
    var j = at + "reasonCode".len
    while j < text.len and text[j] in {' ', '\t'}:
      inc j
    if j < text.len and (text[j] == '=' or text[j] == ':'):
      inc j
      while j < text.len and text[j] in {' ', '\t', '"', '\''}:
        inc j
      let start = j
      while j < text.len and
          text[j] in {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_', '-'}:
        inc j
      if j > start:
        return text[start ..< j]
    i = at + "reasonCode".len
  result = ""

func certificateRefusalCode*(text: string): string {.raises: [].} =
  let code = reasonCodeValue(text)
  result = if code in CertificateRefusalCodes: code else: ""

func isMintJob*(name: string): bool {.raises: [].} =
  let lower = name.toLowerAscii()
  result = lower.startsWith("mint") or "certificate" in lower

func mintJobs*(a: ObservedAttempt): seq[ObservedJob] {.raises: [].} =
  for j in a.jobs:
    if isMintJob(j.name):
      result.add j

func certificateRefusalClass*(a: ObservedAttempt): AttemptClass {.raises: [].} =
  ## NO_CERT / SUBJECT_MISMATCH is never guessed from the text alone. The same
  ## attempt's mint/certificate jobs decide: all success => the verifier refused
  ## a certificate the attempt produced; otherwise unclassified.
  let evPtr = "run:" & a.runId & "/attempt:" & $a.attemptNumber
  if not a.jobsObserved:
    return AttemptClass(kind: ckUnclassified,
                        subtypeDetail: "mint_failed_unattributed",
                        evidence: evPtr & "/jobs:missing",
                        gap: true,
                        gapReason: (if a.jobsError.len > 0: a.jobsError
                                    else: "jobs unobservable"))
  let mint = mintJobs(a)
  if mint.len == 0:
    return AttemptClass(kind: ckUnclassified,
                        subtypeDetail: "mint_failed_unattributed",
                        evidence: evPtr & "/jobs:mint-absent",
                        detail: "no mint/certificate job observable")
  for j in mint:
    if j.status != "completed" or j.conclusion != "success":
      return AttemptClass(kind: ckUnclassified,
                          subtypeDetail: "mint_failed_unattributed",
                          evidence: evPtr & "/jobs:mint-failed:" & j.name,
                          detail: "mint/certificate job did not succeed")
  AttemptClass(kind: ckInternalDefect,
               subtype: dsIdentityDivergence,
               subtypeDetail: "certificate_present_but_unbound",
               evidence: evPtr & "/jobs:mint-success",
               detail: "verifier refused a certificate the same attempt produced")

func signatureNeedles*(subtype: DefectSubtype): seq[string] {.raises: [].} =
  result = case subtype
    of dsSoundnessFailure:
      @SoundnessSignatures
    of dsIdentityDivergence:
      @IdentitySignatures & @[JudgmentCasSignature, "freshly re-derived"]
    of dsFailureProjection:
      @ProjectionSignatures & @["canonical_digest", "canonicalRunDigest",
                                "INTERNAL_ERROR"]
    of dsAuthoritySubstitution:
      @[]
    of dsNone:
      @[]

func findEvidence(a: ObservedAttempt, needles: openArray[string]):
    string {.raises: [].} =
  ## Stable evidence pointer to the first artifact/log that carries a
  ## signature. Artifacts are preferred over logs (§4.6).
  for f in a.artifacts:
    if needles.len == 0 or containsAny(f.text, needles):
      return "run:" & a.runId & "/attempt:" & $a.attemptNumber &
             "/artifact:" & f.name
  for f in a.logs:
    if needles.len == 0 or containsAny(f.text, needles):
      return "run:" & a.runId & "/attempt:" & $a.attemptNumber &
             "/log:" & f.name
  result = "run:" & a.runId & "/attempt:" & $a.attemptNumber & "/evidence"

func attemptText*(a: ObservedAttempt): string {.raises: [].} =
  for f in a.artifacts:
    result.add f.text
    result.add "\n"
  for f in a.logs:
    result.add f.text
    result.add "\n"

func classifyAttempt*(a: ObservedAttempt, replacementExists,
                      replacementObserved: bool): AttemptClass {.raises: [].} =
  let evPtr = "run:" & a.runId & "/attempt:" & $a.attemptNumber
  if a.attemptListGap:
    return AttemptClass(kind: ckUnclassified, evidence: evPtr & "/attempts:missing",
                        gap: true, gapReason: "attempt list unobservable")
  if a.status.len > 0 and a.status != "completed":
    return AttemptClass(kind: ckUnclassified,
                        evidence: evPtr & "/status:" & a.status,
                        gap: true, gapReason: "attempt not terminal (status=" &
                                             a.status & ")")
  if a.conclusion == "success":
    return AttemptClass(kind: ckSuccess, evidence: evPtr & "/conclusion:success")
  if a.conclusion == "cancelled":
    if not replacementObserved:
      return AttemptClass(kind: ckUnclassified,
                          evidence: evPtr & "/conclusion:cancelled",
                          gap: true,
                          gapReason: "replacement context unobservable")
    if replacementExists:
      return AttemptClass(kind: ckCancelledSuperseded,
                          evidence: evPtr & "/conclusion:cancelled/replacement")
    return AttemptClass(kind: ckUnclassified,
                        evidence: evPtr & "/conclusion:cancelled",
                        gap: false,
                        detail: "cancelled without a same-window replacement")
  let text = attemptText(a)
  if text.strip().len == 0:
    let why =
      if a.evidenceError.len > 0: a.evidenceError
      else: "no artifact or log evidence available"
    return AttemptClass(kind: ckUnclassified, evidence: evPtr & "/evidence:missing",
                        gap: true, gapReason: why)
  if hasSoundnessFailure(text):
    return AttemptClass(kind: ckInternalDefect, subtype: dsSoundnessFailure,
                        evidence: findEvidence(a, signatureNeedles(dsSoundnessFailure)),
                        detail: "soundness_failure signature observed")
  if hasIdentityDivergence(text):
    return AttemptClass(kind: ckInternalDefect, subtype: dsIdentityDivergence,
                        evidence: findEvidence(a, signatureNeedles(dsIdentityDivergence)),
                        detail: "identity_divergence signature observed")
  if hasFailureProjection(text):
    return AttemptClass(kind: ckInternalDefect, subtype: dsFailureProjection,
                        evidence: findEvidence(a, signatureNeedles(dsFailureProjection)),
                        detail: "failure_projection signature observed")
  if certificateRefusalCode(text).len > 0:
    return certificateRefusalClass(a)
  if legitimatePolicyRefusal(text):
    return AttemptClass(kind: ckLegitimatePolicy,
                        evidence: findEvidence(a, @LegitSignatures & @["INVALID_INPUT"]),
                        detail: "legitimate policy refusal")
  result = AttemptClass(kind: ckUnclassified, evidence: evPtr & "/evidence:no-signature",
                        gap: false,
                        detail: "failure evidence carries no pre-registered signature")

func kindRank(k: ClassificationKind): int {.raises: [].} =
  result = case k
    of ckInternalDefect: 4
    of ckUnclassified: 3
    of ckLegitimatePolicy: 2
    of ckSuccess: 1
    of ckCancelledSuperseded: 0

func subtypeRank(s: DefectSubtype): int {.raises: [].} =
  result = case s
    of dsAuthoritySubstitution: 4
    of dsSoundnessFailure: 3
    of dsIdentityDivergence: 2
    of dsFailureProjection: 1
    of dsNone: 0

func appIdsText(ids: seq[int]): string {.raises: [].} =
  var parts: seq[string]
  for id in ids:
    parts.add $id
  parts.join(",")

func classifyEntry*(e: ObservedEntry): EntryClass {.raises: [].} =
  ## Worst-of across attempts. Retries never erase an incident. Verifier
  ## identity is an entry-level precondition: admission-check must come from
  ## the required App (5795152), not merely from an Actions check with the
  ## same name.
  if not e.authorityObserved:
    return EntryClass(kind: ckUnclassified,
                      evidence: "entry:" & e.headSha & "/admission-check:unobservable",
                      gap: true,
                      gapReason: (if e.authorityGap.len > 0: e.authorityGap
                                  else: "check-runs unobservable"))
  if not e.admissionAppHasRequired:
    return EntryClass(kind: ckInternalDefect,
                      subtype: dsAuthoritySubstitution,
                      evidence: "entry:" & e.headSha & "/admission-check:apps=" &
                                appIdsText(e.admissionAppIds),
                      detail: "required verifier app " &
                              $RequiredAdmissionAppId &
                              " did not produce admission-check")
  if e.attempts.len == 0:
    return EntryClass(kind: ckUnclassified,
                      evidence: "entry:" & e.headSha & "/attempts:missing",
                      gap: true, gapReason: "entry has no observed attempts")
  var
    best = EntryClass(kind: ckCancelledSuperseded)
    bestRank = -1
    anyGap = false
    gapReasons: seq[string]
    allCancelled = true
  for a in e.attempts:
    let ac = classifyAttempt(a, e.replacementExists, e.replacementObserved)
    if ac.kind != ckCancelledSuperseded:
      allCancelled = false
    if ac.gap:
      anyGap = true
      if ac.gapReason.len > 0:
        gapReasons.add ac.gapReason
    let r = kindRank(ac.kind)
    if r > bestRank or
        (r == bestRank and subtypeRank(ac.subtype) > subtypeRank(best.subtype)):
      bestRank = r
      best = EntryClass(kind: ac.kind, subtype: ac.subtype,
                        subtypeDetail: ac.subtypeDetail,
                        evidence: ac.evidence, detail: ac.detail,
                        gap: false)
  if allCancelled:
    best = EntryClass(kind: ckCancelledSuperseded,
                      evidence: "entry:" & e.headSha & "/cancelled:superseded")
  best.gap = anyGap
  if anyGap:
    best.gapReason = gapReasons.join("; ")
  result = best

# ═══════════════════════════════════════════════════════════════════════════
# §5. Pure core — entry construction, window selection, acceptance report
# ═══════════════════════════════════════════════════════════════════════════

func fallbackAttempt(r: ObservedRun): ObservedAttempt {.raises: [].} =
  ObservedAttempt(
    runId: r.runId,
    attemptNumber: (if r.runAttempt > 0: r.runAttempt else: 1),
    status: r.status,
    conclusion: r.conclusion,
    runStartedAt: r.startedAt,
    updatedAt: r.updatedAt,
    evidenceFetched: false,
    evidenceError: (if r.gapReason.len > 0: r.gapReason
                    else: "attempt list unavailable"),
    attemptListGap: true)

func buildEntries*(runs: seq[ObservedRun]): seq[ObservedEntry] {.raises: [].} =
  ## Group admission-gate runs by unique merge_group head_sha. Re-runs and
  ## re-entries for the same head_sha collapse into one entry.
  for r in runs:
    if r.headSha.len == 0:
      continue
    var idx = -1
    for i, e in result:
      if e.headSha == r.headSha:
        idx = i
        break
    if idx < 0:
      result.add ObservedEntry(headSha: r.headSha, baseSha: r.baseSha,
                               prNumber: r.prNumber, runIds: @[r.runId])
      idx = result.high
    if result[idx].baseSha.len == 0:
      result[idx].baseSha = r.baseSha
    if result[idx].prNumber == 0:
      result[idx].prNumber = r.prNumber
    if r.runId notin result[idx].runIds:
      result[idx].runIds.add r.runId
    var atts = r.attempts
    if atts.len == 0 or not r.attemptsObserved:
      atts = @[fallbackAttempt(r)]
    for a in atts:
      var duplicate = false
      for existing in result[idx].attempts:
        if existing.runId == a.runId and
            existing.attemptNumber == a.attemptNumber:
          duplicate = true
          break
      if not duplicate:
        result[idx].attempts.add a
  for i in 0 ..< result.len:
    result[i].attempts.sort(cmpAttempt)
    result[i].runIds.sort()
  result

func entrySortKey(e: ObservedEntry): tuple[known: int, start: int64] {.raises: [].} =
  let idx = terminalAttemptIndex(e)
  if idx < 0:
    return (1, 0'i64)
  let (v, ok) = parseIsoUtc(e.attempts[idx].runStartedAt)
  if not ok:
    return (1, 0'i64)
  result = (0, v)

func cmpEntryByStart(a, b: ObservedEntry): int {.raises: [].} =
  let ka = entrySortKey(a)
  let kb = entrySortKey(b)
  if ka.known != kb.known:
    return cmp(ka.known, kb.known)
  if ka.start != kb.start:
    return cmp(ka.start, kb.start)
  result = cmp(a.headSha, b.headSha)

func selectWindow*(entries: seq[ObservedEntry], window: int,
                   mode = wmInitial): seq[ObservedEntry] {.raises: [].} =
  ## Post-boundary entries ordered by terminal run_started_at ascending.
  ## initial = the FIRST `window`; rolling = the LAST `window`. Unknown
  ## ancestry stays in the candidate set as an unclassified gap. A short
  ## window is returned short; the report marks it INCOMPLETE.
  var candidates: seq[ObservedEntry]
  for e in entries:
    if e.postBoundary or not e.ancestryObserved:
      candidates.add e
  candidates.sort(cmpEntryByStart)
  if window <= 0:
    return @[]
  let n = min(window, candidates.len)
  result = case mode
    of wmInitial: candidates[0 ..< n]
    of wmRolling: candidates[candidates.len - n .. ^1]

func gapOf(e: ObservedEntry): seq[string] {.raises: [].} =
  if not e.ancestryObserved:
    result.add "boundary ancestry unobservable for " & e.headSha
  if e.boundaryGap.len > 0:
    result.add e.boundaryGap
  if not e.authorityObserved:
    result.add (if e.authorityGap.len > 0: e.authorityGap
                else: "admission-check check-runs unobservable for " & e.headSha)
  if e.attempts.len == 0:
    result.add "entry " & e.headSha & " has no observed attempts"

func entryReportOf(e: ObservedEntry): EntryReport {.raises: [].} =
  let ec = classifyEntry(e)
  let wall = entryCanonicalWallSeconds(e)
  let legacy = entryLegacyWallSeconds(e)
  result = EntryReport(
    runId: terminalAttempt(e).runId,
    runIds: e.runIds,
    headSha: e.headSha,
    baseSha: e.baseSha,
    prNumber: e.prNumber,
    conclusion: terminalAttempt(e).conclusion,
    classification: ec.kind,
    subtype: ec.subtype,
    subtypeDetail: ec.subtypeDetail,
    evidence: ec.evidence,
    wallSeconds: wall.seconds,
    wallObserved: wall.observed,
    legacyWallSeconds: legacy.seconds,
    legacyWallObserved: legacy.observed,
    admissionAppIds: e.admissionAppIds,
    gap: ec.gap,
    gapReason: ec.gapReason,
    postBoundary: e.postBoundary)
  for a in e.attempts:
    result.attemptIds.add(a.runId & ":" & $a.attemptNumber)
    let ac = classifyAttempt(a, e.replacementExists, e.replacementObserved)
    result.details.add("run:" & a.runId & "/attempt:" & $a.attemptNumber &
                       "=" & $ac.kind &
                       (if ac.subtype != dsNone: "/" & $ac.subtype else: "") &
                       (if ac.subtypeDetail.len > 0:
                          "[" & ac.subtypeDetail & "]" else: ""))
  if not e.ancestryObserved:
    result.classification = ckUnclassified
    result.subtype = dsNone
    result.subtypeDetail = ""
    result.evidence = "entry:" & e.headSha & "/ancestry:unobservable"
    result.gap = true
    result.gapReason = "boundary ancestry unobservable"
  if not wall.observed:
    result.wallObserved = false
    result.wallSeconds = 0
    result.gap = true
    if result.gapReason.len == 0:
      result.gapReason = wall.reason
    else:
      result.gapReason.add "; " & wall.reason

func buildReport*(entries: seq[ObservedEntry], repo, boundary, generatedAt: string,
                  window: int, mode = wmInitial): AcceptanceReport {.raises: [].} =
  let selected = selectWindow(entries, window, mode)
  result = AcceptanceReport(
    schemaVersion: SchemaVersion,
    contract: ContractPath,
    generatedAt: generatedAt,
    repo: repo,
    boundary: boundary,
    excludedBeforeBoundary: block:
      var n = 0
      for e in entries:
        if e.ancestryObserved and not e.postBoundary:
          inc n
      n)
  var gapList: seq[string]
  var wallValues: seq[int]
  var legacyValues: seq[int]
  for e in selected:
    let er = entryReportOf(e)
    result.entries.add er
    for g in gapOf(e):
      if g notin gapList:
        gapList.add g
    if er.gap and er.gapReason.len > 0:
      for g in er.gapReason.split("; "):
        if g.len > 0 and g notin gapList:
          gapList.add g
    if er.wallObserved:
      wallValues.add er.wallSeconds
    if er.legacyWallObserved:
      legacyValues.add er.legacyWallSeconds
    case er.classification
    of ckSuccess: inc result.acceptance.success
    of ckLegitimatePolicy: inc result.acceptance.legitimatePolicy
    of ckInternalDefect:
      inc result.acceptance.internalDefect
      case er.subtype
      of dsIdentityDivergence: inc result.acceptance.identityDivergence
      of dsSoundnessFailure: inc result.acceptance.soundnessFailure
      of dsFailureProjection: inc result.acceptance.failureProjection
      of dsAuthoritySubstitution: inc result.acceptance.authoritySubstitution
      of dsNone: discard
    of ckUnclassified: inc result.acceptance.unclassified
    of ckCancelledSuperseded: inc result.acceptance.cancelledSuperseded
  result.acceptance.mode = mode
  result.acceptance.requestedWindow = window
  result.acceptance.observedEntries = selected.len
  result.acceptance.shortfall = max(0, window - selected.len)
  result.acceptance.unexpectedInternalDefects = result.acceptance.internalDefect
  result.acceptance.gaps = gapList
  result.acceptance.observationComplete = gapList.len == 0 and selected.len > 0
  result.acceptance.predicateHolds =
    result.acceptance.shortfall == 0 and
    result.acceptance.unexpectedInternalDefects == 0 and
    result.acceptance.unclassified == 0
  result.acceptance.accepted =
    result.acceptance.predicateHolds and result.acceptance.observationComplete
  if result.acceptance.accepted:
    result.acceptance.status = asAccepted
  elif result.acceptance.shortfall > 0 or
       not result.acceptance.observationComplete:
    result.acceptance.status = asIncomplete
  else:
    result.acceptance.status = asFailed
  let canonical = latencyStats(wallValues)
  result.acceptance.latencyN = canonical.n
  result.acceptance.latencyP50 = canonical.p50
  result.acceptance.latencyMean = canonical.mean
  result.acceptance.latencyMin = canonical.minSeconds
  result.acceptance.latencyMax = canonical.maxSeconds
  let legacy = latencyStats(legacyValues)
  result.acceptance.legacyLatencyN = legacy.n
  result.acceptance.legacyLatencyP50 = legacy.p50
  result.acceptance.legacyLatencyMean = legacy.mean

# ═══════════════════════════════════════════════════════════════════════════
# §6. Pure core — JSON / Markdown report rendering
# ═══════════════════════════════════════════════════════════════════════════

func strArray(items: seq[string]): JsonNode {.raises: [].} =
  result = newJArray()
  for it in items:
    result.add %it

func intArray(items: seq[int]): JsonNode {.raises: [].} =
  result = newJArray()
  for it in items:
    result.add %it

func entryJson(e: EntryReport): JsonNode {.raises: [].} =
  result = %*{
    "run_id": e.runId,
    "run_ids": strArray(e.runIds),
    "attempt_ids": strArray(e.attemptIds),
    "head_sha": e.headSha,
    "base_sha": e.baseSha,
    "pr_number": e.prNumber,
    "conclusion": e.conclusion,
    "classification": $e.classification,
    "subtype": $e.subtype,
    "subtype_detail": e.subtypeDetail,
    "evidence": e.evidence,
    "wall_seconds": e.wallSeconds,
    "wall_observed": e.wallObserved,
    "legacy_wall_seconds":
      (if e.legacyWallObserved: %e.legacyWallSeconds else: newJNull()),
    "legacy_wall_observed": e.legacyWallObserved,
    "admission_app_ids": intArray(e.admissionAppIds),
    "gap": e.gap,
    "gap_reason": e.gapReason,
    "post_boundary": e.postBoundary,
    "attempts": strArray(e.details)}

func reportJson*(r: AcceptanceReport): JsonNode {.raises: [].} =
  var entries = newJArray()
  for e in r.entries:
    entries.add entryJson(e)
  result = %*{
    "schema_version": r.schemaVersion,
    "contract": r.contract,
    "generated_at": r.generatedAt,
    "repo": r.repo,
    "boundary": r.boundary,
    "excluded_before_boundary": r.excludedBeforeBoundary,
    "entries": entries,
    "counts": {
      "success": r.acceptance.success,
      "legitimate_policy": r.acceptance.legitimatePolicy,
      "internal_defect": r.acceptance.internalDefect,
      "unclassified": r.acceptance.unclassified,
      "cancelled_superseded": r.acceptance.cancelledSuperseded,
      "internal_defect_subtypes": {
        "identity_divergence": r.acceptance.identityDivergence,
        "soundness_failure": r.acceptance.soundnessFailure,
        "failure_projection": r.acceptance.failureProjection,
        "authority_substitution": r.acceptance.authoritySubstitution}},
    "acceptance": {
      "mode": $r.acceptance.mode,
      "status": $r.acceptance.status,
      "requested_window": r.acceptance.requestedWindow,
      "observed_entries": r.acceptance.observedEntries,
      "shortfall": r.acceptance.shortfall,
      "unexpected_internal_defects": r.acceptance.unexpectedInternalDefects,
      "unclassified": r.acceptance.unclassified,
      "predicate_holds": r.acceptance.predicateHolds,
      "observation_complete": r.acceptance.observationComplete,
      "accepted": r.acceptance.accepted,
      "gaps": strArray(r.acceptance.gaps)},
    "latency": {
      "n": r.acceptance.latencyN,
      "p50_seconds": r.acceptance.latencyP50,
      "mean_seconds": r.acceptance.latencyMean,
      "min_seconds": r.acceptance.latencyMin,
      "max_seconds": r.acceptance.latencyMax,
      "legacy_n": r.acceptance.legacyLatencyN,
      "legacy_p50_seconds": r.acceptance.legacyLatencyP50,
      "legacy_mean_seconds": r.acceptance.legacyLatencyMean,
      "formula": "max(job.completed_at) - min(job.started_at) over the terminal attempt's jobs with both timestamps; sorted integer seconds; even n = mean of the two middle values",
      "legacy_formula": "terminal attempt updated_at - run_started_at; non-canonical, continuity only"}}

func renderMarkdown*(r: AcceptanceReport): string {.raises: [].} =
  result = "# CI Acceptance Contract v2 — report\n\n"
  result.add "- contract: `" & r.contract & "`\n"
  result.add "- repo: `" & r.repo & "`\n"
  result.add "- boundary: `" & r.boundary & "`\n"
  result.add "- generated_at: `" & r.generatedAt & "`\n"
  result.add "- mode: `" & $r.acceptance.mode & "`\n"
  result.add "- status: **" & $r.acceptance.status & "**\n"
  result.add "- window: " & $r.acceptance.mode & " " &
             $r.acceptance.requestedWindow &
             " post-boundary entries (observed n=" &
             $r.acceptance.observedEntries & ", shortfall=" &
             $r.acceptance.shortfall & ", excluded " &
             $r.excludedBeforeBoundary & " pre-boundary)\n"
  result.add "- latency (canonical, terminal-attempt job span): n=" &
             $r.acceptance.latencyN & ", p50=" &
             formatOneDecimal(r.acceptance.latencyP50) & "s, mean=" &
             formatOneDecimal(r.acceptance.latencyMean) & "s, min=" &
             $r.acceptance.latencyMin & "s, max=" &
             $r.acceptance.latencyMax & "s\n"
  result.add "- latency (legacy, non-canonical updated_at - run_started_at): n=" &
             $r.acceptance.legacyLatencyN & ", p50=" &
             formatOneDecimal(r.acceptance.legacyLatencyP50) & "s, mean=" &
             formatOneDecimal(r.acceptance.legacyLatencyMean) & "s\n\n"
  result.add "## Verdict\n\n"
  result.add "| field | value |\n|---|---|\n"
  result.add "| mode | " & $r.acceptance.mode & " |\n"
  result.add "| status | " & $r.acceptance.status & " |\n"
  result.add "| accepted | " & $r.acceptance.accepted & " |\n"
  result.add "| predicate_holds | " & $r.acceptance.predicateHolds & " |\n"
  result.add "| observation_complete | " &
             $r.acceptance.observationComplete & " |\n"
  result.add "| requested_window | " & $r.acceptance.requestedWindow & " |\n"
  result.add "| observed_entries | " & $r.acceptance.observedEntries & " |\n"
  result.add "| shortfall | " & $r.acceptance.shortfall & " |\n"
  result.add "| unexpected_internal_defects | " &
             $r.acceptance.unexpectedInternalDefects & " |\n"
  result.add "| unclassified | " & $r.acceptance.unclassified & " |\n"
  result.add "| legitimate_policy (reported, not failed) | " &
             $r.acceptance.legitimatePolicy & " |\n"
  result.add "| success | " & $r.acceptance.success & " |\n"
  result.add "| cancelled_superseded | " &
             $r.acceptance.cancelledSuperseded & " |\n\n"
  result.add "## Internal defect subtypes\n\n"
  result.add "| subtype | count |\n|---|---:|\n"
  result.add "| identity_divergence | " & $r.acceptance.identityDivergence & " |\n"
  result.add "| soundness_failure | " & $r.acceptance.soundnessFailure & " |\n"
  result.add "| failure_projection | " & $r.acceptance.failureProjection & " |\n"
  result.add "| authority_substitution | " & $r.acceptance.authoritySubstitution & " |\n\n"
  result.add "## Entries\n\n"
  result.add "| run_id | head_sha | base_sha | PR | conclusion | classification | subtype | detail | wall_s | legacy_s | admission_app_ids | evidence | gap |\n"
  result.add "|---|---|---|---:|---|---|---|---|---:|---:|---|---|---|\n"
  for e in r.entries:
    var appIds: seq[string]
    for id in e.admissionAppIds:
      appIds.add $id
    result.add "| " & e.runId & " | `" & e.headSha[0 ..< min(12, e.headSha.len)] &
               "` | `" & e.baseSha[0 ..< min(12, e.baseSha.len)] & "` | " &
               $e.prNumber & " | " & e.conclusion & " | " & $e.classification &
               " | " & $e.subtype & " | " & e.subtypeDetail & " | " &
               (if e.wallObserved: $e.wallSeconds else: "—") & " | " &
               (if e.legacyWallObserved: $e.legacyWallSeconds else: "—") &
               " | " & appIds.join(",") & " | `" &
               e.evidence & "` | " & (if e.gap: "YES" else: "no") & " |\n"
  result.add "\n## Attempts per entry\n\n"
  for e in r.entries:
    result.add "- `" & e.headSha[0 ..< min(12, e.headSha.len)] & "` run " &
               e.runId & ": " & e.attemptIds.join(", ") & "\n"
    for d in e.details:
      result.add "  - " & d & "\n"
  result.add "\n## Gaps\n\n"
  if r.acceptance.gaps.len == 0:
    result.add "none\n"
  else:
    for g in r.acceptance.gaps:
      result.add "- " & g & "\n"

# ═══════════════════════════════════════════════════════════════════════════
# §7. Pure core — --recompute-baseline (same formula as §6 of the contract)
# ═══════════════════════════════════════════════════════════════════════════

func jsonStr(node: JsonNode, key: string): string {.raises: [].} =
  if node != nil and node.kind == JObject:
    let v = node{key}
    if v != nil:
      case v.kind
      of JString: return v.getStr()
      of JInt: return $v.getInt()
      of JFloat: return $v.getFloat()
      else: discard
  result = ""

func jsonArr(node: JsonNode, key: string): JsonNode {.raises: [].} =
  if node != nil and node.kind == JObject:
    let v = node{key}
    if v != nil and v.kind == JArray:
      return v
  result = nil

func jsonInt(node: JsonNode, key: string, default = 0): int {.raises: [].} =
  if node != nil and node.kind == JObject:
    let v = node{key}
    if v != nil and v.kind == JInt:
      return v.getInt()
  result = default

func jobsFromJson(node: JsonNode): seq[ObservedJob] {.raises: [].} =
  let arr = jsonArr(node, "jobs")
  if arr == nil:
    return @[]
  for item in arr.items:
    if item == nil or item.kind != JObject:
      continue
    result.add ObservedJob(
      name: jsonStr(item, "name"),
      status: jsonStr(item, "status"),
      conclusion: jsonStr(item, "conclusion"),
      startedAt: jsonStr(item, "started_at"),
      completedAt: jsonStr(item, "completed_at"))

func durationFromNode(node: JsonNode, fallback: JsonNode): RunDuration {.raises: [].} =
  ## Canonical wall = job span of the row (or its terminal attempt); legacy wall
  ## = run_started_at -> updated_at. The two observations are independent:
  ## absent jobs never invent a canonical wall.
  var jobs = jobsFromJson(node)
  if jobs.len == 0 and fallback != nil:
    jobs = jobsFromJson(fallback)
  let canonical = jobSpanSeconds(jobs)
  result = RunDuration(
    runId: jsonStr(node, "run_id"),
    seconds: canonical.seconds,
    observed: canonical.observed,
    gapReason: canonical.reason)
  let (s, okStart) = parseIsoUtc(jsonStr(node, "run_started_at"))
  let (u, okUpdated) = parseIsoUtc(jsonStr(node, "updated_at"))
  if okStart and okUpdated and u >= s:
    result.legacySeconds = int(u - s)
    result.legacyObserved = true

func terminalListAttempt(attempts: JsonNode): JsonNode {.raises: [].} =
  ## Highest run_attempt; ties broken by the later run_started_at.
  result = nil
  if attempts == nil or attempts.kind != JArray:
    return nil
  for item in attempts.items:
    if item == nil or item.kind != JObject:
      continue
    if result == nil:
      result = item
      continue
    let a = jsonInt(item, "run_attempt", 0)
    let b = jsonInt(result, "run_attempt", 0)
    if a > b:
      result = item
    elif a == b:
      let (sa, oka) = parseIsoUtc(jsonStr(item, "run_started_at"))
      let (sb, okb) = parseIsoUtc(jsonStr(result, "run_started_at"))
      if oka and okb and sa > sb:
        result = item

func durationsFromRunList*(root: JsonNode): seq[RunDuration] {.raises: [].} =
  ## Accepts a top-level array or `{runs: [...]}` / `{workflow_runs: [...]}`.
  ## Each row may carry its own timestamps or an `attempts` array; when the
  ## latter exists the terminal attempt is used (the acceptance formula).
  var rows: JsonNode = nil
  if root != nil and root.kind == JArray:
    rows = root
  elif root != nil and root.kind == JObject:
    rows = jsonArr(root, "runs")
    if rows == nil:
      rows = jsonArr(root, "workflow_runs")
  if rows == nil:
    return @[]
  for row in rows.items:
    if row == nil or row.kind != JObject:
      continue
    let attempts = jsonArr(row, "attempts")
    var source = row
    var jobFallback: JsonNode = nil
    if attempts != nil and attempts.len > 0:
      let term = terminalListAttempt(attempts)
      if term != nil:
        source = term
        jobFallback = row
    var d = durationFromNode(source, jobFallback)
    if d.runId.len == 0:
      d.runId = jsonStr(row, "run_id")
    if d.runId.len == 0:
      d.runId = jsonStr(row, "id")
    result.add d

func baselineJson*(durations: seq[RunDuration],
                   mode = "recompute-baseline"): JsonNode {.raises: [].} =
  var values, legacyValues: seq[int]
  var rows = newJArray()
  var gaps: seq[string]
  for d in durations:
    let secondsNode = (if d.observed: %d.seconds else: newJNull())
    let legacyNode = (if d.legacyObserved: %d.legacySeconds else: newJNull())
    rows.add %*{"run_id": d.runId,
                "seconds": secondsNode,
                "observed": d.observed,
                "legacy_seconds": legacyNode,
                "legacy_observed": d.legacyObserved,
                "gap_reason": d.gapReason}
    if d.observed:
      values.add d.seconds
    else:
      gaps.add((if d.runId.len > 0: d.runId else: "<unknown>") & ": " &
               d.gapReason)
    if d.legacyObserved:
      legacyValues.add d.legacySeconds
  let canonical = latencyStats(values)
  let legacy = latencyStats(legacyValues)
  var sortedDisplay: seq[string]
  for v in values:
    sortedDisplay.add $v
  sortedDisplay.sort()
  result = %*{
    "schema_version": SchemaVersion,
    "mode": mode,
    "formula": "max(job.completed_at) - min(job.started_at) over jobs with both timestamps; sorted integer seconds; even n = mean of the two middle values",
    "legacy_formula": "updated_at - run_started_at; non-canonical, continuity only",
    "n": canonical.n,
    "excluded": durations.len - canonical.n,
    "p50_seconds": canonical.p50,
    "p50_display": formatNumber(canonical.p50),
    "mean_seconds": canonical.mean,
    "min_seconds": canonical.minSeconds,
    "max_seconds": canonical.maxSeconds,
    "legacy_n": legacy.n,
    "legacy_p50_seconds": legacy.p50,
    "legacy_mean_seconds": legacy.mean,
    "values_sorted": strArray(sortedDisplay),
    "gaps": strArray(gaps),
    "runs": rows}

func baselineComplete*(durations: seq[RunDuration]): bool {.raises: [].} =
  ## Completeness is canonical: every row must carry an observed job span.
  var observed = 0
  for d in durations:
    if not d.observed:
      return false
    inc observed
  result = observed > 0# ═══════════════════════════════════════════════════════════════════════════
# §8. Pure core — identity spellings used by the run list
# ═══════════════════════════════════════════════════════════════════════════

func isHex40*(s: string): bool {.raises: [].} =
  result = s.len == 40 and s.allCharsInSet(HexDigits)

func baseFromHeadBranch*(branch: string): string {.raises: [].} =
  ## gh-readonly-queue/main/pr-<N>-<base_sha> — the canonical queue record.
  if branch.len < 40:
    return ""
  let lastDash = branch.rfind('-')
  if lastDash < 0 or branch.len - lastDash - 1 != 40:
    return ""
  let cand = branch[lastDash + 1 .. ^1]
  result = if isHex40(cand): cand else: ""

func prFromHeadBranch*(branch: string): int {.raises: [].} =
  for i in 0 ..< branch.len - 2:
    if branch[i] == 'p' and branch[i + 1] == 'r' and branch[i + 2] == '-':
      var j = i + 3
      var v = 0
      var any = false
      while j < branch.len and branch[j] in {'0' .. '9'}:
        any = true
        v = v * 10 + (ord(branch[j]) - ord('0'))
        inc j
      if any:
        return v
  result = 0

# ═══════════════════════════════════════════════════════════════════════════
# §9. I/O boundary (the only impure layer; gh api GET only)
# ═══════════════════════════════════════════════════════════════════════════

type
  ApiResult = object
    ok: bool
    body: string
    err: string

proc die(msg: string, code = 2) {.noreturn.} =
  stderr.writeLine("[" & ToolName & "] " & msg)
  quit(code)

func firstLine(s: string): string {.raises: [].} =
  for line in s.splitLines():
    let t = line.strip()
    if t.len > 0:
      return t
  result = ""

proc safeParseJson(s: string): tuple[node: JsonNode, err: string] {.raises: [].} =
  try:
    (parseJson(s), "")
  except CatchableError as e:
    (nil, e.msg)

proc isoNow(): string {.axiomEffect: IoEffect.} =
  now().utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'")

proc ghApiGet(path: string): ApiResult {.axiomEffect: IoEffect.} =
  ## GET only. execCmdEx merges stdout/stderr; on success the body is JSON.
  let (output, code) = execCmdEx("gh api " & quoteShell(path))
  if code != 0:
    return ApiResult(ok: false,
                     err: "gh api " & path & " exited " & $code &
                          (if output.strip().len > 0:
                             ": " & firstLine(output) else: ""))
  ApiResult(ok: true, body: output)

proc ghApiDownload(path, dest: string):
    tuple[ok: bool, err: string] {.axiomEffect: IoEffect.} =
  ## Binary fetch (artifact/log zip) straight to a temp file — never through
  ## execCmdEx's captured stdout.
  let (output, code) = execCmdEx("gh api " & quoteShell(path) & " > " &
                                 quoteShell(dest) & " 2>/dev/null")
  if code != 0:
    return (false, "gh api download " & path & " exited " & $code &
                   (if output.strip().len > 0:
                      ": " & firstLine(output) else: ""))
  if not fileExists(dest) or getFileSize(dest) == 0:
    return (false, "gh api download " & path & " produced no bytes")
  (true, "")

proc unzipEntries(zip: string): seq[string] {.axiomEffect: IoEffect.} =
  let (output, code) = execCmdEx("unzip -Z1 " & quoteShell(zip) &
                                 " 2>/dev/null")
  if code != 0:
    return @[]
  for line in output.splitLines():
    let name = line.strip()
    if name.len > 0 and not name.endsWith("/"):
      result.add name

proc unzipText(zip, name: string, limit: int):
    tuple[ok: bool, text: string] {.axiomEffect: IoEffect.} =
  let (output, code) = execCmdEx("unzip -p " & quoteShell(zip) & " " &
                                 quoteShell(name) & " 2>/dev/null | head -c " &
                                 $limit)
  if code != 0:
    return (false, "")
  (true, output)

func isTextEvidence(name: string): bool {.raises: [].} =
  let lower = name.toLowerAscii()
  result = lower.endsWith(".json") or lower.endsWith(".log") or
    lower.endsWith(".txt") or lower.endsWith(".sha256") or
    lower.endsWith(".out") or lower.endsWith(".md") or
    lower.endsWith(".yml") or lower.endsWith(".yaml")

const
  AllowedArtifactPrefixes* = ["admission-verdict-", "admission-check-",
                              "judgment-record-", "evidence-record-",
                              "subject-certificate-"]
  AllowedArtifactExact* = ["derived-closure", "ci-select-decision"]

func deniedArtifactName*(name: string): bool {.raises: [].} =
  ## Caches and build trees are never evidence. Denying them by name keeps the
  ## allowlist from ever widening onto a cache artifact whose name happens to
  ## share a prefix.
  let lower = name.toLowerAscii()
  result = lower.contains("nimcache") or
    lower == "base-artifacts" or lower.endsWith("-base-artifacts") or
    lower == "bootstrap-artifacts" or lower.endsWith("-bootstrap-artifacts") or
    lower.startsWith("go-") or
    lower == "tested-tree-digest" or lower.endsWith("-tested-tree-digest")

func allowedArtifactName*(name: string): bool {.raises: [].} =
  ## Only text evidence artifacts named by §4.6 of the contract are downloaded.
  if name.len == 0 or deniedArtifactName(name):
    return false
  for prefix in AllowedArtifactPrefixes:
    if name.startsWith(prefix):
      return true
  for exact in AllowedArtifactExact:
    if name == exact:
      return true
  result = false

func selectArtifactNames*(names: seq[string]): seq[string] {.raises: [].} =
  ## Order-preserving, de-duplicated selection. Excluded names are never
  ## downloaded, so a cache artifact cannot reach the evidence extractor.
  for name in names:
    if allowedArtifactName(name) and name notin result:
      result.add name

func admissionCheckSummary*(checkRuns: JsonNode):
    tuple[appIds: seq[int], requiredPresent: bool,
          requiredSuccess: bool] {.raises: [].} =
  ## Identity invariant: the `admission-check` context must be produced by the
  ## required verifier App. A same-name check from another App is an authority
  ## substitution, never a substitute success.
  if checkRuns == nil or checkRuns.kind != JArray:
    return
  for item in checkRuns.items:
    if item == nil or item.kind != JObject:
      continue
    if jsonStr(item, "name") != "admission-check":
      continue
    var appId = 0
    let app = item{"app"}
    if app != nil and app.kind == JObject:
      appId = jsonInt(app, "id", 0)
    if appId notin result.appIds:
      result.appIds.add appId
    if appId == RequiredAdmissionAppId:
      result.requiredPresent = true
      if jsonStr(item, "conclusion") == "success":
        result.requiredSuccess = true

proc extractEvidence(zip, prefix: string, maxBytes: int):
    seq[EvidenceText] {.axiomEffect: IoEffect.} =
  ## Text files only, bounded in count and bytes. Evidence stays in memory
  ## after the temp zip is deleted.
  var names = unzipEntries(zip)
  names.sort()
  var total = 0
  var count = 0
  for name in names:
    if count >= 64 or total >= maxBytes:
      break
    if not isTextEvidence(name):
      continue
    let budget = min(maxBytes - total, 1_000_000)
    if budget <= 0:
      break
    let r = unzipText(zip, name, budget)
    if r.ok and r.text.len > 0:
      result.add EvidenceText(name: prefix & name, text: r.text)
      total += r.text.len
      inc count

proc listArtifacts(res: ApiResult): seq[JsonNode] {.raises: [].} =
  if not res.ok:
    return @[]
  let parsed = safeParseJson(res.body)
  if parsed.err.len > 0:
    return @[]
  let artifacts = jsonArr(parsed.node, "artifacts")
  if artifacts == nil:
    return @[]
  for a in artifacts.items:
    if a != nil and a.kind == JObject:
      result.add a

proc fetchAttemptEvidence(repo: string, a: var ObservedAttempt):
    bool {.axiomEffect: IoEffect.} =
  ## Artifacts first, logs as fallback (§4.6). Missing BOTH is an observation
  ## gap; returning false leaves the attempt unclassified-with-gap.
  if a.conclusion in ["success", "cancelled"]:
    a.evidenceFetched = true
    return true
  if a.attemptListGap:
    a.evidenceFetched = false
    if a.evidenceError.len == 0:
      a.evidenceError = "attempt list unobservable"
    return false

  let tmpDir = getTempDir() / ("axiom_ci_acceptance_" & a.runId & "_" &
                               $a.attemptNumber)
  try:
    if dirExists(tmpDir):
      removeDir(tmpDir)
    createDir(tmpDir)
  except CatchableError as exc:
    a.evidenceFetched = false
    a.evidenceError = "temp evidence directory unavailable: " & exc.msg
    return false

  var
    artifactErr = ""
    logErr = ""
  block artifacts:
    let listPath = "repos/" & repo & "/actions/runs/" & a.runId &
                   "/attempts/" & $a.attemptNumber & "/artifacts?per_page=100"
    let listed = ghApiGet(listPath)
    if not listed.ok:
      artifactErr = listed.err
    else:
      var used = 0
      for art in listArtifacts(listed):
        if used >= 16:
          break
        let name = jsonStr(art, "name")
        if not allowedArtifactName(name):
          continue
        let expired = art{"expired"}
        if expired != nil and expired.kind == JBool and expired.getBool():
          continue
        let id = jsonInt(art, "id", 0)
        if id <= 0:
          continue
        let zip = tmpDir / ("artifact_" & $id & ".zip")
        let dl = ghApiDownload("repos/" & repo & "/actions/artifacts/" &
                               $id & "/zip", zip)
        if not dl.ok:
          if artifactErr.len == 0:
            artifactErr = dl.err
          continue
        let files = extractEvidence(zip, name & "/", MaxArtifactBytes)
        if files.len == 0:
          if artifactErr.len == 0:
            artifactErr = "artifact " & name & " carried no text evidence"
        else:
          for f in files:
            a.artifacts.add f
          inc used
        removeFile(zip)
      if a.artifacts.len == 0 and artifactErr.len == 0:
        artifactErr = "no relevant admission artifact published"

  if a.artifacts.len == 0:
    block logs:
      let zip = tmpDir / "logs.zip"
      let dl = ghApiDownload("repos/" & repo & "/actions/runs/" & a.runId &
                             "/attempts/" & $a.attemptNumber & "/logs", zip)
      if not dl.ok:
        logErr = dl.err
      else:
        let files = extractEvidence(zip, "logs/", MaxLogBytes)
        if files.len == 0:
          logErr = "log archive carried no text evidence"
        else:
          for f in files:
            a.logs.add f
        removeFile(zip)

  try:
    removeDir(tmpDir)
  except CatchableError:
    discard # axiom:best-effort(temp dir cleanup must never mask a measurement)

  a.evidenceFetched = a.artifacts.len > 0 or a.logs.len > 0
  if not a.evidenceFetched:
    var parts: seq[string]
    if artifactErr.len > 0:
      parts.add "artifacts: " & artifactErr
    if logErr.len > 0:
      parts.add "logs: " & logErr
    a.evidenceError = "no artifact/log evidence available (" &
                      parts.join("; ") & ")"
  a.evidenceFetched

proc fetchAttemptJobs(repo: string, a: var ObservedAttempt, latest: bool):
    bool {.axiomEffect: IoEffect.} =
  ## Canonical wall input. The terminal attempt uses `filter=latest`; a
  ## non-terminal certificate-refusal attempt uses `filter=all` plus an exact
  ## `run_attempt` match. Failure leaves jobsObserved=false (observation gap).
  var jobs: seq[ObservedJob]
  var page = 1
  while page <= MaxJobPages:
    let path = "repos/" & repo & "/actions/runs/" & a.runId &
               "/jobs?per_page=100&page=" & $page &
               (if latest: "&filter=latest" else: "&filter=all")
    let res = ghApiGet(path)
    if not res.ok:
      a.jobsObserved = false
      a.jobsError = res.err
      return false
    let parsed = safeParseJson(res.body)
    if parsed.err.len > 0:
      a.jobsObserved = false
      a.jobsError = "job list is not JSON: " & parsed.err
      return false
    let raw = jsonArr(parsed.node, "jobs")
    if raw == nil:
      a.jobsObserved = false
      a.jobsError = "job list lacks jobs"
      return false
    for item in raw.items:
      if item == nil or item.kind != JObject:
        continue
      if not latest and jsonInt(item, "run_attempt", 0) != a.attemptNumber:
        continue
      jobs.add ObservedJob(
        name: jsonStr(item, "name"),
        status: jsonStr(item, "status"),
        conclusion: jsonStr(item, "conclusion"),
        startedAt: jsonStr(item, "started_at"),
        completedAt: jsonStr(item, "completed_at"))
    if raw.len < 100:
      a.jobs = jobs
      a.jobsObserved = true
      a.jobsError = ""
      return true
    inc page
  a.jobsObserved = false
  a.jobsError = "job list truncated at " & $MaxJobPages & " pages"
  false

proc runFromJson(node: JsonNode): ObservedRun {.raises: [].} =
  let headBranch = jsonStr(node, "head_branch")
  result = ObservedRun(
    runId: jsonStr(node, "id"),
    workflowName: jsonStr(node, "name"),
    workflowPath: jsonStr(node, "path"),
    event: jsonStr(node, "event"),
    headSha: jsonStr(node, "head_sha"),
    baseSha: baseFromHeadBranch(headBranch),
    prNumber: prFromHeadBranch(headBranch),
    runAttempt: jsonInt(node, "run_attempt", 1),
    startedAt: jsonStr(node, "run_started_at"),
    updatedAt: jsonStr(node, "updated_at"),
    createdAt: jsonStr(node, "created_at"),
    status: jsonStr(node, "status"),
    conclusion: jsonStr(node, "conclusion"),
    attemptsObserved: false)
  if result.startedAt.len == 0:
    result.startedAt = jsonStr(node, "created_at")
  let pulls = jsonArr(node, "pull_requests")
  if pulls != nil and pulls.len > 0:
    let first = pulls[0]
    if first != nil and first.kind == JObject:
      if result.prNumber == 0:
        result.prNumber = jsonInt(first, "number", 0)
      if result.baseSha.len == 0:
        let base = first{"base"}
        if base != nil and base.kind == JObject:
          result.baseSha = jsonStr(base, "sha")

func isAdmissionRun*(r: ObservedRun): bool {.raises: [].} =
  result = r.workflowName == "admission-gate" or
    r.workflowPath.endsWith("admission-gate-v2.yml")

proc fetchAdmissionRuns(repo, boundaryDate: string):
    tuple[runs: seq[ObservedRun], complete: bool, err: string] {.axiomEffect: IoEffect.} =
  var page = 1
  while page <= MaxRunPages:
    let path = "repos/" & repo & "/actions/runs?event=merge_group" &
               "&per_page=100&page=" & $page &
               "&created=%3E%3D" & boundaryDate
    let res = ghApiGet(path)
    if not res.ok:
      return (@[], false, res.err)
    let parsed = safeParseJson(res.body)
    if parsed.err.len > 0:
      return (@[], false, "run list is not JSON: " & parsed.err)
    let raw = jsonArr(parsed.node, "workflow_runs")
    if raw == nil:
      return (@[], false, "run list lacks workflow_runs")
    if raw.len == 0:
      return (result.runs, true, "")
    for item in raw.items:
      let r = runFromJson(item)
      if isAdmissionRun(r):
        result.runs.add r
    if raw.len < 100:
      return (result.runs, true, "")
    inc page
  (result.runs, false,
   "run list truncated at " & $MaxRunPages & " pages — cannot prove the window")

proc fetchAttempts(repo: string, r: var ObservedRun): string {.axiomEffect: IoEffect.} =
  let path = "repos/" & repo & "/actions/runs/" & r.runId &
             "/attempts?per_page=100"
  let res = ghApiGet(path)
  if not res.ok:
    return res.err
  let parsed = safeParseJson(res.body)
  if parsed.err.len > 0:
    return "attempt list is not JSON: " & parsed.err
  let raw = jsonArr(parsed.node, "workflow_runs")
  if raw == nil:
    return "attempt list lacks workflow_runs"
  let total = jsonInt(parsed.node, "total_count", raw.len)
  if total > 100:
    return "attempt list exceeds 100 entries (paginated observation unsupported)"
  var attempts: seq[ObservedAttempt]
  for item in raw.items:
    let attempt = ObservedAttempt(
      runId: r.runId,
      attemptNumber: jsonInt(item, "run_attempt", 1),
      status: jsonStr(item, "status"),
      conclusion: jsonStr(item, "conclusion"),
      runStartedAt: jsonStr(item, "run_started_at"),
      updatedAt: jsonStr(item, "updated_at"),
      evidenceFetched: false)
    if attempt.runStartedAt.len == 0:
      # The attempts endpoint always carries run_started_at; an absent value is
      # an observation gap, not a timestamp to guess.
      var broken = attempt
      broken.attemptListGap = true
      broken.evidenceError = "attempt lacks run_started_at"
      attempts.add broken
    else:
      attempts.add attempt
  attempts.sort(cmpAttempt)
  r.attempts = attempts
  ""

proc attachAttempts(runs: var seq[ObservedRun], repo: string):
    seq[string] {.axiomEffect: IoEffect.} =
  for r in runs.mitems:
    let err = fetchAttempts(repo, r)
    if err.len > 0:
      r.attemptsObserved = false
      r.gapReason = err
      result.add "run " & r.runId & ": " & err
    else:
      r.attemptsObserved = true

proc fetchBaselineDurations(repo: string, window: int, until = ""):
    tuple[durations: seq[RunDuration], complete: bool,
          err: string] {.axiomEffect: IoEffect.} =
  ## Live reference set: the newest `window` completed admission-gate
  ## merge_group runs created at or before `until` (empty = no pin), GitHub
  ## order. Canonical per run = job span of the latest attempt; legacy =
  ## run_started_at -> updated_at. The pin makes a recorded snapshot
  ## reproducible as the live queue advances.
  var runs: seq[ObservedRun]
  var page = 1
  while runs.len < window and page <= MaxRunPages:
    let path = "repos/" & repo & "/actions/runs?event=merge_group" &
               "&status=completed&per_page=100&page=" & $page
    let res = ghApiGet(path)
    if not res.ok:
      return (@[], false, res.err)
    let parsed = safeParseJson(res.body)
    if parsed.err.len > 0:
      return (@[], false, "run list is not JSON: " & parsed.err)
    let raw = jsonArr(parsed.node, "workflow_runs")
    if raw == nil:
      return (@[], false, "run list lacks workflow_runs")
    for item in raw.items:
      if runs.len >= window:
        break
      let r = runFromJson(item)
      if not isAdmissionRun(r):
        continue
      if until.len > 0:
        let (created, okCreated) = parseIsoUtc(r.createdAt)
        let (cutoff, okCutoff) = parseIsoUtc(until)
        if not okCreated or not okCutoff:
          return (@[], false, "baseline-until pin is unparsable or run lacks created_at")
        if created > cutoff:
          continue
      runs.add r
    if raw.len < 100:
      break
    inc page
  if runs.len < window:
    return (@[], false, "observed only " & $runs.len & " completed " &
            "admission-gate merge_group runs; window is " & $window)
  var unobserved: seq[string]
  for r in runs:
    var a = ObservedAttempt(
      runId: r.runId,
      attemptNumber: (if r.runAttempt > 0: r.runAttempt else: 1),
      status: r.status,
      conclusion: r.conclusion,
      runStartedAt: r.startedAt,
      updatedAt: r.updatedAt)
    discard fetchAttemptJobs(repo, a, true)
    let canonical = jobSpanSeconds(a.jobs)
    var d = RunDuration(runId: r.runId,
                        seconds: canonical.seconds,
                        observed: canonical.observed,
                        gapReason: canonical.reason)
    let (s, okStart) = parseIsoUtc(r.startedAt)
    let (u, okUpdated) = parseIsoUtc(r.updatedAt)
    if okStart and okUpdated and u >= s:
      d.legacySeconds = int(u - s)
      d.legacyObserved = true
    if not d.observed:
      unobserved.add r.runId & ": " & d.gapReason
    result.durations.add d
  result.complete = unobserved.len == 0
  if not result.complete:
    result.err = "canonical wall unobservable for " & $unobserved.len &
                 " run(s): " & unobserved.join("; ")

proc fetchBoundary(repo, boundary: string):
    tuple[ok: bool, date: string, err: string] {.axiomEffect: IoEffect.} =
  let res = ghApiGet("repos/" & repo & "/commits/" & boundary)
  if not res.ok:
    return (false, "", res.err)
  let parsed = safeParseJson(res.body)
  if parsed.err.len > 0:
    return (false, "", "boundary commit is not JSON: " & parsed.err)
  let sha = jsonStr(parsed.node, "sha")
  if sha != boundary:
    return (false, "", "boundary commit resolved to a different sha: " & sha)
  var date = ""
  let commit = parsed.node{"commit"}
  if commit != nil and commit.kind == JObject:
    let committer = commit{"committer"}
    if committer != nil and committer.kind == JObject:
      date = jsonStr(committer, "date")
  if date.len < 10:
    return (false, "", "boundary commit has no committer date")
  (true, date[0 ..< 10], "")

proc fetchAncestry(repo, boundary, baseSha: string):
    tuple[ok: bool, postBoundary: bool, err: string] {.axiomEffect: IoEffect.} =
  if not isHex40(baseSha):
    return (false, false, "base_sha is missing or not 40-hex: '" & baseSha & "'")
  let res = ghApiGet("repos/" & repo & "/compare/" & boundary & "..." & baseSha)
  if not res.ok:
    return (false, false, res.err)
  let parsed = safeParseJson(res.body)
  if parsed.err.len > 0:
    return (false, false, "compare is not JSON: " & parsed.err)
  let status = jsonStr(parsed.node, "status")
  case status
  of "ahead", "identical": (true, true, "")
  of "behind", "diverged": (true, false, "")
  else: (false, false, "compare returned unknown status: '" & status & "'")

proc applyBoundary(entries: var seq[ObservedEntry], repo, boundary: string):
    seq[string] {.axiomEffect: IoEffect.} =
  var cache: seq[tuple[base: string, ok: bool, post: bool, err: string]]
  for e in entries.mitems:
    if e.baseSha.len == 0:
      e.ancestryObserved = false
      e.postBoundary = false
      e.boundaryGap = "base_sha unobservable for " & e.headSha
      result.add e.boundaryGap
      continue
    var cached = false
    for c in cache:
      if c.base == e.baseSha:
        e.ancestryObserved = c.ok
        e.postBoundary = c.post
        if not c.ok:
          e.boundaryGap = c.err
          result.add c.err
        cached = true
        break
    if cached:
      continue
    let anc = fetchAncestry(repo, boundary, e.baseSha)
    cache.add((e.baseSha, anc.ok, anc.postBoundary, anc.err))
    e.ancestryObserved = anc.ok
    e.postBoundary = anc.postBoundary
    if not anc.ok:
      e.boundaryGap = anc.err
      result.add anc.err

proc fetchCheckRunsForEntries(entries: var seq[ObservedEntry], repo: string):
    seq[string] {.axiomEffect: IoEffect.} =
  ## Every measured entry needs an `admission-check` check-run from the required
  ## verifier App (5795152). Absence or a same-name check from another App is
  ## recorded here and classified as authority_substitution (or a gap when the
  ## check-run list itself is unobservable).
  for e in entries.mitems:
    if not (e.postBoundary or not e.ancestryObserved):
      continue
    e.admissionAppIds = @[]
    e.admissionAppHasRequired = false
    e.admissionAppHasSuccess = false
    e.authorityObserved = false
    if not isHex40(e.headSha):
      e.authorityGap = "head_sha is not 40-hex: '" & e.headSha & "'"
      result.add e.authorityGap
      continue
    var
      ids: seq[int]
      present = false
      success = false
      page = 1
      err = ""
      done = false
    while page <= MaxCheckRunPages:
      let res = ghApiGet("repos/" & repo & "/commits/" & e.headSha &
                         "/check-runs?per_page=100&page=" & $page)
      if not res.ok:
        err = res.err
        break
      let parsed = safeParseJson(res.body)
      if parsed.err.len > 0:
        err = "check-run list is not JSON: " & parsed.err
        break
      let raw = jsonArr(parsed.node, "check_runs")
      if raw == nil:
        err = "check-run list lacks check_runs"
        break
      let summary = admissionCheckSummary(raw)
      for id in summary.appIds:
        if id notin ids:
          ids.add id
      present = present or summary.requiredPresent
      success = success or summary.requiredSuccess
      if raw.len < 100:
        done = true
        break
      inc page
    if done:
      e.authorityObserved = true
      e.admissionAppIds = ids
      e.admissionAppHasRequired = present
      e.admissionAppHasSuccess = success
    else:
      if err.len == 0:
        err = "check-run list truncated at " & $MaxCheckRunPages & " pages"
      e.authorityGap = "admission-check check-runs unobservable for " &
                       e.headSha & ": " & err
      result.add e.authorityGap

proc markReplacementContext(entries: var seq[ObservedEntry]) {.raises: [].} =
  ## cancelled_superseded requires a same-PR, same-base entry with a later
  ## terminal run_started_at. Missing PR/base identity leaves the context
  ## unobservable (unclassified + gap), never guessed.
  for i in 0 ..< entries.len:
    if not entries[i].postBoundary:
      continue
    var hasCancelled = false
    for a in entries[i].attempts:
      if a.conclusion == "cancelled":
        hasCancelled = true
        break
    if not hasCancelled:
      continue
    if entries[i].prNumber <= 0 or entries[i].baseSha.len == 0:
      entries[i].replacementObserved = false
      continue
    entries[i].replacementObserved = true
    let startI = entrySortKey(entries[i]).start
    for j in 0 ..< entries.len:
      if i == j or not entries[j].postBoundary:
        continue
      if entries[j].prNumber != entries[i].prNumber or
          entries[j].baseSha != entries[i].baseSha or
          entries[j].headSha == entries[i].headSha:
        continue
      if entrySortKey(entries[j]).start > startI:
        entries[i].replacementExists = true
        break

proc fetchEvidenceForEntries(entries: var seq[ObservedEntry], repo: string):
    seq[string] {.axiomEffect: IoEffect.} =
  ## Evidence for failed attempts; jobs for the terminal attempt (canonical
  ## wall) and for every failed attempt whose verdict reasonCode is NO_CERT or
  ## SUBJECT_MISMATCH (the certificate rule needs that attempt's mint jobs).
  for e in entries.mitems:
    if not e.postBoundary:
      continue
    let terminalIdx = terminalAttemptIndex(e)
    for i in 0 ..< e.attempts.len:
      let isTerminal = i == terminalIdx
      if isTerminal:
        discard fetchAttemptJobs(repo, e.attempts[i], true)
      var needsCertJobs = false
      if not isTerminal:
        if e.attempts[i].conclusion in ["success", "cancelled"] or
            e.attempts[i].attemptListGap:
          continue
        discard fetchAttemptEvidence(repo, e.attempts[i])
        if not e.attempts[i].evidenceFetched and
            e.attempts[i].evidenceError.len > 0:
          result.add "run " & e.attempts[i].runId & "/attempt " &
                     $e.attempts[i].attemptNumber & ": " &
                     e.attempts[i].evidenceError
        needsCertJobs =
          certificateRefusalCode(attemptText(e.attempts[i])).len > 0
      else:
        if e.attempts[i].conclusion notin ["success", "cancelled"]:
          discard fetchAttemptEvidence(repo, e.attempts[i])
          if not e.attempts[i].evidenceFetched and
              e.attempts[i].evidenceError.len > 0:
            result.add "run " & e.attempts[i].runId & "/attempt " &
                       $e.attempts[i].attemptNumber & ": " &
                       e.attempts[i].evidenceError
          # The terminal attempt already has `filter=latest` jobs, which is
          # exactly the same attempt; no second fetch is needed.
      if needsCertJobs:
        discard fetchAttemptJobs(repo, e.attempts[i], false)
    if e.attempts.len == 0:
      result.add "entry " & e.headSha & " has no observed attempts"

# ═══════════════════════════════════════════════════════════════════════════
# §10. I/O — report writing and CLI
# ═══════════════════════════════════════════════════════════════════════════

proc writeReportFiles(outDir: string, report: AcceptanceReport):
    tuple[jsonPath, mdPath: string] {.axiomEffect: IoEffect.} =
  try:
    createDir(outDir)
  except CatchableError as e:
    die("cannot create output directory " & outDir & ": " & e.msg)
  result.jsonPath = outDir / "ci_acceptance_report.json"
  result.mdPath = outDir / "ci_acceptance_report.md"
  try:
    writeFile(result.jsonPath, reportJson(report).pretty() & "\n")
    writeFile(result.mdPath, renderMarkdown(report))
  except CatchableError as e:
    die("cannot write report under " & outDir & ": " & e.msg)

proc writeGapReport(outDir, repo, boundary, reason: string):
    tuple[jsonPath, mdPath: string] {.axiomEffect: IoEffect.} =
  ## Exit-2 paths that still have a report to write (§8: the report is still
  ## written so the gap is visible).
  let report = buildReport(@[], repo, boundary, isoNow(), DefaultWindow)
  var gapped = report
  gapped.acceptance.gaps = @[reason]
  gapped.acceptance.observationComplete = false
  gapped.acceptance.accepted = false
  result = writeReportFiles(outDir, gapped)

proc writeBaselineFiles(outDir: string, durations: seq[RunDuration],
                        mode = "recompute-baseline"):
    tuple[jsonPath, mdPath: string] {.axiomEffect: IoEffect.} =
  try:
    createDir(outDir)
  except CatchableError as e:
    die("cannot create output directory " & outDir & ": " & e.msg)
  let node = baselineJson(durations, mode)
  result.jsonPath = outDir / "ci_acceptance_baseline.json"
  result.mdPath = outDir / "ci_acceptance_baseline.md"
  var md = "# CI Acceptance v2 — baseline (" & node{"mode"}.getStr & ")\n\n"
  md.add "- canonical n=" & $node{"n"}.getInt & ", excluded=" &
         $node{"excluded"}.getInt & "\n"
  md.add "- canonical p50=" & node{"p50_display"}.getStr & "s, mean=" &
         formatOneDecimal(node{"mean_seconds"}.getFloat) & "s, min=" &
         $node{"min_seconds"}.getInt & "s, max=" &
         $node{"max_seconds"}.getInt & "s\n"
  md.add "- legacy n=" & $node{"legacy_n"}.getInt & ", p50=" &
         formatOneDecimal(node{"legacy_p50_seconds"}.getFloat) & "s, mean=" &
         formatOneDecimal(node{"legacy_mean_seconds"}.getFloat) & "s\n"
  md.add "- formula: " & node{"formula"}.getStr & "\n"
  md.add "- legacy formula: " & node{"legacy_formula"}.getStr & "\n\n"
  md.add "| run_id | seconds | observed | legacy_s | gap |\n|---|---:|---|---:|---|\n"
  for r in node{"runs"}.items:
    md.add "| " & r{"run_id"}.getStr & " | " &
           (if r{"seconds"}.kind == JNull: "—" else: $r{"seconds"}.getInt) &
           " | " & $r{"observed"}.getBool & " | " &
           (if r{"legacy_seconds"}.kind == JNull: "—"
            else: $r{"legacy_seconds"}.getInt) &
           " | " & r{"gap_reason"}.getStr & " |\n"
  try:
    writeFile(result.jsonPath, node.pretty() & "\n")
    writeFile(result.mdPath, md)
  except CatchableError as e:
    die("cannot write baseline under " & outDir & ": " & e.msg)

proc usage(): string {.raises: [].} =
  "usage:\n" &
  "  " & ToolName & " --boundary <sha> [--repo owner/name] [--window N]\n" &
  "      [--mode initial|rolling] [--out DIR]\n" &
  "  " & ToolName & " --baseline-live [--repo owner/name] [--window N]\n" &
  "      [--baseline-until ISO8601] [--out DIR]\n" &
  "  " & ToolName & " --recompute-baseline <run-list.json> [--out DIR]\n" &
  "  " & ToolName & " --help\n\n" &
  "--boundary is REQUIRED for acceptance: the canonical main merge commit after\n" &
  "#145, #186, and docs/spec/ci_acceptance_contract.md have all landed. There is\n" &
  "no default. --mode initial = the FIRST N post-boundary entries by terminal\n" &
  "run_started_at (default); --mode rolling = the LAST N.\n" &
  "--baseline-live recomputes the reference latency over the newest N completed\n" &
  "admission-gate merge_group runs (default N=" & $BaselineWindow & ").\n" &
  "Exit: 0 ACCEPTED; 1 FAILED; 2 INCOMPLETE / observation incomplete /\n" &
  "input invalid.\n"

when isMainModule:
  var
    repo = getEnv("GITHUB_REPOSITORY").strip()
    boundary = ""
    window = DefaultWindow
    windowSet = false
    outDir = DefaultOutDir
    recomputePath = ""
    baselineLive = false
    baselineUntil = ""
    mode = wmInitial
  let cliArgs = commandLineParams()
  var i = 0
  proc needValue(flag: string): string =
    if i >= cliArgs.len - 1:
      die("missing value for " & flag)
    inc i
    cliArgs[i]
  while i < cliArgs.len:
    let a = cliArgs[i]
    case a
    of "--repo": repo = needValue(a)
    of "--boundary": boundary = needValue(a)
    of "--window":
      let v = needValue(a)
      let parsed = parseDecimal(v)
      if not parsed.ok or parsed.value <= 0 or parsed.value > 10_000:
        die("--window must be a positive integer (got '" & v & "')")
      window = int(parsed.value)
      windowSet = true
    of "--mode":
      let v = needValue(a)
      case v
      of "initial": mode = wmInitial
      of "rolling": mode = wmRolling
      else: die("--mode must be initial or rolling (got '" & v & "')")
    of "--out": outDir = needValue(a)
    of "--recompute-baseline": recomputePath = needValue(a)
    of "--baseline-live": baselineLive = true
    of "--baseline-until": baselineUntil = needValue(a)
    of "--help", "-h":
      echo usage()
      quit(0)
    else:
      die("unknown option: " & a)
    inc i

  if repo.len == 0:
    repo = DefaultRepo

  if baselineUntil.len > 0 and not baselineLive:
    die("--baseline-until is only valid with --baseline-live")

  if baselineLive:
    if boundary.len > 0:
      die("--baseline-live and --boundary are mutually exclusive")
    if recomputePath.len > 0:
      die("--baseline-live and --recompute-baseline are mutually exclusive")
    let bWindow = (if windowSet: window else: BaselineWindow)
    let live = fetchBaselineDurations(repo, bWindow, baselineUntil)
    if live.durations.len == 0:
      die("baseline-live observation incomplete: " & live.err)
    let paths = writeBaselineFiles(outDir, live.durations, "baseline-live")
    var values, legacyValues: seq[int]
    for d in live.durations:
      if d.observed:
        values.add d.seconds
      if d.legacyObserved:
        legacyValues.add d.legacySeconds
    let canonical = latencyStats(values)
    let legacy = latencyStats(legacyValues)
    echo "[" & ToolName & "] baseline-live canonical: n=" & $canonical.n &
         " p50=" & formatOneDecimal(canonical.p50) & "s mean=" &
         formatOneDecimal(canonical.mean) & "s min=" & $canonical.minSeconds &
         "s max=" & $canonical.maxSeconds & "s"
    echo "[" & ToolName & "] baseline-live legacy: n=" & $legacy.n &
         " p50=" & formatOneDecimal(legacy.p50) & "s mean=" &
         formatOneDecimal(legacy.mean) & "s"
    echo "[" & ToolName & "] wrote " & paths.jsonPath & " and " & paths.mdPath
    if live.complete:
      quit(0)
    else:
      stderr.writeLine("[" & ToolName & "] observation incomplete: " & live.err)
      quit(2)

  if recomputePath.len > 0:
    if boundary.len > 0:
      die("--recompute-baseline and --boundary are mutually exclusive")
    var content = ""
    try:
      content = readFile(recomputePath)
    except CatchableError as e:
      die("cannot read run list " & recomputePath & ": " & e.msg)
    let parsed = safeParseJson(content)
    if parsed.err.len > 0:
      die("run list is not JSON: " & parsed.err)
    let durations = durationsFromRunList(parsed.node)
    if durations.len == 0:
      die("run list carries no rows (expected an array or {runs: [...]})")
    let paths = writeBaselineFiles(outDir, durations)
    var values, legacyValues: seq[int]
    for d in durations:
      if d.observed:
        values.add d.seconds
      if d.legacyObserved:
        legacyValues.add d.legacySeconds
    let canonical = latencyStats(values)
    let legacy = latencyStats(legacyValues)
    echo "[" & ToolName & "] baseline canonical: n=" & $canonical.n &
         " p50=" & formatOneDecimal(canonical.p50) & "s mean=" &
         formatOneDecimal(canonical.mean) & "s min=" & $canonical.minSeconds &
         "s max=" & $canonical.maxSeconds & "s"
    echo "[" & ToolName & "] baseline legacy: n=" & $legacy.n &
         " p50=" & formatOneDecimal(legacy.p50) & "s mean=" &
         formatOneDecimal(legacy.mean) & "s"
    echo "[" & ToolName & "] wrote " & paths.jsonPath & " and " & paths.mdPath
    if baselineComplete(durations):
      quit(0)
    else:
      stderr.writeLine("[" & ToolName & "] observation incomplete: run list " &
                       "contains runs without an observed canonical job span")
      quit(2)

  if boundary.len == 0:
    die("missing required --boundary <sha>: the boundary is the canonical " &
        "main merge commit after #145, #186, and " & ContractPath &
        " have landed; there is no default")
  if not isHex40(boundary):
    die("--boundary must be a 40-hex commit sha (got '" & boundary & "')")

  let boundaryInfo = fetchBoundary(repo, boundary)
  if not boundaryInfo.ok:
    let reason = "boundary is not observable: " & boundaryInfo.err
    discard writeGapReport(outDir, repo, boundary, reason)
    die(reason)

  let runsRes = fetchAdmissionRuns(repo, boundaryInfo.date)
  if not runsRes.complete:
    let reason = "observation incomplete: " & runsRes.err
    discard writeGapReport(outDir, repo, boundary, reason)
    die(reason)

  var runs = runsRes.runs
  let attemptGaps = attachAttempts(runs, repo)
  var entries = buildEntries(runs)
  let boundaryGaps = applyBoundary(entries, repo, boundary)
  let authorityGaps = fetchCheckRunsForEntries(entries, repo)
  markReplacementContext(entries)
  let evidenceGaps = fetchEvidenceForEntries(entries, repo)

  let report = buildReport(entries, repo, boundary, isoNow(), window, mode)
  var allGaps = report.acceptance.gaps
  for g in attemptGaps & boundaryGaps & authorityGaps & evidenceGaps:
    if g.len > 0 and g notin allGaps:
      allGaps.add g
  var finalReport = report
  finalReport.acceptance.gaps = allGaps
  finalReport.acceptance.observationComplete =
    allGaps.len == 0 and report.acceptance.observedEntries > 0
  finalReport.acceptance.accepted =
    finalReport.acceptance.predicateHolds and
    finalReport.acceptance.observationComplete
  if finalReport.acceptance.accepted:
    finalReport.acceptance.status = asAccepted
  elif finalReport.acceptance.shortfall > 0 or
      not finalReport.acceptance.observationComplete:
    finalReport.acceptance.status = asIncomplete
  else:
    finalReport.acceptance.status = asFailed

  let paths = writeReportFiles(outDir, finalReport)
  echo "[" & ToolName & "] boundary=" & boundary
  echo "[" & ToolName & "] mode=" & $finalReport.acceptance.mode &
       " status=" & $finalReport.acceptance.status &
       " window=" & $finalReport.acceptance.observedEntries & "/" &
       $finalReport.acceptance.requestedWindow &
       " shortfall=" & $finalReport.acceptance.shortfall &
       " excluded_before_boundary=" & $finalReport.excludedBeforeBoundary
  echo "[" & ToolName & "] counts: success=" & $finalReport.acceptance.success &
       " legitimate_policy=" & $finalReport.acceptance.legitimatePolicy &
       " internal_defect=" & $finalReport.acceptance.internalDefect &
       " (identity=" & $finalReport.acceptance.identityDivergence &
       " soundness=" & $finalReport.acceptance.soundnessFailure &
       " projection=" & $finalReport.acceptance.failureProjection &
       " authority=" & $finalReport.acceptance.authoritySubstitution & ")" &
       " unclassified=" & $finalReport.acceptance.unclassified &
       " cancelled_superseded=" & $finalReport.acceptance.cancelledSuperseded
  echo "[" & ToolName & "] latency canonical n=" &
       $finalReport.acceptance.latencyN & " p50=" &
       formatOneDecimal(finalReport.acceptance.latencyP50) & "s mean=" &
       formatOneDecimal(finalReport.acceptance.latencyMean) & "s min=" &
       $finalReport.acceptance.latencyMin & "s max=" &
       $finalReport.acceptance.latencyMax & "s"
  echo "[" & ToolName & "] latency legacy n=" &
       $finalReport.acceptance.legacyLatencyN & " p50=" &
       formatOneDecimal(finalReport.acceptance.legacyLatencyP50) & "s mean=" &
       formatOneDecimal(finalReport.acceptance.legacyLatencyMean) & "s"
  echo "[" & ToolName & "] accepted=" & $finalReport.acceptance.accepted &
       " predicate_holds=" & $finalReport.acceptance.predicateHolds &
       " observation_complete=" & $finalReport.acceptance.observationComplete
  echo "[" & ToolName & "] wrote " & paths.jsonPath & " and " & paths.mdPath

  case finalReport.acceptance.status
  of asAccepted: quit(0)
  of asFailed: quit(1)
  of asIncomplete: quit(2)