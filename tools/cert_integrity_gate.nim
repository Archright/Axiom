import std/[json, os, osproc, strutils, algorithm, sequtils, tables], checksums/sha2

const
  DefaultDir = "src/verification/certificates"
  DefaultManifest = "manifest.json"
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

  Violation = object
    kind*: string
    message*: string

  GateResult = object
    mode*: string
    ok*: bool
    errors*: seq[Violation]
    checked*: int
    violations*: int

proc findProjectRoot(): string =
  var dir = getCurrentDir()
  while true:
    if fileExists(dir / ProjectRootAnchor):
      return dir
    if fileExists(dir / "axiom.toml"):
      return dir
    let parent = dir.parentDir()
    if parent == dir:
      quit("ERROR: " & ProjectRootAnchor & " not found. Run from Axiom project directory.", 1)
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

proc computeContentHash(path: string): string =
  let content = readFile(path)
  "sha256:" & $secureHash(Sha_256, content)

proc runGit(args: seq[string]): string =
  let cmd = "git " & args.join(" ")
  let output = execCmdEx(cmd)
  if output.exitCode != 0:
    return ""
  output.output.strip()

proc getChangedFiles(certDir: string): seq[string] =
  let output = runGit(@["diff", "--name-only", "--diff-filter=ACMRT", "HEAD", "--", certDir])
  if output.len == 0:
    return @[]
  output.splitLines()

proc getUntrackedFiles(certDir: string): seq[string] =
  let output = runGit(@["ls-files", "--others", "--exclude-standard", certDir])
  if output.len == 0:
    return @[]
  output.splitLines()

proc loadManifest(manifestPath: string): (seq[CertEntry], bool) =
  if not fileExists(manifestPath):
    return (@[], false)
  let content = readFile(manifestPath)
  if content.strip().len == 0:
    return (@[], false)
  let parsed = parseJson(content)
  if not parsed.hasKey("entries"):
    return (@[], false)
  let entriesArr = parsed["entries"]
  if entriesArr.kind != JArray:
    return (@[], false)
  var entries: seq[CertEntry] = @[]
  for e in entriesArr:
    var entry: CertEntry
    entry.modulePath = e["modulePath"].getStr()
    entry.functionName = e["functionName"].getStr()
    entry.irHash = e["irHash"].getStr()
    entry.fingerprint = e["fingerprint"].getStr()
    entry.contentHash = e["contentHash"].getStr()
    entry.status = e["status"].getStr()
    entry.backend = e["backend"].getStr()
    entry.lifecycleStage = e["lifecycleStage"].getStr()
    entries.add(entry)
  (entries, true)

proc buildEntryByIrHash(entries: seq[CertEntry]): Table[string, CertEntry] =
  var t: Table[string, CertEntry]
  for e in entries:
    t[e.irHash] = e
  t

proc checkFullMode(certDir, manifestPath: string): GateResult =
  result.mode = "full"
  var errors: seq[Violation] = @[]
  var checked = 0
  var violations = 0

  let (entries, manifestOk) = loadManifest(manifestPath)
  if not manifestOk:
    errors.add(Violation(kind: "manifest", message: "manifest not found or empty: " & manifestPath))
    result.ok = false
    result.errors = errors
    result.checked = checked
    result.violations = violations
    return result

  let projectRoot = findProjectRoot()
  let fullCertDir = projectRoot / certDir

  if not dirExists(fullCertDir):
    errors.add(Violation(kind: "directory", message: "cert directory not found: " & fullCertDir))
    result.ok = false
    result.errors = errors
    result.checked = checked
    result.violations = violations
    return result

  var certFiles: seq[string] = @[]
  for file in walkDirRec(fullCertDir):
    let fname = file.splitFile().name
    if isCertFilename(fname):
      certFiles.add(file)
  certFiles.sort()

  let entryByIrHash = buildEntryByIrHash(entries)

  for entry in entries:
    checked.inc
    let expectedFile = fullCertDir / (entry.irHash & ".json")
    if not fileExists(expectedFile):
      errors.add(Violation(kind: "missing-file", message: "manifest entry irHash=" & entry.irHash & " has no file at " & expectedFile))
      violations.inc

  for cf in certFiles:
    let fname = cf.splitFile().name
    let irHash = fname.split('.')[0]
    checked.inc
    let relPath = relativePath(cf, fullCertDir)

    if not entryByIrHash.hasKey(irHash):
      errors.add(Violation(kind: "manifest-membership", message: "cert file has no manifest entry: " & relPath))
      violations.inc
      continue

    let entry = entryByIrHash[irHash]
    let actualHash = computeContentHash(cf)
    if actualHash != entry.contentHash:
      errors.add(Violation(kind: "contentHash-mismatch", message: "contentHash mismatch for " & relPath & ": expected " & entry.contentHash & " got " & actualHash))
      violations.inc

  if violations == 0:
    result.ok = true
  else:
    result.ok = false
  result.errors = errors
  result.checked = checked
  result.violations = violations

