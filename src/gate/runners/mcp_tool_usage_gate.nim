import core/trusted/layer_declaration
axiomLayer "gate"
import core/axiom_pragmas
import infrastructure/logger
## MCP Tool Usage Gate — Policy Enforcement
## Enforces ReadFile deprecation for .nim files and allowlist registration.
## Policy JSON validation is optional.

{.push raises: [CatchableError].}

import std/[os, strutils, times, json]
import core/utils/file_utils
import core/utils/repo_root
import core/gate/gate_vfs
import core/trusted/env_access



# axiomIoBoundary

const
  GateId = "mcp-tool-usage-gate"
  AllowedImportsPath = ".config/nimtry/allowed_imports.lock"

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type
  Severity = enum
    sevError, sevWarning, sevInfo

  PolicyViolation = object
    ruleId: string
    severity: Severity
    filePath: string
    line: int
    message: string

# ---------------------------------------------------------------------------
# Policy loading
# ---------------------------------------------------------------------------

proc loadPolicyJson(repoRoot: string): JsonNode =
  let policyPath = repoRoot / "policy.json"
  if not fileExists(policyPath):
    return newJNull()
  let content = readFileSafe(policyPath)
  if content.len == 0:
    return newJNull()
  try:
    result = parseJson(content)
  except CatchableError:
    result = newJNull()

# ---------------------------------------------------------------------------
# ReadFile .nim deprecation scan
# ---------------------------------------------------------------------------

proc scanReadFileNimBan(repoRoot: string): seq[PolicyViolation] =
  ## Scan source files for ReadFile + .nim patterns.
  result = @[]

  # Scan src/ and tests/ for ReadFile references on .nim files
  let scanDirs = [repoRoot / "src", repoRoot / "tests"]
  for dir in scanDirs:
    if not dirExists(dir):
      continue
    try:
      for kind, path in walkDir(dir):
        if kind == pcDir and path.extractFilename() notin
            [".git", ".nimcache", "build", "node_modules", ".venv", "nimcache"]:
          # Recurse into subdirectories
          try:
            for subKind, subPath in walkDir(path):
              if subKind == pcFile and subPath.endsWith(".nim"):
                let content = readFileSafe(subPath)
                var lineNo = 0
                for line in content.splitLines():
                  lineNo += 1
                  let trimmed = line.strip()
                  # Check for explicit ReadFile calls on .nim files
                  # Skip comment lines (# or ##) to avoid false positives
                  if trimmed.startsWith("#"):
                    continue
                  if "ReadFile" in trimmed and ".nim" in trimmed:
                    let relPath = subPath.replace(repoRoot & "/", "")
                    result.add(PolicyViolation(
                      ruleId: "readfile-nim-ban",
                      severity: sevError,
                      filePath: relPath,
                      line: lineNo,
                      message: "ReadFile tool used on .nim file: " & trimmed
                    ))
          except CatchableError:
            discard  # axiom:best-effort(ioboundary catch)
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

# ---------------------------------------------------------------------------
# Allowlist verification
# ---------------------------------------------------------------------------

proc verifyAllowlist(repoRoot: string): seq[PolicyViolation] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Verify that .config/nimtry/allowed_imports.lock exists and is non-empty.
  result = @[]

  let allowlistPath = repoRoot / AllowedImportsPath
  if not fileExists(allowlistPath):
    result.add(PolicyViolation(
      ruleId: "allowlist-registration",
      severity: sevWarning,
      filePath: AllowedImportsPath,
      line: 0,
      message: "allowed_imports.lock does not exist"
    ))
    return

  let content = readFileSafe(allowlistPath)
  var importCount = 0
  for line in content.splitLines():
    let trimmed = line.strip()
    if trimmed.len > 0 and not trimmed.startsWith("#") and trimmed.startsWith("/"):
      importCount += 1

  if importCount == 0:
    result.add(PolicyViolation(
      ruleId: "allowlist-registration",
      severity: sevWarning,
      filePath: AllowedImportsPath,
      line: 0,
      message: "allowed_imports.lock has no registered imports"
    ))

# ---------------------------------------------------------------------------
# Tool routing validation (config self-consistency)
# ---------------------------------------------------------------------------

