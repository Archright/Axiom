import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}

import core/axiom_pragmas
import core/interfaces/git_operations
import std/[json, os, times, hashes, sequtils, algorithm, strutils]

let gitExe* = git_operations.findRealGit()

const RING_BUFFER_SIZE* = 10
const WINDOW_SIZE* = 5
const SOURCE_EXTENSIONS = [".nim", ".c", ".cpp", ".h", ".rs", ".go", ".py", ".js", ".ts"]
const EXCLUDE_DIRS = [".git", "node_modules", "nimcache", "__pycache__", ".cache", "target", "build", "dist"]

type
  CommandContext* = object
    cmdString*: string
    effect*: int          # OpEffect ordinal (0=idempotent, 1=mutation, 2=transient, 3=derivation)
    contextHash*: string  # Epoch hash (Git SHA based)
    inputHash*: string    # oeDerivation input boundary hash
    success*: bool        # oeDerivation execution success
    timestamp*: string

  RingBuffer* = object
    entries*: array[RING_BUFFER_SIZE, CommandContext]
    head*: int      # next write position
    count*: int     # current item count

  DerivationDecision* = enum
    ddAllow        # 허용
    ddBlock        # 차단
    ddAllowNetwork # 네트워크 재시도 1회 허용

func initRingBuffer*(): RingBuffer =
  ## Initialize an empty ring buffer.
  result = RingBuffer(head: 0, count: 0)

func append*(rb: var RingBuffer, entry: CommandContext) =
  ## Add an entry at the head position, wrapping around at RING_BUFFER_SIZE.
  rb.entries[rb.head] = entry
  rb.head = (rb.head + 1) mod RING_BUFFER_SIZE
  if rb.count < RING_BUFFER_SIZE:
    rb.count += 1

func recentEntries*(rb: RingBuffer, n: int): seq[CommandContext] =
  ## Return up to `n` most recent entries in chronological order (oldest first).
  let actual = min(rb.count, n)
  if actual == 0:
    return @[]

  # Calculate the starting index: (rb.head - actual + RING_BUFFER_SIZE) mod RING_BUFFER_SIZE
  # This gives the oldest entry among the `actual` most recent ones.
  var startIdx = (rb.head - actual + RING_BUFFER_SIZE) mod RING_BUFFER_SIZE
  for i in 0 ..< actual:
    let idx = (startIdx + i) mod RING_BUFFER_SIZE
    result.add(rb.entries[idx])

