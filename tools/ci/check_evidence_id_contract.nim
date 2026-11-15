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
##                      mismatch; plus the verdict-input judgment battery).
##                      The lane's `make test-fast-one` invocation runs this
##                      mode — EXECUTED always, no CAS surface.
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
# This guard closes that with an APPROVAL TABLE read from B. The judgment
# inputs are exactly the paths the lane executes as M's bytes — the four
# matrix tests plus the top-level tests/golden/*.nim fixtures (the overlay's
# non-recursive glob, nothing else). Each path's blob is resolved in BOTH git
# trees: B = the workspace checkout's HEAD (the overlay mutates only the
# working tree, HEAD stays B), M = the `_candidate` checkout's HEAD. A path
# with identical blobs passes; a differing blob passes only when M's blob is
# in that path's APPROVED blob set; a path only in M (addition) needs its
# blob approved; a path only in B (deletion) always FAILs — a deletion is a
# verdict-input change even though the overlay would silently keep B's bytes
# and run them.
#
# The table lives at data/policy/go_critical_input_approvals.json: PRODUCT
# class (no repository_surface registration needed) and outside the
# EvidenceKey PolicyDigestInputPaths five-file set, so adding it rotates no
# pin and no evidence key. It is read from B's HEAD git object — never the
# working tree, never the candidate tree — and CODEOWNERS routes
# /data/policy/ to @Archright/architect.
#
# Authority structure: the lane executes B's copy of this checker against
# B's table, so a PR that changes a test AND its approval in one push is
# judged by the PREVIOUS generation's table and FAILs its own merge-group
# run — self-approval is structurally impossible. A legitimate change is a
# staged landing: (A) register the new blob alongside the old → (B) change
# the test bytes → (C) retire the old blob. Each step passes under the
# previous generation's table.
#
# Deliberately NOT sha256Hex: that primitive is imported from the overlaid
# candidate src/ (core/crypto/hash_kernel), so the judged tree would supply
# the judge's hash. Both sides of every comparison here are computed by git.

const GoCriticalApprovalTablePath* = "data/policy/go_critical_input_approvals.json"
  ## B-owned approval table (CODEOWNERS /data/policy/ → @Archright/architect).
  ## Read from B's HEAD git object, never from the candidate or the overlay.
const GoCriticalApprovalSchema* = "go-critical-input-approvals/v1"
  ## The exact schema string this checker enforces. Anything else is
  ## fail-closed: a table revision must rename itself, never silently
  ## extend under the old schema marker.
const GoTestHashUnapprovedMarker* = "GO_TEST_HASH_UNAPPROVED"
  ## The unique failure code for every judgment-input violation: unapproved
  ## modification, unapproved addition, deletion.
const GoTestTableMalformedMarker* = "GO_TEST_TABLE_MALFORMED"
  ## The failure code for a table that cannot serve as an authority at all
  ## (missing/unparsable/schema drift/out-of-scope entry/bad oid/duplicate
  ## path) and for unresolvable B/M git state. Fail-closed, never a skip.
const GoCriticalMatrixTests* = [
  "tests/unit/test_s1a_lean_golden.nim",
  "tests/unit/proof_integrity_test.nim",
  "tests/unit/test_d2_golden.nim",
  "tests/unit/test_d2_persist.nim"]
  ## The four GO-critical matrix tests (admission-check.yml `matrix.tests`,
  ## lane 0 / lane 1) — always in scope, required to exist as blobs in B.
const GoldenFixtureRoot* = "tests/golden"
  ## The overlay copies `_candidate/tests/golden/*.nim` — a NON-recursive
  ## top-level glob. The guard's golden scope is exactly that set.
const CandidateCheckoutDir* = "_candidate"
  ## The lane's data-only candidate checkout ("[lane] Checkout candidate =
  ## M"); its HEAD is the candidate M.

