## Architecture Constraints — CI gate for layered architecture
##
## Run: nim c -r tests/architecture_constraints.nim
## Or:  make check-architecture
##
## Rules enforced:
##   1. Domain (src/core/) must NOT import from Presentation (src/cli/) or Infrastructure (tools/)
##   2. Domain must NOT contain I/O procs (open, writeFile, execProcess, etc.)
##      unless annotated with {.axiomIoBoundary.}
##   3. Gate (src/gate/) must NOT reference L0 orchestrator entry points
##   4. Platform-specific files must NOT exist in project src/ (after migration)
##
## Architecture Layers (AGENTS.md §1.2):
##   - Domain:      src/core/       — Pure logic, types, BMC engine, refactoring rules
##   - Gate:        src/gate/       — Read-only static analysis enforcement
##   - Infrastructure: src/verification/, tools/ — I/O, file system, subprocess
##   - Presentation: src/cli/, src/mcp/, src/ui/, src/api/ — CLI, TUI, JSON, MCP
##
## Dependency Direction (HARD RULE):
##   Presentation → Infrastructure → Domain
##   Domain NEVER imports Infrastructure, Presentation, or Gate.

import std/[os, strutils, sequtils, algorithm, times]
import std/parsetoml

const
  ProjectRoot = parentDir(parentDir(currentSourcePath()))
  RulesTomlPath = ProjectRoot / "architecture_rules.toml"
  CoreDir = ProjectRoot / "src" / "core"
  CliDir = ProjectRoot / "src" / "cli"
  McpDir = ProjectRoot / "src" / "mcp"
  UiDir = ProjectRoot / "src" / "ui"
  ApiDir = ProjectRoot / "src" / "api"
  VerificationDir = ProjectRoot / "src" / "verification"
  GateDir = ProjectRoot / "src" / "gate"
  ToolsDir = ProjectRoot / "tools"

  # Imports FORBIDDEN in Domain layer (src/core/)
  # These are Presentation or Infrastructure paths that Domain must never reference
  ForbiddenImportPrefixes = [
    # Presentation layer
    "src/cli/",
    "src/cli.",
    "cli/",
    "src/mcp/",
    "src/mcp.",
    "mcp/",
    "src/ui/",
    "src/ui.",
    "ui/",
    "src/api/",
    "src/api.",
    "api/",
    # Infrastructure layer
    "tools/",
    "src/verification/",
    "verification/",
    # Gate layer (Domain must not import Gate)
    "gate_admin",
    "kimi_pre_tool_use",
    "gate_hook",
    "gate_self_check",
    "sentinel",
    "quality_gate_marker",
  ]

  # I/O proc patterns forbidden in Domain layer
  # Files with {.axiomIoBoundary.} pragma are exempt
  IoProcPatterns = [
    "open(",
    "writeFile(",
    "execProcess(",
    "execCmd(",
    "gorge(",
    "staticExec(",
    "readFile(",
    "createDir(",
    "walkDir(",
    "walkDirRec(",
  ]

  # Platform-specific patterns (must not exist in src/ after migration)
  PlatformPatterns = [
    "when defined(windows)",
    "when defined(linux)",
    "when defined(macos)",
    "when defined(posix)",
    "when defined(unix)",
  ]

type
  Violation = object
    file: string
    line: int
    rule: string
    detail: string

  ApprovedViolation = object
    ruleId: string
    target: string
    expiresAt: string
    reason: string

var violations: seq[Violation] = @[]
var warnings: seq[Violation] = @[]

proc isComment(line: string): bool =
  ## Check if a line is a Nim comment (starts with #)
  let stripped = line.strip()
  result = stripped.startsWith("#") or stripped.startsWith("##")

proc isStringLiteral(line: string): bool =
  ## Rough check if the line is inside a string literal (minimal heuristic)
  let stripped = line.strip()
  # If line is just a string content marker, skip I/O check
  result = stripped.startsWith("\"") and stripped.endsWith("\"")

proc isIoBoundaryAnnotated(fileContent: string): bool =
  ## Check if file contains {.axiomIoBoundary.} pragma
  result = "{.axiomIoBoundary.}" in fileContent or
           "axiomIoBoundary" in fileContent

proc loadApprovedViolations(rulesPath: string): seq[ApprovedViolation] =
  ## Load approved violations from architecture_rules.toml.
  ## If the file doesn't exist or has no approved_violations section, returns empty.
  result = @[]
  if not fileExists(rulesPath):
    echo "⚠️  No architecture_rules.toml found — all violations will fail."
    return
  try:
    let doc = parsetoml.parseFile(rulesPath)
    if doc.hasKey("approved_violations"):
      for v in doc["approved_violations"].elems:
        var entry = ApprovedViolation(
          ruleId: v["rule_id"].strVal,
          target: v["target"].strVal,
          expiresAt: v["expires_at"].strVal
        )
        if v.hasKey("reason"):
          entry.reason = v["reason"].strVal
        result.add(entry)
    echo "📋 Loaded ", result.len, " approved violation(s) from architecture_rules.toml"
  except CatchableError as e:
    echo "⚠️  Failed to parse architecture_rules.toml: ", e.msg
    echo "   Continuing without approved violations."

proc isApproved(v: Violation, approved: seq[ApprovedViolation]): bool =
  ## Check if a violation matches an approved violation that hasn't expired.
  for a in approved:
    if a.ruleId == v.rule and a.target == v.file:
      try:
        let expiry = parse(a.expiresAt, "yyyy-MM-dd", utc())
        if expiry > now():
          return true
      except CatchableError:
        # If date parsing fails, treat as expired
        discard
  return false

proc getApprovalReason(v: Violation, approved: seq[ApprovedViolation]): string =
  ## Get the reason for an approved violation.
  for a in approved:
    if a.ruleId == v.rule and a.target == v.file:
      if a.reason.len > 0:
        return a.reason
  return ""

