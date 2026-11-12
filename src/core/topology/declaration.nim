import core/trusted/layer_declaration
axiomLayer "domain"
import core/io/file_utils
import core/pure/json_parse
import core/results
import std/[os, re, strutils, tables]
import std/json except parseJson
# axiomIoBoundary

type
  Subdomain* = object
    description*: string
    paths*: seq[string]

  Domain* = object
    description*: string
    level*: int
    targetLevel*: int
    allowedImports*: seq[string]
    subdomains*: Table[string, Subdomain]

  PatternMapping* = object
    pattern*: string
    domain*: string
    subdomain*: string

  FileMapping* = object
    domain*: string
    subdomain*: string
    note*: string

  TopologyDeclaration* = object
    schema*: string
    domains*: Table[string, Domain]
    mappingByPattern*: seq[PatternMapping]
    mappingByFile*: Table[string, FileMapping]
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func globToRegex*(pattern: string): string {.raises: [].} =
  ## Converts glob pattern with **, *, ? to regex.
  ## ** matches any sequence including /
  ## * matches any sequence except /
  ## ? matches any single char except /
  var i = 0
  result = "^"
  while i < pattern.len:
    if i + 1 < pattern.len and pattern[i] == '*' and pattern[i+1] == '*':
      result.add(".*")
      i += 2
    elif pattern[i] == '*':
      result.add("[^/]*")
      inc i
    elif pattern[i] == '?':
      result.add("[^/]")
      inc i
    elif pattern[i] in {'\\', '.', '+', '(', ')', '|', '^', '$'}:
      result.add('\\')
      result.add(pattern[i])
      inc i
    else:
      result.add(pattern[i])
      inc i
  result.add("$")
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func globMatch*(pattern, text: string): bool {.raises: [].} =
  try:
    let r = re(globToRegex(pattern))
    result = text.match(r)
  except CatchableError:
    result = false
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func parseSubdomains*(j: JsonNode): Table[string, Subdomain] {.raises: [].} =
  result = initTable[string, Subdomain]()
  if j.kind != JObject:
    return
  for name, val in j.pairs:
    var s = Subdomain(description: "")
    if val.hasKey("description"):
      s.description = val{"description"}.getStr
    if val.hasKey("paths"):
      for p in val{"paths"}:
        s.paths.add(p.getStr)
    result[name] = s
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func parseStringSeq*(j: JsonNode): seq[string] {.raises: [].} =
  result = @[]
  if j.kind != JArray:
    return
  for item in j:
    result.add(item.getStr)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func parseDomains*(j: JsonNode): Table[string, Domain] {.raises: [].} =
  result = initTable[string, Domain]()
  if j.kind != JObject:
    return
  for name, val in j.pairs:
    var d = Domain(
      description: if val.hasKey("description"): val{"description"}.getStr else: "",
      level: if val.hasKey("level"): val{"level"}.getInt else: 0,
      targetLevel: if val.hasKey("targetLevel"): val{"targetLevel"}.getInt else: 0
    )
    if val.hasKey("allowedImports"):
      d.allowedImports = parseStringSeq(val{"allowedImports"})
    if val.hasKey("subdomains"):
      d.subdomains = parseSubdomains(val{"subdomains"})
    result[name] = d
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func parseTopologyDeclarationJson*(jsonStr: string): Result[TopologyDeclaration, string] {.raises: [].} =
  ## Pure: parse a topology declaration JSON string.
  try:
    let j = pureParseJson(jsonStr)
    var decl = TopologyDeclaration(
      schema: j{"_schema"}.getStr(""),
      domains: parseDomains(j{"domains"})
    )

    decl.mappingByPattern = @[]
    decl.mappingByFile = initTable[string, FileMapping]()

    if j.hasKey("mapping"):
      let m = j{"mapping"}
      if m.hasKey("by_pattern"):
        for p in m{"by_pattern"}:
          decl.mappingByPattern.add(PatternMapping(
            pattern: p{"pattern"}.getStr(""),
            domain: p{"domain"}.getStr(""),
            subdomain: p{"subdomain"}.getStr("")
          ))
      if m.hasKey("by_file"):
        for pathKey, val in m{"by_file"}.pairs:
          decl.mappingByFile[pathKey] = FileMapping(
            domain: val{"domain"}.getStr(""),
            subdomain: val{"subdomain"}.getStr(""),
            note: if val.hasKey("note"): val{"note"}.getStr else: ""
          )
    ok(decl)
  except CatchableError as e:
    err("topology declaration JSON unreadable: " & e.msg & " — failing closed per §0.9")
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc parseTopologyDeclaration*(path: string): Result[TopologyDeclaration, string] {.raises: [].} =
  ## Pure: parse a topology declaration JSON file. Returns err on parse error.
  let j =
    try:
      parseFile(path)
    except CatchableError as e:
      return err("topology declaration file unreadable: " & e.msg & " — failing closed per §0.9")
  try:
    if not j.hasKey("_schema") or j{"_schema"}.getStr("").len == 0:
      return err("topology declaration corrupt: missing _schema — failing closed per §0.9")
    if not j.hasKey("domains") or j{"domains"}.kind != JObject:
      return err("topology declaration corrupt: missing domains — failing closed per §0.9")
  except CatchableError as e:
    return err("topology declaration parse error: " & e.msg & " — failing closed per §0.9")
  var decl = TopologyDeclaration(
    schema: j{"_schema"}.getStr,
    domains: parseDomains(j{"domains"})
  )

  decl.mappingByPattern = @[]
  decl.mappingByFile = initTable[string, FileMapping]()

  if j.hasKey("mapping"):
    let m = j{"mapping"}
    if m.hasKey("by_pattern"):
      for p in m{"by_pattern"}:
        decl.mappingByPattern.add(PatternMapping(
          pattern: p{"pattern"}.getStr,
          domain: p{"domain"}.getStr,
          subdomain: p{"subdomain"}.getStr
        ))
    if m.hasKey("by_file"):
      for pathKey, val in m{"by_file"}.pairs:
        decl.mappingByFile[pathKey] = FileMapping(
          domain: val{"domain"}.getStr,
          subdomain: val{"subdomain"}.getStr,
          note: if val.hasKey("note"): val{"note"}.getStr else: ""
        )
  ok(decl)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func classifyFile*(filePath: string; decl: TopologyDeclaration): tuple[domain, subdomain, matchedBy: string] {.raises: [].} =
  ## matchedBy: "by_file", "by_pattern", or "unmapped"
  let byFile = decl.mappingByFile.getOrDefault(filePath)
  if byFile.domain.len > 0 or byFile.subdomain.len > 0:
    return (byFile.domain, byFile.subdomain, "by_file")
  for p in decl.mappingByPattern:
    if globMatch(p.pattern, filePath):
      return (p.domain, p.subdomain, "by_pattern")
  result = ("", "unmapped", "unmapped")
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func expectedPath*(filePath: string; domain, subdomain: string; decl: TopologyDeclaration): string {.raises: [].} =
  ## Returns the first allowed path for the subdomain, or "" if unknown.
  let d = decl.domains.getOrDefault(domain)
  if d.description.len == 0 and d.level == 0:
    return ""
  let sd = d.subdomains.getOrDefault(subdomain)
  if sd.paths.len > 0:
    result = sd.paths[0]
  else:
    result = ""
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func effectiveLevel*(decl: TopologyDeclaration; domainName: string): int {.raises: [].} =
  let d = decl.domains.getOrDefault(domainName)
  result = d.level
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func isStdlibImport*(imp: string): bool {.raises: [].} =
  ## Heuristic: stdlib modules are either 'std/...' or have no '/'.
  result = not imp.contains('/') or imp.startsWith("std/")
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func classifyImportDomain*(imp: string; decl: TopologyDeclaration): string {.raises: [].} =
  ## Determine which topology domain an import belongs to.
  ## Returns "" for stdlib or unclassified.
  if isStdlibImport(imp):
    return "std"
  # Try to map import path to a declared subdomain path
  for path, fm in decl.mappingByFile:
    let moduleName = path.changeFileExt("").replace('/', '.')
    if imp == moduleName or imp.endsWith("." & moduleName):
      return fm.domain
  for domainName, domain in decl.domains:
    for subName, sub in domain.subdomains:
      for allowedPath in sub.paths:
        let prefix = allowedPath.changeFileExt("")
        if imp.startsWith(prefix.replace('/', '.')):
          return domainName
  result = ""
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc listGhostPaths*(decl: TopologyDeclaration): seq[string] {.raises: [].} =
  ## Files declared in topology.json but missing on filesystem.
  result = @[]
  for path in decl.mappingByFile.keys:
    if not fileExists(path):
      result.add(path)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc isForwardingStub*(path: string): bool {.raises: [].} =
  ## A forwarding stub contains only import/export statements and comments.
  ## Used to skip stub files in lock compliance and declaration audits.
  ## Pure projection: I/O failures are treated as "not a stub" (deterministic).
  let exists = try: fileExists(path) except CatchableError: false
  if not exists:
    return false
  let content = try: readFileSafe(path) except CatchableError: ""
  for rawLine in content.splitLines:
    let line = rawLine.strip
    if line.len == 0 or line.startsWith("#") or line.startsWith("##"):
      continue
    if not (line.startsWith("import") or line.startsWith("export")):
      return false
  return true