type ApprovalEntry* = object
  ## One path's approved blob set: the exact git blob oids the CANDIDATE may
  ## carry for that judgment input. Multiple oids = the staged-landing window
  ## (old and new registered side by side). An empty set pins the path to
  ## B's bytes (any divergence FAILs).
  path*: string
  approvedBlobs*: seq[string]

type TreeBlob* = object
  ## One `git ls-tree` blob entry (tree/submodule entries are not judgment
  ## inputs and never appear here).
  path*: string
  oid*: string

func isHex40*(s: string): bool {.raises: [].} =
  ## A git blob oid as this table accepts it: 40 lowercase hex.
  if s.len != 40:
    return false
  for ch in s:
    if ch notin {'0'..'9', 'a'..'f'}:
      return false
  true

func isMatrixTestPath(path: string): bool {.raises: [].} =
  for t in GoCriticalMatrixTests:
    if path == t:
      return true
  false

func isGoldenFixturePath*(path: string): bool {.raises: [].} =
  ## `tests/golden/<name>.nim` — top level only (no further '/'), mirroring
  ## the overlay's non-recursive glob. Subdirectories and non-.nim files are
  ## not overlaid (B's bytes run for them), so they are out of scope.
  if not path.startsWith(GoldenFixtureRoot & "/"):
    return false
  let name = path[GoldenFixtureRoot.len + 1 .. ^1]
  if name.len == 0 or name.contains('/'):
    return false
  name.endsWith(".nim")

func inApprovalScope*(path: string): bool {.raises: [].} =
  ## The only paths a table entry may govern: the matrix tests and the
  ## top-level golden fixtures. Anything else in the table is malformed.
  isMatrixTestPath(path) or isGoldenFixturePath(path)

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

func parseLsTree*(text: string): Result[seq[TreeBlob], string] {.raises: [].} =
  ## Parse `git ls-tree` output (`mode SP type SP oid TAB path`, one record
  ## per line) keeping blob entries in tree order (git emits them sorted —
  ## the guard's target order is therefore deterministic). Subdirectory
  ## (tree) entries are skipped — the scope glob is top-level. A record that
  ## is not well-formed is an err: the guard never guesses at half-readable
  ## git state (fail-closed).
  var blobs: seq[TreeBlob] = @[]
  for line in text.splitLines():
    if line.len == 0:
      continue
    let tab = line.find('\t')
    if tab < 0:
      return err("malformed ls-tree record (no TAB): '" &
        line[0 ..< min(line.len, 60)] & "'")
    let meta = line[0 ..< tab]
    let path = line[tab + 1 .. ^1]
    let parts = meta.splitWhitespace(maxSplit = 2)
    if parts.len != 3 or parts[0].len == 0:
      return err("malformed ls-tree record (meta): '" & meta & "'")
    if parts[1] == "blob":
      if not isHex40(parts[2]):
        return err("malformed ls-tree record (oid): '" & parts[2] & "'")
      blobs.add(TreeBlob(path: path, oid: parts[2]))
    elif parts[1] == "tree":
      discard
    else:
      return err("malformed ls-tree record (type '" & parts[1] & "')")
  ok(blobs)

