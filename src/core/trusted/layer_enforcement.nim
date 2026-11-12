{.push raises: [].}
import core/trusted/layer_declaration
axiomLayer "trusted.core.layer-enforcement"

import core/trusted/layer_rules
import gate/gate_consts
import std/[strutils, macros, os]
import core/utils/path_identity
import core/trusted/axiom_pragmas

# ── Cross-platform project root detection ─────────────────────────────────
# Compile-time root detection using .axiom_root sentinel file.
# Traverses upward from currentSourcePath() looking for .axiom_root.
# Handles Windows drive letters: parent of "C:\" is "C:\" (infinite loop guard).

proc findProjectRoot*(start: string): string {.compileTime.} =
  var current = start
  while true:
    let parent = current.parentDir()
    # Infinite loop guard: when parent == current we've hit root (e.g., "/" or "C:\")
    if parent == current:
      return ""
    let marker = parent / ".axiom_root"
    if fileExists(marker):
      return parent
    current = parent

# QUIRK(DEBT#453): const-context currentSourcePath() returns string; wrapping
# in LogicalPath would break const evaluation / macro expansion. See
# docs/spec/artifact_determinism.md §2.4-2.5. Bind the {.axiomDebt.} marker here
# so the debt_integrity_gate recognizes the open registry entry (AGENTS.md §0.5c).
const debtMarker453 {.axiomDebt: "DEBT#453".} = true

proc resolveProjectRoot*(): string {.compileTime.} =
  # QUIRK(DEBT#453): currentSourcePath() returns string in const context;
  # wrapping in LogicalPath would break const evaluation and cascade into
  # widely-imported public APIs (enforceLayerImports, enforceLayer).
  # Deferred per plan §2 — PhysicalPath remains until runtime refactor.
  const srcPath = currentSourcePath()
  result = findProjectRoot(srcPath)

