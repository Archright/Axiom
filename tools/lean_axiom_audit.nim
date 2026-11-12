import core/trusted/layer_declaration
axiomLayer "tools"

import std/[osproc, strutils, sequtils, tables, json, os, parseutils]
import infrastructure/process_utils

# ── Allowed-axiom policy ──────────────────────────────────
# Lean kernel guarantees soundness only up to declared axioms.
# Axiom's generated modules import only Init + Std.Tactic.BVDecide.
# The default allowlist contains axioms that are unavoidable when
# using the standard library's BVDecide tactic (which internally
# depends on Classical.choice and propositional extensionality).
# Any axiom outside this set is a policy violation.
#
# Policy rationale (from leanprover/lean4 official docs):
# - propext: propositional extensionality — used by BVDecide's
#   internal encoding of bit-vector comparisons.
# - Classical.choice: global choice — used by Classical.em which
#   BVDecide invokes for discharge.
# - Quot.sound: quotient soundness — transitively imported by
#   Classical.choice.
# - bv_decide.ax_*: BVDecide's internal decision-procedure axioms.
#
# If mathlib were imported, additional axioms (e.g.
# Mathlib.Classical.choice, Mathlib.Equiv.ax) would need explicit
# entries here.

const DefaultAllowedAxioms*: seq[string] = @[
  "propext",
  "Classical.choice",
  "Quot.sound",
]

# ── Parsing helpers ────────────────────────────────

func extractTheoremNames*(leanSource: string): seq[string] =
  ## Extract theorem names from a .lean source string.
  ## Matches lines of the form: `theorem <name> ...`
  for line in leanSource.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith("theorem "):
      let rest = trimmed[8 .. ^1].strip()
      if rest.len > 0 and rest[0].isAlphaAscii:
        let name = rest.split({' ', '(', '{', ':'})[0]
        if name.len > 0:
          result.add(name)

func parseAxiomBlock*(lines: seq[string]): seq[string] =
  ## Parse multi-line `#print axioms` output.
  ## Accumulates lines from a "depends on axioms:" line
  ## until the closing bracket, then returns the flattened
  ## axiom name list.
  var collecting = false
  var buffer = ""
  for line in lines:
    let s = line.strip()
    if s.contains("depends on axioms:"):
      collecting = true
      let marker = "depends on axioms:"
      let idx = s.find(marker)
      # Content after "depends on axioms:" may start with " ["
      # or directly with the first axiom name.
      buffer = s[idx + marker.len .. ^1].strip()
      # If buffer starts with "[", strip it — we'll find the closing "]" later.
      if buffer.startsWith("["):
        buffer = buffer[1 .. ^1].strip()
      continue
    if collecting:
      buffer.add(" " & s)
      if buffer.contains(']'):
        # Extract content up to the closing bracket
        let closeIdx = buffer.find(']')
        let content = buffer[0 ..< closeIdx]
        result = content.split(",").mapIt(it.strip()).filterIt(it.len > 0)
        collecting = false
        buffer = ""
      continue
    if s.contains("does not depend on any axioms"):
      return @[]

func isAxiomAllowed*(axiomName: string; allowed: seq[string]): bool =
  ## Check if an axiom name is in the allowed list.
  ## BVDecide internal axioms (bv_decide.ax_*) are always allowed
  ## as they are internal to the tactic plugin.
  if axiomName in allowed:
    return true
  if axiomName.contains("bv_decide.ax_"):
    return true
  false

# ── Core audit logic ───────────────────────────────

type
  AxiomAuditResult* = object
    theoremName*: string
    axiomsFound*: seq[string]
    violations*: seq[string]

type
  AxiomAuditReport* = object
    filePath*: string
    compiled*: bool
    compileOutput*: string
    results*: seq[AxiomAuditResult]
    allowedAxioms*: seq[string]
    totalViolations*: int

proc runLean*(leanFile: string): tuple[output: string; exitCode: int] =
  ## Run `lean <file>` and capture stdout+stderr.
  execCmdWithTimeout("lean " & leanFile, timeoutMs = 120_000)

proc buildAxiomPrintFile*(leanFile: string; theoremName: string): string =
  ## Build a temporary .lean file that includes the original content
  ## (with any trailing `#print axioms` line removed) plus
  ## `#print axioms <theoremName>` at the end.
  let source = readFile(leanFile)
  var lines = source.splitLines()
  # Remove trailing #print axioms lines (with or without theorem name)
  while lines.len > 0 and lines[^1].strip().startsWith("#print axioms"):
    discard lines.pop()
  # Remove trailing blank lines
  while lines.len > 0 and lines[^1].strip().len == 0:
    discard lines.pop()
  # Add the per-theorem #print axioms command
  lines.add("")
  lines.add("#print axioms " & theoremName)
  result = lines.join("\n")

