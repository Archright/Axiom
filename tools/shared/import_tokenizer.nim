## tools/shared/import_tokenizer.nim
## Deterministic import tokenizer — single source of truth for import path extraction.
## Extracted from src/core/trusted/axiom_pragmas.nim (tokenizeImports).
##
## Dependencies: std/[sets, strutils] only. No src/ imports.
## Used by: tools/hermetic_build, tools/axiom_validator, src/core/trusted/axiom_pragmas.nim

import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [].}

import std/[sets, strutils]

func tokenizeImports*(source: string): HashSet[string] =
  ## Deterministic tokenizer that extracts module paths from import statements.
  ## Lightweight state machine — no full parser required.
  ## Handles: import X, import X as Y, from X import Y,
  ##          multi-line bracket imports (import X/[a, b, c]),
  ##          comma-separated imports, commented-out lines (#), and
  ##          Windows path separators (\\ → /).
  result = initHashSet[string]()

  let lines = source.splitLines()
  var inBracket = false
  var bracketPrefix = ""
  var bracketAccum = ""

  for line in lines:
    let stripped = line.strip()

    # Skip empty lines and lines starting with # (commented-out imports)
    if stripped.len == 0 or stripped.startsWith("#"):
      continue

    # Normalize Windows path separators
    let normalized = line.replace("\\", "/")

    # ── Bracket accumulation state ──────────────────────────────────────────
    if inBracket:
      bracketAccum &= " " & normalized
      if "]" in normalized:
        inBracket = false
        # Extract content between [ and ]
        let openIdx = bracketAccum.find('[')
        let closeIdx = bracketAccum.rfind(']')
        if openIdx >= 0 and closeIdx > openIdx:
          let content = bracketAccum[openIdx + 1 ..< closeIdx]
          for modEntry in content.split(','):
            let modPath = modEntry.strip()
            if modPath.len > 0:
              let parts = modPath.split(" as ")
              let cleanPath = parts[0].strip()
              if cleanPath.len > 0:
                let fullPath = if bracketPrefix.len > 0:
                  bracketPrefix & "/" & cleanPath
                else:
                  cleanPath
                result.incl(fullPath)
        bracketAccum = ""
        bracketPrefix = ""
      continue

    # ── from X import Y ─────────────────────────────────────────────────────
    let s = normalized.strip()
    if s.startsWith("from ") and " import " in s:
      let fromEnd = 5  # len("from ")
      let importStart = s.find(" import ")
      if importStart > fromEnd:
        let modPath = s[fromEnd ..< importStart].strip()
        if modPath.len > 0:
          result.incl(modPath)
      continue

    # ── import ... ───────────────────────────────────────────────────────────
    if "import " in normalized:
      let importIdx = normalized.find("import ")
      if importIdx >= 0:
        let afterImport = normalized[importIdx + 7 .. ^1].strip()

        # Bracket opens on this line but does not close → enter bracket mode
        if "[" in afterImport and "]" notin afterImport:
          let openIdx = afterImport.find('[')
          bracketPrefix = afterImport[0 ..< openIdx].strip()
          # Normalize: remove trailing slash so prefix/module produces correct path
          if bracketPrefix.len > 0 and bracketPrefix[^1] == '/':
            bracketPrefix = bracketPrefix[0 ..< ^1]
          inBracket = true
          bracketAccum = afterImport
          continue

        # Bracket opens and closes on the same line
        if "[" in afterImport and "]" in afterImport:
          let openIdx = afterImport.find('[')
          let closeIdx = afterImport.rfind(']')
          var prefix = afterImport[0 ..< openIdx].strip()
          # Normalize: remove trailing slash so prefix/module produces correct path
          if prefix.len > 0 and prefix[^1] == '/':
            prefix = prefix[0 ..< ^1]
          let bracketContent = afterImport[openIdx + 1 ..< closeIdx]

          for modEntry in bracketContent.split(','):
            let modPath = modEntry.strip()
            if modPath.len > 0:
              let parts = modPath.split(" as ")
              let cleanPath = parts[0].strip()
              if cleanPath.len > 0:
                let fullPath = if prefix.len > 0:
                  prefix & "/" & cleanPath
                else:
                  cleanPath
                result.incl(fullPath)
          continue

        # Comma-separated or single import on one line
        for modEntry in afterImport.split(','):
          let modPath = modEntry.strip()
          if modPath.len > 0:
            let parts = modPath.split(" as ")
            let cleanPath = parts[0].strip()
            if cleanPath.len > 0:
              result.incl(cleanPath)
