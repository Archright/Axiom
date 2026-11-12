import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

import ../utils/real_git
import core/axiom_pragmas
import core/gate/gate_context as gate_context
import core/gate/gate_vfs as gate_vfs
import core/utils/file_utils
import gate/tag_parser
import std/os
import std/osproc
import std/strutils
import infrastructure/logging_facade


# axiomIoBoundary

let gitExe = findRealGit()
proc runProcedureGate*(cmd: string): bool =
  gate_context.withGate("procedure_gate"):
    if cmd == "cli":
      # CLI mode is the primary mode for this gate
      ctx.pass()
    else:
      ctx.fail("Unknown command: " & cmd)
proc main() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let (patch, _) = execCmdEx(gitExe & " diff --cached --unified=0 -- src src/semantic_proofs lakefile.toml lean-toolchain axiom.nimble config.nims")

  var styleOnly = true
  for rawLine in patch.splitLines:
    if rawLine.len == 0:
      continue
    if rawLine.startsWith("+++ ") or rawLine.startsWith("--- ") or
       rawLine.startsWith("@@") or rawLine.startsWith("diff ") or
       rawLine.startsWith("index ") or rawLine.startsWith("new file") or
       rawLine.startsWith("deleted file"):
      continue
    if rawLine.len < 1:
      continue
    let marker = rawLine[0]
    if marker != '+' and marker != '-':
      continue
    if rawLine.startsWith("+++ ") or rawLine.startsWith("--- "):
      continue
    let body = rawLine[1..^1].strip()
    if body.len == 0:
      continue
    if body.startsWith("#") or body.startsWith("//") or
       body.startsWith("/*") or body.endsWith("*/"):
      continue
    styleOnly = false
    break

  if styleOnly:
    return

  # BDD feature evidence check:
  # If the diff contains implementation files, require at least one
  # feature file (tests/features/*.feature) in the same commit.
  let (stagedFiles, _) = execCmdEx(gitExe & " diff --cached --name-only")
  var hasImplementation = false
  var hasFeatureEvidence = false
  for line in stagedFiles.splitLines:
    let file = line.strip()
    if file.len == 0:
      continue
    if isImplementationFile(file):
      hasImplementation = true
    if isFeatureEvidenceFile(file):
      hasFeatureEvidence = true

  if hasImplementation and not hasFeatureEvidence:
    logWarn("procedure_gate", "Warning: commit has implementation changes without a BDD feature evidence file")
    logWarn("procedure_gate", "         (tests/features/*.feature) — warning only, not blocking")

  # Spec-density validation: check @spec-density tags in staged feature files.
  const MinSpecDensity = 50
  for line in stagedFiles.splitLines:
    let file = line.strip()
    if file.len == 0 or not file.endsWith(".feature"):
      continue
    if fileExists(file):
      let content = readFile(file)
      let tags = parseFeatureTags(content)
      if tags.hasSpecDensity() and tags.getSpecDensity() < MinSpecDensity:
        logWarn("procedure_gate", "Warning: " & file &
          " spec-density " & $tags.getSpecDensity() &
          " below threshold " & $MinSpecDensity)

  if not runProcedureGate("cli"):
    quit(1)
proc mainWithVfs(ctx: gate_vfs.GateContext) =
  ## VFS entry point. Checks BDD feature evidence and spec-density via VFS.
  let patchResult = gate_vfs.vfsExec(ctx, "git", @["diff", "--cached", "--unified=0", "--", "src", "src/semantic_proofs", "lakefile.toml", "lean-toolchain", "axiom.nimble", "config.nims"])
  let patch = patchResult.output

  var styleOnly = true
  for rawLine in patch.splitLines:
    if rawLine.len == 0:
      continue
    if rawLine.startsWith("+++ ") or rawLine.startsWith("--- ") or
       rawLine.startsWith("@@") or rawLine.startsWith("diff ") or
       rawLine.startsWith("index ") or rawLine.startsWith("new file") or
       rawLine.startsWith("deleted file"):
      continue
    if rawLine.len < 1:
      continue
    let marker = rawLine[0]
    if marker != '+' and marker != '-':
      continue
    if rawLine.startsWith("+++ ") or rawLine.startsWith("--- "):
      continue
    let body = rawLine[1..^1].strip()
    if body.len == 0:
      continue
    if body.startsWith("#") or body.startsWith("//") or
       body.startsWith("/*") or body.endsWith("*/"):
      continue
    styleOnly = false
    break

  if styleOnly:
    return

  # BDD feature evidence check via VFS subprocess
  let stagedResult = gate_vfs.vfsExec(ctx, "git", @["diff", "--cached", "--name-only"])
  let stagedFiles = stagedResult.output
  var hasImplementation = false
  var hasFeatureEvidence = false
  for line in stagedFiles.splitLines:
    let file = line.strip()
    if file.len == 0:
      continue
    if isImplementationFile(file):
      hasImplementation = true
    if isFeatureEvidenceFile(file):
      hasFeatureEvidence = true

  if hasImplementation and not hasFeatureEvidence:
    logWarn("procedure_gate", "Warning: commit has implementation changes without a BDD feature evidence file")
    logWarn("procedure_gate", "         (tests/features/*.feature) — warning only, not blocking")

  # Spec-density validation via VFS
  const MinSpecDensity = 50
  for line in stagedFiles.splitLines:
    let file = line.strip()
    if file.len == 0 or not file.endsWith(".feature"):
      continue
    if gate_vfs.vfsExists(ctx, file):
      try:
        let content = gate_vfs.vfsRead(ctx, file)
        let tags = parseFeatureTags(content)
        if tags.hasSpecDensity() and tags.getSpecDensity() < MinSpecDensity:
          logWarn("procedure_gate", "Warning: " & file &
            " spec-density " & $tags.getSpecDensity() &
            " below threshold " & $MinSpecDensity)
      except KeyError:
        discard
  if not runProcedureGate("cli"):
    quit(1)

when isMainModule:
  main()

{.pop.}
