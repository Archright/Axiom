import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## DEBT#428: tools/mutation_harness.sh mutates only non-critical files and
## targets only `nim check bin/axiom` — the invariant mutation harness needs
## to exercise the critical gate-runner paths it is meant to protect.

## Anti-Theater Gate
##
## Enforces AGENTS.md §0.9 (Theater Prohibition) on git staged additions.
## Scans git diff output for four theater signatures:
##   S2 (swallowed failure): `except: discard` without `{.bestEffort("""reason""").}`
##   S1 (disguised stub): `check true` / `doAssert true` / `assert true` without `{.axiomEffect: IOEffect.}` gate effect
##   C  (known-dangerous swallow tripwire): `|| <rm|echo|true|:>` in CI config files without `{.bestEffort("""reason""").}`
##     CI files: Makefile, *.mk, .circleci/*.yml, .github/workflows/**/*.yml|.yaml, .github/actions/**/*.yml|.yaml
##     NOT a general fail-open verifier: `|| exit ...` is fail-closed and never flagged.
##   S3 (vsProved raw comparison): `status == vsProved` in proof-authoritative .nim files
##     (whitelist: verification_result_types.nim helper SSOT, anti_theater_gate.nim self-ref).
##     Raw comparison bypasses the semantic helper layer (isProved/isUnboundedProved/isBoundedProved),
##     enabling proof-authoritative decisions without scope awareness.
##
## Added-lines-only scope per Incremental Principle (§2). Exit 0 = clean.
## Exit 1 = violations listed on stderr.

import std/[os, osproc, strutils]
import core/axiom_pragmas
const debtMarker428 {.axiomDebt: "DEBT#428".} = true
import core/utils/repo_root
import infrastructure/logging_facade


const
  GateName* = "anti-theater-gate"
  GateTag* = "[anti-theater]"

type
  Violation* = object
    file*: string
    lineContent*: string
    rule*: string
    hint*: string

func hasTag*(line: string; tag: string): bool =
  tag in line

func hasBestEffortTag*(line: string): bool =
  "axiom:best-effort(" in line or "bestEffort(" in line

func matchesSrcOrToolsNim*(fileName: string): bool =
  (fileName.startsWith("src/") or fileName.startsWith("tools/")) and
  fileName.endsWith(".nim")

func matchesTestNim*(fileName: string): bool =
  fileName.startsWith("tests/") and fileName.endsWith(".nim")

func matchesCIFile*(fileName: string): bool =
  fileName == "Makefile" or
  fileName.endsWith(".mk") or
  (fileName.startsWith(".circleci/") and fileName.endsWith(".yml")) or
  (fileName.startsWith(".github/workflows/") and (fileName.endsWith(".yml") or fileName.endsWith(".yaml"))) or
  (fileName.startsWith(".github/actions/") and (fileName.endsWith(".yml") or fileName.endsWith(".yaml")))

func matchesVerificationResultTypes*(fileName: string): bool =
  fileName.endsWith("verification_result_types.nim")

func matchesProofAuthoritativeFile*(fileName: string): bool =
  matchesSrcOrToolsNim(fileName) and
  not matchesVerificationResultTypes(fileName) and
  not fileName.endsWith("anti_theater_gate.nim")

func isExceptDiscardSameLine*(line: string): bool =
  let trimmed = line.strip()
  trimmed.contains("except") and trimmed.contains("discard") and
  trimmed.contains(":")

func isExceptLine*(line: string): bool =
  let trimmed = line.strip()
  trimmed.startsWith("except") and trimmed.endsWith(":")

func isDiscardLine*(line: string): bool =
  line.strip() == "discard"

func isCheckTrueStub*(line: string): bool =
  let trimmed = line.strip()
  trimmed == "check true" or trimmed == "doAssert true" or trimmed == "assert true"

func hasFailOpenSwallow*(line: string): bool =
  ## Known-dangerous swallow patterns whose RHS makes a failing LHS succeed:
  ## `|| true`, `|| :`, `|| rm ...`, `|| echo ...` (and other no-op/cleanup RHS).
  ## NOT a general fail-open verifier: `|| exit ...` is fail-closed and never flagged.
  let parts = line.split("||")
  if parts.len < 2:
    return false
  let rhs = parts[^1].strip()
  rhs == "true" or rhs.startsWith("true ") or rhs.startsWith("true#") or
  rhs == ":" or
  rhs.startsWith("rm ") or
  rhs.startsWith("echo ")

func hasVsProvedRaw*(line: string): bool =
  "status == vsProved" in line or
  ".status == vsProved" in line

type
  DiffFile* = object
    fileName*: string
    lines*: seq[string]

func parseDiff*(diffText: string): seq[DiffFile] =
  var current: DiffFile
  for line in diffText.splitLines():
    if line.startsWith("+++ b/"):
      if current.fileName.len > 0 and current.lines.len > 0:
        result.add(current)
      current = DiffFile(fileName: line[6..^1])
    elif current.fileName.len > 0:
      if line.len > 0 and (line[0] == ' ' or line[0] == '+'):
        if line[0] == '+' and not line.startsWith("+++"):
          current.lines.add(line)

  if current.fileName.len > 0 and current.lines.len > 0:
    result.add(current)

func stripPlus*(line: string): string =
  if line.len > 0 and line[0] == '+':
    line[1..^1]
  else:
    line

