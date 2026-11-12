import core/trusted/layer_declaration
axiomLayer "tools"
import std/[osproc, strutils, sequtils]

const
  Identifiers = [
    "getCanonicalCertFilename", "ControlFlowGraph", "writeStderrLine",
    "proveWithFixedpoint", "findPrimaryLoopHeader", "checkApplicability",
    "buildLeanHintDatabase", "buildControlFlowGraph", "buildCfgFromAst",
    "verifyAxiomHash", "recordProvenanceOverwriteAttempt", "pkLinearizeVariables",
    "pkIsolateInterface", "pkInsertCompositionNode", "pkExtractPureFunction",
    "pkAddLoopInvariant", "pkAddDecreaseMeasure", "lookupAxiom",
    "isProvenanceProtected", "findLoopHeaders", "enforceProvenanceBeforeWrite",
    "axiomMatchesLeanProposition", "BasicBlock",
  ]

proc main() =
  echo "   # │ Identifier                               │ Last commit                                                │ Action"
  echo repeat("-", 120)
  for i, ident in Identifiers:
    let (logOut, _) = execCmdEx("git log --all -S " & ident & " --pretty=format:%H|%s -- '*.nim'")
    let commits = logOut.strip.splitLines.filterIt(it.len > 0)
    if commits.len == 0:
      echo align($(i + 1), 4) & " │ " & alignLeft(ident, 40) & " │ NO GIT HISTORY FOUND"
      continue
    let parts = commits[0].split("|", 1)
    let lastHash = parts[0]
    let lastMsg = if parts.len > 1: parts[1] else: ""
    let (diffOut, _) = execCmdEx("git show " & lastHash & " --pretty=format: -- '*.nim'")
    var deleted = false
    for line in diffOut.splitLines:
      if line.startsWith("-") and ident in line:
        deleted = true
        break
    let action = if deleted: "DELETED" else: "MODIFIED"
    let shortMsg = if lastMsg.len > 55: lastMsg[0..54] & "..." else: lastMsg
    echo align($(i + 1), 4) & " │ " & alignLeft(ident, 40) & " │ " & alignLeft(shortMsg, 60) & " │ " & action

when isMainModule:
  main()
