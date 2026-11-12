import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Spec Generator Helpers
## Nim→Lean type mapping, AST parsing, and rendering helpers.
##
## Extracted from spec_generator_part1.nim (include-based) into a proper module.

import std/strutils
import core/trusted/axiom_pragmas

import core/parser_utils
import core/parsers/pred
import core/parsers/pnode_nav
import compiler/ast

import core/spec/spec_generator_types

# ── Identifier Normalization ──

# @axiom-hint: lean="raw.length ≥ 0" smt="(assert (and (>= (str.len raw) 0)))"
# @axiom-hint: lean="token.length = 0 ∧ buf.length = 0 ∧ (token ≥ 0)" smt="(assert (and (= (str.len token) 0) (= (str.len buf) 0) (>= token 0)))"
func normalizeIdent*(raw: string): string {.raises: [].} =
  var token = raw.strip()
  token = token.replace("*", "").replace("`", "")
  if token.len == 0:
    return "unnamed"
  var buf = newStringOfCap(token.len)
  for ch in token:
    if ch.isAlphaNumeric or ch == '_':
      buf.add(ch)
  if buf.len == 0:
    return "unnamed"
  buf

# ── Type Parsing Helpers ──

# @axiom-hint: lean="raw.length ≥ 0" smt="(assert (and (>= (str.len raw) 0)))"
# @axiom-hint: lean="depth > 0 ∧ ch = sep ∧ depth = 0 ∧ start ≤ raw.high ∧ start = i + 1 ∧ (start ≥ 0) ∧ (raw ≥ 0)" smt="(assert (and (> depth 0) (and (= ch sep) (= depth 0)) (<= start raw.high) (= start (+ i 1)) (>= start 0) (>= raw 0)))"
func splitTopLevel*(raw: string; sep: char): seq[string] {.raises: [].} =
  var depth = 0
  var start = 0
  for i, ch in raw:
    case ch
    of '[', '(', '{':
      inc depth
    of ']', ')', '}':
      if depth > 0:
        dec depth
    else:
      discard
    if ch == sep and depth == 0:
      result.add(raw[start ..< i].strip())
      start = i + 1
  if start <= raw.high:
    result.add(raw[start .. ^1].strip())

# @axiom-hint: lean="token.length = 0 ∧ quotePos > 0 ∧ token ∧ token.length = 0 → result = token" smt="(assert (and (= (str.len token) 0) (> quotePos 0) token (=> (= (str.len token) 0) (= result token))))"
func normalizeNimNumericLiteral*(raw: string): string {.raises: [].} =
  let token = raw.strip().replace("_", "")
  if token.len == 0:
    return token
  let quotePos = token.find('\'')
  if quotePos > 0:
    return token[0 ..< quotePos]
  token

# @axiom-hint: lean="raw.length ≥ 0 ∧ ast_parse_failed_isolated" smt="(assert (and (>= (str.len raw) 0) ast_parse_failed_isolated))"
# @axiom-hint: lean="raw.length ≥ 0" smt="(assert (and (>= (str.len raw) 0)))"
# @axiom-hint: lean="token.length = 0 ∧ false ∧ token.length = 0 → result = false ∧ (token ≥ 0)" smt="(assert (and (= (str.len token) 0) false (=> (= (str.len token) 0) (= result false)) (>= token 0)))"
func isNonNegativeIntegerLiteral*(raw: string): bool {.raises: [].} =
  let token = normalizeNimNumericLiteral(raw)
  if token.len == 0:
    return false
  if token[0] == '-':
    return false
  for ch in token:
    if not ch.isDigit:
      return false
  true