proc checkFastMode(certDir, manifestPath: string): GateResult =
  result.mode = "fast"
  var errors: seq[Violation] = @[]
  var checked = 0
  var violations = 0

  let projectRoot = findProjectRoot()
  let fullCertDir = projectRoot / certDir

  let (entries, manifestOk) = loadManifest(manifestPath)
  if not manifestOk:
    errors.add(Violation(kind: "manifest", message: "manifest not found or empty: " & manifestPath))
    result.ok = false
    result.errors = errors
    result.checked = checked
    result.violations = violations
    return result

  let entryByIrHash = buildEntryByIrHash(entries)

  var changedFiles = getChangedFiles(certDir)
  let untrackedFiles = getUntrackedFiles(certDir)

  var trackedChanged: seq[string] = @[]
  for f in changedFiles:
    let fname = f.splitFile().name
    if fname == "manifest.json":
      continue
    if fname.startsWith("type_mappings"):
      continue
    if not isCertFilename(fname):
      continue
    trackedChanged.add(f)

  var untrackedNew: seq[string] = @[]
  for f in untrackedFiles:
    let fname = f.splitFile().name
    if fname == "manifest.json":
      continue
    if fname.startsWith("type_mappings"):
      continue
    if not isCertFilename(fname):
      continue
    untrackedNew.add(f)

  for f in trackedChanged:
    let fullPath = projectRoot / f
    if not fileExists(fullPath):
      continue
    let fname = fullPath.splitFile().name
    let irHash = fname.split('.')[0]
    checked.inc

    if not entryByIrHash.hasKey(irHash):
      errors.add(Violation(kind: "manifest-membership", message: "changed cert file has no manifest entry: " & f))
      violations.inc
      continue

    let entry = entryByIrHash[irHash]
    let actualHash = computeContentHash(fullPath)
    if actualHash != entry.contentHash:
      errors.add(Violation(kind: "contentHash-mismatch", message: "contentHash mismatch for " & f & ": expected " & entry.contentHash & " got " & actualHash))
      violations.inc

  for f in untrackedNew:
    let fullPath = projectRoot / f
    if not fileExists(fullPath):
      continue
    let fname = fullPath.splitFile().name
    let irHash = fname.split('.')[0]
    checked.inc

    if not entryByIrHash.hasKey(irHash):
      errors.add(Violation(kind: "canonical-path-invariant", message: "untracked new cert file in canonical dir not in manifest (promotion required): " & f))
      violations.inc
      continue

    let entry = entryByIrHash[irHash]
    let actualHash = computeContentHash(fullPath)
    if actualHash != entry.contentHash:
      errors.add(Violation(kind: "contentHash-mismatch", message: "contentHash mismatch for " & f & ": expected " & entry.contentHash & " got " & actualHash))
      violations.inc

  if violations == 0:
    result.ok = true
  else:
    result.ok = false
  result.errors = errors
  result.checked = checked
  result.violations = violations

proc formatHumanReadable(r: GateResult): string =
  var lines: seq[string] = @[]
  lines.add("=== Certificate Integrity Gate [" & r.mode & "] ===")
  lines.add("Checked: " & $r.checked)
  lines.add("Violations: " & $r.violations)
  if r.ok:
    lines.add("Result: PASS")
  else:
    lines.add("Result: FAIL")
    for e in r.errors:
      lines.add("  [" & e.kind & "] " & e.message)
  lines.join("\n")

proc toJson(r: GateResult): string =
  let errorsJson = r.errors.map(proc(e: Violation): JsonNode =
    let o = newJObject()
    o["kind"] = %e.kind
    o["message"] = %e.message
    o
  )
  let root = newJObject()
  root["mode"] = %r.mode
  root["ok"] = %r.ok
  root["errors"] = %errorsJson
  root["checked"] = %r.checked
  root["violations"] = %r.violations
  $root

proc main() =
  let args = commandLineParams()
  var mode = ""
  var certDir = DefaultDir
  var manifest = DefaultManifest
  var jsonOutput = false

  var i = 0
  while i < args.len:
    if args[i] == "--mode" and i + 1 < args.len:
      mode = args[i + 1]
      inc i
    elif args[i] == "--dir" and i + 1 < args.len:
      certDir = args[i + 1]
      inc i
    elif args[i] == "--manifest" and i + 1 < args.len:
      manifest = args[i + 1]
      inc i
    elif args[i] == "--json":
      jsonOutput = true
    inc i

  if mode notin @["fast", "full"]:
    quit("ERROR: --mode fast|full is required", 1)

  let projectRoot = findProjectRoot()
  let fullManifestPath = projectRoot / certDir / manifest

  var result: GateResult
  if mode == "full":
    result = checkFullMode(certDir, fullManifestPath)
  else:
    result = checkFastMode(certDir, fullManifestPath)

  if jsonOutput:
    echo result.toJson()
  else:
    echo result.formatHumanReadable()

  if not result.ok:
    quit(1)

when isMainModule:
  main()