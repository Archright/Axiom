import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Extraction provenance evidence chain (feat/rust-subject-v1 Phase 2-D).
##
## THIS ATTESTATION LANE consumes LLBC and never runs Charon itself — the
## product-side pinned execution lives in `src/verification/charon_runner.nim`
## (the CLI prepare stage), whose identity this module machine-verifies at
## three points (probe-time pin gate, ledger landing, issuance-time
## re-compare). This module closes the provenance gap between "the LLBC bytes
## we consume" and "an approved extraction run" with ZERO new
## gates/authorities/verdict vocabularies:
##
##   1. ExtractionJobRecord — the canonical record of ONE approved extraction
##      run: the Aeneas-side Charon pin (docs/spec/rust_toolchain_quirks.md
##      Q3 — the pin authority lives in the consumer repo, so the SSOT values
##      below are the measured `./charon-pin` resolution), the charon_version
##      recorded in the LLBC header (tcRecorded grade), the MEASURED Rust
##      toolchain fingerprint (the REUSED `RustToolchainFingerprint` type from
##      rust_replay_adapter — measurement is never re-implemented here), the
##      recorded extraction contract (invocation/opts/target as recorded from
##      the LLBC `translated.target_information`/`translated.options` —
##      recorded provenance, never trust adjudication), the subject identity
##      (git ref + tree merkle + module sha256) and `llbcDigest` — the
##      raw-byte sha256 of the consumed LLBC file.
##   2. Durable landing: the record's canonical JSON is appended to the
##      EXISTING EvidenceCas side-ref ledger (evidence_ledger.appendEvidence)
##      under its content address (key = sha256(canonical record bytes)) —
##      FF-only, exactly-once, payloadSha256 re-verified on every read. No
##      second store, no second ref, no new authority.
##   3. Identity binding: `rustToolchainIdentityToken` renders the record's
##      measured fingerprint identity as the token carried by
##      AttestationInputs.rustToolchainIdentity (attestation_orchestrator,
##      evidence schema v2); `llbcDigest` is carried by
##      AttestationInputs.llbcDigest. Both fold into the evidence bundle wire,
##      so evidenceDigest → certificate evidenceId (the 13th identity field)
##      binds the LLBC bytes.
##   4. Attestation-time re-compare: `verifyExtractionEnvironment` is the PURE
##      gate comparing the recorded job record against the currently-installed
##      environment (declared-pin gate pattern from rust_replay_adapter —
##      fail-closed on both violation AND unverifiability). The recorded
##      values stay RECORDED provenance (tcRecorded): this comparison never
##      upgrades them to adjudicated truth, it only refuses to attest on an
##      environment that provably differs or cannot be measured.
##
## Comparison-scope note (deliberate, matches the repo's own recorded-identity
## definition): `rustReplayRecordPayload` records exactly rustVersion,
## rustcHash, componentsHash, channel, profile and components as the measured
## toolchain identity; `rustcPath` and `sysroot` are host-local bookkeeping
## (PATH dispatch token and install prefix) that legitimately differ across
## hosts and are NOT environment identity. The record serializes the full
## fingerprint, but the re-compare compares the identity subset only.

import std/[algorithm, json, os, strutils]
import core/axiom_pragmas
import core/crypto/hash_kernel
import core/results
import verification/canonical_json
import verification/evidence_ledger
import verification/ledger_side_ref  # LedgerTransport (evidence_ledger does not re-export it)
import verification/rust_replay_adapter  # RustToolchainFingerprint — reused measured-identity type
import verification/verification_subject  # isHexOfLen

axiomIoBoundary()

const
  PinnedCharonPinCommit* = "798016509139eb51f0d764645f76d068d34ba5f6"
    ## The Aeneas-side `./charon-pin` resolution — the SSOT for WHICH Charon
    ## revision an approved extraction run must use (docs/spec/
    ## rust_toolchain_quirks.md Q3, measured 2026-10-12). Pin authority is the
    ## consumer repo (Aeneas), never the Charon repo.
  PinnedCharonVersion* = "0.1.281"
    ## charon_version of the pinned Charon revision (same measurement).
  ExtractionJobRecordSchema* = "axiom.extraction.job.v1"
    ## Job-record schema version — a record carrying any other value is
    ## corrupt (fail-closed on parse).

