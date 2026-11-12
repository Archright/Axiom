import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
import std/sequtils
import std/strutils
import std/os
import checksums/sha2
import core/axiom_pragmas

## Normalize Path.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func normalizePath*(raw: string): string {.noSideEffect.} =
  raw.strip().replace('\\', '/')

## Normalize Path Separators.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func normalizePathSeparators*(path: string): string {.noSideEffect, raises: [].} =
  ## Replace backslashes (`\\`) with forward slashes (`/`) in `path`.
  ## Returns the normalized path string. Unlike `normalizePath`, this does not strip whitespace.
  result = path.replace('\\', '/')
## Read File Safe.
# @axiom-hint: lean="path.length ≥ 0 ∧ default.length ≥ 0 ∧ external_io_isolated" smt="(assert (and (>= (str.len path) 0) (>= (str.len default) 0) external_io_isolated))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc readFileSafe*(path: string; default: string = ""): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    readFile(path)
  except CatchableError:
    default

## Write File Safe.
# @axiom-hint: lean="path.length ≥ 0 ∧ data.length ≥ 0 ∧ external_io_isolated" smt="(assert (and (>= (str.len path) 0) (>= (str.len data) 0) external_io_isolated))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc writeFileSafe*(path: string; data: string): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    writeFile(path, data)
    true
  except CatchableError:
    false

## Remove File Optional.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc reremoveFileOpt*(path: string): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Remove file if it exists; return true on success or if file did not exist.
  try:
    if fileExists(path):
      removeFile(path)
    true
  except CatchableError:
    false

## Compute File Hash.
# @axiom-hint: lean="path.length ≥ 0" smt="(assert (>= (str.len path) 0))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc computeFileHash*(path: string): string =
  ## Compute SHA256 hash of file contents for incremental analysis caching.
  ## Returns empty string on I/O failure.
  let content = readFileSafe(path)
  if content.len == 0 and not fileExists(path):
    return ""
  try:
    result = $secureHash(Sha_256, content)
  except CatchableError:
    result = ""

## I Test Evidence.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func isTestEvidence*(filePath: string): bool {.noSideEffect.} =
  filePath.contains("tests/gateway/") or filePath.contains("tests/unit/") or filePath.contains("tests/generated/")

## I History File.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func isHistoryFile*(filePath: string): bool {.noSideEffect.} =
  filePath.startsWith("docs/history/")

## I Implementation File.
# @axiom-hint: lean="filePath.length ≥ 0" smt="(assert (and (>= (str.len filePath) 0)))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func isImplementationFile*(filePath: string): bool {.noSideEffect.} =
  ## Deterministic White-listing: Core source must reside within designated source roots.
  ## Excludes infrastructure tools, documentation, or temporary artifacts by design.
  ## OCP-compliant: new directories outside src/ are automatically excluded.
  let lower = filePath.toLowerAscii()
  # Phase 1: Strict Scope Validation (White-list)
  let isCoreSource = lower.startsWith("src/") or
                      lower == "axiom.nimble" or
                      lower == "config.nims"
  if not isCoreSource:
    return false
  # Phase 2: Extension-based inclusion
  lower.endsWith(".nim") or lower.endsWith(".lean") or lower.endsWith(".smt2")

## I BDD Evidence.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func isBddEvidence*(filePath: string): bool {.noSideEffect.} =
  filePath.contains("tests/features/steps/")

## I Feature Evidence.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func isFeatureEvidenceFile*(filePath: string): bool {.noSideEffect.} =
  filePath.contains("tests/features/") and filePath.toLowerAscii().endsWith(".feature")

## I Comment or Style Line.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func isCommentOrStyleLine*(line: string): bool {.noSideEffect.} =
  let trimmed = line.strip()
  trimmed.len == 0 or trimmed.startsWith("#") or trimmed.startsWith("//")

## I Diff Only Comments.
## Returns true if a diff block contains only comment or style changes.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func isDiffOnlyComments*(diffLines: seq[string]): bool {.noSideEffect.} =
  for line in diffLines:
    if line.len == 0:
      continue
    let marker = line[0]
    if marker != '+' and marker != '-':
      continue
    let body = line[1..^1].strip()
    if body.len == 0:
      continue
    if not isCommentOrStyleLine(body):
      return false
  true

## Extract New External Imports.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func extractNewExternalImports*(patch: string): seq[string] {.noSideEffect.} =
  var imports: seq[string] = @[]
  for line in patch.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith("import ") or trimmed.startsWith("from "):
      let importLine = trimmed
      if not importLine.contains("std/") and not importLine.contains("./") and not importLine.contains("../"):
        imports.add(importLine)
  imports

## New Imports Not In Allowlist.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func newImportsNotInAllowlist*(patch: string; allowed: seq[string]): seq[string] {.noSideEffect.} =
  let newImports = extractNewExternalImports(patch)
  result = newImports.filterIt(it notin allowed)

## Patch Has Only Style Or Comment Changes.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func patchHasOnlyStyleOrCommentChanges*(patch: string): bool {.noSideEffect.} =
  for line in patch.splitLines():
    if line.len == 0:
      continue
    if line.startsWith("+++") or line.startsWith("---") or line.startsWith("@@") or line.startsWith("diff ") or line.startsWith("index "):
      continue
    let marker = line[0]
    if marker != '+' and marker != '-':
      continue
    let body = line[1..^1].strip()
    if body.len == 0:
      continue
    if not isCommentOrStyleLine(body):
      return false
  true

{.pop.}