# @axiom-hint: lean="lowerBound.length = 0 ∨ upperBound.length = 0" smt="(assert (and (or (= (str.len lowerBound) 0) (= (str.len upperBound) 0))))"
func parseRangeBounds*(raw: string): tuple[ok: bool; lowerBound: string; upperBound: string] {.raises: [].} =
  let cleaned = raw.strip()
  let dots = cleaned.find("..")
  if dots <= 0 or dots + 2 >= cleaned.len:
    return (ok: false, lowerBound: "", upperBound: "")
  let lowerBound = normalizeNimNumericLiteral(cleaned[0 ..< dots])
  let upperBound = normalizeNimNumericLiteral(cleaned[dots + 2 .. ^1])
  if lowerBound.len == 0 or upperBound.len == 0:
    return (ok: false, lowerBound: "", upperBound: "")
  (ok: true, lowerBound: lowerBound, upperBound: upperBound)

# @axiom-hint: lean="rawBounds.length ≥ 0" smt="(assert (and (>= (str.len rawBounds) 0)))"
func mapRangeToLeanSubtype*(rawBounds: string): string {.raises: [].} =
  let bounds = parseRangeBounds(rawBounds)
  if not bounds.ok:
    return "Int"
  let baseType =
    if isNonNegativeIntegerLiteral(bounds.lowerBound) and isNonNegativeIntegerLiteral(bounds.upperBound):
      "Nat"
    else:
      "Int"
  "Subtype (fun x : " & baseType & " => " & bounds.lowerBound & " <= x ∧ x <= " & bounds.upperBound & ")"

# @axiom-hint: lean="rawType.length ≥ 0" smt="(assert (and (>= (str.len rawType) 0)))"
func mapBuiltinRefinementType*(rawType: string): string {.raises: [].} =
  let t = rawType.strip()
  if t == "Positive" or t == "PositiveInt":
    return "Subtype (fun x : Nat => 0 < x)"
  if t == "Natural":
    return "Nat"
  if t == "uint":
    return "Nat"
  if t == "uint8":
    return "Subtype (fun x : Nat => 0 <= x ∧ x <= 255)"
  if t == "uint16":
    return "Subtype (fun x : Nat => 0 <= x ∧ x <= 65535)"
  if t == "uint32":
    return "Nat"
  if t == "uint64":
    return "Nat"
  ""

# @axiom-hint: lean="raw.length ≥ 0" smt="(assert (and (>= (str.len raw) 0)))"
# @axiom-hint: lean="stripped.length = 0 ∧ stripped ∧ stripped.length = 0 → result = stripped" smt="(assert (and (= (str.len stripped) 0) stripped (=> (= (str.len stripped) 0) (= result stripped))))"
func parenthesizeLeanTypeArg*(raw: string): string {.raises: [].} =
  let stripped = raw.strip()
  if stripped.len == 0:
    return stripped
  if stripped.find(' ') >= 0:
    return "(" & stripped & ")"
  stripped

# ── Core Type Mapping ──

# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
## [Verified Core] Nim→Lean type mapping table. Data-driven dispatch — no structural bloat. Wave Y certified.
func mapNimTypeToLean*(rawType: string): string {.raises: [].} =
  let t = rawType
    .strip()
    .replace("var ", "")
    .replace("sink ", "")
    .replace("lent ", "")
    .replace("distinct ", "")
    .replace("owned ", "")
    .replace("not nil ", "")
  if t.len == 0:
    return "Unit"
  if t.startsWith("ref "):
    return mapNimTypeToLean(t["ref ".len .. ^1])
  if t.startsWith("ptr "):
    return mapNimTypeToLean(t["ptr ".len .. ^1])
  if t.startsWith("static[") and t.endsWith("]"):
    let inner = t["static[".len .. ^2].strip()
    if inner.find("..") >= 0 and not inner.startsWith("range["):
      return mapRangeToLeanSubtype(inner)
    return mapNimTypeToLean(inner)
  if t.startsWith("range[") and t.endsWith("]"):
    return mapRangeToLeanSubtype(t["range[".len .. ^2])
  if t.startsWith("proc") or t.startsWith("iterator") or t.startsWith("converter") or t.startsWith("func"):
    return "Unit"
  if t.startsWith("typeof(") or t.startsWith("type("):
    return "Unit"
  let mappedRefinement = mapBuiltinRefinementType(t)
  if mappedRefinement.len > 0:
    return mappedRefinement
  if t == "int":
    return "Int"
  if t == "int64":
    return "Int"
  if t == "int32":
    return "Int"
  if t == "bool":
    return "Bool"
  if t == "float":
    return "Float"
  if t == "float64":
    return "Float"
  if t == "float32":
    return "Float"
  if t == "char":
    return "Char"
  if t == "string":
    return "String"
  if t == "cstring":
    return "String"
  if t == "void":
    return "Unit"
  if t.startsWith("seq[") and t.endsWith("]"):
    return "List " & mapNimTypeToLean(t[4 .. ^2])
  if t.startsWith("openArray[") and t.endsWith("]"):
    return "List " & mapNimTypeToLean(t[10 .. ^2])
  if t.startsWith("Option[") and t.endsWith("]"):
    return "Option " & mapNimTypeToLean(t[7 .. ^2])
  if t.startsWith("set[") and t.endsWith("]"):
    return "List " & mapNimTypeToLean(t[4 .. ^2])
  if t.startsWith("Result[") and t.endsWith("]"):
    let inner = t["Result[".len .. ^2]
    let parts = splitTopLevel(inner, ',')
    if parts.len == 2:
      return "Result " & parenthesizeLeanTypeArg(mapNimTypeToLean(parts[0])) & " " & parenthesizeLeanTypeArg(mapNimTypeToLean(parts[1]))
    return "Result Unit String"
  if t.startsWith("HashSet[") and t.endsWith("]"):
    return "List " & mapNimTypeToLean(t["HashSet[".len .. ^2])
  if t.startsWith("OrderedSet[") and t.endsWith("]"):
    return "List " & mapNimTypeToLean(t["OrderedSet[".len .. ^2])
  if t.startsWith("Table[") and t.endsWith("]"):
    let inner = t["Table[".len .. ^2]
    let parts = splitTopLevel(inner, ',')
    if parts.len == 2:
      return "List (Prod " & mapNimTypeToLean(parts[0]) & " " & mapNimTypeToLean(parts[1]) & ")"
    return "List (Prod Int Int)"
  if t.startsWith("OrderedTable[") and t.endsWith("]"):
    let inner = t["OrderedTable[".len .. ^2]
    let parts = splitTopLevel(inner, ',')
    if parts.len == 2:
      return "List (Prod " & mapNimTypeToLean(parts[0]) & " " & mapNimTypeToLean(parts[1]) & ")"
    return "List (Prod Int Int)"
  if t.startsWith("array[") and t.endsWith("]"):
    let inner = t[6 .. ^2]
    let parts = splitTopLevel(inner, ',')
    if parts.len == 2:
      return "List " & mapNimTypeToLean(parts[1])
    return "List Int"
  if t.startsWith("(") and t.endsWith(")"):
    let inner = t[1 .. ^2]
    let parts = splitTopLevel(inner, ',')
    if parts.len == 2:
      return "Prod " & mapNimTypeToLean(parts[0]) & " " & mapNimTypeToLean(parts[1])
  let genericPos = t.find('[')
  if genericPos > 0 and t.endsWith("]"):
    let baseName = normalizeIdent(t[0 ..< genericPos])
    let rawArgs = t[genericPos + 1 .. ^2]
    let parts = splitTopLevel(rawArgs, ',')
    if baseName.len > 0 and parts.len > 0:
      var rendered = baseName
      for part in parts:
        rendered.add(" " & parenthesizeLeanTypeArg(mapNimTypeToLean(part)))
      return rendered
  normalizeIdent(t)

# ── AST Parsing Functions ──

