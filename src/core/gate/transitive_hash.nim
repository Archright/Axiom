import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [CatchableError].}

## Transitive Dependency Hasher for Gate Runners (Core Module)
##
## Parses Nim `import`/`from` statements recursively and computes a
## Merkle tree hash of the full transitive dependency chain.
##
## Extracted from tools/import_resolver.nim for use in core/gate/.
## This avoids the layer boundary violation (core importing from tools/)
## while providing the same functionality for CAS key computation.
##
## Purpose: When a shared utility (e.g. core/utils/io_utils.nim) changes,
## ALL gate runners that transitively depend on it should have their CAS
## cache invalidated. Currently gate_cas.nim only hashes the single gate
## runner source file.
##
## This module provides:
##   - Direct import resolution for a single file
##   - Transitive import resolution (DFS with cycle detection)
##   - Deterministic SHA-256 hash of the full dependency tree

import std/[os, strutils, tables, algorithm]
import checksums/sha2
import core/trusted/axiom_pragmas_lite

# ---------------------------------------------------------------------------
# Standard library detection
# ---------------------------------------------------------------------------

const StdlibPrefixes* = ["std/", "system", "nimsuggest/"]

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func isStdlib*(module: string): bool {.raises: [], noSideEffect.} =
  ## Returns true if the module is a standard library or built-in module.
  for prefix in StdlibPrefixes:
    if module.startsWith(prefix):
      return true
  # Single-word tokens without dots or slashes are stdlib (e.g. "os", "strutils")
  if '/' notin module and '.' notin module:
    return true
  false

# ---------------------------------------------------------------------------
# Import parsing
# ---------------------------------------------------------------------------

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func stripComment(line: string): string {.raises: [], noSideEffect.} =
  ## Return empty string for comment/blank lines.
  let trimmed = line.strip()
  if trimmed.len == 0 or trimmed.startsWith("#") or trimmed.startsWith("##"):
    return ""
  trimmed

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func parseRawImports*(source: string): seq[string] =
  ## Parse all import targets from a Nim source string.
  ## Handles: import X, from X import Y, multi-line imports, comma-separated.
  ## Returns raw module tokens (e.g. "core/results", "std/os", "checksums/sha2").
  result = @[]
  var inMultilineImport = false

  for rawLine in source.splitLines():
    let line = stripComment(rawLine)
    if line.len == 0:
      inMultilineImport = false
      continue

    let trimmed = line.strip()

    # `from X import symbol`
    if trimmed.startsWith("from "):
      let rest = trimmed[5 .. ^1]
      let importIdx = rest.find(" import")
      if importIdx > 0:
        let moduleName = rest[0 .. importIdx-1].strip()
        if moduleName.len > 0:
          result.add(moduleName)
      inMultilineImport = false
      continue

    # `import X, Y, Z` (possibly multi-line)
    if trimmed.startsWith("import "):
      let rest = trimmed[7 .. ^1]
      if rest.strip().endsWith(","):
        let items = rest[0 .. ^2].strip()
        for item in items.split(','):
          let s = item.strip()
          if s.len > 0:
            result.add(s)
        inMultilineImport = true
      else:
        for item in rest.split(','):
          let s = item.strip()
          if s.len > 0:
            result.add(s)
        inMultilineImport = false
      continue

    # Continuation of multi-line import
    if inMultilineImport:
      if trimmed.endsWith(","):
        let items = trimmed[0 .. ^2].strip()
        for item in items.split(','):
          let s = item.strip()
          if s.len > 0:
            result.add(s)
      else:
        for item in trimmed.split(','):
          let s = item.strip()
          if s.len > 0:
            result.add(s)
        inMultilineImport = false

# ---------------------------------------------------------------------------
# Path normalization
# ---------------------------------------------------------------------------

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func canonPath*(p: string): string {.raises: [], noSideEffect.} =
  ## Normalize path separators and collapse double slashes.
  result = p.replace('\\', '/')
  while "//" in result:
    result = result.replace("//", "/")
  if result.endsWith("/"):
    result = result[0 .. ^2]

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func dirName*(filePath: string): string {.raises: [], noSideEffect.} =
  ## Directory portion of a file path.
  let sep = filePath.rfind('/')
  if sep >= 0: filePath[0 ..< sep]
  else: "."

