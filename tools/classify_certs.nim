import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, osproc, json, times, algorithm, tables, strutils, sets, sequtils]

const
  DefaultDir = "src/verification/certificates"
  ManifestName = "manifest.json"
  Version = 1

type
  CertRecord = object
    modulePath: string
    functionName: string
    fingerprint: string
    sourceHash: string
    irHash: string
    status: string
    trusted: bool
    kernel: bool
    winningStrategy: string
    solverProvenance: string
    verificationTier: string
    reason: string
    leanProposition: string
    smtlib2: string
    solverStatus: string
    fileName: string
    tracked: bool
    inManifest: bool

  Counts = object
    totalFiles: int
    tracked: int
    untracked: int
    inManifest: int
    duplicateIdentities: int
    certRed: int
    certGreen: int
    certLeanVerified: int
    kernel: int

  ClassGroup = object
    status: string
    solverProvenance: string
    verificationTier: string
    winningStrategy: string
    count: int

  IdentityEntry = object
    identity: string
    modulePath: string
    functionName: string
    irHash: string
    fingerprint: string
    sourceHash: string
    status: string
    tracked: bool
    inManifest: bool
    kernel: bool
    trusted: bool
    files: seq[string]

  ReportEntry = object
    fileName: string
    identity: string
    modulePath: string
    functionName: string
    irHash: string
    fingerprint: string
    sourceHash: string
    status: string
    tracked: bool
    inManifest: bool
    kernel: bool
    trusted: bool
    winningStrategy: string
    solverProvenance: string
    verificationTier: string

  ClassificationOutput = object
    version: int
    generatedAt: string
    counts: Counts
    classes: seq[ClassGroup]
    byIdentity: seq[IdentityEntry]
    report: seq[ReportEntry]

func identityKey(modulePath, functionName: string): string =
  modulePath & "\x00" & functionName

func identityLabel(modulePath, functionName: string): string =
  modulePath & " :: " & functionName

func safeGetStr(node: JsonNode, key: string, default: string = ""): string =
  if node == nil or node.kind != JObject:
    return default
  if not node.hasKey(key):
    return default
  result = node[key].getStr(default)

func safeGetBool(node: JsonNode, key: string, default: bool = false): bool =
  if node == nil or node.kind != JObject:
    return default
  if not node.hasKey(key):
    return default
  result = node[key].getBool(default)

func parseCertJson(node: JsonNode, fileName: string, tracked: bool, inManifest: bool): CertRecord =
  result.fileName = fileName
  result.tracked = tracked
  result.inManifest = inManifest
  result.modulePath = safeGetStr(node, "modulePath")
  result.functionName = safeGetStr(node, "functionName")
  result.fingerprint = safeGetStr(node, "fingerprint")
  result.sourceHash = safeGetStr(node, "sourceHash")
  result.irHash = safeGetStr(node, "irHash")
  result.status = safeGetStr(node, "status")
  result.trusted = safeGetBool(node, "trusted")
  result.kernel = safeGetBool(node, "kernel")
  result.winningStrategy = safeGetStr(node, "winningStrategy")
  result.reason = safeGetStr(node, "reason")
  result.leanProposition = safeGetStr(node, "leanProposition")
  result.smtlib2 = safeGetStr(node, "smtlib2")
  result.solverStatus = safeGetStr(node, "solverStatus")
  let sm = node["solverMeta"]
  if sm != nil and sm.kind == JObject:
    result.solverProvenance = safeGetStr(sm, "solverProvenance")
    result.verificationTier = safeGetStr(node, "verificationTier")
  else:
    result.solverProvenance = ""
    result.verificationTier = ""

proc getTrackedSet(dir: string): HashSet[string] =
  let cmd = "git ls-files " & dir
  let output = execCmdEx(cmd).output.strip
  for line in output.splitLines:
    let trimmed = line.strip
    if trimmed.len > 0:
      result.incl(trimmed)

proc loadManifest(dir: string): HashSet[string] =
  let manifestPath = dir / ManifestName
  if not fileExists(manifestPath):
    return result
  let content = readFile(manifestPath)
  let node = parseJson(content)
  let entries = node["entries"]
  if entries == nil or entries.kind != JArray:
    return result
  for entry in entries.items:
    let mp = entry["modulePath"].getStr("")
    let fn = entry["functionName"].getStr("")
    if mp.len > 0 and fn.len > 0:
      result.incl(identityKey(mp, fn))