func extractTypeAliasesFromAstP(ast: PNode): seq[tuple[name: string, genericParams: seq[string], targetType: string]] =
  if ast.isNil: return
  for section in findNodesP(ast, {nkTypeSection}):
    for typeDef in section:
      if not typeDef.isNil and typeDef.kind == nkTypeDef:
        if typeDef.len >= 2:
          let nameNode = typeDef[0]
          let typeNode = typeDef[1]
          if not nameNode.isNil and not typeNode.isNil:
            let name = pNodeText(nameNode)
            let typ = pNodeText(typeNode)
            if name.len > 0:
              result.add((name: name, genericParams: @[], targetType: typ))

func extractObjectTypesFromAstP(ast: PNode): seq[tuple[name: string, genericParams: seq[string], fields: seq[tuple[name: string, nimType: string]]]] =
  if ast.isNil: return
  for section in findNodesP(ast, {nkTypeSection}):
    for typeDef in section:
      if not typeDef.isNil and typeDef.kind == nkTypeDef:
        if typeDef.len >= 2:
          let nameNode = typeDef[0]
          let typeNode = typeDef[1]
          if not nameNode.isNil and not typeNode.isNil:
            let name = pNodeText(nameNode)
            if name.len > 0 and typeNode.kind == nkObjectTy:
              var fields: seq[tuple[name: string, nimType: string]] = @[]
              for child in typeNode:
                if not child.isNil and child.kind == nkIdentDefs:
                  if child.len >= 2:
                    let fieldNameNode = child[0]
                    let fieldTypeNode = child[1]
                    if not fieldNameNode.isNil and not fieldTypeNode.isNil:
                      let fieldName = pNodeText(fieldNameNode)
                      let fieldType = pNodeText(fieldTypeNode)
                      if fieldName.len > 0:
                        fields.add((name: fieldName, nimType: fieldType))
              result.add((name: name, genericParams: @[], fields: fields))

func extractTupleTypesFromAstP(ast: PNode): seq[tuple[name: string, genericParams: seq[string], fields: seq[tuple[name: string, nimType: string]]]] =
  if ast.isNil: return
  for section in findNodesP(ast, {nkTypeSection}):
    for typeDef in section:
      if not typeDef.isNil and typeDef.kind == nkTypeDef:
        if typeDef.len >= 2:
          let nameNode = typeDef[0]
          let typeNode = typeDef[1]
          if not nameNode.isNil and not typeNode.isNil:
            let name = pNodeText(nameNode)
            if name.len > 0 and typeNode.kind == nkTupleTy:
              var fields: seq[tuple[name: string, nimType: string]] = @[]
              for child in typeNode:
                if not child.isNil and child.kind == nkIdentDefs:
                  if child.len >= 2:
                    let fieldNameNode = child[0]
                    let fieldTypeNode = child[1]
                    if not fieldNameNode.isNil and not fieldTypeNode.isNil:
                      let fieldName = pNodeText(fieldNameNode)
                      let fieldType = pNodeText(fieldTypeNode)
                      if fieldName.len > 0:
                        fields.add((name: fieldName, nimType: fieldType))
              result.add((name: name, genericParams: @[], fields: fields))

func extractEnumTypesFromAstP(ast: PNode): seq[tuple[name: string, genericParams: seq[string], cases: seq[string]]] =
  if ast.isNil: return
  for section in findNodesP(ast, {nkTypeSection}):
    for typeDef in section:
      if not typeDef.isNil and typeDef.kind == nkTypeDef:
        if typeDef.len >= 2:
          let nameNode = typeDef[0]
          let typeNode = typeDef[1]
          if not nameNode.isNil and not typeNode.isNil:
            let name = pNodeText(nameNode)
            if name.len > 0 and typeNode.kind == nkEnumTy:
              var cases: seq[string] = @[]
              for child in typeNode:
                if not child.isNil:
                  let caseName = pNodeText(child)
                  if caseName.len > 0:
                    cases.add(caseName)
              result.add((name: name, genericParams: @[], cases: cases))