func charonIdentitySegment*(): string {.raises: [].} =
  ## The charon segment of the pinned toolchain identity (stage-e input):
  ## "|charon-pin-<40hex>|charon-<ver>" — appended by
  ## attestation_orchestrator.pinnedToolchainIdentity so the recorded vs
  ## pinned comparison enforces the extraction-pin identity.
  "|charon-pin-" & PinnedCharonPinCommit & "|charon-" & PinnedCharonVersion

# ---------------------------------------------------------------------------
# ExtractionJobRecord — canonical wire (pure)
# ---------------------------------------------------------------------------

type
  ExtractionJobRecord* = object
    ## The provenance record of ONE approved extraction run whose LLBC Axiom
    ## consumes. Everything here is RECORDED provenance (tcRecorded grade):
    ## the record describes the run, it never adjudicates trust by itself.
    charonPinCommit*: string      ## 40-hex — Aeneas-side ./charon-pin (quirk Q3)
    charonVersion*: string        ## charon_version from the LLBC header
    rustcFingerprint*: RustToolchainFingerprint  ## MEASURED (reused type)
    extractionContract*: JsonNode ## recorded invocation/opts/target — object
                                  ## with string values (LLBC-translated
                                  ## target_information/options); empty object
                                  ## allowed, anything else malformed
    subjectGitRef*: string        ## 40-hex — exact subject commit
    subjectTreeMerkle*: string    ## 40-hex — git tree OID of the subject commit
    moduleSha256*: string         ## 64-hex — subject .rs bytes before extraction
    llbcDigest*: string           ## 64-hex — raw-byte sha256 of the LLBC file

func fingerprintToNode*(fp: RustToolchainFingerprint): JsonNode {.raises: [].} =
  ## Canonical node form of the measured fingerprint (full shape — every
  ## measured field travels; the re-compare narrows to the identity subset).
  %*{
    "rustcPath": fp.rustcPath,
    "rustVersion": fp.rustVersion,
    "rustcHash": fp.rustcHash,
    "sysroot": fp.sysroot,
    "componentsHash": fp.componentsHash,
    "components": fp.components,
    "channel": fp.channel,
    "profile": fp.profile
  }

func fingerprintFromNode(node: JsonNode): Result[RustToolchainFingerprint, string] {.raises: [].} =
  ## Strict fingerprint decode: every field present and typed (arrays of
  ## strings); missing/mistyped → err. Never defaults.
  if node.isNil or node.kind != JObject:
    return err("extraction_provenance: rustcFingerprint must be a JSON object")
  template needStr(key: string): string =
    block:
      let v = node{key}
      if v.isNil or v.kind != JString:
        return err("extraction_provenance: rustcFingerprint field '" & key & "' missing or not a string")
      v.getStr()
  var components: seq[string] = @[]
  let compsNode = node{"components"}
  if compsNode.isNil or compsNode.kind != JArray:
    return err("extraction_provenance: rustcFingerprint field 'components' missing or not an array")
  for el in compsNode.items:
    if el.isNil or el.kind != JString:
      return err("extraction_provenance: rustcFingerprint 'components' element not a string")
    components.add(el.getStr())
  ok(RustToolchainFingerprint(
    rustcPath: needStr("rustcPath"),
    rustVersion: needStr("rustVersion"),
    rustcHash: needStr("rustcHash"),
    sysroot: needStr("sysroot"),
    componentsHash: needStr("componentsHash"),
    components: components,
    channel: needStr("channel"),
    profile: needStr("profile")))

func validateExtractionContract(node: JsonNode): string {.raises: [].} =
  ## The recorded extraction contract must be a JSON object with string values
  ## so the canonical serialization stays deterministic (same discipline as
  ## evidence_ledger.validateVerifierArtifactDigests). Empty object is valid —
  ## recording the contract is optional RECORDED provenance.
  if node.isNil:
    return "extraction_provenance: extractionContract must be an object (fail-closed)"
  if node.kind != JObject:
    return "extraction_provenance: extractionContract must be an object (fail-closed)"
  for key, value in node.pairs:
    if value.kind != JString:
      return "extraction_provenance: extractionContract." & key & " must be a string (fail-closed)"
  ""

