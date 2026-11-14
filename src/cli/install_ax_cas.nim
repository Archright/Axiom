import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}

## Canonical ax CLI CAS Installer
##
## binary-freshness-gate verifies bin/ax identity via the gate CAS:
##   .axiom/cache/gates/axiom-cli-<srcHash16>-<cfgHash16>/binary
## with bin/ax as a stable entry (symlink/hardlink) pointing at it.
## No build step ever produced that CAS entry — `make ci-bootstrap` writes a
## plain bin/ax — so Phase 1 of the freshness check was structurally
## unsatisfiable in a clean environment (CI RED). This installer closes that
## producer gap at the canonical build boundary (invoked by `make ci-bootstrap`
## right after the release build):
##   1. register the freshly built bin/ax into the CAS (atomic tmp→rename),
##   2. convert bin/ax into a stable entry pointing at the CAS binary,
##   3. record the build-time source fingerprint manifest so the gate's
##      secondary defense (Phase 2) has a baseline in a clean checkout.
## Verification semantics are unchanged — this only makes the declared
## contract producible. Idempotent: re-running on an up-to-date tree is a no-op.

import std/os
import checksums/sha2
import core/axiom_pragmas
import core/gate/gate_cas
import core/utils/repo_root
import infrastructure/provenance_probe
import generated/build_env
import core/trusted/stdlib_shield
import gate/runners/binary_freshness_gate

# axiomIoBoundary

const AxiomCliGateId = "axiom-cli"
const AxSourcePath* = "src" / "cli" / "main.nim"
const DefaultAxPath* = "bin" / "ax"

proc pointsToStableEntry(stablePath, casPath: string): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Mirror of binary_freshness_gate.stableEntryPointsTo (symlink, hardlink).
  if not fileExists(stablePath):
    return false
  try:
    if expandSymlink(stablePath) == casPath:
      return true
  except OSError:
    discard
  try:
    return sameFile(stablePath, casPath)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
  false

proc contentSha(data: string): string {.raises: [].} =
  var hasher = initSha_256()
  hasher.update(data)
  result = $hasher.digest()

proc installStableEntry(axBin, casBinary: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Replace the plain bin/ax with a stable entry linked to the CAS binary.
  ## Symlink preferred (a later rebuild replaces the path instead of writing
  ## through the link); hardlink is the fallback for filesystems without
  ## symlink support.
  removeFile(axBin)
  try:
    createSymlink(casBinary, axBin)
  except CatchableError:
    createHardlink(casBinary, axBin)

proc main() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  # B-layer cache provenance probe contract: strict self-check verdict only —
  # no CAS registration, no side effects (mismatch FATAL-exits 1 inside).
  if isProvenanceSelfCheckRequest(commandLineParams()):
    verifyProvenanceOrFatal("bin" / "install_ax_cas")
    echo "[OK] install_ax_cas provenance self-check: embedded BuildSourceHash == live src tree (" & BuildSourceHash & ")"
    quit(0)

  let repoRoot = findRepoRoot()
  setCurrentDir(repoRoot)

  if not fileExists(DefaultAxPath):
    stderr.writeLine("[ERROR] install_ax_cas: " & DefaultAxPath & " missing — run the release build first")
    quit(1)

  let srcHash = computeSourceHash(AxSourcePath)
  if srcHash.len == 0:
    stderr.writeLine("[ERROR] install_ax_cas: cannot hash " & AxSourcePath)
    quit(1)

  let casDir = resolveCasDir(AxiomCliGateId, srcHash, repoRoot)
  if casDir.len == 0:
    stderr.writeLine("[ERROR] install_ax_cas: empty CAS key")
    quit(1)
  createDir(casDir)

  let casBinary = casDir / "binary"
  # Refresh the CAS entry when the freshly built binary differs from what is
  # registered (e.g. a prior install raced with an older build). Identity is
  # content, not mere existence.
  let needsCopy = (not fileExists(casBinary)) or
    contentSha(readFile(casBinary)) != contentSha(readFile(DefaultAxPath))
  if needsCopy:
    let tmp = casDir / "binary.tmp"
    copyFile(DefaultAxPath, tmp)
    # preserve the executable bit — copyFile carries content, not modes
    setFilePermissions(tmp, getFilePermissions(DefaultAxPath))
    try:
      safeMoveFile(tmp, casBinary)
    except CatchableError as e:
      # atomic rename failed — clean up and fail closed
      if fileExists(tmp):
        try:
          removeFile(tmp)
        except CatchableError:
          discard  # axiom:best-effort(ioboundary catch)
      stderr.writeLine("[ERROR] install_ax_cas: CAS rename failed: " & e.msg)
      quit(1)

  # DEBT#524: every CAS entry carries its digest sidecar (idempotent — also
  # backfills entries installed before the integrity contract existed). An
  # entry without a verified digest is a permanent MISS under resolve
  # verification, so a sidecar write failure is fatal.
  if gate_cas.writeCasBinarySidecar(casBinary).len == 0:
    stderr.writeLine("[ERROR] install_ax_cas: digest sidecar write failed: " &
      casBinary & gate_cas.CasSidecarSuffix)
    quit(1)

  let axBin = DefaultAxPath
  if not pointsToStableEntry(axBin, casBinary):
    installStableEntry(axBin, casBinary)

  # Build-time fingerprint baseline for the freshness gate's Phase 2.
  saveManifest(axBin, @CliSourcePaths)

  echo "[OK] axiom-cli registered in CAS: " & casBinary
  quit(0)

when isMainModule:
  main()

{.pop.}
