## Unified Import Parser — single source of truth for Nim import path extraction.
##
## Merges the logic of:
##   - `tokenizeImports()` from axiom_pragmas.nim (compile-time, HashSet-based)
##   - `extractImports()` from architecture_config_gate.nim (runtime, seq-based)
##
## Design: pure `func` only, zero I/O, works at compile time via `staticRead`.
## All functions are deterministic: identical input → identical output.

import core/trusted/layer_declaration
axiomLayer "domain"
{.push noSideEffect.}
{.push raises: [].}

import std/strutils

# ─── Core Parser ──────────────────────────────────────────────────────────────

func parseImports*(content: string): seq[string] =
  ## Extract all import paths from Nim source text.
  ## Handles: import X, from X import Y, import X/Y/Z,
  ##          import X, Y, Z (comma-separated),
  ##          import X except Y,
  ##          bracket imports import pkg/[a, b, c]
  ##          bare import blocks (indented continuation lines)
  ##          Windows path separators (backslash → slash)
  ## Returns raw import paths (e.g., "core/topology/lock").
  result = @[]

  let lines = content.splitLines()
  var inBracket = false
  var bracketPrefix = ""
  var bracketAccum = ""
  var inImportBlock = false   # bare `import` followed by indented lines

  for line in lines:
    let stripped = line.strip()

    # Skip empty lines and comment lines
    if stripped.len == 0 or stripped.startsWith("#"):
      inImportBlock = false
      continue

    # Normalize Windows path separators
    var normalized = ""
    for ch in line:
      if ch == '\\':
        normalized.add('/')
      else:
        normalized.add(ch)

    let normStripped = normalized.strip()

    # ── Bracket accumulation state ──────────────────────────────────────────
    if inBracket:
      bracketAccum.add(" ")
      bracketAccum.add(normalized)
      if ']' in normalized:
        inBracket = false
        let openIdx = bracketAccum.find('[')
        let closeIdx = bracketAccum.rfind(']')
        if openIdx >= 0 and closeIdx > openIdx:
          let inner = bracketAccum[openIdx + 1 ..< closeIdx]
          for entry in inner.split(','):
            var modPath = entry.strip()
            # Strip ` as <alias>`
            let asIdx = modPath.find(" as ")
            if asIdx >= 0:
              modPath = modPath[0 ..< asIdx].strip()
            # Strip `except <name>`
            let excIdx = modPath.find(" except ")
            if excIdx >= 0:
              modPath = modPath[0 ..< excIdx].strip()
            if modPath.len > 0:
              var fullPath = ""
              if bracketPrefix.len > 0:
                fullPath = bracketPrefix & "/" & modPath
              else:
                fullPath = modPath
              # Deduplicate
              var found = false
              for existing in result:
                if existing == fullPath:
                  found = true
                  break
              if not found:
                result.add(fullPath)
        bracketAccum = ""
        bracketPrefix = ""
      continue

    # ── Bare import block: indented continuation after a bare `import` ──────
    if inImportBlock:
      if line.len > 0 and (line[0] == ' ' or line[0] == '\t'):
        # Continuation of import block — treat as an import line
        discard  # fall through to the import parsing below
      else:
        inImportBlock = false
        # Fall through — this line might itself be an import/from statement

    # ── from X import Y ─────────────────────────────────────────────────────
    if normStripped.startsWith("from ") and " import " in normStripped:
      let fromEnd = 5  # len("from ")
      let importStart = normStripped.find(" import ")
      if importStart > fromEnd:
        var modPath = normStripped[fromEnd ..< importStart].strip()
        # Strip ` as <alias>`
        let asIdx = modPath.find(" as ")
        if asIdx >= 0:
          modPath = modPath[0 ..< asIdx].strip()
        if modPath.len > 0:
          var found = false
          for existing in result:
            if existing == modPath:
              found = true
              break
          if not found:
            result.add(modPath)
      continue

    # ── import ... ───────────────────────────────────────────────────────────
    if "import " in normStripped:
      let importIdx = normStripped.find("import ")
      if importIdx >= 0:
        let afterImport = normStripped[importIdx + 7 .. ^1].strip()

        # Bracket opens on this line but does not close → enter bracket mode
        if '[' in afterImport and ']' notin afterImport:
          let openIdx = afterImport.find('[')
          bracketPrefix = afterImport[0 ..< openIdx].strip()
          # Normalize: remove trailing slash
          if bracketPrefix.len > 0 and bracketPrefix[^1] == '/':
            bracketPrefix = bracketPrefix[0 ..< ^1]
          inBracket = true
          bracketAccum = afterImport
          continue

        # Bracket opens and closes on the same line
        if '[' in afterImport and ']' in afterImport:
          let openIdx = afterImport.find('[')
          let closeIdx = afterImport.rfind(']')
          var prefix = afterImport[0 ..< openIdx].strip()
          # Normalize: remove trailing slash
          if prefix.len > 0 and prefix[^1] == '/':
            prefix = prefix[0 ..< ^1]
          let bracketContent = afterImport[openIdx + 1 ..< closeIdx]

          for entry in bracketContent.split(','):
            var modPath = entry.strip()
            # Strip ` as <alias>`
            let asIdx = modPath.find(" as ")
            if asIdx >= 0:
              modPath = modPath[0 ..< asIdx].strip()
            # Strip `except <name>`
            let excIdx = modPath.find(" except ")
            if excIdx >= 0:
              modPath = modPath[0 ..< excIdx].strip()
            if modPath.len > 0:
              var fullPath = ""
              if prefix.len > 0:
                fullPath = prefix & "/" & modPath
              else:
                fullPath = modPath
              var found = false
              for existing in result:
                if existing == fullPath:
                  found = true
                  break
              if not found:
                result.add(fullPath)
          continue

        # Comma-separated or single import on one line
        for entry in afterImport.split(','):
          var modPath = entry.strip()
          # Strip ` except <name>` / `exceptz <name>`
          let excIdx = modPath.find(" except")
          if excIdx >= 0:
            modPath = modPath[0 ..< excIdx].strip()
          # Strip ` as <alias>`
          let asIdx = modPath.find(" as ")
          if asIdx >= 0:
            modPath = modPath[0 ..< asIdx].strip()
          if modPath.len > 0:
            var found = false
            for existing in result:
              if existing == modPath:
                found = true
                break
            if not found:
              result.add(modPath)
      continue

    # ── Bare import block: indented path without `import` keyword ─────────
    # If we're in a bare import block and no pattern matched above,
    # treat the stripped line as a raw import path.
    if inImportBlock and normStripped.len > 0:
      var found = false
      for existing in result:
        if existing == normStripped:
          found = true
          break
      if not found:
        result.add(normStripped)
      continue

    # ── Bare `import` keyword (no path after it) → enter import block ───────
    if normStripped == "import":
      inImportBlock = true
      continue