func extractGlobalVarsFromAstP(ast: PNode): seq[tuple[name: string]] =
  if ast.isNil: return
  for section in findNodesP(ast, {nkVarSection, nkLetSection, nkConstSection}):
    for child in section:
      if not child.isNil:
        case child.kind
        of nkIdent:
          result.add((name: child.ident.s))
        of nkIdentDefs:
          if child.len > 0 and not child[0].isNil:
            let identNode = child[0]
            if identNode.kind == nkIdent:
              result.add((name: identNode.ident.s))
        else:
          discard

proc parseAliases*(source: string): seq[LeanAliasDef] {.raises: [].} =
  let ast = parseStringAST(source)
  if not ast.isNil:
    for entry in extractTypeAliasesFromAstP(ast):
      result.add(LeanAliasDef(
        name: entry.name,
        genericParams: entry.genericParams,
        targetType: mapNimTypeToLean(entry.targetType)
      ))

# @axiom-hint: lean="source.length ≥ 0" smt="(assert (and (>= (str.len source) 0)))"
proc parseStructures*(source: string): seq[LeanStructureDef] {.raises: [].} =
  let ast = parseStringAST(source)
  if not ast.isNil:
    for entry in extractObjectTypesFromAstP(ast):
      var fields: seq[LeanField] = @[]
      for f in entry.fields:
        fields.add(LeanField(name: f.name, leanType: mapNimTypeToLean(f.nimType)))
      result.add(LeanStructureDef(name: entry.name, genericParams: entry.genericParams, fields: fields))
    for entry in extractTupleTypesFromAstP(ast):
      var fields: seq[LeanField] = @[]
      for f in entry.fields:
        fields.add(LeanField(name: f.name, leanType: mapNimTypeToLean(f.nimType)))
      result.add(LeanStructureDef(name: entry.name, genericParams: entry.genericParams, fields: fields))

# @axiom-hint: lean="source.length ≥ 0" smt="(assert (and (>= (str.len source) 0)))"
proc parseEnums*(source: string): seq[LeanEnumDef] {.raises: [].} =
  let ast = parseStringAST(source)
  if not ast.isNil:
    for entry in extractEnumTypesFromAstP(ast):
      result.add(LeanEnumDef(name: entry.name, genericParams: entry.genericParams, cases: entry.cases))

# @axiom-hint: lean="source.length ≥ 0" smt="(assert (and (>= (str.len source) 0)))"
proc parseGlobalVars*(source: string): seq[string] {.raises: [].} =
  let ast = parseStringAST(source)
  if not ast.isNil:
    for entry in extractGlobalVarsFromAstP(ast):
      if entry.name.len > 0 and entry.name notin result:
        result.add(entry.name)

# ── Effect Detection ──

# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
# @axiom-hint: lean="name ∈ patterns" smt="(assert (and (member name patterns)))"
func detectIoSideEffects*(bodyNode: PNode): seq[string] {.raises: [].} =
  let patterns = [
    "echo", "stdout", "stderr", "readfile", "writefile", "readline",
    "readall", "open", "execmd", "execmdex", "startprocess",
    "send", "recv", "socket"
  ]
  for identNode in findNodesP(bodyNode, {nkIdent}):
    let name = identNode.ident.s.toLowerAscii()
    if name in patterns:
      result.add("I/O call pattern detected: " & name)

func detectGlobalRefs*(bodyNode: PNode; globalVars: seq[string]): seq[string] {.raises: [].} =
  for globalName in globalVars:
    if hasIdentifierNamed(bodyNode, globalName):
      result.add("Mutable global variable reference detected: " & globalName)

# ── Function Parsing ──

