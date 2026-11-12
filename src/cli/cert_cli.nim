import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
# axiomIoBoundary

## Cert CLI — Generate or inspect proof certificates from the reasoning ledger.
##
## Subcommands:
##   show              — display recent proof certificates
##   verify [--kernel] <path>  — verify a certificate file (--kernel: deep-verify via
##                               kernel re-execution of the embedded leanSource/smtlib2)
##   export [--json]   — export certificates
##   reissue-reference <path>  — reclassify a REFERENCE certificate under the current bundle (maintenance-only, never auto-calls ax prove)
##   reconcile [--check|--apply] [--staged] [--cert <id|filename>] — project and materialize the canonical reference vault
##   attest / subject-register / ledger-append / ledger-list — trusted attestation chain + side-ref ledger (certification-continuity Phase 4)
##   continuity --main <sha> --cert <path> — cheap post-merge continuity check (Phase 5b, §4.4 I-2)
##
## Usage: ax cert [show|verify|export|reissue-reference|reconcile|attest|ledger-append|ledger-list|ledger-verify|continuity] [args...]

import std/[os, strutils, json, osproc, tables]
import infrastructure/certificate_attestation
import infrastructure/logging_facade
import core/axiom_pragmas
import core/interfaces/git_operations
import core/results
import core/crypto/hash_kernel
import core/parsers/safe_parsers
import verification/certificate_verifier
import verification/cert_promotion
import verification/cert_reconcile
import verification/cert_vault_role
import verification/evidence_cas
import verification/evidence_ledger
import verification/kernel_reexecution
import verification/attestation_orchestrator
import verification/attestation_witness
import verification/continuity_check
import verification/extraction_agreement
import verification/judgment_cas
import verification/ledger_side_ref
import verification/subject_store
import verification/subject_continuity_writer
import verification/verification_subject
import core/trusted/trust_commit

when fileExists("src/generated/build_env.nim"):
  import generated/build_env
else:
  const BuildEnvGitHash = ""

