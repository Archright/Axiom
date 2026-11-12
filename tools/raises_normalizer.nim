import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [].}
## tools/raises_normalizer.nim — {.raises: [].} normalizer
## Compiler feedback loop: parse errors → verify locations → insert annotations
## AGENTS.md §0.6: Static First Enforcement
##
## Types mirror tools/build_types.nim (which has a pre-existing {.raises: [].}
## violation in save* procs). Once build_types.nim is fixed, this file should
## switch to `import build_types`.
##
## Usage:
##   nim c -r tools/raises_normalizer.nim --entry=src/cli/axiom.nim [--overlay=build/tmp] [--dry-run]

import std/[algorithm, os, osproc, strutils]
import shared_types/shared_types

# ── Shared types (mirrors tools/build_types.nim) ─────────────────────────────

type
  BuildErrorKind* = enum
    bekNormalization   ## {.raises: [].} 삽입 실패
    bekCompile         ## nim c 컴파일 실패
    bekIO              ## 파일 I/O 실패

  BuildError* = object
    kind*: BuildErrorKind
    message*: string
    file*: string
    line*: int

  BuildResult* = Result[void, BuildError]

  CompileError* = object
    file*: string
    line*: int
    col*: int
    procName*: string
    exceptionType*: string

  ChangeRecord* = object
    file*: string
    line*: int
    procName*: string
    annotation*: string     ## {.raises: []}

  BuildConfig* = object
    srcDir*: string          ## "src"
    entryPoint*: string      ## "src/cli/axiom.nim"
    outputPath*: string      ## "bin/axiom"
    overlayDir*: string      ## "build/tmp"
    nimcacheDir*: string     ## "build/nimcache"
    hashFile*: string        ## "data/.build_hash"
    autoRaises*: bool        ## {.raises: []} 자동 삽입 활성화
    dryRun*: bool            ## Dry Run 모드
    verify*: bool            ## 멱등성 검증 모드
    jsonLog*: bool           ## JSON 구조화 로그

# ── Helpers ──────────────────────────────────────────────────────────────────

func toBuildError*(kind: BuildErrorKind, msg: string,
                   file: string = "", line: int = 0): BuildError =
  BuildError(kind: kind, message: msg, file: file, line: line)

# ── Constants ────────────────────────────────────────────────────────────────

const
  RaisesAnnotation = "{.raises: [].}"
  MaxIterations = 5

# ── Manual error-line parser (no regex — avoids RegexError raise) ────────────

func parseErrorLine(line: string): CompileError =
  ## Parse a single Nim compiler error line.
  ## Formats (Nim 2.x):
  ##   "file(line, col) Error: expr can raise an unlisted exception: ref ExcType"
  ##   "file(line, col) Error: 'procName' can raise an unlisted exception: ref ExcType"
  ## Returns a CompileError with default (empty/zero) fields on parse failure.
  result = CompileError(file: "", line: 0, col: 0, procName: "", exceptionType: "")

  # Find the opening paren that separates file from (line, col)
  let parenOpen = line.find('(')
  if parenOpen < 0: return

  result.file = line[0 ..< parenOpen]

  # Find comma between line and col
  let comma = line.find(',', start = parenOpen)
  if comma < 0: return

  # Find closing paren
  let parenClose = line.find(')', start = comma)
  if parenClose < 0: return

  # Parse line and col numbers
  let lineStr = line[(parenOpen + 1) ..< comma].strip()
  let colStr = line[(comma + 1) ..< parenClose].strip()
  try:
    result.line = parseInt(lineStr)
    result.col = parseInt(colStr)
  except ValueError:
    return

  # Find "Error: " marker
  let errorIdx = line.find("Error: ")
  if errorIdx < 0: return
  let exprStart = errorIdx + 7  # len("Error: ")

  # Find "can raise an unlisted exception: " marker
  # Nim 2.x uses "can raise an unlisted exception" (with "an")
  let excLabel = "can raise an unlisted exception: "
  let excIdx = line.find(excLabel, start = exprStart)
  if excIdx < 0: return

  # Extract the expression (proc name or raise expression)
  result.procName = line[exprStart ..< excIdx].strip()
  # Strip surrounding single quotes if present (legacy format)
  if result.procName.len >= 2 and
     result.procName[0] == '\'' and result.procName[^1] == '\'':
    result.procName = result.procName[1 .. ^2]

  # Extract exception type
  result.exceptionType = line[(excIdx + excLabel.len) .. ^1].strip()