func toLayerIdentifier*(path: string): string =
  ## Convert a file path to a layer identifier by stripping the project root prefix.
  let root = resolveProjectRoot()
  var normalized = path.replace("\\", "/")
  if root.len > 0:
    let rootNorm = root.replace("\\", "/")
    if normalized.startsWith(rootNorm & "/"):
      normalized = normalized[(rootNorm.len + 1)..^1]
  result = normalized

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func inferLayer*(path: string): string =
  ## Infer layer from file path.
  ## Closed universe (DEBT#287): every .nim file under src/ and tools/ must
  ## classify into exactly one registered layer. Each layer has exactly one
  ## rule in LayerRules; "mcp" is its own layer so its rule is not shadowed
  ## by the presentation rule under layer-keyed lookup.
  let normalized = path.replace("\\", "/")
  if normalized.endsWith("src/api.nim"): result = "presentation"
  elif normalized.endsWith("src/engine.nim"): result = "infrastructure"
  elif "/src/core/" in normalized or normalized.startsWith("src/core/"): result = "domain"
  elif "/src/verification/" in normalized or "/src/engine/" in normalized or
       "/src/frontend/" in normalized or "/src/infrastructure/" in normalized or
       "/src/personas/" in normalized or "/src/generated/" in normalized or
       normalized.startsWith("src/verification/") or normalized.startsWith("src/engine/") or
       normalized.startsWith("src/frontend/") or normalized.startsWith("src/infrastructure/") or
       normalized.startsWith("src/personas/") or normalized.startsWith("src/generated/"): result = "infrastructure"
  elif "/src/cli/" in normalized or "/src/ui/" in normalized or
       "/src/api/" in normalized or "/src/bin/" in normalized or
       normalized.startsWith("src/cli/") or normalized.startsWith("src/ui/") or
       normalized.startsWith("src/api/") or normalized.startsWith("src/bin/"): result = "presentation"
  elif "/src/mcp/" in normalized or normalized.startsWith("src/mcp/"): result = "mcp"
  elif "/src/gate/" in normalized or "/src/policy/" in normalized or
       normalized.startsWith("src/gate/") or normalized.startsWith("src/policy/"): result = "gate"
  elif "/src/sieve/" in normalized or normalized.startsWith("src/sieve/"): result = "infrastructure"
  elif "/src/shared_types/" in normalized or normalized.startsWith("src/shared_types/"): result = "infrastructure"
  elif normalized.startsWith("tools/") or "/tools/" in normalized: result = "tools"
  else: result = "unknown"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func layerRulesAllow(srcLayer, canonical: string): bool =
  ## The existing LayerRules verdict logic (unchanged semantics), extracted
  ## so isAllowedImport can consult it after the approved-exception check.
  for rule in LayerRules:
    if srcLayer == inferLayer(rule.source):
      # Check if target is in allowed list
      for allowed in rule.allowedImports:
        if canonical.startsWith(allowed): return true
      # Check if target is explicitly forbidden
      for forbidden in rule.forbiddenImports:
        if canonical.startsWith(forbidden): return false
      # Default: allow if not explicitly forbidden
      return true
  # No rule found for this layer — deny (fail closed)
  result = false

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func isAllowedImport*(srcFile, targetPath: string;
                      approved: seq[(string, string)] = @[]): bool =
  ## Check if the import `targetPath` into `srcFile` is allowed.
  ##
  ## DI seam (RL-14.4 S3): `approved` carries caller-supplied exceptions as
  ## (normalizedSourceFile, normalizedTarget) pairs — BOTH members already
  ## normalized per the numbered contract in layer_rules.nim
  ## (normalizeSourcePath / normalizeImportPath forms). This func normalizes
  ## its own inputs before membership comparison, so a pair match wins
  ## immediately ("exception wins") without re-normalizing the list.
  ## Core stays dependency-free: the caller (gate/policy layer) injects the
  ## exception data — this module never imports src/gate/**
  ## (docs/agents/architecture.md:88). Default `@[]` preserves the previous
  ## behavior when no exceptions are passed.
  let canonicalTargets = resolveImportTarget(srcFile, targetPath)
  if canonicalTargets.len == 0:
    return false                      # rule 10: uninterpretable → violation
  let srcLayer = inferLayer(srcFile)
  let srcNorm = normalizeSourcePath(srcFile)
  for canonical in canonicalTargets:
    block exceptionCheck:
      for (okSrc, okTarget) in approved:
        if okSrc == srcNorm and okTarget == canonical:
          break exceptionCheck        # exception wins — no rule check
      if srcLayer == "unknown":
        return false
      if not canonical.contains("/"):
        continue              # rule 7: single-segment std/nimble — out of scope
      if not layerRulesAllow(srcLayer, canonical):
        return false
  result = true
{.warning[UnusedImport]: off.}  # Macro-only module — import is always "unused" at surface

# ── Section C: hardened line-parser helpers (compile-time, macro-only) ────
# Minimal lexical hardening of the line scanner — deliberately NOT a full
# AST parser; the SSOT AST extractor is extractImportsV4 (nimtry).

func stripNimComments(line: string; blockDepth: var int): string =
  ## Quote-aware removal of `#[ ... ]#` spans (nesting tracked via the var
  ## depth) and `#`-to-EOL line comments, so an `import` inside a comment is
  ## never a false-positive target.
  result = ""
  var inStr = false
  var i = 0
  while i < line.len:
    if inStr:
      result.add(line[i])
      if line[i] == '"' and (i == 0 or line[i - 1] != '\\'):
        inStr = false
      inc i
    elif blockDepth > 0:
      if i + 1 < line.len and line[i] == ']' and line[i + 1] == '#':
        dec blockDepth
        inc i, 2
      elif i + 1 < line.len and line[i] == '#' and line[i + 1] == '[':
        inc blockDepth
        inc i, 2
      else:
        inc i
    elif line[i] == '"':
      inStr = true
      result.add(line[i])
      inc i
    elif i + 1 < line.len and line[i] == '#' and line[i + 1] == '[':
      inc blockDepth
      inc i, 2
    elif line[i] == '#':
      break
    else:
      result.add(line[i])
      inc i

func splitTopLevelCommas(s: string): seq[string] =
  ## Comma-split at bracket depth 0 so `std/[a, b]` stays one token.
  result = @[]
  var depth = 0
  var cur = ""
  for ch in s:
    if ch == '[':
      inc depth
    elif ch == ']':
      dec depth
    if ch == ',' and depth <= 0:
      result.add(cur)
      cur = ""
    else:
      cur.add(ch)
  result.add(cur)