proc parseApprovalTable*(text: string): Result[seq[ApprovalEntry], string] {.
    raises: [].} =
  ## Parse and validate the approval table. Fail-closed: a missing key, a
  ## wrong type, a schema string other than GoCriticalApprovalSchema, an
  ## out-of-scope path, a non-40-hex oid, a duplicate oid within an entry, or
  ## a duplicate path across entries is an err — never a partial read, never
  ## a skip.
  var node: JsonNode
  try:
    node = parseJson(text)
  except CatchableError as e:
    return err("approval table unparsable (fail-closed): " & e.msg)
  if node.isNil or node.kind != JObject:
    return err("approval table must be a JSON object (fail-closed)")
  let schema = node{"schema"}
  if schema.isNil or schema.kind != JString or
      schema.getStr != GoCriticalApprovalSchema:
    return err("approval table schema must be '" & GoCriticalApprovalSchema &
      "' (fail-closed)")
  let desc = node{"description"}
  if desc.isNil or desc.kind != JString or desc.getStr.strip().len == 0:
    return err("approval table description must be a non-empty string (fail-closed)")
  let entriesNode = node{"entries"}
  if entriesNode.isNil or entriesNode.kind != JArray:
    return err("approval table 'entries' must be an array (fail-closed)")
  var entries: seq[ApprovalEntry] = @[]
  for e in entriesNode.elems:
    if e.isNil or e.kind != JObject:
      return err("approval table entry must be a JSON object (fail-closed)")
    let p = e{"path"}
    if p.isNil or p.kind != JString:
      return err("approval table entry 'path' must be a string (fail-closed)")
    if not inApprovalScope(p.getStr):
      return err("approval table entry path out of scope (matrix tests + " &
        "top-level " & GoldenFixtureRoot & "/*.nim only, fail-closed): " &
        p.getStr)
    let blobsNode = e{"approvedBlobs"}
    if blobsNode.isNil or blobsNode.kind != JArray:
      return err("approval table entry '" & p.getStr &
        "' requires an approvedBlobs array (fail-closed)")
    var approved: seq[string] = @[]
    for b in blobsNode.elems:
      if b.isNil or b.kind != JString or not isHex40(b.getStr):
        return err("approval table entry '" & p.getStr &
          "' carries a blob oid that is not 40 lowercase hex (fail-closed)")
      if b.getStr in approved:
        return err("approval table entry '" & p.getStr &
          "' lists a duplicate blob oid (fail-closed)")
      approved.add(b.getStr)
    for prior in entries:
      if prior.path == p.getStr:
        return err("approval table lists path twice (fail-closed): " & p.getStr)
    entries.add(ApprovalEntry(path: p.getStr, approvedBlobs: approved))
  ok(entries)

func approvalFor*(entries: seq[ApprovalEntry]; path: string): seq[string] {.
    raises: [].} =
  ## The approved blob set for one path. An absent entry is an EMPTY
  ## approval set — divergence then FAILs — never a bypass.
  for e in entries:
    if e.path == path:
      return e.approvedBlobs
  @[]

func blobAt*(blobs: seq[TreeBlob]; path: string): string {.raises: [].} =
  ## The oid for one path ("" when absent — an empty oid can never be an
  ## approved blob, so absence resolves to "unapproved" in the judge).
  for b in blobs:
    if b.path == path:
      return b.oid
  ""

func goldenTargets(bBlobs, mBlobs: seq[TreeBlob]): seq[string] {.raises: [].} =
  ## The golden-scope target set: the union of the two trees' top-level
  ## golden fixtures, B's (git-sorted) order first, then M-only additions.
  ## Deterministic; an M-only path is the addition case, a B-only path the
  ## deletion case — the judge sees both.
  for b in bBlobs:
    if isGoldenFixturePath(b.path) and b.path notin result:
      result.add(b.path)
  for m in mBlobs:
    if isGoldenFixturePath(m.path) and m.path notin result:
      result.add(m.path)

