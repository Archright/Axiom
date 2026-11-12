## Unit tests for src/cli/upstream_report_cli.nim — `ax report --upstream`
## (docs/spec/upstream_reporting_contract.md). PURE parts + the pipeline
## orchestrator over a scripted mock gh adapter. NO NETWORK: the gh boundary
## is the injected GhAdapter seam; ledger/overlay live in a temp fixture dir.
##
## Covered: owner/repo extraction from the descriptive overlay repository
## string, findingEvidence counterexample normalization (key-sorted
## `input.<k>=<v>` bindings from the state document's canonical evidence
## block), the v2 identity model (§4: findingKey stable across evidence
## reinforcement, evidenceDigest moving with every evidence member,
## legacyFingerprints provenance of the v1 reportFingerprint expression),
## the gh outcome classification table (403/404/410/429/401/4xx/5xx/timeout/
## 127 — 429 its own rate-limit family, never rejected), clause algebra (law
## content stays overlay DATA), receipt v2 JSON schema round-trip + v1
## migration-source acceptance + atomic write/reload, fail-closed state/
## display/findingEvidence parsing, issue-body contract (findingKey +
## evidenceDigest + legacyFingerprints identity lines, BUG_SUSPECTED INFERRED
## disclaimer, repro quartet, NO Axiom internals), flag parsing, exit codes,
## and the pipeline status machine: dry-run READY (nothing persisted, no
## create), SUBMITTED (create -> verify -> persist immediately, dup-check
## BEFORE create), ledger-SUBMITTED -> DUPLICATE without any gh write,
## RECONCILIATION_REQUIRED -> direct candidate recovery BEFORE search/create
## (never blind-retry), RECONCILIATION_REQUIRED persistence across
## failed/empty re-queries (no regeneration, no BLOCKED demotion — the
## candidateUrl recovery input survives until a SUBMITTED|DUPLICATE
## observation resolves it), READY-intent persistence failure -> the external
## create is forbidden (fail-closed), BLOCKED paths (404 resolve, 410
## has_issues/create, 429 rate limit, gh-auth preflight,
## duplicate-check-unavailable), receipt evidence preservation across re-runs
## (prior submittedAt, structured issue identity and the attempt history
## carry forward into every replacement receipt — never destroyed), the
## structured identity being re-queried DIRECTLY on every later run (search
## indexes never trusted for dedup; DUPLICATE/BLOCKED/RR priors included;
## unverifiable -> RECONCILIATION_REQUIRED, never a re-create), FAILED(remote-
## unverifiable) candidate recovery, dry-run never persisting any state
## transition, a READY ledger receipt (which can only be the pre-create
## intent left by a crashed run) being treated as an unresolved creation,
## an SSOT receipt persistence failure being a hard error that carries the
## receipt identity (never terminal success; dry-run's no-write is not a
## failure), the §6 legacy v1 receipt migration (identity-triple match ->
## evidence succession + legacyFingerprints record + v2 rewrite at
## <findingKey>.json with the v1 original immutable; multi-match -> fail-
## closed BLOCKED; submittedAt backfilled from the GitHub issue created_at;
## dry-run safe; unreadable legacy entries hard-error), and the §11
## findingEvidence gate (no evidence block / empty counterexample -> BLOCKED
## before any gh call, READY unreachable).
##
## Run from repo root:
##   nim c -r --hints:off tests/unit/test_upstream_report_cli.nim

import std/[base64, json, options, os, sequtils, strutils, unittest]
import ../../src/cli/upstream_report_cli
import ../../src/core/crypto/hash_kernel
import ../../src/core/results

# ---------------------------------------------------------------------------
# Fixtures (the committed bytesview overlay family, trimmed to its DATA)
# ---------------------------------------------------------------------------

const CLAUSES* = @[
  "1 <= e", "e <= 5",
  "bvSliceLenLaw1(e) == e",
  "bvSliceLenActual(e) == (e - 1)",
  "bvSliceLenLaw0(e) == (e + 1)",
  "bvSliceLenControl(e) == (e + 1)"]

const TARGET_SYMBOL* = "libp2p/utils/bytesview.nim::toOpenArray"
const SUBJECT_COMMIT* = "a130a7f32219909bdcda14b7f1e64d0804fc832c"
const SUBJECT_BLOB* = "b205c969ba04f4199d8fd4a121d4b6fccdc82c426e336add0e1e9fd0e961e5ee"
const LEGACY_FP* = "38647549ce6cced6c8f0ee8a0c83163e34d4cf7da006a45e4b7295af578914b4"

proc overlayJson(): JsonNode =
  %*{
    "specId": "SPEC-LIBP2P-BV-SLICE",
    "ruleId": "external:libp2p/bytesview/slice-length-law",
    "ruleVersion": "1.0.0",
    "subject": {
      "repository": "status-im/nim-libp2p (local READ-ONLY clone /home/x/nim-libp2p; origin iftech/nim-libp2p fork of status-im/nim-libp2p)",
      "commit": "a130a7f32219909bdcda14b7f1e64d0804fc832c",
      "module": "libp2p/utils/bytesview.nim",
      "symbols": ["toOpenArray"],
      "blobSha256": "b205c969ba04f4199d8fd4a121d4b6fccdc82c426e336add0e1e9fd0e961e5ee"},
    "canonicalSpecIR": CLAUSES,
    "carriers": [
      {"name": "bvSliceLenActual", "kind": "defect", "groundingSymbol": "toOpenArray",
       "grounding": "bytesview.nim:18-19 — the template's actual index arithmetic with b pinned at 1"},
      {"name": "bvSliceLenControl", "kind": "control", "groundingSymbol": "toOpenArray",
       "grounding": "at b=0 the actual length is e+1 — b pinned at 0 — injection guard only"}]}

proc makeState*(attribution: string; verdict: string): JsonNode =
  ## The canonical producer shape: the display unit carries the attribution
  ## (its quartet line deliberately DISAGREES with the evidence — the
  ## reporter must consume ONLY the findingEvidence block), and the state
  ## root's findingEvidence supplies the counterexample + subject pin.
  %*{
    "schemaVersion": "axiom.report.v1",
    "findingEvidence": {
      "libp2p/utils/bytesview.nim::toOpenArray": {
        "claimOutcome": "DISPROVED",
        "rowStatus": "BUG_SUSPECTED",
        "machineVerdict": "DISPROVED",
        "machineEstablished": true,
        "counterExample": ["exact input: input.e=4"],
        "quartetPayloadDigest": "cafebabe",
        "subjectCommit": "a130a7f32219909bdcda14b7f1e64d0804fc832c",
        "subjectBlob": "b205c969ba04f4199d8fd4a121d4b6fccdc82c426e336add0e1e9fd0e961e5ee"}},
    "reportJson": {"display": {
      "schemaVersion": "bug-verdict-display-v3",
      "units": [{
        "targetSymbol": "libp2p/utils/bytesview.nim::toOpenArray",
        "adoptedSpecRef": {"specId": "SPEC-LIBP2P-BV-SLICE",
          "specRelPath": "nim_libp2p_bytesview_slice.json"},
        "ruleJudgment": "rule linked to software requirement (external:libp2p/bytesview/slice-length-law)",
        "bugAttribution": attribution,
        "propositionVerdict": verdict,
        "requirementSourceStatus": "recordedBinding",
        "uncertaintyKinds": ["upstream-spec"],
        "machineStates": [],
        "groundsRefs": ["r#abc"],
        "groundsValidation": "",
        "displayInputDigest": "deadbeef",
        "quartetPayloadDigest": "stale-display-digest",
        "quartet": ["exact input: input.e=999"]}]}}}

proc makeStateWithoutEvidence*(attribution: string; verdict: string): JsonNode =
  ## No findingEvidence block at all — the §11 gate must block READY.
  result = makeState(attribution, verdict)
  result.delete("findingEvidence")

proc makeStateEvidence*(attribution: string; verdict: string;
    counterExample: JsonNode; machineEstablished: JsonNode): JsonNode =
  ## makeState with a replaced findingEvidence entry (malformed/empty variants).
  result = makeState(attribution, verdict)
  let ev = result{"findingEvidence"}{TARGET_SYMBOL}
  ev["counterExample"] = counterExample
  ev["machineEstablished"] = machineEstablished

proc makeStateEmptyCounterexample*(attribution: string; verdict: string): JsonNode =
  makeStateEvidence(attribution, verdict, newJArray(), newJBool(true))

proc makeStateMalformedCounterexample*(attribution: string; verdict: string): JsonNode =
  makeStateEvidence(attribution, verdict, %"not-an-array", newJBool(true))

proc makeStateMalformedMachineFlag*(attribution: string; verdict: string): JsonNode =
  makeStateEvidence(attribution, verdict, newJArray(), %"yes")

proc unitOf(state: JsonNode): JsonNode =
  state{"reportJson"}{"display"}{"units"}[0]

proc expectedFindingKey*(): string =
  composeFindingKey("iftech/nim-libp2p",
    "libp2p/utils/bytesview.nim::toOpenArray", "SPEC-LIBP2P-BV-SLICE",
    "external:libp2p/bytesview/slice-length-law", "1.0.0",
    canonicalSpecIrDigest(CLAUSES))

proc expectedEvidenceDigest*(): string =
  composeEvidenceDigest("DISPROVED", "DISPROVED", "BUG_SUSPECTED", "cafebabe",
    true, @["e=4"], SUBJECT_COMMIT, SUBJECT_BLOB)

proc expectedIdentity*(): FindingIdentity =
  FindingIdentity(findingKey: expectedFindingKey(),
    evidenceDigest: expectedEvidenceDigest())

proc legacyV1ReceiptJson*(reportFingerprint: string; status = "SUBMITTED";
    issueNumber = 3364; submittedAt: JsonNode = newJNull();
    specId = "SPEC-LIBP2P-BV-SLICE";
    schemaVersion = "upstream-report-receipt-v1"): JsonNode =
  ## A v1-schema receipt as the old code wrote it (file name = the v1
  ## fingerprint). submittedAt defaults to null — the §6 backfill case.
  %*{
    "schemaVersion": schemaVersion,
    "reportFingerprint": reportFingerprint,
    "status": status,
    "verdict": {
      "propositionVerdict": "DISPROVED",
      "requirementSourceStatus": "unrecorded",
      "bugAttribution": "BUG_SUSPECTED"},
    "subject": {
      "requestedRepository": "status-im/nim-libp2p",
      "resolvedRepository": "iftech/nim-libp2p",
      "commit": "a130a7f32219909bdcda14b7f1e64d0804fc832c",
      "module": "libp2p/utils/bytesview.nim",
      "symbol": "toOpenArray",
      "blobSha256": "b205c969ba04f4199d8fd4a121d4b6fccdc82c426e336add0e1e9fd0e961e5ee"},
    "proposition": {
      "specId": specId,
      "ruleId": "external:libp2p/bytesview/slice-length-law",
      "ruleVersion": "1.0.0",
      "specRelPath": "nim_libp2p_bytesview_slice.json",
      "canonicalSpecIRDigest": canonicalSpecIrDigest(CLAUSES)},
    "counterexample": {"normalized": [], "rawQuartet": []},
    "issue": {"number": issueNumber,
      "url": "https://github.com/iftech/nim-libp2p/issues/" & $issueNumber},
    "blockedReason": newJNull(),
    "attempts": [],
    "submittedAt": submittedAt}

# ---------------------------------------------------------------------------
# Mock gh adapter (the seam) + fixture workspace
# ---------------------------------------------------------------------------

type
  MockGh* = ref object
    rules: seq[tuple[match: string; code: int; output: string]]
    calls*: seq[string]

proc on*(m: MockGh; match: string; code: int; output: string) =
  m.rules.add((match, code, output))

proc ghAdapter*(m: MockGh): GhAdapter =
  result = proc (command: string): GhResult =
    m.calls.add(command)
    for rule in m.rules:
      if command.contains(rule.match):
        return GhResult(exitCode: rule.code, output: rule.output)
    GhResult(exitCode: 1, output: "MOCK: no scripted response for: " & command)

proc testClock*(): string =
  "2026-10-31T12:00:00Z"

const REPO_API_OK* = """{"full_name": "iftech/nim-libp2p", "has_issues": true}"""
const CREATE_URL_OUTPUT* = "\n\nCreating issue...\n\nhttps://github.com/iftech/nim-libp2p/issues/12\n"

proc newHappyMock*(createOutput: string = CREATE_URL_OUTPUT;
    createCode = 0): MockGh =
  result = MockGh()
  result.on("auth status", 0, "logged in")
  result.on("repos/'status-im/nim-libp2p'", 0, REPO_API_OK)
  result.on("issue view 12", 0,
    $(%*{"number": 12, "url": "https://github.com/iftech/nim-libp2p/issues/12",
         "state": "open"}))
  result.on("search issues", 0, "[]")
  result.on("issue list", 0, "[]")
  result.on("ISSUE_TEMPLATE", 1, "gh: Not Found (HTTP 404)")
  result.on("issue create", createCode, createOutput)

var fixtureCounter = 0

proc makeFixture*(state: JsonNode): tuple[dir: string; ledgerDir: string] =
  inc fixtureCounter
  let dir = joinPath(getTempDir(),
    "axiom-upstream-test-" & $getCurrentProcessId() & "-" & $fixtureCounter)
  let ledgerDir = joinPath(dir, "data", "upstream_reports")
  createDir(joinPath(dir, "config", "spec"))
  createDir(ledgerDir)
  writeFile(joinPath(dir, ".axiom_root"), "")
  writeFile(joinPath(dir, "config", "spec", "nim_libp2p_bytesview_slice.json"),
    $overlayJson())
  writeFile(joinPath(dir, "state.json"), $state)
  (dir, ledgerDir)

proc makeCfg*(dir: string; ledgerDir: string; dryRun: bool): UpstreamRunConfig =
  UpstreamRunConfig(
    stateFilePath: joinPath(dir, "state.json"),
    repoRoot: dir,
    ledgerDir: ledgerDir,
    dryRun: dryRun,
    emitJson: false)

proc runPipe*(state: JsonNode; dir: string; ledgerDir: string; dryRun: bool;
    m: MockGh): Result[seq[UpstreamUnitOutcome], string] =
  runUpstreamReport(state, makeCfg(dir, ledgerDir, dryRun), m.ghAdapter(), testClock)

