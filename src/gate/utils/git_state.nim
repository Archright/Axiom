import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## git_state — Git repository state detection via filesystem invariant analysis
##
## Detects Git operational state by examining .git directory markers directly.
## Does NOT shell out to git (avoids self-referential wrapper calls).
##
## State precedence hierarchy (invariant):
##   rebase > rebase-conflict > cherry-pick > merge > revert > bisect > contextFree

import std/[os, strutils]
import core/axiom_pragmas

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type
  GitState* = enum
    gsContextFree        ## Normal: all policies active
    gsRebasing           ## rebase in progress (rebase-merge or rebase-apply)
    gsRebasingConflict   ## rebase + conflict (rebase-merge + MERGE_HEAD/CHERRY_PICK_HEAD)
    gsMerging            ## merge in progress (MERGE_HEAD)
    gsCherryPick         ## cherry-pick in progress (CHERRY_PICK_HEAD)
    gsReverting          ## revert in progress (REVERT_HEAD)
    gsBisecting          ## bisect in progress (BISECT_LOG)

  GitContext* = object
    state*: GitState
    gitDir*: string           ## Resolved .git directory (absolute path)
    headName*: string         ## Original branch name during rebase (from head-name file)
    onto*: string             ## Rebase --onto target
    conflictingFiles*: seq[string]  ## Files in conflict state

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const
  ## Flags that indicate a rebase resolution command.
  RebaseResolutionFlags*: array[6, string] = [
    "--continue", "--abort", "--skip", "--quit",
    "--edit-todo", "--show-current-patch"
  ]

  ## Flags that indicate a merge resolution command.
  MergeResolutionFlags*: array[3, string] = [
    "--continue", "--abort", "--quit"
  ]

  ## Flags that indicate a cherry-pick or revert resolution command.
  CherryPickRevertResolutionFlags*: array[3, string] = [
    "--continue", "--abort", "--quit"
  ]

# ---------------------------------------------------------------------------
# Git directory discovery
# ---------------------------------------------------------------------------

proc findGitDir*(): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Walk up from getCurrentDir() looking for `.git` (directory or file).
  ## For worktrees, `.git` is a file containing `gitdir: <path>`.
  ## The path may be absolute OR relative — MUST normalize to absolute.
  ## Returns "" if no .git is found.
  var dir = getCurrentDir()
  while true:
    let gitPath = dir / ".git"
    if dirExists(gitPath):
      return gitPath
    if fileExists(gitPath):
      let content = readFile(gitPath).strip()
      if content.startsWith("gitdir: "):
        let rawPath = content["gitdir: ".len .. ^1].strip()
        if isAbsolute(rawPath):
          return normalizedPath(rawPath)
        else:
          return normalizedPath(dir / rawPath)
    let parent = parentDir(dir)
    if parent == dir: break
    dir = parent
  return ""

# ---------------------------------------------------------------------------
# Rebase metadata readers
# ---------------------------------------------------------------------------