func judgeGoCriticalInput*(path, bBlob, mBlob: string;
    approved: seq[string]): string {.raises: [].} =
  ## The pure verdict for ONE judgment input. "" = PASS; otherwise the
  ## rejection reason, always carrying GoTestHashUnapprovedMarker.
  ##   bBlob / mBlob: the path's git blob oid in B's / M's tree ("" = absent)
  ## The arm order IS the policy:
  ##   deletion (M lost a B input) → FAIL; no approved set can permit it
  ##   identical blobs            → PASS (B's bytes need no approval)
  ##   M's blob approved          → PASS (the staged-landing window)
  ##   M-only (addition)          → covered by the approval arm above
  ##   anything else              → FAIL
  if mBlob.len == 0:
    return GoTestHashUnapprovedMarker & "(" & path & ") deleted in M — a " &
      "deletion is a verdict-input change; the overlay would silently keep " &
      "B's bytes, and the judgment must not pretend the input still exists " &
      "(fail-closed)"
  if mBlob == bBlob:
    return ""
  if mBlob in approved:
    return ""
  if bBlob.len == 0:
    return GoTestHashUnapprovedMarker & "(" & path & ") added in M with " &
      "bytes=" & mBlob[0 ..< 12] & "… — a new judgment input whose blob is " &
      "not in the approved set (fail-closed)"
  GoTestHashUnapprovedMarker & "(" & path & ") B=" & bBlob[0 ..< 12] & "… M=" &
    mBlob[0 ..< 12] & "… — the candidate's judgment-input bytes are not B's " &
    "and not an approved blob (fail-closed)"

