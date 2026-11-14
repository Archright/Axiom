import std/[json, os, osproc, strutils, algorithm, sequtils], checksums/sha2

const
  DefaultDir = "src/verification/certificates"
  DefaultManifest = "src/verification/certificates/manifest.json"
  ProjectRootAnchor = ".axiom_root"

type
  CertEntry = object
    modulePath*: string
    functionName*: string
    irHash*: string
    fingerprint*: string
    contentHash*: string
    status*: string
    backend*: string
    lifecycleStage*: string

proc findProjectRoot(): string =
  var dir = getCurrentDir()
  while true:
    if fileExists(dir / ProjectRootAnchor):
      return dir
    let parent = dir.parentDir()
    if parent == dir:
      quit("ERROR: " & ProjectRootAnchor & " not found. Run from Axiom project directory.")
    dir = parent

func isCertFilename(fname: string): bool =
  if fname == "manifest.json":
    return false
  if fname.startsWith("type_mappings"):
    return false
  let base = fname.split('.')[0]
  if base.len == 0:
    return false
  for ch in base:
    if ch notin {'0'..'9', 'a'..'f', 'A'..'F'}:
      return false
  true

proc canonicalCertificatesDigest*(certDir: string; schemaVersion: int = 1): string =
  ## Canonical digest of the certificate vault: sorted relative path + byte-exact
  ## file contents + digest contract version. manifest.json is EXCLUDED by
  ## isCertFilename. This is the single shared digest primitive — sync_certs
  ## (writer) and the integrity gate both use it so they can never drift.
  ## Digest contract version is independent of manifest schema version.
  var buf = "certdigest_v" & $schemaVersion & "\n"
  var files: seq[string] = @[]
  if dirExists(certDir):
    for f in walkDirRec(certDir):
      if isCertFilename(f.splitFile().name):
        files.add(f)
  files.sort()
  for f in files:
    buf.add(f.readFile())
    buf.add("\n")
  "sha256:" & $secureHash(Sha_256, buf)

func deriveSolverMethod(verificationTier: string): string =
  if verificationTier == "lean-verified":
    "smCLI"
  else:
    "smNone"

func deriveBackend(verificationTier: string): string =
  if verificationTier == "lean-verified":
    "lean"
  else:
    "smt"

proc loadCertEntry(certPath: string): CertEntry =
  let content = readFile(certPath)
  let parsed = parseJson(content)
  result.modulePath = parsed["modulePath"].getStr()
  result.functionName = parsed["functionName"].getStr()
  result.irHash = parsed["irHash"].getStr()
  result.fingerprint = parsed["fingerprint"].getStr()
  let status = parsed["status"].getStr()
  let verificationTier = if parsed.hasKey("verificationTier"):
                          parsed["verificationTier"].getStr()
                        else:
                          "none"
  result.backend = deriveBackend(verificationTier)
  let solverMethod = deriveSolverMethod(verificationTier)
  result.contentHash = "sha256:" & $secureHash(Sha_256, content)
  let isTracked = execCmdEx("git ls-files --error-unmatch " & certPath).exitCode == 0
  result.lifecycleStage = if isTracked: "canonical" else: "generated"

proc entryToJson(entry: CertEntry): JsonNode =
  result = newJObject()
  result["modulePath"] = %entry.modulePath
  result["functionName"] = %entry.functionName
  result["irHash"] = %entry.irHash
  result["fingerprint"] = %entry.fingerprint
  result["contentHash"] = %entry.contentHash
  result["status"] = %entry.status
  result["backend"] = %entry.backend
  result["lifecycleStage"] = %entry.lifecycleStage

proc computeFingerprint(entries: openArray[CertEntry]): string =
  var buf = ""
  for entry in entries:
    buf.add(entry.modulePath & "|" & entry.functionName & "|" &
            entry.irHash & "|" & entry.contentHash & "|" &
            entry.status & "|" & entry.backend & "|" &
            entry.lifecycleStage & ";")
  $secureHash(Sha_256, buf)

