## registry_macro — L2 Zero-Persistence In-Memory Registry Injector.
## Compile-time macro that scans all .nim files and builds an in-memory
## const table of axiom-annotated symbols.
##
## Phase 17: Four-Layer Proof-Carrying Code — L2 Registry Injector.
##
## IMPORTANT Agent-127 quirks:
##   - closeParser internally closes the stream — NO separate llStreamClose
##   - Variable name `ast` is FORBIDDEN (collides with compiler/ast module)
##   - Must use AbsoluteFile for filenames

import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

import std/macros
import std/[os, strutils, algorithm, options]

# ─── Type alias ──────────────────────────────────────────────────────────────

type
  RegistryEntry* = tuple[name: string, modulePath: string, line: int, kind: string]

# ─── Runtime Lookup ──────────────────────────────────────────────────────────

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func lookupRegistry*(name: string,
                      registry: seq[RegistryEntry]): Option[RegistryEntry] =
  ## Runtime lookup in the baked registry.
  ## Returns some(entry) if found, none otherwise.
  ## O(N) linear scan — acceptable for registry sizes < 1000.
  for entry in registry:
    if entry.name == name:
      return some(entry)
  none(RegistryEntry)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func lookupByKind*(kind: string,
                    registry: seq[RegistryEntry]): seq[RegistryEntry] =
  ## Return all entries matching the given kind (axiomImpl/axiomMacro/axiomDsl).
  result = @[]
  for entry in registry:
    if entry.kind == kind:
      result.add(entry)

# ─── Compile-Time Registry Builder ───────────────────────────────────────────

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro injectRegistry*(srcDir: static string): untyped =
  ## At compile time, scans all .nim files in srcDir for axiom-annotated
  ## symbols and builds a sorted const table.
  ##
  ## Returns nnkConstSection with `axiomRegistryBaked*` const.
  ##
  ## This macro eliminates the need for src/generated/axiom_topology.nim
  ## by baking the registry directly into the binary at compile time.
  ## Zero disk I/O at runtime — everything is in-memory.
  ##
  ## Usage:
  ##   static:
  ##     const axiomRegistryBaked = injectRegistry("src")

  # Phase 1: Collect all .nim files via walkDirRec at macro expansion time
  # Nim 2.x walkDirRec yields file paths; filter for .nim extension.
  var nimFiles: seq[string] = @[]
  for path in walkDirRec(srcDir):
    if path.endsWith(".nim"):
      nimFiles.add(path)

  # Phase 2: For each file, use staticRead + string scanning for axiom pragmas
  # We use string scanning (not compiler/parser) because macros execute in
  # a limited compile-time context.
  var entries: seq[tuple[name: string, modulePath: string, line: int, kind: string]] = @[]

  for filePath in nimFiles:
    var content: string
    try:
      content = staticRead(filePath)
    except IOError:
      continue
    if content.len == 0:
      continue

    let lines = content.splitLines()
    for i, line in lines:
      let stripped = line.strip()
      # Skip comments
      if stripped.startsWith("#"):
        continue

      # Check for axiom pragma patterns
      let axiomPragmas = ["axiomImpl", "axiomOpaque", "axiomTryImpl", "axiomMacro", "axiomDsl"]
      for pragma in axiomPragmas:
        if "{." & pragma & ".}" in stripped or
           pragma in stripped:
          # Extract the function/proc/type name from this line or nearby lines
          var name = ""
          var kind = pragma

          # Try to extract name from current line
          if stripped.startsWith("func ") or stripped.startsWith("proc "):
            let parts = stripped.split({' ', '('})
            if parts.len >= 2:
              name = parts[1]
              if name.endsWith("*"):
                name = name[0..^2]
          elif stripped.startsWith("macro ") or stripped.startsWith("template "):
            let parts = stripped.split({' ', '('})
            if parts.len >= 2:
              name = parts[1]
              if name.endsWith("*"):
                name = name[0..^2]

          # If name not found on pragma line, check previous lines
          if name.len == 0 and i > 0:
            for j in countdown(max(0, i - 3), i - 1):
              let prevLine = lines[j].strip()
              if prevLine.startsWith("func ") or prevLine.startsWith("proc "):
                let parts = prevLine.split({' ', '('})
                if parts.len >= 2:
                  name = parts[1]
                  if name.endsWith("*"):
                    name = name[0..^2]
                  break
              elif prevLine.startsWith("type "):
                let parts = prevLine.split({' ', '='})
                if parts.len >= 2:
                  name = parts[1]
                  if name.endsWith("*"):
                    name = name[0..^2]
                  break

          if name.len > 0:
            entries.add((name: name, modulePath: filePath, line: i + 1, kind: kind))

  # Phase 3: Sort entries for determinism (by name, then module path)
  entries.sort(proc(a, b: tuple[name: string, modulePath: string, line: int, kind: string]): int =
    let nameCmp = cmp(a.name, b.name)
    if nameCmp != 0: return nameCmp
    return cmp(a.modulePath, b.modulePath)
  )

  # Phase 4: Build the const section AST
  # Result type: const axiomRegistryBaked*: seq[(string, string, int, string)] = @[...]
  result = newNimNode(nnkConstSection)

  var constDef = newNimNode(nnkConstDef)
  constDef.add(ident("axiomRegistryBaked"))

  # Type annotation
  var tupleType = nnkBracketExpr.newTree(
    ident("seq"),
    nnkTupleConstr.newTree(
      ident("string"),  # name
      ident("string"),  # modulePath
      ident("int"),     # line
      ident("string")   # kind
    )
  )
  constDef.add(tupleType)

  # Build the value: @[(name, module, line, kind), ...]
  var seqLit = nnkPrefix.newTree(ident("@"), nnkBracket.newTree())
  for entry in entries:
    let tupleNode = nnkPar.newTree(
      newStrLitNode(entry.name),
      newStrLitNode(entry.modulePath),
      newIntLitNode(entry.line),
      newStrLitNode(entry.kind)
    )
    seqLit[1].add(tupleNode)

  constDef.add(seqLit)
  result.add(constDef)

{.pop.}