proc fileCount*(dir: string): int =
  for kind, path in walkDir(dir):
    if kind == pcFile:
      inc result

# Module-level fixtures for the pure suites.
let MERGED* = selectReportableUnits(makeState("BUG_SUSPECTED", "DISPROVED"))
let UNIT* = MERGED.get()[0]
let FACTS* = extractOverlayFacts(overlayJson(), UNIT)

# ---------------------------------------------------------------------------
# Pure: descriptor extraction + quoting
# ---------------------------------------------------------------------------

suite "repository descriptor extraction":
  test "first owner/repo token of the descriptive string wins":
    check extractOwnerRepo("status-im/nim-libp2p (local READ-ONLY clone /home/x/nim-libp2p; origin iftech/nim-libp2p fork of status-im/nim-libp2p)") == "status-im/nim-libp2p"
  test "path fragments and repo-less strings never resolve":
    check extractOwnerRepo("no repository recorded") == ""
    check extractOwnerRepo("cloned at /home/x/dest dir") == ""
    check extractOwnerRepo("") == ""
  test "the extracted token is shell-safe by construction":
    let tok = extractOwnerRepo("a_b.c/d-e.f (desc)")
    check tok == "a_b.c/d-e.f"
    check allIn(tok, {'A'..'Z', 'a'..'z', '0'..'9', '_', '.', '-', '/'})

suite "spec overlay path guard":
  test "config/spec-relative paths only":
    check safeSpecRelPath("nim_libp2p_bytesview_slice.json")
    check safeSpecRelPath("sub/dir/spec.json")
    check not safeSpecRelPath("../etc/passwd")
    check not safeSpecRelPath("a/../../escape.json")
    check not safeSpecRelPath("/abs.json")
    check not safeSpecRelPath("back\\slash.json")
    check not safeSpecRelPath("")

suite "shell quoting":
  test "single quotes with embedded quote escaping":
    check shellQuote("plain") == "'plain'"
    check shellQuote("it's") == "'it'\\''s'"
    check shellQuote("/tmp/a b.md") == "'/tmp/a b.md'"

# ---------------------------------------------------------------------------
# Pure: counterexample normalization (findingEvidence consumption)
# ---------------------------------------------------------------------------

suite "findingEvidence counterexample normalization":
  test "counterExample lines normalize into key-sorted, deduped bindings":
    let (norm, raw) = normalizeEvidenceCounterexample(@[
      "exact input: input.e=4 and input.b=1",
      "replay: input.e=4"])
    check norm == @["b=1", "e=4"]
    check raw == @["exact input: input.e=4 and input.b=1", "replay: input.e=4"]
  test "lines without bindings never enter the normalized set":
    let (norm, raw) = normalizeEvidenceCounterexample(@[
      "clUnknown", "no bindings here"])
    check norm.len == 0
    check raw.len == 0
  test "binding accessors":
    check bindingKey("e=4") == "e"
    check bindingValue("e=4") == "4"

# ---------------------------------------------------------------------------
# Pure: clause algebra — the law content stays overlay DATA
# ---------------------------------------------------------------------------

suite "clause algebra":
  test "clause call-name / variable extraction":
    check clauseCallName("bvSliceLenActual(e) == (e - 1)") == "bvSliceLenActual"
    check clauseCallName("1 <= e") == ""
    check clauseVarName("bvSliceLenActual(e) == (e - 1)") == "e"
  test "single-variable linear forms evaluate; anything else is none":
    check evalLinearRhs("e", "e", 4) == some(4)
    check evalLinearRhs("e - 1", "e", 4) == some(3)
    check evalLinearRhs("(e - 1)", "e", 4) == some(3)
    check evalLinearRhs("e + 1", "e", 4) == some(5)
    check evalLinearRhs("f(e)", "e", 4) == none(int)
    check evalClauseValue("bvSliceLenActual(e) == (e - 1)", "e", 4) == some(3)
    check evalClauseValue("bvSliceLenLaw1(e) == e", "e", 4) == some(4)
    check evalClauseValue("1 <= e", "e", 4) == none(int)
  test "malformed RHS constants are rejected, never prefix-parsed":
    check evalLinearRhs("e - 1abc", "e", 4) == none(int)
    check evalLinearRhs("e + 1abc", "e", 4) == none(int)
    check evalLinearRhs("(e - 1x)", "e", 4) == none(int)
    check evalLinearRhs("e - ", "e", 4) == none(int)
    check evalClauseValue("bvSliceLenActual(e) == (e - 1abc)", "e", 4) == none(int)
  test "the pinned byte is read from the carrier grounding":
    check pinnedByte("arithmetic with b pinned at 1: range [rpos+1, rpos+e-1]") == "1"
    check pinnedByte("no pin recorded") == ""
  test "defect law selection via the overlay's Law<b> convention":
    check defectLawClause(CLAUSES,
      @["bvSliceLenActual", "bvSliceLenControl"], "1") == "bvSliceLenLaw1(e) == e"
    check defectLawClause(CLAUSES,
      @["bvSliceLenActual", "bvSliceLenControl"], "") == ""
  test "overlay facts: requested repo, defect carrier, law and actual clauses":
    check FACTS.requestedRepository == "status-im/nim-libp2p"
    check FACTS.symbol == "toOpenArray"
    check FACTS.moduleName == "libp2p/utils/bytesview.nim"
    check FACTS.defectCarrier == "bvSliceLenActual"
    check FACTS.actualClause == "bvSliceLenActual(e) == (e - 1)"
    check FACTS.lawClause == "bvSliceLenLaw1(e) == e"
    check FACTS.ruleId == "external:libp2p/bytesview/slice-length-law"

# ---------------------------------------------------------------------------
# Pure: the v2 identity — findingKey + evidenceDigest (+ v1 legacy expression)
# ---------------------------------------------------------------------------

suite "findingKey + evidenceDigest — v2 identity projection (§4)":
  test "same identity -> same findingKey (volatile fields have no input channel)":
    let fk1 = expectedFindingKey()
    let fk2 = composeFindingKey("iftech/nim-libp2p",
      "libp2p/utils/bytesview.nim::toOpenArray", "SPEC-LIBP2P-BV-SLICE",
      "external:libp2p/bytesview/slice-length-law", "1.0.0",
      canonicalSpecIrDigest(CLAUSES))
    check fk1 == fk2
    check fk1.len == 64
  test "every identity component moves the findingKey":
    let base = expectedFindingKey()
    let digest = canonicalSpecIrDigest(CLAUSES)
    check composeFindingKey("status-im/nim-libp2p",
      "libp2p/utils/bytesview.nim::toOpenArray", "SPEC-LIBP2P-BV-SLICE",
      "external:libp2p/bytesview/slice-length-law", "1.0.0", digest) != base
    check composeFindingKey("iftech/nim-libp2p", "other/mod.nim::sym",
      "SPEC-LIBP2P-BV-SLICE", "external:libp2p/bytesview/slice-length-law",
      "1.0.0", digest) != base
    check composeFindingKey("iftech/nim-libp2p",
      "libp2p/utils/bytesview.nim::toOpenArray", "SPEC-OTHER",
      "external:libp2p/bytesview/slice-length-law", "1.0.0", digest) != base
    check composeFindingKey("iftech/nim-libp2p",
      "libp2p/utils/bytesview.nim::toOpenArray", "SPEC-LIBP2P-BV-SLICE",
      "external:other-rule", "1.0.0", digest) != base
    check composeFindingKey("iftech/nim-libp2p",
      "libp2p/utils/bytesview.nim::toOpenArray", "SPEC-LIBP2P-BV-SLICE",
      "external:libp2p/bytesview/slice-length-law", "1.0.1", digest) != base
    check composeFindingKey("iftech/nim-libp2p",
      "libp2p/utils/bytesview.nim::toOpenArray", "SPEC-LIBP2P-BV-SLICE",
      "external:libp2p/bytesview/slice-length-law", "1.0.0",
      sha256Hex("other-clauses")) != base
  test "(a) same identity + different normalized counterexample -> SAME findingKey, DIFFERENT evidenceDigest":
    let fkA = composeFindingKey("iftech/nim-libp2p",
      "libp2p/utils/bytesview.nim::toOpenArray", "SPEC-LIBP2P-BV-SLICE",
      "external:libp2p/bytesview/slice-length-law", "1.0.0",
      canonicalSpecIrDigest(CLAUSES))
    let fkB = composeFindingKey("iftech/nim-libp2p",
      "libp2p/utils/bytesview.nim::toOpenArray", "SPEC-LIBP2P-BV-SLICE",
      "external:libp2p/bytesview/slice-length-law", "1.0.0",
      canonicalSpecIrDigest(CLAUSES))
    let edA = composeEvidenceDigest("DISPROVED", "DISPROVED", "BUG_SUSPECTED",
      "cafebabe", true, @["e=4"], SUBJECT_COMMIT, SUBJECT_BLOB)
    let edB = composeEvidenceDigest("DISPROVED", "DISPROVED", "BUG_SUSPECTED",
      "cafebabe", true, @["b=1", "e=4"], SUBJECT_COMMIT, SUBJECT_BLOB)
    check fkA == fkB
    check edA != edB
  test "(a) evidence reinforcement moves evidenceDigest only — findingKey is invariant":
    let fk = expectedFindingKey()
    let edA = expectedEvidenceDigest()
    let edB = composeEvidenceDigest("DISPROVED", "DISPROVED", "BUG_SUSPECTED",
      "cafebabe", true, @["b=1", "e=4"], SUBJECT_COMMIT, SUBJECT_BLOB)
    check edA != edB
    check composeFindingKey("iftech/nim-libp2p",
      "libp2p/utils/bytesview.nim::toOpenArray", "SPEC-LIBP2P-BV-SLICE",
      "external:libp2p/bytesview/slice-length-law", "1.0.0",
      canonicalSpecIrDigest(CLAUSES)) == fk
  test "every §4 evidence member moves the evidenceDigest":
    let base = expectedEvidenceDigest()
    let (norm, raw) = (@["e=4"], @["exact input: input.e=4"])
    check composeEvidenceDigest("DISPROVED_OTHER", "DISPROVED", "BUG_SUSPECTED",
      "cafebabe", true, norm, SUBJECT_COMMIT, SUBJECT_BLOB) != base
    check composeEvidenceDigest("DISPROVED", "DISPROVED_OTHER", "BUG_SUSPECTED",
      "cafebabe", true, norm, SUBJECT_COMMIT, SUBJECT_BLOB) != base
    check composeEvidenceDigest("DISPROVED", "DISPROVED", "BUG_SUSPECTED_OTHER",
      "cafebabe", true, norm, SUBJECT_COMMIT, SUBJECT_BLOB) != base
    check composeEvidenceDigest("DISPROVED", "DISPROVED", "BUG_SUSPECTED",
      "cafebabe_OTHER", true, norm, SUBJECT_COMMIT, SUBJECT_BLOB) != base
    check composeEvidenceDigest("DISPROVED", "DISPROVED", "BUG_SUSPECTED",
      "cafebabe", false, norm, SUBJECT_COMMIT, SUBJECT_BLOB) != base
    check composeEvidenceDigest("DISPROVED", "DISPROVED", "BUG_SUSPECTED",
      "cafebabe", true, @[], SUBJECT_COMMIT, SUBJECT_BLOB) != base
    check composeEvidenceDigest("DISPROVED", "DISPROVED", "BUG_SUSPECTED",
      "cafebabe", true, norm, "other-commit", SUBJECT_BLOB) != base
    check composeEvidenceDigest("DISPROVED", "DISPROVED", "BUG_SUSPECTED",
      "cafebabe", true, norm, SUBJECT_COMMIT, "other-blob") != base
    discard raw
  test "spec IR digest = sha256 over the canonically joined clause array":
    check canonicalSpecIrDigest(@["a", "b"]) == sha256Hex("a\nb")
    check canonicalSpecIrDigest(@["a", "b"]) != canonicalSpecIrDigest(@["b", "a"])
  test "the legacy v1 fingerprint expression (§4 legacyFingerprints provenance) still carries the counterexample member":
    let digest = canonicalSpecIrDigest(CLAUSES)
    let legacyA = composeReportFingerprint("iftech/nim-libp2p",
      "libp2p/utils/bytesview.nim::toOpenArray", "SPEC-LIBP2P-BV-SLICE",
      "external:libp2p/bytesview/slice-length-law", "1.0.0", digest, @["e=4"])
    let legacyB = composeReportFingerprint("iftech/nim-libp2p",
      "libp2p/utils/bytesview.nim::toOpenArray", "SPEC-LIBP2P-BV-SLICE",
      "external:libp2p/bytesview/slice-length-law", "1.0.0", digest, @["e=5"])
    check legacyA != legacyB
    check legacyA.len == 64
    check legacyA != expectedFindingKey()  # v1 identity != v2 identity

# ---------------------------------------------------------------------------
# Pure: gh outcome classification + payload parsing
# ---------------------------------------------------------------------------

