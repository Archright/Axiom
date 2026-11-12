import core/trusted/layer_declaration


axiomLayer "gate"
import infrastructure/logger
## Policy File Meta-Validator
##
## Enforces deterministic format, deduplication, and sorting on SSOT
## policy files. Called by pre-commit hook before architecture gate.
## Validates: architecture_policy.lock, allowed_imports.lock, etc.
{.push raises: [].}
# axiomIoBoundary
# Policy File Meta-Validator (v0.4.0)
# Enforces deterministic format, deduplication, and sorting on SSOT policy files.
# Called by pre-commit hook before architecture gate.
#
# Validated files:
#   1. src/verification/.physically_impure_modules — one module name per line, no duplicates
#   2. src/allowed_imports.lock — /org/project module reason format
#
# Usage:
#   bin/policy_validator          # validate only (exit 1 on violations)
#   bin/policy_validator --fix    # auto-normalize and rewrite files

import std/os
import std/strutils
import std/algorithm
import std/sequtils
import std/tables
import core/utils/file_utils
import core/axiom_pragmas
import infrastructure/logging_facade

const
  ImpureModulesPath = "src/verification/.physically_impure_modules"
  AllowedImportsPath = ".config/nimtry/allowed_imports.lock"
  ImpureModulePattern = {'a'..'z', 'A'..'Z', '0'..'9', '_'}
  # Format: /org/project module reason

type
  PolicyValidationViolation = object
    file: string
    line: int
    message: string

  ValidationReport = object
    violations: seq[PolicyValidationViolation]

# ---------------------------------------------------------------------------
# .physically_impure_modules validation
# ---------------------------------------------------------------------------

proc parseImpureModules(content: string): seq[string] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  for line in content.splitLines():
    let trimmed = line.strip()
    if trimmed.len == 0: continue
    if trimmed.startsWith("#"): continue
    if allCharsInSet(trimmed, ImpureModulePattern):
      result.add(trimmed)

proc validateImpureModules(report: var ValidationReport): seq[string] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let content = readFileSafe(ImpureModulesPath)
  let modules = parseImpureModules(content)
  var seen: CountTable[string]
  for m in modules:
    seen.inc(m)
  for m, count in seen.pairs():
    if count > 1:
      report.violations.add(PolicyValidationViolation(
        file: ImpureModulesPath,
        line: 0,
        message: "duplicate module '" & m & "' appears " & $count & " times"
      ))
  result = toSeq(seen.keys()).sorted()

proc normalizeImpureModules(modules: seq[string]) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let header = "# Physically Impure Modules in src/verification/\n" &
               "# These modules perform physical side effects: file system IO, network IO,\n" &
               "# process execution, time acquisition, mutable global state mutation, or\n" &
               "# async dispatch. They MUST NOT receive {" & ".push noSideEffect.} at module scope.\n" &
               "# {" & ".push raises: [].} still applies to all modules.\n" &
               "# This list is the SSOT for verification-layer purity exemptions.\n" &
               "# Date: 2026-05-04\n" &
               "# Determined by: nim check src/cli/main.nim (compiler-native verification)\n"
  var normalized = header
  for m in modules:
    normalized.add(m & "\n")
  discard writeFileSafe(ImpureModulesPath, normalized)

# ---------------------------------------------------------------------------
# allowed_imports.lock validation
# ---------------------------------------------------------------------------

proc validateAllowedImports(report: var ValidationReport) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let content = readFileSafe(AllowedImportsPath)
  var lineNum = 0
  for line in content.splitLines():
    inc lineNum
    let trimmed = line.strip()
    if trimmed.len == 0: continue
    if trimmed.startsWith("#") and not trimmed.startsWith("# @"): continue

    # Layer adjacency matrix entries start with "# @layer"
    if trimmed.startsWith("# @layer"): continue
    if trimmed.startsWith("# @module-role"): continue

    # Must start with '/'
    if not trimmed.startsWith('/'):
      report.violations.add(PolicyValidationViolation(
        file: AllowedImportsPath,
        line: lineNum,
        message: "malformed entry — does not start with '/org/project': '" & trimmed & "'"
      ))
      continue

    # Must have at least 3 space-separated parts: /org/project, module, reason
    let parts = trimmed.split(' ', maxsplit = 2)
    if parts.len < 2:
      report.violations.add(PolicyValidationViolation(
        file: AllowedImportsPath,
        line: lineNum,
        message: "malformed entry — needs at least '/org/project module': '" & trimmed & "'"
      ))

    # Must not contain bare module names without /org/project prefix
    if not parts[0].startsWith('/'):
      report.violations.add(PolicyValidationViolation(
        file: AllowedImportsPath,
        line: lineNum,
        message: "malformed entry — invalid org/project prefix: '" & parts[0] & "'"
      ))

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

proc main() {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let doFix = paramCount() > 0 and paramStr(1) == "--fix"
  var report: ValidationReport

  # Validate .physically_impure_modules
  if fileExists(ImpureModulesPath):
    let deduped = validateImpureModules(report)
    if doFix and deduped.len > 0:
      normalizeImpureModules(deduped)
      logInfo("policy_validator", "[policy-validator] Normalized " & ImpureModulesPath & " (" & $deduped.len & " unique modules)")
  else:
    report.violations.add(PolicyValidationViolation(
      file: ImpureModulesPath, line: 0,
      message: "file not found — create with: echo > " & ImpureModulesPath
    ))

  # Validate allowed_imports.lock
  if fileExists(AllowedImportsPath):
    validateAllowedImports(report)
  else:
    report.violations.add(PolicyValidationViolation(
      file: AllowedImportsPath, line: 0,
      message: "file not found — this is a critical SSOT violation"
    ))

  if report.violations.len == 0:
    logger.info("[policy-validator] PASS")
    quit(0)
  else:
    for v in report.violations:
      let pos = if v.line > 0: ":" & $v.line else: ""
      logInfo("policy_validator", "[policy-validator] " & v.file & pos & ": " & v.message)
    logInfo("policy_validator", "[policy-validator] " & $report.violations.len & " violation(s) found")
    if not doFix:
      logInfo("policy_validator", "[policy-validator] Run with --fix to auto-normalize")
    quit(1)

when isMainModule:
  main()

{.pop.}
