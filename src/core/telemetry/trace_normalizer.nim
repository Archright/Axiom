import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import std/[strutils, os]
# ---------------------------------------------------------------------------
# Compile-time type safety: raw vs. normalized traces
# ---------------------------------------------------------------------------

type
  RawTrace* = distinct string
  NormalizedTrace* = distinct string
# ---------------------------------------------------------------------------
# Pure normalization helpers (func, noSideEffect)
# ---------------------------------------------------------------------------

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func normalizeLineEndings(s: string): string {.raises: [].} =
  ## Normalize CRLF / CR / LF to unified LF.
  ## Context7: strutils.replace is the canonical Nim primitive.
  result = s.replace("\r\n", "\n").replace("\r", "\n")
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func normalizeAbsolutePaths(s, projectRoot: string): string {.raises: [].} =
  ## Replace absolute project paths with {{PROJECT_ROOT}}/relative.
  ## Also normalizes common temp directories.
  result = s
  if projectRoot.len > 0:
    result = result.replace(projectRoot, "{{PROJECT_ROOT}}")
  result = result.replace("/tmp/", "{{TMPDIR}}/")
  result = result.replace("/var/tmp/", "{{TMPDIR}}/")
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func normalizeTimestamps(s: string): string {.raises: [].} =
  ## Replace obvious ISO-8601 timestamps with {{TIMESTAMP}}.
  ## Heuristic: YYYY-MM-DDTHH:MM:SS or YYYY-MM-DD HH:MM:SS.
  result = s
  var i = 0
  while i + 18 < result.len:
    if result[i] in {'0'..'9'} and result[i+1] in {'0'..'9'} and
       result[i+2] in {'0'..'9'} and result[i+3] in {'0'..'9'} and
       result[i+4] == '-' and result[i+7] == '-' and
       result[i+10] in {'T', ' '} and
       result[i+13] == ':' and result[i+16] == ':':
      var j = i + 19
      while j < result.len and result[j] in {'0'..'9', '.', '+', '-', 'Z'}:
        j.inc
      result = result[0..<i] & "{{TIMESTAMP}}" & result[j..^1]
    else:
      i.inc
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func normalizePIDs(s: string): string {.raises: [].} =
  ## Replace process IDs in common contexts with {{PID}}.
  result = s
  const pidPatterns = ["pid: ", "PID=", "pid=", "process "]
  for pat in pidPatterns:
    var i = 0
    while true:
      i = result.find(pat, i)
      if i < 0: break
      let start = i + pat.len
      var j = start
      while j < result.len and result[j] in {'0'..'9'}:
        j.inc
      if j > start:
        result = result[0..<start] & "{{PID}}" & result[j..^1]
      i = start

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func normalizeTrace*(raw: RawTrace, projectRoot: string): NormalizedTrace {.raises: [].} =
  ## Full normalization pipeline for I/O traces.
  ## Deterministic: identical (raw, projectRoot) → identical output.
  let s1 = normalizeLineEndings(string(raw))
  let s2 = normalizeAbsolutePaths(s1, projectRoot)
  let s3 = normalizeTimestamps(s2)
  let s4 = normalizePIDs(s3)
  result = NormalizedTrace(s4)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func `$`*(nt: NormalizedTrace): string {.raises: [].} = string(nt)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc `$`*(nt: NormalizedTrace): string {.raises: [].} = string(nt)

# ---------------------------------------------------------------------------
# I/O boundary: project-root auto-detection (proc, side-effect permitted)
# ---------------------------------------------------------------------------
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc detectProjectRoot*(): string {.raises: [OSError].} =
  ## Returns the repository root path (where axiom.nimble lives).
  ## Falls back to empty string if not found.
  when not defined(js):
    try:
      var dir = getCurrentDir()
      for _ in 0..<10:  # search upward max 10 levels
        if fileExists(dir / "axiom.nimble"):
          return dir
        let parent = parentDir(dir)
        if parent == dir or parent.len == 0:
          break
        dir = parent
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

{.pop.}