suite "gh outcome classification table":
  test "success and missing binary":
    check classifyGhOutcome(0, "") == gokOk
    check classifyGhOutcome(127, "sh: 1: gh: not found") == gokGhMissing
  test "the contract's blocked families":
    check classifyGhOutcome(1, "gh: Forbidden (HTTP 403)") == gokHttp403
    check classifyGhOutcome(1, "gh: Not Found (HTTP 404)") == gokHttp404
    check classifyGhOutcome(1, "gh: Issues have been disabled for this repository (HTTP 410)") == gokHttp410
    check classifyGhOutcome(1, "gh: Bad credentials (HTTP 401)") == gokAuth
  test "(d) 429 is its own rate-limit family, classified before the generic 4xx catch (§8)":
    check classifyGhOutcome(1, "gh: API rate limit exceeded (HTTP 429)") == gokHttp429
    check classifyGhOutcome(1, "gh: Too many requests (HTTP 429)") == gokHttp429
    check classifyGhOutcome(1, "HTTP 429") == gokHttp429
    # the status code itself is the throttle signal — never confirmed
    # non-creation, never folded into the rejection family:
    check classifyGhOutcome(1, "HTTP 429") != gokRejected
  test "4xx beyond the blocked families is confirmed non-creation":
    check classifyGhOutcome(1, "gh: Unprocessable Entity (HTTP 422)") == gokRejected
  test "5xx / timeout / unknown stay ambiguous (creation state never guessed)":
    check classifyGhOutcome(1, "gh: Internal Server Error (HTTP 500)") == gokAmbiguous
    check classifyGhOutcome(28, "request timed out") == gokTimeout
    check classifyGhOutcome(1, "context deadline exceeded") == gokTimeout
    check classifyGhOutcome(1, "network unreachable") == gokAmbiguous
  test "blocked-reason mapping":
    check blockedReasonFor(gokHttp403) == blocked403
    check blockedReasonFor(gokHttp404) == blocked404
    check blockedReasonFor(gokHttp410) == blocked410
    check blockedReasonFor(gokHttp429) == blocked429
    check blockedReasonFor(gokGhMissing) == blockedGhAuth
    check blockedReasonFor(gokAuth) == blockedGhAuth
    check blockedReasonFor(gokRejected) == failedConfirmed
    check blockedReasonFor(gokTimeout) == ""
    check blockedReasonFor(gokAmbiguous) == ""
    check blocked429 != blocked403
    check blocked429 != failedConfirmed
  test "(d) tokenless 429 still maps to the rate-limit reason (the code is the signal)":
    check blockedReasonFor(gokHttp429, "HTTP 429") == blocked429
    check blockedReasonFor(gokHttp429, "") == blocked429
    check blocked429Detail.contains("rate limited")
    check blocked429Detail.contains("no auto-retry")
    check blocked429Detail != blocked403RateLimitedDetail
  test "403 with rate-limit output stays BLOCKED with an honest rate-limit reason":
    # GitHub's official REST docs: a primary/secondary rate limit answers
    # 403 or 429 (docs.github.com/en/rest/using-the-rest-api/
    # rate-limits-for-the-rest-api) — the recorded reason must say so.
    check classifyGhOutcome(1, "gh: API rate limit exceeded (HTTP 403)") == gokHttp403
    check blockedReasonFor(gokHttp403, "gh: API rate limit exceeded (HTTP 403)") ==
      blocked403RateLimited
    check blockedReasonFor(gokHttp403,
      "HTTP 403 — you have exceeded a secondary rate limit") == blocked403RateLimited
    check blockedReasonFor(gokHttp403, "HTTP 403: too many requests") ==
      blocked403RateLimited
    check blockedReasonFor(gokHttp403, "HTTP 403 retry after 57s") == blocked403RateLimited
    check blockedReasonFor(gokHttp403, "gh: API rate limit exceeded (HTTP 403)") != blocked403
    check blocked403RateLimitedDetail.contains("rate limited")
    check blocked403RateLimitedDetail.contains("no auto-retry")
  test "403 without rate-limit output keeps the permission/creation restriction reason":
    check blockedReasonFor(gokHttp403, "gh: Forbidden (HTTP 403)") == blocked403
    check blockedReasonFor(gokHttp403,
      "gh: creation restricted by interaction limits (HTTP 403)") == blocked403
    check blockedReasonFor(gokHttp403,
      "gh: Resource not accessible by integration (HTTP 403)") == blocked403
    check blockedReasonFor(gokHttp403, "") == blocked403
  test "rate-limit 403 reason is deterministic (same input -> same reason)":
    const rl403 = "gh: API rate limit exceeded (HTTP 403)"
    check blockedReasonFor(gokHttp403, rl403) == blockedReasonFor(gokHttp403, rl403)
    check blockedReasonFor(gokHttp403, rl403) ==
      blockedReasonFor(gokHttp403, rl403.toLowerAscii())
    check blockedReasonFor(gokHttp403, rl403) == blocked403RateLimited

suite "gh payload parsing":
  test "created-issue URL extraction":
    check extractIssueUrl(CREATE_URL_OUTPUT) ==
      (12, "https://github.com/iftech/nim-libp2p/issues/12")
    check extractIssueUrl("no url here").number == 0
    check issueNumberFromUrl("https://github.com/o/r/issues/77") == 77
  test "issue view payload (createdAt is the §6 backfill source)":
    let v = parseIssueView(
      """{"number": 12, "url": "https://github.com/o/r/issues/12", "state": "open", "body": "hi", "createdAt": "2026-10-30T08:00:00Z"}""")
    check v.isOk
    check v.get().number == 12
    check v.get().state == "open"
    check v.get().body == "hi"
    check v.get().createdAt == "2026-10-30T08:00:00Z"
    let noTs = parseIssueView(
      """{"number": 12, "url": "u", "state": "open", "body": "hi"}""")
    check noTs.isOk
    check noTs.get().createdAt == ""
    check parseIssueView("not json").isErr
  test "issue reference lists (search / issue list)":
    let refs = parseIssueRefList("""[{"number": 3, "url": "u3"}, {"number": 0}]""")
    check refs.isOk
    check refs.get().len == 2
    check refs.get()[0] == (3, "u3")
    check parseIssueRefList("{}").isErr
  test "gh contents (base64) template decode":
    let encoded = encode("## Bug report\nbody\n")
    let okDecode = decodeGhContentsJson(
      """{"encoding": "base64", "content": """" & encoded & """"}""")
    check okDecode.isOk
    check okDecode.get() == "## Bug report\nbody\n"
    check decodeGhContentsJson("""{"encoding": "utf-8", "content": "x"}""").isErr
  test "bug-report template section headers, in order":
    check extractTemplateSections("# Title\n## Problem\nbody\n## Impact\n") ==
      @["Problem", "Impact"]

suite "gh command builders":
  test "create is non-interactive and shell-quoted":
    check ghCreateCmd("o/r", "it's", "/tmp/a b.md") ==
      "gh issue create -R 'o/r' --title 'it'\\''s' --body-file '/tmp/a b.md'"
  test "search embeds the identity anchor; list and view shapes (createdAt always fetched)":
    check ghSearchCmd("o/r", "abc") == "gh search issues --repo 'o/r' --json number,url 'abc'"
    check ghListCmd("o/r", "abc").contains("--search 'abc'")
    check ghIssueViewCmd(5, "o/r", false).endsWith("--json number,url,state,createdAt")
    check ghIssueViewCmd(5, "o/r", true).endsWith("--json number,url,state,body,createdAt")
    check ghRepoCmd("o/r") == "gh api repos/'o/r'"

# ---------------------------------------------------------------------------
# Pure: receipt projection (the ledger SSOT record) — v2 schema + v1 source
# ---------------------------------------------------------------------------

suite "receipt schema — round trip, atomicity, fail-closed reload":
  test "toJson -> fromJson is lossless (schema upstream-report-receipt-v2)":
    var r = UpstreamReceipt(
      schemaVersion: upstreamReceiptSchemaVersion,
      findingKey: expectedFindingKey(),
      evidenceDigest: expectedEvidenceDigest(),
      legacyFingerprints: @[LEGACY_FP],
      status: ursSubmitted,
      propositionVerdict: "DISPROVED",
      requirementSourceStatus: "recordedBinding",
      bugAttribution: "BUG_SUSPECTED",
      requestedRepository: "status-im/nim-libp2p",
      resolvedRepository: "iftech/nim-libp2p",
      commit: "c0ffee",
      module: "libp2p/utils/bytesview.nim",
      symbol: "toOpenArray",
      blobSha256: "b205",
      specId: "SPEC-LIBP2P-BV-SLICE",
      ruleId: "external:libp2p/bytesview/slice-length-law",
      ruleVersion: "1.0.0",
      specRelPath: "nim_libp2p_bytesview_slice.json",
      canonicalSpecIrDigest: canonicalSpecIrDigest(CLAUSES),
      normalized: @["e=4"],
      rawQuartet: @["exact input: input.e=4"],
      issueNumber: 12,
      issueUrl: "https://github.com/iftech/nim-libp2p/issues/12",
      attempts: @[UpstreamAttempt(ts: "2026-10-31T12:00:00Z",
        phase: "create-issue", outcome: "exit=0",
        candidateUrl: "https://github.com/iftech/nim-libp2p/issues/12")],
      submittedAt: "2026-10-31T12:00:00Z")
    let j = receiptToJson(r)
    check j{"schemaVersion"}.getStr() == "upstream-report-receipt-v2"
    check j{"findingKey"}.getStr() == expectedFindingKey()
    check j{"evidenceDigest"}.getStr() == expectedEvidenceDigest()
    check j{"legacyFingerprints"}[0].getStr() == LEGACY_FP
    check j{"status"}.getStr() == "SUBMITTED"
    check j{"issue"}{"number"}.getInt() == 12
    check j{"verdict"}{"bugAttribution"}.getStr() == "BUG_SUSPECTED"
    check j{"counterexample"}{"normalized"}[0].getStr() == "e=4"
    let back = receiptFromJson(j)
    check back.isOk
    check back.get() == r
  test "null-able fields render as JSON null; empty legacyFingerprints is an empty array":
    let r = UpstreamReceipt(schemaVersion: upstreamReceiptSchemaVersion,
      findingKey: expectedFindingKey(), status: ursBlocked, blockedReason: blocked410)
    let j = receiptToJson(r)
    check j{"issue"}.kind == JNull
    check j{"blockedReason"}.getStr() == blocked410
    check j{"submittedAt"}.kind == JNull
    check j{"legacyFingerprints"}.kind == JArray
    check j{"legacyFingerprints"}.len == 0
  test "wrong schemaVersion / unknown status fail closed":
    check receiptFromJson(parseJson("""{"schemaVersion": "nope"}""")).isErr
    check receiptFromJson(parseJson(
      """{"schemaVersion": "upstream-report-receipt-v2", "status": "MAYBE"}""")).isErr
    check receiptFromJson(parseJson("[]")).isErr
  test "v1 receipts parse as the read-only migration source (§10): reportFingerprint -> legacyFingerprints":
    let legacy = receiptFromJson(legacyV1ReceiptJson(LEGACY_FP))
    check legacy.isOk
    check legacy.get().schemaVersion == upstreamReceiptSchemaVersionV1
    check legacy.get().legacyFingerprints == @[LEGACY_FP]
    check legacy.get().findingKey == ""  # the v2 identity is computed, not stored
    check legacy.get().issueNumber == 3364
    check legacy.get().submittedAt == ""  # JSON null -> empty (backfill case)
    check receiptFromJson(parseJson(
      """{"schemaVersion": "upstream-report-receipt-v1", "status": "MAYBE"}""")).isErr
  test "atomic write: tmp cleaned up, reload equal, absent = none":
    let (dir, ledgerDir) = makeFixture(makeState("BUG_SUSPECTED", "DISPROVED"))
    let path = joinPath(ledgerDir, expectedFindingKey() & ".json")
    var r = UpstreamReceipt(schemaVersion: upstreamReceiptSchemaVersion,
      findingKey: expectedFindingKey(), status: ursReady)
    check saveReceiptAtomic(r, path).isOk
    check fileExists(path)
    check not fileExists(path & ".tmp")
    let loaded = loadReceipt(path)
    check loaded.isOk and loaded.get().isSome
    check loaded.get().get() == r
    let absent = loadReceipt(joinPath(ledgerDir, "absent.json"))
    check absent.isOk and absent.get().isNone
  test "a present-but-unreadable ledger receipt is a hard error (never a blind create)":
    let (dir, ledgerDir) = makeFixture(makeState("BUG_SUSPECTED", "DISPROVED"))
    let badPath = joinPath(ledgerDir, "bad.json")
    writeFile(badPath, """{"schemaVersion": "nope"}""")
    check loadReceipt(badPath).isErr
  test "evidence carry-forward: prior submittedAt + attempts survive a replacement receipt":
    let priorAttempt = UpstreamAttempt(ts: "2026-10-30T00:00:00Z",
      phase: "create-issue", outcome: "exit=28 timed out",
      candidateUrl: "https://github.com/o/r/issues/77")
    let prior = UpstreamReceipt(schemaVersion: upstreamReceiptSchemaVersion,
      findingKey: expectedFindingKey(), status: ursReconciliationRequired,
      submittedAt: "2026-10-30T09:00:00Z", attempts: @[priorAttempt])
    var fresh = UpstreamReceipt(schemaVersion: upstreamReceiptSchemaVersion,
      findingKey: expectedFindingKey(), status: ursDuplicate)
    carryForwardReceiptEvidence(fresh, prior)
    check fresh.submittedAt == "2026-10-30T09:00:00Z"
    check fresh.attempts.len == 1
    check fresh.attempts[0].candidateUrl == "https://github.com/o/r/issues/77"
    fresh.submittedAt = "2026-11-01T00:00:00Z"
    fresh.attempts = @[UpstreamAttempt(ts: "2026-11-01T00:00:00Z",
      phase: "verify-ledger-submission", outcome: "exit=0")]
    carryForwardReceiptEvidence(fresh, prior)
    check fresh.submittedAt == "2026-11-01T00:00:00Z"
      # a freshly verified submission timestamp wins over the prior one
    check fresh.attempts.len == 2
    check fresh.attempts[0].phase == "create-issue"
    check fresh.attempts[1].phase == "verify-ledger-submission"
  test "carry-forward from an absent prior receipt is a no-op":
    var fresh = UpstreamReceipt(schemaVersion: upstreamReceiptSchemaVersion,
      findingKey: expectedFindingKey(), status: ursReady,
      attempts: @[UpstreamAttempt(ts: "t", phase: "resolve-repository")])
    carryForwardReceiptEvidence(fresh, UpstreamReceipt())
    check fresh.submittedAt == ""
    check fresh.attempts.len == 1

# ---------------------------------------------------------------------------
# Pure: legacy migration helpers (§4/§6)
# ---------------------------------------------------------------------------