proc loadFromDisk*(path: string): RingBuffer {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Load a RingBuffer from a JSON file. Fail-open: if the file doesn't exist
  ## or parsing fails, return an empty buffer.
  if not fileExists(path):
    return initRingBuffer()

  try:
    let data = parseFile(path)
    var rb = initRingBuffer()
    rb.head = data["head"].getInt()
    rb.count = data["count"].getInt()

    let entriesArr = data["entries"]
    var i = 0
    for entryVal in entriesArr:
      if i >= RING_BUFFER_SIZE:
        break
      var entry: CommandContext
      entry.cmdString = entryVal["cmdString"].getStr()
      entry.effect = entryVal["effect"].getInt()
      entry.contextHash = entryVal["contextHash"].getStr()
      entry.inputHash = entryVal["inputHash"].getStr()
      entry.success = entryVal["success"].getBool()
      entry.timestamp = entryVal["timestamp"].getStr()
      rb.entries[i] = entry
      i += 1

    # Ensure head and count are within valid bounds
    rb.head = rb.head mod RING_BUFFER_SIZE
    if rb.count > RING_BUFFER_SIZE:
      rb.count = RING_BUFFER_SIZE

    return rb
  except CatchableError:
    return initRingBuffer()

proc saveToDisk*(rb: RingBuffer, path: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Save the RingBuffer as a JSON file. Create the parent directory if needed.
  let dir = parentDir(path)
  if dir.len > 0 and not dirExists(dir):
    createDir(dir)

  var root = newJObject()
  root["head"] = newJInt(rb.head)
  root["count"] = newJInt(rb.count)

  var entriesArr = newJArray()
  for i in 0 ..< rb.count:
    let entry = rb.entries[i]
    var entryObj = newJObject()
    entryObj["cmdString"] = newJString(entry.cmdString)
    entryObj["effect"] = newJInt(entry.effect)
    entryObj["contextHash"] = newJString(entry.contextHash)
    entryObj["inputHash"] = newJString(entry.inputHash)
    entryObj["success"] = newJBool(entry.success)
    entryObj["timestamp"] = newJString(entry.timestamp)
    entriesArr.add(entryObj)

  root["entries"] = entriesArr
  writeFile(path, $root)

proc getGitHeadHash*(repoRoot: string): string =
  ## Run `git -C <repoRoot> rev-parse HEAD` and return the stripped output.
  ## On failure, return "unknown".
  try:
    let (output, exitCode) = git_operations.runGitEx(gitExe, "-C \"" & repoRoot & "\" rev-parse HEAD")
    if exitCode == 0:
      return strip(output)
    else:
      return "unknown"
  except CatchableError:
    return "unknown"

proc generateContextHash*(repoRoot: string): string {.axiomEffect: IOEffect.} =
  ## Hash of `repoRoot & getGitHeadHash(repoRoot)`.
  let gitHash = getGitHeadHash(repoRoot)
  let combined = repoRoot & gitHash
  var h: Hash = 0
  h = h !& hash(combined)
  result = $cast[int](h)

proc extractInputPaths*(cmd: string, repoRoot: string): seq[string] =
  ## Parse command arguments, skip flags starting with `-` and `key=value` tokens.
  ## Return paths that contain `/`, `\`, `.`, or exist as files/dirs.
  ## Return empty seq if ambiguous → caller falls back to repoRoot.
  result = @[]

  let parts = cmd.split(' ')
  for part in parts:
    # Skip flags
    if part.len > 0 and part[0] == '-':
      continue
    # Skip key=value tokens
    if '=' in part:
      continue
    # Skip empty tokens
    if part.len == 0:
      continue

    let p = part.strip()
    if p.len == 0:
      continue

    # Check if it looks like a path (contains /, \, or .)
    let looksLikePath = (DirSep in p) or (AltSep in p) or ('.' in p)

    if looksLikePath:
      result.add(p)
    else:
      # Check if it exists as a file or directory
      if fileExists(p) or dirExists(p):
        result.add(p)

  # If we have no clear paths, return empty so caller falls back to repoRoot
  # If every token was a flag or value, this stays empty which is the desired behavior.

proc getInputBoundaryHash*(cmd: string, repoRoot: string): string =
  ## Compute a deterministic hash of the command's input boundary.
  ## If no input paths are extracted, fall back to hashing repoRoot.
  let inputPaths = extractInputPaths(cmd, repoRoot)

  var pathsToHash: seq[string]
  if inputPaths.len == 0:
    pathsToHash = @[repoRoot]
  else:
    pathsToHash = inputPaths

  var h: Hash = 0

  for p in pathsToHash:
    let absPath =
      if isAbsolute(p):
        p
      else:
        joinPath(repoRoot, p)

    if dirExists(absPath):
      # Walk the directory, filter by SOURCE_EXTENSIONS and EXCLUDE_DIRS
      try:
        var files: seq[string] = @[]
        for f in walkDirRec(absPath, relative = true):
          # Check that no path component is in EXCLUDE_DIRS
          let dominated = f.split({DirSep, AltSep}).anyIt(it in EXCLUDE_DIRS)
          if dominated:
            continue
          # Check file extension
          let (_, _, ext) = splitFile(f)
          if ext in SOURCE_EXTENSIONS:
            files.add(f)

        files.sort()

        for f in files:
          let fullPath = joinPath(absPath, f)
          try:
            let info = getFileInfo(fullPath)
            h = h !& hash(f)
            h = h !& hash(info.lastWriteTime.toUnix)
            h = h !& hash(info.size)
          except CatchableError:
            # Skip files that can't be stat'd
            h = h !& hash(f)
      except CatchableError:
        # If walkDirRec fails, hash just the directory path
        h = h !& hash(absPath)
    elif fileExists(absPath):
      try:
        let info = getFileInfo(absPath)
        h = h !& hash(absPath)
        h = h !& hash(info.lastWriteTime.toUnix)
        h = h !& hash(info.size)
      except CatchableError:
        h = h !& hash(absPath)
    else:
      # Path doesn't exist, hash it as-is (ambiguous input)
      h = h !& hash(absPath)

  result = $cast[int](h)

func isNetworkRetryCommand*(cmd: string): bool =
  ## Check if the command starts with any of: "git pull", "git fetch", "curl", "wget".
  let trimmed = cmd.strip()
  const prefixes = ["git pull", "git fetch", "curl", "wget"]
  for prefix in prefixes:
    if trimmed.startsWith(prefix):
      return true
  return false

func decideDerivation*(currentInputHash: string, rb: RingBuffer, cmd: string): DerivationDecision =
  ## 4-cell matrix for derivation gating:
  ## - First execution (no matching entry): ddAllow
  ## - Network retry + previous success + retryCount <= 1: ddAllowNetwork
  ## - Previous success + input unchanged: ddBlock
  ## - Otherwise: ddAllow

  # Effect ordinal 3 = derivation
  const derivationEffect = 3

  # Search for the most recent entry with the same command string and derivation effect.
  var previousEntry: CommandContext
  var foundPrevious = false
  var retryCount = 0

  let recent = rb.recentEntries(rb.count)
  for entry in recent:
    if entry.cmdString == cmd and entry.effect == derivationEffect:
      if not foundPrevious:
        previousEntry = entry
        foundPrevious = true
      retryCount += 1

  # First execution: no matching entry found
  if not foundPrevious:
    return ddAllow

  # Network retry command: allow one retry if previous was successful
  if isNetworkRetryCommand(cmd) and previousEntry.success and retryCount <= 1:
    return ddAllowNetwork

  # Previous success + input unchanged: block (no-op, already succeeded)
  if previousEntry.success and previousEntry.inputHash == currentInputHash:
    return ddBlock

  # Otherwise: allow
  return ddAllow

{.pop.}
