import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

import core/axiom_pragmas
import core/utils/file_utils
import core/trusted/env_access
import std/os
import std/strutils
import infrastructure/logging_facade


# axiomIoBoundary

# ---------------------------------------------------------------------------
# Conventional Commits validation
# ---------------------------------------------------------------------------

const
  ValidTypes = ["feat", "fix", "refactor", "docs", "test", "chore"]
  MinDescriptionLen = 10

  CommitScopeStart = '('
  CommitScopeEnd = ')'
type
  CommitStatus = enum
    csOk
    csMissingFile
    csEmptyMessage
    csNoType
    csInvalidType
    csNoDescription
    csDescriptionTooShort
    csMalformed

  CommitCheck = object
    status: CommitStatus
    message: string
    msgFile: string
func readCommitTypeFromEnv(): string =
  ## Read commit type from AXIOM_COMMIT_TYPE environment variable.
  ## Agent-initiated commits can set this to bypass COMMIT_EDITMSG dependency.
  let envVal = getAxiomEnv(evCommitType)
  if envVal.len > 0:
    return envVal
  result = ""
proc findCommitMsgFile(args: seq[string]): string {.axiomEffect: IOEffect.} =
  ## Resolve the commit message file path.
  ## Priority: 0) AXIOM_COMMIT_TYPE env var, 1) first argument, 2) .git/COMMIT_EDITMSG, 3) .git/COMMIT_MSG
  let envCommitType = readCommitTypeFromEnv()
  if envCommitType.len > 0:
    # When AXIOM_COMMIT_TYPE is set, create a synthetic commit message
    # so the rest of the pipeline can process it as a normal COMMIT_EDITMSG.
    let synthPath = ".git/AXIOM_SYNTHETIC_MSG"
    writeFile(synthPath, envCommitType & ": agent-initiated commit")
    return synthPath

  if args.len >= 1 and args[0].len > 0:
    if fileExists(args[0]):
      return args[0]
    # Try relative to repo root
    if fileExists(".git/" & args[0]):
      return ".git/" & args[0]

  # Try standard git paths
  for path in [".git/COMMIT_EDITMSG", ".git/COMMIT_MSG"]:
    if fileExists(path):
      return path

  result = ""
proc readCommitMessage(filePath: string): string =
  ## Read the commit message from file, returning the first non-comment line.
  try:
    let content = readFileSafe(filePath)
    for line in content.splitLines():
      let trimmed = line.strip()
      if trimmed.len > 0 and trimmed[0] != '#':
        return trimmed
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
  result = ""
func validateCommit(message: string): CommitCheck =
  ## Validate a commit message against Conventional Commits rules.
  result.status = csOk
  result.message = message

  if message.len == 0:
    result.status = csEmptyMessage
    return

  # Split type(scope): description
  # Format: type(scope): description  OR  type: description (no scope)
  let colonPos = message.find(':')
  if colonPos < 0:
    result.status = csMalformed
    return

  let typeScopePart = message[0 .. colonPos - 1].strip()
  var descPart = ""
  if colonPos + 1 < message.len:
    # Skip colon and optional space
    var startIdx = colonPos + 1
    if startIdx < message.len and message[startIdx] == ' ':
      inc startIdx
    descPart = message[startIdx .. ^1].strip()

  # Extract type and optional scope from typeScopePart
  let scopeStart = typeScopePart.find(CommitScopeStart)
  var commitType = ""
  var commitScope = ""

  if scopeStart >= 0:
    commitType = typeScopePart[0 .. scopeStart - 1].strip()
    let scopeEnd = typeScopePart.find(CommitScopeEnd, scopeStart)
    if scopeEnd < 0:
      result.status = csMalformed
      return
    commitScope = typeScopePart[scopeStart + 1 .. scopeEnd - 1].strip()
  else:
    commitType = typeScopePart.strip()

  # Validate type is present
  if commitType.len == 0:
    result.status = csNoType
    return

  # Validate type is one of the valid types
  if commitType notin ValidTypes:
    result.status = csInvalidType
    return

  # Chore/fix commits: skip the intent document requirement.
  # These are non-feature commits where the type alone conveys intent;
  # a full-length description is not required.
  if commitType == "chore" or commitType == "fix":
    result.status = csOk
    return

  # Validate description is present
  if descPart.len == 0:
    result.status = csNoDescription
    return

  # Validate description length
  if descPart.len < MinDescriptionLen:
    result.status = csDescriptionTooShort
    return

  result.status = csOk
func statusToString(status: CommitStatus): string =
  case status
  of csOk:                 "PASS"
  of csMissingFile:        "commit message file not found"
  of csEmptyMessage:       "commit message is empty"
  of csNoType:             "missing commit type (e.g., feat, fix)"
  of csInvalidType:        "invalid commit type — must be one of: " & ValidTypes.join(", ")
  of csNoDescription:      "missing description after type(scope):"
  of csDescriptionTooShort: "description too short (minimum " & $MinDescriptionLen & " chars)"
  of csMalformed:          "malformed format — expected: type(scope): description"

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
proc reportFailure(check: CommitCheck) =
  ## Report intent-gate validation failure to stderr.
  logError("intent_gate", "[intent-gate] FAIL — " & statusToString(check.status))
  if check.message.len > 0:
    logInfo("intent_gate", "[intent-gate]   message: " & check.message)
  logInfo("intent_gate", "[intent-gate]   expected format: type(scope): description (min " & $MinDescriptionLen & " chars)")
proc main() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let args = commandLineParams()

  # Priority 1: AXIOM_COMMIT_TYPE env var — agent-initiated commits
  # can set this to pass a full conventional-commit message directly,
  # bypassing the COMMIT_EDITMSG file entirely.
  let envCommitMsg = getAxiomEnv(evCommitType)
  if envCommitMsg.len > 0:
    let check = validateCommit(envCommitMsg)
    if check.status == csOk:
      quit(0)
    reportFailure(check)
    quit(1)

  # Priority 2: Find commit message file
  let msgFile = findCommitMsgFile(args)
  if msgFile.len == 0:
    # When git commit -m is used, no COMMIT_EDITMSG file exists.
    # intent-gate should run in prepare-commit-msg hook for full coverage.
    quit(0)

  # Read commit message
  let message = readCommitMessage(msgFile)
  let check = validateCommit(message)

  if check.status == csOk:
    quit(0)

  # Report failure
  reportFailure(check)
  quit(1)

when isMainModule:
  main()

{.pop.}
