import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Kernel Re-execution (certification continuity contract — Phase 3).
##
## `ax cert verify --kernel` deep-verification basis: re-execute the pinned
## kernels on the certificate's embedded inputs — Lean (`lake env lean
## --threads=1` typecheck + `#print axioms` allowlist, contract INV-6) and
## Z3 (recorded smtlib2 under the rlimit-primary envelope, contract INV-10).
## run.conclusion and step census are explicitly NOT attestation evidence
## (INV-5): only a fresh kernel verdict counts.
##
## Fail-closed: any verdict other than krPassed → certificate not attested.
## The recorded smtlib2/leanSource artifacts were captured at certify time;
## re-execution re-runs them FRESH — a cached result from a previous run is
## never trusted.

import std/json
import std/os
import std/osproc
import std/strutils
import std/times
import core/axiom_pragmas
import core/crypto/hash_kernel
import core/results
import core/sync/sync_utils_process
import core/trusted/env_types
import core/trusted/solver_invocation
import core/types/z3_solver_config
import core/utils/repo_root
import core/trusted/stdlib_shield
import infrastructure/process_utils
import infrastructure/source_identity_cache
import verification/solver/z3_pool
import verification/verification_subject

when defined(posix):
  import std/posix

axiomIoBoundary()

# ─── Verdicts ────────────────────────────────────────────────────────────────

type KernelVerdict* = enum
  krPassed          ## kernel re-execution passed (lean: typecheck + allowlisted axioms; z3: fresh unsat)
  krAxiomViolation  ## observed proof depends on an axiom outside the allowlist
  krSorry           ## observed proof depends on sorry (sorryAx family) — kernel soundness violation
  krCompileError    ## lean artifact failed kernel typecheck
  krTimeout         ## kernel re-execution exceeded its wall-clock budget and was killed
  krZ3Mismatch      ## z3 re-execution did not yield unsat
  krZ3Error         ## z3 binary missing / not checksum-pinned — fail-closed
  krMissingInput    ## certificate carries no leanSource/smtlib2 evidence to re-execute
  krInternalError   ## unexpected internal failure during re-execution

const
  defaultLeanReexecTimeoutMs* = 120_000  ## matches canonicalLeanKernelCheck budget
  defaultZ3ReexecTimeoutMs* = 120_000
  z3BinaryChecksumsPolicyPath* = "data/policy/z3_binary_checksums.json"
  kernelReexecSentinel* = "AXIOM_KERNEL_REEXEC_FIN"

# ─── Pure allowlist / verdict logic ──────────────────────────────────────────

func axiomAllowlist*(): seq[string] {.raises: [].} =
  ## INV-6 allowlist — the ONLY axiom names a kernel-verified proof may depend on.
  @["propext", "Classical.choice", "Quot.sound", "funext"]

func isAxiomAllowed*(axiomName: string): bool {.raises: [].} =
  ## Deny-first: any name containing a sorry/trustCompiler/native_decide marker
  ## is rejected regardless of allowlist shape; everything else must be an
  ## EXACT allowlist member. Empty names never pass (fail-closed).
  if axiomName.len == 0:
    return false
  let lower = axiomName.toLowerAscii()
  if "sorry" in lower:
    return false
  if "trustcompiler" in lower:
    return false
  if "native_decide" in lower:
    return false
  for allowed in axiomAllowlist():
    if axiomName == allowed:
      return true
  false

const verdictReasons: array[KernelVerdict, string] = [
  "kernel re-execution passed",
  "observed proof depends on an axiom outside the allowlist {propext, Classical.choice, Quot.sound, funext}",
  "observed proof depends on sorry (sorryAx family) — kernel soundness violation",
  "lean artifact failed kernel typecheck",
  "kernel re-execution timed out and was killed",
  "z3 re-execution did not yield unsat — recorded query no longer proves the claim",
  "z3 binary missing or failing the pinned checksum policy — fail-closed",
  "certificate carries no leanSource/smtlib2 evidence to re-execute",
  "internal error during kernel re-execution"
]

func kernelVerdictReason*(v: KernelVerdict): string {.raises: [].} =
  ## Precise reason string for a verdict — the CLI surfaces this verbatim.
  verdictReasons[v]