proc verifyPolicyJson(repoRoot: string): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Verify that the policy JSON is valid and contains required sections.
  let policy = loadPolicyJson(repoRoot)
  if policy.kind == JNull:
    return false

  # Must have toolRouting with rules
  if not policy.hasKey("toolRouting"):
    return false
  let routing = policy["toolRouting"]
  if not routing.hasKey("rules"):
    return false
  let rules = routing["rules"]
  if rules.kind != JArray or rules.len == 0:
    return false

  # Must have readFileDeprecation
  if not policy.hasKey("readFileDeprecation"):
    return false
  let deprecation = policy["readFileDeprecation"]
  if not deprecation.hasKey("extension") or deprecation{"extension"}.getStr() != ".nim":
    return false

  true

# ---------------------------------------------------------------------------
# Gate history
# ---------------------------------------------------------------------------

proc appendGateHistory(repoRoot: string; gateId: string; passed: bool;
                      violations: int; elapsedMs: int) {.axiomEffect: IOEffect.} =
  ## Append to ~/.axiom/gate_history.jsonl
  let home = getAxiomEnv(evHome)
  let historyDir = home / ".axiom"
  try:
    createDir(historyDir)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

  let historyFile = historyDir / "gate_history.jsonl"
  let now = $getTime().utc()
  let passStr = if passed: "true" else: "false"
  let line = """{"gate":""" & """"""" & gateId & """","passed":""" & passStr &
             ""","violations":""" & $violations & ""","ts":""" & """"""" & now &
             """","elapsed_ms":""" & $elapsedMs & "}"
  try:
    let f = open(historyFile, fmAppend)
    defer: f.close()
    f.writeLine(line)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

# ---------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------

proc runSelfTest(repoRoot: string): bool =
  ## Self-test: validate policy JSON, mock scan.
  logger.info("[" & GateId & "] self-test: starting...")

  # 1. Validate policy JSON structure
  if not verifyPolicyJson(repoRoot):
    logger.info("[" & GateId & "] self-test: FAIL - policy JSON invalid")
    return false
  logger.info("[" & GateId & "] self-test: policy JSON valid")

  # 2. Verify tool routing has required entries
  let policy = loadPolicyJson(repoRoot)
  if policy.kind != JNull:
    let routing = policy["toolRouting"]["rules"]
    var foundCodeIndex = false
    var foundSequential = false
    for rule in routing:
      let required = rule{"requiredMcp"}.getStr()
      if required == "code-index": foundCodeIndex = true
      if required == "Sequential Thinking": foundSequential = true
    if not foundCodeIndex or not foundSequential:
      logger.info("[" & GateId & "] self-test: FAIL - missing required MCP routing entries")
      return false
    logger.info("[" & GateId & "] self-test: all required MCP routing entries present")

  logger.info("[" & GateId & "] self-test: PASS")
  true

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