func importStmtContinues(s: string): bool =
  ## `import a, b,` continues on the next line (trailing comma at bracket
  ## depth 0); an unclosed bracket (`import std/[`) also continues.
  var depth = 0
  for ch in s:
    if ch == '[':
      inc depth
    elif ch == ']':
      dec depth
  if depth > 0:
    return true
  result = s.strip().endsWith(",")

func extractRawTargets(stmt: string): seq[string] =
  ## Raw import tokens from one (possibly continued) `import` statement:
  ## `except`-list cut (contract rule 5), bracket-aware comma split (rule 6
  ## input), alias cut (rule 4). Quotes are kept — normalizeImportPath strips
  ## them (rule 8).
  let body = stmt[7 .. ^1]
  var targetsPart = body
  let excIdx = body.find(" except ")
  if excIdx >= 0:
    targetsPart = body[0 ..< excIdx]
  result = @[]
  for piece in splitTopLevelCommas(targetsPart):
    var tok = piece.strip()
    let asIdx = tok.find(" as ")
    if asIdx >= 0:
      tok = tok[0 ..< asIdx].strip()
    if tok.len > 0:
      result.add(tok)

template checkSingleImport(currentFile: string; lineNum: int; rawToken: string) =
  ## Compile-time verdict for ONE raw import token (section C contract):
  ##  - uninterpretable forms fail closed as UNPARSED_IMPORT (rule 10);
  ##  - bare single-segment names are resolved against the source file's own
  ##    directory first — a real same-directory module is enforced via its
  ##    canonical path, a std/nimble bare name is out of scope (rule 7);
  ##  - the DI call passes currentFile (not a layer name) and @[] — the
  ##    compile-time macro has no exception source; the approved list is
  ##    injected by runtime callers.
  ##  Template, not proc/func: it performs compile-time fileExists I/O
  ##  (side-effect inference would reject a func) and the src/core proc
  ##  ratchet (architecture_invariants) caps `proc` declarations; templates
  ##  are neither.
  let canonicalTok = normalizeImportPath(rawToken)
  if canonicalTok.len == 0 or resolveImportTarget(currentFile, rawToken).len == 0:
    error("UNPARSED_IMPORT: " & currentFile & ":" & $lineNum &
          " cannot interpret import '" & rawToken &
          "' — fail-closed (RL-14.4 normalization contract rule 10).")
  var checkPath = rawToken
  var outOfScope = false
  if not canonicalTok.contains("/"):
    let srcDir = parentDir(currentFile.replace("\\", "/"))
    if srcDir.len > 0 and fileExists(srcDir / canonicalTok & ".nim"):
      checkPath = srcDir & "/" & canonicalTok
    else:
      outOfScope = true      # std/nimble bare name — out of scope (rule 7)
  if not outOfScope:
    if not isAllowedImport(currentFile, checkPath, @[]):
      error("LAYER VIOLATION: " & currentFile & ":" & $lineNum &
            " imports '" & rawToken & "' (" & inferLayer(rawToken) &
            " layer) from " & inferLayer(currentFile) & " layer." &
            "\n  See docs/agents/rules_workflow.md for allowed imports.")

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro enforceLayerImports*(): untyped =
  ## Compile-time macro that reads the current source file via staticRead
  ## and validates all import statements against LayerRules.
  ##
  ## When called from moduleA.nim, instantiationInfo() returns moduleA.nim's
  ## path, so staticRead reads moduleA.nim and validates its imports.
  ##
  ## Skipped for:
  ##   - trusted/ files (they legitimately import across layers)
  ##   - Unknown call-site: instantiationInfo() returns "???" inside macro
  ##     bodies on Nim 2.2.10 (verified empirically — filename is "???" and
  ##     line is 0 in ALL invocations, not only standalone ones), so this
  ##     guard currently skips in every build. The live RL-14.4 enforcement
  ##     layer is therefore the runtime gate (layer_enforcement_gate), which
  ##     walks real files and injects the approved exception list. The guard
  ##     is kept so this macro enforces automatically once call-site info is
  ##     available again (e.g. via an explicit path parameter at the call
  ##     site); changing the location mechanism is out of S3 scope.
  let loc = instantiationInfo()
  let currentFile = loc.filename

  # Guard: skip when file cannot be resolved — instantiationInfo() returns
  # "???" in macro bodies on Nim 2.2.10 (see doc comment above)
  if currentFile == "???" or currentFile.len == 0:
    return newNimNode(nnkStmtList)

  # Skip validation for infrastructure/trusted files (they legitimately import anything)
  if currentFile.contains("/trusted/"):
    return newNimNode(nnkStmtList)

  # Read file content at compile time; hardened line scan:
  #   - comments (line + #[ ... ]# block) never yield targets
  #   - `import a, b,` / open-bracket statements continue across lines
  #   - `except`-lists, `as` aliases and bracket members are not targets
  #   - `/`-less targets are checked only AFTER normalization, and a bare
  #     name that resolves to a same-directory module IS enforced
  let content = staticRead(currentFile)
  var blockDepth = 0
  var pendingStmt = ""
  var pendingLine = 0
  var lineNum = 0
  for line in content.splitLines():
    inc lineNum
    let code = stripNimComments(line, blockDepth).strip()
    if code.len == 0:
      continue
    if pendingStmt.len > 0:
      # multi-line import continuation (trailing comma / open bracket)
      pendingStmt = pendingStmt & " " & code
      if importStmtContinues(pendingStmt):
        continue
      for tok in extractRawTargets(pendingStmt):
        checkSingleImport(currentFile, pendingLine, tok)
      pendingStmt = ""
      continue
    if code.startsWith("import "):
      if importStmtContinues(code):
        pendingStmt = code
        pendingLine = lineNum
        continue
      for tok in extractRawTargets(code):
        checkSingleImport(currentFile, lineNum, tok)
    elif code.startsWith("from "):
      # `from X import Y` — the target is X; the imported symbols are not
      let parts = code.split(" import ")
      if parts.len >= 1:
        let target = parts[0][5 .. ^1].strip()
        if target.len > 0:
          checkSingleImport(currentFile, lineNum, target)
  if pendingStmt.len > 0:
    # EOF with an unterminated statement — malformed form fails closed (rule 10)
    for tok in extractRawTargets(pendingStmt):
      checkSingleImport(currentFile, pendingLine, tok)

  result = newNimNode(nnkStmtList)

  # Emit compile-time error if this layer has no rules in LayerRules
  # Theater prohibition §0.9: a warning that doesn't stop compilation is theater
  let currentLayer = inferLayer(currentFile)
  var layerHasRules = false
  for rule in LayerRules:
    if currentLayer == inferLayer(rule.source):
      layerHasRules = true
      break
  if not layerHasRules:
    error("LAYER NOT REGISTERED: " & currentFile &
      " has layer \"" & currentLayer &
      "\" which has no rules in LayerRules — imports pass unchecked. " &
      "Add rules to LayerRules in layer_rules.nim to enforce import constraints.")