func checkRuleA*(files: seq[DiffFile]): seq[Violation] =
  for df in files:
    if not matchesSrcOrToolsNim(df.fileName):
      continue
    let lines = df.lines
    for i in 0..<lines.len:
      let raw = lines[i]
      let content = stripPlus(raw)
      let prevContent = if i > 0: stripPlus(lines[i-1]) else: ""

      block sameLineCheck:
        if not isExceptDiscardSameLine(content):
          break sameLineCheck
        if hasBestEffortTag(content):
          break sameLineCheck
        result.add(Violation(
          file: df.fileName,
          lineContent: content.strip(),
          rule: "S2",
          hint: "Use {.bestEffort(\"\"\"reason\"\"\").} or handle the error properly"
        ))

      block multiLineCheck:
        if not isExceptLine(content):
          break multiLineCheck
        if i + 1 >= lines.len:
          break multiLineCheck
        let nextContent = stripPlus(lines[i+1])
        if not isDiscardLine(nextContent):
          break multiLineCheck
        if hasBestEffortTag(content) or hasBestEffortTag(nextContent):
          break multiLineCheck
        if hasBestEffortTag(prevContent):
          break multiLineCheck
        result.add(Violation(
          file: df.fileName,
          lineContent: (content.strip() & " " & nextContent.strip()).strip(),
          rule: "S2",
          hint: "Use {.bestEffort(\"\"\"reason\"\"\").} or handle the error properly"
        ))

func checkRuleB*(files: seq[DiffFile]): seq[Violation] =
  for df in files:
    if not matchesTestNim(df.fileName):
      continue
    let lines = df.lines
    for i in 0..<lines.len:
      let raw = lines[i]
      let content = stripPlus(raw)
      let prevContent = if i > 0: stripPlus(lines[i-1]) else: ""

      if not isCheckTrueStub(content):
        continue
      if hasTag(content, "axiom:compile-check") or hasTag(prevContent, "axiom:compile-check"):
        continue
      result.add(Violation(
        file: df.fileName,
        lineContent: content.strip(),
        rule: "S1",
        hint: "Tag with # axiom:compile-check or replace with a meaningful assertion"
      ))

func checkRuleC*(files: seq[DiffFile]): seq[Violation] =
  for df in files:
    if not matchesCIFile(df.fileName):
      continue
    let lines = df.lines
    for i in 0..<lines.len:
      let raw = lines[i]
      let content = stripPlus(raw)
      let prevContent = if i > 0: stripPlus(lines[i-1]) else: ""

      if not hasFailOpenSwallow(content):
        continue
      if hasBestEffortTag(content) or hasBestEffortTag(prevContent):
        continue
      result.add(Violation(
        file: df.fileName,
        lineContent: content.strip(),
        rule: "C",
        hint: "Remove known swallow pattern `|| <rm|echo|true|:>` — cleanup may not overwrite verification exit (AGENTS.md §4 fail-closed)"
      ))

func checkRuleS3*(files: seq[DiffFile]): seq[Violation] =
  for df in files:
    if not matchesProofAuthoritativeFile(df.fileName):
      continue
    let lines = df.lines
    for i in 0..<lines.len:
      let raw = lines[i]
      let content = stripPlus(raw)

      if not hasVsProvedRaw(content):
        continue
      result.add(Violation(
        file: df.fileName,
        lineContent: content.strip(),
        rule: "S3",
        hint: "Use isProved() / isUnboundedProved() / isBoundedProved() helper instead of raw status == vsProved"
      ))

func runAllChecks*(files: seq[DiffFile]): seq[Violation] =
  result.add(checkRuleA(files))
  result.add(checkRuleB(files))
  result.add(checkRuleC(files))
  result.add(checkRuleS3(files))

proc runGitDiff(cmd: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  let (output, exitCode) = execCmdEx(cmd)
  if exitCode != 0:
    logError("anti_theater_gate", $(GateTag) & " git command failed (exit " & $(exitCode) & "): " & cmd)
    return ""
  result = output

proc getDiffOutput(): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  result = runGitDiff("git diff --cached -U0")
  if result.len == 0 or result.strip().len == 0:
    result = runGitDiff("git diff -U0 HEAD")

proc main() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  let repoRoot = findRepoRoot()
  setCurrentDir(repoRoot)

  let diffOutput = getDiffOutput()
  if diffOutput.len == 0 or diffOutput.strip().len == 0:
    logInfo("anti_theater_gate", $(GateTag) & " PASS — no staged changes to check")
    quit(0)

  let files = parseDiff(diffOutput)
  if files.len == 0:
    logInfo("anti_theater_gate", $(GateTag) & " PASS — no added lines found")
    quit(0)

  let violations = runAllChecks(files)
  if violations.len == 0:
    logInfo("anti_theater_gate", $(GateTag) & " PASS — no theater signatures detected in " & $files.len & " file(s)")
    quit(0)

  logError("anti_theater_gate", $(GateTag) & " BLOCKED — " & $(violations.len) & " theater signature(s) detected:")
  for v in violations:
    logError("anti_theater_gate", "  " & v.file & ":" & v.lineContent & " | " & v.rule & " | " & v.hint)
  logInfo("anti_theater_gate", "")
  logError("anti_theater_gate", $(GateTag) & " Violations violate AGENTS.md §0.9 Theater Prohibition.")
  logError("anti_theater_gate", "  Fix: Remove always-pass patterns or add {.axiomDebt.} pragma. See AGENTS.md §0.5c for Quirk Spec.")
  quit(1)

when isMainModule:
  main()

static:
  const needle = "# " & "axiom:best-effort"
  const selfContent = staticRead(currentSourcePath())
  assert not selfContent.contains(needle), "Deprecated comment pattern found"

{.pop.}