func validateExtractionJobRecord*(record: ExtractionJobRecord): string {.raises: [].} =
  ## "" = well-formed; otherwise the rejection reason (fail-closed). The
  ## measured fingerprint identity fields must ALL be recorded — an extraction
  ## run whose environment could not be fully measured produces NO valid
  ## record (quirk Q1: profile and the installed component set are ambient and
  ## MUST be recorded; the absent fold of the raw fingerprint type is the
  ## diagnostic of the MEASUREMENT proc, never an acceptable record state).
  if not isHexOfLen(record.charonPinCommit, 40):
    return "extraction_provenance: charonPinCommit must be 40 lowercase hex chars (fail-closed)"
  if record.charonVersion.len == 0:
    return "extraction_provenance: empty field 'charonVersion' (fail-closed)"
  let fp = record.rustcFingerprint
  for (label, value) in [("rustcPath", fp.rustcPath), ("rustVersion", fp.rustVersion),
                         ("rustcHash", fp.rustcHash), ("sysroot", fp.sysroot),
                         ("componentsHash", fp.componentsHash),
                         ("channel", fp.channel), ("profile", fp.profile)]:
    if value.len == 0:
      return "extraction_provenance: rustcFingerprint empty field '" & label & "' (fail-closed)"
  if not isHexOfLen(fp.rustcHash, 64):
    return "extraction_provenance: rustcFingerprint.rustcHash must be 64 lowercase hex chars (fail-closed)"
  if not isHexOfLen(fp.componentsHash, 64):
    return "extraction_provenance: rustcFingerprint.componentsHash must be 64 lowercase hex chars (fail-closed)"
  if fp.components.len == 0:
    return "extraction_provenance: rustcFingerprint.components empty (fail-closed)"
  for c in fp.components:
    if c.len == 0:
      return "extraction_provenance: rustcFingerprint.components contains an empty name (fail-closed)"
  let contractProblem = validateExtractionContract(record.extractionContract)
  if contractProblem.len > 0:
    return contractProblem
  if not isHexOfLen(record.subjectGitRef, 40):
    return "extraction_provenance: subjectGitRef must be 40 lowercase hex chars (fail-closed)"
  if not isHexOfLen(record.subjectTreeMerkle, 40):
    return "extraction_provenance: subjectTreeMerkle must be 40 lowercase hex chars (fail-closed)"
  if not isHexOfLen(record.moduleSha256, 64):
    return "extraction_provenance: moduleSha256 must be 64 lowercase hex chars (fail-closed)"
  if not isHexOfLen(record.llbcDigest, 64):
    return "extraction_provenance: llbcDigest must be 64 lowercase hex chars (fail-closed)"
  ""

func extractionJobRecordToNode*(record: ExtractionJobRecord): JsonNode {.raises: [].} =
  ## The full record as a JSON node (schemaVersion included).
  %*{
    "schemaVersion": ExtractionJobRecordSchema,
    "charonPinCommit": record.charonPinCommit,
    "charonVersion": record.charonVersion,
    "rustcFingerprint": fingerprintToNode(record.rustcFingerprint),
    "extractionContract": record.extractionContract,
    "subjectGitRef": record.subjectGitRef,
    "subjectTreeMerkle": record.subjectTreeMerkle,
    "moduleSha256": record.moduleSha256,
    "llbcDigest": record.llbcDigest
  }

func jobRecordToCanonicalJson*(record: ExtractionJobRecord): string {.raises: [].} =
  ## RFC 8785 canonical JSON of the record — the deterministic ledger payload
  ## bytes. Fixed field set, canonical key order; identical records serialize
  ## to identical bytes (idempotent appends, stable content address).
  canonicalJsonString(extractionJobRecordToNode(record))