# ─── Domain Utilities ─────────────────────────────────────────────────────────

func getDomainPrefix*(importPath: string): string =
  ## Extract domain prefix from import path.
  ## "core/topology/lock" → "topology"
  ## "std/json" → "" (stdlib, not a domain)
  ## "verification/solver/z3_pool" → "verification"
  ## "foo" → "" (single-component import, skip)
  result = ""

  # Skip stdlib and pkg paths
  if importPath.startsWith("std/") or importPath.startsWith("pkg/"):
    return ""

  # Count slashes to determine component count
  var slashCount = 0
  for ch in importPath:
    if ch == '/':
      inc slashCount

  # Need at least 2 components to have a domain prefix
  if slashCount < 1:
    return ""

  # Find the second component: skip past the first '/'
  let firstSlash = importPath.find('/')
  let secondStart = firstSlash + 1
  var secondEnd = secondStart
  while secondEnd < importPath.len and importPath[secondEnd] != '/':
    inc secondEnd

  if secondEnd > secondStart:
    result = importPath[secondStart ..< secondEnd]

func countDistinctPrefixes*(content: string): int =
  ## Count distinct domain prefixes in a file's imports.
  ## Uses parseImports + getDomainPrefix.
  let imports = parseImports(content)
  # Manual distinct count (no HashSet dependency)
  var prefixes: seq[string] = @[]
  for imp in imports:
    let pfx = getDomainPrefix(imp)
    if pfx.len > 0:
      var found = false
      for existing in prefixes:
        if existing == pfx:
          found = true
          break
      if not found:
        prefixes.add(pfx)
  result = prefixes.len

func getDomainPrefixes*(content: string): seq[string] =
  ## Get all distinct domain prefixes from file content.
  let imports = parseImports(content)
  var prefixes: seq[string] = @[]
  for imp in imports:
    let pfx = getDomainPrefix(imp)
    if pfx.len > 0:
      var found = false
      for existing in prefixes:
        if existing == pfx:
          found = true
          break
      if not found:
        prefixes.add(pfx)
  result = prefixes

{.pop.}  # raises
{.pop.}  # noSideEffect