# ── Pure computation ─────────────────────────────────────────────────────────

func parseErrors*(compilerOutput: string): seq[CompileError] =
  ## Parse Nim compiler error output.
  ## Pattern: "file(line, col) Error: expr can raise an unlisted exception: ref ExcType"
  ## Handles multiple errors in one output.
  result = @[]
  for line in compilerOutput.splitLines():
    let parsed = parseErrorLine(line)
    if parsed.line > 0 and parsed.procName.len > 0:
      result.add(parsed)

func findEnclosingProc*(error: CompileError,
                        sourceLines: seq[string]): int =
  ## Search backward from error.line to find the nearest proc/func/method declaration.
  ## Returns the 1-based line number of the declaration, or 0 if not found.
  ## The compiler error points at the call site (e.g. readFile(...));
  ## the annotation must go on the enclosing proc/func line.
  if error.line < 1 or error.line > sourceLines.len:
    return 0
  for i in countdown(error.line - 1, 0):
    let ln = sourceLines[i]
    if ("proc " in ln) or ("func " in ln) or ("method " in ln):
      return i + 1  # back to 1-based
  0

func verifyErrorLocation*(error: CompileError,
                           sourceLines: seq[string]): bool =
  ## Verify that a proc/func/method declaration exists on or above the error line.
  ## Searches backward from error.line to find the enclosing declaration.
  ## Return true if found, false if suspicious (no enclosing proc).
  findEnclosingProc(error, sourceLines) > 0

# ── I/O boundary: normalization plan ─────────────────────────────────────────

proc resolveFilePath(errorFile, overlayDir: string): string {.raises: [IOError, OSError].} =
  ## Resolve the file path from a compiler error.
  ## Compiler errors may use absolute paths or overlay-relative paths.
  if errorFile.isAbsolute:
    return errorFile
  # Try as-is (relative to project root), then with overlay prefix
  if fileExists(errorFile):
    return errorFile
  overlayDir / errorFile

proc computeNormalization*(errors: seq[CompileError],
                           overlayDir: string): seq[ChangeRecord] {.raises: [IOError, OSError].} =
  ## Compute normalization plan.
  ## For each verified error, read source from overlayDir and create a ChangeRecord.
  ## Pure logic; file reads are deterministic given same overlay state.
  result = @[]
  for error in errors:
    let filePath = resolveFilePath(error.file, overlayDir)
    if not fileExists(filePath):
      continue
    let sourceLines = readFile(filePath).splitLines()
    let procLine = findEnclosingProc(error, sourceLines)
    if procLine > 0:
      result.add(ChangeRecord(
        file: error.file,
        line: procLine,
        procName: error.procName,
        annotation: RaisesAnnotation
      ))

# ── I/O boundary: apply changes ──────────────────────────────────────────────

proc applyNormalization*(changes: seq[ChangeRecord],
                         overlayDir: string): Result[int, BuildError] {.raises: [].} =
  ## Apply changes to files in overlayDir.
  ## Processes changes in descending line order to prevent line-number drift.
  ## Checks for existing {.raises:} pragma to avoid duplicates.
  ## Returns the number of files modified, or an error.
  try:
    var sorted = changes
    sorted.sort(proc (a, b: ChangeRecord): int = cmp(b.line, a.line))

    var filesModified: seq[string] = @[]
    for change in sorted:
      let filePath = resolveFilePath(change.file, overlayDir)
      if not fileExists(filePath):
        return err(toBuildError(bekNormalization,
          "File not found: " & filePath, change.file, change.line))

      var lines = readFile(filePath).splitLines()
      if change.line < 1 or change.line > lines.len:
        return err(toBuildError(bekNormalization,
          "Line out of range: " & $change.line, change.file, change.line))

      let targetLine = lines[change.line - 1]
      # Skip if {.raises:} pragma already present on the proc/func line
      if "{.raises:" in targetLine:
        continue

      # Insert pragma on the line above the proc/func declaration
      lines.insert(RaisesAnnotation, change.line - 1)

      if change.file notin filesModified:
        filesModified.add(change.file)

      writeFile(filePath, lines.join("\n"))

    ok(filesModified.len)
  except IOError as e:
    err(toBuildError(bekNormalization, "I/O error: " & e.msg))
  except OSError as e:
    err(toBuildError(bekNormalization, "OS error: " & e.msg))

