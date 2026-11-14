import core/trusted/layer_declaration
import core/trusted/axiom_pragmas_lite
axiomLayer "tools"

import std/[json, os, strutils, parseopt, osproc]

{.push raises: [].}

import core/crypto/hash_kernel
import core/deterministic_cas_key
import core/results

## check_evidence_id_contract.nim — B-owned independent evidenceId contract check.
##
## The GO-critical lane (go-critical-lane job, admission-check.yml) executes
## this tool AGAINST the overlaid candidate (M) source tree. It is the lane's
## independent recomputation authority for the CanonicalLeanEvidence evidenceId
## contract (src/verification/obligation/kernel_acceptance_authority.nim,
## `evidenceId`):
##
##   legacy : evidenceId = sha256(c1|c2|c3|c4|c5|c6)
##   strict : evidenceId = sha256(c1|c2|c3|c4|c5|c6|completenessBindingDigest)
##
##   c1 obligationId · c2 propositionHash · c3 leanSourceHash · c4 kaaDigest ·
##   c5 toolchainFingerprint · c6 executionContractDigest
##
## Independence: the preimage here is THIS file's own construction — the
## checker never calls the candidate's `evidenceId()` to bless an artifact and
## never trusts a candidate-provided evidenceId. The claimed value is only the
## COMPARISON TARGET: components arrive from a contract artifact (`--artifact`)
## or from the lane's probe test (tests/unit/test_evidence_id_contract_probe.nim,
## which executes the REAL canonical chain through the overlaid src/ and hands
## this checker the raw components — observation, not authority); internal hash
## bindings are re-verified, and the recomputed digest must equal the claimed
## one or the run FAILs.
##
## Layer boundary: this file imports ONLY std + core/ — the tools layer
## forbids verification/ imports, and an independent checker must not link
## the candidate-owned implementation anyway.
##
## Modes:
##   (no args)          --self-check: the embedded fixture battery (positive
##                      legacy + strict, and every rejection class: missing
##                      field, non-64-hex, double-hash drift, strict context
##                      mismatch). The lane's `make test-fast-one` invocation
##                      runs this mode — EXECUTED always, no CAS surface.
##   --artifact <file>  recompute from one contract artifact JSON.
##
## Exit: 0 = contract PASS · 1 = contract FAIL · 2 = usage error.
## Fail-closed: a missing/unparsable/unhexed component is a FAIL, never a skip.

const EvidenceIdContractFields* = [
  "obligationId",
  "propositionHash",
  "leanSourceHash",
  "kaaDigest",
  "toolchainFingerprint",
  "executionContractDigest"]

const CompletenessContractStrictV1* = "strict-v1"
  ## This checker's own normative declaration of the strict-contract wire
  ## marker — deliberately NOT imported from the candidate-owned src/ (tools
  ## may not import verification/, and an independent checker owns the wire
  ## literals it validates against).

type EvidenceIdComponents* = object
  ## The raw CLE component set, in preimage order (c1..c6) plus the strict
  ## binding members (empty digest = legacy representation) and the claimed
  ## (candidate-provided) evidenceId — comparison target, never trusted.
  obligationId*: string
  propositionHash*: string
  leanSourceHash*: string
  kaaDigest*: string
  toolchainFingerprint*: string
  executionContractDigest*: string
  completenessBindingDigest*: string
  completenessContract*: string
  claimedEvidenceId*: string

func fieldValues*(c: EvidenceIdComponents): array[6, string] {.raises: [].} =
  [c.obligationId, c.propositionHash, c.leanSourceHash, c.kaaDigest,
   c.toolchainFingerprint, c.executionContractDigest]

func isHex64*(s: string): bool {.raises: [].} =
  if s.len != 64:
    return false
  for ch in s:
    if ch notin {'0'..'9', 'a'..'f'}:
      return false
  true

# ---------------------------------------------------------------------------
# THE normative formula — this file's own preimage, byte-exact
# ---------------------------------------------------------------------------

func legacyPreimage*(c: EvidenceIdComponents): string {.raises: [].} =
  ## c1|c2|c3|c4|c5|c6 — the exact separator and order of the normative
  ## formula (kernel_acceptance_authority.evidenceId).
  c.obligationId & "|" & c.propositionHash & "|" & c.leanSourceHash & "|" &
    c.kaaDigest & "|" & c.toolchainFingerprint & "|" & c.executionContractDigest