suite "legacy migration helpers (§6, pure)":
  test "legacyReceiptMatchesIdentity — canonical triple equality on resolved repo + subject + proposition":
    let legacy = receiptFromJson(legacyV1ReceiptJson(LEGACY_FP)).get()
    let digest = canonicalSpecIrDigest(CLAUSES)
    check legacyReceiptMatchesIdentity(legacy, "iftech/nim-libp2p",
      TARGET_SYMBOL, "SPEC-LIBP2P-BV-SLICE",
      "external:libp2p/bytesview/slice-length-law", "1.0.0", digest)
    check not legacyReceiptMatchesIdentity(legacy, "status-im/nim-libp2p",
      TARGET_SYMBOL, "SPEC-LIBP2P-BV-SLICE",
      "external:libp2p/bytesview/slice-length-law", "1.0.0", digest)
    check not legacyReceiptMatchesIdentity(legacy, "iftech/nim-libp2p",
      "other/mod.nim::sym", "SPEC-LIBP2P-BV-SLICE",
      "external:libp2p/bytesview/slice-length-law", "1.0.0", digest)
    check not legacyReceiptMatchesIdentity(legacy, "iftech/nim-libp2p",
      TARGET_SYMBOL, "SPEC-OTHER",
      "external:libp2p/bytesview/slice-length-law", "1.0.0", digest)
    check not legacyReceiptMatchesIdentity(legacy, "iftech/nim-libp2p",
      TARGET_SYMBOL, "SPEC-LIBP2P-BV-SLICE", "external:other-rule", "1.0.0",
      digest)
    check not legacyReceiptMatchesIdentity(legacy, "iftech/nim-libp2p",
      TARGET_SYMBOL, "SPEC-LIBP2P-BV-SLICE",
      "external:libp2p/bytesview/slice-length-law", "1.0.1", digest)
    check not legacyReceiptMatchesIdentity(legacy, "iftech/nim-libp2p",
      TARGET_SYMBOL, "SPEC-LIBP2P-BV-SLICE",
      "external:libp2p/bytesview/slice-length-law", "1.0.0",
      sha256Hex("other-clauses"))
  test "a v2-schema receipt is never a legacy migration source":
    let v2 = receiptFromJson(legacyV1ReceiptJson(LEGACY_FP,
      schemaVersion = "upstream-report-receipt-v2")).get()
    check not legacyReceiptMatchesIdentity(v2, "iftech/nim-libp2p",
      TARGET_SYMBOL, "SPEC-LIBP2P-BV-SLICE",
      "external:libp2p/bytesview/slice-length-law", "1.0.0",
      canonicalSpecIrDigest(CLAUSES))
  test "legacyReceiptFingerprints — parsed mapping, with the v1 recomputation fallback":
    let digest = canonicalSpecIrDigest(CLAUSES)
    let withField = receiptFromJson(legacyV1ReceiptJson(LEGACY_FP)).get()
    check legacyReceiptFingerprints(withField, "iftech/nim-libp2p",
      TARGET_SYMBOL, "SPEC-LIBP2P-BV-SLICE",
      "external:libp2p/bytesview/slice-length-law", "1.0.0", digest) ==
      @[LEGACY_FP]
    let noField = receiptFromJson(legacyV1ReceiptJson("")).get()
    check legacyReceiptFingerprints(noField, "iftech/nim-libp2p",
      TARGET_SYMBOL, "SPEC-LIBP2P-BV-SLICE",
      "external:libp2p/bytesview/slice-length-law", "1.0.0", digest) ==
      @[composeReportFingerprint("iftech/nim-libp2p", TARGET_SYMBOL,
        "SPEC-LIBP2P-BV-SLICE", "external:libp2p/bytesview/slice-length-law",
        "1.0.0", digest, @[])]
  test "mergeLegacyFingerprints — sorted, deduped union (deterministic across scan order)":
    let empty: seq[string] = @[]
    check mergeLegacyFingerprints(@["b", "a"], @["a", "c", ""]) == @["a", "b", "c"]
    check mergeLegacyFingerprints(empty, empty) == empty
  test "identityAnchors — findingKey first, legacy fingerprints after, deduped":
    check identityAnchors("fk", @["f1", "fk", "f1", ""]) == @["fk", "f1"]
    check identityAnchors("", @["f1"]) == @["f1"]
    check identityAnchors("fk", @[]) == @["fk"]
  test "bodyCarriesIdentity — any anchor confirms the hit (v2 bodies and pre-v2 reportFingerprint lines)":
    check bodyCarriesIdentity("some prose\nfindingKey: fk\n", @["fk", "f1"])
    check bodyCarriesIdentity("reportFingerprint: f1\n", @["fk", "f1"])
    check not bodyCarriesIdentity("an unrelated issue body", @["fk", "f1"])

# ---------------------------------------------------------------------------
# Pure: state / display / findingEvidence parsing (fail-closed)
# ---------------------------------------------------------------------------

suite "state/display parsing — fail-closed findingEvidence consumption":
  test "(e) reportable unit consumes findingEvidence: bindings, digest, subject pin, machine flag":
    let units = selectReportableUnits(makeState("BUG_SUSPECTED", "DISPROVED"))
    check units.isOk
    check units.get().len == 1
    check units.get()[0].targetSymbol == TARGET_SYMBOL
    check units.get()[0].normalized == @["e=4"]
    check units.get()[0].quartetPayloadDigest == "cafebabe"
    check units.get()[0].subjectCommit == SUBJECT_COMMIT
    check units.get()[0].subjectBlob == SUBJECT_BLOB
    check units.get()[0].machineEstablished
    check units.get()[0].claimOutcome == "DISPROVED"
    check units.get()[0].rowStatus == "BUG_SUSPECTED"
    check units.get()[0].machineVerdict == "DISPROVED"
    check not units.get()[0].evidenceMissing
    check units.get()[0].specRelPath == "nim_libp2p_bytesview_slice.json"
    check units.get()[0].specId == "SPEC-LIBP2P-BV-SLICE"
  test "(e) the display unit's quartet is NEVER the evidence source (findingEvidence wins)":
    # makeState's display quartet deliberately says input.e=999 — the
    # normalized bindings must come from the findingEvidence block only.
    let units = selectReportableUnits(makeState("BUG_SUSPECTED", "DISPROVED"))
    check units.get()[0].normalized == @["e=4"]
    check "999" notin units.get()[0].rawQuartet.join(" ")
  test "(e) a reportable unit without findingEvidence stays reportable-but-gated (honest empty set)":
    let units = selectReportableUnits(makeStateWithoutEvidence("BUG_SUSPECTED", "DISPROVED"))
    check units.isOk
    check units.get().len == 1
    check units.get()[0].evidenceMissing
    check units.get()[0].normalized.len == 0
    check units.get()[0].rawQuartet.len == 0
  test "(e) a binding-less counterexample parses to an empty normalized set (not evidence-missing)":
    let units = selectReportableUnits(makeStateEmptyCounterexample("BUG_SUSPECTED", "DISPROVED"))
    check units.isOk
    check not units.get()[0].evidenceMissing
    check units.get()[0].normalized.len == 0
  test "malformed findingEvidence fails closed":
    check selectReportableUnits(makeStateMalformedCounterexample(
      "BUG_SUSPECTED", "DISPROVED")).error.contains("findingEvidence")
    check selectReportableUnits(makeStateMalformedMachineFlag(
      "BUG_SUSPECTED", "DISPROVED")).error.contains("findingEvidence")
  test "BUG_FOUND + DISPROVED is reportable":
    check selectReportableUnits(makeState("BUG_FOUND", "DISPROVED")).isOk
  test "missing display block fails closed":
    check selectReportableUnits(parseJson("{}")).error.contains(
      "missing reportJson.display block")
    check selectReportableUnits(parseJson("[]")).error.contains(
      "not a JSON object")
  test "wrong display schemaVersion fails closed":
    let bad = %*{"reportJson": {"display": {
      "schemaVersion": "bug-verdict-display-v2", "units": []}}}
    check selectReportableUnits(bad).error.contains("bug-verdict-display-v3")
  test "UNKNOWN / NOT_DISPROVED units are never reported upstream":
    check selectReportableUnits(makeState("UNKNOWN", "DISPROVED")).error.contains(
      "no reportable finding")
    check selectReportableUnits(makeState("BUG_FOUND", "NOT_DISPROVED")).error.contains(
      "no reportable finding")
    check selectReportableUnits(makeState("BUG_SUSPECTED", "UNKNOWN")).error.contains(
      "no reportable finding")
  test "INCAPABLE rollup entries are not units and are never selected for reporting":
    # The §3 capability rollup rides display.propositions[] — a sibling of
    # the units array. A state with a reportable unit AND an INCAPABLE
    # rollup selects exactly the unit; an INCAPABLE-only document (zero
    # units) reports nothing.
    var mixed = makeState("BUG_SUSPECTED", "DISPROVED")
    mixed{"reportJson"}{"display"}["propositionRollupSchemaVersion"] =
      %"proposition-rollup-v1"
    mixed{"reportJson"}{"display"}["propositions"] = %*[
      {"id": "prop-incapable",
       "capability": {"status": "INCAPABLE", "reason": "UNKNOWN_SPEC"},
       "verification": {"attempted": false, "verdict": newJNull()}},
      {"id": "prop-capable",
       "capability": {"status": "CAPABLE"},
       "verification": {"attempted": true, "verdict": "UNKNOWN"}}]
    let units = selectReportableUnits(mixed)
    check units.isOk
    check units.get().len == 1
    check units.get()[0].targetSymbol == TARGET_SYMBOL
    var incapableOnly = makeState("BUG_SUSPECTED", "DISPROVED")
    incapableOnly{"reportJson"}{"display"}["units"] = %*[{"targetSymbol": "m::f",
      "bugAttribution": "INCAPABLE", "propositionVerdict": ""}]
    incapableOnly{"reportJson"}{"display"}["propositions"] = %*[
      {"id": "prop-incapable",
       "capability": {"status": "INCAPABLE", "reason": "LANE_NOT_EQUIPPED"},
       "verification": {"attempted": false, "verdict": newJNull()}}]
    check selectReportableUnits(incapableOnly).error.contains("no reportable finding")
    check not isReportableUnit("INCAPABLE", "")
    check not isReportableUnit("", "")
  test "the root-level display placement is accepted (historical)":
    let nested = makeState("BUG_SUSPECTED", "DISPROVED")
    let flat = %*{"display": nested{"reportJson"}{"display"}}
    check selectReportableUnits(flat).isOk

# ---------------------------------------------------------------------------
# Pure: issue body / title contract
# ---------------------------------------------------------------------------

suite "issue body contract (self-contained, no Axiom internals)":
  test "BUG_SUSPECTED: identity lines, INFERRED disclaimer, repro quartet":
    let identity = expectedIdentity()
    let body = composeIssueBody(FACTS, UNIT, "status-im/nim-libp2p",
      "iftech/nim-libp2p", identity, defaultIssueSections)
    check body.contains("findingKey: " & identity.findingKey)
    check body.contains("evidenceDigest: " & identity.evidenceDigest)
    check "legacyFingerprints:" notin body
      # a fresh finding has no v1 record — no empty line noise
    check "reportFingerprint:" notin body
      # the v1 body anchor line is superseded by findingKey (§9)
    check body.contains("INFERRED")
    check body.contains("has NOT been shown to guarantee")
    check body.contains("BytesView.init(@[byte 1, 2, 3, 4, 5, 6])")
    check body.contains("toOpenArray(1, 4)")
    check body.contains("# observed: 3  expected: 4")
    check body.contains("requested as status-im/nim-libp2p")
    check body.contains("iftech/nim-libp2p")
    check body.contains("bvSliceLenActual(e) == (e - 1)")
    check body.contains("bvSliceLenLaw1(e) == e")
    check body.contains("recorded binding: e=4")
  test "legacy fingerprints are recorded in the body (pre-v2 re-linking anchors)":
    var identity = expectedIdentity()
    identity.legacyFingerprints = @["aaa111", "bbb222"]
    let body = composeIssueBody(FACTS, UNIT, "r", "r", identity,
      defaultIssueSections)
    check body.contains("legacyFingerprints: aaa111, bbb222")
  test "no Axiom engine/certificate internals ever enter the body":
    let body = composeIssueBody(FACTS, UNIT, "status-im/nim-libp2p",
      "iftech/nim-libp2p", expectedIdentity(), defaultIssueSections)
    let low = body.toLowerAscii()
    check "axiom" notin low
    check "certificate" notin low
    check "quartet" notin low
    check "displayinputdigest" notin low
    check "groundsrefs" notin low
    check "deadbeef" notin low
    check "cafebabe" notin low
    check "machineStates" notin body
    check "rule linked to software requirement" notin body
  test "BUG_FOUND: recorded requirement basis, never the INFERRED disclaimer":
    let foundUnit = parseReportableUnit(unitOf(makeState("BUG_FOUND", "DISPROVED")))
    let body = composeIssueBody(FACTS, foundUnit, "status-im/nim-libp2p",
      "iftech/nim-libp2p", expectedIdentity(), defaultIssueSections)
    check body.contains("recorded requirement basis")
    check "INFERRED" notin body
  test "template sections are mirrored when the target repo provides them":
    let body = composeIssueBody(FACTS, UNIT, "r", "r", expectedIdentity(),
      @["Overview", "Steps to reproduce"])
    check body.contains("## Overview")
    check body.contains("## Steps to reproduce")
  test "malformed binding value -> verbatim pinned replay, never projected numbers":
    var badUnit = UNIT
    badUnit.normalized = @["e=4x"]
    let body = composeIssueBody(FACTS, badUnit, "status-im/nim-libp2p",
      "iftech/nim-libp2p", expectedIdentity(), defaultIssueSections)
    check body.contains("pinned replay of the recorded counterexample")
    check body.contains("binding: e=4x")
    check "toOpenArray(1, 4)" notin body
    check "# observed: 3" notin body

suite "issue title":
  test "observed vs expected projected from overlay DATA":
    check composeIssueTitle(FACTS, @["e=4"]) ==
      "toOpenArray: observed 3 where the adopted law expects 4 at e=4 " &
      "(external:libp2p/bytesview/slice-length-law)"
  test "no evaluable binding -> generic deterministic title":
    check composeIssueTitle(FACTS, @[]).startsWith(
      "toOpenArray: adopted proposition violated")
  test "malformed binding value -> generic title, never prefix-parsed numbers":
    check composeIssueTitle(FACTS, @["e=4x"]).startsWith(
      "toOpenArray: adopted proposition violated")
    check composeIssueTitle(FACTS, @["e=4x"]).contains("under binding e=4x")

# ---------------------------------------------------------------------------
# Pure: flags + exit codes
# ---------------------------------------------------------------------------

