import core/trusted/layer_declaration
axiomLayer "domain"
import core/trusted/axiom_pragmas
import std/[os, strutils]
import core/interfaces/logging_hub
# ---------------------------------------------------------------------------
# FileIoExecutor Concept — Compile-time interface contract
# ---------------------------------------------------------------------------

type
  FileIoExecutor* = concept e
    ## Compile-time interface for file I/O operations.
    ## SystemFileIoExecutor satisfies this for real I/O.
    ## MockFileIoExecutor satisfies this for testing.
    e.fileExists(string) is bool
    e.dirExists(string) is bool
    e.readFile(string) is string
    e.writeFile(string, string) is bool
    e.appendLine(string, string) is bool
    e.createDir(string) is bool
    e.readLines(string) is seq[string]
    e.walkDirEntries(string) is seq[string]
    e.writeStderr(string)
# ---------------------------------------------------------------------------
# SystemFileIoExecutor — Real I/O (boundary)
# ---------------------------------------------------------------------------

type
  SystemFileIoExecutor* = object
    ## Real file I/O executor. Satisfies FileIoExecutor.
    ## All I/O is performed here; core logic never touches stdlib I/O directly.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func newSystemFileIoExecutor*(): SystemFileIoExecutor {.raises: [].} =
  ## Construct a SystemFileIoExecutor (no configuration needed).
  SystemFileIoExecutor()
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc fileExists*(e: SystemFileIoExecutor, path: string): bool {.axiomEffect: IOEffect, tags: [IOEffect].} =
  os.fileExists(path)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc dirExists*(e: SystemFileIoExecutor, path: string): bool {.axiomEffect: IOEffect, tags: [IOEffect].} =
  os.dirExists(path)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc readFile*(e: SystemFileIoExecutor, path: string): string {.axiomEffect: IOEffect, tags: [IOEffect].} =
  system.readFile(path)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc writeFile*(e: SystemFileIoExecutor, path, content: string): bool {.axiomEffect: IOEffect, tags: [IOEffect].} =
  try:
    system.writeFile(path, content)
    true
  except CatchableError:
    false
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc appendLine*(e: SystemFileIoExecutor, path, line: string): bool {.axiomEffect: IOEffect, tags: [IOEffect].} =
  try:
    var f = open(path, fmAppend)
    f.writeLine(line)
    f.close()
    true
  except CatchableError:
    false
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc createDir*(e: SystemFileIoExecutor, path: string): bool {.axiomEffect: IOEffect, tags: [IOEffect].} =
  try:
    os.createDir(path)
    true
  except CatchableError:
    false
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc readLines*(e: SystemFileIoExecutor, path: string): seq[string] {.axiomEffect: IOEffect, tags: [IOEffect].} =
  try:
    system.readFile(path).splitLines()
  except CatchableError:
    @[]
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc walkDirEntries*(e: SystemFileIoExecutor, path: string): seq[string] {.axiomEffect: IOEffect, tags: [IOEffect].} =
  var entries: seq[string]
  try:
    for entry in walkDirRec(path):
      entries.add(entry)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
  entries
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc writeStderr*(e: SystemFileIoExecutor, msg: string) {.axiomEffect: IOEffect, tags: [IOEffect, RootEffect].} =
  logInfo(msg)

# ---------------------------------------------------------------------------
# MockFileIoExecutor — Test double
# ---------------------------------------------------------------------------

type
  MockFileIoExecutor* = object
    ## Mock file I/O executor for testing. Satisfies FileIoExecutor.
    existingFiles*: seq[string]
    existingDirs*: seq[string]
    readFileResult*: string
    readLinesResult*: seq[string]
    walkDirEntriesResult*: seq[string]

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func newMockFileIoExecutor*(): MockFileIoExecutor {.raises: [].} =
  ## Construct an empty MockFileIoExecutor.
  MockFileIoExecutor(
    readLinesResult: @[],
    walkDirEntriesResult: @[]
  )
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func fileExists*(e: var MockFileIoExecutor, path: string): bool {.raises: [].} =
  path in e.existingFiles
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func dirExists*(e: var MockFileIoExecutor, path: string): bool {.raises: [].} =
  path in e.existingDirs
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func readFile*(e: var MockFileIoExecutor, path: string): string {.raises: [].} =
  e.readFileResult
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func readLines*(e: var MockFileIoExecutor, path: string): seq[string] {.raises: [].} =
  e.readLinesResult
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func walkDirEntries*(e: var MockFileIoExecutor, path: string): seq[string] {.raises: [].} =
  e.walkDirEntriesResult