func jobRecordFromJson*(node: JsonNode): Result[ExtractionJobRecord, string] {.raises: [].} =
  ## Strict record decode: missing/mistyped fields, a foreign schemaVersion or
  ## a malformed record → err (fail-closed; never defaults).
  if node.isNil or node.kind != JObject:
    return err("extraction_provenance: extraction job record must be a JSON object")
  template need(key: string): string =
    block:
      let v = node{key}
      if v.isNil or v.kind != JString:
        return err("extraction_provenance: extraction job field '" & key & "' missing or not a string")
      v.getStr()
  let schemaVersion = need("schemaVersion")
  if schemaVersion != ExtractionJobRecordSchema:
    return err("extraction_provenance: unsupported extraction job schemaVersion '" &
      schemaVersion[0 ..< min(schemaVersion.len, 32)] & "' (fail-closed)")
  let fingerprint = fingerprintFromNode(node{"rustcFingerprint"})
  if fingerprint.isErr:
    return err(fingerprint.error)
  let contract = node{"extractionContract"}
  if contract.isNil or contract.kind != JObject:
    return err("extraction_provenance: extraction job field 'extractionContract' missing or not an object")
  var contractCopy = newJObject()
  for key, value in contract.pairs:
    contractCopy[key] = value
  let record = ExtractionJobRecord(
    charonPinCommit: need("charonPinCommit"),
    charonVersion: need("charonVersion"),
    rustcFingerprint: fingerprint.get,
    extractionContract: contractCopy,
    subjectGitRef: need("subjectGitRef"),
    subjectTreeMerkle: need("subjectTreeMerkle"),
    moduleSha256: need("moduleSha256"),
    llbcDigest: need("llbcDigest"))
  let problem = validateExtractionJobRecord(record)
  if problem.len > 0:
    return err(problem)
  ok(record)

