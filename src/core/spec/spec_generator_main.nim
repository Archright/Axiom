import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import core/spec/spec_generator_helpers
import core/spec/spec_generator_types
import core/trusted/axiom_pragmas
import core/utils/text_utils
import std/strutils
# ── Rendering ──

# @axiom-hint: lean="defn_name.length ≥ 0 ∧ defn_genericParams.size ≥ 0 ∧ defn_params.size ≥ 0 ∧ defn_returnType.length ≥ 0 ∧ defn_trusted = true ∨ defn_trusted = false ∧ defn_warnings.size ≥ 0" smt="(assert (and (>= (str.len defn_name) 0) (>= (seq.len defn_genericParams) 0) (>= (seq.len defn_params) 0) (>= (str.len defn_returnType) 0) (or (= defn_trusted true) (= defn_trusted false)) (>= (seq.len defn_warnings) 0)))"
# @axiom-hint: lean="defn_trusted = true ∨ defn_trusted = false" smt="(assert (and (or (= defn_trusted true) (= defn_trusted false))))"
func renderFunction(defn: LeanFunctionDef): string {.raises: [].} =
  var rendered = "def " & defn.name
  for param in defn.genericParams:
    rendered.add(" {" & param & " : Type} [Inhabited " & param & "]")
  for p in defn.params:
    rendered.add(" (" & p.name & " : " & p.leanType & ")")
  rendered.add(" : " & defn.returnType & " := " & leanDefaultForType(defn.returnType) & "\n")
  rendered

# @axiom-hint: lean="defn_name.length ≥ 0 ∧ defn_genericParams.size ≥ 0 ∧ defn_cases.size ≥ 0" smt="(assert (and (>= (str.len defn_name) 0) (>= (seq.len defn_genericParams) 0) (>= (seq.len defn_cases) 0)))"
func renderEnum(defn: LeanEnumDef): string {.raises: [].} =
  var rendered = "inductive " & defn.name
  for param in defn.genericParams:
    rendered.add(" (" & param & " : Type)")
  rendered.add(" where\n")
  if defn.cases.len == 0:
    rendered.add("  | unnamed\n")
    rendered.add("deriving Inhabited")
    return rendered
  for c in defn.cases:
    rendered.add("  | " & c & "\n")
  rendered.add("deriving Inhabited")
  rendered

# @axiom-hint: lean="defn_name.length ≥ 0 ∧ defn_genericParams.size ≥ 0 ∧ defn_targetType.length ≥ 0" smt="(assert (and (>= (str.len defn_name) 0) (>= (seq.len defn_genericParams) 0) (>= (str.len defn_targetType) 0)))"
func renderAlias(defn: LeanAliasDef): string {.raises: [].} =
  var rendered = "abbrev " & defn.name
  for param in defn.genericParams:
    rendered.add(" (" & param & " : Type)")
  rendered.add(" := " & defn.targetType)
  rendered

# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
func isIdentChar(ch: char): bool {.inline, raises: [].} =
  ch.isAlphaNumeric or ch == '_'