proc auditFile*(leanFile: string; allowedAxioms: seq[string] = DefaultAllowedAxioms): AxiomAuditReport =
  ## Audit a .lean file for axiom policy violations.
  result.filePath = leanFile
  result.allowedAxioms = allowedAxioms

  # Step 1: Read source and extract theorem names
  if not fileExists(leanFile):
    result.compileOutput = "ERROR: file not found: " & leanFile
    return result

  let source = readFile(leanFile)
  let theoremNames = extractTheoremNames(source)
  if theoremNames.len == 0:
    result.compileOutput = "WARNING: no theorems found in " & leanFile
    return result

  # Step 2: Try compiling the file as-is first
  let (compileOut, compileCode) = runLean(leanFile)
  result.compileOutput = compileOut

  # Step 3: For each theorem, build a temp file with per-theorem #print axioms
  for tname in theoremNames:
    let tmpFile = getTempDir() / ("axiom_audit_" & tname & ".lean")
    let modifiedSource = buildAxiomPrintFile(leanFile, tname)
    writeFile(tmpFile, modifiedSource)
    try:
      let (axOut, axCode) = runLean(tmpFile)
      if axCode == 0:
        let axiomLines = axOut.splitLines()
        let foundAxioms = parseAxiomBlock(axiomLines)

        # Deduplicate
        var allAxioms: seq[string] = @[]
        for a in foundAxioms:
          if a notin allAxioms:
            allAxioms.add(a)

        # Step 4: Check against allowlist
        var violations: seq[string] = @[]
        for ax in allAxioms:
          if not isAxiomAllowed(ax, allowedAxioms):
            violations.add(ax)

        result.results.add(AxiomAuditResult(
          theoremName: tname,
          axiomsFound: allAxioms,
          violations: violations
        ))
        result.totalViolations += violations.len
      else:
        # Compilation failed for this theorem's audit file
        result.results.add(AxiomAuditResult(
          theoremName: tname,
          axiomsFound: @[],
          violations: @["compile error: " & axOut.splitLines()[0]]
        ))
        result.totalViolations += 1
    finally:
      try: removeFile(tmpFile) except: discard

  result.compiled = (compileCode == 0)

proc formatReport*(report: AxiomAuditReport): string =
  ## Format the audit report as human-readable text.
  result = ""
  result.add("=" & repeat("=", 72) & "\n")
  result.add("  Axiom Audit Report\n")
  result.add("  File: " & report.filePath & "\n")
  result.add("  Compiled: " & (if report.compiled: "YES" else: "NO") & "\n")
  result.add("  Allowed axioms: " & report.allowedAxioms.join(", ") & "\n")
  result.add("=" & repeat("=", 72) & "\n")

  if report.results.len == 0:
    result.add("\n[NO THEOREMS] No theorems found for audit.\n")
    if report.compileOutput.len > 0:
      result.add("Compilation output:\n" & report.compileOutput & "\n")
    return result

  for r in report.results:
    result.add("\n--- Theorem: " & r.theoremName & " ---\n")
    result.add("  Axioms found: " & (if r.axiomsFound.len > 0: r.axiomsFound.join(", ") else: "(none)") & "\n")
    if r.violations.len > 0:
      result.add("  VIOLATIONS (" & $r.violations.len & "):\n")
      for v in r.violations:
        result.add("    ✗ " & v & "\n")
    else:
      result.add("  ✓ No violations (all axioms are allowed)\n")

  result.add("\n" & "=" & repeat("=", 72) & "\n")
  result.add("  Total violations: " & $report.totalViolations & "\n")
  if report.totalViolations == 0:
    result.add("  AUDIT PASSED\n")
  else:
    result.add("  AUDIT FAILED\n")
  result.add("=" & repeat("=", 72) & "\n")

# ── CLI entry point ────────────────────────────────

proc main() =
  let args = commandLineParams()
  if args.len == 0 or args.contains("--help") or args.contains("-h"):
    echo """Usage: lean_axiom_audit <file.lean> [options]

Audit a Lean 4 module for axiom policy violations.

The tool compiles the .lean file with `lean`, extracts theorem names,
creates per-theorem audit files with `#print axioms <theorem>`, and
compares the resulting axiom list against an allowed-axiom policy.

Exit code 0: all axioms are allowed (audit passed)
Exit code 1: unallowed axioms found (audit failed)
Exit code 2: file not found or no theorems found

Options:
  --help, -h    Show this help message
"""
    quit(0)

  let leanFile = args[0]
  let report = auditFile(leanFile)
  echo report.formatReport()

  if report.results.len == 0:
    quit(2)

  if report.totalViolations > 0:
    quit(1)

  quit(0)

main()
