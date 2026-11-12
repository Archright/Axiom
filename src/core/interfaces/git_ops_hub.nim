import core/trusted/layer_declaration
axiomLayer "domain"
import core/interfaces/git_operations
import std/strutils
import std/osproc

{.push raises: [].}

## Git Operations IoC Hub
## Core modules import THIS instead of gate/utils/real_git directly.
## Composition Root (pipeline_dispatch.nim) injects the real implementation.
##
## findRealGit delegates to the SSOT in git_operations.nim.

type GitHashProc* = proc(): string {.nimcall, gcsafe, raises: [CatchableError].}

proc defaultGitHash(): string {.nimcall, gcsafe, raises: [CatchableError].} =
  try:
    let output = execProcess("git rev-parse --short HEAD", options={poEvalCommand})
    result = output.strip()
    if result.len == 0:
      raise newException(CatchableError, "git rev-parse returned empty")
  except:
    raise newException(CatchableError, "Failed to resolve git commit hash")

var getCommitHash* {.global.}: GitHashProc = defaultGitHash

var isGitInjected {.global.}: bool = false
var isIoCLocked {.global.}: bool = false

proc lockIoCRegistry*() =
  isIoCLocked = true

proc injectGitOps*(hashProc: GitHashProc) =
  if isIoCLocked:
    raise newException(Defect, "[Axiom IoC-FATAL] Registry locked. Re-injection forbidden.")
  if isGitInjected:
    raise newException(Defect, "Axiom IoC Violation: GitOps already injected, re-binding forbidden.")
  getCommitHash = hashProc
  isGitInjected = true

proc findRealGit*(): string {.inline, raises: [CatchableError].} =
  ## Returns the real git binary path (wrapper-avoidance).
  ## Delegates to the SSOT in git_operations.nim.
  git_operations.findRealGit()

{.pop.}