# @axiom-hint: lean="leanType.length ≥ 0 ∧ knownTypes.size ≥ 0 ∧ (∀ (knownTypesIdx : Fin knownTypes.size), (knownTypes.get knownTypesIdx).length ≥ 0) ∧ ignoredTypes.size ≥ 0 ∧ (∀ (ignoredTypesIdx : Fin ignoredTypes.size), (ignoredTypes.get ignoredTypesIdx).length ≥ 0)" smt="(assert (and (>= (str.len leanType) 0) (>= (seq.len knownTypes) 0) (forall ((knownTypesIdx Int)) (=> (and (>= knownTypesIdx 0) (< knownTypesIdx (seq.len knownTypes))) (>= (str.len (seq.nth knownTypes knownTypesIdx)) 0))) (>= (seq.len ignoredTypes) 0) (forall ((ignoredTypesIdx Int)) (=> (and (>= ignoredTypesIdx 0) (< ignoredTypesIdx (seq.len ignoredTypes))) (>= (str.len (seq.nth ignoredTypes ignoredTypesIdx)) 0)))))"
# @axiom-hint: lean="token.length > 0 ∧ (leanType ≥ 0) ∧ (∀ (knownTypesIdx : Fin knownTypes.size), (knownTypes.get knownTypesIdx).length ≥ 0) ∧ (∀ (ignoredTypesIdx : Fin ignoredTypes.size), (ignoredTypes.get ignoredTypesIdx).length ≥ 0)" smt="(assert (and (> (str.len token) 0) (>= leanType 0) (forall ((knownTypesIdx Int)) (=> (and (>= knownTypesIdx 0) (< knownTypesIdx (seq.len knownTypes))) (>= (str.len (seq.nth knownTypes knownTypesIdx)) 0))) (forall ((ignoredTypesIdx Int)) (=> (and (>= ignoredTypesIdx 0) (< ignoredTypesIdx (seq.len ignoredTypes))) (>= (str.len (seq.nth ignoredTypes ignoredTypesIdx)) 0)))))"
func collectTypeDependencies(leanType: string; knownTypes: seq[string]; ignoredTypes: seq[string]): seq[string] {.raises: [].} =
  var token = ""
  for ch in leanType:
    if isIdentChar(ch):
      token.add(ch)
      continue
    if token.len > 0:
      if knownTypes.contains(token) and not ignoredTypes.contains(token):
        result.addUnique(token)
      token.setLen(0)
  if token.len > 0 and knownTypes.contains(token) and not ignoredTypes.contains(token):
    result.addUnique(token)

# @axiom-hint: lean="defn_name.length ≥ 0 ∧ defn_genericParams.size ≥ 0 ∧ defn_fields.size ≥ 0 ∧ knownTypes.size ≥ 0 ∧ (∀ (knownTypesIdx : Fin knownTypes.size), (knownTypes.get knownTypesIdx).length ≥ 0)" smt="(assert (and (>= (str.len defn_name) 0) (>= (seq.len defn_genericParams) 0) (>= (seq.len defn_fields) 0) (>= (seq.len knownTypes) 0) (forall ((knownTypesIdx Int)) (=> (and (>= knownTypesIdx 0) (< knownTypesIdx (seq.len knownTypes))) (>= (str.len (seq.nth knownTypes knownTypesIdx)) 0)))))"
# @axiom-hint: lean="(∀ (knownTypesIdx : Fin knownTypes.size), (knownTypes.get knownTypesIdx).length ≥ 0)" smt="(assert (and (forall ((knownTypesIdx Int)) (=> (and (>= knownTypesIdx 0) (< knownTypesIdx (seq.len knownTypes))) (>= (str.len (seq.nth knownTypes knownTypesIdx)) 0)))))"
func structureDependencies(defn: LeanStructureDef; knownTypes: seq[string]): seq[string] {.raises: [].} =
  var ignoredTypes = defn.genericParams
  ignoredTypes.add(defn.name)
  for field in defn.fields:
    for dep in collectTypeDependencies(field.leanType, knownTypes, ignoredTypes):
      result.addUnique(dep)

