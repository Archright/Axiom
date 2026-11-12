import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import core/crypto/hash_kernel
import core/json/std_redirect
import core/pure/json_parse
import core/symbolic/global_symbol_graph_types
import core/types/global_symbol_graph_types
import core/types/results
import core/utils/io_utils
import std/algorithm
import std/os
import std/tables
import core/trusted/axiom_pragmas
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func extractSymbolsFromSourceFallback*(content: string; relPath: string): seq[SymbolNode] {.raises: [].} =
  ## Tree-sitter fallback: extract proc/func/method/iterator/converter names via regex.
  ## This ensures buildGlobalSymbolGraph never returns an empty graph when tree-sitter is unavailable.
  let moduleStem {.used.} = moduleNameFromPath(relPath)
  var i = 0
  while i < content.len:
    # Skip comments
    if i + 1 < content.len and content[i] == '#' and content[i+1] == '#':
      while i < content.len and content[i] notin {'\n', '\r'}:
        inc i
      continue
    if i + 1 < content.len and content[i] == '#' and content[i+1] != '#':
      while i < content.len and content[i] notin {'\n', '\r'}:
        inc i
      continue
    # Skip string literals
    if content[i] == '"':
      inc i
      while i < content.len and content[i] != '"':
        if content[i] == '\\' and i + 1 < content.len:
          inc i
        inc i
      inc i
      continue
    if content[i] == '\'':
      inc i
      while i < content.len and content[i] != '\'':
        if content[i] == '\\' and i + 1 < content.len:
          inc i
        inc i
      inc i
      continue
    # Look for proc/func/method/iterator/converter declarations
    if i + 4 < content.len and content[i] == 'p' and content[i+1] == 'r' and content[i+2] == 'o' and content[i+3] == 'c' and content[i+4] in {' ', '\t', '('}:
      i += 4
      while i < content.len and content[i] in {' ', '\t'}:
        inc i
      var name = ""
      while i < content.len and content[i] in {'A'..'Z', 'a'..'z', '0'..'9', '_', '`'}:
        name.add(content[i])
        inc i
      if name.len > 0 and name != "":
        let qn = qualifiedName(relPath, name)
        result.add(SymbolNode(
          qualifiedName: qn,
          kind: skProc,
          modulePath: relPath,
          astNode: nil,
          visibility: "public"
        ))
      continue
    if i + 4 < content.len and content[i] == 'f' and content[i+1] == 'u' and content[i+2] == 'n' and content[i+3] == 'c' and content[i+4] in {' ', '\t', '('}:
      i += 4
      while i < content.len and content[i] in {' ', '\t'}:
        inc i
      var name = ""
      while i < content.len and content[i] in {'A'..'Z', 'a'..'z', '0'..'9', '_', '`'}:
        name.add(content[i])
        inc i
      if name.len > 0:
        let qn = qualifiedName(relPath, name)
        result.add(SymbolNode(
          qualifiedName: qn,
          kind: skFunc,
          modulePath: relPath,
          astNode: nil,
          visibility: "public"
        ))
      continue
    if i + 6 < content.len and content[i] == 'm' and content[i+1] == 'e' and content[i+2] == 't' and content[i+3] == 'h' and content[i+4] == 'o' and content[i+5] == 'd' and content[i+6] in {' ', '\t', '('}:
      i += 6
      while i < content.len and content[i] in {' ', '\t'}:
        inc i
      var name = ""
      while i < content.len and content[i] in {'A'..'Z', 'a'..'z', '0'..'9', '_', '`'}:
        name.add(content[i])
        inc i
      if name.len > 0:
        let qn = qualifiedName(relPath, name)
        result.add(SymbolNode(
          qualifiedName: qn,
          kind: skProc,
          modulePath: relPath,
          astNode: nil,
          visibility: "public"
        ))
      continue
    if i + 8 < content.len and content[i] == 'i' and content[i+1] == 't' and content[i+2] == 'e' and content[i+3] == 'r' and content[i+4] == 'a' and content[i+5] == 't' and content[i+6] == 'o' and content[i+7] == 'r' and content[i+8] in {' ', '\t', '('}:
      i += 8
      while i < content.len and content[i] in {' ', '\t'}:
        inc i
      var name = ""
      while i < content.len and content[i] in {'A'..'Z', 'a'..'z', '0'..'9', '_', '`'}:
        name.add(content[i])
        inc i
      if name.len > 0:
        let qn = qualifiedName(relPath, name)
        result.add(SymbolNode(
          qualifiedName: qn,
          kind: skProc,
          modulePath: relPath,
          astNode: nil,
          visibility: "public"
        ))
      continue
    if i + 9 < content.len and content[i] == 'c' and content[i+1] == 'o' and content[i+2] == 'n' and content[i+3] == 'v' and content[i+4] == 'e' and content[i+5] == 'r' and content[i+6] == 't' and content[i+7] == 'e' and content[i+8] == 'r' and content[i+9] in {' ', '\t', '('}:
      i += 9
      while i < content.len and content[i] in {' ', '\t'}:
        inc i
      var name = ""
      while i < content.len and content[i] in {'A'..'Z', 'a'..'z', '0'..'9', '_', '`'}:
        name.add(content[i])
        inc i
      if name.len > 0:
        let qn = qualifiedName(relPath, name)
        result.add(SymbolNode(
          qualifiedName: qn,
          kind: skProc,
          modulePath: relPath,
          astNode: nil,
          visibility: "public"
        ))
      continue
    inc i
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc loadIncrementalGraphCache*(cachePath: string): Table[string, ModuleGraphContribution] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if not fileExists(cachePath):
    return initTable[string, ModuleGraphContribution]()
  try:
    let readRes = readFileOpt(cachePath)
    if readRes.isErr: return
    let data = readRes.get
    let root = pureParseJson(data)
    if root.kind != JObject or not root.hasKey("modules"):
      return initTable[string, ModuleGraphContribution]()
    for key, val in root["modules"]:
      if val.kind != JObject: continue
      let hash = val.getOrDefault("hash").getStr("")
      var syms: seq[SymbolNode] = @[]
      if val.hasKey("symbols") and val["symbols"].kind == JArray:
        for s in val["symbols"]:
          let qn = s.getOrDefault("qualifiedName").getStr("")
          if qn.len == 0: continue
          let kindStr = s.getOrDefault("kind").getStr("skProc")
          var kind = skProc
          case kindStr
          of "skProc": kind = skProc
          of "skFunc": kind = skFunc
          of "skType": kind = skType
          of "skField": kind = skField
          of "skVar": kind = skVar
          of "skLet": kind = skLet
          of "skConst": kind = skConst
          of "skGenericParam": kind = skGenericParam
          of "skLeanTheorem", "skLeanDef", "skLeanMacro", "skLeanAbbrev",
             "skLeanInductive", "skLeanStructure", "skLeanClass", "skLeanOpaque",
             "skLeanExample", "skLeanMeta": discard
          else: discard
          syms.add(SymbolNode(
            qualifiedName: qn,
            kind: kind,
            modulePath: s.getOrDefault("modulePath").getStr(""),
            astNode: nil,
            visibility: s.getOrDefault("visibility").getStr("public")
          ))
      var eds: seq[ReferenceEdge] = @[]
      if val.hasKey("edges") and val["edges"].kind == JArray:
        for e in val["edges"]:
          let kindStr = e.getOrDefault("kind").getStr("rkCall")
          var kind = rkCall
          case kindStr
          of "rkCall": kind = rkCall
          of "rkTypeUse": kind = rkTypeUse
          of "rkFieldAccess": kind = rkFieldAccess
          of "rkMutates": kind = rkMutates
          of "rkReads": kind = rkReads
          else: discard
          eds.add(ReferenceEdge(
            source: e.getOrDefault("source").getStr(""),
            target: e.getOrDefault("target").getStr(""),
            kind: kind,
            line: e.getOrDefault("line").getInt(0),
            column: e.getOrDefault("column").getInt(0)
          ))
      syms.sort(symbolNodeCmp)
      eds.sort(referenceEdgeCmp)
      result[key] = ModuleGraphContribution(fileHash: hash, symbols: syms, edges: eds)
  except CatchableError:
    return initTable[string, ModuleGraphContribution]()
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func globalSymbolGraphIncrementalCachePath*(repoRoot: string): string {.raises: [].} =
  joinPath(getTempDir(), "axiom_global_symbol_graph_inc." & sha256Hex(repoRoot) & ".json")

{.pop.}
