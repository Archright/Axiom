import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## Import Encapsulation Gate
##
## Blocks direct internal imports that bypass hub modules.
## Scans all .nim files for imports that reference internal implementation
## paths directly instead of going through hub modules.

import core/axiom_pragmas
import std/[os, options, strutils, tables, strformat, monotimes]
import core/results
import core/parsers/safe_parsers
import core/trusted/axiom_pragmas_lite
import infrastructure/logger
import core/gate/gate_vfs
import gate/gate_consts
import infrastructure/logging_facade


# axiomIoBoundary

type
  ImportEncapsulationViolation = object
    path: string
    lineNo: int
    content: string
    internal: string

proc isExempted(filepath: string; internal: string): bool {.raises: [].} =
  ## Check if filepath is exempted from importing internal path.
  # Intra-core imports are allowed
  if filepath.startsWith("src/core/"):
    return true
  # Exact file match in hubMapping
  if hubMapping.hasKey(filepath):
    for exc in hubMapping.getOrDefault(filepath):
      if internal.startsWith(exc):
        return true
  # Directory prefix match in hubMapping
  for hubKey, hubExceptions in hubMapping.pairs:
    if hubKey.endsWith("/") and filepath.startsWith(hubKey):
      for exc in hubExceptions:
        if internal.startsWith(exc):
          return true
  result = false

proc checkFile(filepath: string): seq[ImportEncapsulationViolation] {.raises: [], axiomEffect: IOEffect.} =
  ## Check a single file for import encapsulation violations.
  result = @[]
  var inImportBlock = false
  try:
    let fileContent = readFile(filepath)
    var lineNo = 0
    for line in fileContent.splitLines:
      lineNo += 1
      let stripped = line.strip
      if stripped.len == 0 or stripped.startsWith("#"):
        inImportBlock = false
        continue
      var isImportLine = false
      if stripped.startsWith("import ") or stripped.startsWith("from "):
        inImportBlock = false
        isImportLine = true
      elif stripped == "import":
        inImportBlock = true
        continue
      elif inImportBlock:
        if line.startsWith(" ") or line.startsWith("\t"):
          isImportLine = true
        else:
          inImportBlock = false
      if isImportLine:
        for internal in InternalPaths:
          if internal in stripped:
            if internal in filepath:
              continue
            if isExempted(filepath, internal):
              continue
            result.add(ImportEncapsulationViolation(path: filepath, lineNo: lineNo, content: stripped, internal: internal))
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

proc runImportEncapsulationScan*(repoRoot: string; files: seq[string]; severity: string = "error"): tuple[ok: bool; stdout: string; stderr: string] {.raises: [].} =
  var targetFiles: seq[string]
  if files.len > 0:
    targetFiles = files
  else:
    try:
      for path in walkDirRec(repoRoot / "src"):
        if path.endsWith(".nim"):
          targetFiles.add(path)
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

  var violations: seq[ImportEncapsulationViolation] = @[]
  for path in targetFiles:
    # Use repo-relative paths for exemption matching; gate_hook may pass
    # absolute paths, and walkDirRec also yields absolute paths.
    let relPath = try: relativePath(path, repoRoot, '/') except CatchableError: path
    let fileImportEncapsulationViolations = checkFile(relPath)
    for v in fileImportEncapsulationViolations:
      violations.add(v)

  var output = ""
  if violations.len > 0:
    if severity == "warn":
      # Phased rollout: warn-only mode — report violations but pass the gate
      output.add(&"[GUARD:WARN] {violations.len} import encapsulation violations (warn-only phase):\n")
      for v in violations:
        output.add(&"  {v.path}:{v.lineNo}: {v.content}\n")
      result = (ok: true, stdout: output, stderr: "")
    else:
      output.add(&"[GUARD] {violations.len} import encapsulation violations:\n")
      for v in violations:
        output.add(&"  {v.path}:{v.lineNo}: {v.content}\n")
      result = (ok: false, stdout: output, stderr: "")
  else:
    result = (ok: true, stdout: "[GUARD] All imports properly encapsulated. ✅\n", stderr: "")