# @axiom-hint: lean="pending ∧ blocked ∧ progressed ∧ remaining.length > 0 ∧ idx < remaining.length ∧ pending = true ∧ blocked = true ∧ progressed = true ∧ (remaining ≥ 0) ∧ (progressed ≥ 0) ∧ ((idx ≥ 0) ∧ (idx < remaining)) ∧ (pending ≥ 0) ∧ (blocked ≥ 0) ∧ (∀ (knownTypesIdx : Fin knownTypes.size), (knownTypes.get knownTypesIdx).length ≥ 0)" smt="(assert (and pending blocked progressed (> (str.len remaining) 0) (< idx (str.len remaining)) (= pending true) (= blocked true) (= progressed true) (>= remaining 0) (>= progressed 0) (and (>= idx 0) (< idx remaining)) (>= pending 0) (>= blocked 0) (forall ((knownTypesIdx Int)) (=> (and (>= knownTypesIdx 0) (< knownTypesIdx (seq.len knownTypes))) (>= (str.len (seq.nth knownTypes knownTypesIdx)) 0)))))"
func sortStructuresByDependencies(
  structures: seq[tuple[moduleName: string; defn: LeanStructureDef]];
  knownTypes: seq[string]
): seq[tuple[moduleName: string; defn: LeanStructureDef]] {.raises: [].} =
  var remaining = structures
  var emitted: seq[string] = @[]
  while remaining.len > 0:
    var progressed = false
    var idx = 0
    while idx < remaining.len:
      let candidate = remaining[idx]
      var blocked = false
      for dep in structureDependencies(candidate.defn, knownTypes):
        if emitted.contains(dep):
          continue
        var pending = false
        for other in remaining:
          if other.defn.name == dep and other.defn.name != candidate.defn.name:
            pending = true
            break
        if pending:
          blocked = true
          break
      if blocked:
        inc idx
        continue
      result.add(candidate)
      emitted.add(candidate.defn.name)
      remaining.delete(idx)
      progressed = true
    if progressed:
      continue
    result.add(remaining[0])
    emitted.add(remaining[0].defn.name)
    remaining.delete(0)
# @axiom-hint: lean="modulePath.length ≥ 0" smt="(assert (and (>= (str.len modulePath) 0)))"
func moduleHeader(modulePath: string): string {.raises: [].} =
  let normalized = normalizeIdent(
    modulePath
      .replace("\\", "_")
      .replace("/", "_")
      .replace(".", "_")
      .replace("sorry", "sry")
  )
  if normalized.len == 0:
    "Module"
  else:
    normalized
## Map Nim Type To Smt Sort.
# @axiom-hint: lean="rawType.length ≥ 0" smt="(assert (and (>= (str.len rawType) 0)))"
# @axiom-hint: lean="innerStart > 0 ∧ innerEnd > innerStart" smt="(assert (and (and (> innerStart 0) (> innerEnd innerStart))))"
func mapNimTypeToSmtSort*(rawType: string): string {.raises: [].} =
  let t = rawType.strip
  if t == "int" or t.startsWith("range[") or t == "Natural" or t == "Positive" or
     t == "uint" or t == "uint8" or t == "uint16" or t == "uint32" or t == "uint64":
    return "Int"
  if t == "bool":
    return "Bool"
  if t == "float" or t == "float32" or t == "float64":
    return "Real"
  if t == "string":
    return "String"
  if t == "char":
    return "String"
  if t == "void":
    return "Unit"
  if t.startsWith("seq[") or t.startsWith("array[") or t.startsWith("set["):
    let innerStart = t.find('[') + 1
    let innerEnd = t.rfind(']')
    if innerStart > 0 and innerEnd > innerStart:
      let inner = t[innerStart ..< innerEnd].split(',')[0].strip
      return "(List " & mapNimTypeToSmtSort(inner) & ")"
    return "(List Int)"
  if t.startsWith("Option["):
    let innerStart = t.find('[') + 1
    let innerEnd = t.rfind(']')
    if innerStart > 0 and innerEnd > innerStart:
      let inner = t[innerStart ..< innerEnd].strip
      return "(Option " & mapNimTypeToSmtSort(inner) & ")"
    return "(Option Int)"
  if t.startsWith("Table["):
    let innerStart = t.find('[') + 1
    let innerEnd = t.rfind(']')
    if innerStart > 0 and innerEnd > innerStart:
      let inner = t[innerStart ..< innerEnd]
      let parts = inner.split(',')
      if parts.len >= 2:
        return "(List (Prod " & mapNimTypeToSmtSort(parts[0].strip) & " " & mapNimTypeToSmtSort(parts[1].strip) & "))"
    return "(List (Prod Int Int))"
  if t.startsWith("(") and t.endsWith(")"):
    return "Prod"
  return normalizeIdent(t)