func recomputeEvidenceId*(c: EvidenceIdComponents): string {.raises: [].} =
  ## H(c1|…|c6) legacy; H(c1|…|c6|completenessBindingDigest) strict — the
  ## strict digest is appended to the SAME preimage (never to the legacy
  ## hash: the double-hash drift this check exists to catch independently).
  if c.completenessBindingDigest.len > 0:
    sha256Hex(legacyPreimage(c) & "|" & c.completenessBindingDigest)
  else:
    sha256Hex(legacyPreimage(c))

# ---------------------------------------------------------------------------
# Structural validation (fail-closed)
# ---------------------------------------------------------------------------

func validateComponents*(c: EvidenceIdComponents): string {.raises: [].} =
  ## "" = structurally valid; otherwise the rejection reason.
  ## Missing/empty and non-64-lowercase-hex components are rejected — an
  ## identity can never rest on an unmeasured or malformed field.
  for i, name in EvidenceIdContractFields:
    let v = fieldValues(c)[i]
    if v.len == 0:
      return "missing required component '" & name & "' (fail-closed)"
    if not isHex64(v):
      return "component '" & name & "' is not 64 lowercase hex (fail-closed)"
  if c.completenessBindingDigest.len > 0 and not isHex64(c.completenessBindingDigest):
    return "completenessBindingDigest is not 64 lowercase hex (fail-closed)"
  ""

func validateStrictContext*(c: EvidenceIdComponents): string {.raises: [].} =
  ## The strict artifact's digest↔context binding: a strict-contract
  ## artifact (completenessContract == "strict-v1") MUST carry a non-empty
  ## completenessBindingDigest, and a carried digest MUST be strict-contract
  ## context. Either half missing = a mismatched digest/context artifact.
  if c.completenessContract == CompletenessContractStrictV1 and
      c.completenessBindingDigest.len == 0:
    return "strict-contract artifact carries no completenessBindingDigest " &
      "(mismatched digest/context, fail-closed)"
  if c.completenessContract.len == 0 and c.completenessBindingDigest.len > 0:
    return "completenessBindingDigest present but completenessContract is empty " &
      "(mismatched digest/context, fail-closed)"
  if c.completenessContract.len > 0 and c.completenessContract != CompletenessContractStrictV1:
    return "unknown completenessContract '" & c.completenessContract &
      "' (fail-closed)"
  ""

func checkContract*(c: EvidenceIdComponents): string {.raises: [].} =
  ## The full contract check (structure + strict context + recompute). ""
  ## = PASS; otherwise the rejection reason. The claimed evidenceId is
  ## REQUIRED and compared against the recomputed value — it is never
  ## substituted, defaulted, or trusted.
  let structural = validateComponents(c)
  if structural.len > 0:
    return structural
  let context = validateStrictContext(c)
  if context.len > 0:
    return context
  if c.claimedEvidenceId.len == 0:
    return "missing claimed evidenceId (fail-closed)"
  if not isHex64(c.claimedEvidenceId):
    return "claimed evidenceId is not 64 lowercase hex (fail-closed)"
  let recomputed = recomputeEvidenceId(c)
  if recomputed != c.claimedEvidenceId:
    return "evidenceId MISMATCH — recomputed H(c1..c6" &
      (if c.completenessBindingDigest.len > 0: "|completenessBindingDigest" else: "") &
      ")=" & recomputed[0 ..< 16] & "… != claimed " & c.claimedEvidenceId[0 ..< 16] &
      "… (the candidate-provided value is not the normative digest, fail-closed)"
  ""

# ---------------------------------------------------------------------------
# Artifact parsing
# ---------------------------------------------------------------------------