suite "CLI flags + exit codes":
  test "flag parsing is fail-closed on unknown options":
    check parseUpstreamFlags(@["--upstream"]).isOk
    let full = parseUpstreamFlags(@["--upstream", "--dry-run", "--json",
                                    "--state-file", "/x/y.json"])
    check full.isOk
    check full.get().dryRun
    check full.get().emitJson
    check full.get().stateFilePath == "/x/y.json"
    check parseUpstreamFlags(@["--upstream", "--wat"]).isErr
    check parseUpstreamFlags(@["--upstream", "--state-file"]).isErr
  test "exit 0 only for terminal-success statuses":
    check upstreamExitCode(@[]) == 0
    check upstreamExitCode(@[UpstreamUnitOutcome(status: ursReady)]) == 0
    check upstreamExitCode(@[UpstreamUnitOutcome(status: ursSubmitted)]) == 0
    check upstreamExitCode(@[UpstreamUnitOutcome(status: ursDuplicate)]) == 0
    check upstreamExitCode(@[UpstreamUnitOutcome(status: ursBlocked)]) == 1
    check upstreamExitCode(@[UpstreamUnitOutcome(status: ursFailed)]) == 1
    check upstreamExitCode(@[UpstreamUnitOutcome(status: ursReconciliationRequired)]) == 1

# ---------------------------------------------------------------------------
# Pipeline (mock gh — no network): status machine
# ---------------------------------------------------------------------------