proc extractionJobRecordFromPayload*(payload: string): Result[ExtractionJobRecord, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Canonical payload bytes → validated record (parseJson lives at the I/O
  ## boundary; validation stays pure). Malformed JSON → err (fail-closed).
  var node: JsonNode
  try:
    node = parseJson(payload)
  except CatchableError as e:
    return err("extraction_provenance: malformed extraction job record JSON: " & e.msg)
  jobRecordFromJson(node)

# ---------------------------------------------------------------------------
# Identity tokens + the content address (pure)
# ---------------------------------------------------------------------------

func rustToolchainIdentityToken*(fp: RustToolchainFingerprint): string {.raises: [].} =
  ## The deterministic identity token carried by
  ## AttestationInputs.rustToolchainIdentity (evidence schema v2 wire member):
  ## the measured identity subset in fixed key order, pipe-joined. Host-local
  ## paths (rustcPath/sysroot) are deliberately absent — see the module header.
  ## Component names never contain '|' or ',' (rust component vocabulary), so
  ## the token is injective over the identity subset.
  "rustc-version=" & fp.rustVersion &
    "|rustc-sha256=" & fp.rustcHash &
    "|components-sha256=" & fp.componentsHash &
    "|channel=" & fp.channel &
    "|profile=" & fp.profile &
    "|components=" & fp.components.join(",")

func validateRustToolchainIdentityToken*(token: string): string {.raises: [].} =
  ## "" = well-formed token; otherwise the rejection reason. Strict grammar:
  ## the six canonical key=value segments in fixed order, 64-hex digests,
  ## non-empty values everywhere (a token that cannot name its full measured
  ## identity is never accepted).
  const Keys = ["rustc-version=", "rustc-sha256=", "components-sha256=",
                "channel=", "profile=", "components="]
  let segments = token.split('|')
  if segments.len != Keys.len:
    return "extraction_provenance: rustToolchainIdentity token must have exactly " &
      $Keys.len & " segments (fail-closed)"
  for i, key in Keys:
    if not segments[i].startsWith(key):
      return "extraction_provenance: rustToolchainIdentity token segment " & $i &
        " must be '" & key & "<value>' (fail-closed)"
    let value = segments[i][key.len ..< segments[i].len]
    if value.len == 0:
      return "extraction_provenance: rustToolchainIdentity token field '" & key[0 ..< key.len - 1] &
        "' is empty (fail-closed)"
  if not isHexOfLen(segments[1]["rustc-sha256=".len ..< segments[1].len], 64):
    return "extraction_provenance: rustToolchainIdentity token rustc-sha256 must be 64 lowercase hex chars (fail-closed)"
  if not isHexOfLen(segments[2]["components-sha256=".len ..< segments[2].len], 64):
    return "extraction_provenance: rustToolchainIdentity token components-sha256 must be 64 lowercase hex chars (fail-closed)"
  ""

func extractionJobKey*(record: ExtractionJobRecord): Result[string, string] {.raises: [].} =
  ## The record's content address: sha256 over the canonical record bytes.
  ## Fail-closed on a malformed record — a record that cannot validate never
  ## yields a key (and never lands in the ledger).
  let problem = validateExtractionJobRecord(record)
  if problem.len > 0:
    return err(problem)
  ok(sha256Hex(jobRecordToCanonicalJson(record)))

# ---------------------------------------------------------------------------
# I/O boundary — raw-file digest + LLBC digest + ledger landing (the ONLY
# writes: FF-only CAS)
# ---------------------------------------------------------------------------

proc fileSha256Hex*(path: string): Result[string, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## sha256Hex over the raw bytes of one file — the canonical raw-file digest
  ## (consumed both by attestation-time digest recomputes and by the LLBC
  ## binding below). Fail-closed on missing or unreadable files; never an
  ## empty/zero digest.
  if not fileExists(path):
    return err("file not found: " & path)
  let bytes =
    try: readFile(path)
    except CatchableError as e:
      return err("file unreadable: " & path & ": " & e.msg)
  ok(sha256Hex(bytes))

proc llbcFileDigest*(path: string): Result[string, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## sha256 over the RAW bytes of the consumed LLBC file — the digest the job
  ## record records and the v2 evidence wire binds. Delegates to the canonical
  ## raw-file digest (`fileSha256Hex` above) and keeps the lane-specific
  ## error prefix.
  fileSha256Hex(path).mapErr(
    proc (e: string): string = "extraction_provenance.llbcFileDigest: " & e)

proc appendExtractionJobRecord*(transport: LedgerTransport; repo: string;
                                record: ExtractionJobRecord;
                                storedAtUtc: string): Result[EvidenceAppendOutcome, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Land ONE extraction job record in the EXISTING EvidenceCas side-ref
  ## ledger. The record is validated first; the ledger payload is the
  ## canonical record bytes and the evidence key is their content address
  ## (sha256) — same bytes → same key → evidence_ledger's exactly-once
  ## discipline makes re-appends idempotent no-ops. verifierArtifactDigests
  ## stays empty: every record field is already inside the payload (identity),
  ## and the digests slot is provenance/informational by contract — nothing
  ## here may smuggle identity out of the payload hash. The record's
  ## evidenceDigest is the payload's OWN content digest (a self-contained
  ## record: the payload is its own evidence object — ADR-0034).
  let problem = validateExtractionJobRecord(record)
  if problem.len > 0:
    return err("extraction_provenance.appendExtractionJobRecord: " & problem)
  let payload = jobRecordToCanonicalJson(record)
  let payloadDigest = sha256Hex(payload)
  let built = makeEvidenceRecord(payloadDigest, payload, newJObject(), storedAtUtc,
    payloadDigest)
  if built.isErr:
    return err("extraction_provenance.appendExtractionJobRecord: " & built.error)
  appendEvidence(transport, repo, built.get)

proc fetchExtractionJobRecord*(transport: LedgerTransport; repo,
                               evidenceKey: string): Result[ExtractionJobRecord, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read ONE extraction job record back: the ledger read re-hashes the
  ## payload bytes and re-verifies the full identity chain
  ## (evidence_ledger.fetchEvidenceRecord), then the payload is strictly
  ## decoded into a validated record. Any anomaly → err (fail-closed).
  let fetched = fetchEvidenceRecord(transport, repo, evidenceKey)
  if fetched.isErr:
    return err("extraction_provenance.fetchExtractionJobRecord: " & fetched.error)
  let record = extractionJobRecordFromPayload(fetched.get.payload)
  if record.isErr:
    return err("extraction_provenance.fetchExtractionJobRecord: " & record.error)
  ok(record.get)

# ---------------------------------------------------------------------------
# Attestation-time re-compare gate (PURE — declared-pin gate pattern)
# ---------------------------------------------------------------------------

type
  MeasuredExtractionEnvironment* = object
    ## The currently-installed environment as MEASURED by the caller at the
    ## I/O boundary (fingerprint: rust_replay_adapter.rustToolchainFingerprint
    ## shape — measurement is never re-implemented here; charon fields: the
    ## resolved Aeneas-side pin present in this environment). An empty field
    ## is the recorded measurement gap — the gate treats it as UNVERIFIABLE,
    ## never as a match.
    fingerprint*: RustToolchainFingerprint
    charonPinCommit*: string
    charonVersion*: string

func verifyExtractionEnvironment*(record: ExtractionJobRecord;
                                  measured: MeasuredExtractionEnvironment): Result[string, string] {.
    raises: [].} =
  ## Attestation-time re-compare of the RECORDED extraction job record against
  ## the MEASURED current environment — the rust_replay_adapter declared-pin
  ## gate pattern: fail-closed on both VIOLATION (a recorded value differs
  ## from the measured one) and UNVERIFIABILITY (the corresponding measurement
  ## is absent, so equality cannot be established). ok("") only when every
  ## compared field matches. The comparison covers the identity subset the
  ## repo itself records (rustVersion, rustcHash, componentsHash, channel,
  ## profile, components) plus the resolved Charon pin identity; host-local
  ## paths (rustcPath/sysroot) are NOT compared — see the module header. Pure:
  ## tests drive it with synthetic records and measured values; the live
  ## caller measures the environment and passes it in. Recorded values stay
  ## tcRecorded provenance — this gate never upgrades them to adjudicated
  ## truth, it only refuses to attest on a divergent or unmeasurable
  ## environment.
  if measured.charonPinCommit.len == 0:
    return err("extraction_provenance.verifyExtractionEnvironment: charon pin commit measurement absent — unverifiable (fail-closed)")
  if measured.charonPinCommit != record.charonPinCommit:
    return err("extraction_provenance.verifyExtractionEnvironment: recorded charon pin commit " &
      record.charonPinCommit & " != measured " & measured.charonPinCommit & " (fail-closed)")
  if measured.charonVersion.len == 0:
    return err("extraction_provenance.verifyExtractionEnvironment: charon version measurement absent — unverifiable (fail-closed)")
  if measured.charonVersion != record.charonVersion:
    return err("extraction_provenance.verifyExtractionEnvironment: recorded charon version " &
      record.charonVersion & " != measured " & measured.charonVersion & " (fail-closed)")
  let recorded = record.rustcFingerprint
  let current = measured.fingerprint
  for (label, rec, now) in [("rustVersion", recorded.rustVersion, current.rustVersion),
                            ("rustcHash", recorded.rustcHash, current.rustcHash),
                            ("componentsHash", recorded.componentsHash, current.componentsHash),
                            ("channel", recorded.channel, current.channel),
                            ("profile", recorded.profile, current.profile)]:
    if now.len == 0:
      return err("extraction_provenance.verifyExtractionEnvironment: measured rustc fingerprint field '" &
        label & "' absent — unverifiable (fail-closed)")
    if now != rec:
      return err("extraction_provenance.verifyExtractionEnvironment: recorded rustc fingerprint " &
        label & " != measured (fail-closed)")
  if current.components.len == 0:
    return err("extraction_provenance.verifyExtractionEnvironment: measured component set absent — unverifiable (fail-closed)")
  var recordedComps = recorded.components
  var measuredComps = current.components
  recordedComps.sort()
  measuredComps.sort()
  if recordedComps != measuredComps:
    return err("extraction_provenance.verifyExtractionEnvironment: recorded rustc component set != measured (fail-closed)")
  ok("")

{.pop.}