proc main() =
  let args = commandLineParams()
  let ciDriftCheck = "--ci-drift-check" in args or "--check" in args

  var certDir = DefaultDir
  var manifestPath = DefaultManifest
  var i = 0
  while i < args.len:
    if args[i] == "--dir" and i + 1 < args.len:
      certDir = args[i + 1]
      inc i
    elif args[i] == "--manifest" and i + 1 < args.len:
      manifestPath = args[i + 1]
      inc i
    inc i

  let projectRoot = findProjectRoot()
  let fullCertDir = projectRoot / certDir
  let fullManifestPath = projectRoot / manifestPath

  if not dirExists(fullCertDir):
    quit("ERROR: cert directory not found: " & fullCertDir, 1)

  var certFiles: seq[string] = @[]
  for file in walkDirRec(fullCertDir):
    let fname = file.splitFile().name
    if isCertFilename(fname):
      certFiles.add(file)

  certFiles.sort()

  var entries: seq[CertEntry] = @[]
  for cf in certFiles:
    let entry = loadCertEntry(cf)
    entries.add(entry)

  entries.sort(proc(a, b: CertEntry): int =
    let cmpPath = cmp(a.modulePath, b.modulePath)
    if cmpPath != 0:
      return cmpPath
    cmp(a.functionName, b.functionName))

  let fingerprint = computeFingerprint(entries)

  var manifest = newJObject()
  manifest["version"] = %2
  manifest["fingerprint"] = %fingerprint
  manifest["metadata"] = %*{
    "contentHash": canonicalCertificatesDigest(fullCertDir),
    "digestContractVersion": 1
  }
  let entriesJson = newJArray()
  for entry in entries:
    entriesJson.add(entryToJson(entry))
  manifest["entries"] = entriesJson

  let newContent = pretty(manifest) & "\n"

  # ── Integrity verify (CI/hermetic): recompute the cert digest and compare with
  #    the manifest's recorded metadata.contentHash. Fail-closed on mismatch.
  if "--verify" in args:
    if not fileExists(fullManifestPath):
      quit("VERIFY FAIL: manifest missing at " & fullManifestPath, 1)
    let oldNode = parseJson(readFile(fullManifestPath))
    let recorded = oldNode.getOrDefault("metadata").getOrDefault("contentHash").getStr("")
    let recomputed = canonicalCertificatesDigest(fullCertDir)
    if recorded.len == 0 or recorded != recomputed:
      stderr.writeLine("VERIFY FAIL: certificate manifest is stale.\n" &
        "  recorded=" & (if recorded.len > 0: recorded else: "(none)") &
        "\n  recomputed=" & recomputed &
        "\nRun the canonical cert sync command: nim c -r tools/sync_certs.nim")
      quit(1)
    quit(0)

  # ── Ensure (local materialization/update): if the manifest's recorded digest is
  #    stale or absent, REGENERATE it from current cert contents and exit 0. This is
  #    a deterministic value-materialization step, NOT an integrity assertion — the
  #    fail-closed assertion lives in `--verify` (local mutation / CI fail-closed
  #    separation). We never silently skip regeneration against a stale manifest.
  if "--ensure" in args:
    let recomputed = canonicalCertificatesDigest(fullCertDir)
    var stale = not fileExists(fullManifestPath)
    if not stale:
      let oldNode = parseJson(readFile(fullManifestPath))
      let recorded = oldNode.getOrDefault("metadata").getOrDefault("contentHash").getStr("")
      stale = (recorded.len == 0 or recorded != recomputed)
    if stale:
      writeFile(fullManifestPath, newContent)
      echo "[sync_certs] ENSURED manifest regenerated: " & fullManifestPath & " (" & $entries.len & " entries)"
    else:
      echo "[sync_certs] Manifest fresh (" & $entries.len & " entries)"
    quit(0)

  if fileExists(fullManifestPath):
    let oldContent = readFile(fullManifestPath)
    if oldContent == newContent:
      echo "[sync_certs] Manifest unchanged (" & $entries.len & " entries)"
      if ciDriftCheck:
        echo "[sync_certs] CI drift check: PASS (no drift)"
      return

  writeFile(fullManifestPath, newContent)
  echo "[sync_certs] Manifest written: " & fullManifestPath & " (" & $entries.len & " entries)"

  if ciDriftCheck:
    let exitCode = execCmdEx("git diff --exit-code " & fullManifestPath).exitCode
    if exitCode != 0:
      quit("[sync_certs] DRIFT DETECTED: " & fullManifestPath & " would change. Run 'nim r tools/sync_certs.nim' locally and commit the results.", 1)
    else:
      echo "[sync_certs] CI drift check: PASS (no drift)"

when isMainModule:
  main()