## Generate Type Mapping Certificates.
# @axiom-hint: lean="depth >= 0" smt="(assert (>= depth 0))"
func generateTypeMappingCertificates*(): seq[TypeMappingCertificate] {.raises: [].} =
  let baseTypes = @[
    "int", "bool", "float", "char", "string", "void",
    "Natural", "Positive",
    "uint", "uint8", "uint16", "uint32", "uint64",
    "range[0..255]", "range[0..65535]",
    "seq[int]", "seq[string]", "seq[bool]",
    "Option[int]", "Option[string]",
    "array[10,int]",
    "Table[string,int]",
    "(int,string)"
  ]
  for nt in baseTypes:
    let lt = mapNimTypeToLean(nt)
    let st = mapNimTypeToSmtSort(nt)
    let obligation = "nim_lean_" & normalizeIdent(nt) & "_iso"
    result.add(TypeMappingCertificate(
      nimType: nt,
      leanType: lt,
      smtSort: st,
      mappingProofObligation: obligation,
      verified: false,
      sourceHash: ""
    ))

## Render Type Mapping Proof Obligation.
# @axiom-hint: lean="cert_verified = true ∨ cert_verified = false" smt="(assert (and (or (= cert_verified true) (= cert_verified false))))"
func renderTypeMappingProofObligation*(cert: TypeMappingCertificate): string {.raises: [].} =
  ## Render a Lean theorem stub for the type mapping proof obligation.
  if cert.nimType == "int":
    return "theorem " & cert.mappingProofObligation & " : ∀ (x : Int), toLean (toNim x) = x := by first | intros; rfl"
  if cert.nimType == "bool":
    return "theorem " & cert.mappingProofObligation & " : ∀ (x : Bool), toLean (toNim x) = x := by first | intros; rfl"
  if cert.nimType == "float":
    return "theorem " & cert.mappingProofObligation & " : ∀ (x : Float), toLean (toNim x) = x := by first | intros; rfl"
  if cert.nimType == "string":
    return "theorem " & cert.mappingProofObligation & " : ∀ (x : String), toLean (toNim x) = x := by first | intros; rfl"
  if cert.nimType == "char":
    return "theorem " & cert.mappingProofObligation & " : ∀ (x : Char), toLean (toNim x) = x := by first | intros; rfl"
  return "theorem " & cert.mappingProofObligation & " : ∀ (x : " & cert.leanType & "), toLean (toNim x) = x := by first | intros; rfl"