proc main() {.axiomEffect: IOEffect.} =
  if paramCount() < 3:
    logInfo("import_encapsulation_gate", "Usage: import_encapsulation_gate <repoRoot> <mode> <maxJobs> [files...]")
    quit(1)
  let repoRoot = paramStr(1)
  let mode = paramStr(2)
  let maxJobsRes = safeParseInt(paramStr(3))
  if not maxJobsRes.isOk:
    logInfo("import_encapsulation_gate", "Invalid maxJobs: " & paramStr(3))
    quit(1)
  let maxJobs = maxJobsRes.get()
  var files: seq[string] = @[]
  for i in 4 .. paramCount():
    files.add(paramStr(i))
  let t0Ticks = getMonoTime().ticks
  let res = runImportEncapsulationScan(repoRoot, files)
  let elapsedMs = (getMonoTime().ticks - t0Ticks) div 1_000_000
  if elapsedMs > 500:
    logInfo("import_encapsulation_gate", &"axiom: [PERF] import-encapsulation took {elapsedMs}ms (threshold: 500ms) — consider caching")
  logger.info (if res.ok: "PASS" else: "FAIL") & " import-encapsulation"
  logger.info res.stdout
  quit(if res.ok: 0 else: 1)

proc checkFileVfs(ctx: GateContext; filepath: string): seq[ImportEncapsulationViolation] {.raises: [].} =
  ## VFS-aware version of checkFile.
  result = @[]
  var inImportBlock = false
  let contentOpt = vfsReadOpt(ctx, filepath)
  if contentOpt.isNone:
    return
  let fileContent = contentOpt.get()
  var lineNo = 0
  for line in fileContent.splitLines:
    lineNo += 1
    let stripped = line.strip
    if stripped.len == 0 or stripped.startsWith("#"):
      inImportBlock = false
      continue
    var isImportLine = false
    if stripped.startsWith("import ") or stripped.startsWith("from "):
      inImportBlock = false
      isImportLine = true
    elif stripped == "import":
      inImportBlock = true
      continue
    elif inImportBlock:
      if line.startsWith(" ") or line.startsWith("\t"):
        isImportLine = true
      else:
        inImportBlock = false
    if isImportLine:
      for internal in InternalPaths:
        if internal in stripped:
          if internal in filepath:
            continue
          if isExempted(filepath, internal):
            continue
          result.add(ImportEncapsulationViolation(path: filepath, lineNo: lineNo, content: stripped, internal: internal))

proc runImportEncapsulationScanVfs*(ctx: GateContext; repoRoot: string; files: seq[string]; severity: string = "error"): tuple[ok: bool; stdout: string; stderr: string] {.raises: [].} =
  ## VFS-aware version of runImportEncapsulationScan.
  var targetFiles: seq[string]
  if files.len > 0:
    targetFiles = files
  else:
    let entries = vfsListDir(ctx, repoRoot / "src")
    for path in entries:
      if path.endsWith(".nim"):
        targetFiles.add(path)

  var violations: seq[ImportEncapsulationViolation] = @[]
  for path in targetFiles:
    let relPath = try: relativePath(path, repoRoot, '/') except CatchableError: path
    let fileImportEncapsulationViolations = checkFileVfs(ctx, relPath)
    for v in fileImportEncapsulationViolations:
      violations.add(v)

  var output = ""
  if violations.len > 0:
    if severity == "warn":
      output.add(&"[GUARD:WARN] {violations.len} import encapsulation violations (warn-only phase):\n")
      for v in violations:
        output.add(&"  {v.path}:{v.lineNo}: {v.content}\n")
      result = (ok: true, stdout: output, stderr: "")
    else:
      output.add(&"[GUARD] {violations.len} import encapsulation violations:\n")
      for v in violations:
        output.add(&"  {v.path}:{v.lineNo}: {v.content}\n")
      result = (ok: false, stdout: output, stderr: "")
  else:
    result = (ok: true, stdout: "[GUARD] All imports properly encapsulated. ✅\n", stderr: "")

proc mainWithVfs*(ctx: GateContext) =
  ## VFS-aware entry point.
  if paramCount() < 3:
    logInfo("import_encapsulation_gate", "Usage: import_encapsulation_gate <repoRoot> <mode> <maxJobs> [files...]")
    quit(1)
  let repoRoot = paramStr(1)
  let mode = paramStr(2)
  let maxJobsRes = safeParseInt(paramStr(3))
  if not maxJobsRes.isOk:
    logInfo("import_encapsulation_gate", "Invalid maxJobs: " & paramStr(3))
    quit(1)
  var files: seq[string] = @[]
  for i in 4 .. paramCount():
    files.add(paramStr(i))
  let res = runImportEncapsulationScanVfs(ctx, repoRoot, files)
  logger.info (if res.ok: "PASS" else: "FAIL") & " import-encapsulation"
  logger.info res.stdout
  quit(if res.ok: 0 else: 1)

when isMainModule: main()

{.pop.}

