import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## plumbing — Git plumbing command wrappers (thin facade)
##
## Wraps Git's low-level plumbing commands for deterministic,
## programmatic repository manipulation.
##
## Delegates to git_operations.nim (SSOT) for all git subprocess calls.
## Public API is preserved — callers are unaffected.
##
## Uses:
##   - git update-ref --stdin (transactional ref updates)
##   - git read-tree -m (3-way index merge)
##   - git merge-file (file-level 3-way merge)
##   - git cat-file blob (stage extraction)
##   - git ls-files -u (unmerged file listing)

import std/[osproc, strutils, strformat]
import core/interfaces/git_operations
import core/parsers/safe_parsers
import core/results

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc runGit(args: string): (string, int) =
  ## Executes a git command via the SSOT (git_operations.runGit).
  result = git_operations.runGit(args)

# ---------------------------------------------------------------------------
# Ref updates
# ---------------------------------------------------------------------------

proc updateRef*(refName: string, newValue: string, oldValue: string = ""): bool =
  ## Transactional ref update via `git update-ref --stdin`.
  var input: string
  if oldValue.len == 0:
    input = "create " & refName & " " & newValue & "\n"
  else:
    input = "update " & refName & " " & newValue & " " & oldValue & "\n"
  input.add("prepare\n")
  input.add("commit\n")

  let (_, exitCode) = execCmdEx(git_operations.findRealGit() & " update-ref --stdin", input = input)
  result = (exitCode == 0)

# ---------------------------------------------------------------------------
# 3-way index merge
# ---------------------------------------------------------------------------

proc readTreeMerge*(base, ours, theirs: string): bool =
  ## Loads a 3-way merge into the index via `git read-tree -m`.
  let (output, exitCode) = runGit(fmt"read-tree -m {base} {ours} {theirs}")
  result = (exitCode == 0)

# ---------------------------------------------------------------------------
# Stage extraction
# ---------------------------------------------------------------------------

proc checkoutIndexStage*(filePath: string, stage: int): string =
  ## Extracts a specific merge stage from the index.
  if stage notin 1..3:
    return ""

  let (lsOutput, lsExit) = runGit(fmt"ls-files -u -- {filePath}")
  if lsExit != 0:
    return ""

  let lines = lsOutput.strip().splitLines()
  for line in lines:
    let parts = line.split({'\t'})
    if parts.len < 2:
      continue
    let fields = parts[0].split({' '})
    if fields.len >= 3:
      let fileStageRes = safeParseInt(fields[2])
      if fileStageRes.isErr:
        continue
      let fileStage = fileStageRes.get
      if fileStage == stage:
        let blobHash = fields[1]
        let (blobOutput, blobExit) = runGit(fmt"cat-file blob {blobHash}")
        if blobExit == 0:
          return blobOutput
        return ""

  return ""

# ---------------------------------------------------------------------------
# File-level 3-way merge
# ---------------------------------------------------------------------------

proc mergeFile*(oursPath, basePath, theirsPath: string): int =
  ## Runs `git merge-file` on three files and writes the result back to oursPath.
  let (output, exitCode) = runGit(
    fmt"merge-file {oursPath} {basePath} {theirsPath}"
  )
  if exitCode < 0:
    return -1
  return exitCode

# ---------------------------------------------------------------------------
# Unmerged file listing
# ---------------------------------------------------------------------------

proc parseUnmergedOutput(raw: string): seq[string] =
  result = @[]
  var seen: seq[string] = @[]
  for line in raw.strip().splitLines():
    let trimmed = line.strip()
    if trimmed.len == 0:
      continue
    let tabParts = trimmed.split('\t')
    if tabParts.len < 2:
      continue
    let path = tabParts[tabParts.len - 1]
    if path notin seen:
      seen.add(path)
      result.add(path)

proc listUnmergedFiles*(): seq[string] =
  let (output, exitCode) = runGit("ls-files -u")
  if exitCode != 0:
    return @[]
  result = parseUnmergedOutput(output)

# ---------------------------------------------------------------------------
# Index update (mark resolved)
# ---------------------------------------------------------------------------

proc updateIndex*(filePath: string): bool =
  let (_, rmExit) = runGit(fmt"update-index --remove {filePath}")
  if rmExit != 0:
    return false
  let (_, addExit) = runGit(fmt"add {filePath}")
  result = (addExit == 0)

# ---------------------------------------------------------------------------
# Object hashing
# ---------------------------------------------------------------------------

proc hashObject*(filePath: string): string =
  let (output, exitCode) = runGit(fmt"hash-object {filePath}")
  if exitCode == 0:
    let trimmed = output.strip()
    if trimmed.len > 0 and trimmed.len == 40:
      return trimmed
  return ""

{.pop.}