proc componentsFromJson*(node: JsonNode): Result[EvidenceIdComponents, string] {.
    raises: [].} =
  ## Parse the contract artifact: all six components are REQUIRED keys (a
  ## missing key is a rejection — absent ≠ empty), the strict members and the
  ## claimed evidenceId are read when present.
  if node.isNil or node.kind != JObject:
    return err("artifact must be a JSON object")
  for name in EvidenceIdContractFields:
    let f = node{name}
    if f.isNil:
      return err("artifact missing required field '" & name & "' (fail-closed)")
    if f.kind != JString:
      return err("artifact field '" & name & "' must be a string (fail-closed)")
  var c = EvidenceIdComponents()
  c.obligationId = node{"obligationId"}.getStr("")
  c.propositionHash = node{"propositionHash"}.getStr("")
  c.leanSourceHash = node{"leanSourceHash"}.getStr("")
  c.kaaDigest = node{"kaaDigest"}.getStr("")
  c.toolchainFingerprint = node{"toolchainFingerprint"}.getStr("")
  c.executionContractDigest = node{"executionContractDigest"}.getStr("")
  c.completenessBindingDigest = node{"completenessBindingDigest"}.getStr("")
  c.completenessContract = node{"completenessContract"}.getStr("")
  c.claimedEvidenceId = node{"evidenceId"}.getStr("")
  ok(c)

proc checkArtifactFile*(path: string): Result[string, string] {.raises: [].} =
  ## Check one artifact file; ok(report) on contract PASS, err(reason) on FAIL.
  if not fileExists(path):
    return err("artifact file not found (fail-closed): " & path)
  var text = ""
  try:
    text = readFile(path)
  except CatchableError as e:
    return err("artifact unreadable (fail-closed): " & path & ": " & e.msg)
  var node: JsonNode
  try:
    node = parseJson(text)
  except CatchableError as e:
    return err("artifact unparsable (fail-closed): " & path & ": " & e.msg)
  let parsed = componentsFromJson(node)
  if parsed.isErr:
    return err(parsed.error)
  let verdict = checkContract(parsed.get)
  if verdict.len > 0:
    return err(verdict)
  ok("PASS " & path & " evidenceId=" & parsed.get.claimedEvidenceId[0 ..< 16] &
    "… formula=" & EvidenceIdContractVersion &
    (if parsed.get.completenessBindingDigest.len > 0: " strict" else: " legacy"))

# ---------------------------------------------------------------------------
# Verdict-input integrity — the candidate never supplies the measuring stick
# ---------------------------------------------------------------------------
#
# The lane overlays the candidate's OWN copies of the GO-critical test files
# and the tests/golden/ fixtures onto B's workspace (admission-check.yml, step
# "Overlay M src/+GO-critical tests onto the B workspace"). Every executor
# surface beside them — Makefile, config.nims, tests/config.nims,
# config/effects.nims, nimble.lock, tools/, config/ — stays B's and is
# byte-guarded by that same step. The overlay inputs themselves are NOT
# guarded: a candidate can delete a `check` line and the lane still reports
# PASS. The B-owned attest payload validator pins the 17/14/[3,2,1,11]
# OUTCOME shape, not the assertions that establish it, and repository_surface
# judges these paths PRODUCT (MODIFY=PASS).
#
# This guard closes that. Every tracked file under tests/ that differs from
# B's blob — modified, deleted, renamed, or newly added — must be pinned HERE
# by its exact git blob oid and must still carry at least the approved number
# of assertion sites. The pins live in this B-owned file, and the lane
# executes B's copy, so a candidate that edits them is invisible to the run
# that judges it: changing an approved test is a two-step policy landing
# (pin update first, test change second), never a self-service.
#
# Deliberately NOT sha256Hex: that primitive is imported from the overlaid
# candidate src/ (core/crypto/hash_kernel), so the judged tree would supply
# the judge's hash. Both sides of every comparison here are computed by git.

const VerdictInputRoot* = "tests"
const VerdictInputDivergedMarker* = "GO_TEST_BYTES_DIVERGED"
const VerdictInputReducedMarker* = "GO_TEST_OBLIGATIONS_REDUCED"
const VerdictInputPinMalformedMarker* = "GO_TEST_PIN_MALFORMED"

type PinnedVerdictInput* = object
  ## One approved verdict input: the exact bytes (git blob oid) and the
  ## weakening floor (assertion sites) that approval covered.
  path*: string
  blobOid*: string
  obligations*: int