proc showCerts*(): int  {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let proofVault = ".axiom/vault"
  if not dirExists(proofVault):
    echo "[cert] No proof vault found at .axiom/vault/"
    return 0
  var count = 0
  for kind, path in walkDir(proofVault):
    if kind == pcFile and path.endsWith(".json"):
      inc(count)
      let name = extractFilename(path)
      echo "  " & name
  if count == 0:
    echo "[cert] No certificates found in proof vault."
  else:
    echo "[cert] " & $count & " certificate(s) found."
  return 0

proc verifyKernelReexecution(node: JsonNode): int {.
  axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## --kernel body (extracted so verifyCert stays within the surface budget):
  ## after the structural checks pass, the certificate's attestation basis
  ## becomes re-execution of the pinned kernels on the embedded inputs — Lean
  ## typecheck + `#print axioms` allowlist (INV-6) and fresh Z3 unsat on the
  ## recorded smtlib2 (INV-10), plus the Phase 6 additive leanchecker deep
  ## check. Any non-krPassed verdict → non-zero exit with the precise reason.
  let leanPresent = node.getOrDefault("leanSource").getStr("").len > 0
  let z3Present = node.getOrDefault("smtlib2").getStr("").len > 0
  let leanVerdict =
    if leanPresent: reexecuteLean(node, "", defaultLeanReexecTimeoutMs)
    else: krPassed
  let z3Verdict =
    if z3Present: reexecuteZ3(node, "", defaultZ3ReexecTimeoutMs)
    else: krPassed
  # Phase 6 additive deep check: independent leanchecker re-validation of a
  # FRESH compile of the artifact. Absent checker → loud SKIP, continue;
  # present + mismatch → fail-closed KERNEL_REEXECUTION_FAILED.
  let checkerVerdict =
    if leanPresent: checkLeanWithLeanChecker(node, "", "")
    else: lcSkipped
  if checkerVerdict == lcMismatch:
    echo "[cert] Verify: KERNEL_REEXECUTION_FAILED — " & leanCheckerVerdictReason(checkerVerdict)
    return 1
  let verdict = composeKernelVerdict(leanVerdict, z3Verdict, leanPresent, z3Present)
  if verdict == krPassed:
    echo "[cert] Verify: PASS (kernel re-execution — lean=" &
      (if leanPresent: "re-executed" else: "absent") &
      ", z3=" & (if z3Present: "unsat" else: "absent") &
      ", leanchecker=" &
      (if checkerVerdict == lcPassed: "passed" else: "SKIPPED (additive deep check)" ) & ")"
    return 0
  echo "[cert] Verify: KERNEL_REEXECUTION_FAILED — " & kernelVerdictReason(verdict)
  return 1

proc verifyCert*(path: string; kernelMode: bool = false; projectRoot: string = ""): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## v1 certificate verification — delegates to the R4 trust-closure pipeline
  ## (deep verification + identityDigest recompute + journal binding + replay
  ## input consistency + replay equality). Fail-closed: any missing/mismatched
  ## element fails verification.
  ##
  ## --project <dir>: subject repo root for certificates whose modulePath is
  ## relative to an external subject (the source-staleness leg reads the
  ## subject bytes there; the journal leg always resolves at the product root).
  ##
  ## --kernel mode (certification-continuity Phase 3): AFTER the structural
  ## checks pass, the certificate's attestation basis becomes re-execution of
  ## the pinned kernels on the embedded inputs (verifyKernelReexecution —
  ## Lean/Z3 + Phase 6 leanchecker deep check). Without --kernel the behavior
  ## is unchanged (backward-compatible).
  if not fileExists(path):
    logInfo("cert_cli", "[cert] File not found: " & path)
    return 1
  let res = verifyCertificateClosure(path, projectRoot)
  case res.status
  of ccsPass:
    if not kernelMode:
      echo "[cert] Verify: PASS (replayMatched=true, semanticHash=" & res.semanticHash & ")"
      return 0
    # ── Kernel re-execution deep verify ─────────────────────────────────
    let certLoad = loadCertJsonForReexecution(path)
    if certLoad.isErr():
      echo "[cert] Verify: KERNEL_REEXECUTION_FAILED — " & certLoad.error
      return 1
    return verifyKernelReexecution(certLoad.get)
  of ccsNotCurrent:
    echo "[cert] NOT CURRENT — artifact is valid but not current product truth: " & res.detail
    return 4
  of ccsJournalBindingAbsent, ccsJournalRequired:
    echo "[cert] Verify: JOURNAL_REQUIRED — " & res.detail
    return 2
  else:
    echo "[cert] Verify: FAIL — " & res.detail
    return 1

proc exportCerts*(args: seq[string]): int =
  var asJson = false
  for arg in args:
    if arg == "--json":
      asJson = true
  if asJson:
    echo "{\"certificates\": [], \"count\": 0}"
  else:
    echo "[cert] Export: no certificates to export."
  return 0

proc reconcileCerts*(args: seq[string]): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var checkMode = true
  var staged = false
  var certId = ""
  var i = 0
  while i < args.len:
    let arg = args[i]
    if arg == "--apply":
      checkMode = false
    elif arg == "--staged":
      staged = true
    elif arg == "--cert" and i + 1 < args.len:
      certId = args[i + 1]
      i.inc
    i.inc

  let repoRoot = repoRootForPath(".")
  # listCommitIds and readCommit internally append data/trusted/journal
  # via journalDir(), so they need the repo root, not the journal path.
  let baseDir = if repoRoot.len > 0: repoRoot else: "."

  # Build source snapshot from journal module paths.
  # Handles both v1 (flat claim with top-level modulePath) and
  # v2 (claim with entries[] array, each entry carrying modulePath).
  var sourceSnapshot: Table[string, string]
  let idsRes = listCommitIds(baseDir)
  if idsRes.ok:
    for cid in idsRes.value:
      let rc = readCommit(baseDir, cid)
      if not rc.ok: continue
      var claim: JsonNode
      try:
        claim = parseJson(rc.value.claim)
      except CatchableError:
        continue
      if claim.kind != JObject: continue

      let entries = claim{"entries"}
      if entries != nil and entries.kind == JArray and entries.len > 0:
        for entry in entries:
          if entry.kind != JObject: continue
          let mp = entry{"modulePath"}.getStr("")
          if mp.len == 0: continue
          if not sourceSnapshot.hasKey(mp):
            let sourceCode = if staged:
              try: execProcess("git show :" & mp) except CatchableError: ""
            else:
              try: readFile(mp) except CatchableError: ""
            if sourceCode.len > 0:
              sourceSnapshot[mp] = sourceCode
      else:
        # v1 flat claim shape
        let mp = claim{"modulePath"}.getStr("")
        if mp.len == 0: continue
        if not sourceSnapshot.hasKey(mp):
          let sourceCode = if staged:
            try: execProcess("git show :" & mp) except CatchableError: ""
          else:
            try: readFile(mp) except CatchableError: ""
          if sourceCode.len > 0:
            sourceSnapshot[mp] = sourceCode

  # Single-pass claim-bucket index built once; each tracked cert
  # looks up its own bucket in O(1) instead of re-scanning the journal.
  let bucketsRes = buildClaimBuckets(baseDir)
  if bucketsRes.isErr():
    echo "Result: MATERIALIZATION_UNDEFINED"
    return 2
  let buckets = bucketsRes.value

  # ── Artifact-local projection (new primary path) ──────────────
  # Iterates over tracked reference certificates in the canonical
  # vault and projects each via projectReferenceCertificate.
  let canonicalVaultDir = resolveCertificate(cvCanonicalRead)
  let vaultAbsDir = if canonicalVaultDir.isAbsolute: canonicalVaultDir else: baseDir / canonicalVaultDir

  var hasUndefined = false
  var hasDrift = false
  var allResolved = true
  var scopedMatchCount = 0
  var projections: seq[ReferenceCertProjection]

  if dirExists(vaultAbsDir):
    for kind, path in walkDir(vaultAbsDir):
      if kind != pcFile or not path.endsWith(".json"): continue
      # Manifest skip: a .json without both modulePath and functionName
      # is not a tracked certificate (e.g. a banner/manifest file).
      let fileData = try: readFile(path) except CatchableError: ""
      var fNode = try: parseJson(fileData) except CatchableError: nil
      if fNode == nil or fNode.kind != JObject: continue
      let mp = fNode.getOrDefault("modulePath").getStr("")
      let fn = fNode.getOrDefault("functionName").getStr("")
      if mp.len == 0 and fn.len == 0: continue

      # --cert scoping: only the cert whose basename (no .json) or
      # irHash matches <value> is considered.  A leading-prefix match is
      # accepted so that an irHash prefix (e.g. f3d17f0e) selects the
      # single canonical certificate it derives from.
      if certId.len > 0:
        let basename = splitFile(path).name
        let fileIrHash = fNode.getOrDefault("irHash").getStr("")
        let matches =
          basename == certId or fileIrHash == certId or
          basename.startsWith(certId) or fileIrHash.startsWith(certId)
        if not matches: continue
        inc(scopedMatchCount)

      let projRes = projectReferenceCertificate(path, baseDir, sourceSnapshot, repoRoot, buckets)
      if projRes.isErr():
        echo "MATERIALIZATION_UNDEFINED  " & path
        hasUndefined = true
        continue
      let proj = projRes.value
      projections.add proj

      case proj.outcome
      of rpoResolved:
        let shortCommit = if proj.journalCommitId.len >= 9: proj.journalCommitId[0..8] else: proj.journalCommitId
        echo "RESOLVED  " & proj.claimIdentity & "  commit: " & shortCommit & "..."
        # Drift check: does the vault file differ from projected canonical bytes?
        let vaultBytes = try: readFile(path) except CatchableError: ""
        if vaultBytes != bytesToString(proj.bytes):
          hasDrift = true
      of rpoNoCurrentEvidence:
        echo "NO_EVIDENCE  " & proj.claimIdentity
        hasUndefined = true
        allResolved = false
      of rpoAmbiguousEvidence:
        echo "AMBIGUOUS  " & proj.claimIdentity & " (variants: " & $proj.variantCount & ")"
        hasUndefined = true
        allResolved = false
      of rpoBindingMismatch:
        echo "BINDING_MISMATCH  " & proj.claimIdentity
        hasDrift = true
        allResolved = false
      of rpoInvalidCurrentCertificate:
        echo "INVALID_CERT  " & proj.claimIdentity
        hasUndefined = true
        allResolved = false

  # ── --cert scoping: if the caller constrained to a single tracked cert
  # and none matched, that is an error, not a silent empty success.  A
  # matched cert that projects cleanly is reported by the loop above.
  if certId.len > 0 and scopedMatchCount == 0:
    echo "CERT_NOT_FOUND  " & certId
    return 2

  # ── Exit codes (based on artifact-local projection) ──────────
  if hasUndefined:
    echo "Result: MATERIALIZATION_UNDEFINED"
    if not checkMode:
      echo "  --apply: REFUSED  exit: 2"
    return 2

  if checkMode:
    if hasDrift:
      return 1
    return 0

  # --apply mode (all-or-nothing transaction).
  # P(check,X) == P(apply,X): the same projection path computes the
  # plan whether the user runs --check or --apply; apply only adds
  # the commit (write) step.
  if not allResolved:
    echo "Result: MATERIALIZATION_UNDEFINED"
    echo "  --apply: REFUSED  exit: 2"
    return 2

  # Apply precondition: re-verify projection inputs haven't changed
  # between plan and commit.
  for proj in projections:
    if proj.outcome != rpoResolved:
      echo "Result: MATERIALIZATION_UNDEFINED"
      echo "  --apply: REFUSED (recollection precondition failed): " & (vaultAbsDir / (proj.trackedCertName & ".json"))
      return 2

  # Reference-vault materialization: the reference certificate is a
  # deterministic materialized view of the current canonical evidence.
  # The canonical vault contract (cert_integrity_gate) requires the
  # vault FILENAME to equal the certificate's content irHash — exactly
  # like the manifest's expected-file mapping (irHash & ".json").  When a
  # genuine source mutation changes the evidence irHash, the materialized
  # cert is written under the NEW irHash filename and the stale filename
  # (whose basename no longer matches the manifest) is removed.  This is a
  # deterministic materialization of the new evidence, NOT a certificate
  # mutation script: the bytes are the canonical projection computed by
  # projectReferenceCertificate, and only the stale-name artifact is
  # dropped as an obsolete projection.
  var applied = 0
  for proj in projections:
    let oldTargetPath = vaultAbsDir / (proj.trackedCertName & ".json")
    # Derive the NEW irHash from the canonical projected bytes so the
    # materialized filename matches the new cert content/manifest irHash.
    var newIrHash = ""
    try:
      newIrHash = parseJson(bytesToString(proj.bytes)).getOrDefault("irHash").getStr("")
    except CatchableError:
      newIrHash = ""
    if newIrHash.len == 0:
      echo "  --apply: REFUSED (projected cert has no irHash): " & oldTargetPath
      return 2
    let newTargetPath = vaultAbsDir / (newIrHash & ".json")
    let needsRename = newIrHash != proj.trackedCertName
    if needsRename and fileExists(newTargetPath):
      echo "  --apply: REFUSED (target filename already exists): " & newTargetPath
      return 2
    # Re-read the tracked cert file and confirm trackedCertDigest
    # (on-disk irHash) matches proj.trackedCertId.
    let onDiskData = try: readFile(oldTargetPath) except CatchableError: ""
    var onDiskNode = try: parseJson(onDiskData) except CatchableError: nil
    if onDiskNode != nil and onDiskNode.kind == JObject:
      let onDiskIrHash = onDiskNode.getOrDefault("irHash").getStr("")
      if onDiskIrHash != proj.trackedCertId:
        echo "  --apply: REFUSED (recollection precondition failed): " & oldTargetPath
        return 2
    let targetPath = if needsRename: newTargetPath else: oldTargetPath
    let stagingPath = targetPath & ".new"
    try:
      writeFile(stagingPath, bytesToString(proj.bytes))
    except CatchableError as e:
      echo "  --apply: REFUSED (cannot write staging file): " & e.msg
      if fileExists(stagingPath):
        try: removeFile(stagingPath)
        except CatchableError: discard  # axiom:best-effort(staging cleanup is best-effort; apply outcome already decided)
      return 2
    # Atomic namespace transition.  When the materialized filename is
    # unchanged (in-place replacement of an existing tracked cert),
    # swap staging ↔ target via renameat2(RENAME_EXCHANGE).  When the
    # materialized filename is new because the irHash changed, the
    # target does not exist yet, so RENAME_EXCHANGE is inapplicable;
    # use moveFile (atomic rename(2)) to land the canonical bytes at the
    # new name in a single syscall, then drop the stale-name projection.
    if needsRename:
      try:
        moveFile(stagingPath, targetPath)
      except Exception:
        if fileExists(stagingPath):
          try: removeFile(stagingPath)
          except CatchableError: discard  # axiom:best-effort(staging cleanup is best-effort; apply outcome already decided)
        echo "  --apply: REFUSED (atomic rename failed): " & targetPath
        return 2
    else:
      let exch = atomicReplaceFile(stagingPath, targetPath)
      if exch.isErr():
        echo "  --apply: REFUSED (atomic replace failed): " & exch.error.message
        if fileExists(stagingPath):
          try: removeFile(stagingPath)
          except CatchableError: discard  # axiom:best-effort(staging cleanup is best-effort; apply outcome already decided)
        return 2
    if fileExists(stagingPath):
      try: removeFile(stagingPath)
      except CatchableError: discard  # axiom:best-effort(staging cleanup is best-effort; apply outcome already decided)
    # Remove the obsolete stale-name artifact (stale projection) only after
    # the new canonical file has been atomically written.
    if needsRename and fileExists(oldTargetPath):
      try: removeFile(oldTargetPath)
      except CatchableError:
        echo "  --apply: REFUSED (cannot remove obsolete stale-name artifact): " & oldTargetPath
        return 2
    inc(applied)

  echo "Result: MATERIALIZATION_DEFINED"
  return 0

# ─── Phase 4: trusted attestation + side-ref ledger (certification-continuity) ──

const AttestEvidenceDir = "data" / "trusted" / "evidence"
const DefaultLedgerRepo* = "Archright/Axiom"
  ## Ledger target repo: AXIOM_REPO env overrides; GitHub token = GITHUB_TOKEN.

proc certGateHistoryPath(): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## .axiom/gate_history.jsonl under the repo root (same evidence log the
  ## merge stages journal into; gitignored by repo policy).
  let root = repoRootForPath(".")
  let dir = if root.len > 0: root / ".axiom" else: ".axiom"
  if not dirExists(dir):
    createDir(dir)
  dir / "gate_history.jsonl"

proc journalCertStage(stage: string; record: JsonNode): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Append one stage record (merge-attestation / ledger-append) to the
  ## gate-history evidence log. Failure is surfaced (never silent): the CLI
  ## treats an unwritable journal as an error.
  try:
    var f = open(certGateHistoryPath(), fmAppend)
    defer: f.close()
    f.write($record & "\n")
    true
  except CatchableError:
    false

proc ledgerRepo(): string {.raises: [].} =
  let r = getEnv("AXIOM_REPO", "")
  if r.len > 0: r else: DefaultLedgerRepo

proc ledgerToken(): string {.raises: [].} =
  getEnv("GITHUB_TOKEN", "")

type AttestCliMode* = enum
  amFull          ## existing trusted-tier full attest (kernel a–f + mint g + D6 + journal) — unchanged
  amWitnessOnly   ## DEBT#464 S4 Phase 1a — kernel a–f only → unsigned witness bundle (no sign/journal/network)
  amSign          ## DEBT#464 S4 Phase 1a — verify witness → normalize → reconstruct canonical cert → sign → journal

type AttestCliArgs* = object
  refName: string
  prNumber: int
  evidencePath: string
  mode: AttestCliMode
  witnessPath: string      ## --sign <witness-file>
  witnessOut: string       ## --out <path> for the witness-only bundle (default "witness.json")
  mergeSha: string         ## provenance M — merge-ref commit
  mergeTree: string        ## provenance — tree OID of the merge-ref commit (merge-candidate tree)
  toolCommit: string       ## provenance B — build commit of the ax binary that ran the chain
  runId: string            ## provenance run id (GitHub Actions)
  runAttempt: string       ## provenance run attempt

type RegisterCliArgs = object
  baseSha: string
  prNumber: int
  headTreeOid: string
  createdAt: string
  evidencePath: string
  evidenceFromPath: string

proc parseRegisterArgs(args: seq[string]): tuple[ok: bool; parsed: RegisterCliArgs; err: string] {.raises: [].} =
  ## usage: ax cert subject-register --base <baseSha> [--pr N] [--head-tree <oid>] [--created-at <ts>] [--evidence <path>]
  ## The binding evidence is the UNTRUSTED-TIER record (axiom.attestation.evidence.v1);
  ## --base / --pr / --head-tree / --created-at come from the trusted dispatch
  ## inputs (the trusted boundary's independently-observed values).
  ## if/elif (not a case) so the module's OCP case-branch surface stays at its
  ## anchored baseline (solid-ocp debt).
  var parsed = RegisterCliArgs(baseSha: "", prNumber: 0, headTreeOid: "", createdAt: "",
    evidencePath: "", evidenceFromPath: "")
  var i = 0
  while i < args.len:
    if args[i] == "--base":
      if i + 1 >= args.len:
        return (ok: false, parsed: parsed, err: "--base requires a value")
      parsed.baseSha = args[i + 1]
      inc i
    elif args[i] == "--pr":
      if i + 1 >= args.len:
        return (ok: false, parsed: parsed, err: "--pr requires a number")
      let num = safeParseInt(args[i + 1])
      if num.isErr or num.get <= 0:
        return (ok: false, parsed: parsed, err: "invalid PR number: " & args[i + 1])
      parsed.prNumber = num.get
      inc i
    elif args[i] == "--head-tree":
      if i + 1 >= args.len:
        return (ok: false, parsed: parsed, err: "--head-tree requires a value")
      parsed.headTreeOid = args[i + 1]
      inc i
    elif args[i] == "--created-at":
      if i + 1 >= args.len:
        return (ok: false, parsed: parsed, err: "--created-at requires a value")
      parsed.createdAt = args[i + 1]
      inc i
    elif args[i] == "--evidence":
      if i + 1 >= args.len:
        return (ok: false, parsed: parsed, err: "--evidence requires a path")
      parsed.evidencePath = args[i + 1]
      inc i
    elif args[i] == "--evidence-from":
      if i + 1 >= args.len:
        return (ok: false, parsed: parsed, err: "--evidence-from requires a path")
      parsed.evidenceFromPath = args[i + 1]
      inc i
    else:
      return (ok: false, parsed: parsed, err: "unknown argument: " & args[i])
    inc i
  if parsed.baseSha.len == 0:
    return (ok: false, parsed: parsed, err: "usage: ax cert subject-register --base <baseSha> [--pr N] [--head-tree <oid>] [--evidence <path>]")
  if parsed.evidencePath.len == 0 and parsed.evidenceFromPath.len == 0:
    return (ok: false, parsed: parsed, err: "subject-register requires --evidence <path> (or --evidence-from)")
  (ok: true, parsed: parsed, err: "")

proc cleanHexOpt*(s: string): string {.raises: [].} =
  ## Normalize an 40-hex option to lowercase, stripping surrounding quotes.
  var t = s.strip()
  if t.len > 0 and t[0] == '"' and t[^1] == '"':
    t = t[1 .. ^2]
  t.toLowerAscii

const AttestStrValueFlags = ["--ref", "--evidence", "--out", "--merge-sha",
  "--merge-tree", "--tool-commit", "--run-id", "--run-attempt"]
  ## Value-taking attest flags mapped to AttestCliArgs string fields.

proc parseAttestModeFlags(args: seq[string]; parsed: var AttestCliArgs; iRef: var int): tuple[
    ok: bool; err: string] {.raises: [].} =
  ## Parse one attest argument from args[iRef] onward, advancing iRef.
  ## if/elif (not a case) keeps the OCP case-branch surface at its baseline.
  let arg = args[iRef]
  if arg == "--witness-only":
    parsed.mode = amWitnessOnly
  elif arg in AttestStrValueFlags:
    if iRef + 1 >= args.len:
      return (ok: false, err: arg & " requires a value")
    let value = args[iRef + 1]
    inc iRef
    if arg == "--ref": parsed.refName = value
    elif arg == "--evidence": parsed.evidencePath = value
    elif arg == "--out": parsed.witnessOut = value
    elif arg == "--merge-sha": parsed.mergeSha = value
    elif arg == "--merge-tree": parsed.mergeTree = value
    elif arg == "--tool-commit": parsed.toolCommit = value
    elif arg == "--run-id": parsed.runId = value
    else: parsed.runAttempt = value
  elif arg == "--pr":
    if iRef + 1 >= args.len:
      return (ok: false, err: "--pr requires a number")
    let num = safeParseInt(args[iRef + 1])
    if num.isErr or num.get <= 0:
      return (ok: false, err: "invalid PR number: " & args[iRef + 1])
    parsed.prNumber = num.get
    inc iRef
  elif arg == "--sign":
    if iRef + 1 >= args.len:
      return (ok: false, err: "--sign requires a witness file path")
    parsed.mode = amSign
    parsed.witnessPath = args[iRef + 1]
    inc iRef
  else:
    return (ok: false, err: "unknown argument: " & arg)
  (ok: true, err: "")

func validateAttestArgs(parsed: AttestCliArgs): string {.raises: [].} =
  ## Mode-scoped post-parse validation — returns the rejection reason or "".
  if parsed.mode == amSign:
    if parsed.witnessPath.len == 0:
      return "usage: ax cert attest --sign <witness-file>"
    return ""
  if parsed.refName.len == 0:
    if parsed.mode == amWitnessOnly:
      return "usage: ax cert attest --witness-only --ref <headSha> [--pr N] [--evidence <path>] --merge-sha <M> --merge-tree <treeOID> --tool-commit <B> --run-id <N> --run-attempt <N> [--out <path>]"
    return "usage: ax cert attest --ref <headSha> [--pr N] [--evidence <path>]"
  if parsed.mode == amWitnessOnly:
    # provenance recording is mandatory — a witness without M/B/run identity is
    # not traceable and would be rejected by the publisher tier anyway.
    if parsed.mergeSha.len == 0 or parsed.mergeTree.len == 0 or
       parsed.toolCommit.len == 0 or parsed.runId.len == 0 or parsed.runAttempt.len == 0:
      return "witness-only requires --merge-sha <M> --merge-tree <treeOID> --tool-commit <B> --run-id <N> --run-attempt <N> (provenance recording is mandatory, fail-closed)"
  ""

proc parseAttestArgs*(args: seq[string]): tuple[ok: bool; parsed: AttestCliArgs; err: string] {.raises: [].} =
  ## usage:
  ##   ax cert attest --ref <headSha> [--pr N] [--evidence <path>]          (full, unchanged)
  ##   ax cert attest --witness-only --ref <headSha> [--pr N] [--evidence <path>]
  ##       --merge-sha <M> --merge-tree <treeOID> --tool-commit <B>
  ##       --run-id <N> --run-attempt <N> [--out <path>]
  ##   ax cert attest --sign <witness-file>
  ## if/elif (not a case) so the module's OCP case-branch surface stays at its
  ## anchored baseline (solid-ocp debt).
  var parsed = AttestCliArgs(refName: "", prNumber: 0, evidencePath: "",
    mode: amFull, witnessPath: "", witnessOut: "witness.json",
    mergeSha: "", mergeTree: "", toolCommit: "", runId: "", runAttempt: "")
  var i = 0
  while i < args.len:
    let flagRes = parseAttestModeFlags(args, parsed, i)
    if not flagRes.ok:
      return (ok: false, parsed: parsed, err: flagRes.err)
    inc i
  let problem = validateAttestArgs(parsed)
  if problem.len > 0:
    return (ok: false, parsed: parsed, err: problem)
  (ok: true, parsed: parsed, err: "")

type AttestLoadedInputs = object
  subject: VerificationSubject
  evidence: AttestationInputs
  evidencePath: string

proc loadEvidenceRecordForRegister*(parsed: RegisterCliArgs): Result[AttestationInputs, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## F8: load + strictly validate the untrusted-tier evidence record the verb
  ## registers a subject for. Fail-closed: missing file, unparsable JSON, or
  ## record-schema violation → err (never a silent skip).
  let evidencePath = if parsed.evidencePath.len > 0: parsed.evidencePath else: parsed.evidenceFromPath
  if not fileExists(evidencePath):
    return err("evidence record not found: " & evidencePath & " (fail-closed)")
  let evidenceText = readFile(evidencePath)
  var outcome: Result[AttestationInputs, string]
  try:
    outcome = parseAttestationEvidenceText(evidenceText)
  except Exception as e:
    outcome = Result[AttestationInputs, string](ok: false, err: "evidence parse raised: " & e.msg)
  outcome

proc registerSubjectFromEvidence*(parsed: RegisterCliArgs; evidencePath: string;
                                  evidence: AttestationInputs): Result[VerificationSubject, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## F8: construct the VerificationSubject from the VERIFIED evidence + the
  ## trusted-boundary-observed bindings (--base, --head-tree). The subjectId is
  ## RE-DERIVED from the canonical 6-field wire — never accepted from the
  ## artifact (fail-closed). headTreeDigest = sha256Hex(headTreeOid) where the
  ## OID was independently re-derived (GitHub API) at the trusted boundary.
  let baseSha = cleanHexOpt(parsed.baseSha)
  if not isHexOfLen(baseSha, 40):
    return err("--base must be 40 lowercase hex (fail-closed)")
  var headTreeOid = ""
  if parsed.headTreeOid.len > 0:
    headTreeOid = cleanHexOpt(parsed.headTreeOid)
  if not isHexOfLen(headTreeOid, 40):
    return err("--head-tree required — the trusted boundary must re-derive the head tree OID (fail-closed)")
  var createdAt = parsed.createdAt
  if createdAt.len == 0:
    createdAt = currentUtcTimestamp()
  if not isValidIso8601Zulu(createdAt):
    return err("--created-at must be ISO8601 'yyyy-MM-ddTHH:mm:ssZ' (fail-closed)")
  if not isHexOfLen(evidence.prHeadSha, 40):
    return err("evidence.prHeadSha must be 40 hex (fail-closed)")
  let evidenceDigest = evidenceBundleDigest(evidence)
  let headTreeDigest = sha256Hex(headTreeOid)
  let made = makeSubject(baseSha, evidence.prHeadSha, headTreeDigest,
    evidence.policyDigest, evidence.scopeDigest, evidenceDigest,
    evidence.prNumber, createdAt)
  if made.isErr:
    return err(made.error)
  ok(made.get)

proc persistRegisteredSubject*(subject: VerificationSubject; evidencePath: string): Result[string, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## F8: append-only persistence + journal record for a registered subject.
  ## Idempotent: a same-subjectId existing record short-circuits (the re-attest
  ## path), anything else is saved via saveSubject (append-only, refuses
  ## overwrite — fail-closed).
  var existingOutcome: Result[VerificationSubject, string]
  try:
    existingOutcome = loadSubject(subject.subjectId)
  except Exception as e:
    existingOutcome = Result[VerificationSubject, string](ok: false, err: "loadSubject raised: " & e.msg)
  if existingOutcome.isOk():
    logInfo("cert_cli", "subject-register: subject " & subject.subjectId[0 ..< 12] &
      " already registered (append-only) — idempotent re-attest path")
    return ok("already-registered")
  var saved: Result[string, string]
  try:
    saved = saveSubject(subject)
  except Exception as e:
    saved = Result[string, string](ok: false, err: "saveSubject raised: " & e.msg)
  if saved.isErr:
    return err(saved.error)
  let record = %*{
    "stage": "merge-subject-register",
    "timestamp": currentUtcTimestamp(),
    "baseSha": subject.baseSha,
    "headSha": subject.headSha,
    "headTreeDigest": subject.headTreeDigest,
    "subjectId": subject.subjectId,
    "evidenceDigest": subject.evidenceDigest,
    "prNumber": subject.prNumber,
    "policyDigest": subject.policyDigest,
    "scopeDigest": subject.scopeDigest,
    "evidencePath": evidencePath,
    "storePath": saved.get
  }
  if not journalCertStage("merge-subject-register", record):
    return err("journal write failed (merge-subject-register)")
  ok(saved.get)

proc runSubjectRegisterCli(args: seq[string]): int {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## usage: ax cert subject-register --base <baseSha> [--pr N] [--head-tree <oid>] [--evidence <path>]
  ## Trusted-tier subject registration (certification-continuity F8 — the
  ## issuance wiring that completes Phase 4): builds a VerificationSubject from
  ## VERIFIED evidence (schema axiom.attestation.evidence.v1) whose binding
  ## fields were already independently verified at the trusted boundary
  ## (dispatch headSha == evidence.prHeadSha; head tree OID re-derived via the
  ## GitHub API; policy/scope/toolchain digests recomputed at that boundary).
  ## The subjectId is re-derived from the canonical 6-field wire — never
  ## accepted from the artifact (fail-closed). store subject registration is
  ## append-only (data/trusted/subjects/<subjectId>.json); an existing same-id
  ## record short-circuits and returns 0 (the re-attest path is idempotent).
  var parsedRes: tuple[ok: bool; parsed: RegisterCliArgs; err: string]
  try:
    parsedRes = parseRegisterArgs(args)
  except Exception as e:
    logInfo("cert_cli", "subject-register: parse raised: " & e.msg)
    return 1
  if not parsedRes.ok:
    logInfo("cert_cli", parsedRes.err)
    return 1
  let parsed = parsedRes.parsed
  let evidencePath = if parsed.evidencePath.len > 0: parsed.evidencePath else: parsed.evidenceFromPath
  var evidenceOutcome: Result[AttestationInputs, string]
  evidenceOutcome =
    try: loadEvidenceRecordForRegister(parsed)
    except Exception as e:
      Result[AttestationInputs, string](ok: false, err: "evidence load raised: " & e.msg)
  if evidenceOutcome.isErr():
    logError("cert_cli", "subject-register: " & evidenceOutcome.error)
    return 1
  let evidence = evidenceOutcome.get
  var subjectOutcome: Result[VerificationSubject, string]
  subjectOutcome =
    try: registerSubjectFromEvidence(parsed, evidencePath, evidence)
    except Exception as e:
      Result[VerificationSubject, string](ok: false, err: "subject construction raised: " & e.msg)
  if subjectOutcome.isErr():
    logError("cert_cli", "subject-register: " & subjectOutcome.error)
    return 1
  let subject = subjectOutcome.get
  var persistOutcome: Result[string, string]
  persistOutcome =
    try: persistRegisteredSubject(subject, evidencePath)
    except Exception as e:
      Result[string, string](ok: false, err: "persist raised: " & e.msg)
  if persistOutcome.isErr():
    logError("cert_cli", "subject-register: " & persistOutcome.error)
    return 1
  echo "[cert] Subject registered: " & subject.subjectId
  return 0

proc loadAttestInputs(parsed: AttestCliArgs): Result[AttestLoadedInputs, string] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Resolve the STORED subject by headSha (exactly one — none or several is
  ## fail-closed), load and validate its evidence record, and cross-check the
  ## optional --pr binding. No verdicts here; pure input.
  var subjectsOutcome: Result[seq[VerificationSubject], string]
  try:
    subjectsOutcome = findSubjectsByHeadSha(parsed.refName)
  except Exception as e:
    subjectsOutcome = Result[seq[VerificationSubject], string](ok: false, err: "subject store raised: " & e.msg)
  if subjectsOutcome.isErr:
    return err("subject store: " & subjectsOutcome.error)
  let subjects = subjectsOutcome.get
  if subjects.len == 0:
    return err("no stored subject for ref " & parsed.refName & " (fail-closed)")
  if subjects.len > 1:
    return err("multiple stored subjects for ref " & parsed.refName & " (fail-closed)")
  let subject = subjects[0]
  let evidencePath = if parsed.evidencePath.len > 0:
    parsed.evidencePath
  else:
    AttestEvidenceDir / subject.subjectId & ".json"
  if not fileExists(evidencePath):
    return err("evidence record not found: " & evidencePath & " (fail-closed)")
  let evidenceText = readFile(evidencePath)
  var evidenceOutcome: Result[AttestationInputs, string]
  try:
    evidenceOutcome = parseAttestationEvidenceText(evidenceText)
  except Exception as e:
    evidenceOutcome = Result[AttestationInputs, string](ok: false, err: "evidence parse raised: " & e.msg)
  if evidenceOutcome.isErr:
    return err("evidence: " & evidenceOutcome.error)
  let evidence = evidenceOutcome.get
  if parsed.prNumber > 0 and evidence.prNumber != parsed.prNumber:
    return err("evidence prNumber " & $evidence.prNumber & " != --pr " & $parsed.prNumber & " (fail-closed)")
  ok(AttestLoadedInputs(subject: subject, evidence: evidence, evidencePath: evidencePath))

proc journalAttestRecord(record: JsonNode; outcome: AttestationResult; verdict: AttestationVerdict;
                         ledgerOutcome: Result[string, string]; ledgerNote: string): bool
    {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## One merge-attestation journal record per run — the CLI's single journal
  ## surface (stage merge-attestation). Never silent: returns journal success.
  ## ledgerNote carries a free-form ledger state annotation (delegation note
  ## or error) — never swallowed.
  var rec = record
  rec["certPath"] = %(if outcome.certPath.len > 0: outcome.certPath else: "")
  rec["commitId"] = %outcome.commitId
  rec["reason"] = %outcome.reason
  rec["verdict"] = %($verdict)
  rec["ledgerTip"] = %(if ledgerOutcome.isOk: ledgerOutcome.get else: "")
  if ledgerNote.len > 0:
    rec["ledgerNote"] = %ledgerNote
  journalCertStage("merge-attestation", rec)

proc ledgerHasSubjectCert*(transport: LedgerTransport; repo, subjectId: string): Result[bool, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## ADR-0021 D6 (Phase 3): duplicate-subject predicate — ok(true) iff the
  ## side-ref ledger already holds a certificate authority for subjectId
  ## (certId = subjectId; the ledger is the only durable authority source).
  ## A subject already minted there must NOT mint again (authority count = 1).
  ## A ledger read failure is an err — the caller must refuse (fail-closed:
  ## minting on an unknown ledger state could mint a second authority).
  let ids = listLedgerCertIds(transport, repo)
  if ids.isErr:
    return err("ledger read failed (fail-closed): " & ids.error)
  ok(ids.get.contains(subjectId))

proc runWitnessOnlyCli(parsed: AttestCliArgs): int {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## usage: ax cert attest --witness-only --ref <headSha> ... (DEBT#464 S4 Phase 1a)
  ## Runs the kernel chain stages (a)-(f) EXACTLY as the full attest does, then
  ## writes an UNSIGNED witness bundle. No certificate mint, no journal write.
  ## Fail-closed: any chain verdict other than atPassed exits non-zero; the
  ## subject store reload is the same trusted source the full path uses.
  ##
  ## Evidence CAS branch (AXIOM_EVIDENCE_CAS_ENABLED=1 — SL-15): the chain is
  ## attestWitnessChainCas — on a verified ledger HIT the kernel chain
  ## (b)+(c) is the sanctioned §15.3 skip and the stored evidence payload is
  ## reused; on a MISS the fresh outcome produces the canonical evidence
  ## record file for the trusted mint to append (idempotent). Env unset =
  ## zero behavior change: no new reads, no new files, no log lines. Any
  ## enabled-but-unverifiable CAS state (or a record-write failure) is
  ## fail-closed — the run never continues without its evidence record.
  let loadedRes = loadAttestInputs(parsed)
  if loadedRes.isErr:
    logError("cert_cli", "attest --witness-only: " & loadedRes.error)
    return 1
  let loaded = loadedRes.get
  # The plan itself never aborts the CLI: any raise is folded into a casError
  # plan, which attestWitnessChainCas fail-closes to atInternalError — an
  # enabled-but-unverifiable CAS state never degrades into a chain PASS.
  var cas: EvidenceCasPlan
  try:
    cas = planEvidenceCas("")
  except Exception as e:
    cas = EvidenceCasPlan(mode: casError,
      reason: "evidence CAS plan raised: " & e.msg & " (fail-closed)")
  var reusedIrHash = ""
  var agreement: ExtractionAgreementResult
  var attestOutcome: AttestationResult
  try:
    attestOutcome = attestWitnessChainCas(loaded.subject, loaded.evidence,
      defaultAttestationOptions(), agreement, cas, reusedIrHash)
  except Exception as e:
    attestOutcome = AttestationResult(verdict: atInternalError,
      reason: "attest chain raised: " & e.msg)
  if attestOutcome.verdict != atPassed:
    logError("cert_cli", "attest --witness-only: FAILED — " & $attestOutcome.verdict & ": " & attestOutcome.reason)
    return 1
  # Evidence CAS record — written BEFORE any witness lands (fail-closed: the
  # store path must complete or the run dies here). MISS = the fresh outcome's
  # canonical record for the trusted mint's append; HIT = the re-verified
  # stored record rebound to this run (same identity bytes → the mint's
  # append is an idempotent no-op — exactly-once preserved).
  if cas.mode != casOff:
    var payload = cas.payload
    if cas.mode == casMiss:
      let neRes = normalizedEvidenceForRun(loaded.evidence, agreement)
      if neRes.isErr:
        logError("cert_cli", "attest --witness-only: evidence CAS record: " & neRes.error)
        return 1
      payload = normalizedEvidenceWire(neRes.get)
    var recordRes = Result[EvidenceCasRecord, string](ok: false, err: "")
    try:
      recordRes = buildEvidenceCasRecord(cas, payload, loaded.evidence)
    except Exception as e:
      recordRes = Result[EvidenceCasRecord, string](ok: false,
        err: "record build raised: " & e.msg)
    if recordRes.isErr:
      logError("cert_cli", "attest --witness-only: evidence CAS record: " & recordRes.error)
      return 1
    try:
      writeFile(cas.recordPath, evidenceRecordToCanonicalJson(recordRes.get))
    except CatchableError as e:
      logError("cert_cli", "attest --witness-only: evidence CAS record write failed (fail-closed): " & e.msg)
      return 1
    echo evidenceCasReuseLogLine(cas)
  let b = if parsed.toolCommit.len > 0: parsed.toolCommit else: BuildEnvGitHash
  let provenance = WitnessProvenance(
    mergeSha: parsed.mergeSha,
    mergeTreeDigest: parsed.mergeTree,
    toolCommit: b,
    prHeadSha: loaded.subject.headSha,
    prNumber: loaded.evidence.prNumber,
    runId: parsed.runId,
    runAttempt: parsed.runAttempt,
    artifact: "witness-" & parsed.runAttempt)
  # Judgment CAS branch (AXIOM_JUDGMENT_CAS_ENABLED — SL-15): consume the plan
  # stage's decision, bind the judgment projection into the witness, and
  # publish the record file the trusted mint appends. Unarmed = zero behavior
  # change (legacy witness bytes, no journal line). An armed-but-unverifiable
  # state fails the run — a certificate never rides on a judgment it cannot
  # re-verify (REUSED) or show (EXECUTED). The branch runs once PER SUBJECT
  # (s1a + the three extension subjects): s1a keeps its landed `.semantic.
  # judgment` node; the extension subjects land in `.semantic.judgments[]`.
  var judgmentNode: JsonNode = nil
  var judgmentsNode: JsonNode = newJArray()
  try:
    for subject in allJudgmentSubjects():
      let judgmentRes = runJudgmentAttestBranchForSubject(subject)
      if judgmentRes.isErr:
        logError("cert_cli", "attest --witness-only: judgment CAS[" &
          subjectName(subject) & "]: " & judgmentRes.error)
        return 1
      if judgmentRes.get.armed:
        if subject == jsS1aGolden:
          judgmentNode = judgmentRes.get.node
        else:
          judgmentsNode.add(judgmentRes.get.node)
        let record = %*{
          "stage": "judgment-cas",
          "timestamp": currentUtcTimestamp(),
          "basis": judgmentRes.get.basis,
          "evidenceKey": judgmentRes.get.evidenceKey,
          "reason": judgmentRes.get.reason,
          "recordPath": judgmentRes.get.recordPath,
          "subject": subjectName(subject),
          "prHeadSha": loaded.subject.headSha
        }
        if not journalCertStage("judgment-cas", record):
          logError("cert_cli", "attest --witness-only: journal write failed (judgment-cas)")
          return 1
        echo "[cert] Judgment CAS[" & subjectName(subject) & "]: " &
          judgmentRes.get.basis & " — key " &
          judgmentRes.get.evidenceKey[0 ..< 12] & " (" & judgmentRes.get.reason & ")"
  except Exception as e:
    logError("cert_cli", "attest --witness-only: judgment CAS raised: " & e.msg)
    return 1
  let irHash = if cas.mode == casHit: reusedIrHash
    elif agreement.nimDigest.len > 0: agreement.nimDigest
    else: evidenceBundleDigest(loaded.evidence)
  var bundle: WitnessBundle
  try:
    let bundleRes = createWitnessBundle(loaded.subject, loaded.evidence, irHash,
      currentUtcTimestamp(), provenance, judgment = judgmentNode,
      judgments = (if judgmentsNode.len > 0: judgmentsNode else: nil))
    if bundleRes.isErr:
      logError("cert_cli", "attest --witness-only: " & bundleRes.error)
      return 1
    bundle = bundleRes.get
  except Exception as e:
    logError("cert_cli", "attest --witness-only: witness assembly raised: " & e.msg)
    return 1
  let text = witnessBundleJson(bundle)
  try:
    writeFile(parsed.witnessOut, text)
  except CatchableError as e:
    logError("cert_cli", "attest --witness-only: cannot write witness bundle: " & e.msg)
    return 1
  echo "[cert] Attest --witness-only: PASS (chain a-f) — unsigned witness bundle " & parsed.witnessOut
  echo "[cert] Witness: head " & loaded.subject.headSha[0 ..< 12] &
    " merge " & parsed.mergeSha[0 ..< 12] &
    " mergeTree " & parsed.mergeTree[0 ..< 12] &
    " tool " & b[0 ..< 12] &
    " run " & parsed.runId & "/" & parsed.runAttempt
  return 0
proc runSignWitnessCli(parsed: AttestCliArgs): int {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## usage: ax cert attest --sign <witness-file> (DEBT#464 S4 Phase 1a)
  ## Verify → normalize → reconstruct the canonical certificate representation →
  ## journal → sign, through the SAME v3 writer the full attest uses. NO kernel
  ## execution, NO network. Fail-closed: a tampered/deformed witness is rejected
  ## with its WITNESS_* reason; exit 0 only when the certificate minted.
  if parsed.witnessPath.len == 0 or not fileExists(parsed.witnessPath):
    logError("cert_cli", "attest --sign: witness file not found: " & parsed.witnessPath & " (fail-closed)")
    return 1
  let text =
    try: readFile(parsed.witnessPath)
    except CatchableError as e:
      logError("cert_cli", "attest --sign: witness read failed: " & e.msg & " (fail-closed)")
      return 1
  var bundle: WitnessBundle
  try:
    let parsedRes = parseWitnessBundleText(text)
    if parsedRes.isErr:
      logError("cert_cli", "attest --sign: witness rejected — " & parsedRes.error)
      return 1
    bundle = parsedRes.get
  except Exception as e:
    logError("cert_cli", "attest --sign: witness parse raised: " & e.msg & " (fail-closed)")
    return 1
  let signRes =
    try: signWitness(bundle, defaultAttestationOptions().certDir)
    except Exception as e:
      Result[SubjectCertificateMintResult, string](ok: false, err: "sign raised: " & e.msg)
  if signRes.isErr:
    logError("cert_cli", "attest --sign: " & signRes.error)
    return 1
  let record = %*{
    "stage": "merge-attestation",
    "timestamp": currentUtcTimestamp(),
    "headSha": bundle.semantic.subject.headSha,
    "subjectId": bundle.semantic.subject.subjectId,
    "prNumber": bundle.semantic.evidence.prNumber,
    "witness": parsed.witnessPath
  }
  if not journalCertStage("merge-attestation", record):
    logError("cert_cli", "attest --sign: journal write failed (merge-attestation)")
    return 1
  echo "[cert] Attest --sign: PASS — certificate " & signRes.get.path
  return 0

proc runAttestD6Duplicate(subject: VerificationSubject): int {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## ADR-0021 D6 duplicate-subject predicate — the CLI's execution-authority
  ## refusal BEFORE the mint-attempt chain: a certificate authority already in
  ## the ledger for this subjectId must never be minted again (authority count
  ## = 1). A ledger read failure fails closed (minting on an unknown ledger
  ## state is not allowed). Returns 0 = no duplicate (proceed), non-zero =
  ## refused.
  let token = ledgerToken()
  if token.len == 0:
    logError("cert_cli", "attest: GITHUB_TOKEN not set — duplicate-subject ledger check refused (fail-closed)")
    return 1
  var dupOutcome: Result[bool, string]
  try:
    dupOutcome = ledgerHasSubjectCert(liveLedgerTransport(token), ledgerRepo(), subject.subjectId)
  except Exception as e:
    dupOutcome = Result[bool, string](ok: false, err: "ledger transport raised: " & e.msg)
  if dupOutcome.isErr:
    logError("cert_cli", "attest: " & dupOutcome.error)
    return 1
  if dupOutcome.get:
    logError("cert_cli", "attest: duplicate-subject: certificate authority for subjectId " &
      subject.subjectId & " already exists in ledger — re-verification of the same subject " &
      "does not mint a new authority (ADR-0021 D6)")
    return 1
  0

proc runAttestCli(args: seq[string]): int {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## usage: ax cert attest --ref <headSha> [--pr N] [--evidence <path>]
  ## Trusted-tier orchestration (contract §4.1): load subject + evidence, run
  ## the attestation chain, mint on ALL PASS, append to the side-ref ledger,
  ## journal `merge-attestation`. Exit 0 ONLY when the verdict is atPassed.
  ## D6 duplicate-subject refusal runs before the chain (ADR-0021).
  ##
  ## DEBT#464 S4 Phase 1a mode split — the FULL path above is unchanged:
  ##   --witness-only → runWitnessOnlyCli (kernel a–f only, unsigned witness)
  ##   --sign <witness> → runSignWitnessCli (verify → normalize → reconstruct →
  ##                     sign → journal; kernel/network 0)
  ## dispatch is mode-first so the requested surface decides before any
  ## token/journal access.
  let parsedRes = parseAttestArgs(args)
  if not parsedRes.ok:
    logInfo("cert_cli", parsedRes.err)
    return 1
  let parsed = parsedRes.parsed
  if parsed.mode == amWitnessOnly:
    return runWitnessOnlyCli(parsed)
  if parsed.mode == amSign:
    return runSignWitnessCli(parsed)
  let loadedRes = loadAttestInputs(parsed)
  if loadedRes.isErr:
    logError("cert_cli", "attest: " & loadedRes.error)
    return 1
  let loaded = loadedRes.get
  if runAttestD6Duplicate(loaded.subject) != 0:
    return 1
  var attestOutcome: AttestationResult
  try:
    attestOutcome = attest(loaded.subject, loaded.evidence, defaultAttestationOptions(),
      parsed.mergeTree)
  except Exception as e:
    attestOutcome = AttestationResult(verdict: atInternalError,
      reason: "attest chain raised: " & e.msg)
  let record = %*{
    "stage": "merge-attestation",
    "timestamp": currentUtcTimestamp(),
    "headSha": loaded.subject.headSha,
    "subjectId": loaded.subject.subjectId,
    "prNumber": loaded.evidence.prNumber
  }
  if attestOutcome.verdict != atPassed:
    if not journalAttestRecord(record, attestOutcome, attestOutcome.verdict,
        Result[string, string](ok: false, err: ""), ""):
      logError("cert_cli", "attest: journal write failed (merge-attestation)")
    logError("cert_cli", "attest: FAILED — " & $attestOutcome.verdict & ": " & attestOutcome.reason)
    return 1
  # Publication is NOT part of the attest tier (ADR-0022 §4/D5): the attest
  # tier holds contents: read — the single trusted admission writer
  # (auto_merge.yml) publishes the minted certificate to the side-ref ledger
  # AFTER its own admission verdict, and the D9 operator path remains the
  # bootstrap/recovery publisher (ax cert ledger-append). Exit 0 = Verify(E,
  # M) PASS + certificate minted + journal recorded; the artifact handoff
  # transports the certificate to the publication authority.
  if not journalAttestRecord(record, attestOutcome, attestOutcome.verdict,
      Result[string, string](ok: true, value: ""),
      "publication delegated to the single trusted admission writer (ADR-0022 §4/D5)"):
    logError("cert_cli", "attest: journal write failed (merge-attestation)")
    return 1
  echo "[cert] Attest: PASS — " & attestOutcome.reason
  echo "[cert] Attest: certificate " & attestOutcome.certPath
  echo "[cert] Attest: publication delegated (single trusted writer appends post-verdict)"
  return 0

proc runLedgerAppendCli(args: seq[string]): int {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## usage: ax cert ledger-append [--provenance <text>] <certPath> — append one
  ## subject-continuity certificate to the side-ref ledger (FF-only CAS) and
  ## journal it. --provenance (DEBT#464 S4) is OPTIONAL and appends
  ## certificate-side provenance to the ledger commit message (M, run_id,
  ## run_attempt, artifact identity, witness digest) — the certificate
  ## representation itself never carries it (plan v12 identity separation).
  ## Default behaviour (no flag) is unchanged: legacy callers are unaffected.
  var provenance = ""
  var positional: seq[string] = @[]
  var i = 0
  while i < args.len:
    if args[i] == "--provenance":
      if i + 1 >= args.len:
        logInfo("cert_cli", "ledger-append: --provenance requires a value")
        return 1
      provenance = args[i + 1]
      inc i
    else:
      positional.add(args[i])
    inc i
  if positional.len != 1:
    logInfo("cert_cli", "Usage: ax cert ledger-append [--provenance <text>] <certPath>")
    return 1
  let certPath = positional[0]
  let token = ledgerToken()
  if token.len == 0:
    logError("cert_cli", "ledger-append: GITHUB_TOKEN not set (fail-closed)")
    return 1
  var appendOutcome: Result[string, string]
  try:
    appendOutcome = appendCertificate(liveLedgerTransport(token), ledgerRepo(), certPath,
      commitProvenance = provenance)
  except Exception as e:
    appendOutcome = Result[string, string](ok: false, err: "ledger transport raised: " & e.msg)
  if appendOutcome.isErr:
    logError("cert_cli", "ledger-append: " & appendOutcome.error)
    return 1
  let record = %*{
    "stage": "ledger-append",
    "timestamp": currentUtcTimestamp(),
    "certPath": certPath,
    "repo": ledgerRepo(),
    "ledgerTip": appendOutcome.get
  }
  if provenance.len > 0:
    record["provenance"] = %provenance
  if not journalCertStage("ledger-append", record):
    logError("cert_cli", "ledger-append: journal write failed")
    return 1
  echo "[cert] Ledger append: OK — tip " & appendOutcome.get
  return 0

proc runLedgerListCli(args: seq[string]): int {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## usage: ax cert ledger-list — read the side ref and list certificate ids
  ## (the Phase 5/5b continuity consumption surface).
  if args.len != 0:
    logInfo("cert_cli", "Usage: ax cert ledger-list")
    return 1
  let token = ledgerToken()
  if token.len == 0:
    logError("cert_cli", "ledger-list: GITHUB_TOKEN not set (fail-closed)")
    return 1
  var idsOutcome: Result[seq[string], string]
  try:
    idsOutcome = listLedgerCertIds(liveLedgerTransport(token), ledgerRepo())
  except Exception as e:
    idsOutcome = Result[seq[string], string](ok: false, err: "ledger transport raised: " & e.msg)
  if idsOutcome.isErr:
    logError("cert_cli", "ledger-list: " & idsOutcome.error)
    return 1
  let ids = idsOutcome.get
  for id in ids:
    echo id
  echo "[cert] Ledger entries: " & $ids.len
  return 0

# ---------------------------------------------------------------------------
# D6 + CAS reconciliation — `ax cert ledger-verify` (plan Phase 1 item 5)
# ---------------------------------------------------------------------------
## `ledger-verify` implements the D6 idempotency predicate (A): the ledger
## record for the certificate's subjectId must be a VALID authority for the
## SAME logical evidence chain — NOT mere key membership. The chain
## (plan D6 A: same logical evidence → same evidenceDigest → same wire → same
## subjectId) makes a consistent record the exactly-once proof: an earlier
## publish of the same evidence already holds the authority, so the re-run
## appends 0. The record is consistent iff:
##   record.subjectId == cert.subjectId         (the key — ledgerCertId,
##     a corrupt entry never matches)
##   ∧ record.baseSha == cert.baseSha ∧ record.headSha == cert.headSha
##     (same candidate B/H)
##   ∧ record.certTree == cert.certTree         (cert.certTree == re-derived
##     tree(mergeSha), bound at prepare steps (3b)/(4); the record must carry
##     the same re-derived merge-candidate tree — plan D6 A second conjunct)
##   ∧ record Ed25519 attestation verifies      (canonical RFC 8785 bytes —
##     structural closure; a tampered record fails)
##   ∧ cert Ed25519 attestation verifies        ([X] 4 signature/closure of
##     the publication candidate itself)
## Witness digest는 run-scoped — 교차 런 정체성으로 사용하지 않는다 (plan D6 A).
## Exit 0 = (A) HOLDS (reconciliation PASS — append count 0); any deviation =
## fail-closed (exit 1, caller refuses both append and skip).

proc ledgerRecordConsistentWith*(cert, record: JsonNode): Result[void, string] {.raises: [].} =
  ## Pure (A) predicate — deterministic, raises-free; see the section header.
  let certId = ledgerCertId(cert)
  if certId.isErr:
    return err("ledger-record consistency: " & certId.error)
  let recId = ledgerCertId(record)
  if recId.isErr:
    return err("ledger-record consistency: record is not a subject-continuity certificate: " & recId.error)
  if recId.get != certId.get:
    return err("ledger-record consistency: record subjectId " & recId.get[0 ..< 12] &
      " != cert subjectId " & certId.get[0 ..< 12] & " (fail-closed — record is a different authority)")
  for field in ["baseSha", "headSha", "certTree"]:
    let rv = record.getOrDefault(field).getStr("")
    let cv = cert.getOrDefault(field).getStr("")
    if cv.len == 0:
      return err("ledger-record consistency: cert '" & field & "' missing — mint-path certificate must carry it (fail-closed)")
    if rv.len == 0:
      return err("ledger-record consistency: record '" & field & "' missing (fail-closed)")
    if rv != cv:
      return err("ledger-record consistency: record " & field & " '" & rv[0 ..< min(rv.len, 12)] &
        "' != cert " & field & " '" & cv[0 ..< min(cv.len, 12)] & "' (fail-closed)")
  let recAtt = verifyCertificateAttestation(record)
  if recAtt.isErr:
    return err("ledger-record consistency: record Ed25519 attestation invalid — tampered/corrupt record (fail-closed)")
  let certAtt = verifyCertificateAttestation(cert)
  if certAtt.isErr:
    return err("ledger-record consistency: cert Ed25519 attestation invalid (fail-closed)")
  Result[void, string](ok: true)

proc runLedgerVerifyCli(args: seq[string]): int {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## usage: ax cert ledger-verify <certPath> — D6 (A) idempotency predicate.
  ## Exit 0 = the ledger record for cert.subjectId is a valid authority for
  ## the same logical evidence (reconciliation PASS — the publish appends 0).
  ## Non-zero = missing record, or present-but-inconsistent (mismatched
  ## subjectId/baseSha/headSha/certTree, invalid signature) → fail-closed: the
  ## caller must neither skip an append onto an inconsistent ledger nor mint a
  ## second authority beside a corrupt record.
  if args.len != 1:
    logInfo("cert_cli", "Usage: ax cert ledger-verify <certPath>")
    return 1
  let certPath = args[0]
  let token = ledgerToken()
  if token.len == 0:
    logError("cert_cli", "ledger-verify: GITHUB_TOKEN not set — ledger read refused (fail-closed)")
    return 1
  if not fileExists(certPath):
    logError("cert_cli", "ledger-verify: certificate file not found: " & certPath & " (fail-closed)")
    return 1
  var node: JsonNode
  try:
    node = parseJson(readFile(certPath))
  except CatchableError as e:
    logError("cert_cli", "ledger-verify: certificate unreadable: " & e.msg & " (fail-closed)")
    return 1
  let certIdRes = ledgerCertId(node)
  if certIdRes.isErr:
    logError("cert_cli", "ledger-verify: " & certIdRes.error)
    return 1
  var recordOutcome: Result[JsonNode, string]
  try:
    recordOutcome = downloadLedgerCertificate(liveLedgerTransport(token),
      ledgerRepo(), certIdRes.get)
  except Exception as e:
    recordOutcome = Result[JsonNode, string](ok: false,
      err: "ledger transport raised: " & e.msg)
  if recordOutcome.isErr:
    logError("cert_cli", "ledger-verify: no verifiable ledger record for subjectId " &
      certIdRes.get[0 ..< 12] & ": " & recordOutcome.error & " (fail-closed)")
    return 1
  let consistent = ledgerRecordConsistentWith(node, recordOutcome.get)
  if consistent.isErr:
    logError("cert_cli", "ledger-verify: " & consistent.error)
    return 1
  echo "[cert] Ledger verify: OK — record for subjectId " & certIdRes.get[0 ..< 12] &
    " consistent (D6 (A) HOLDS — reconciliation PASS, append count 0)"
  return 0

# ---------------------------------------------------------------------------
# Continuity check — `ax cert continuity` (certification-continuity Phase 5b,
# contract §4.4 I-2 — the CHEAP post-merge check, NOT full L2)
# ---------------------------------------------------------------------------

## `runContinuityCli` runs the cheap post-merge continuity check: the observed
## main tip is compared EXACTLY against the certified M OID of a
## subject-continuity certificate (object-level, INV-1/INV-2), and the
## certificate itself is re-verified (structural closure + Ed25519 attestation
## — a continuity check against a tampered certificate fails). No kernel
## re-execution here: full-L2 backstop responsibility stays with the
## attestation chain and the nightly full verification (contract §7). The
## evidence record (stage merge-continuity) is journaled; exit 0 ONLY on
## ccPassed — every other verdict exits non-zero (fail-visible).

type ContinuityArgs = object
  mainSha: string
  certPath: string

func parseContinuityArgs(args: seq[string]): tuple[ok: bool; parsed: ContinuityArgs; err: string] {.raises: [].} =
  ## usage: ax cert continuity --main <sha> --cert <path> (fail-closed on
  ## malformed/unknown input).
  var parsed = ContinuityArgs(mainSha: "", certPath: "")
  var i = 0
  while i < args.len:
    if args[i] == "--main":
      if i + 1 >= args.len:
        return (ok: false, parsed: parsed, err: "--main requires a 40-hex OID")
      parsed.mainSha = args[i + 1].toLowerAscii()
      inc i
    elif args[i] == "--cert":
      if i + 1 >= args.len:
        return (ok: false, parsed: parsed, err: "--cert requires a path")
      parsed.certPath = args[i + 1]
      inc i
    else:
      return (ok: false, parsed: parsed, err: "unknown argument: " & args[i])
    inc i
  if parsed.mainSha.len != 40:
    return (ok: false, parsed: parsed, err: "usage: ax cert continuity --main <40-hex-oid> --cert <certPath>")
  for c in parsed.mainSha:
    if c notin {'0'..'9', 'a'..'f'}:
      return (ok: false, parsed: parsed, err: "--main must be a lowercase 40-hex git OID (fail-closed)")
  if parsed.certPath.len == 0:
    return (ok: false, parsed: parsed, err: "usage: ax cert continuity --main <sha> --cert <certPath>")
  (ok: true, parsed: parsed, err: "")

proc runContinuityCli(args: seq[string]): int {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let parsedRes = parseContinuityArgs(args)
  if not parsedRes.ok:
    logInfo("cert_cli", "continuity: " & parsedRes.err)
    return 1
  # Resolve the observed main shape at the I/O boundary: parent1 = <main>^1,
  # parent2 = <main>^2, headTreeOid = <parent2>^{tree}. A non-merge main
  # cannot resolve ^2 → parent2 = "" → the pure predicate maps it to
  # ccMismatch (fail-visible: the shape is the violation).
  let gitExe = findRealGit()
  let (p1Out, p1Code) = runGitEx(gitExe, "rev-parse " & parsedRes.parsed.mainSha & "^1")
  let (p2Out, p2Code) = runGitEx(gitExe, "rev-parse " & parsedRes.parsed.mainSha & "^2")
  let parent1 = if p1Code == 0: p1Out.strip() else: ""
  let parent2 = if p2Code == 0: p2Out.strip() else: ""
  var headTreeOid = ""
  if parent2.len == 40:
    let (treeOut, treeCode) = runGitEx(gitExe, "rev-parse " & parent2 & "^{tree}")
    if treeCode == 0:
      headTreeOid = treeOut.strip()
  let observed = MainShape(mainSha: parsedRes.parsed.mainSha, parent1: parent1,
    parent2: parent2, headTreeOid: headTreeOid)
  let detail = verifyContinuityCertDetailed(observed, parsedRes.parsed.certPath)
  let verdict = detail.verdict
  let record = %*{
    "stage": "merge-continuity",
    "timestamp": currentUtcTimestamp(),
    "mainSha": parsedRes.parsed.mainSha,
    "certPath": parsedRes.parsed.certPath,
    "verdict": $verdict,
    "reasonCode": continuityVerdictCode(verdict),
    "mergeShapeOk": detail.mergeShapeOk,
    "ancestryOk": detail.ancestryOk,
    "treeOk": detail.treeOk,
    "policyOk": detail.policyOk,
    "scopeOk": detail.scopeOk
  }
  if not journalCertStage("merge-continuity", record):
    logError("cert_cli", "continuity: journal write failed (merge-continuity)")
    return 1
  echo "[cert] Continuity: " & $verdict & " (" & continuityVerdictCode(verdict) & ") — main " &
    parsedRes.parsed.mainSha[0 ..< 12] & " vs certified M " &
    (if verdict == ccNoCert: "(no certificate)" else: "from " & parsedRes.parsed.certPath)
  if verdict == ccPassed:
    return 0
  logError("cert_cli", "continuity: " & continuityVerdictCode(verdict) &
    " — fail-visible (ccPassed required for exit 0)")
  return 1

proc runJudgmentPlanCli(args: seq[string]): int {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## usage: ax cert judgment-plan [--subject <name>] --decision <path>
  ## The plan stage of the Judgment CAS: resolve the reuse decision for ONE
  ## subject (default s1a — the landed wire) via a read-only ledger consult
  ## with fail-closed closure collection, and write the decision file the
  ## armed attest consumes. The decision is never wrong-directional: every
  ## unverifiable state resolves to EXECUTED (the subject's test runs)
  ## except unarmed OFF; only an internal error exits non-zero.
  var decisionPath = ""
  var subjectNameArg = "s1a"
  var i = 0
  while i < args.len:
    if args[i] == "--decision" and i + 1 < args.len:
      decisionPath = args[i + 1]
      inc i
    elif args[i] == "--subject" and i + 1 < args.len:
      subjectNameArg = args[i + 1]
      inc i
    else:
      logInfo("cert_cli", "Usage: ax cert judgment-plan [--subject <name>] --decision <path>")
      return 1
    inc i
  if decisionPath.len == 0:
    logInfo("cert_cli", "Usage: ax cert judgment-plan [--subject <name>] --decision <path>")
    return 1
  let subject = parseJudgmentSubject(subjectNameArg)
  if subject.isErr:
    logError("cert_cli", "judgment-plan: " & subject.error)
    return 1
  var plan: JudgmentPlan
  try:
    plan = planJudgmentCasForSubject(subject.get)
  except Exception as e:
    logError("cert_cli", "judgment-plan: plan raised: " & e.msg)
    return 1
  if plan.mode != jOff:
    let written =
      try: writeJudgmentDecisionFile(plan, decisionPath)
      except Exception as e:
        Result[string, string](ok: false, err: "decision write raised: " & e.msg)
    if written.isErr:
      logError("cert_cli", "judgment-plan: " & written.error)
      return 1
  echo planLogLine(plan)
  return 0

proc runJudgmentSubjectsCli(args: seq[string]): int {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## usage: ax cert judgment-subjects [--json]
  ## The read-only projection of the judgment subject SSOT: every subject
  ## name, in SSOT order. Pure — no side effects, no network, no state.
  ## `--json` emits the canonical `{"subjects":[...]}` wire; the default is
  ## one name per line.
  var asJson = false
  var i = 0
  while i < args.len:
    if args[i] == "--json":
      asJson = true
      inc i
    else:
      logInfo("cert_cli", "Usage: ax cert judgment-subjects [--json]")
      return 1
  if asJson:
    echo allJudgmentSubjectsJson()
  else:
    for s in allJudgmentSubjects():
      echo subjectName(s)
  return 0

proc runAttestationSubCli(cmd: string; args: seq[string]): int {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Node for the certification-continuity subcommands; keeps runCertCli's
  ## case dispatch small (attest / subject-register / ledger-append /
  ## ledger-list / continuity / judgment-plan / judgment-subjects).
  ## if/elif (not a case) so the file's case-branch OCP surface stays at its baseline.
  if cmd == "attest":
    runAttestCli(args)
  elif cmd == "subject-register":
    runSubjectRegisterCli(args)
  elif cmd == "ledger-append":
    runLedgerAppendCli(args)
  elif cmd == "ledger-verify":
    runLedgerVerifyCli(args)
  elif cmd == "continuity":
    runContinuityCli(args)
  elif cmd == "judgment-plan":
    runJudgmentPlanCli(args)
  elif cmd == "judgment-subjects":
    runJudgmentSubjectsCli(args)
  else:
    runLedgerListCli(args)

func parseCertVerifyArgs(args: seq[string]): tuple[certPath, projectRoot: string; kernelMode: bool; err: string] =
  ## `ax cert verify [--kernel] [--project <dir>] <path>` argument parser —
  ## pure; the caller owns logging and exit codes.
  const usage = "Usage: ax cert verify [--kernel] [--project <dir>] <path>"
  result = ("", "", false, "")
  var i = 1
  while i < args.len:
    if args[i] == "--kernel":
      result.kernelMode = true
    elif args[i] == "--project":
      if i + 1 >= args.len:
        return ("", "", false, usage)
      inc i
      result.projectRoot = args[i]
    elif args[i].len > 0 and args[i][0] == '-':
      return ("", "", false, "Unknown flag: " & args[i])
    elif result.certPath.len == 0:
      result.certPath = args[i]
    else:
      return ("", "", false, usage)
    inc i
  if result.certPath.len == 0:
    result.err = usage

proc runCertCli*(args: seq[string]): int =
  if args.len == 0:
    logInfo("cert_cli", "Usage: ax cert <command> [args]")
    logInfo("cert_cli", "Commands: show, verify [--kernel] <path>, export [--json], reissue-reference <path>, reconcile [--check|--apply] [--staged] [--cert <id|filename>], attest, subject-register, ledger-append, ledger-list, ledger-verify, continuity")
    return 1

  let cmd = args[0]
  # Certification-continuity subcommands live OUTSIDE the case dispatch
  # (if/elif) so the case-branch OCP surface stays at its anchored baseline.
  if cmd == "attest" or cmd == "subject-register" or cmd == "ledger-append" or cmd == "ledger-list" or cmd == "ledger-verify" or cmd == "continuity" or cmd == "judgment-plan" or cmd == "judgment-subjects":
    return runAttestationSubCli(cmd, args[1 .. ^1])
  case cmd
  of "show":
    return showCerts()
  of "verify":
    let parsed = parseCertVerifyArgs(args)
    if parsed.err.len > 0:
      logInfo("cert_cli", parsed.err)
      return 1
    return verifyCert(parsed.certPath, parsed.kernelMode, parsed.projectRoot)
  of "export":
    return exportCerts(args[1 .. ^1])
  of "reissue-reference":
    if args.len < 2:
      logInfo("cert_cli", "Usage: ax cert reissue-reference <path>")
      return 1
    let reissueResult = reissueReference(args[1])
    logInfo("cert_cli", reissueResult)
    if reissueResult.startsWith("reissue-reference error:"):
      return 1
    return 0
  of "reconcile":
    return reconcileCerts(args[1 .. ^1])
  else:
    logInfo("cert_cli", "Unknown cert subcommand: " & cmd)
    logInfo("cert_cli", "Commands: show, verify [--kernel] <path>, export [--json], reissue-reference <path>, reconcile [--check|--apply] [--staged] [--cert <id|filename>], attest, subject-register, ledger-append, ledger-list, ledger-verify, continuity")
    return 1
{.pop.}