# ---------------------------------------------------------------------------
# Import path -> file path resolution
# ---------------------------------------------------------------------------

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc resolveImportPath*(imported: string, sourceFile: string, srcRoot: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Map a raw import token to a concrete .nim file path.
  ## Tries: source-dir-relative, srcRoot-relative, srcRoot/as-module.nim.
  ## Returns "" if not resolvable or is stdlib.
  let clean = imported.strip()
  if clean.len == 0:
    return ""

  if isStdlib(clean):
    return ""

  var resolved = clean
  if not resolved.endsWith(".nim"):
    resolved = resolved & ".nim"

  # Candidate 1: relative to the importing file's directory
  let fromDir = dirName(sourceFile)
  let candidate1 = canonPath(fromDir / resolved)
  if fileExists(candidate1):
    return candidate1

  # Candidate 2: relative to srcRoot
  let candidate2 = canonPath(srcRoot / resolved)
  if fileExists(candidate2):
    return candidate2

  # Candidate 3: the raw import path itself (if it's already a valid path)
  if fileExists(canonPath(resolved)):
    return canonPath(resolved)

  # Candidate 4: Try srcRoot/<imported>/ (package-style)
  let candidate4 = canonPath(srcRoot / clean / "module.nim")
  if fileExists(candidate4):
    return candidate4

  ""

# ---------------------------------------------------------------------------
# Direct import resolution
# ---------------------------------------------------------------------------

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc resolveImports*(sourcePath: string, srcRoot: string): seq[string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Parse and resolve all direct imports of a single file.
  ## Returns list of resolved .nim file paths (stdlib and unresolvable filtered out).
  ## Deduplicates while preserving order.
  result = @[]
  if sourcePath.len == 0 or not fileExists(sourcePath):
    return

  var content: string
  try:
    content = readFile(sourcePath)
  except IOError:
    return

  let rawImports = parseRawImports(content)
  var seen = initTable[string, bool]()

  for raw in rawImports:
    let resolved = resolveImportPath(raw, sourcePath, srcRoot)
    if resolved.len > 0 and resolved notin seen:
      seen[resolved] = true
      result.add(resolved)

# ---------------------------------------------------------------------------
# Transitive import resolution
# ---------------------------------------------------------------------------

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc resolveTransitiveImports*(sourcePath: string, srcRoot: string): seq[string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Recursively resolve ALL transitive imports (DFS with cycle detection).
  ## Returns deduped, sorted list of file paths (does NOT include sourcePath itself).
  result = @[]
  if sourcePath.len == 0 or not fileExists(sourcePath):
    return

  var visited = initTable[string, bool]()
  visited[sourcePath] = true  # Don't recurse into self

  # DFS stack
  var stack: seq[string] = @[]
  let directImports = resolveImports(sourcePath, srcRoot)
  for imp in directImports:
    if imp notin visited:
      stack.add(imp)

  while stack.len > 0:
    let current = stack[^1]
    stack.setLen(stack.len - 1)

    if current in visited:
      continue
    visited[current] = true
    result.add(current)

    # Recurse into this file's imports
    if fileExists(current):
      let nextImports = resolveImports(current, srcRoot)
      for imp in nextImports:
        if imp notin visited:
          stack.add(imp)

  # Deterministic output: sorted
  result.sort(cmp)

# ---------------------------------------------------------------------------
# Transitive hash computation
# ---------------------------------------------------------------------------

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc computeFileHash*(filePath: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## SHA-256 of a single file's content. Returns "" on error.
  if filePath.len == 0 or not fileExists(filePath):
    return ""
  try:
    $secureHash(Sha_256, readFile(filePath))
  except CatchableError:
    ""

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func pairwiseHash*(a, b: string): string {.raises: [], noSideEffect.} =
  ## Hash two sibling nodes in the Merkle tree.
  $secureHash(Sha_256, "\x02" & a & b)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func reduceHashes*(hashes: seq[string]): string {.raises: [], noSideEffect.} =
  ## Reduce a list of hashes to a single Merkle root via pairwise hashing.
  ## Uses "\x02" domain separator (distinct from file_hash_cache's "\x01").
  if hashes.len == 0:
    return ""
  if hashes.len == 1:
    return hashes[0]

  var layer = hashes
  while layer.len > 1:
    var next: seq[string] = @[]
    var i = 0
    while i < layer.len:
      if i + 1 < layer.len:
        next.add(pairwiseHash(layer[i], layer[i + 1]))
      else:
        next.add(layer[i])
      i += 2
    layer = next
  layer[0]

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc computeTransitiveHash*(sourcePath: string, srcRoot: string): string {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Compute a deterministic Merkle root hash of sourcePath + all transitive deps.
  ## The hash changes when ANY file in the transitive dependency tree changes.
  ## Deterministic regardless of traversal order (sorted before hashing).
  if sourcePath.len == 0 or not fileExists(sourcePath):
    return ""

  # Collect all transitive dependencies (sorted)
  let deps = resolveTransitiveImports(sourcePath, srcRoot)

  # Build the full file list: source + all deps (sorted for determinism)
  var allFiles: seq[string] = @[]
  allFiles.add(sourcePath)
  for dep in deps:
    allFiles.add(dep)
  allFiles.sort(cmp)

  # Hash each file
  var fileHashes: seq[string] = @[]
  for f in allFiles:
    let h = computeFileHash(f)
    if h.len > 0:
      fileHashes.add(h)

  if fileHashes.len == 0:
    return ""

  # Merkle root of all file hashes
  reduceHashes(fileHashes)

{.pop.}

