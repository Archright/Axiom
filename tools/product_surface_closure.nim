## tools/product_surface_closure.nim — deterministic static import-closure
## tool for the product entrypoint.
##
## BFS over the static import graph starting at --entry. Only lines whose
## first non-space token is `import`, `from`, or `include` are parsed
## (line-based, no full Nim parsing, per contract). Handled forms: dot paths
## (`a.b.c`), slash paths (`x / y / z`), bracket groups (`x / [y, z]`),
## comma lists, trailing `as alias`, trailing `except` clauses.
##
## Module resolution order: importing file's directory, then src/, tools/,
## vendor/ (mirrors config.nims --path src / --path tools, plus vendor/).
## Unresolvable names (stdlib, nimble packages) are recorded. Output is a
## single sorted, timestamp-free JSON document at --out; contentHash (sha256
## over files and edges) makes output byte-identical for the same repo.
##
## SHA-256 comes from tools/sha256_native.nim (repo-canonical, pure): the
## pinned Nim 2.2.10 stdlib ships only std/sha1, no std/sha256.

import std/[algorithm, json, os, sequtils, sets, strutils]
import ./sha256_native

type
  ImportEdge = object
    fromFile*: string
    toFile*: string

proc edgeLess(a, b: ImportEdge): int {.raises: [].} =
  result = cmp(a.fromFile, b.fromFile)
  if result == 0:
    result = cmp(a.toFile, b.toFile)

proc normalize(path: string): string {.raises: [].} =
  var p = path
  normalizePath(p)
  p

proc cutAtSharp(line: string): tuple[code: string, openBlock: bool] {.raises: [].} =
  ## Cut at the first '#' (trailing comment or '#[' block opener). openBlock
  ## is set when that '#' opens a '#[ ... ]#' comment that continues past
  ## this line.
  let sharp = line.find('#')
  if sharp < 0:
    return (line.strip(), false)
  if line[sharp .. ^1].startsWith("#[") and line.find("]#", sharp + 2) < 0:
    return (line[0 ..< sharp].strip(), true)
  return (line[0 ..< sharp].strip(), false)

proc idxOfKeyword(line: string, kw: string): int {.raises: [].} =
  ## Offset of the first standalone (whitespace-delimited) occurrence of kw.
  var i = 0
  while i < line.len:
    while i < line.len and line[i] in {' ', '\t'}: inc i
    if i >= line.len: break
    let start = i
    while i < line.len and line[i] notin {' ', '\t'}: inc i
    if line[start ..< i] == kw: return start
  -1

proc cutAtKeyword(line: string, kw: string): string {.raises: [].} =
  ## Text before the first standalone kw, trimmed.
  let idx = idxOfKeyword(line, kw)
  if idx >= 0: line[0 ..< idx].strip()
  else: line.strip()

proc splitTopLevel(item: string): seq[string] {.raises: [].} =
  ## Comma-split at bracket depth 0: `a / [b, c], d` -> `a / [b, c]`, `d`.
  var depth = 0
  var cur = ""
  for ch in item:
    case ch
    of '[': inc depth; cur.add(ch)
    of ']': dec depth; cur.add(ch)
    of ',':
      if depth == 0:
        result.add(cur)
        cur.setLen(0)
      else:
        cur.add(ch)
    else: cur.add(ch)
  if cur.strip().len > 0:
    result.add(cur)

proc expandOne(item: string): seq[string] {.raises: [].} =
  ## Expand one import item: `x / [y, z]` -> `x/y`, `x/z`; `a.b` stays for
  ## resolution. A standalone `as` token terminates the item (alias drop).
  var paths: seq[seq[string]] = @[@[]]
  for part0 in item.split('/'):
    let part = part0.strip()
    if part.len == 0: continue
    if part == "as": break
    var nxt: seq[seq[string]] = @[]
    for p in paths:
      if part.len >= 2 and part[0] == '[' and part[^1] == ']':
        for n in part[1 .. ^2].split(','):
          var segs: seq[string] = @[]
          for s0 in n.split('/'):
            let s = s0.strip()
            if s.len > 0: segs.add(s)
          if segs.len > 0: nxt.add(p & segs)
      else:
        nxt.add(p & @[part])
    paths = nxt
  for p in paths:
    if p.len > 0:
      result.add(join(p, "/"))

proc firstWordEnd(s: string): int {.raises: [].} =
  ## Index just past the first whitespace-delimited word of `s`.
  var i = 0
  while i < s.len and s[i] in {' ', '\t'}: inc i
  while i < s.len and s[i] notin {' ', '\t'}: inc i
  i

proc statementContinued(s: string): bool {.raises: [].} =
  ## True when the import statement carries onto the next line: no body yet,
  ## a trailing top-level comma, or an unclosed '[' bracket group.
  let body = s[firstWordEnd(s) .. ^1].strip()
  if body.len == 0: return true
  var depth = 0
  for ch in body:
    case ch
    of '[': inc depth
    of ']': dec depth
    else: discard
  body.endsWith(",") or depth > 0