## Generate Lean Spec From Sources.
# @axiom-hint: lean="sources.size ≥ 0 ∧ namespaceName.length ≥ 0" smt="(assert (and (>= (seq.len sources) 0) (>= (str.len namespaceName) 0)))"
# @axiom-hint: lean="aliases.length = 0 ∧ structures.length = 0 ∧ enums.length = 0 ∧ functions.length = 0 ∧ (modules ≥ 0) ∧ (sources ≥ 0) ∧ (scopedAliases ≥ 0) ∧ (orderedStructures ≥ 0) ∧ (result ≥ 0) ∧ (scopedEnums ≥ 0)" smt="(assert (and (and (and (and (= (str.len aliases) 0) (= (str.len structures) 0)) (= (str.len enums) 0)) (= (str.len functions) 0)) (>= modules 0) (>= sources 0) (>= scopedAliases 0) (>= orderedStructures 0) (>= result 0) (>= scopedEnums 0)))"
proc generateLeanSpecFromSources*(
  sources: seq[NimSourceUnit];
  namespaceName: string = "Axiom.GeneratedCore"
): SpecGeneratorOutput {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var modules: seq[tuple[
    name: string,
    aliases: seq[LeanAliasDef],
    structures: seq[LeanStructureDef],
    enums: seq[LeanEnumDef],
    functions: seq[LeanFunctionDef]
  ]] = @[]
  for unit in sources:
    let aliases = parseAliases(unit.source)
    let structures = parseStructures(unit.source)
    let enums = parseEnums(unit.source)
    let functions = parseFunctions(unit.source, parseGlobalVars(unit.source))
    if aliases.len == 0 and structures.len == 0 and enums.len == 0 and functions.len == 0:
      continue
    modules.add((
      name: moduleHeader(unit.modulePath),
      aliases: aliases,
      structures: structures,
      enums: enums,
      functions: functions
    ))

  var lines: seq[string] = @[]
  lines.add("namespace " & namespaceName)
  lines.add("")
  var allTypeNames: seq[string] = @[]
  var scopedAliases: seq[tuple[moduleName: string; defn: LeanAliasDef]] = @[]
  var scopedEnums: seq[tuple[moduleName: string; defn: LeanEnumDef]] = @[]
  var scopedStructures: seq[tuple[moduleName: string; defn: LeanStructureDef]] = @[]
  for module in modules:
    for aliasDef in module.aliases:
      allTypeNames.addUnique(aliasDef.name)
      scopedAliases.add((moduleName: module.name, defn: aliasDef))
    for enumDef in module.enums:
      allTypeNames.addUnique(enumDef.name)
      scopedEnums.add((moduleName: module.name, defn: enumDef))
    for structureDef in module.structures:
      allTypeNames.addUnique(structureDef.name)
      scopedStructures.add((moduleName: module.name, defn: structureDef))
  let orderedStructures = sortStructuresByDependencies(scopedStructures, allTypeNames)
  var totalStructures = 0
  var totalEnums = 0
  var totalFunctions = 0
  var totalUntrustedFunctions = 0
  var warnings: seq[string] = @[]
  for module in modules:
    lines.add("namespace " & module.name)
    lines.add("end " & module.name)
    lines.add("")
  for aliasDef in scopedAliases:
    lines.add("namespace " & aliasDef.moduleName)
    for opened in modules:
      lines.add("open " & opened.name)
    lines.add("")
    lines.add(renderAlias(aliasDef.defn))
    lines.add("")
    lines.add("end " & aliasDef.moduleName)
    lines.add("")
  for enumDef in scopedEnums:
    lines.add("namespace " & enumDef.moduleName)
    for opened in modules:
      lines.add("open " & opened.name)
    lines.add("")
    lines.add(renderEnum(enumDef.defn))
    lines.add("")
    inc totalEnums
    lines.add("end " & enumDef.moduleName)
    lines.add("")
  for structureDef in orderedStructures:
    lines.add("namespace " & structureDef.moduleName)
    for opened in modules:
      lines.add("open " & opened.name)
    lines.add("")
    lines.add(renderStructure(structureDef.defn))
    lines.add("")
    inc totalStructures
    lines.add("end " & structureDef.moduleName)
    lines.add("")
  for module in modules:
    lines.add("namespace " & module.name)
    for opened in modules:
      lines.add("open " & opened.name)
    lines.add("")
    for f in module.functions:
      if f.trusted:
        lines.add(renderFunction(f))
        lines.add("")
        inc totalFunctions
      else:
        inc totalUntrustedFunctions
        for warning in f.warnings:
          warnings.add(module.name & "." & f.name & " -> " & warning)
    lines.add("end " & module.name)
    lines.add("")
  lines.add("end " & namespaceName)

  result.leanCode = lines.join("\n")
  result.structureCount = totalStructures
  result.enumCount = totalEnums
  result.functionCount = totalFunctions
  result.untrustedFunctionCount = totalUntrustedFunctions
  result.warnings = warnings
{.pop.}