# ─── Lean `#print axioms` observation parsing (pure) ─────────────────────────

type AxiomPrintObservation* = object
  names*: seq[string]       ## observed axiom names (union across #print commands)
  observedAny*: bool        ## true iff at least one result set was parsed

func parsePrintAxiomsObservations*(output: string): AxiomPrintObservation {.raises: [].} =
  ## Parses Lean `#print axioms` result text (toolchain-pinned 4.33.0 format):
  ##   '<thm>' depends on axioms: [ax1, ax2]
  ##   '<thm>' does not depend on any axioms
  ## A long bracket list may continue on following lines — the parser
  ## accumulates until `]` closes. `does not depend on any axioms` records an
  ## observed-but-empty set (kernel-pure). A `depends on axioms:` marker with
  ## no parseable bracket is NOT an observation (fail-closed: unobservable
  ## axiom set never counts as pass).
  result = AxiomPrintObservation(names: @[], observedAny: false)
  var pending = ""
  for rawLine in output.splitLines():
    if "does not depend on any axioms" in rawLine:
      result.observedAny = true
      continue
    if pending.len == 0:
      let marker = rawLine.find("depends on axioms:")
      if marker < 0:
        continue
      pending = rawLine[min(marker + "depends on axioms:".len, rawLine.high) .. ^1]
    else:
      pending.add("\n" & rawLine)
    let openIdx = pending.find('[')
    if openIdx < 0:
      pending = ""
      continue
    let openRest = pending[openIdx + 1 .. ^1]
    let closeIdx = openRest.find(']')
    if closeIdx < 0:
      continue  # bracket list continues on a later line
    result.observedAny = true
    for tok in openRest[0 ..< closeIdx].split(','):
      let t = tok.strip()
      if t.len > 0 and t notin result.names:
        result.names.add(t)
    pending = ""

func evaluateObservedAxioms*(observation: AxiomPrintObservation): KernelVerdict {.raises: [].} =
  ## INV-6 composition: no observation → krMissingInput (cannot attest);
  ## empty observed set → krPassed (kernel-pure); any unallowed name →
  ## krSorry (sorry family) or krAxiomViolation (everything else).
  if not observation.observedAny:
    return krMissingInput
  for name in observation.names:
    if isAxiomAllowed(name):
      continue
    if "sorry" in name.toLowerAscii():
      return krSorry
    return krAxiomViolation
  krPassed

func firstDeclaredName*(leanSource: string): string {.raises: [].} =
  ## First `theorem <name>` / `def <name>` declaration — the target for an
  ## appended `#print axioms <name>` observation line. Empty if none.
  for line in leanSource.splitLines():
    let stripped = line.strip()
    if stripped.startsWith("theorem ") or stripped.startsWith("def "):
      let rest = stripped[(if stripped.startsWith("theorem "): "theorem ".len else: "def ".len) .. ^1]
      let nameEnd = rest.find({' ', ':', '(', '\t'})
      if nameEnd < 0:
        return rest
      if nameEnd == 0:
        return ""
      return rest[0 ..< nameEnd]
  ""

# ─── Z3 verdict composition (pure) ───────────────────────────────────────────

func z3ResultVerdict*(exitCode: int; timedOut: bool; output: string): KernelVerdict {.raises: [].} =
  ## INV-10 fail-closed mapping: fresh run must exit cleanly AND answer unsat.
  ## Anything else — timeout, non-zero exit, sat/unknown — is a mismatch.
  ##
  ## The ⟨error_response⟩ form is rejected here rather than being left to the
  ## exit code alone to catch: the exit status is a whole-run property that says
  ## nothing about WHICH command was refused, and Z3 answers a rejected command
  ## with `(error …)` and then keeps answering later ones. Routing both rules
  ## through one detector keeps this path from reading a tool failure as a
  ## kernel proof — which for a certificate re-execution would be the most
  ## consequential misreading available (INV-5: only a fresh kernel verdict counts).
  if timedOut:
    return krTimeout
  if solverResponse(output, exitCode) == srUnsat:
    return krPassed
  krZ3Mismatch