# ── {.axiomLayer.} Pragma ──────────────────────────────────────────────────
# Allows modules to override directory-based layer inference.
# Usage: `{.axiomLayer: "domain".}` at module top level.
# The pragma is parsed by enforceLayer() to determine the layer.

macro axiomLayerPragmaImpl*(body: untyped): untyped =
  ## Internal: reads the `{.axiomLayer.}` pragma from the current module.
  ## Returns the layer string if found, else empty string.
  const srcPath = instantiationInfo(-1, true).filename
  when srcPath != "???" and srcPath.len > 0:
    const content = staticRead(srcPath)
    for line in content.splitLines():
      let stripped = line.strip()
      if stripped.startsWith("{.axiomLayer:") and stripped.endsWith(".}"):
        let start = stripped.find(':') + 1
        let endPos = stripped.find(".}")
        if start > 0 and endPos > start:
          let raw = stripped[start..<endPos].strip()
          if raw.len >= 2:
            if (raw[0] == '"' and raw[^1] == '"') or (raw[0] == '\'' and raw[^1] == '\''):
              let layerVal = raw[1..^2]
              if layerVal.len > 0:
                return newStrLitNode(layerVal)
  result = newStrLitNode("")

# ── enforceLayer() Macro ───────────────────────────────────────────────────
# Compile-time layer enforcement using currentSourcePath().
# Cross-platform: normalizes paths, handles Windows drive letters.
#
# Fail-Closed Policy (per AGENTS.md §0.8 — Theater Prohibition):
#   A warning that doesn't stop compilation is theater: it appears to enforce
#   something but guarantees nothing. All layer enforcement failures MUST be
#   hard errors (error()) unless explicitly bypassed via -d:allowMissingLayer.
#   This ensures NO code compiles with unenforced layer constraints.
#
#   Reference: Theater signature #5 (Dead gate) — a check registered but not
#   enforced is indistinguishable from no check at all.