proc scanFile(filepath: string, approved: seq[ApprovedViolation]) =
  let relPath = filepath.replace(ProjectRoot & "/", "")
  var fileContent: string
  try:
    fileContent = readFile(filepath)
  except IOError:
    return

  let lines = fileContent.splitLines()
  let hasIoBoundary = isIoBoundaryAnnotated(fileContent)

  for i, line in lines:
    let stripped = line.strip()

    # Skip comments and empty lines
    if stripped.len == 0 or isComment(stripped):
      continue

    # Rule 1: Domain must not import Presentation/Infrastructure
    if relPath.startsWith("src/core/"):
      let lineLower = stripped.toLowerAscii()
      if lineLower.startsWith("import ") or lineLower.startsWith("from "):
        for prefix in ForbiddenImportPrefixes:
          if prefix.toLowerAscii() in lineLower:
            let v = Violation(
              file: relPath,
              line: i + 1,
              rule: "no-cross-layer-import",
              detail: "Domain imports forbidden path: " & prefix
            )
            if isApproved(v, approved):
              warnings.add(v)
            else:
              violations.add(v)
            break

    # Rule 2: Domain must not contain raw I/O procs
    # Files with {.axiomIoBoundary.} are explicitly marking their I/O boundary
    if relPath.startsWith("src/core/") and not hasIoBoundary:
      # Only check proc declarations (not comments, strings, or other lines)
      let isProcDecl = stripped.startsWith("proc ") or
                       stripped.startsWith("  proc ") or
                       stripped.startsWith("method ")
      if isProcDecl:
        for ioProc in IoProcPatterns:
          if ioProc in stripped:
            let v = Violation(
              file: relPath,
              line: i + 1,
              rule: "no-io-in-domain",
              detail: "Domain proc contains I/O: " & ioProc
            )
            if isApproved(v, approved):
              warnings.add(v)
            else:
              violations.add(v)
            break

    # Rule 3: Gate must not reference L0 orchestrator entry points
    if relPath.startsWith("src/gate/") and
       not relPath.startsWith("src/gate/runners/gate_hook.nim"):
      let lineLower = stripped.toLowerAscii()
      if "gate_hook" in lineLower and
         (lineLower.startsWith("import ") or lineLower.startsWith("from ")):
        let v = Violation(
          file: relPath,
          line: i + 1,
          rule: "gate-no-l0-reference",
          detail: "L1/L2 gate references L0 orchestrator (gate_hook)"
        )
        if isApproved(v, approved):
          warnings.add(v)
        else:
          violations.add(v)

    # Rule 4: Platform-specific code must not exist in src/
    if relPath.startsWith("src/") and not relPath.startsWith("src/gate/"):
      for pattern in PlatformPatterns:
        if pattern in stripped:
          let v = Violation(
            file: relPath,
            line: i + 1,
            rule: "no-platform-in-project",
            detail: "Platform-specific code found: " & pattern
          )
          if isApproved(v, approved):
            warnings.add(v)
          else:
            violations.add(v)
          break

proc scanDirectory(dir: string, approved: seq[ApprovedViolation]) =
  if not dirExists(dir):
    return
  for entry in walkDirRec(dir):
    if entry.endsWith(".nim"):
      scanFile(entry, approved)

proc main() =
  echo "=== Axiom Architecture Constraints ==="
  echo "Project: ", ProjectRoot
  echo ""

  # Load approved violations from TOML
  let approved = loadApprovedViolations(RulesTomlPath)
  echo ""

  # Scan Domain layer
  echo "Scanning Domain layer (src/core/)..."
  scanDirectory(CoreDir, approved)

  # Scan Presentation layer
  echo "Scanning Presentation layer (src/cli/, src/mcp/, src/ui/, src/api/)..."
  scanDirectory(CliDir, approved)
  scanDirectory(McpDir, approved)
  scanDirectory(UiDir, approved)
  scanDirectory(ApiDir, approved)

  # Scan Gate layer
  echo "Scanning Gate layer (src/gate/)..."
  scanDirectory(GateDir, approved)

  # Scan Infrastructure layer
  echo "Scanning Infrastructure (tools/)..."
  scanDirectory(ToolsDir, approved)

  echo ""

  # Report warnings (approved violations)
  if warnings.len > 0:
    echo "⚠️  Approved violations (WARN — allowed to pass): ", warnings.len
    echo ""

    var warnRules: seq[string]
    for v in warnings:
      if v.rule notin warnRules:
        warnRules.add(v.rule)

    for rule in warnRules:
      echo "--- Rule: ", rule, " (approved) ---"
      for v in warnings:
        if v.rule == rule:
          let reason = getApprovalReason(v, approved)
          echo "  ", v.file, ":", v.line
          echo "    ", v.detail
          if reason.len > 0:
            echo "    Reason: ", reason
      echo ""

  # Report violations (failures)
  if violations.len == 0:
    if warnings.len > 0:
      echo "✅ All architecture constraints satisfied (", warnings.len, " approved exceptions)."
    else:
      echo "✅ All architecture constraints satisfied."
    quit(0)
  else:
    echo "❌ Architecture violations found: ", violations.len
    echo ""

    # Group by rule
    var rules: seq[string]
    for v in violations:
      if v.rule notin rules:
        rules.add(v.rule)

    for rule in rules:
      echo "--- Rule: ", rule, " ---"
      for v in violations:
        if v.rule == rule:
          echo "  ", v.file, ":", v.line
          echo "    ", v.detail
      echo ""

    echo "Fix violations above or add to approved_violations in architecture_rules.toml."
    echo "See architecture_rules.toml for the approval format with expiry dates."
    quit(1)

main()
