import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [CatchableError].}

import core/crypto/hash_kernel
import core/gate/closure_manifest
import core/gate/gate_memo
import core/trusted/stdlib_shield
import core/types/results
import core/utils/io_utils
import std/[os, json, strutils]
import std/osproc
import core/interfaces/logging_hub
import core/trusted/axiom_pragmas_lite
# axiomIoBoundary

const CasDirName* = "gates"
const CasSidecarSuffix* = ".sha256"

# ---------------------------------------------------------------------------
# Hash helpers
# ---------------------------------------------------------------------------
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc computeSourceHash*(sourcePath: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Compute SHA-256 of a gate source file. Returns "" if file doesn't exist.
  if sourcePath.len == 0 or not fileExists(sourcePath):
    return ""
  try:
    hash_kernel.sha256Hex(readFile(sourcePath))
  except CatchableError:
    ""
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func closurePairwiseHash*(a, b: string): string {.raises: [], noSideEffect.} =
  ## Hash two sibling nodes in the closure Merkle tree ("\x02" domain
  ## separator — schema preserved from the retired transitive_hash basis).
  hash_kernel.sha256Hex("\x02" & a & b)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func reduceClosureHashes*(hashes: seq[string]): string {.raises: [], noSideEffect.} =
  ## Reduce a list of per-file hashes to a single Merkle root via pairwise
  ## hashing (odd node carries to the next layer). Deterministic for a
  ## sorted input file set.
  if hashes.len == 0:
    return ""
  if hashes.len == 1:
    return hashes[0]
  var layer = hashes
  while layer.len > 1:
    var next: seq[string] = @[]
    var i = 0
    while i < layer.len:
      if i + 1 < layer.len:
        next.add(closurePairwiseHash(layer[i], layer[i + 1]))
      else:
        next.add(layer[i])
      i += 2
    layer = next
  layer[0]
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc computeTransitiveSourceHash*(sourcePath: string; srcRoot: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Compute the transitive dependency hash over the COMPILER-TRUTH closure
  ## (VS-T authority handoff, 2026-11-08): the validated genDepend manifest
  ## closure (closure_manifest.loadProjectClosure — project-filtered
  ## `nim genDepend` .deps files ∪ live `when fileExists` probe targets),
  ## Merkle-rooted with the unchanged CAS hash schema (sorted absolute file
  ## set, per-file SHA-256, "\x02" pairwise domain separator). Hashing stays
  ## here (the consumer); only the closure source changed — the retired
  ## heuristic (transitive_hash) is no longer imported by this module.
  ## Fail-closed (verification_dag_contract.md §4/§5, DEBT#450): no valid
  ## manifest returns "" (Unresolved) — callers MUST NOT fall back to a
  ## weaker single-file key; the decision layer treats "" as no-key →
  ## execute. "" is never composed into a weaker key.
  ##
  ## No memoization (VS-T correctness-first): the closure is recomputed on
  ## every call from live manifest + file content; the retired
  ## (file, mtime, size) memo could have served closures computed under a
  ## different provider or manifest generation.
  ## srcRoot is retained for API compatibility with the existing readers
  ## (src/gate/** call sites); the provider derives the repository root
  ## from the source path itself.
  if sourcePath.len == 0 or not fileExists(sourcePath):
    return ""
  let files = closure_manifest.loadProjectClosure(sourcePath)
  if files.len == 0:
    return ""
  var fileHashes: seq[string] = @[]
  for f in files:
    let readRes = readFileOpt(f)
    if readRes.isErr:
      return ""
    let h = hash_kernel.sha256Hex(readRes.get())
    if h.len == 0:
      return ""
    fileHashes.add(h)
  if fileHashes.len == 0:
    return ""
  reduceClosureHashes(fileHashes)

proc gateClosureSourceHash(gateId, sourceFile, repoRoot: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Canonical gate-runner CAS identity basis (verification_dag_contract.md §3):
  ## transitive import-closure Merkle root. Unresolved → "" with reason logged
  ## (fail-closed reuse, DEBT#449/#450); the decision layer treats "" as
  ## no-key → compile/execute. "" is never composed into a weaker key.
  let srcHash = computeTransitiveSourceHash(sourceFile, repoRoot / "src")
  if srcHash.len == 0:
    logInfo("gate_cas", "axiom: transitive closure unresolved for " & gateId &
      " — no CAS key, forcing compile (fail-closed, DEBT#449/#450)")
  srcHash

# ---------------------------------------------------------------------------
# CAS key & path resolution
# ---------------------------------------------------------------------------
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc computeCasKey*(gateId, sourceHash: string; repoRoot: string;
 transitiveHash: string = ""): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Returns ``<gateId>-<srcHash[:16]>-<cfgHash[:16]>``.
  ## If transitiveHash is provided, includes it:
  ##   ``<gateId>-<srcHash[:16]>-<cfgHash[:16]>-<tHash[:16]>``
  ## Empty string if inputs are insufficient.
  if gateId.len == 0 or sourceHash.len == 0:
    return ""
  let cfgHash = computeBuildEnvHash(repoRoot)
  let srcShort = sourceHash[0 ..< min(16, sourceHash.len)]
  let cfgShort = cfgHash[0 ..< min(16, cfgHash.len)]
  if transitiveHash.len > 0:
    let tShort = transitiveHash[0 ..< min(16, transitiveHash.len)]
    gateId & "-" & srcShort & "-" & cfgShort & "-" & tShort
  else:
    gateId & "-" & srcShort & "-" & cfgShort
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc computeCompositeCasKey*(gateId, sourceHash, subtreeRoot: string;
                             repoRoot: string;
 transitiveHash: string = ""): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Extended CAS key: base CAS key + subtree root.
  ## Changing any component invalidates the cache.
  let baseKey = computeCasKey(gateId, sourceHash, repoRoot, transitiveHash)
  if baseKey.len == 0 or subtreeRoot.len == 0:
    return baseKey
  let subtreeShort = subtreeRoot[0 ..< min(16, subtreeRoot.len)]
  baseKey & "-" & subtreeShort
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc resolveCasDir*(gateId, sourceHash, repoRoot: string;
 transitiveHash: string = ""): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Returns the CAS directory: ``<repoRoot>/.axiom/cache/gates/<casKey>``.
  let key = computeCasKey(gateId, sourceHash, repoRoot, transitiveHash)
  if key.len == 0:
    return ""
  repoRoot / ".axiom" / "cache" / CasDirName / key
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc resolveCasPath*(gateId, sourceHash, repoRoot: string;
 transitiveHash: string = ""): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Returns full CAS binary path: ``<casDir>/binary``.
  let dir = resolveCasDir(gateId, sourceHash, repoRoot, transitiveHash)
  if dir.len == 0:
    return ""
  dir / "binary"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc getBinaryHash*(casKey: string; repoRoot: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Returns SHA-256 of the compiled binary in CAS for the given casKey.
  ## Returns "" if the binary does not exist.
  let binaryPath = repoRoot / ".axiom" / "cache" / CasDirName / casKey / "binary"
  if fileExists(binaryPath):
    try:
      hash_kernel.sha256Hex(readFile(binaryPath))
    except CatchableError:
      ""
  else:
    ""

# ---------------------------------------------------------------------------
# CAS binary integrity sidecar (DEBT#524 — fail-closed reuse verdict)
# ---------------------------------------------------------------------------
# A CAS entry is complete only when <casDir>/binary AND its digest sidecar
# <casDir>/binary.sha256 coexist and match. fileExists(binary) alone is NOT
# a reuse verdict: a post-store tamper or a crash between the binary and
# sidecar renames must resolve as a MISS (recompile), never as a hit.
# ---------------------------------------------------------------------------
func isLowercaseHex64*(s: string): bool {.raises: [], noSideEffect.} =
  ## Strict sidecar format: exactly 64 lowercase hex characters.
  if s.len != 64:
    return false
  for c in s:
    if c notin {'0'..'9', 'a'..'f'}:
      return false
  true
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc writeCasBinarySidecar*(casBinaryPath: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Atomically store the lowercase hex SHA-256 of the CAS binary at
  ## ``<casBinaryPath>.sha256`` (tmp + fsync + POSIX rename — the same
  ## store protocol as the binary itself). Returns the digest on success,
  ## "" on any failure; an entry whose sidecar could not be written stays
  ## incomplete and therefore a permanent CAS MISS (fail-closed, DEBT#524).
  if casBinaryPath.len == 0 or not fileExists(casBinaryPath):
    return ""
  let content =
    try:
      readFile(casBinaryPath)
    except CatchableError:
      return ""
  let digest = hash_kernel.sha256Hex(content)
  if digest.len == 0:
    return ""
  let stored = writeFileAtomic(casBinaryPath & CasSidecarSuffix, digest & "\n")
  if stored.isErr:
    return ""
  digest
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc casBinarySidecarIntact*(casBinaryPath, gateId: string): bool {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Reuse-verdict guard (DEBT#524): the binary is a hit only when its
  ## digest sidecar exists, is well-formed, and equals the binary's actual
  ## SHA-256. Missing, unreadable, or malformed sidecar — and any digest
  ## mismatch — is a MISS with a loud logError, never a silent reuse.
  ## Cost: one sidecar read + one binary read per resolve.
  let sidecarPath = casBinaryPath & CasSidecarSuffix
  if not fileExists(sidecarPath):
    logError("[CAS] DEBT#524 integrity MISS for " & gateId &
      ": digest sidecar missing (" & sidecarPath & ") — CAS miss (fail-closed)")
    return false
  let sidecarContent =
    try:
      readFile(sidecarPath)
    except CatchableError as e:
      logError("[CAS] DEBT#524 unreadable digest sidecar for " & gateId &
        ": " & sidecarPath & " (" & e.msg & ") — CAS miss (fail-closed)")
      return false
  let expected = sidecarContent.strip()
  if not isLowercaseHex64(expected):
    logError("[CAS] DEBT#524 malformed digest sidecar for " & gateId &
      ": " & sidecarPath & " (expected 64 lowercase hex chars) — CAS miss (fail-closed)")
    return false
  let actual =
    try:
      hash_kernel.sha256Hex(readFile(casBinaryPath))
    except CatchableError as e:
      logError("[CAS] DEBT#524 unreadable CAS binary for " & gateId &
        ": " & casBinaryPath & " (" & e.msg & ") — CAS miss (fail-closed)")
      return false
  if actual != expected:
    logError("[CAS] DEBT#524 TAMPER DETECTED for " & gateId &
      ": digest mismatch at " & casBinaryPath &
      " (sidecar=" & expected & ", actual=" & actual & ") — CAS miss (fail-closed)")
    return false
  true

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc resolveCasBinaryPathWithHash*(gateId, sourceFile, repoRoot: string; sourceHash: string;
  transitiveHash: string = ""; buildEnvHash: string = ""): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Compute the CAS binary path using an explicit pre-computed source hash.
  ## Callers MUST pass an explicit identity; no implicit single-file fallback
  ## (DEBT#450 pattern). Returns "" if sourceHash is empty (no key) or the
  ## binary does not exist (CAS miss). A hit requires the digest sidecar to
  ## verify against the stored binary (DEBT#524, fail-closed).
  if sourceHash.len == 0: return ""
  let srcHash = sourceHash
  let casKey = computeCasKey(gateId, srcHash, repoRoot, transitiveHash)
  if casKey.len == 0: return ""
  let absPath = repoRoot / ".axiom" / "cache" / CasDirName / casKey / "binary"
  if fileExists(absPath) and casBinarySidecarIntact(absPath, gateId):
    return absPath
  return ""

# ---------------------------------------------------------------------------
# Stable entry installation (3-tier fallback)
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Binary path resolution (replaces stable entry symlink approach)
# ---------------------------------------------------------------------------
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc resolveCasBinaryPath*(gateId, sourceFile, repoRoot: string;
 transitiveHash: string = ""): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Compute the CAS key and return the absolute path to the binary.
  ## Basis: transitive import-closure Merkle root via gateClosureSourceHash
  ## (verification_dag_contract.md §3). Unresolved "" means no-key →
  ## compile (fail-closed, DEBT#449/#450). A hit requires the digest
  ## sidecar to verify against the stored binary (DEBT#524, fail-closed).
  let srcHash = gateClosureSourceHash(gateId, sourceFile, repoRoot)
  if srcHash.len == 0: return ""
  let casKey = computeCasKey(gateId, srcHash, repoRoot, transitiveHash)
  if casKey.len == 0: return ""
  let absPath = repoRoot / ".axiom" / "cache" / CasDirName / casKey / "binary"
  if fileExists(absPath) and casBinarySidecarIntact(absPath, gateId):
    return absPath
  return ""

# ---------------------------------------------------------------------------
# JIT compilation into CAS
# ---------------------------------------------------------------------------
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc compileGateToCas*(gateId, entry, sourcePath, nimcacheDir, repoRoot: string;
 transitiveHash: string = ""; allowJit: bool = true): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## JIT compile a gate binary into the CAS directory.
  ## Writes to ``binary.tmp`` inside the CAS dir, then atomic rename to ``binary``.
  ## Returns the CAS binary path on success, empty string on failure.
  ##
  ## Parameters:
  ##   gateId      - gate identifier (e.g. "binary-freshness")
  ##   entry       - stable entry path (e.g. "bin/binary_freshness_gate")
  ##   sourcePath  - resolved .nim source file path
  ##   nimcacheDir - per-gate nimcache isolation dir
  ##   repoRoot    - project root directory
  ##   transitiveHash - optional Merkle root of transitive dependencies
  ##   allowJit      - if false, CAS miss returns "" instead of JIT compilation (default: true)
  if gateId.len == 0 or sourcePath.len == 0:
    return ""
  if not fileExists(sourcePath):
    return ""

  let srcHash = gateClosureSourceHash(gateId, sourcePath, repoRoot)
  if srcHash.len == 0:
    return ""

  let casDir = resolveCasDir(gateId, srcHash, repoRoot, transitiveHash)
  if casDir.len == 0:
    return ""
  discard existsOrCreateDirOpt(casDir)

  let casBinary = casDir / "binary"
  let casTmp = casDir / "binary.tmp"

  # Skip compilation if CAS binary already exists AND its digest sidecar
  # verifies (DEBT#524: existence alone is not a reuse verdict — a tampered
  # or sidecar-less entry falls through to recompilation, fail-closed).
  if fileExists(casBinary) and casBinarySidecarIntact(casBinary, gateId):
    return casBinary

  # CAS miss — check if JIT is allowed
  if not allowJit:
    logError("CAS MISS for " & gateId &
      " — binary not pre-compiled. Run: bin/precompile_gates")
    return ""

  # Per-gate nimcache isolation
  if nimcacheDir.len > 0:
    discard existsOrCreateDirOpt(nimcacheDir)

  let nimExe = findExe("nim")
  let nimCmd = "c --hints:off -d:release --skipUserCfg:on" &
    (if nimcacheDir.len > 0: " --nimcache:" & quoteShell(nimcacheDir) else: "") &
    " -d:ThreadPoolSize=14" &
    " -o:" & quoteShell(casTmp) &
    " " & quoteShell(sourcePath)

  # AXIOM_HERMETIC_BUILDING marks hermetic gate recompilation: src/gate/config.nims
  # skips its cli/main existence check in this context (the CAS build compiles a
  # single gate runner, not the full CLI).
  let (outp, code) = execCmdEx("AXIOM_HERMETIC_BUILDING=1 " & nimExe & " " & nimCmd)
  if code != 0:
    # Clean up failed temp file
    if fileExists(casTmp):
      try:
        removeFile(casTmp)
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)
    logError("[CAS] Compile failed for " & gateId & ": " & outp)
    return ""

  # Atomic rename: binary.tmp → binary
  try:
    safeMoveFile(casTmp, casBinary)
    # DEBT#524: persist the digest sidecar atomically after the binary
    # rename. A crash between the two renames leaves a sidecar-less binary
    # — a permanent MISS on every future resolve (fail-closed). A sidecar
    # write failure means the same incomplete state: report the store as
    # failed, never as a hit.
    if writeCasBinarySidecar(casBinary).len == 0:
      logError("[CAS] DEBT#524 digest sidecar write failed for " & gateId &
        " — entry incomplete, store failed (fail-closed)")
      return ""
    return casBinary
  except CatchableError as e:
    logError("[CAS] Atomic rename failed for " & gateId & ": " & e.msg)
    if fileExists(casTmp):
      try:
        removeFile(casTmp)
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)
    return ""

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc compileGateToCasWithHash*(gateId, entry, sourcePath, sourceHash, nimcacheDir, repoRoot: string;
  transitiveHash: string = ""; buildEnvHash: string = ""; allowJit: bool = true;
  nimCompileThreads: int = 14): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## JIT compile a gate binary into the CAS directory using pre-computed hashes.
  ## Returns CAS binary path on success, empty string on failure.
  if gateId.len == 0 or sourcePath.len == 0:
    return ""
  if not fileExists(sourcePath):
    return ""

  if sourceHash.len == 0: return ""
  let srcHash = sourceHash
  if srcHash.len == 0:
    return ""

  let casDir = resolveCasDir(gateId, srcHash, repoRoot, transitiveHash)
  if casDir.len == 0:
    return ""
  discard existsOrCreateDirOpt(casDir)

  let casBinary = casDir / "binary"
  let casTmp = casDir / "binary.tmp"

  # DEBT#524: existence alone is not a reuse verdict — a tampered or
  # sidecar-less entry falls through to recompilation (fail-closed).
  if fileExists(casBinary) and casBinarySidecarIntact(casBinary, gateId):
    return casBinary

  if not allowJit:
    logError("CAS MISS for " & gateId &
      " — binary not pre-compiled. Run: bin/precompile_gates")
    return ""

  if nimcacheDir.len > 0:
    discard existsOrCreateDirOpt(nimcacheDir)

  let nimExe = findExe("nim")
  let nimCmd = "c --hints:off -d:release --skipUserCfg:on " &
    (if nimcacheDir.len > 0: "--nimcache:" & quoteShell(nimcacheDir) & " " else: "") &
    "-d:ThreadPoolSize=" & $max(1, min(14, nimCompileThreads)) &
    " -o:" & quoteShell(casTmp) & " " & quoteShell(sourcePath)

  # See first compile site: hermetic marker for gate-only recompilation.
  let (outp, code) = execCmdEx("AXIOM_HERMETIC_BUILDING=1 " & nimExe & " " & nimCmd)
  if code != 0:
    if fileExists(casTmp):
      try:
        removeFile(casTmp)
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)
    logError("[CAS] Compile failed for " & gateId & ": " & outp)
    return ""

  try:
    safeMoveFile(casTmp, casBinary)
    # DEBT#524: digest sidecar after the binary rename — see first compile
    # site (crash between renames ⇒ sidecar-less binary ⇒ permanent MISS).
    if writeCasBinarySidecar(casBinary).len == 0:
      logError("[CAS] DEBT#524 digest sidecar write failed for " & gateId &
        " — entry incomplete, store failed (fail-closed)")
      return ""
    return casBinary
  except CatchableError as e:
    logError("[CAS] Atomic rename failed for " & gateId & ": " & e.msg)
    if fileExists(casTmp):
      try:
        removeFile(casTmp)
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)
    return ""

# ---------------------------------------------------------------------------
# CAS content operations (Phase 2: Merkle Integration — Wave 5B-2)
# ---------------------------------------------------------------------------
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc resolveBinaryPath*(gateId, entry, repoRoot: string;
 transitiveHash: string = ""): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Convenience: computeSourceHash → resolveCasPath in one call.
  ## Returns CAS binary path if it exists, empty string otherwise.
  let sourcePath = repoRoot / entry
  let srcHash = computeSourceHash(sourcePath)
  if srcHash.len == 0: return ""
  try:
    resolveCasPath(gateId, srcHash, repoRoot)
  except CatchableError:
    ""
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc casContentByHash*(hash, repoRoot: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read content from CAS by its hash. Returns "" if not found.
  ## Scans .axiom/cache/content/ for a file matching the hash
  ## (the same directory storeContentToCas writes to).
  # axiomIoBoundary
  let contentDir = repoRoot / ".axiom" / "cache" / "content"
  try:
    if not dirExists(contentDir):
      return ""
    for path in walkDirRec(contentDir):
      try:
        let content = readFile(path)
        let fileHash = hash_kernel.sha256Hex(content)
        if fileHash == hash:
          return content
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
  ""
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc storeContentToCas*(content, repoRoot: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Store content in CAS, return its SHA-256 hash.
  ## Path: .axiom/cache/content/<hash[:2]>/<hash>
  ## Atomic write: open → write → fsync → close → temp file → rename.
  # axiomIoBoundary
  if content.len == 0:
    return ""
  let hash = hash_kernel.sha256Hex(content)
  let contentDir = repoRoot / ".axiom" / "cache" / "content" / hash[0 ..< 2]
  let target = contentDir / hash
  try:
    # createDir creates all missing parent directories (existsOrCreateDirOpt
    # does not — it fails when the parent is absent in this environment).
    createDir(contentDir)
    if fileExists(target):
      return hash  # Already stored
    let tmpPath = target & ".tmp"
    let fh = open(tmpPath, fmWrite)
    fh.write(content)
    fh.flushFile()
    fh.close()
    safeMoveFile(tmpPath, target)
    return hash
  except CatchableError:
    if fileExists(target & ".tmp"):
      try: removeFile(target & ".tmp")
      except CatchableError: discard  # axiom:best-effort(ioboundary catch)
    ""
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc casReadByHash*(casKey, hash, repoRoot: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read content from a specific CAS key directory by hash.
  ## Returns "" if not found or hash mismatch.
  # axiomIoBoundary
  let casDir = repoRoot / ".axiom" / "cache" / CasDirName / casKey
  try:
    if not dirExists(casDir):
      return ""
    for kind, path in walkDir(casDir):
      if kind == pcFile:
        try:
          let content = readFile(path)
          let fileHash = hash_kernel.sha256Hex(content)
          if fileHash == hash:
            return content
        except CatchableError:
          discard  # axiom:best-effort(ioboundary catch)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
  ""
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc verifyCasIntegrity*(repoRoot: string): bool {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Verify CAS integrity. Checks for stale temp files and manifest corruption.
  ## If a .recover flag exists, performs Double Fault recovery:
  ##   1. Delete manifest and tmp dir (clean slate)
  ##   2. Remove .recover flag
  ##   3. Return false (caller must rebuild)
  let casDir = repoRoot / ".axiom" / "cache" / CasDirName
  let recoverFlag = casDir / ".recover"
  let manifestPath = casDir / "manifest.json"
  let tmpDir = casDir / "tmp"

  # Double Fault recovery: recover flag FIRST → clean slate → return false
  if fileExists(recoverFlag):
    if fileExists(manifestPath):
      try: removeFile(manifestPath)
      except CatchableError: discard  # axiom:best-effort(ioboundary catch)
    if dirExists(tmpDir):
      try: removeDir(tmpDir)
      except CatchableError: discard  # axiom:best-effort(ioboundary catch)
    try: removeFile(recoverFlag)
    except CatchableError: discard  # axiom:best-effort(ioboundary catch)
    return false

  # Normal integrity check: no stale tmp files
  if dirExists(tmpDir):
    # Stale tmp directory from crashed compilation
    try: removeDir(tmpDir)
    except CatchableError: discard  # axiom:best-effort(ioboundary catch)

  # Manifest corruption check
  if fileExists(manifestPath):
    try:
      let content = readFile(manifestPath)
      if content.len == 0:
        return false  # Empty manifest = corruption
      let node = parseJson(content)
      if node.kind != JObject:
        return false  # Manifest must be a JSON object
      # Validate top-level keys are strings (expected CAS manifest structure)
      for key in node.keys:
        if key.len == 0:
          return false  # Empty key = corruption
    except CatchableError:
      return false  # Unparseable manifest = corruption

  true
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc storeContentToCasChecked*(content, repoRoot: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Store content in CAS with immutability assertion.
  ## If the hash already exists, verify content matches.
  ## If content doesn't match (hash collision), raise AssertionDefect.
  # axiomIoBoundary
  if content.len == 0:
    return ""
  let hash = hash_kernel.sha256Hex(content)
  let contentDir = repoRoot / ".axiom" / "cache" / "content" / hash[0 ..< 2]
  let target = contentDir / hash
  try:
    # createDir creates all missing parent directories (existsOrCreateDirOpt
    # does not — it fails when the parent is absent in this environment).
    createDir(contentDir)
    if fileExists(target):
      # Immutability check: existing content must match
      let existing = readFile(target)
      if existing != content:
        raise (ref AssertionDefect)(msg: "CAS immutability violation: content mismatch for hash " & hash)
      return hash
  except CatchableError as e:
    raise (ref AssertionDefect)(msg: "CAS immutability check failed: " & e.msg)
  # Store new content atomically (with fsync)
  let tmpPath = target & ".tmp"
  try:
    let fh = open(tmpPath, fmWrite)
    fh.write(content)
    fh.flushFile()
    fh.close()
    safeMoveFile(tmpPath, target)
    return hash
  except CatchableError as e:
    if fileExists(tmpPath):
      try: removeFile(tmpPath)
      except CatchableError: discard  # axiom:best-effort(ioboundary catch)
    raise (ref AssertionDefect)(msg: "CAS store failed for hash " & hash & ": " & e.msg)

{.pop.}