var axiomLayerPragmaCache* {.compileTime.}: seq[(string, string)] = @[]

macro enforceLayer*(): untyped =
  ## Compile-time layer enforcement macro.
  ##
  ## Uses `instantiationInfo(-1, true).filename` to get the calling module's path.
  ## Normalizes relative to project root (via `-d:projectPath` or `.axiom_root` traversal).
  ##
  ## Supports `{.axiomLayer: "layerName".}` pragma to override inference.
  ##
  ## Emits `error()` at compile time if layer is "unknown".
  let loc = instantiationInfo(-1, true)
  let rawPath = loc.filename

  # Guard: skip when file cannot be resolved
  if rawPath == "???" or rawPath.len == 0:
    return newNimNode(nnkStmtList)

  let normalizedPath = rawPath.replace("\\", "/")

  # Check pragma cache first
  for (cachedPath, cachedLayer) in axiomLayerPragmaCache:
    if cachedPath == normalizedPath and cachedLayer.len > 0:
      return newNimNode(nnkStmtList)

  # Check for {.axiomLayer.} pragma in the source file
  let content = staticRead(rawPath)
  var pragmaLayer = ""
  for line in content.splitLines():
    let stripped = line.strip()
    if stripped.startsWith("{.axiomLayer:") and stripped.endsWith(".}"):
      let start = stripped.find(':') + 1
      let endPos = stripped.find(".}")
      if start > 0 and endPos > start:
        let raw = stripped[start..<endPos].strip()
        if raw.len >= 2:
          if (raw[0] == '"' and raw[^1] == '"') or (raw[0] == '\'' and raw[^1] == '\''):
            pragmaLayer = raw[1..^2]

  # Determine layer: pragma override or inference
  var currentLayer: string
  if pragmaLayer.len > 0:
    currentLayer = pragmaLayer
  else:
    let projectRoot = resolveProjectRoot()
    var relativePath = normalizedPath
    if projectRoot.len > 0:
      let rootNorm = projectRoot.replace("\\", "/")
      if normalizedPath.startsWith(rootNorm & "/"):
        relativePath = normalizedPath[(rootNorm.len + 1)..^1]
    currentLayer = inferLayer(relativePath)

  # Update cache
  axiomLayerPragmaCache.add((normalizedPath, currentLayer))

  # Emit error if layer is unknown (unless in trusted/)
  if currentLayer == "unknown" and "/trusted/" notin normalizedPath:
    error("LAYER UNKNOWN: " & rawPath & " — cannot determine layer. " &
          "Add a path rule to inferLayer() in layer_enforcement.nim, " &
          "or annotate with {.axiomLayer: \"layerName\".} pragma.")

  # Verify layer has rules registered
  var layerHasRules = false
  for rule in LayerRules:
    if currentLayer == inferLayer(rule.source):
      layerHasRules = true
      break
  when not defined(allowMissingLayer):
    if not layerHasRules:
      error("LAYER NOT REGISTERED: " & rawPath &
        " resolves to layer \"" & currentLayer &
        "\" which has no rules in LayerRules. " &
        "Add rules in layer_rules.nim, or bypass with -d:allowMissingLayer.")

  result = newNimNode(nnkStmtList)

# Auto-execute on module load (when imported).
# This is a no-op when imported: this file is in /trusted/ → skipped.
# Real enforcement happens when modules call enforceLayerImports() explicitly.
enforceLayerImports()
