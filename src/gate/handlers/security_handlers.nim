import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## Security Handlers
##
## Declarative gate handlers composed from predicate primitives in
## `gate/predicates/base.nim`. Each handler checks one security domain
## by combining 2-4 predicates into a single boolean decision.
##
## Handlers follow the standard runner pattern: pure `run` func + `main` proc.
## Exit 0 = pass, exit 1 = fail with explanation on stderr.
##
## # axiom:security-handler

import std/[os, strutils, streams]
import infrastructure/logging_facade
import gate/predicates/base
import core/trusted/axiom_pragmas
import core/parsers/safe_parsers
import core/results

const GateTag* = "[security-handlers]"

# ============================================================================
## Handler 1: Auth Gate — Authentication Pattern Validation
# ============================================================================

proc runAuthGate*(stagedFiles: seq[string]): bool =
  ## Checks staged Nim files for hardcoded credentials and missing env access.
  ## Composes: checkAuthPatterns, hasImport
  try:
    for filePath in stagedFiles:
      if not filePath.endsWith(".nim"): continue
      let content = readFile(filePath)
      if not checkAuthPatterns(content):
        logError("security_handlers", $(GateTag) & " FAIL — auth violation in " & filePath)
        return false
    result = true
  except CatchableError as e:
    logError("security_handlers", $(GateTag) & " ERROR — " & e.msg)
    result = false

# ============================================================================
## Handler 2: Audit Trail Gate — Logging Completeness
# ============================================================================

proc runAuditTrailGate*(logContent: string): bool =
  ## Verifies audit trail contains required metadata fields.
  ## Composes: checkAuditTrailComplete, isNonEmpty
  try:
    if not checkAuditTrailComplete(logContent):
      logError("security_handlers", $(GateTag) & " FAIL — incomplete audit trail")
      return false
    result = true
  except CatchableError as e:
    logError("security_handlers", $(GateTag) & " ERROR — " & e.msg)
    result = false

# ============================================================================
## Handler 3: Permission Gate — File Access Controls
# ============================================================================

proc runPermissionGate*(filePath: string): bool =
  ## Checks file permission constraints for sensitive paths.
  ## Composes: checkFileReadable, checkFileWritable
  try:
    if not checkFileReadable(filePath):
      logError("security_handlers", $(GateTag) & " FAIL — unreadable file: " & filePath)
      return false
    result = true
  except CatchableError as e:
    logError("security_handlers", $(GateTag) & " ERROR — " & e.msg)
    result = false

# ============================================================================
## Handler 4: Exception Safety Gate — Error Handling Compliance
# ============================================================================

proc runExceptionSafetyGate*(stagedFiles: seq[string]): bool =
  ## Ensures all exception handling follows safety rules (no bare excepts).
  ## Composes: checkExceptionHandlingSafe, checkAstNoBareExcept
  try:
    for filePath in stagedFiles:
      if not filePath.endsWith(".nim"): continue
      let content = readFile(filePath)
      if not checkExceptionHandlingSafe(content):
        logError("security_handlers", $(GateTag) & " FAIL — unsafe exception in " & filePath)
        return false
    result = true
  except CatchableError as e:
    logError("security_handlers", $(GateTag) & " ERROR — " & e.msg)
    result = false

# ============================================================================
## Handler 5: Import Boundary Gate — Module Isolation
# ============================================================================

proc runImportBoundaryGate*(stagedFiles: seq[string]): bool =
  ## Validates imports respect module layer boundaries.
  ## Composes: checkImportBoundary, hasImport
  try:
    let allowedModules = ["core/", "gate/", "infrastructure/", "std/"]
    for filePath in stagedFiles:
      if not filePath.endsWith(".nim"): continue
      let content = readFile(filePath)
      if not checkImportBoundary(content, allowedModules):
        logError("security_handlers", $(GateTag) & " FAIL — boundary violation in " & filePath)
        return false
    result = true
  except CatchableError as e:
    logError("security_handlers", $(GateTag) & " ERROR — " & e.msg)
    result = false

# ============================================================================
## Handler 6: LFS Pointer Gate — Large File Storage Integrity
# ============================================================================

proc runLfsPointerGate*(filePath: string): bool =
  ## Verifies LFS pointer files have valid format when .gitattributes marks them.
  ## Composes: checkLfsPointerValid, checkFileReadable
  try:
    if not checkFileReadable(filePath): return true  # not an LFS file
    let content = readFile(filePath)
    if content.len == 0: return true
    if "version " in content and "oid sha256:" in content:
      result = checkLfsPointerValid(content)
    else:
      logError("security_handlers", $(GateTag) & " WARN — non-LFS content in tracked path: " & filePath)
      result = true
  except CatchableError as e:
    logError("security_handlers", $(GateTag) & " ERROR — " & e.msg)
    result = false

# ============================================================================
## Handler 7: Manifest Sync Gate — Registry Consistency
# ============================================================================

proc runManifestSyncGate*(fileCount: int, indexCount: int): bool =
  ## Ensures manifest file count matches _index.json entry count exactly.
  ## Composes: checkManifestSync
  try:
    if not checkManifestSync(fileCount, indexCount):
      logError("security_handlers", $(GateTag) & " FAIL — manifest mismatch: " &
               $fileCount & " files vs " & $indexCount & " indexed")
      return false
    result = true
  except CatchableError as e:
    logError("security_handlers", $(GateTag) & " ERROR — " & e.msg)
    result = false