const PinnedVerdictInputs* = [
  PinnedVerdictInput(path: "tests/unit/test_s1a_lean_golden.nim",
    blobOid: "377e5c641386218ce2138ed4bcfa7ab11635535d", obligations: 95),
  PinnedVerdictInput(path: "tests/unit/proof_integrity_test.nim",
    blobOid: "8a5a7f142134050a7205144c6139672e70c106a3", obligations: 17),
  PinnedVerdictInput(path: "tests/unit/test_d2_golden.nim",
    blobOid: "ba294f29118f21d84c2609f3170a538888ce27ac", obligations: 62),
  PinnedVerdictInput(path: "tests/unit/test_d2_persist.nim",
    blobOid: "6eba34131d910d052a08b76bc2bd738ce510a9f1", obligations: 8)]
  ## The four GO-critical matrix tests (admission-check.yml:3429 lane 0,
  ## :3432 lane 1). `obligations` counts `check …`/`doAssert …` sites in the
  ## approved bytes.

func trimmedLeading(line: string): string {.raises: [].} =
  var i = 0
  while i < line.len and line[i] in {' ', '\t'}:
    inc i
  if i >= line.len: "" else: line[i .. ^1]

func obligationCount*(content: string): int {.raises: [].} =
  ## The weakening floor: `check …` / `doAssert …` sites, counted after
  ## leading whitespace. A ratchet against silent deletion — never a proof of
  ## strength. Lowering a pin's count is an explicit operator-merged act.
  var n = 0
  for line in content.splitLines():
    let t = trimmedLeading(line)
    if t.startsWith("check ") or t.startsWith("doAssert "):
      inc n
  n