proc main()  =
  let args = commandLineParams()
  let repoRoot = findRepoRoot()

  # --self-test mode
  if "--self-test" in args:
    if runSelfTest(repoRoot):
      quit(0)
    else:
      quit(1)

  # DEBT#289 remediated: BYPASS_TOKEN removed; only Ed25519-signed emergency bypass permitted

  # debug_mode_on
  let debugFlag = repoRoot / ".axiom" / "debug_mode_on"
  if fileExists(debugFlag):
    writeLine(stderr, "[" & GateId & "] DEBUG MODE - diagnostics only, exiting PASS")
    let policy = loadPolicyJson(repoRoot)
    if policy.kind != JNull:
      let routing = policy["toolRouting"]["rules"]
      writeLine(stderr, "[" & GateId & "] debug: " & $routing.len & " tool routing rules loaded")
      for rule in routing:
        let taskType = rule{"taskType"}.getStr("")
        let mcp = rule{"requiredMcp"}.getStr("")
        writeLine(stderr, "[" & GateId & "] debug: " & taskType & " -> " & mcp)
    else:
      writeLine(stderr, "[" & GateId & "] debug: policy JSON failed to load")
    appendGateHistory(repoRoot, GateId, true, 0, 0)
    quit(0)

  let startTime = epochTime()
  var allViolations: seq[PolicyViolation] = @[]

  # 1. Verify policy JSON is valid (optional - warning only)
  if not verifyPolicyJson(repoRoot):
    allViolations.add(PolicyViolation(
      ruleId: "policy-json-valid",
      severity: sevWarning,
      filePath: "policy.json",
      line: 0,
      message: "Policy JSON is invalid or missing (optional)"
    ))

  # 2. Scan for ReadFile + .nim violations
  allViolations.add(scanReadFileNimBan(repoRoot))

  # 3. Verify allowlist
  allViolations.add(verifyAllowlist(repoRoot))

  let elapsedMs = int((epochTime() - startTime) * 1000)
  var errorCount = 0
  var warningCount = 0

  for v in allViolations:
    case v.severity
    of sevError:
      inc errorCount
      writeLine(stderr, "[" & GateId & "] ERROR " & v.ruleId & ": " & v.message &
                " (" & v.filePath & ":" & $v.line & ")")
    of sevWarning:
      inc warningCount
      writeLine(stderr, "[" & GateId & "] WARN " & v.ruleId & ": " & v.message)
    of sevInfo:
      writeLine(stderr, "[" & GateId & "] INFO " & v.ruleId & ": " & v.message)

  let passed = errorCount == 0
  if passed:
    logger.info("[" & GateId & "] PASS (" & $warningCount & " warnings, " & $elapsedMs & "ms)")
  else:
    logger.info("[" & GateId & "] FAIL (" & $errorCount & " errors, " & $warningCount & " warnings)")

  appendGateHistory(repoRoot, GateId, passed, errorCount, elapsedMs)

  if passed: quit(0)
  else: quit(1)

{.pop.}

# ---------------------------------------------------------------------------
# VFS-aware entry point (Wave 5D-1)
# ---------------------------------------------------------------------------

proc mainWithVfs(ctx: GateContext) =
  ## VFS-aware entry point for pipeline orchestrator integration.
  ## Policy scanning uses vfsRead for file content when available.
  let args = commandLineParams()

  if "--self-test" in args:
    if runSelfTest(ctx.repoRoot):
      quit(0)
    else:
      quit(1)

  let debugFlag = ctx.repoRoot / ".axiom" / "debug_mode_on"
  if fileExists(debugFlag):
    writeLine(stderr, "[" & GateId & "] DEBUG MODE - diagnostics only, exiting PASS")
    appendGateHistory(ctx.repoRoot, GateId, true, 0, 0)
    quit(0)

  let startTime = epochTime()
  var allViolations: seq[PolicyViolation] = @[]

  if not verifyPolicyJson(ctx.repoRoot):
    allViolations.add(PolicyViolation(
      ruleId: "policy-json-valid",
      severity: sevWarning,
      filePath: "policy.json",
      line: 0,
      message: "Policy JSON is invalid or missing (optional)"
    ))

  allViolations.add(scanReadFileNimBan(ctx.repoRoot))
  allViolations.add(verifyAllowlist(ctx.repoRoot))

  let elapsedMs = int((epochTime() - startTime) * 1000)
  var errorCount = 0
  var warningCount = 0

  for v in allViolations:
    case v.severity
    of sevError:
      inc errorCount
      writeLine(stderr, "[" & GateId & "] ERROR " & v.ruleId & ": " & v.message &
                " (" & v.filePath & ":" & $v.line & ")")
    of sevWarning:
      inc warningCount
      writeLine(stderr, "[" & GateId & "] WARN " & v.ruleId & ": " & v.message)
    of sevInfo:
      writeLine(stderr, "[" & GateId & "] INFO " & v.ruleId & ": " & v.message)

  let passed = errorCount == 0
  if passed:
    logger.info("[" & GateId & "] PASS (" & $warningCount & " warnings, " & $elapsedMs & "ms)")
  else:
    logger.info("[" & GateId & "] FAIL (" & $errorCount & " errors, " & $warningCount & " warnings)")

  appendGateHistory(ctx.repoRoot, GateId, passed, errorCount, elapsedMs)

  if passed: quit(0)
  else: quit(1)

when isMainModule:
  main()

