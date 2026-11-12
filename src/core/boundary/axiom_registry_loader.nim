import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import core/crypto/hash_kernel
import core/pure/json_parse
import core/types/results
import std/[strutils, os, json]
import core/trusted/axiom_pragmas
type
  AxiomTier* = enum
    atTier1  ## ADT modeling (Option[T], Result[T,E]) via Z3 declare-datatypes
    atTier2  ## Abstract spec (Table, JsonNode) via declare-sort + axioms
    atTier3  ## Uninterpreted functions (complex I/O) via declare-fun

  AxiomDef* = object
    name*: string
    formula*: string
    lean*: string

  AxiomLocation* = object
    line*: int
    column*: int

  AxiomLocationReport* = object
    name*: string
    location*: AxiomLocation
    contextLines*: seq[string]

  AxiomRegistryEntry* = object
    typeName*: string
    tier*: AxiomTier
    sortDecl*: string
    axioms*: seq[AxiomDef]

  AxiomRegistry* = object
    version*: string
    checksum*: string
    entries*: seq[AxiomRegistryEntry]
    rawJson*: string
    lineIndex*: seq[tuple[name: string, line: int]]
# ── Checksum Verification ──

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func computeRegistryChecksum*(rawJson: string): string {.raises: [].} =
  ## Compute SHA-256 checksum of JSON content, excluding the "checksum" field.
  ## Parses the JSON, removes the checksum key, then hashes the canonical form.
  try:
    let node = pureParseJson(rawJson)
    if node.hasKey("checksum"):
      node.delete("checksum")
    let canonical = $node
    result = hash_kernel.sha256Hex(canonical)
  except CatchableError:
    result = ""
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func verifyChecksum*(registry: AxiomRegistry): bool {.raises: [].} =
  ## Verify that the stored checksum matches a freshly computed one.
  if registry.checksum.len == 0:
    return false
  let computed = computeRegistryChecksum(registry.rawJson)
  computed == registry.checksum
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func buildAxiomLineIndex*(rawJson: string): seq[tuple[name: string, line: int]] {.raises: [].} =
  ## Scan raw JSON text to find "name" fields and their line numbers.
  ## Used for error reporting with line-level precision.
  ## Finds ALL "name" fields per line, not just the first.
  result = @[]
  let lines = rawJson.splitLines()
  for i, line in lines:
    let trimmed = line.strip()
    # Find all "name" : "value" patterns in this line
    var searchPos = 0
    while searchPos < trimmed.len:
      let nameIdx = trimmed.find("\"name\"", searchPos)
      if nameIdx < 0:
        break
      let colonIdx = trimmed.find(':', nameIdx + 6)
      if colonIdx >= 0:
        let quoteStart = trimmed.find('"', colonIdx + 1)
        if quoteStart >= 0:
          let quoteEnd = trimmed.find('"', quoteStart + 1)
          if quoteEnd > quoteStart:
            let nameVal = trimmed[quoteStart + 1 ..< quoteEnd]
            if nameVal.len > 0:
              result.add((name: nameVal, line: i + 1))
      searchPos = nameIdx + 6
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func lookupAxiomLine*(lineIndex: seq[tuple[name: string, line: int]];
                      axiomName: string): int {.raises: [].} =
  ## Find the line number for a given axiom name. Returns -1 if not found.
  for entry in lineIndex:
    if entry.name == axiomName:
      return entry.line
  -1
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func readJsonContextLines*(rawJson: string; lineNumber: int;
                           radius: int = 3): seq[string] {.raises: [].} =
  ## Return ±radius lines around lineNumber (1-based) from raw JSON text.
  ## Used for debugging — gives surrounding context when a checksum or
  ## formula validation fails.
  let lines = rawJson.splitLines()
  if lines.len == 0 or lineNumber < 1:
    return @[]
  let startIdx = max(0, lineNumber - 1 - radius)
  let endIdx = min(lines.len - 1, lineNumber - 1 + radius)
  for i in startIdx .. endIdx:
    let prefix = if i == lineNumber - 1: ">> " else: "   "
    result.add(prefix & $(i + 1) & ": " & lines[i])
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func parseTier*(tierInt: int): AxiomTier {.raises: [].} =
  case tierInt
  of 1: atTier1
  of 2: atTier2
  of 3: atTier3
  else: atTier2
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc loadAxiomRegistry*(path: string): Result[AxiomRegistry, string] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Load and validate the axiom registry from a JSON file.
  ## Returns Err on I/O failure, JSON parse error, or checksum mismatch.
  try:
    if not fileExists(path):
      return err("Axiom registry file not found: " & path)
    let rawJson = readFile(path)
    if rawJson.len == 0:
      return err("Axiom registry file is empty: " & path)
    let node = pureParseJson(rawJson)
    let version = node.getOrDefault("version").getStr("")
    let checksum = node.getOrDefault("checksum").getStr("")
    var entries: seq[AxiomRegistryEntry] = @[]
    let entriesNode = node.getOrDefault("entries")
    if entriesNode.kind == JArray:
      for entryNode in entriesNode:
        let typeName = entryNode.getOrDefault("typeName").getStr("")
        let tier = parseTier(entryNode.getOrDefault("tier").getInt(2))
        let sortDecl = entryNode.getOrDefault("sortDecl").getStr("")
        var axioms: seq[AxiomDef] = @[]
        let axiomsNode = entryNode.getOrDefault("axioms")
        if axiomsNode.kind == JArray:
          for axiomNode in axiomsNode:
            axioms.add(AxiomDef(
              name: axiomNode.getOrDefault("name").getStr(""),
              formula: axiomNode.getOrDefault("formula").getStr(""),
              lean: axiomNode.getOrDefault("lean").getStr("")
            ))
        entries.add(AxiomRegistryEntry(
          typeName: typeName,
          tier: tier,
          sortDecl: sortDecl,
          axioms: axioms
        ))
    let lineIndex = buildAxiomLineIndex(rawJson)
    var registry = AxiomRegistry(
      version: version,
      checksum: checksum,
      entries: entries,
      rawJson: rawJson,
      lineIndex: lineIndex
    )
    # Verify checksum
    if not registry.verifyChecksum():
      return err("Checksum mismatch in axiom registry at " & path)
    ok(registry)
  except CatchableError as e:
    err("Failed to load axiom registry: " & e.msg)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func buildLocationReport*(registry: AxiomRegistry;
                          axiomName: string): AxiomLocationReport {.raises: [].} =
  ## Build a location report for a given axiom name with surrounding context.
  let line = lookupAxiomLine(registry.lineIndex, axiomName)
  let ctxLines = if line > 0: readJsonContextLines(registry.rawJson, line) else: @[]
  AxiomLocationReport(
    name: axiomName,
    location: AxiomLocation(line: line, column: 0),
    contextLines: ctxLines
  )

{.pop.}