proc readRebaseHeadName(gitDir: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read the original branch name from `.git/rebase-merge/head-name`,
  ## stripping the `refs/heads/` prefix. Returns "" on any failure.
  let headNamePath = gitDir / "rebase-merge" / "head-name"
  if not fileExists(headNamePath):
    return ""
  try:
    var name = readFile(headNamePath).strip()
    if name.startsWith("refs/heads/"):
      name = name["refs/heads/".len .. ^1]
    return name
  except CatchableError:
    return ""

proc readRebaseOnto(gitDir: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read the onto target from `.git/rebase-merge/onto`.
  ## Returns "" on any failure.
  let ontoPath = gitDir / "rebase-merge" / "onto"
  if not fileExists(ontoPath):
    return ""
  try:
    return readFile(ontoPath).strip()
  except CatchableError:
    return ""

# ---------------------------------------------------------------------------
# Conflict detection
# ---------------------------------------------------------------------------

proc detectConflictingFiles(gitDir: string): seq[string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Detect files in conflict state by reading the index.
  ## Falls back to scanning for merge-relevant marker files.
  result = @[]

  # Primary: read conflicts from the index file via REFTABLE or packed-refs.
  # The most reliable filesystem-only approach during a merge/rebase conflict
  # is to look at the MERGE_HEAD and the .git/MERGE_MSG, then scan the worktree
  # for conflict markers. However, reading the index requires parsing the binary
  # index format. A simpler heuristic: if we are in a conflict state, the
  # conflicted files are embedded in MERGE_MSG or can be derived from the
  # rerere directory.

  # Heuristic: read MERGE_MSG for conflict context
  let mergeMsgPath = gitDir / "MERGE_MSG"
  if fileExists(mergeMsgPath):
    try:
      let content = readFile(mergeMsgPath)
      # MERGE_MSG often contains conflict markers or file listings
      for line in content.splitLines():
        let trimmed = line.strip()
        # Lines starting with "Unmerged paths:" or similar section headers
        # indicate conflict file listings follow
        if trimmed.len > 0 and not trimmed.startsWith("#") and
           not trimmed.startsWith("Merge") and
           not trimmed.startsWith("Conflicting") and
           not trimmed.startsWith("Conflicts"):
          # Heuristic: lines that look like file paths in conflict sections
          discard  # We cannot reliably extract filenames from MERGE_MSG alone
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

  # Secondary: check for rerere-tracked conflict resolution state
  let rerereDir = gitDir / "rr-cache"
  if dirExists(rerereDir):
    try:
      for entry in walkDir(rerereDir):
        if entry.kind == pcFile:
          result.add(entry.path.extractFilename())
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

  # Tertiary: during a rebase-apply, look at the stopped-sha or
  # the commit being applied for conflict hints.
  let stoppedShaPath = gitDir / "rebase-apply" / "stopped-sha"
  if fileExists(stoppedShaPath):
    # Presence of stopped-sha indicates a conflict during rebase-apply
    discard  # We record the state but cannot list specific files without git

# ---------------------------------------------------------------------------
# Main state detection
# ---------------------------------------------------------------------------

proc detectGitContext*(): GitContext =
  ## The main state detection proc with strict precedence hierarchy:
  ##   rebase > rebase-conflict > cherry-pick > merge > revert > bisect > contextFree
  ##
  ## Detects state by examining .git directory markers directly.
  ## Does NOT shell out to git.
  result = GitContext(
    state: gsContextFree,
    gitDir: "",
    headName: "",
    onto: "",
    conflictingFiles: @[]
  )

  let gitDir = findGitDir()
  if gitDir.len == 0:
    return result

  result.gitDir = gitDir

  # --- Highest priority: rebase detection ---
  let inRebaseMerge = dirExists(gitDir / "rebase-merge")
  let inRebaseApply = dirExists(gitDir / "rebase-apply")

  if inRebaseMerge or inRebaseApply:
    # Check for conflict during rebase: presence of MERGE_HEAD or
    # CHERRY_PICK_HEAD alongside rebase state indicates a conflict.
    let hasMergeHead = fileExists(gitDir / "MERGE_HEAD")
    let hasCherryPickHead = fileExists(gitDir / "CHERRY_PICK_HEAD")

    if hasMergeHead or hasCherryPickHead:
      result.state = gsRebasingConflict
      result.conflictingFiles = detectConflictingFiles(gitDir)
    else:
      result.state = gsRebasing

    # Read rebase metadata (only available during rebase-merge)
    if inRebaseMerge:
      result.headName = readRebaseHeadName(gitDir)
      result.onto = readRebaseOnto(gitDir)

    return result

  # --- Cherry-pick ---
  if fileExists(gitDir / "CHERRY_PICK_HEAD"):
    result.state = gsCherryPick
    return result

  # --- Merge ---
  if fileExists(gitDir / "MERGE_HEAD"):
    result.state = gsMerging
    result.conflictingFiles = detectConflictingFiles(gitDir)
    return result

  # --- Revert ---
  if fileExists(gitDir / "REVERT_HEAD"):
    result.state = gsReverting
    return result

  # --- Bisect ---
  if fileExists(gitDir / "BISECT_LOG"):
    result.state = gsBisecting
    return result

  # --- Default: context-free ---
  result.state = gsContextFree
  return result

# ---------------------------------------------------------------------------
# Resolution command detection
# ---------------------------------------------------------------------------

func hasResolutionFlag(argv: seq[string], flags: openArray[string]): bool =
  ## Check if argv contains any of the given resolution flags.
  for arg in argv:
    for flag in flags:
      if arg == flag:
        return true
  return false

func isResolutionCommand*(argv: seq[string], state: GitState): bool =
  ## Check if argv contains resolution flags appropriate for the given state.
  ## Returns true if the command is a valid resolution command for the state.
  case state
  of gsRebasing, gsRebasingConflict:
    return hasResolutionFlag(argv, RebaseResolutionFlags)
  of gsMerging:
    return hasResolutionFlag(argv, MergeResolutionFlags)
  of gsCherryPick, gsReverting:
    return hasResolutionFlag(argv, CherryPickRevertResolutionFlags)
  of gsBisecting:
    # Bisect has no resolution flags — any command is valid
    return false
  of gsContextFree:
    # No resolution needed when not in a conflict state
    return false

func isRebaseResolutionCommand*(argv: seq[string]): bool =
  ## Convenience wrapper: checks if argv contains rebase resolution flags.
  return hasResolutionFlag(argv, RebaseResolutionFlags)

func isMergeResolutionCommand*(argv: seq[string]): bool =
  ## Convenience wrapper: checks if argv contains merge resolution flags.
  return hasResolutionFlag(argv, MergeResolutionFlags)

{.pop.}