proc classifyDir(dir: string): (seq[CertRecord], Counts, seq[ClassGroup], seq[IdentityEntry], seq[ReportEntry]) =
  var certs: seq[CertRecord]
  var counts: Counts
  var classGroups: Table[string, int]
  var identityMap: Table[string, seq[CertRecord]]
  var manifestKeys: HashSet[string]

  manifestKeys = loadManifest(dir)
  let trackedSet = getTrackedSet(dir)

  if not dirExists(dir):
    return (certs, counts, @[], @[], @[])

  for entry in walkDirRec(dir, {pcFile}):
    let fullPath = entry
    let baseName = entry.splitPath.tail
    if baseName == ManifestName:
      continue
    if not baseName.endsWith(".json"):
      continue

    let relPath = entry
    let isTracked = trackedSet.contains(relPath)
    if isTracked:
      counts.tracked += 1
    else:
      counts.untracked += 1
    counts.totalFiles += 1

    let content = readFile(fullPath)
    let node = parseJson(content)
    if not node.hasKey("modulePath") or not node.hasKey("functionName"):
      continue
    var cert = parseCertJson(node, baseName, isTracked, false)

    let ik = identityKey(cert.modulePath, cert.functionName)
    let inManifest = manifestKeys.contains(ik)
    cert.inManifest = inManifest
    if inManifest:
      counts.inManifest += 1

    if cert.status == "certRed":
      counts.certRed += 1
    elif cert.status == "certGreen":
      counts.certGreen += 1
    elif cert.status == "certLeanVerified":
      counts.certLeanVerified += 1

    if cert.kernel:
      counts.kernel += 1

    let classKey = cert.status & "|" & cert.solverProvenance & "|" & cert.verificationTier & "|" & cert.winningStrategy
    classGroups[classKey] = classGroups.getOrDefault(classKey) + 1

    identityMap.mgetOrPut(ik, @[]).add(cert)
    certs.add(cert)

  counts.duplicateIdentities = 0
  var identityEntries: seq[IdentityEntry]
  var reportEntries: seq[ReportEntry]

  let sortedIdentities = toSeq(identityMap.keys).sorted
  for ik in sortedIdentities:
    let entries = identityMap[ik]
    let parts = ik.split("\x00")
    let modPath = if parts.len > 0: parts[0] else: ""
    let funcName = if parts.len > 1: parts[1] else: ""
    let isDuplicate = entries.len > 1
    if isDuplicate:
      counts.duplicateIdentities += 1

    var files: seq[string]
    var statuses: HashSet[string]
    var trackedCount = 0
    var untrackedCount = 0
    var manifestCount = 0
    var kernelCount = 0
    for e in entries:
      files.add(e.fileName)
      if e.tracked: trackedCount += 1
      else: untrackedCount += 1
      if e.inManifest: manifestCount += 1
      if e.kernel: kernelCount += 1
      statuses.incl(e.status)

    let primaryStatus = if statuses.len > 0: toSeq(statuses)[0] else: ""
    let primaryIrHash = entries[0].irHash
    let primaryFingerprint = entries[0].fingerprint
    let primarySourceHash = entries[0].sourceHash
    let primaryTrusted = entries[0].trusted

    identityEntries.add(IdentityEntry(
      identity: identityLabel(modPath, funcName),
      modulePath: modPath,
      functionName: funcName,
      irHash: primaryIrHash,
      fingerprint: primaryFingerprint,
      sourceHash: primarySourceHash,
      status: primaryStatus,
      tracked: trackedCount > 0,
      inManifest: manifestCount > 0,
      kernel: kernelCount > 0,
      trusted: primaryTrusted,
      files: files.sorted
    ))

    for e in entries:
      reportEntries.add(ReportEntry(
        fileName: e.fileName,
        identity: identityLabel(modPath, funcName),
        modulePath: modPath,
        functionName: funcName,
        irHash: e.irHash,
        fingerprint: e.fingerprint,
        sourceHash: e.sourceHash,
        status: e.status,
        tracked: e.tracked,
        inManifest: e.inManifest,
        kernel: e.kernel,
        trusted: e.trusted,
        winningStrategy: e.winningStrategy,
        solverProvenance: e.solverProvenance,
        verificationTier: e.verificationTier
      ))

  let sortedReport = reportEntries.sortedByIt((it.identity, it.fileName))

  var classSeq: seq[ClassGroup]
  let sortedClassKeys = toSeq(classGroups.keys).sorted
  for k in sortedClassKeys:
    let parts = k.split("|")
    classSeq.add(ClassGroup(
      status: if parts.len > 0: parts[0] else: "",
      solverProvenance: if parts.len > 1: parts[1] else: "",
      verificationTier: if parts.len > 2: parts[2] else: "",
      winningStrategy: if parts.len > 3: parts[3] else: "",
      count: classGroups[k]
    ))

  let sortedIdentityEntries = identityEntries.sortedByIt(it.identity)

  return (certs, counts, classSeq, sortedIdentityEntries, sortedReport)

proc buildOutput(dir: string): ClassificationOutput =
  let (_, counts, classes, byIdentity, report) = classifyDir(dir)
  result.version = Version
  result.generatedAt = format(now(), "yyyy-MM-dd'T'HH:mm:ss'Z'")
  result.counts = counts
  result.classes = classes
  result.byIdentity = byIdentity
  result.report = report

proc main() =
  var outPath = ""
  var certDir = DefaultDir

  var i = 1
  while i <= paramCount():
    let arg = paramStr(i)
    if arg == "--out" and i + 1 <= paramCount():
      outPath = paramStr(i + 1)
      i += 2
    elif arg == "--dir" and i + 1 <= paramCount():
      certDir = paramStr(i + 1)
      i += 2
    else:
      i += 1

  let output = buildOutput(certDir)
  let jsonStr = $(%output)

  if outPath.len > 0:
    let parentDir = outPath.parentDir
    if parentDir.len > 0 and not dirExists(parentDir):
      createDir(parentDir)
    writeFile(outPath, jsonStr)
    echo "Wrote classification report to: " & outPath
  else:
    echo jsonStr

when isMainModule:
  main()