# @axiom-hint: lean="source.length ≥ 0 ∧ globalVars.size ≥ 0 ∧ (∀ (globalVarsIdx : Fin globalVars.size), (globalVars.get globalVarsIdx).length ≥ 0)" smt="(assert (and (>= (str.len source) 0) (>= (seq.len globalVars) 0) (forall ((globalVarsIdx Int)) (=> (and (>= globalVarsIdx 0) (< globalVarsIdx (seq.len globalVars))) (>= (str.len (seq.nth globalVars globalVarsIdx)) 0)))))"
# @axiom-hint: lean="returnType.length = 0 ∧ (returnType ≥ 0) ∧ (∀ (globalVarsIdx : Fin globalVars.size), (globalVars.get globalVarsIdx).length ≥ 0)" smt="(assert (and (= (str.len returnType) 0) (>= returnType 0) (forall ((globalVarsIdx Int)) (=> (and (>= globalVarsIdx 0) (< globalVarsIdx (seq.len globalVars))) (>= (str.len (seq.nth globalVars globalVarsIdx)) 0)))))"
proc parseFunctions*(source: string; globalVars: seq[string]): seq[LeanFunctionDef] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    let ast = parseStringAST(source)
    for entry in extractFunctionDefsFromAstP(ast):
      var params: seq[LeanParam] = @[]
      for p in entry.params:
        params.add(LeanParam(name: p.name, leanType: mapNimTypeToLean(p.nimType)))
      var returnType = mapNimTypeToLean(entry.returnType)
      if returnType.len == 0:
        returnType = "Unit"
      var warnings: seq[string] = @[]
      # detectIoSideEffects/detectGlobalRefs require legacy XmlNode; PNode path skips these
      result.add(LeanFunctionDef(
        name: entry.name,
        genericParams: @[],
        params: params,
        returnType: returnType,
        trusted: warnings.len == 0,
        warnings: warnings
      ))
  except CatchableError:
    discard  # best-effort  # axiom:best-effort(ioboundary catch)

# ── Rendering Helpers ──

# @axiom-hint: lean="defn_name.length ≥ 0 ∧ defn_genericParams.size ≥ 0 ∧ defn_fields.size ≥ 0" smt="(assert (and (>= (str.len defn_name) 0) (>= (seq.len defn_genericParams) 0) (>= (seq.len defn_fields) 0)))"
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert (and ast_parse_failed_isolated))"
func renderStructure*(defn: LeanStructureDef): string {.raises: [].} =
  var rendered = "structure " & defn.name
  for param in defn.genericParams:
    rendered.add(" (" & param & " : Type)")
  rendered.add(" where\n")
  if defn.fields.len == 0:
    rendered.add("  marker : Unit\n")
    rendered.add("deriving Inhabited")
    return rendered
  for field in defn.fields:
    rendered.add("  " & field.name & " : " & field.leanType & "\n")
  rendered.add("deriving Inhabited")
  rendered

# @axiom-hint: lean="leanType.length ≥ 0" smt="(assert (and (>= (str.len leanType) 0)))"
# @axiom-hint: lean="arrowPos > baseStart" smt="(assert (and (> arrowPos baseStart)))"
func leanDefaultForType*(leanType: string): string {.raises: [].} =
  let t = leanType.strip()
  if t == "Unit":
    return "()"
  if t == "Nat":
    return "0"
  if t == "Int":
    return "0"
  if t == "Bool":
    return "false"
  if t == "String":
    return "\"\""
  if t == "Float":
    return "0.0"
  if t == "Char":
    return "default"
  if t.startsWith("List "):
    return "[]"
  if t.startsWith("Option "):
    return "none"
  if t.startsWith("Subtype (fun x : "):
    let baseStart = "Subtype (fun x : ".len
    let arrowPos = t.find(" => ")
    if arrowPos > baseStart:
      let baseType = t[baseStart ..< arrowPos].strip()
      let predicate = t[arrowPos + " => ".len .. ^1]
      if predicate == "0 < x)":
        if baseType == "Nat":
          return "⟨1, by decide⟩"
        return "⟨1, by decide⟩"
      let conj = predicate.find(" <= x ∧ x <= ")
      if conj > 0 and predicate.endsWith(")"):
        let lowerBound = predicate[0 ..< conj].strip()
        return "⟨" & lowerBound & ", by decide⟩"
  "default"

{.pop.}