func composeKernelVerdict*(
  leanVerdict, z3Verdict: KernelVerdict;
  leanPresent, z3Present: bool
): KernelVerdict {.raises: [].} =
  ## Overall `--kernel` verdict: every evidence class embedded in the cert
  ## must re-execute to krPassed. No embedded evidence at all → fail-closed
  ## krMissingInput (nothing to attest). The first failing class decides.
  if not leanPresent and not z3Present:
    return krMissingInput
  if leanPresent and leanVerdict != krPassed:
    return leanVerdict
  if z3Present and z3Verdict != krPassed:
    return z3Verdict
  krPassed

# ─── Loader (fail-closed, never crashes on malformed input) ──────────────────

proc loadCertJsonForReexecution*(certPath: string): Result[JsonNode, string] {.
  raises: [CatchableError], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Fail-closed certificate loading: unreadable file or malformed JSON →
  ## err (never crash). The structural verifier already ran at this point;
  ## this is the re-execution input extraction path.
  let text =
    try: readFile(certPath)
    except CatchableError as e: return err("certificate file unreadable: " & e.msg)
  if text.len == 0:
    return err("certificate file is empty")
  var node: JsonNode
  try:
    node = parseJson(text)
  except CatchableError as e:
    return err("malformed certificate JSON: " & e.msg)
  if node.isNil or node.kind != JObject:
    return err("certificate is not a JSON object")
  ok(node)

# ─── Z3 binary checksum pinning (INV-10) ─────────────────────────────────────

const
  z3BinaryIdentitySchema* = "axiom-z3-binary-identity/1"
    ## Stat-identity cache schema tag — a foreign/stale schema is discarded.
  z3BinaryIdentityCacheRelPath* = ".axiom/cache/z3_binary_identity.json"
    ## Z3-binary digest acceleration cache (project-root relative).

type
  Z3BinaryIdentityStats* = object
    ## Acceleration observability seam (SourceIdentityStats twin): reused =
    ## stat-identity cache HIT, rehashed = full read+hash, racy = identity
    ## matched but the git racy-git rule forced a rehash.
    reused*, rehashed*, racy*: int

  Z3IdentityCacheEntry = object
    path: string
    ident: StatIdentity
    digest: string
    writtenAtNs: int64

proc z3IdentityNowNs(): int64 {.raises: [].} =
  let t = getTime()
  t.toUnix * 1_000_000_000'i64 + t.nanosecond.int64

when defined(posix):
  proc z3IdentityCacheFileTrusted(path: string): bool {.raises: [].} =
    ## source_identity_cache.cacheFileTrusted twin: only a regular file owned
    ## by the effective user and not group/other-writable is read; anything
    ## else is treated as absent (recompute).
    var st: Stat
    if lstat(path.cstring, st) != 0:
      return false
    if (int64(st.st_mode) and int64(S_IFMT)) != int64(S_IFREG):
      return false
    if st.st_uid != geteuid():
      return false
    if (int64(st.st_mode) and (int64(S_IWGRP) or int64(S_IWOTH))) != 0:
      return false
    true

proc loadZ3IdentityCache(path: string): Z3IdentityCacheEntry {.raises: [].} =
  ## Fail-closed loader: unreadable/invalid/corrupt/untrusted cache or a
  ## foreign schema → default entry (miss → recompute). Numbers are stored as
  ## strings so 64-bit fields survive every JSON number precision boundary.
  when defined(posix):
    if not fileExists(path) or not z3IdentityCacheFileTrusted(path):
      return
    try:
      let node = parseFile(path)
      if node{"schema"}.getStr("") != z3BinaryIdentitySchema:
        return
      result.writtenAtNs = parseBiggestInt(node{"writtenAtNs"}.getStr("0"))
      result.path = node{"path"}.getStr("")
      result.digest = node{"digest"}.getStr("")
      result.ident = StatIdentity(
        dev: parseBiggestInt(node{"dev"}.getStr("0")),
        ino: parseBiggestInt(node{"ino"}.getStr("0")),
        size: parseBiggestInt(node{"size"}.getStr("0")),
        mtimeNs: parseBiggestInt(node{"mtimeNs"}.getStr("0")),
        ctimeNs: parseBiggestInt(node{"ctimeNs"}.getStr("0")),
        mode: parseBiggestInt(node{"mode"}.getStr("0")),
        kind: node{"kind"}.getStr(""))
    except CatchableError:
      result = Z3IdentityCacheEntry()

proc saveZ3IdentityCache(path: string; entry: Z3IdentityCacheEntry) {.raises: [].} =
  ## Best-effort atomic write (PID-unique tmp + chmod 0600 + safeMoveFile).
  ## The tmp file lands in the destination directory, so the move is an
  ## atomic same-filesystem rename(2) — the atomicWriteFile precedent.
  ## Failure is ignored — the cache is acceleration ONLY.
  let tmpPath = path & ".tmp." & $getCurrentProcessId()
  try:
    let dir = parentDir(path)
    if not dirExists(dir):
      createDir(dir)
    let body = %*{
      "schema": z3BinaryIdentitySchema,
      "writtenAtNs": $entry.writtenAtNs,
      "path": entry.path,
      "dev": $entry.ident.dev,
      "ino": $entry.ident.ino,
      "size": $entry.ident.size,
      "mtimeNs": $entry.ident.mtimeNs,
      "ctimeNs": $entry.ident.ctimeNs,
      "mode": $entry.ident.mode,
      "kind": entry.ident.kind,
      "digest": entry.digest}
    writeFile(tmpPath, $body)
    when defined(posix):
      discard chmod(tmpPath.cstring, 0o600)
    safeMoveFile(tmpPath, path)
  except CatchableError: # axiom:best-effort(z3 identity cache write is speed-only; the digest is always recomputable from the live binary)
    discard tryRemoveFile(tmpPath)

proc readZ3BinaryStable(z3Bin: string; first: StatIdentity):
    tuple[digest: string, ident: StatIdentity] {.
    raises: [CatchableError], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read, then re-stat (source_identity_cache.readAndDigestStable twin): a
  ## mismatch means the binary changed during the read — retry once, then
  ## fail closed (never return a digest of an unstable file).
  var ident = first
  for _ in 0 .. 1:
    let content = readFile(z3Bin)
    let after = statIdentity(z3Bin)
    if sameIdentity(ident, after):
      return (sha256Hex(content), after)
    ident = after
  raise newException(OSError, "z3 binary changed while hashing: " & z3Bin)

proc z3BinaryDigestWithStats*(z3Bin: string; projectRoot: string;
                              stats: var Z3BinaryIdentityStats): string {.
    raises: [CatchableError], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## sha256 of the Z3 binary bytes — the INV-10 verdict input, with a
  ## stat-identity acceleration cache (the source_identity_cache pattern).
  ## The OS kernel already knows whether the bytes changed
  ## (dev/ino/size/mtime_ns/ctime_ns/mode), so a cached digest is reused ONLY
  ## when the entry's path and full stat identity match AND the entry is not
  ## racily clean (git racy-git rule, second granularity — the
  ## source_identity_cache.isRacy predicate). Every anomaly — unreadable/
  ## invalid/corrupt cache, untrusted cache file, non-64-hex cached digest,
  ## path change, or a non-posix platform without a trustworthy stat identity
  ## — recomputes from the live bytes; an unreadable binary returns ""
  ## (fail-closed). The cache is acceleration ONLY: never evidence, never a
  ## verdict input beyond supplying the digest the live bytes would produce;
  ## same-UID processes are INSIDE the trust boundary (DEBT#524 — local
  ## single-writer boundary, no forgery defense claimed; the policy
  ## comparison below stays fail-closed regardless of the digest source).
  when not defined(posix):
    inc stats.rehashed
    try:
      return sha256Hex(readFile(z3Bin))
    except CatchableError:
      return ""
  else:
    let cachePath = projectRoot / z3BinaryIdentityCacheRelPath
    let cached = loadZ3IdentityCache(cachePath)
    var first: StatIdentity
    var statOk = true
    try:
      first = statIdentity(z3Bin)
    except CatchableError:
      statOk = false
    if not statOk:
      # unstatable binary: the plain read below fails -> "" (fail-closed)
      inc stats.rehashed
      try:
        return sha256Hex(readFile(z3Bin))
      except CatchableError:
        return ""
    if cached.path == z3Bin and sameIdentity(cached.ident, first) and
        isHexOfLen(cached.digest, 64):
      if not isRacy(cached.ident, cached.writtenAtNs):
        inc stats.reused
        return cached.digest
      inc stats.racy
    try:
      let stable = readZ3BinaryStable(z3Bin, first)
      inc stats.rehashed
      saveZ3IdentityCache(cachePath, Z3IdentityCacheEntry(
        path: z3Bin, ident: stable.ident, digest: stable.digest,
        writtenAtNs: z3IdentityNowNs()))
      stable.digest
    except CatchableError:
      ""

proc z3BinaryChecksumAcceptedWithStats*(z3Bin: string; projectRoot: string;
                                        stats: var Z3BinaryIdentityStats): bool {.
    raises: [CatchableError], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Runtime pinning: the ACTUAL z3 binary's sha256 must match an entry in
  ## data/policy/z3_binary_checksums.json. Missing policy file, unreadable
  ## binary, or no matching checksum → false (fail-closed, never pass). The
  ## digest comes from z3BinaryDigestWithStats (stat-identity-cached), but the
  ## pin comparison itself is UNCHANGED — the verdict is bit-identical to the
  ## full-rehash path and any digest mismatch still returns false; a cache
  ## anomaly recomputes, it can never manufacture a pass.
  let root = if projectRoot.len > 0: projectRoot else: resolveRepoRoot()
  let policyText =
    try: readFile(root / z3BinaryChecksumsPolicyPath)
    except CatchableError: ""
  if policyText.len == 0:
    return false
  var policy: JsonNode
  try:
    policy = parseJson(policyText)
  except CatchableError:
    return false
  if policy.isNil or policy.kind != JObject:
    return false
  let versions = policy.getOrDefault("versions")
  if versions.isNil or versions.kind != JObject:
    return false
  let actual = z3BinaryDigestWithStats(z3Bin, root, stats)
  if actual.len == 0:
    return false
  for _, recorded in versions.pairs:
    if recorded.kind == JString and recorded.getStr("") == actual:
      return true
  false

proc z3BinaryChecksumAccepted*(z3Bin: string; projectRoot: string = ""): bool {.
    raises: [CatchableError], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var stats: Z3BinaryIdentityStats
  z3BinaryChecksumAcceptedWithStats(z3Bin, projectRoot, stats)

# ─── Lean kernel re-execution ────────────────────────────────────────────────

proc reexecuteLean*(certJson: JsonNode; leanExe: string; timeoutMs: int): KernelVerdict {.
  raises: [CatchableError], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Re-executes the certificate's embedded leanSource on the pinned Lean
  ## kernel: write artifact to a temp file (QUIRK(runGitEx-argv-flattening):
  ## Lean SOURCE IS NEVER INLINED — whitespace/newline payloads must travel
  ## via the file channel), run `lake env lean --threads=1 <file>`, then gate
  ## the observed `#print axioms` set on the INV-6 allowlist.
  ##
  ## If the artifact does not already embed `#print axioms` commands, the
  ## command is appended for the first declared theorem/def so the axiom set
  ## is OBSERVED from the fresh run — a missing observation is fail-closed
  ## krMissingInput, never a pass.
  if certJson.isNil or certJson.kind != JObject:
    return krMissingInput
  let leanSource = certJson.getOrDefault("leanSource").getStr("")
  if leanSource.len == 0:
    return krMissingInput
  let artifactSource =
    if "#print axioms" in leanSource:
      leanSource
    else:
      let target = firstDeclaredName(leanSource)
      if target.len == 0:
        return krMissingInput
      leanSource & "\n#print axioms " & target & "\n"
  let cmdBase =
    if leanExe.len > 0:
      leanExe
    else:
      let envCmd = getAxiomEnv(evLeanCmd, "")
      if envCmd.len > 0: envCmd else: "lake env lean"
  var artifactPath = ""
  var output = ""
  var exitCode = -1
  try:
    artifactPath = getTempDir() / ("axiom_kreexec_" & sha256Hex(artifactSource) & ".lean")
    writeFile(artifactPath, artifactSource)
    (output, exitCode) = execCmdWithTimeout(
      cmdBase & " --threads=1 " & quoteShell(artifactPath),
      timeoutMs = timeoutMs)
  except CatchableError:
    if artifactPath.len > 0:
      try: removeFile(artifactPath)
      except CatchableError: discard  # axiom:best-effort(temp artifact cleanup)
    return krInternalError
  if artifactPath.len > 0:
    try: removeFile(artifactPath)
    except CatchableError: discard  # axiom:best-effort(temp artifact cleanup)
  if exitCode == -1:
    return krTimeout
  if exitCode != 0:
    return krCompileError
  evaluateObservedAxioms(parsePrintAxiomsObservations(output))

# ─── Z3 re-execution ─────────────────────────────────────────────────────────

proc reexecuteZ3*(certJson: JsonNode; z3Path: string; timeoutMs: int): KernelVerdict {.
  raises: [CatchableError], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Re-executes the certificate's recorded smtlib2 on a FRESH z3 process
  ## (never a pool worker, never a cached result — INV-10). The query is
  ## wrapped in the canonical rlimit-primary envelope (buildZ3QueryEnvelope —
  ## the pinned determinism option set from core/trusted/solver_invocation:
  ## non-zero random seeds, :rlimit budget, :timeout liveness net), written to
  ## a temp file, and the fresh verdict must be unsat. The resolved binary must
  ## match the pinned checksum policy (missing/unpinned binary → krZ3Error,
  ## fail-closed).
  if certJson.isNil or certJson.kind != JObject:
    return krMissingInput
  let smtlib2 = certJson.getOrDefault("smtlib2").getStr("")
  if smtlib2.len == 0:
    return krMissingInput
  let z3Bin = if z3Path.len > 0: z3Path else: resolveZ3Path()
  if z3Bin.len == 0 or not fileExists(z3Bin):
    return krZ3Error
  if not z3BinaryChecksumAccepted(z3Bin):
    return krZ3Error
  var envelopeDigest = ""
  let payload = buildZ3QueryEnvelope(
    smtlib2, timeoutMs, kernelReexecSentinel,
    canonicalEnvelopeDigest = envelopeDigest)
  var queryPath = ""
  try:
    queryPath = getTempDir() / ("axiom_z3reexec_" & sha256Hex(smtlib2) & ".smt2")
    writeFile(queryPath, payload)
    let res = runProcessWithTimeout(z3Bin, @["-smt2", queryPath], timeoutMs)
    if queryPath.len > 0:
      try: removeFile(queryPath)
      except CatchableError: discard  # axiom:best-effort(temp artifact cleanup)
    z3ResultVerdict(res.exitCode, res.timedOut, res.output)
  except CatchableError:
    if queryPath.len > 0:
      try: removeFile(queryPath)
      except CatchableError: discard  # axiom:best-effort(temp artifact cleanup)
    krZ3Error

# ─── Independent Lean checker deep-check (certification-continuity Phase 6) ─

type LeanCheckerVerdict* = enum
  lcPassed   ## leanchecker re-validation of a FRESH compile of the artifact passed
  lcMismatch ## checker present and ran, but re-validation failed (fail-closed)
  lcSkipped  ## checker binary absent (or no artifact) — deep check skipped LOUDLY (additive)

func leanCheckerVerdictReason*(v: LeanCheckerVerdict): string =
  case v
  of lcPassed: "leanchecker re-validation passed"
  of lcMismatch: "leanchecker re-validation MISMATCH — independent kernel-level re-check failed"
  of lcSkipped: "leanchecker binary not found — independent deep check skipped (additive)"

proc resolveLeanChecker(explicit: string): string =
  ## AXIOM_LEANCHECKER_CMD env override > PATH lookup (the `leanchecker`
  ## binary ships with every elan-installed Lean 4 toolchain). "" when absent.
  if explicit.len > 0:
    return explicit
  let envCmd = getEnv("AXIOM_LEANCHECKER_CMD", "")
  if envCmd.len > 0:
    return envCmd
  try:
    result = findExe("leanchecker")
  except OSError:
    discard  # axiom:best-effort(checker lookup best-effort — absent → lcSkipped)

proc leanCheckerStagingDir(): string {.raises: [].} =
  ## Dedicated user-owned staging dir: leanchecker ENUMERATES every directory
  ## on LEAN_PATH, and shared temp roots carry inaccessible entries (e.g.
  ## systemd-private service dirs) that abort the scan with EACCES.
  getTempDir() / "axiom_lcheck"

proc compileLeanArtifact(leanSource, cmdBase, dir, leanPath, oleanPath: string;
                         timeoutMs: int): bool {.
  raises: [CatchableError], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Fresh compile of the certificate artifact into <dir>/<Mod>.olean. Runs in
  ## the temp dir: from the repo root, `lake env lean` enforces a project-root
  ## confinement that refuses out-of-tree artifacts (in root dir) — the temp
  ## dir is root-free, so the pinned lean compiles freely.
  try:
    writeFile(leanPath, leanSource)
    let (_, code) = execCmdWithTimeout(
      cmdBase & " --threads=1 -o " & quoteShell(oleanPath) & " " & quoteShell(leanPath),
      workingDir = dir,
      timeoutMs = timeoutMs)
    result = code == 0 and fileExists(oleanPath)
  except CatchableError:
    result = false

proc leanCheckerSearchPath(realChecker, dir: string): string {.
  raises: [CatchableError], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## LEAN_PATH for the checker = temp dir (fresh artifact) + the toolchain's
  ## library search path as reported by `lake env` in the working dir (std
  ## libs; elan `leanchecker` shims are copies, NOT symlinks, so the checker's
  ## own path cannot locate the toolchain — `lake env` is the canonical source).
  var basePath = ""
  let (envOut, _) = execCmdWithTimeout("lake env", workingDir = dir, timeoutMs = 30_000)
  for line in envOut.splitLines:
    if line.startsWith("LEAN_PATH="):
      basePath = line["LEAN_PATH=".len .. ^1]
      break
  if basePath.len == 0:
    # fallback: checker's own toolchain root (real elan symlink case)
    let sysroot = parentDir(parentDir(realChecker))
    if dirExists(sysroot / "lib" / "lean"):
      basePath = sysroot / "lib" / "lean"
  result = dir
  if basePath.len > 0:
    result = result & ":" & basePath

proc checkLeanWithLeanChecker*(certJson: JsonNode; leanExe: string = "";
                               checkerExe: string = ""; projectRoot: string = "";
                               timeoutMs: int = defaultLeanReexecTimeoutMs): LeanCheckerVerdict {.
  raises: [CatchableError], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Phase 6 optional deep check: lean4checker's `leanchecker` re-validates the
  ## certificate's leanSource compiled FRESH to a temp .olean (never a cached
  ## build — same rule as reexecuteLean). ADDITIVE: absent checker binary →
  ## lcSkipped (caller prints a loud SKIP and continues); present + failed →
  ## lcMismatch (fail-closed). Honest scope (contract §8.3): leanchecker is an
  ## independently-implemented CHECKER over the pinned Lean kernel — "not an
  ## external verifier" — so this is artifact/build-integrity re-validation,
  ## not a second kernel.
  ##
  ## Flow: compile leanSource with the pinned lean (`-o <temp>/<Mod>.olean`),
  ## then `env LEAN_PATH=<temp>:<lake-env LEAN_PATH> <checker> --fresh <Mod>`.
  ## Corruption/hangs surface as exit!=0 or a wall-clock timeout — both
  ## lcMismatch (a poisoned artifact cannot pass).
  if certJson.isNil or certJson.kind != JObject:
    return lcSkipped
  let leanSource = certJson.getOrDefault("leanSource").getStr("")
  if leanSource.len == 0:
    return lcSkipped  # no artifact to double-check; the mandatory path verdicts it
  let checker = resolveLeanChecker(checkerExe)
  if checker.len == 0 or not fileExists(checker):
    return lcSkipped
  let cmdBase =
    if leanExe.len > 0:
      leanExe
    else:
      let envCmd = getAxiomEnv(evLeanCmd, "")
      if envCmd.len > 0: envCmd else: "lake env lean"
  let moduleName = "AxiomLcheck" & sha256Hex(leanSource)
  let dir = leanCheckerStagingDir()
  try:
    if not dirExists(dir):
      createDir(dir)
  except CatchableError:
    return lcMismatch  # cannot stage the artifact — fail-closed
  let leanPath = dir / moduleName & ".lean"
  let oleanPath = dir / moduleName & ".olean"
  if not compileLeanArtifact(leanSource, cmdBase, dir, leanPath, oleanPath, timeoutMs):
    try: removeFile(leanPath)
    except CatchableError: discard  # axiom:best-effort(temp artifact cleanup)
    return lcMismatch
  let realChecker =
    try: expandFilename(checker)
    except OSError: checker  # axiom:best-effort(symlink resolution failure — run the resolved path)
  var exitCode = -1
  try:
    let (_, code) = execCmdWithTimeout(
      "env LEAN_PATH=" & quoteShell(leanCheckerSearchPath(realChecker, dir)) &
        " " & quoteShell(realChecker) & " --fresh " & moduleName,
      workingDir = dir,
      timeoutMs = timeoutMs)
    exitCode = code
  except CatchableError:
    exitCode = -1
  try: removeFile(leanPath)
  except CatchableError: discard  # axiom:best-effort(temp artifact cleanup)
  try: removeFile(oleanPath)
  except CatchableError: discard  # axiom:best-effort(temp artifact cleanup)
  if exitCode == 0:
    return lcPassed
  lcMismatch

# ─── Lean IR meta-check worker (certification-continuity Phase 3.5) ─────────

proc checkIRWithLeanWorker*(irBytes: openArray[byte]; leanWorkerExe: string = "";
                            projectRoot: string = ""; timeoutMs: int = 60_000): KernelVerdict {.
  raises: [CatchableError], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Tier-1 semantic-closure structural check: serialize IRExpr bytes are
  ## decoded + MetaM-checked by the standalone Lean worker
  ## (`proofs/.lake/build/bin/ircheck --check-file <path>`, built from
  ## IR/IRCheckWorker.lean — the file-mode twin of IR/LeanWorker.lean).
  ##
  ## The payload travels via a temp FILE (never argv — QUIRK(quirk#runGitEx-
  ## argv-flattening): whitespace/newline payloads would be re-split by shell
  ## semantics; the only argv tokens are the quoted worker path and the
  ## quoted temp path). Verdict mapping:
  ##   empty bytes                  → krMissingInput
  ##   worker binary not resolvable → krInternalError (fail-closed)
  ##   exit 0                       → krPassed (decode + meta-check OK)
  ##   non-zero exit                → krCompileError (decode/meta-check failed)
  ##   timeout                      → krTimeout
  if irBytes.len == 0:
    return krMissingInput
  let root = if projectRoot.len > 0: projectRoot else: resolveRepoRoot()
  let worker =
    if leanWorkerExe.len > 0:
      leanWorkerExe
    else:
      let envCmd = getEnv("AXIOM_IRCHECK_CMD", "")
      if envCmd.len > 0: envCmd else: root / "proofs" / ".lake" / "build" / "bin" / "ircheck"
  if not fileExists(worker):
    return krInternalError
  var payload = newString(irBytes.len)
  for i in 0 ..< irBytes.len:
    payload[i] = char(irBytes[i])
  var artifactPath = ""
  var output = ""
  var exitCode = -1
  try:
    artifactPath = getTempDir() / ("axiom_ircheck_" & sha256Hex(payload) & ".bin")
    writeFile(artifactPath, payload)
    (output, exitCode) = execCmdWithTimeout(
      quoteShell(worker) & " --check-file " & quoteShell(artifactPath),
      timeoutMs = timeoutMs)
  except CatchableError:
    if artifactPath.len > 0:
      try: removeFile(artifactPath)
      except CatchableError: discard  # axiom:best-effort(temp artifact cleanup)
    return krInternalError
  if artifactPath.len > 0:
    try: removeFile(artifactPath)
    except CatchableError: discard  # axiom:best-effort(temp artifact cleanup)
  if exitCode == -1:
    return krTimeout
  if exitCode == 0:
    return krPassed
  krCompileError

{.pop.}