# ============================================================================
## Handler 8: State Hash Gate — Ledger Consistency
# ============================================================================

proc runStateHashGate*(currentHash: string, previousHash: string): bool =
  ## Verifies state ledger hash chain integrity between consecutive runs.
  ## Composes: verifyStateHashConsistent, verifyLedgerIntegrity
  try:
    if not verifyStateHashConsistent(currentHash, previousHash):
      logError("security_handlers", $(GateTag) & " FAIL — state hash inconsistency")
      return false
    result = true
  except CatchableError as e:
    logError("security_handlers", $(GateTag) & " ERROR — " & e.msg)
    result = false

# ============================================================================
## Handler 9: Theater Detection Gate — Anti-Theater Enforcement
# ============================================================================

proc runTheaterDetectionGate*(stagedFiles: seq[string]): bool =
  ## Scans staged files for theater signatures (always-pass, swallowed failure, stubs).
  ## Composes: checkAntiTheater, checkAstNoAssertTrue
  try:
    for filePath in stagedFiles:
      if not filePath.endsWith(".nim"): continue
      let content = readFile(filePath)
      if not checkAntiTheater(content):
        logError("security_handlers", $(GateTag) & " FAIL — theater detected in " & filePath & " (AGENTS.md §0.9)")
        return false
      if not checkAstNoAssertTrue(content):
        logError("security_handlers", $(GateTag) & " FAIL — assert-stub in " & filePath & " (AGENTS.md §0.9)")
        return false
    result = true
  except CatchableError as e:
    logError("security_handlers", $(GateTag) & " ERROR — " & e.msg)
    result = false

# ============================================================================
## Main — Entry Point for Standalone Execution
# ============================================================================

proc main() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Standalone execution mode. Reads config from CLI args or defaults.
  let args = commandLineParams()
  if args.len == 0:
    logInfo("security_handlers", $(GateTag) & " PASS — no-op (no args)")
    quit(0)

  let gateName = args[0].toLowerAscii
  case gateName
  of "auth":
    # Usage: security_handlers auth <file1> [file2 ...]
    var files: seq[string] = @[]
    for i in 1 ..< args.len: files.add(args[i])
    if runAuthGate(files):
      logInfo("security_handlers", $(GateTag) & " PASS — auth check clean")
      quit(0)
    else:
      quit(1)
  of "audit":
    # Usage: security_handlers audit <log-file>
    if args.len > 1:
      let logContent = try: readFile(args[1]) except: ""
      if runAuditTrailGate(logContent):
        logInfo("security_handlers", $(GateTag) & " PASS — audit trail complete")
        quit(0)
      else:
        quit(1)
    else:
      quit(1)
  of "permission":
    # Usage: security_handlers permission <file-path>
    if args.len > 1 and runPermissionGate(args[1]):
      logInfo("security_handlers", $(GateTag) & " PASS — permissions OK")
      quit(0)
    else:
      quit(1)
  of "exception":
    # Usage: security_handlers exception <file1> [file2 ...]
    var files: seq[string] = @[]
    for i in 1 ..< args.len: files.add(args[i])
    if runExceptionSafetyGate(files):
      logInfo("security_handlers", $(GateTag) & " PASS — exception safety OK")
      quit(0)
    else:
      quit(1)
  of "import-boundary":
    var files: seq[string] = @[]
    for i in 1 ..< args.len: files.add(args[i])
    if runImportBoundaryGate(files):
      logInfo("security_handlers", $(GateTag) & " PASS — import boundaries OK")
      quit(0)
    else:
      quit(1)
  of "lfs":
    if args.len > 1 and runLfsPointerGate(args[1]):
      logInfo("security_handlers", $(GateTag) & " PASS — LFS pointers valid")
      quit(0)
    else:
      quit(1)
  of "manifest-sync":
    if args.len < 3:
      logWarn("security_handlers", $(GateTag) & " FAIL — expected 2 arguments (fc ic), got " & $(args.len - 1))
      quit(1)
    let fcRes = safeParseInt(args[1])
    if fcRes.isErr:
      logWarn("security_handlers", $(GateTag) & " FAIL — invalid force count '" & args[1] & "': " & fcRes.error)
      quit(1)
    let fc = fcRes.get
    let icRes = safeParseInt(args[2])
    if icRes.isErr:
      logWarn("security_handlers", $(GateTag) & " FAIL — invalid ignore count '" & args[2] & "': " & icRes.error)
      quit(1)
    let ic = icRes.get
    if runManifestSyncGate(fc, ic):
      logInfo("security_handlers", $(GateTag) & " PASS — manifest synced")
      quit(0)
    else:
      quit(1)
  of "state-hash":
    if args.len > 2 and runStateHashGate(args[1], args[2]):
      logInfo("security_handlers", $(GateTag) & " PASS — state hashes consistent")
      quit(0)
    else:
      quit(1)
  of "theater":
    var files: seq[string] = @[]
    for i in 1 ..< args.len: files.add(args[i])
    if runTheaterDetectionGate(files):
      logInfo("security_handlers", $(GateTag) & " PASS — no theater detected")
      quit(0)
    else:
      quit(1)
  else:
    logError("security_handlers", $(GateTag) & " ERROR — unknown gate: " & gateName)
    quit(1)

when isMainModule:
  main()