suite "pipeline — dry-run READY (no external write, nothing persisted)":
  test "READY preview with preflight + resolution + duplicate check only":
    let state = makeState("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    let m = newHappyMock()
    let res = runPipe(state, dir, ledgerDir, true, m)
    check res.isOk
    let outcomes = res.get()
    check outcomes.len == 1
    check outcomes[0].status == ursReady
    check outcomes[0].findingKey == expectedFindingKey()
    check outcomes[0].requestedRepository == "status-im/nim-libp2p"
    check outcomes[0].resolvedRepository == "iftech/nim-libp2p"
    check outcomes[0].detail.contains("READY (dry-run preview)")
    check m.calls.findIt(it.contains("issue create")) < 0
    check fileCount(ledgerDir) == 0
    check upstreamExitCode(outcomes) == 0
  test "dry-run never persists — a BLOCKED preview leaves the ledger receipt untouched":
    let state = makeState("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    let fk = expectedFindingKey()
    let prior = UpstreamReceipt(
      schemaVersion: upstreamReceiptSchemaVersion,
      findingKey: fk,
      status: ursSubmitted,
      submittedAt: "2026-10-30T09:00:00Z",
      issueNumber: 12,
      issueUrl: "https://github.com/iftech/nim-libp2p/issues/12")
    check saveReceiptAtomic(prior, joinPath(ledgerDir, fk & ".json")).isOk
    # a path that WOULD persist a BLOCKED replacement in a real run
    let m = MockGh()
    m.on("auth status", 0, "ok")
    m.on("repos/'status-im/nim-libp2p'", 0,
      """{"full_name": "iftech/nim-libp2p", "has_issues": false}""")
    let res = runPipe(state, dir, ledgerDir, true, m)
    check res.isOk
    check res.get()[0].status == ursBlocked
    check res.get()[0].blockedReason == blocked410
    check res.get()[0].detail.contains("not persisted")
    check fileCount(ledgerDir) == 1
    let after = loadReceipt(joinPath(ledgerDir, fk & ".json"))
    check after.isOk and after.get().isSome
    check after.get().get().status == ursSubmitted
    check after.get().get().issueNumber == 12

suite "pipeline — SUBMITTED happy path":
  test "duplicate check BEFORE create; verify; persist immediately (v2 receipt at <findingKey>.json)":
    let state = makeState("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    let m = newHappyMock()
    let res = runPipe(state, dir, ledgerDir, false, m)
    check res.isOk
    let outcomes = res.get()
    check outcomes.len == 1
    check outcomes[0].status == ursSubmitted
    check outcomes[0].findingKey == expectedFindingKey()
    check outcomes[0].issueNumber == 12
    check outcomes[0].issueUrl == "https://github.com/iftech/nim-libp2p/issues/12"
    check upstreamExitCode(outcomes) == 0
    let searchIdx = m.calls.findIt(it.contains("search issues"))
    let listIdx = m.calls.findIt(it.contains("issue list"))
    let createIdx = m.calls.findIt(it.contains("issue create"))
    let viewIdx = m.calls.findIt(it.contains("issue view 12"))
    check searchIdx >= 0 and listIdx >= 0
    check createIdx > searchIdx and createIdx > listIdx
    check viewIdx > createIdx
    let loaded = loadReceipt(joinPath(ledgerDir, expectedFindingKey() & ".json"))
    check loaded.isOk and loaded.get().isSome
    let receipt = loaded.get().get()
    check receipt.status == ursSubmitted
    check receipt.schemaVersion == "upstream-report-receipt-v2"
    check receipt.findingKey == expectedFindingKey()
    check receipt.evidenceDigest == expectedEvidenceDigest()
    check receipt.legacyFingerprints == newSeq[string]()
    check receipt.issueNumber == 12
    check receipt.submittedAt == "2026-10-31T12:00:00Z"
    check receipt.requestedRepository == "status-im/nim-libp2p"
    check receipt.resolvedRepository == "iftech/nim-libp2p"
    var phases: seq[string] = @[]
    for a in receipt.attempts:
      phases.add(a.phase)
    check phases == @["resolve-repository", "duplicate-check", "duplicate-check",
      "fetch-issue-template", "create-issue", "verify-submission"]

suite "pipeline — READY intent persistence failure (fail-closed)":
  test "an unwritable ledger forbids the external create":
    let state = makeState("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    # A regular file where the ledger directory must live: every
    # saveReceiptAtomic into it fails while loadReceipt still sees absence —
    # exactly the "record failure" condition.
    removeDir(ledgerDir)
    writeFile(ledgerDir, "")
    let m = newHappyMock()
    let res = runPipe(state, dir, ledgerDir, false, m)
    check res.isErr
    check res.error.contains("READY intent persistence FAILED")
    check res.error.contains(failedReadyPersist)
    check res.error.contains("create is forbidden")
    check m.calls.findIt(it.contains("search issues")) >= 0
    # the pipeline got all the way to the create boundary, then refused
    check m.calls.findIt(it.contains("issue create")) < 0

suite "pipeline — SSOT persistence failure is never terminal success":
  test "a DUPLICATE link whose receipt cannot persist is a hard error carrying the issue identity":
    let state = makeState("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    let fk = expectedFindingKey()
    let prior = UpstreamReceipt(
      schemaVersion: upstreamReceiptSchemaVersion,
      findingKey: fk,
      status: ursSubmitted,
      issueNumber: 12,
      issueUrl: "https://github.com/iftech/nim-libp2p/issues/12")
    check saveReceiptAtomic(prior, joinPath(ledgerDir, fk & ".json")).isOk
    let m = newHappyMock()
    # reads still work, writes fail — the SSOT update cannot land
    setFilePermissions(ledgerDir, {fpUserRead, fpUserExec})
    let res = runPipe(state, dir, ledgerDir, false, m)
    setFilePermissions(ledgerDir, {fpUserRead, fpUserWrite, fpUserExec})
    check res.isErr
    check res.error.contains("receipt persistence FAILED")
    check res.error.contains("DUPLICATE")
    check res.error.contains("issue 12")
    check res.error.contains("https://github.com/iftech/nim-libp2p/issues/12")
    check m.calls.findIt(it.contains("issue create")) < 0
  test "a RECONCILIATION_REQUIRED update whose receipt cannot persist is a hard error too":
    let state = makeState("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    let fk = expectedFindingKey()
    let prior = UpstreamReceipt(
      schemaVersion: upstreamReceiptSchemaVersion,
      findingKey: fk,
      status: ursReconciliationRequired,
      attempts: @[UpstreamAttempt(ts: "2026-10-30T00:00:00Z",
        phase: "create-issue", outcome: "exit=28 request timed out")])
    check saveReceiptAtomic(prior, joinPath(ledgerDir, fk & ".json")).isOk
    let m = MockGh()
    m.on("auth status", 0, "ok")
    m.on("repos/'status-im/nim-libp2p'", 0, REPO_API_OK)
    m.on("search issues", 28, "gh: request timed out")
    setFilePermissions(ledgerDir, {fpUserRead, fpUserExec})
    let res = runPipe(state, dir, ledgerDir, false, m)
    setFilePermissions(ledgerDir, {fpUserRead, fpUserWrite, fpUserExec})
    check res.isErr
    check res.error.contains("receipt persistence FAILED")
    check res.error.contains("RECONCILIATION_REQUIRED")
    check res.error.contains(fk)
    check m.calls.findIt(it.contains("issue create")) < 0

suite "pipeline — idempotency: ledger SUBMITTED -> DUPLICATE, no gh write":
  test "the ledger-claimed submission is verified, then linked":
    let state = makeState("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    let fk = expectedFindingKey()
    let prior = UpstreamReceipt(
      schemaVersion: upstreamReceiptSchemaVersion,
      findingKey: fk,
      status: ursSubmitted,
      issueNumber: 12,
      issueUrl: "https://github.com/iftech/nim-libp2p/issues/12")
    check saveReceiptAtomic(prior, joinPath(ledgerDir, fk & ".json")).isOk
    let m = newHappyMock()
    let res = runPipe(state, dir, ledgerDir, false, m)
    check res.isOk
    check res.get()[0].status == ursDuplicate
    check res.get()[0].issueUrl == "https://github.com/iftech/nim-libp2p/issues/12"
    check upstreamExitCode(res.get()) == 0
    check m.calls.findIt(it.contains("issue create")) < 0
    check m.calls.findIt(it.contains("search issues")) < 0
  test "(c) re-run over a v2 SUBMITTED receipt: same receipt file, same identity, DUPLICATE — the create path is never reached":
    let state = makeState("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    let fk = expectedFindingKey()
    let res1 = runPipe(state, dir, ledgerDir, false, newHappyMock())
    check res1.isOk
    check res1.get()[0].status == ursSubmitted
    let first = loadReceipt(joinPath(ledgerDir, fk & ".json"))
    check first.isOk and first.get().isSome
    let receipt1 = first.get().get()
    check receipt1.schemaVersion == "upstream-report-receipt-v2"
    check receipt1.findingKey == fk
    check receipt1.evidenceDigest == expectedEvidenceDigest()
    check receipt1.issueNumber == 12
    # Run 2: identical inputs -> DUPLICATE against the SAME receipt file.
    let m2 = newHappyMock()
    let res2 = runPipe(state, dir, ledgerDir, false, m2)
    check res2.isOk
    check res2.get()[0].status == ursDuplicate
    check res2.get()[0].issueNumber == 12
    check upstreamExitCode(res2.get()) == 0
    check m2.calls.findIt(it.contains("issue create")) < 0
    check m2.calls.findIt(it.contains("search issues")) < 0
    let second = loadReceipt(joinPath(ledgerDir, fk & ".json"))
    check second.isOk and second.get().isSome
    let receipt2 = second.get().get()
    check receipt2.status == ursDuplicate
    check receipt2.findingKey == receipt1.findingKey
    check receipt2.evidenceDigest == receipt1.evidenceDigest
    check receipt2.legacyFingerprints == receipt1.legacyFingerprints
    check receipt2.issueNumber == receipt1.issueNumber
    check receipt2.issueUrl == receipt1.issueUrl
    check receipt2.submittedAt == receipt1.submittedAt

suite "pipeline — receipt evidence preservation (§10: a re-run never destroys prior evidence)":
  test "ledger SUBMITTED -> DUPLICATE keeps submittedAt and the attempt history":
    let state = makeState("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    let fk = expectedFindingKey()
    let prior = UpstreamReceipt(
      schemaVersion: upstreamReceiptSchemaVersion,
      findingKey: fk,
      status: ursSubmitted,
      submittedAt: "2026-10-30T09:00:00Z",
      issueNumber: 12,
      issueUrl: "https://github.com/iftech/nim-libp2p/issues/12",
      attempts: @[UpstreamAttempt(ts: "2026-10-30T09:00:00Z",
        phase: "create-issue", outcome: "exit=0",
        candidateUrl: "https://github.com/iftech/nim-libp2p/issues/12")])
    check saveReceiptAtomic(prior, joinPath(ledgerDir, fk & ".json")).isOk
    let m = newHappyMock()
    let res = runPipe(state, dir, ledgerDir, false, m)
    check res.isOk
    check res.get()[0].status == ursDuplicate
    let loaded = loadReceipt(joinPath(ledgerDir, fk & ".json"))
    check loaded.isOk and loaded.get().isSome
    let receipt = loaded.get().get()
    check receipt.status == ursDuplicate
    check receipt.submittedAt == "2026-10-30T09:00:00Z"
    var phases: seq[string] = @[]
    for a in receipt.attempts:
      phases.add(a.phase)
    check phases == @["create-issue", "resolve-repository",
      "verify-ledger-submission"]
    check receipt.attempts[0].candidateUrl ==
      "https://github.com/iftech/nim-libp2p/issues/12"
  test "a dup-check failure over RECONCILIATION_REQUIRED keeps RR + the candidateUrl recovery input":
    let state = makeState("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    let fk = expectedFindingKey()
    let prior = UpstreamReceipt(
      schemaVersion: upstreamReceiptSchemaVersion,
      findingKey: fk,
      status: ursReconciliationRequired,
      attempts: @[UpstreamAttempt(ts: "2026-10-30T00:00:00Z",
        phase: "create-issue", outcome: "exit=1 request timed out",
        candidateUrl: "https://github.com/iftech/nim-libp2p/issues/77")])
    check saveReceiptAtomic(prior, joinPath(ledgerDir, fk & ".json")).isOk
    let m = MockGh()
    m.on("auth status", 0, "ok")
    m.on("repos/'status-im/nim-libp2p'", 0, REPO_API_OK)
    m.on("issue view 77", 1, "gh: Not Found (HTTP 404)")
    m.on("search issues", 28, "gh: request timed out")
    let res = runPipe(state, dir, ledgerDir, false, m)
    check res.isOk
    # BLOCKED would bury the candidate recovery input under a status the next
    # run does not reconcile from — the ambiguous creation stays RR.
    check res.get()[0].status == ursReconciliationRequired
    check upstreamExitCode(res.get()) == 1
    check m.calls.findIt(it.contains("issue create")) < 0
    let loaded = loadReceipt(joinPath(ledgerDir, fk & ".json"))
    check loaded.isOk and loaded.get().isSome
    let receipt = loaded.get().get()
    check receipt.status == ursReconciliationRequired
    var phases: seq[string] = @[]
    var keptCandidate = false
    for a in receipt.attempts:
      phases.add(a.phase)
      if a.candidateUrl == "https://github.com/iftech/nim-libp2p/issues/77":
        keptCandidate = true
    check phases == @["create-issue", "resolve-repository",
      "reconcile-candidate", "duplicate-check", "reconcile"]
    check keptCandidate
  test "issues-disabled (410) over a ledger SUBMITTED receipt keeps submittedAt and attempts":
    let state = makeState("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    let fk = expectedFindingKey()
    let prior = UpstreamReceipt(
      schemaVersion: upstreamReceiptSchemaVersion,
      findingKey: fk,
      status: ursSubmitted,
      submittedAt: "2026-10-30T09:00:00Z",
      issueNumber: 12,
      issueUrl: "https://github.com/iftech/nim-libp2p/issues/12",
      attempts: @[UpstreamAttempt(ts: "2026-10-30T09:00:00Z",
        phase: "create-issue", outcome: "exit=0")])
    check saveReceiptAtomic(prior, joinPath(ledgerDir, fk & ".json")).isOk
    let m = MockGh()
    m.on("auth status", 0, "ok")
    m.on("repos/'status-im/nim-libp2p'", 0,
      """{"full_name": "iftech/nim-libp2p", "has_issues": false}""")
    let res = runPipe(state, dir, ledgerDir, false, m)
    check res.isOk
    check res.get()[0].status == ursBlocked
    check res.get()[0].blockedReason == blocked410
    let loaded = loadReceipt(joinPath(ledgerDir, fk & ".json"))
    check loaded.isOk and loaded.get().isSome
    let receipt = loaded.get().get()
    check receipt.status == ursBlocked
    check receipt.blockedReason == blocked410
    check receipt.submittedAt == "2026-10-30T09:00:00Z"
    var phases: seq[string] = @[]
    for a in receipt.attempts:
      phases.add(a.phase)
    check phases == @["create-issue", "resolve-repository"]

suite "pipeline — RECONCILIATION_REQUIRED: candidate recovery, never blind-retry":
  test "direct gh issue view of the recorded candidate comes FIRST":
    let state = makeState("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    let fk = expectedFindingKey()
    let prior = UpstreamReceipt(
      schemaVersion: upstreamReceiptSchemaVersion,
      findingKey: fk,
      status: ursReconciliationRequired,
      attempts: @[UpstreamAttempt(ts: "2026-10-30T00:00:00Z",
        phase: "create-issue", outcome: "exit=1 request timed out",
        candidateUrl: "https://github.com/iftech/nim-libp2p/issues/77")])
    check saveReceiptAtomic(prior, joinPath(ledgerDir, fk & ".json")).isOk
    let m = MockGh()
    m.on("auth status", 0, "ok")
    m.on("repos/'status-im/nim-libp2p'", 0, REPO_API_OK)
    m.on("issue view 77", 0, $(%*{"number": 77,
      "url": "https://github.com/iftech/nim-libp2p/issues/77",
      "state": "open", "body": "findingKey: " & fk & "\n"}))
    let res = runPipe(state, dir, ledgerDir, false, m)
    check res.isOk
    check res.get()[0].status == ursDuplicate
    check res.get()[0].issueNumber == 77
    check res.get()[0].issueUrl == "https://github.com/iftech/nim-libp2p/issues/77"
    check upstreamExitCode(res.get()) == 0
    check m.calls.findIt(it.contains("issue view 77")) >= 0
    check m.calls.findIt(it.contains("issue create")) < 0
    check m.calls.findIt(it.contains("search issues")) < 0
  test "an empty remote re-query keeps RECONCILIATION_REQUIRED (no regeneration)":
    # Contract §5: RECONCILIATION_REQUIRED -> SUBMITTED | DUPLICATE only — a
    # search that simply finds nothing is NOT a regeneration license.
    let state = makeState("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    let fk = expectedFindingKey()
    let prior = UpstreamReceipt(
      schemaVersion: upstreamReceiptSchemaVersion,
      findingKey: fk,
      status: ursReconciliationRequired,
      attempts: @[UpstreamAttempt(ts: "2026-10-30T00:00:00Z",
        phase: "create-issue", outcome: "exit=28 request timed out")])
    check saveReceiptAtomic(prior, joinPath(ledgerDir, fk & ".json")).isOk
    let m = MockGh()
    m.on("auth status", 0, "ok")
    m.on("repos/'status-im/nim-libp2p'", 0, REPO_API_OK)
    m.on("search issues", 0, "[]")
    m.on("issue list", 0, "[]")
    let res = runPipe(state, dir, ledgerDir, false, m)
    check res.isOk
    check res.get()[0].status == ursReconciliationRequired
    check upstreamExitCode(res.get()) == 1
    check m.calls.findIt(it.contains("issue create")) < 0
    check m.calls.findIt(it.contains("ISSUE_TEMPLATE")) < 0
    let loaded = loadReceipt(joinPath(ledgerDir, fk & ".json"))
    check loaded.isOk and loaded.get().isSome
    check loaded.get().get().status == ursReconciliationRequired
  test "the preserved RR receipt recovers the duplicate on a later healthy re-query":
    let state = makeState("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    let fk = expectedFindingKey()
    let prior = UpstreamReceipt(
      schemaVersion: upstreamReceiptSchemaVersion,
      findingKey: fk,
      status: ursReconciliationRequired,
      attempts: @[UpstreamAttempt(ts: "2026-10-30T00:00:00Z",
        phase: "create-issue", outcome: "exit=1 request timed out",
        candidateUrl: "https://github.com/iftech/nim-libp2p/issues/77")])
    check saveReceiptAtomic(prior, joinPath(ledgerDir, fk & ".json")).isOk
    # Run 1: the re-query is unavailable — RR must survive, never demote.
    let m1 = MockGh()
    m1.on("auth status", 0, "ok")
    m1.on("repos/'status-im/nim-libp2p'", 0, REPO_API_OK)
    m1.on("issue view 77", 1, "gh: Not Found (HTTP 404)")
    m1.on("search issues", 28, "gh: request timed out")
    let res1 = runPipe(state, dir, ledgerDir, false, m1)
    check res1.isOk
    check res1.get()[0].status == ursReconciliationRequired
    check m1.calls.findIt(it.contains("issue create")) < 0
    # Run 2: the re-query recovers the real issue — DUPLICATE, never a create.
    let m2 = MockGh()
    m2.on("auth status", 0, "ok")
    m2.on("repos/'status-im/nim-libp2p'", 0, REPO_API_OK)
    m2.on("issue view 77", 1, "gh: Not Found (HTTP 404)")
    m2.on("search issues", 0,
      $(%*[{"number": 88, "url": "https://github.com/iftech/nim-libp2p/issues/88"}]))
    m2.on("issue view 88", 0, $(%*{"number": 88,
      "url": "https://github.com/iftech/nim-libp2p/issues/88",
      "state": "open", "body": "findingKey: " & fk & "\n"}))
    let res2 = runPipe(state, dir, ledgerDir, false, m2)
    check res2.isOk
    check res2.get()[0].status == ursDuplicate
    check res2.get()[0].issueNumber == 88
    check upstreamExitCode(res2.get()) == 0
    check m2.calls.findIt(it.contains("issue create")) < 0

suite "pipeline — BLOCKED paths":
  test "target unresolvable (404) at repository resolution":
    let state = makeState("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    let m = MockGh()
    m.on("auth status", 0, "ok")
    m.on("repos/'status-im/nim-libp2p'", 1, "gh: Not Found (HTTP 404)")
    let res = runPipe(state, dir, ledgerDir, false, m)
    check res.isOk
    check res.get()[0].status == ursBlocked
    check res.get()[0].blockedReason == blocked404
    check res.get()[0].resolvedRepository == ""
    check upstreamExitCode(res.get()) == 1
    check m.calls.findIt(it.contains("issue create")) < 0
  test "issues disabled via the repository API (has_issues = false)":
    let state = makeState("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    let m = MockGh()
    m.on("auth status", 0, "ok")
    m.on("repos/'status-im/nim-libp2p'", 0,
      """{"full_name": "iftech/nim-libp2p", "has_issues": false}""")
    let res = runPipe(state, dir, ledgerDir, false, m)
    check res.isOk
    check res.get()[0].status == ursBlocked
    check res.get()[0].blockedReason == blocked410
    check m.calls.findIt(it.contains("issue create")) < 0
    let loaded = loadReceipt(joinPath(ledgerDir, expectedFindingKey() & ".json"))
    check loaded.isOk and loaded.get().isSome
    check loaded.get().get().blockedReason == blocked410
  test "410 at create time persists the BLOCKED receipt":
    let state = makeState("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    let m = newHappyMock(
      "gh: Issues have been disabled for this repository (HTTP 410)", 1)
    let res = runPipe(state, dir, ledgerDir, false, m)
    check res.isOk
    check res.get()[0].status == ursBlocked
    check res.get()[0].blockedReason == blocked410
    check upstreamExitCode(res.get()) == 1
    let loaded = loadReceipt(joinPath(ledgerDir, expectedFindingKey() & ".json"))
    check loaded.isOk and loaded.get().isSome
    check loaded.get().get().blockedReason == blocked410
  test "unauthenticated gh blocks before any other gh call":
    let state = makeState("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    let m = MockGh()
    m.on("auth status", 1,
      "gh: To get started with GitHub CLI, please run: gh auth login")
    let res = runPipe(state, dir, ledgerDir, false, m)
    check res.isOk
    check res.get()[0].status == ursBlocked
    check res.get()[0].blockedReason == blockedGhAuth
    check m.calls.len == 1
  test "a failed duplicate check blocks creation (never risks a duplicate)":
    let state = makeState("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    let m = MockGh()
    m.on("auth status", 0, "ok")
    m.on("repos/'status-im/nim-libp2p'", 0, REPO_API_OK)
    m.on("search issues", 28, "gh: request timed out")
    let res = runPipe(state, dir, ledgerDir, false, m)
    check res.isOk
    check res.get()[0].status == ursBlocked
    check res.get()[0].blockedReason == blockedDupCheck
    check m.calls.findIt(it.contains("issue create")) < 0

suite "pipeline — 429 rate limit (§8: transient restriction, never rejected)":
  test "(d) HTTP 429 at create -> BLOCKED with the 429 rate-limit reason":
    let state = makeState("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    let m = newHappyMock("gh: API rate limit exceeded (HTTP 429)", 1)
    let res = runPipe(state, dir, ledgerDir, false, m)
    check res.isOk
    check res.get()[0].status == ursBlocked
    check res.get()[0].blockedReason == blocked429
    check upstreamExitCode(res.get()) == 1
    let loaded = loadReceipt(joinPath(ledgerDir, expectedFindingKey() & ".json"))
    check loaded.isOk and loaded.get().isSome
    check loaded.get().get().status == ursBlocked
    check loaded.get().get().blockedReason == blocked429
  test "(d) a tokenless 429 is still the rate-limit restriction (the code is the signal)":
    let state = makeState("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    let m = newHappyMock("gh: HTTP 429 response", 1)
    let res = runPipe(state, dir, ledgerDir, false, m)
    check res.isOk
    check res.get()[0].status == ursBlocked
    check res.get()[0].blockedReason == blocked429
  test "(d) 429 at repository resolution blocks with the rate-limit reason (no create)":
    let state = makeState("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    let m = MockGh()
    m.on("auth status", 0, "ok")
    m.on("repos/'status-im/nim-libp2p'", 1,
      "gh: API rate limit exceeded (HTTP 429)")
    let res = runPipe(state, dir, ledgerDir, false, m)
    check res.isOk
    check res.get()[0].status == ursBlocked
    check res.get()[0].blockedReason == blocked429
    check m.calls.findIt(it.contains("issue create")) < 0
  test "(d) 429 at the duplicate check blocks creation (a rate-limited re-query would risk a duplicate)":
    let state = makeState("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    let m = MockGh()
    m.on("auth status", 0, "ok")
    m.on("repos/'status-im/nim-libp2p'", 0, REPO_API_OK)
    m.on("search issues", 1, "gh: API rate limit exceeded (HTTP 429)")
    let res = runPipe(state, dir, ledgerDir, false, m)
    check res.isOk
    check res.get()[0].status == ursBlocked
    check res.get()[0].blockedReason == blocked429
    check m.calls.findIt(it.contains("issue create")) < 0

suite "pipeline — confirmed submission failure":
  test "422 at create -> FAILED (confirmed non-creation), re-creatable":
    let state = makeState("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    let m = newHappyMock("gh: Unprocessable Entity (HTTP 422)", 1)
    let res = runPipe(state, dir, ledgerDir, false, m)
    check res.isOk
    check res.get()[0].status == ursFailed
    check res.get()[0].blockedReason == failedConfirmed
    check upstreamExitCode(res.get()) == 1
  test "timeout at create -> RECONCILIATION_REQUIRED with the candidate recorded":
    let state = makeState("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    let m = MockGh()
    m.on("auth status", 0, "ok")
    m.on("repos/'status-im/nim-libp2p'", 0, REPO_API_OK)
    m.on("search issues", 0, "[]")
    m.on("issue list", 0, "[]")
    m.on("ISSUE_TEMPLATE", 1, "gh: Not Found (HTTP 404)")
    m.on("issue create", 28, "gh: request timed out")
    let res = runPipe(state, dir, ledgerDir, false, m)
    check res.isOk
    check res.get()[0].status == ursReconciliationRequired
    check upstreamExitCode(res.get()) == 1
    let loaded = loadReceipt(joinPath(ledgerDir, expectedFindingKey() & ".json"))
    check loaded.isOk and loaded.get().isSome
    let receipt = loaded.get().get()
    check receipt.status == ursReconciliationRequired
    var hasCandidate = false
    for a in receipt.attempts:
      if a.candidateUrl.len > 0:
        hasCandidate = true
    check hasCandidate == false
      # the timed-out create printed no URL — nothing to recover from; the
      # NEXT run's mandatory remote search is the re-query.

suite "pipeline — §6 legacy v1 receipt migration (identity triple -> v2 succession)":
  test "(b) a v1 legacy receipt migrates: v2 receipt at <findingKey>.json with legacyFingerprints, issue succession and the created_at backfill":
    let state = makeState("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    writeFile(joinPath(ledgerDir, LEGACY_FP & ".json"),
      $legacyV1ReceiptJson(LEGACY_FP))
    let m = MockGh()
    m.on("auth status", 0, "ok")
    m.on("repos/'status-im/nim-libp2p'", 0, REPO_API_OK)
    m.on("issue view 3364", 0, $(%*{"number": 3364,
      "url": "https://github.com/iftech/nim-libp2p/issues/3364",
      "state": "OPEN", "createdAt": "2026-10-30T08:00:00Z"}))
    m.on("search issues", 0, "[]")
    m.on("issue list", 0, "[]")
    m.on("issue create", 0, CREATE_URL_OUTPUT)  # must never be reached
    let res = runPipe(state, dir, ledgerDir, false, m)
    check res.isOk
    check res.get()[0].status == ursDuplicate
    check res.get()[0].findingKey == expectedFindingKey()
    check res.get()[0].issueNumber == 3364
    check upstreamExitCode(res.get()) == 0
    check m.calls.findIt(it.contains("issue create")) < 0
    # the v1 original stays immutable
    let v1After = parseFile(joinPath(ledgerDir, LEGACY_FP & ".json"))
    check v1After{"schemaVersion"}.getStr() == "upstream-report-receipt-v1"
    check v1After{"reportFingerprint"}.getStr() == LEGACY_FP
    # the authoritative v2 receipt landed at <findingKey>.json
    let loaded = loadReceipt(joinPath(ledgerDir, expectedFindingKey() & ".json"))
    check loaded.isOk and loaded.get().isSome
    let receipt = loaded.get().get()
    check receipt.schemaVersion == "upstream-report-receipt-v2"
    check receipt.findingKey == expectedFindingKey()
    check receipt.legacyFingerprints == @[LEGACY_FP]
    check receipt.status == ursDuplicate
    check receipt.issueNumber == 3364
    check receipt.issueUrl == "https://github.com/iftech/nim-libp2p/issues/3364"
    check receipt.submittedAt == "2026-10-30T08:00:00Z"
      # §6 backfill: the v1 submittedAt was null -> GitHub created_at
    check receipt.commit == SUBJECT_COMMIT
    check receipt.evidenceDigest == expectedEvidenceDigest()
    check receipt.requirementSourceStatus == "unrecorded"
      # verdict succession from the v1 record (the fresh display says recordedBinding)
    var phases: seq[string] = @[]
    for a in receipt.attempts:
      phases.add(a.phase)
    check phases == @["resolve-repository", "legacy-migrate",
      "verify-ledger-submission", "legacy-backfill"]
  test "(b) multiple matching legacy receipts -> fail-closed BLOCKED (ambiguous), nothing persisted":
    let state = makeState("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    const otherFp = "aa00000000000000000000000000000000000000000000000000000000000001"
    writeFile(joinPath(ledgerDir, LEGACY_FP & ".json"),
      $legacyV1ReceiptJson(LEGACY_FP))
    writeFile(joinPath(ledgerDir, otherFp & ".json"),
      $legacyV1ReceiptJson(otherFp))
    let m = MockGh()
    m.on("auth status", 0, "ok")
    m.on("repos/'status-im/nim-libp2p'", 0, REPO_API_OK)
    let res = runPipe(state, dir, ledgerDir, false, m)
    check res.isOk
    check res.get()[0].status == ursBlocked
    check res.get()[0].blockedReason == blockedLegacyAmbiguous
    check res.get()[0].detail.contains("legacy receipts match")
    check upstreamExitCode(res.get()) == 1
    check m.calls.findIt(it.contains("issue create")) < 0
    check fileCount(ledgerDir) == 2  # nothing persisted beyond the v1 originals
  test "(b) migration is dry-run safe: the preview inherits the legacy identity but persists nothing":
    let state = makeState("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    writeFile(joinPath(ledgerDir, LEGACY_FP & ".json"),
      $legacyV1ReceiptJson(LEGACY_FP))
    let m = MockGh()
    m.on("auth status", 0, "ok")
    m.on("repos/'status-im/nim-libp2p'", 0, REPO_API_OK)
    m.on("issue view 3364", 0, $(%*{"number": 3364,
      "url": "https://github.com/iftech/nim-libp2p/issues/3364",
      "state": "OPEN", "createdAt": "2026-10-30T08:00:00Z"}))
    let res = runPipe(state, dir, ledgerDir, true, m)
    check res.isOk
    check res.get()[0].status == ursDuplicate
    check res.get()[0].detail.contains("dry-run")
    check fileCount(ledgerDir) == 1  # only the immutable v1 original
    let absent = loadReceipt(joinPath(ledgerDir, expectedFindingKey() & ".json"))
    check absent.isOk and absent.get().isNone
    check m.calls.findIt(it.contains("issue create")) < 0
  test "(b) a migrated-but-unverifiable legacy issue keeps RR with the inherited identity, then a healthy re-query recovers DUPLICATE + backfill":
    let state = makeState("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    writeFile(joinPath(ledgerDir, LEGACY_FP & ".json"),
      $legacyV1ReceiptJson(LEGACY_FP))
    # Run 1: the migration's verification view fails -> RR (never a create),
    # the inherited identity survives, submittedAt stays honestly unset.
    let m1 = MockGh()
    m1.on("auth status", 0, "ok")
    m1.on("repos/'status-im/nim-libp2p'", 0, REPO_API_OK)
    m1.on("issue view 3364", 1, "gh: server error (HTTP 502)")
    let res1 = runPipe(state, dir, ledgerDir, false, m1)
    check res1.isOk
    check res1.get()[0].status == ursReconciliationRequired
    check upstreamExitCode(res1.get()) == 1
    check m1.calls.findIt(it.contains("issue create")) < 0
    let mid = loadReceipt(joinPath(ledgerDir, expectedFindingKey() & ".json"))
    check mid.isOk and mid.get().isSome
    let rrReceipt = mid.get().get()
    check rrReceipt.schemaVersion == "upstream-report-receipt-v2"
    check rrReceipt.status == ursReconciliationRequired
    check rrReceipt.legacyFingerprints == @[LEGACY_FP]
    check rrReceipt.issueNumber == 3364
    check rrReceipt.submittedAt == ""
    # Run 2: the re-query recovers the issue -> DUPLICATE with the backfill.
    let m2 = MockGh()
    m2.on("auth status", 0, "ok")
    m2.on("repos/'status-im/nim-libp2p'", 0, REPO_API_OK)
    m2.on("issue view 3364", 0, $(%*{"number": 3364,
      "url": "https://github.com/iftech/nim-libp2p/issues/3364",
      "state": "OPEN", "createdAt": "2026-10-30T08:00:00Z"}))
    let res2 = runPipe(state, dir, ledgerDir, false, m2)
    check res2.isOk
    check res2.get()[0].status == ursDuplicate
    check res2.get()[0].issueNumber == 3364
    check upstreamExitCode(res2.get()) == 0
    check m2.calls.findIt(it.contains("issue create")) < 0
    let recovered = loadReceipt(joinPath(ledgerDir, expectedFindingKey() & ".json"))
    check recovered.isOk and recovered.get().isSome
    let dupReceipt = recovered.get().get()
    check dupReceipt.status == ursDuplicate
    check dupReceipt.submittedAt == "2026-10-30T08:00:00Z"
    check dupReceipt.legacyFingerprints == @[LEGACY_FP]
    var phases: seq[string] = @[]
    for a in dupReceipt.attempts:
      phases.add(a.phase)
    check phases == @["resolve-repository", "legacy-migrate",
      "verify-ledger-submission", "reconcile", "legacy-backfill",
      "resolve-repository", "verify-ledger-submission", "legacy-backfill"]
  test "(b) a non-matching legacy receipt is ignored — a fresh SUBMITTED proceeds without inheriting it":
    let state = makeState("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    const otherFp = "bb00000000000000000000000000000000000000000000000000000000000002"
    writeFile(joinPath(ledgerDir, otherFp & ".json"),
      $legacyV1ReceiptJson(otherFp, specId = "SPEC-OTHER"))
    let m = newHappyMock()
    let res = runPipe(state, dir, ledgerDir, false, m)
    check res.isOk
    check res.get()[0].status == ursSubmitted
    let loaded = loadReceipt(joinPath(ledgerDir, expectedFindingKey() & ".json"))
    check loaded.isOk and loaded.get().isSome
    let receipt = loaded.get().get()
    check receipt.legacyFingerprints == newSeq[string]()
    check receipt.issueNumber == 12
    # the non-matching v1 original is untouched
    let other = parseFile(joinPath(ledgerDir, otherFp & ".json"))
    check other{"schemaVersion"}.getStr() == "upstream-report-receipt-v1"
    check fileCount(ledgerDir) == 2
  test "(b) an unreadable legacy receipt is a hard error (fail-closed, never a blind create)":
    let state = makeState("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    writeFile(joinPath(ledgerDir, "broken.json"), """{"schemaVersion": "nope"}""")
    let m = MockGh()
    m.on("auth status", 0, "ok")
    m.on("repos/'status-im/nim-libp2p'", 0, REPO_API_OK)
    let res = runPipe(state, dir, ledgerDir, false, m)
    check res.isErr
    check res.error.contains("legacy receipt scan failed")
    check m.calls.findIt(it.contains("issue create")) < 0

suite "pipeline — findingEvidence gate (§11: no evidence, no report)":
  test "(e) missing findingEvidence -> BLOCKED before any gh call; nothing persisted":
    let state = makeStateWithoutEvidence("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    let m = MockGh()  # ANY gh call would be recorded here
    m.on("auth status", 0, "ok")
    let res = runPipe(state, dir, ledgerDir, false, m)
    check res.isOk
    check res.get()[0].status == ursBlocked
    check res.get()[0].blockedReason == blockedEvidenceMissing
    check res.get()[0].detail.contains("common four evidence elements")
    check m.calls.len == 0
    check fileCount(ledgerDir) == 0
    check upstreamExitCode(res.get()) == 1
  test "(e) the dry-run preview of a gated finding is BLOCKED too (never READY)":
    let state = makeStateWithoutEvidence("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    let m = MockGh()
    m.on("auth status", 0, "ok")
    let res = runPipe(state, dir, ledgerDir, true, m)
    check res.isOk
    check res.get()[0].status == ursBlocked
    check res.get()[0].blockedReason == blockedEvidenceMissing
    check m.calls.len == 0
    check fileCount(ledgerDir) == 0
  test "(e) a binding-less counterexample blocks with the empty-counterexample reason":
    let state = makeStateEmptyCounterexample("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    let m = MockGh()
    m.on("auth status", 0, "ok")
    let res = runPipe(state, dir, ledgerDir, false, m)
    check res.isOk
    check res.get()[0].status == ursBlocked
    check res.get()[0].blockedReason == blockedEvidenceEmpty
    check m.calls.len == 0
    check fileCount(ledgerDir) == 0
  test "(e) malformed findingEvidence fails closed":
    let state = makeStateMalformedCounterexample("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    let m = MockGh()
    m.on("auth status", 0, "ok")
    let res = runPipe(state, dir, ledgerDir, false, m)
    check res.isErr
    check res.error.contains("findingEvidence")
    check m.calls.len == 0
    let state2 = makeStateMalformedMachineFlag("BUG_SUSPECTED", "DISPROVED")
    let (dir2, ledgerDir2) = makeFixture(state2)
    let res2 = runPipe(state2, dir2, ledgerDir2, false, m)
    check res2.isErr
    check res2.error.contains("findingEvidence")
  test "(e) evidence present: normalized non-empty and the receipt pin comes from findingEvidence":
    let state = makeState("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    let m = newHappyMock()
    let res = runPipe(state, dir, ledgerDir, false, m)
    check res.isOk
    check res.get()[0].status == ursSubmitted
    let loaded = loadReceipt(joinPath(ledgerDir, expectedFindingKey() & ".json"))
    check loaded.isOk and loaded.get().isSome
    let receipt = loaded.get().get()
    check receipt.normalized == @["e=4"]
    check receipt.commit == SUBJECT_COMMIT
    check receipt.blobSha256 == SUBJECT_BLOB
    check receipt.evidenceDigest == expectedEvidenceDigest()

suite "pipeline — 3-run state-transition chains (prior identity, never search-dependent)":
  test "DUPLICATE receipt re-queries its issue DIRECTLY — a search-index miss cannot cause a re-create":
    let state = makeState("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    # Run 1: fresh create -> SUBMITTED #12.
    let res1 = runPipe(state, dir, ledgerDir, false, newHappyMock())
    check res1.isOk
    check res1.get()[0].status == ursSubmitted
    check res1.get()[0].issueNumber == 12
    # Run 2: ledger SUBMITTED -> DUPLICATE (direct re-query).
    let res2 = runPipe(state, dir, ledgerDir, false, newHappyMock())
    check res2.isOk
    check res2.get()[0].status == ursDuplicate
    check res2.get()[0].issueNumber == 12
    # Run 3: the search index misses the issue — the structured identity
    # still wins via the direct gh issue view; never a re-create.
    let m3 = MockGh()
    m3.on("auth status", 0, "ok")
    m3.on("repos/'status-im/nim-libp2p'", 0, REPO_API_OK)
    m3.on("issue view 12", 0, $(%*{"number": 12,
      "url": "https://github.com/iftech/nim-libp2p/issues/12", "state": "open"}))
    m3.on("search issues", 0, "[]")
    m3.on("issue list", 0, "[]")
    let res3 = runPipe(state, dir, ledgerDir, false, m3)
    check res3.isOk
    check res3.get()[0].status == ursDuplicate
    check res3.get()[0].issueNumber == 12
    check upstreamExitCode(res3.get()) == 0
    check m3.calls.findIt(it.contains("issue view 12")) >= 0
    check m3.calls.findIt(it.contains("issue create")) < 0
  test "structured issue identity survives BLOCKED transitions and is consumed on recovery":
    let state = makeState("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    # Run 1: fresh create -> SUBMITTED #12.
    let res1 = runPipe(state, dir, ledgerDir, false, newHappyMock())
    check res1.isOk
    check res1.get()[0].status == ursSubmitted
    # Run 2: issues get disabled -> BLOCKED(410); the receipt must keep the
    # structured issue identity across the transition.
    let m2 = MockGh()
    m2.on("auth status", 0, "ok")
    m2.on("repos/'status-im/nim-libp2p'", 0,
      """{"full_name": "iftech/nim-libp2p", "has_issues": false}""")
    let res2 = runPipe(state, dir, ledgerDir, false, m2)
    check res2.isOk
    check res2.get()[0].status == ursBlocked
    let mid = loadReceipt(joinPath(ledgerDir, expectedFindingKey() & ".json"))
    check mid.isOk and mid.get().isSome
    let blockedReceipt = mid.get().get()
    check blockedReceipt.status == ursBlocked
    check blockedReceipt.issueNumber == 12
    check blockedReceipt.issueUrl ==
      "https://github.com/iftech/nim-libp2p/issues/12"
    check blockedReceipt.submittedAt == "2026-10-31T12:00:00Z"
    # Run 3: issues re-enabled — the carried identity is re-queried directly
    # and linked; no regeneration over the live issue #12.
    let m3 = MockGh()
    m3.on("auth status", 0, "ok")
    m3.on("repos/'status-im/nim-libp2p'", 0, REPO_API_OK)
    m3.on("issue view 12", 0, $(%*{"number": 12,
      "url": "https://github.com/iftech/nim-libp2p/issues/12", "state": "open"}))
    m3.on("search issues", 0, "[]")
    m3.on("issue list", 0, "[]")
    let res3 = runPipe(state, dir, ledgerDir, false, m3)
    check res3.isOk
    check res3.get()[0].status == ursDuplicate
    check res3.get()[0].issueNumber == 12
    check upstreamExitCode(res3.get()) == 0
    check m3.calls.findIt(it.contains("issue create")) < 0
  test "FAILED(remote-unverifiable) -> RR -> DUPLICATE recovery chain, never a re-create":
    let state = makeState("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    # Run 1: create succeeds (URL printed) but remote verification fails
    # -> FAILED(remote-state-unverifiable) with the candidate recorded.
    let m1 = MockGh()
    m1.on("auth status", 0, "ok")
    m1.on("repos/'status-im/nim-libp2p'", 0, REPO_API_OK)
    m1.on("search issues", 0, "[]")
    m1.on("issue list", 0, "[]")
    m1.on("ISSUE_TEMPLATE", 1, "gh: Not Found (HTTP 404)")
    m1.on("issue create", 0, CREATE_URL_OUTPUT)
    m1.on("issue view 12", 1, "gh: server error (HTTP 502)")
    let res1 = runPipe(state, dir, ledgerDir, false, m1)
    check res1.isOk
    check res1.get()[0].status == ursFailed
    check res1.get()[0].blockedReason == failedRemoteUnverifiable
    let seeded = loadReceipt(joinPath(ledgerDir, expectedFindingKey() & ".json"))
    check seeded.isOk and seeded.get().isSome
    var hasCandidate = false
    for a in seeded.get().get().attempts:
      if a.candidateUrl.len > 0:
        hasCandidate = true
    check hasCandidate
    # Run 2: the candidate stays unverifiable and the search finds nothing
    # -> RECONCILIATION_REQUIRED (never a re-create over the FAILED record).
    let m2 = MockGh()
    m2.on("auth status", 0, "ok")
    m2.on("repos/'status-im/nim-libp2p'", 0, REPO_API_OK)
    m2.on("issue view 12", 1, "gh: server error (HTTP 502)")
    m2.on("search issues", 0, "[]")
    m2.on("issue list", 0, "[]")
    let res2 = runPipe(state, dir, ledgerDir, false, m2)
    check res2.isOk
    check res2.get()[0].status == ursReconciliationRequired
    check upstreamExitCode(res2.get()) == 1
    check m2.calls.findIt(it.contains("issue create")) < 0
    let mid = loadReceipt(joinPath(ledgerDir, expectedFindingKey() & ".json"))
    check mid.isOk and mid.get().isSome
    check mid.get().get().status == ursReconciliationRequired
    var keptCandidate = false
    for a in mid.get().get().attempts:
      if a.candidateUrl.len > 0:
        keptCandidate = true
    check keptCandidate
    # Run 3: the candidate re-query finally confirms the issue -> DUPLICATE.
    let m3 = MockGh()
    m3.on("auth status", 0, "ok")
    m3.on("repos/'status-im/nim-libp2p'", 0, REPO_API_OK)
    m3.on("issue view 12", 0, $(%*{"number": 12,
      "url": "https://github.com/iftech/nim-libp2p/issues/12",
      "state": "open", "body": "findingKey: " & expectedFindingKey() & "\n"}))
    let res3 = runPipe(state, dir, ledgerDir, false, m3)
    check res3.isOk
    check res3.get()[0].status == ursDuplicate
    check res3.get()[0].issueNumber == 12
    check upstreamExitCode(res3.get()) == 0
    check m3.calls.findIt(it.contains("issue create")) < 0
  test "RR with a candidate: issues-disabled never demotes it — a later empty re-query still forbids regeneration":
    let state = makeState("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    # Run 1: timed-out create WITH a printed URL -> RR + candidate recorded.
    let m1 = MockGh()
    m1.on("auth status", 0, "ok")
    m1.on("repos/'status-im/nim-libp2p'", 0, REPO_API_OK)
    m1.on("search issues", 0, "[]")
    m1.on("issue list", 0, "[]")
    m1.on("ISSUE_TEMPLATE", 1, "gh: Not Found (HTTP 404)")
    m1.on("issue create", 28,
      "gh: request timed out\nhttps://github.com/iftech/nim-libp2p/issues/77\n")
    let res1 = runPipe(state, dir, ledgerDir, false, m1)
    check res1.isOk
    check res1.get()[0].status == ursReconciliationRequired
    # Run 2: issues get disabled — the RR state (and its candidate recovery
    # input) must survive; BLOCKED here would license a later regeneration.
    let m2 = MockGh()
    m2.on("auth status", 0, "ok")
    m2.on("repos/'status-im/nim-libp2p'", 0,
      """{"full_name": "iftech/nim-libp2p", "has_issues": false}""")
    let res2 = runPipe(state, dir, ledgerDir, false, m2)
    check res2.isOk
    check res2.get()[0].status == ursReconciliationRequired
    check res2.get()[0].detail.contains("issues are disabled")
    let mid = loadReceipt(joinPath(ledgerDir, expectedFindingKey() & ".json"))
    check mid.isOk and mid.get().isSome
    check mid.get().get().status == ursReconciliationRequired
    var keptCandidate = false
    for a in mid.get().get().attempts:
      if a.candidateUrl == "https://github.com/iftech/nim-libp2p/issues/77":
        keptCandidate = true
    check keptCandidate
    # Run 3: issues re-enabled, candidate still unconfirmed, search empty
    # -> RR stays; no regeneration.
    let m3 = MockGh()
    m3.on("auth status", 0, "ok")
    m3.on("repos/'status-im/nim-libp2p'", 0, REPO_API_OK)
    m3.on("issue view 77", 1, "gh: Not Found (HTTP 404)")
    m3.on("search issues", 0, "[]")
    m3.on("issue list", 0, "[]")
    let res3 = runPipe(state, dir, ledgerDir, false, m3)
    check res3.isOk
    check res3.get()[0].status == ursReconciliationRequired
    check upstreamExitCode(res3.get()) == 1
    check m3.calls.findIt(it.contains("issue create")) < 0
  test "RR without a candidate: issues-disabled never demotes it — a later empty re-query still forbids regeneration":
    let state = makeState("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    # Run 1: timed-out create with NO URL -> RR, nothing to recover from.
    let m1 = MockGh()
    m1.on("auth status", 0, "ok")
    m1.on("repos/'status-im/nim-libp2p'", 0, REPO_API_OK)
    m1.on("search issues", 0, "[]")
    m1.on("issue list", 0, "[]")
    m1.on("ISSUE_TEMPLATE", 1, "gh: Not Found (HTTP 404)")
    m1.on("issue create", 28, "gh: request timed out")
    let res1 = runPipe(state, dir, ledgerDir, false, m1)
    check res1.isOk
    check res1.get()[0].status == ursReconciliationRequired
    # Run 2: issues get disabled — RR must survive the transition.
    let m2 = MockGh()
    m2.on("auth status", 0, "ok")
    m2.on("repos/'status-im/nim-libp2p'", 0,
      """{"full_name": "iftech/nim-libp2p", "has_issues": false}""")
    let res2 = runPipe(state, dir, ledgerDir, false, m2)
    check res2.isOk
    check res2.get()[0].status == ursReconciliationRequired
    check res2.get()[0].detail.contains("issues are disabled")
    let mid = loadReceipt(joinPath(ledgerDir, expectedFindingKey() & ".json"))
    check mid.isOk and mid.get().isSome
    check mid.get().get().status == ursReconciliationRequired
    # Run 3: issues re-enabled, the re-query finds nothing -> RR stays.
    let m3 = MockGh()
    m3.on("auth status", 0, "ok")
    m3.on("repos/'status-im/nim-libp2p'", 0, REPO_API_OK)
    m3.on("search issues", 0, "[]")
    m3.on("issue list", 0, "[]")
    let res3 = runPipe(state, dir, ledgerDir, false, m3)
    check res3.isOk
    check res3.get()[0].status == ursReconciliationRequired
    check upstreamExitCode(res3.get()) == 1
    check m3.calls.findIt(it.contains("issue create")) < 0
  test "a READY create-intent left by a dead process never regenerates on an empty re-query; a landed create is recovered":
    let state = makeState("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    let fk = expectedFindingKey()
    # The crash window: the READY intent the pipeline persists immediately
    # before `gh issue create`. Dry-run never persists READY and no other
    # transition does, so a READY ledger receipt means "the create may have
    # run" — the creation state is unresolved.
    let crashed = UpstreamReceipt(
      schemaVersion: upstreamReceiptSchemaVersion,
      findingKey: fk,
      status: ursReady,
      attempts: @[UpstreamAttempt(ts: "2026-10-30T00:00:00Z",
        phase: "fetch-issue-template", outcome: "exit=1 gh: Not Found (HTTP 404)")])
    check saveReceiptAtomic(crashed, joinPath(ledgerDir, fk & ".json")).isOk
    # Run 1: the re-query finds nothing -> READY converts to RR; no create.
    let m1 = MockGh()
    m1.on("auth status", 0, "ok")
    m1.on("repos/'status-im/nim-libp2p'", 0, REPO_API_OK)
    m1.on("search issues", 0, "[]")
    m1.on("issue list", 0, "[]")
    let res1 = runPipe(state, dir, ledgerDir, false, m1)
    check res1.isOk
    check res1.get()[0].status == ursReconciliationRequired
    check upstreamExitCode(res1.get()) == 1
    check m1.calls.findIt(it.contains("issue create")) < 0
    let mid = loadReceipt(joinPath(ledgerDir, fk & ".json"))
    check mid.isOk and mid.get().isSome
    check mid.get().get().status == ursReconciliationRequired
    # Run 2: still nothing -> RR stays.
    let m2 = MockGh()
    m2.on("auth status", 0, "ok")
    m2.on("repos/'status-im/nim-libp2p'", 0, REPO_API_OK)
    m2.on("search issues", 0, "[]")
    m2.on("issue list", 0, "[]")
    let res2 = runPipe(state, dir, ledgerDir, false, m2)
    check res2.isOk
    check res2.get()[0].status == ursReconciliationRequired
    check m2.calls.findIt(it.contains("issue create")) < 0
    # Run 3: the crashed create actually landed and the index caught up ->
    # recovered as DUPLICATE; still never a re-create.
    let m3 = MockGh()
    m3.on("auth status", 0, "ok")
    m3.on("repos/'status-im/nim-libp2p'", 0, REPO_API_OK)
    m3.on("search issues", 0,
      $(%*[{"number": 88, "url": "https://github.com/iftech/nim-libp2p/issues/88"}]))
    m3.on("issue view 88", 0, $(%*{"number": 88,
      "url": "https://github.com/iftech/nim-libp2p/issues/88",
      "state": "open", "body": "findingKey: " & fk & "\n"}))
    let res3 = runPipe(state, dir, ledgerDir, false, m3)
    check res3.isOk
    check res3.get()[0].status == ursDuplicate
    check res3.get()[0].issueNumber == 88
    check upstreamExitCode(res3.get()) == 0
    check m3.calls.findIt(it.contains("issue create")) < 0
  test "dry-run over a READY create-intent previews RR and leaves the intent untouched":
    let state = makeState("BUG_SUSPECTED", "DISPROVED")
    let (dir, ledgerDir) = makeFixture(state)
    let fk = expectedFindingKey()
    let crashed = UpstreamReceipt(
      schemaVersion: upstreamReceiptSchemaVersion,
      findingKey: fk,
      status: ursReady)
    check saveReceiptAtomic(crashed, joinPath(ledgerDir, fk & ".json")).isOk
    let m = MockGh()
    m.on("auth status", 0, "ok")
    m.on("repos/'status-im/nim-libp2p'", 0, REPO_API_OK)
    m.on("search issues", 0, "[]")
    m.on("issue list", 0, "[]")
    let res = runPipe(state, dir, ledgerDir, true, m)
    check res.isOk
    check res.get()[0].status == ursReconciliationRequired
    check res.get()[0].detail.contains("not persisted")
    check fileCount(ledgerDir) == 1
    let after = loadReceipt(joinPath(ledgerDir, fk & ".json"))
    check after.isOk and after.get().isSome
    check after.get().get().status == ursReady

suite "spec overlay loading (I/O, fail-closed)":
  test "the committed overlay loads; traversal and absence fail":
    let (dir, _) = makeFixture(makeState("BUG_SUSPECTED", "DISPROVED"))
    check loadSpecOverlay(dir, "nim_libp2p_bytesview_slice.json").isOk
    check loadSpecOverlay(dir, "../secrets.json").isErr
    check loadSpecOverlay(dir, "missing.json").isErr