proc gitRun(args: openArray[string]): Result[string, string] {.
    raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  ## Run git and capture stdout. Non-zero exit = err (never a silent skip).
  var cmd = "git"
  for a in args:
    cmd.add(' ')
    cmd.add(quoteShell(a))
  try:
    let r = execCmdEx(cmd, options = {poStdErrToStdOut, poUsePath, poEvalCommand})
    if r.exitCode != 0:
      return err("git " & args[0] & " exited " & $r.exitCode & ": " &
        r.output.strip())
    ok(r.output)
  except CatchableError as e:
    err("git " & args[0] & " could not run: " & e.msg)

func divergedPaths*(porcelainZ: string): seq[string] {.raises: [].} =
  ## `git status --porcelain -z` records are `XY <path>`; rename/copy records
  ## are followed by the source path record. BOTH paths are surfaced so a
  ## rename can never hide the deletion it performs.
  let records = porcelainZ.split('\0')
  var i = 0
  while i < records.len:
    let rec = records[i]
    inc i
    if rec.len < 4:
      continue
    let status = rec[0 .. 1]
    result.add(rec[3 .. ^1])
    if status[0] in {'R', 'C'} and i < records.len:
      result.add(records[i])
      inc i

func pinIndex(path: string): int {.raises: [].} =
  result = -1
  for i in 0 ..< PinnedVerdictInputs.len:
    if PinnedVerdictInputs[i].path == path:
      return i

proc verifyOnePinnedInput(path: string): Result[string, string] {.
    raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  ## One diverged path: deleted / unpinned / wrong bytes / pruned assertions.
  if not fileExists(path):
    return err(VerdictInputDivergedMarker & "(" & path &
      ") deleted — a verdict input was removed; the candidate may not delete " &
      "the measuring stick (fail-closed)")
  let idx = pinIndex(path)
  if idx < 0:
    return err(VerdictInputDivergedMarker & "(" & path &
      ") not pinned — the candidate changed a verdict input that carries no " &
      "approved pin (fail-closed)")
  let pin = PinnedVerdictInputs[idx]
  let oid = gitRun(["hash-object", "--no-filters", "--", path])
  if oid.isErr:
    return err(oid.error)
  let measured = oid.get.strip()
  if measured != pin.blobOid:
    return err(VerdictInputDivergedMarker & "(" & path & ") bytes=" &
      measured[0 ..< 12] & "… != approved pin=" & pin.blobOid[0 ..< 12] &
      "… — the candidate's bytes are not the approved bytes (fail-closed)")
  var content = ""
  try:
    content = readFile(path)
  except CatchableError as e:
    return err(VerdictInputDivergedMarker & "(" & path & ") unreadable: " & e.msg)
  let measuredObligations = obligationCount(content)
  if measuredObligations < pin.obligations:
    return err(VerdictInputReducedMarker & "(" & path & ") obligations=" &
      $measuredObligations & " < approved=" & $pin.obligations &
      " — the approved bytes were pruned (fail-closed)")
  ok("")

proc checkVerdictInputs*(): Result[string, string] {.
    raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  ## ok("") = inert (not a venue that executes the GO lane);
  ## ok(report) = armed and PASS; err(reason) = fail-closed.
  if getEnv("GITHUB_ACTIONS") != "true":
    return ok("")
  if getEnv("GITHUB_EVENT_NAME") notin ["merge_group", "workflow_call"]:
    return ok("")
  for pin in PinnedVerdictInputs:
    if not pin.path.startsWith(VerdictInputRoot & "/") or
        pin.blobOid.len != 40 or pin.obligations <= 0:
      return err(VerdictInputPinMalformedMarker & "(" & pin.path &
        ") malformed pin (fail-closed)")
  let status = gitRun(["status", "--porcelain", "-z", "--untracked-files=all",
    "--", VerdictInputRoot])
  if status.isErr:
    return err(status.error)
  let changed = divergedPaths(status.get)
  for path in changed:
    let verdict = verifyOnePinnedInput(path)
    if verdict.isErr:
      return err(verdict.error)
  ok("ARMED event=" & getEnv("GITHUB_EVENT_NAME") & " diverged=" &
    $changed.len & "/" & $PinnedVerdictInputs.len & " pins " & VerdictInputRoot & "/**")

# ---------------------------------------------------------------------------
# Self-check — the embedded fixture battery (the lane's make test-fast-one run)
# ---------------------------------------------------------------------------

proc hx(seed: string): string {.raises: [].} =
  ## A valid 64-lowercase-hex fixture component (deterministic per seed).
  sha256Hex("evidence-id-contract-fixture:" & seed)

proc badHex(): string {.raises: [].} =
  ## A 64-char NON-hex component (the rejection-class fixture).
  var s = ""
  for i in 1 .. 32:
    s.add("zz")
  s

proc legacyFixture(digest: string = ""; contract: string = ""; claimed: string = ""): EvidenceIdComponents =
  EvidenceIdComponents(
    obligationId: hx("c1"),
    propositionHash: hx("c2"),
    leanSourceHash: hx("c3"),
    kaaDigest: hx("c4"),
    toolchainFingerprint: hx("c5"),
    executionContractDigest: hx("c6"),
    completenessBindingDigest: digest,
    completenessContract: contract,
    claimedEvidenceId: claimed)

proc strictFixture(digest, contract, claimed: string): EvidenceIdComponents =
  EvidenceIdComponents(
    obligationId: hx("c1"),
    propositionHash: hx("c2"),
    leanSourceHash: hx("c3"),
    kaaDigest: hx("c4"),
    toolchainFingerprint: hx("c5"),
    executionContractDigest: hx("c6"),
    completenessBindingDigest: digest,
    completenessContract: contract,
    claimedEvidenceId: claimed)

proc runSelfCheck*(): int {.raises: [].} =
  ## The embedded battery: positive legacy + strict, and EVERY rejection
  ## class. Any unexpected outcome fails the battery (exit 1).
  var failures = 0
  template expectPass(name: string; body: untyped) =
    let v: string = body
    if v.len == 0:
      echo "  [PASS] " & name
    else:
      inc failures
      echo "  FAIL: " & name & " — " & v
  template expectFail(name: string; needle: string; body: untyped) =
    let v: string = body
    if v.len > 0 and (needle.len == 0 or v.contains(needle)):
      echo "  [PASS] " & name
    else:
      inc failures
      echo "  FAIL: " & name & " — expected rejection containing '" & needle &
        "', got '" & (if v.len == 0: "<PASS>" else: v) & "'"

  # Positive controls — the claimed value is the RECOMPUTED one.
  let legacy = legacyFixture()
  let legacyClaim = recomputeEvidenceId(legacy)
  expectPass("legacy artifact: H(c1|…|c6) accepted"):
    checkContract(legacyFixture(claimed = legacyClaim))
  let strictDigest = hx("strict")
  let strict = strictFixture(strictDigest, CompletenessContractStrictV1,
    recomputeEvidenceId(strictFixture(strictDigest,
      CompletenessContractStrictV1, "")))
  expectPass("strict artifact: H(c1|…|c6|completenessBindingDigest) accepted"):
    checkContract(strict)
  # The double-hash drift (the B-test defect this check is independent of):
  # hashing the legacy DIGEST instead of the preimage must be rejected.
  expectFail("strict double-hash drift rejected", "MISMATCH"):
    checkContract(strictFixture(strictDigest, CompletenessContractStrictV1,
      sha256Hex(legacyClaim & "|" & strictDigest)))
  # Missing field.
  var missing = legacyFixture(claimed = legacyClaim)
  missing.obligationId = ""
  expectFail("missing required component rejected", "missing required component"):
    checkContract(missing)
  # Non-64-hex.
  var unhexed = legacyFixture(claimed = legacyClaim)
  unhexed.kaaDigest = badHex()
  expectFail("non-64-hex component rejected", "not 64 lowercase hex"):
    checkContract(unhexed)
  expectFail("short claimed evidenceId rejected", "not 64 lowercase hex"):
    checkContract(legacyFixture(claimed = legacyClaim[0 ..< 63]))
  # Strict context mismatches.
  expectFail("strict-contract artifact without digest rejected", "mismatched digest/context"):
    checkContract(legacyFixture(contract = CompletenessContractStrictV1,
      claimed = legacyClaim))
  expectFail("digest without strict contract rejected", "mismatched digest/context"):
    checkContract(legacyFixture(digest = strictDigest, claimed = legacyClaim))
  expectFail("unknown completenessContract rejected", "unknown completenessContract"):
    checkContract(legacyFixture(digest = strictDigest, contract = "strict-v2",
      claimed = legacyClaim))
  # Untrusted claimed value: the legacy digest claimed on a STRICT artifact
  # must never pass.
  expectFail("legacy digest claimed on strict artifact rejected", "MISMATCH"):
    checkContract(strictFixture(strictDigest, CompletenessContractStrictV1,
      legacyClaim))
  # Empty claimed evidenceId.
  expectFail("missing claimed evidenceId rejected", "missing claimed evidenceId"):
    checkContract(legacyFixture())

  echo "[evidence-id-contract] self-check " &
    (if failures == 0: "PASSED — " else: "FAILED — ") & "contract " &
    EvidenceIdContractVersion
  if failures == 0: 0 else: 1

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

proc usage(): int =
  echo "usage: check_evidence_id_contract [--self-check | --artifact <file.json>]"
  echo "  (no args) = --self-check"
  2

proc main(): int {.raises: [CatchableError, OSError, Exception],
    axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  # Verdict-input integrity runs FIRST: before any compile of the candidate
  # chain, and long before the GO-critical tests this checker's caller runs
  # next (the lane's step order is overlay → this check → GO tests).
  let verdictInputs = checkVerdictInputs()
  if verdictInputs.isErr:
    echo "[verdict-inputs] FAIL — " & verdictInputs.error
    return 1
  if verdictInputs.get.len > 0:
    echo "[verdict-inputs] " & verdictInputs.get
  var mode = "self-check"
  var artifact = ""
  var p = initOptParser()
  for kind, key, val in p.getopt():
    case kind
    of cmdLongOption:
      case key
      of "self-check": mode = "self-check"
      of "artifact":
        mode = "artifact"
        artifact = val
      else:
        return usage()
    else:
      return usage()
  case mode
  of "self-check":
    runSelfCheck()
  of "artifact":
    if artifact.len == 0:
      echo "[evidence-id-contract] --artifact requires a file path"
      return usage()
    let r = checkArtifactFile(artifact)
    if r.isOk:
      echo "[evidence-id-contract] " & r.get
      0
    else:
      echo "[evidence-id-contract] FAIL — " & r.error
      1
  else:
    usage()

when isMainModule:
  quit(main())
{.pop.}