proc checkGoCriticalInputs*(): Result[string, string] {.
    raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  ## ok("") = inert (not a venue that executes the GO lane);
  ## ok(report) = armed and PASS; err(reason) = fail-closed.
  if getEnv("GITHUB_ACTIONS") != "true":
    return ok("")
  if getEnv("GITHUB_EVENT_NAME") notin ["merge_group", "workflow_call"]:
    return ok("")
  # The approval table is read from B's HEAD GIT OBJECT — never the working
  # tree (which the overlay mutates) and never the candidate tree. B is the
  # judge; the judge's policy cannot be supplied by the judged.
  let tableText = gitRun(["show", "HEAD:" & GoCriticalApprovalTablePath])
  if tableText.isErr:
    return err(GoTestTableMalformedMarker & " cannot read " &
      GoCriticalApprovalTablePath & " from B's HEAD (fail-closed): " &
      tableText.error)
  let entries = parseApprovalTable(tableText.get)
  if entries.isErr:
    return err(GoTestTableMalformedMarker & " " & entries.error)
  # Resolve the two trees: the workspace (B) and the candidate checkout (M).
  let rootRun = gitRun(["rev-parse", "--show-toplevel"])
  if rootRun.isErr:
    return err(GoTestTableMalformedMarker &
      " workspace root unresolvable (fail-closed): " & rootRun.error)
  let root = rootRun.get.strip()
  let cand = root / CandidateCheckoutDir
  if not (dirExists(cand / ".git") or fileExists(cand / ".git")):
    return err(GoTestTableMalformedMarker &
      " candidate checkout missing (fail-closed): " & cand)
  let mShaRun = gitRun(["-C", cand, "rev-parse", "HEAD"])
  if mShaRun.isErr:
    return err(GoTestTableMalformedMarker &
      " candidate HEAD unresolvable (fail-closed): " & mShaRun.error)
  let mSha = mShaRun.get.strip()
  let bShaRun = gitRun(["rev-parse", "HEAD"])
  if bShaRun.isErr:
    return err(GoTestTableMalformedMarker &
      " B HEAD unresolvable (fail-closed): " & bShaRun.error)
  let bSha = bShaRun.get.strip()
  if not isHex40(bSha) or not isHex40(mSha):
    return err(GoTestTableMalformedMarker &
      " HEAD oid is not 40-hex (fail-closed): B='" & bSha & "' M='" & mSha & "'")
  # One ls-tree per side over the exact scope: the matrix tests plus the
  # golden top-level — the same path set the overlay copies.
  var pathspecs: seq[string] = @[]
  for t in GoCriticalMatrixTests:
    pathspecs.add(t)
  pathspecs.add(GoldenFixtureRoot & "/")
  let bTreeRun = gitRun(@["ls-tree", "HEAD", "--"] & pathspecs)
  if bTreeRun.isErr:
    return err(GoTestTableMalformedMarker & " B tree unreadable (fail-closed): " &
      bTreeRun.error)
  let mTreeRun = gitRun(@["-C", cand, "ls-tree", "HEAD", "--"] & pathspecs)
  if mTreeRun.isErr:
    return err(GoTestTableMalformedMarker & " M tree unreadable (fail-closed): " &
      mTreeRun.error)
  let bBlobs = parseLsTree(bTreeRun.get)
  if bBlobs.isErr:
    return err(GoTestTableMalformedMarker & " " & bBlobs.error)
  let mBlobs = parseLsTree(mTreeRun.get)
  if mBlobs.isErr:
    return err(GoTestTableMalformedMarker & " " & mBlobs.error)
  # The matrix tests are REQUIRED in B — a B that lost one is a malformed
  # judge state (the lane could not run the admission contract at all).
  for t in GoCriticalMatrixTests:
    if blobAt(bBlobs.get, t).len == 0:
      return err(GoTestTableMalformedMarker & "(" & t &
        ") missing from B's tree — the judge lost a matrix test (fail-closed)")
  # Judge every in-scope path: the matrix tests (fixed order), then the
  # golden union (B's git order, then M-only additions). Every violation is
  # reported, then the aggregate fails closed.
  var targets: seq[string] = @[]
  for t in GoCriticalMatrixTests:
    targets.add(t)
  for g in goldenTargets(bBlobs.get, mBlobs.get):
    targets.add(g)
  var violations: seq[string] = @[]
  var approvedDivergence = 0
  for t in targets:
    let bBlob = blobAt(bBlobs.get, t)
    let mBlob = blobAt(mBlobs.get, t)
    let verdict = judgeGoCriticalInput(t, bBlob, mBlob, approvalFor(entries.get, t))
    if verdict.len > 0:
      violations.add(verdict)
    elif bBlob != mBlob:
      inc approvedDivergence
  if violations.len > 0:
    return err(violations.join("; "))
  ok("ARMED event=" & getEnv("GITHUB_EVENT_NAME") & " B=" & bSha[0 ..< 12] &
    "… M=" & mSha[0 ..< 12] & "… judged=" & $targets.len &
    " approvedDivergence=" & $approvedDivergence & " entries=" &
    $entries.get.len & " table=" & GoCriticalApprovalTablePath)

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
  ## class — plus the verdict-input judgment battery (the approval-table
  ## guard's pure semantics: identical/approved/unapproved/addition/deletion
  ## and every malformed-table shape). Any unexpected outcome fails the
  ## battery (exit 1).
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

  # ── Verdict-input battery — the approval-table guard's judgment semantics
  # (the armed merge-group path composes these pure functions over the two
  # git trees; the cases below are the composition's building blocks, the
  # same four the tests/ci unit suite pins). ────────────────────────────
  proc tblVerdict(text: string): string {.raises: [].} =
    let r = parseApprovalTable(text)
    if r.isErr: r.error else: ""
  let pGo = "tests/unit/test_d2_golden.nim"
  let blobB = "ba294f29118f21d84c2609f3170a538888ce27ac"
  let blobM = "1111111111111111111111111111111111111111"
  let blobOther = "2222222222222222222222222222222222222222"
  # (i) identical blob passes — B's own bytes need no approval.
  expectPass("judge: identical blob passes (no approval needed)"):
    judgeGoCriticalInput(pGo, blobB, blobB, @[])
  # (ii) an unapproved change is rejected — empty set AND a wrong-blob set.
  expectFail("judge: unapproved modification rejected", GoTestHashUnapprovedMarker):
    judgeGoCriticalInput(pGo, blobB, blobM, @[])
  expectFail("judge: approving a DIFFERENT blob does not pass", GoTestHashUnapprovedMarker):
    judgeGoCriticalInput(pGo, blobB, blobM, @[blobOther])
  # (iii) an approved change passes — the staged-landing window.
  expectPass("judge: approved modification passes (staged window)"):
    judgeGoCriticalInput(pGo, blobB, blobM, @[blobB, blobM])
  # (iv) additions need their blob approved; deletions never pass.
  expectPass("judge: approved addition passes"):
    judgeGoCriticalInput(pGo, "", blobM, @[blobM])
  expectFail("judge: unapproved addition rejected", GoTestHashUnapprovedMarker):
    judgeGoCriticalInput(pGo, "", blobM, @[])
  expectFail("judge: deletion always rejected (approval cannot permit it)",
      GoTestHashUnapprovedMarker):
    judgeGoCriticalInput(pGo, blobB, "", @[blobB])
  # Table parsing — every malformed shape is fail-closed, never a skip.
  let tableOk = """
{
  "schema": "go-critical-input-approvals/v1",
  "description": "battery fixture",
  "entries": [
    {"path": "tests/unit/test_d2_golden.nim", "approvedBlobs": ["ba294f29118f21d84c2609f3170a538888ce27ac", "1111111111111111111111111111111111111111"]},
    {"path": "tests/golden/rem_body.nim", "approvedBlobs": []}
  ]
}
"""
  let parsedTable = parseApprovalTable(tableOk)
  expectPass("table: valid fixture parses (2 entries, blobs verbatim)"):
    if parsedTable.isOk and parsedTable.get.len == 2 and
        parsedTable.get[0].approvedBlobs.len == 2 and
        parsedTable.get[0].approvedBlobs[1] == blobM and
        parsedTable.get[1].approvedBlobs.len == 0:
      ""
    else:
      "valid-table parse mismatch"
  expectFail("table: wrong schema marker rejected", "schema must be"):
    tblVerdict(tableOk.replace("go-critical-input-approvals/v1",
      "go-critical-input-approvals/v0"))
  expectFail("table: out-of-scope path rejected", "out of scope"):
    tblVerdict("""{"schema":"go-critical-input-approvals/v1","description":"x","entries":[{"path":"src/main.nim","approvedBlobs":["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]}]}""")
  expectFail("table: non-hex blob oid rejected", "not 40 lowercase hex"):
    tblVerdict("""{"schema":"go-critical-input-approvals/v1","description":"x","entries":[{"path":"tests/golden/rem_body.nim","approvedBlobs":["zz"]}]}""")
  expectFail("table: duplicate path rejected", "lists path twice"):
    tblVerdict("""{"schema":"go-critical-input-approvals/v1","description":"x","entries":[{"path":"tests/golden/rem_body.nim","approvedBlobs":[]},{"path":"tests/golden/rem_body.nim","approvedBlobs":[]}]}""")
  expectFail("table: unparsable text rejected", "unparsable"):
    tblVerdict("{not json")
  # ls-tree parsing — blobs kept in git order, subdirectories skipped,
  # malformed records never guessed at.
  expectPass("ls-tree: blobs kept, tree entries skipped, order preserved"):
    block:
      let r = parseLsTree("100644 blob " & blobB & "\ttests/golden/rem_body.nim\n" &
        "040000 tree 0123456789012345678901234567890123456789\ttests/golden/base36_subject\n" &
        "100644 blob " & blobM & "\ttests/unit/test_d2_golden.nim\n")
      if r.isOk and r.get.len == 2 and r.get[0].path == "tests/golden/rem_body.nim" and
          r.get[1].oid == blobM:
        ""
      else:
        "ls-tree parse mismatch"
  expectFail("ls-tree: malformed record rejected", "malformed ls-tree record"):
    block:
      let r = parseLsTree("garbage-without-tab\n")
      if r.isErr: r.error else: ""

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
  let verdictInputs = checkGoCriticalInputs()
  if verdictInputs.isErr:
    echo "[go-critical-inputs] FAIL — " & verdictInputs.error
    return 1
  if verdictInputs.get.len > 0:
    echo "[go-critical-inputs] " & verdictInputs.get
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