proc importNamesOf(line: string): seq[string] {.raises: [].} =
  ## Module names referenced by one `import` / `from` / `include` line.
  let endTok = firstWordEnd(line)
  if endTok == 0: return
  let tok = line[0 ..< endTok]
  let body = line[endTok .. ^1].strip()
  case tok
  of "import", "include":
    let clean = cutAtKeyword(cutAtKeyword(body, "as"), "except")
    for item in splitTopLevel(clean):
      for name in expandOne(item):
        result.add(name)
  of "from":
    let clean = cutAtKeyword(cutAtKeyword(cutAtKeyword(body, "import"), "as"), "except")
    for name in expandOne(clean):
      result.add(name)
  else: discard

proc importsOf(path: string): seq[string] =
  ## Every module name referenced by `path`, skipping comment blocks and
  ## joining multi-line import statements (line breaks after `import` or a
  ## trailing comma).
  var f: File
  if not f.open(path, fmRead):
    raise newException(IOError, "cannot open " & path)
  var inBlockComment = false
  var stmt = ""
  for line in f.lines:
    if inBlockComment:
      if line.find("]#") >= 0: inBlockComment = false
      continue
    let (code, openBlock) = cutAtSharp(line)
    if openBlock:
      inBlockComment = true
    if stmt.len > 0:
      if code.len > 0:
        stmt.add(" ")
        stmt.add(code)
        if not statementContinued(stmt):
          for name in importNamesOf(stmt):
            result.add(name)
          stmt.setLen(0)
      continue
    if code.len == 0:
      continue
    var i = 0
    while i < code.len and code[i] in {' ', '\t'}: inc i
    let endTok = i
    while i < code.len and code[i] notin {' ', '\t'}: inc i
    let tok = code[endTok ..< i]
    if tok == "import" or tok == "include" or tok == "from":
      if statementContinued(code):
        stmt = code
      else:
        for name in importNamesOf(code):
          result.add(name)

proc checkNimFile(path: string): string {.raises: [].} =
  ## `path` (or `path.nim`) as a normalized path when it exists, else "".
  for cand in [path, path & ".nim"]:
    if fileExists(cand):
      return normalize(cand)
  ""

proc resolveModule(importingFile, name: string): string {.raises: [].} =
  ## Canonical repo-relative .nim path for `name` imported from
  ## `importingFile`; "" when unresolvable.
  if name.startsWith("./") or name.startsWith("../"):
    return checkNimFile(normalize(parentDir(importingFile) / name))
  let dotted = name.replace('.', '/')
  for cand in [parentDir(importingFile) / dotted,
               "src" / dotted,
               "tools" / dotted,
               "vendor" / dotted]:
    let hit = checkNimFile(cand)
    if hit.len > 0: return hit
  ""

proc computeContentHash(files: seq[string], edges: seq[ImportEdge]): string {.raises: [].} =
  var content = ""
  for fname in files:
    content.add(fname & "\n")
  for e in edges:
    content.add(e.fromFile & "\t" & e.toFile & "\n")
  "sha256:" & sha256String(content)

proc run(args: seq[string]) =
  if args.len != 4 or args[0] != "--entry" or args[2] != "--out":
    stderr.writeLine("usage: product_surface_closure --entry <file.nim> --out <output.json>")
    quit(1)
  let entry = normalize(args[1])
  let outPath = args[3]
  if not fileExists(entry):
    stderr.writeLine("entry not found: " & args[1])
    quit(1)

  var queue = @[entry]
  var visited = initHashSet[string]()
  visited.incl(entry)
  var edgeSet = initHashSet[tuple[a, b: string]]()
  var unresolvedSet = initHashSet[string]()
  var head = 0
  while head < queue.len:
    let cur = queue[head]
    inc head
    for name in importsOf(cur):
      let resolved = resolveModule(cur, name)
      if resolved.len == 0:
        unresolvedSet.incl(name)
      else:
        edgeSet.incl((cur, resolved))
        if resolved notin visited:
          visited.incl(resolved)
          queue.add(resolved)

  var files = toSeq(visited)
  sort(files, system.cmp)
  var edges: seq[ImportEdge] = @[]
  for (a, b) in edgeSet:
    edges.add(ImportEdge(fromFile: a, toFile: b))
  sort(edges, edgeLess)
  var unresolved = toSeq(unresolvedSet)
  sort(unresolved, system.cmp)

  var edgesJson = newSeq[JsonNode](edges.len)
  for i, e in edges:
    edgesJson[i] = %* {"from": e.fromFile, "to": e.toFile}
  let doc = %* {
    "schemaVersion": 1,
    "entrypoint": entry,
    "reachableFiles": files,
    "unresolvedModules": unresolved,
    "importEdges": edgesJson,
    "moduleCount": files.len,
    "edgeCount": edges.len,
    "contentHash": computeContentHash(files, edges)
  }
  writeFile(outPath, doc.pretty() & "\n")
  stderr.writeLine(entry & " -> " & outPath & ": " &
                   $files.len & " files, " & $edges.len & " edges, " &
                   $unresolved.len & " unresolved")

when isMainModule:
  run(commandLineParams())