# ── I/O boundary: compiler invocation ────────────────────────────────────────

proc runNimCheck*(entryPoint: string, nimFlags: seq[string],
                  workDir: string): string {.raises: [].} =
  ## Run `nim c --hints:off <entryPoint>` and capture compiler output.
  ## Compiles from the project root so config.nims resolves correctly.
  ## workDir is the overlay directory — added via --path so overlay sources
  ## are found first by the compiler.
  ## Uses std/osproc.execProcess. Returns combined compiler output.
  try:
    var args = @["c", "--hints:off"]
    for flag in nimFlags:
      args.add(flag)
    # Add overlay dir as a path so the compiler finds overlay sources
    args.add("--path:" & workDir)
    # Entry point is relative to the overlay dir
    args.add(workDir / entryPoint)
    execProcess("nim", args = args, workingDir = "",
                options = {poStdErrToStdOut, poUsePath})
  except CatchableError as e:
    "[normalizer] Failed to run nim: " & e.msg

# ── Convergence loop ─────────────────────────────────────────────────────────

proc normalizeLoop*(config: BuildConfig): BuildResult {.raises: [].} =
  ## Main convergence loop:
  ## 1. Run nim c on overlay
  ## 2. Parse errors
  ## 3. Verify error locations
  ## 4. Compute normalization plan
  ## 5. If dryRun: log changes and return ok()
  ## 6. Apply normalization
  ## 7. Repeat (max 5 iterations)
  ## 8. If converged (no more errors), return ok()
  ## 9. If not converged after 5 iterations, return error
  for i in 1..MaxIterations:
    let nimFlags = @["--nimcache:" & config.nimcacheDir]
    let compilerOutput = runNimCheck(config.entryPoint, nimFlags,
                                    config.overlayDir)

    let errors = parseErrors(compilerOutput)

    if errors.len == 0:
      return ok()

    try:
      let changes = computeNormalization(errors, config.overlayDir)
      if changes.len == 0:
        return err(toBuildError(bekNormalization,
          "Compiler errors found but no valid normalization targets"))

      if config.dryRun:
        for change in changes:
          echo "[dry-run] ", change.file, ":", $change.line,
               " — insert ", change.annotation,
               " (", change.procName, ")"
        return ok()

      let applyResult = applyNormalization(changes, config.overlayDir)
      if applyResult.isErr():
        return err(applyResult.error)
    except IOError as e:
      return err(toBuildError(bekNormalization, "I/O error: " & e.msg))
    except OSError as e:
      return err(toBuildError(bekNormalization, "OS error: " & e.msg))

  err(toBuildError(bekNormalization,
    "Failed to converge after " & $MaxIterations & " iterations"))

# ── CLI Entry Point ──────────────────────────────────────────────────────────

when isMainModule:
  var entryPoint = ""
  var overlayDir = "build/tmp"
  var dryRun = false

  for i in 1..paramCount():
    let arg = paramStr(i)
    if arg.startsWith("--entry="):
      entryPoint = arg[8..^1]
    elif arg.startsWith("--overlay="):
      overlayDir = arg[10..^1]
    elif arg == "--dry-run":
      dryRun = true

  if entryPoint.len == 0:
    echo "Usage: raises_normalizer --entry=<entry.nim> [--overlay=<dir>] [--dry-run]"
    quit(1)

  let config = BuildConfig(
    srcDir: "src",
    entryPoint: entryPoint,
    outputPath: "",
    overlayDir: overlayDir,
    nimcacheDir: overlayDir / "nimcache",
    hashFile: "",
    autoRaises: true,
    dryRun: dryRun,
    verify: false,
    jsonLog: false
  )

  let res = normalizeLoop(config)
  if res.isErr():
    let e = res.error
    stderr.writeLine("[normalizer] FAILED: ", e.message)
    if e.file.len > 0:
      stderr.writeLine("  at ", e.file, ":", $e.line)
    quit(1)
  else:
    echo "[normalizer] Convergence achieved."
