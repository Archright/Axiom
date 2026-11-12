import core/trusted/layer_declaration
import core/trusted/axiom_pragmas_lite
axiomLayer "tools"

import std/[json, os, strutils, parseopt]

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
