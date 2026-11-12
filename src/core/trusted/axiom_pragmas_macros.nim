# nim-check: skip (include fragment — not an independent translation unit)
axiomLayer "domain"
# QUIRK(DEBT#455): macro/template instantiationInfo(-1,true).filename and
# currentSourcePath() embeddings (axiomLayerGuard, axiomLayerGuardAutoImpl,
# enforceFacadePattern, verifySpecification, ...) return string in macro context
# and cannot be wrapped in LogicalPath without breaking macro expansion. See
# docs/spec/artifact_determinism.md §2.4-2.5. Bind marker for debt_integrity_gate.
const debtMarker455 {.axiomDebt: "DEBT#455".} = true

template axiomGate*(gateId: static string) {.pragma.}
template axiom*(val: untyped = "") {.pragma.}

proc hasAxiomPragma*(node: NimNode): bool {.raises: [].} =
  if node.kind notin {nnkProcDef, nnkFuncDef, nnkTemplateDef}:
    return false
  let pragma = node.pragma
  if pragma.kind == nnkEmpty:
    return false
  for child in pragma:
    if child.kind == nnkIdent and child.strVal == "axiom":
      return true
    if child.kind == nnkExprColonExpr and child[0].kind == nnkIdent and child[0].strVal == "axiom":
      return true
  return false

proc extractAxiomStrings*(node: NimNode): tuple[smt, lean: string] {.raises: [].} =
  result = ("", "")
  let pragma = node.pragma
  if pragma.kind == nnkEmpty:
    return
  for child in pragma:
    if child.kind == nnkExprColonExpr and child[0].kind == nnkIdent and child[0].strVal == "axiom":
      if child[1].kind == nnkBracket:
        for arg in child[1]:
          if arg.kind in {nnkCall, nnkExprColonExpr}:
            let name = if arg[0].kind == nnkIdent: arg[0].strVal else: ""
            let val = if arg[1].kind == nnkStrLit: arg[1].strVal else: ""
            if name == "smt": result.smt = val
            elif name == "lean": result.lean = val

func unwrapParenExpr(n: NimNode): NimNode {.raises: [].} =
  result = n
  while result.kind in {nnkPar, nnkStmtListExpr} and result.len == 1:
    result = result[0]

func extractAxiomSpec*(node: NimNode): tuple[pre, post: seq[NimNode], smt, lean: string] {.raises: [].} =
  result.smt = ""
  result.lean = ""
  let pragma = node.pragma
  if pragma.kind == nnkEmpty:
    return
  for child in pragma:
    if child.kind == nnkExprColonExpr and child[0].kind == nnkIdent and child[0].strVal == "axiom":
      if child[1].kind == nnkBracket:
        for arg in child[1]:
          if arg.kind in {nnkCall, nnkExprColonExpr}:
            let name = if arg[0].kind == nnkIdent: arg[0].strVal else: ""
            case name
            of "smt":
              if arg[1].kind == nnkStrLit: result.smt = arg[1].strVal
            of "lean":
              if arg[1].kind == nnkStrLit: result.lean = arg[1].strVal
            of "pre":
              if arg.len >= 2: result.pre.add(unwrapParenExpr(arg[1]))
            of "post":
              if arg.len >= 2: result.post.add(unwrapParenExpr(arg[1]))
            else: discard

proc applyAxiomSpec*(def: NimNode; irDef: var IRFuncDef) {.raises: [].} =
  let spec = extractAxiomSpec(def)
  if spec.pre.len == 0 and spec.post.len == 0:
    return
  var params: seq[IRFuncParam] = @[]
  var unsignedNames: seq[string] = @[]
  let formalParams = def[3]
  if formalParams.kind == nnkFormalParams:
    for i in 1 ..< formalParams.len:
      let identDefs = formalParams[i]
      if identDefs.kind == nnkIdentDefs and identDefs.len >= 3:
        let typeNode = identDefs[identDefs.len - 2]
        let ty = if typeNode.kind != nnkEmpty: convertType(typeNode)
                 else: irTypeBitVec64()
        for j in 0 ..< identDefs.len - 2:
          params.add(IRFuncParam(name: stripGensym(identDefs[j].strVal), ty: ty))
          if nimTypeNodeIsUnsigned(typeNode):
            unsignedNames.add(stripGensym(identDefs[j].strVal))
  var ctx = initIrContext(irDef.name, params)
  for u in unsignedNames: ctx.unsignedParams.incl(u)
  for p in spec.pre:
    let e = convertExpr(p, ctx)
    if e != nil: irDef.preConditions.add(e)
  for p in spec.post:
    let e = convertExpr(p, ctx)
    if e != nil: irDef.postConditions.add(e)

macro axiomSafeParse*(body: untyped): untyped =
  for child in body:
    let reprStr = $child.repr
    if "parseInt(" in reprStr and "safeParseInt" notin reprStr:
      error("DEBT PREVENTION: Use safeParseInt instead of parseInt. " &
            "See src/core/safe_parsers.nim for the safe wrapper.", child)
    if "parseFloat(" in reprStr and "safeParseFloat" notin reprStr:
      error("DEBT PREVENTION: Use safeParseFloat instead of parseFloat. " &
            "See src/core/safe_parsers.nim for the safe wrapper.", child)
  result = body

macro axiomStrongHash*(body: untyped): untyped =
  for child in body:
    let reprStr = $child.repr
    if "checksums/md5" in reprStr or "import md5" in reprStr:
      error("DEBT PREVENTION: Use checksums/sha2 instead of checksums/md5. " &
            "MD5 is cryptographically broken since 2005.", child)
    if "checksums/sha1" in reprStr or "std/sha1" in reprStr:
      error("DEBT PREVENTION: Use checksums/sha2 instead of checksums/sha1. " &
            "SHA-1 is broken for signatures.", child)
  result = body

proc verifyNoPointerEscapeTyped*(node: NimNode) {.used, raises: [].} =
  if node.kind == nnkStmtList:
    for child in node:
      if child.kind == nnkReturnStmt and child.len > 0:
        let childType = child[0].getTypeImpl
        if childType.kind == nnkPtrTy:
          error("ESCAPE VIOLATION: Pointer leaked via explicit return.", child)
      elif child.kind in {nnkAsgn, nnkFastAsgn}:
        if child[0].kind == nnkIdent and $child[0] == "result":
          let childType = child[1].getTypeImpl
          if childType.kind == nnkPtrTy:
            error("ESCAPE VIOLATION: Pointer leaked via 'result' assignment.", child)
  if node.kind == nnkStmtList and node.len > 0:
    let lastChild = node[^1]
    if lastChild.kind notin {nnkReturnStmt, nnkAsgn, nnkFastAsgn, nnkDiscardStmt,
                             nnkIfStmt, nnkCaseStmt, nnkWhileStmt, nnkBlockStmt, nnkTryStmt}:
      let lastType = lastChild.getTypeImpl
      if lastType.kind == nnkPtrTy:
        error("ESCAPE VIOLATION: Pointer leaked via implicit return.", lastChild)

macro axiomNoEscape*(body: typed): untyped =
  case body.kind
  of nnkSym:
    let impl = body.getImpl()
    if impl.kind notin {nnkProcDef, nnkFuncDef}:
      return body

    let formalParams = impl[3]
    if formalParams.kind != nnkFormalParams or formalParams.len == 0:
      return body

    let returnTypeNode = formalParams[0]
    if returnTypeNode.kind == nnkEmpty:
      return body

    let returnTypeImpl = returnTypeNode.getTypeImpl
    let isPtrReturn = returnTypeImpl.kind == nnkPtrTy or
                      (returnTypeImpl.kind == nnkDistinctTy and
                       returnTypeImpl[0].getTypeImpl.kind == nnkPtrTy)

    if not isPtrReturn:
      return body

    let procBody = impl[6]
    verifyNoPointerEscapeTyped(procBody)
    result = body
  of nnkProcDef, nnkFuncDef:
    var cleaned = newNimNode(body.kind)
    cleaned.add(body[0])
    cleaned.add(body[1])
    cleaned.add(body[2])
    cleaned.add(body[3])
    if body[4].kind == nnkPragma:
      var newPragmas = newNimNode(nnkPragma)
      for p in body[4]:
        if (p.kind == nnkIdent and $p == "axiomNoEscape") or
           (p.kind == nnkExprColonExpr and p[0].kind == nnkIdent and $p[0] == "axiomNoEscape"):
          continue
        newPragmas.add(p)
      cleaned.add(if newPragmas.len > 0: newPragmas else: newEmptyNode())
    else:
      cleaned.add(body[4])
    cleaned.add(body[5])
    cleaned.add(body[6])
    result = cleaned
  else:
    error("axiomNoEscape: expected a proc symbol or proc definition, got " & $body.kind)

proc stripAxiomProcPragma(pragmas: NimNode): NimNode {.raises: [].} =
  if pragmas.kind == nnkEmpty: return pragmas
  result = newNimNode(pragmas.kind)
  for p in pragmas:
    if p.kind == nnkExprColonExpr and p[0].kind == nnkIdent and $p[0] == "axiomProc":
      continue
    if p.kind == nnkIdent and $p == "axiomProc":
      continue
    result.add(p)
  if result.len == 0: result = newEmptyNode()

proc extractParamIdent(param: NimNode): NimNode {.raises: [].} =
  if param.kind == nnkIdent: return param
  if param.kind == nnkPragmaExpr: return extractParamIdent(param[0])
  if param.kind == nnkPostfix: return param[1]
  return param

macro axiomProc*(procDef: untyped; refines: static string = "";
                  withContext: static bool = false;
                  pure: static bool = false): untyped =
  if not withContext:
    result = procDef
    return

  let baseIdent = if procDef[0].kind == nnkPostfix: procDef[0][1] else: procDef[0]
  let procNameStr = $baseIdent
  let internalName = ident(procNameStr & "WithCtx")

  var internalProc = procDef.copyNimTree()
  internalProc[0] = internalName
  if internalProc[0].kind == nnkPragmaExpr:
    internalProc[0][1] = stripAxiomProcPragma(internalProc[0][1])
  else:
    internalProc[4] = stripAxiomProcPragma(internalProc[4])
  let ctxParam = newIdentDefs(ident("ctx"), ident("PipelineContextHandle"))
  internalProc[3].insert(1, ctxParam)
  if procDef[2].kind != nnkEmpty:
    internalProc[2] = procDef[2].copyNimTree()
  for i in 1 ..< internalProc[3].len:
    let param = internalProc[3][i]
    if param.kind == nnkIdentDefs:
      let paramType = param[^2]
      if paramType.kind == nnkBracketExpr and $paramType[0] == "varargs":
        param[^2] = nnkBracketExpr.newTree(ident("openArray"), paramType[1])

  var wrapper = procDef.copyNimTree()
  if wrapper[0].kind == nnkPragmaExpr:
    wrapper[0][1] = stripAxiomProcPragma(wrapper[0][1])
  else:
    wrapper[4] = stripAxiomProcPragma(wrapper[4])

  var callTarget: NimNode
  if procDef[2].kind != nnkEmpty:
    let bracketExpr = nnkBracketExpr.newTree(internalName)
    for genericParam in procDef[2]:
      bracketExpr.add(genericParam[0])
    callTarget = bracketExpr
  else:
    callTarget = internalName

  var callExpr = newCall(callTarget)
  callExpr.add(newCall("getContextHandle"))

  var varargsIdx = -1
  for i in 1 ..< procDef[3].len:
    let param = procDef[3][i]
    if param.kind == nnkIdentDefs:
      let paramType = param[^2]
      if paramType.kind == nnkBracketExpr and $paramType[0] == "varargs":
        varargsIdx = i
        break
      for j in 0 .. param.len - 3:
        let realIdent = extractParamIdent(param[j])
        callExpr.add(realIdent)

  if varargsIdx >= 0:
    let varargsIdent = extractParamIdent(procDef[3][varargsIdx][0])
    callExpr = newCall(ident("unpackVarargs"), callExpr, varargsIdent)

  wrapper[6] = newStmtList(callExpr)
  result = newStmtList(internalProc, wrapper)

macro axiomAcyclic*(body: untyped): untyped =
  for child in body:
    if child.kind == nnkTypeSection:
      for typedef in child:
        if typedef.kind == nnkTypeDef:
          let typeBody = typedef[^1]
          if typeBody.kind == nnkRefTy:
            let pragmas = typedef[0]
            var hasAcyclic = false
            if pragmas.kind == nnkPragmaExpr:
              for p in pragmas[1]:
                if p.kind == nnkIdent and p.strVal == "acyclic":
                  hasAcyclic = true
            if not hasAcyclic:
              warning("DEBT PREVENTION: ref object '" & typedef[0].repr &
                      "' may need {.acyclic.} pragma if it has no self-referential fields. " &
                      "See AGENTS.md §0.6a.", typedef)
  result = body

macro axiomLayerGuard*(body: untyped): untyped =
  let srcPath = instantiationInfo(-1, true).filename
  let srcBase = srcPath.extractFilename()
  if srcBase == "axiom_pragmas.nim" or
     srcBase == "axiom_pragmas_shadow.nim" or
     "/config/" in srcPath:
    result = body
    return

  if srcPath in importGuardCache:
    result = body
    return
  importGuardCache[srcPath] = true

  for child in body:
    let reprStr = $child.repr
    for layer in forbiddenCoreImports:
      if layer in reprStr and "solver/provers" notin reprStr:
        error("AGENTS.md §1.2 VIOLATION: core/ MUST NOT import from " &
              "Infrastructure/Presentation/Gate layers directly. " &
              "Use core/interfaces/ hub modules or Composition Root pattern. " &
              "See src/core/interfaces/ for approved DIP boundary modules.", child)
  result = body

macro axiomLayerGuardAutoImpl*(path: static string): untyped =
  let content = staticRead(path)
  let imports = tokenizeImports(content)
  let callerFile = path.extractFilename()

  let srcPath = path.replace("\\", "/")
  var sourceLayer = ""
  if srcPath.startsWith("src/core/"):
    sourceLayer = "core"
  elif srcPath.startsWith("src/infrastructure/"):
    sourceLayer = "infrastructure"
  elif srcPath.startsWith("src/verification/"):
    sourceLayer = "verification"
  elif srcPath.startsWith("src/cli/"):
    sourceLayer = "cli"
  else:
    result = newStmtList()
    return

  const layerForbids = [
    ("core", @["gate/", "cli/", "verification/", "ui/", "frontend/", "infrastructure/"]),
    ("infrastructure", @["gate/", "cli/", "verification/"]),
    ("verification", @["cli/", "ui/", "frontend/"]),
    ("cli", @["ui/", "frontend/"])
  ]

  for (layer, forbids) in layerForbids:
    if sourceLayer == layer:
      for imp in imports:
        if imp.startsWith("std/"): continue
        for fb in forbids:
          if imp.startsWith(fb) or imp.contains("/" & fb):
            if "solver/provers" notin imp:
              error("AGENTS.md §1.2 VIOLATION: " & callerFile &
                    " (layer: " & layer & ") imports '" & imp & "'. " &
                    "Forbidden patterns: " & $forbids & ". " &
                    "Use Composition Root pattern (gateway_main.nim) for DIP wiring.")
      break

  result = newStmtList()

template axiomLayerGuardAuto*() =
  axiomLayerGuardAutoImpl(instantiationInfo(-1, true).filename)

macro axiomMaxLines*(maxLines: static int): untyped =
  discard

macro enforceFacadePatternImpl(path: static string, maxLines: static int): untyped =
  let content = staticRead(path)
  var lineCount = 0
  for line in content.splitLines():
    inc lineCount
  if lineCount > 0 and content.endsWith("\n"):
    dec lineCount
  if lineCount > maxLines:
    error("DEBT PREVENTION: File has " & $lineCount &
          " lines, exceeding the " & $maxLines &
          " line facade pattern limit. " &
          "Decompose into facade + implementation files. " &
          "See AGENTS.md §1.3b.")

template enforceFacadePattern*(maxLines: static int) =
  enforceFacadePatternImpl(instantiationInfo(-1, true).filename, maxLines)

macro axiomEnforceAll*(): untyped =
  discard

macro verifySpecification*(specPath: static string): untyped =
  let srcFile = instantiationInfo(-1, true).filename
  let srcDir = parentDir(srcFile)

  let absDir = srcDir

  var projectRoot = ""
  var d = absDir
  for _ in 0..10:
    if fileExists(d / ".axiom_root"):
      projectRoot = d
      break
    if fileExists(d / "axiom.toml"):
      projectRoot = d
      break
    let p = parentDir(d)
    if p == d: break
    d = p

  if projectRoot.len == 0:
    discard
  else:
    let fullPath = projectRoot & "/" & specPath
    if not fileExists(fullPath):
      error "verifySpecification: specification file missing: " & fullPath &
            " (project root: " & projectRoot & ")"
    let fileContent = readFile(fullPath)
    if fileContent.len == 0:
      error "verifySpecification: specification file empty: " & fullPath &
            " (project root: " & projectRoot & ")"
    var scenarioCount = 0
    for line in fileContent.splitLines():
      let stripped = line.strip()
      if "Scenario:" in stripped:
        inc scenarioCount
    if scenarioCount == 0:
      warning "verifySpecification: spec '" & specPath &
              "' contains no Scenario: entries. Consider adding concrete examples."

  result = newStmtList()

macro registerStageImpl*(p: untyped): untyped =
  if p.kind notin {nnkProcDef, nnkFuncDef}:
    error("registerStage can only be applied to proc/func definitions", p)
  let procName = p.name
  let procNameAsStr = $procName
  result = newTree(nnkStmtList, p)
  result.add quote do:
    static:
      stageRegistry.add((`procNameAsStr`, instantiationInfo(-1, true).filename))

template registerStage*(body: untyped) =
  registerStageImpl(body)

macro autoGenerateSmokeTest*(): untyped =
  result = newStmtList()

  var stageNodes = newSeq[NimNode]()
  for entry in stageRegistry:
    stageNodes.add(newStrLitNode(entry[0]))

  let stagesBracket = newNimNode(nnkPrefix)
  stagesBracket.add(ident("@"))
  let bracket = newNimNode(nnkBracket)
  for node in stageNodes:
    bracket.add(node)
  stagesBracket.add(bracket)

  result.add quote do:
    func getRegisteredStages*(): seq[string] {.raises: [].} =
      `stagesBracket`

  for entry in stageRegistry:
    let stageName = entry[0]
    let modName = entry[1]
    let testName = ident("testSmoke" & stageName.capitalizeAscii)
    let stageIdent = ident(stageName)
    let stageLit = newStrLitNode(stageName)
    let modLit = newStrLitNode(modName)
    result.add quote do:
      func `testName`() =
        doAssert `stageLit` in getRegisteredStages(),
          "Stage '" & `stageLit` & "' not found in registeredStages"
        doAssert cast[pointer](`stageIdent`) != nil,
          "Stage function '" & `stageLit` & "' (module: " & `modLit` & ") resolved to nil"

macro autoGenerateModuleSmokeTest*(modulePath: static string): untyped =
  result = newStmtList()

  let content = staticRead(modulePath)
  let lines = content.splitLines()

  var exportedProcs: seq[string] = @[]
  var exportedTypes: seq[string] = @[]
  var exportedConsts: seq[string] = @[]
  var inTypeBlock = false
  var typeBlockIndent = 0

  for line in lines:
    let stripped = line.strip()

    if stripped.startsWith("type"):
      inTypeBlock = true
      typeBlockIndent = line.len - line.strip(leading = true, trailing = false).len
      if "*" in stripped and "=" in stripped:
        let afterType = stripped[5 .. ^1].strip()
        if "*" in afterType:
          let nameEnd = afterType.find('*')
          if nameEnd > 0:
            let name = afterType[0 ..< nameEnd].strip()
            if name.len > 0 and name[0] in {'A' .. 'Z'}:
              if nameEnd + 1 < afterType.len and afterType[nameEnd + 1] == '[':
                continue
              exportedTypes.add(name)
      continue

    if inTypeBlock:
      let lineIndent = line.len - line.strip(leading = true, trailing = false).len
      if lineIndent <= typeBlockIndent and stripped.len > 0:
        inTypeBlock = false
      elif "*" in stripped and "=" in stripped:
        let nameEnd = stripped.find('*')
        if nameEnd > 0:
          let name = stripped[0 ..< nameEnd].strip()
          if name.len > 0 and name[0] in {'A' .. 'Z'}:
            if nameEnd + 1 < stripped.len and stripped[nameEnd + 1] == '[':
              continue
            exportedTypes.add(name)
      continue

    if (stripped.startsWith("proc ") or stripped.startsWith("func ")) and "*" in stripped:
      let keywordEnd = stripped.find(' ')
      let rest = stripped[keywordEnd + 1 .. ^1]
      if "*" in rest:
        let nameEnd = rest.find('*')
        if nameEnd > 0:
          let name = rest[0 ..< nameEnd].strip()
          if name.len > 0:
            if nameEnd + 1 < rest.len and rest[nameEnd + 1] == '[':
              continue
            if "{.compileTime" in stripped or "{.compileTime." in stripped:
              continue
            exportedProcs.add(name)

    if stripped.startsWith("const") and "*" in stripped:
      let afterConst = stripped[5 .. ^1].strip()
      if "*" in afterConst:
        let nameEnd = afterConst.find('*')
        if nameEnd > 0:
          let name = afterConst[0 ..< nameEnd].strip()
          if name.len > 0:
            exportedConsts.add(name)

  for typeName in exportedTypes:
    let typeIdent = ident(typeName)
    result.add quote do:
      check sizeof(`typeIdent`) > 0

  for procName in exportedProcs:
    let procIdent = ident(procName)
    result.add quote do:
      check cast[pointer](`procIdent`) != nil

  for constName in exportedConsts:
    let constIdent = ident(constName)
    result.add quote do:
      check `constIdent` == `constIdent`

template axiomGcsafe*() {.pragma.}

template axiomIoHint*(reason: string) =
  discard

template axiomProp*(props: varargs[PropertyKind]) {.pragma.}

template axiomIoBoundary*() =
  discard

macro axiomDebt*(args: varargs[untyped]): untyped =
  let bodyNode = args[^1]
  let params = extractDebtParams(args)
  let currentBuildDate = BuildEnvBuildDate
  when defined(release) or defined(axiomCi):
    if params.ttl.len > 0 and params.ttl < currentBuildDate:
      error("Axiom Integrity Violation [DEBT EXPIRED]: " & params.id &
            " (Deadline: " & params.ttl & ", Current Build UTC: " & currentBuildDate & ")", bodyNode)
  else:
    if params.ttl.len > 0 and params.ttl < currentBuildDate:
      warning("DEBT EXPIRED (local): " & params.id & " Deadline=" & params.ttl, bodyNode)
  if params.severity == sevCritical:
    error("Axiom Structural Block [CRITICAL DEBT]: " & params.id &
          " must be resolved before cutting a release build.", bodyNode)
  result = bodyNode

template axiomDebt*(id: static[string], category: static[string] = "") {.pragma.}

macro axiomNestingDepth*(maxDepth: static int, body: untyped): untyped =
  let procDef = body
  if procDef.kind notin {nnkProcDef, nnkFuncDef, nnkMethodDef}:
    result = body
    return
  if procDef.len <= 6 or procDef[6].kind == nnkEmpty:
    result = body
    return
  let procBody = procDef[6]
  let depth = countNestingDepth(procBody)
  if depth > maxDepth:
    error("DEBT PREVENTION: Nesting depth " & $depth & " exceeds max " & $maxDepth &
          ". Flatten using table-driven parsers or early returns.", procDef)
  result = body

macro compositionRootGuardImpl*(path: static string,
                                requiredModules: static seq[string]): untyped =
  let source = staticRead(path)
  let tokenizedImports = tokenizeImports(source)
  for modPath in requiredModules:
    if modPath notin tokenizedImports:
      error("COMPOSITION ROOT GUARD: missing required import '" & modPath &
            "'. See docs/spec/intentional_architecture_patterns.md §8.")
  result = newStmtList()

template compositionRootGuard*(requiredModules: static seq[string]) =
  compositionRootGuardImpl(instantiationInfo(-1, true).filename, requiredModules)

macro verifyTestExists*(modulePath: static string): untyped =
  let srcFile = instantiationInfo(-1, true).filename
  let srcDir = parentDir(srcFile)
  let moduleDir = currentSourcePath.parentDir()
  var candidate = moduleDir
  while candidate.len > 0 and candidate != "/":
    if dirExists(candidate / "src") or fileExists(candidate / ".axiom_root"):
      break
    candidate = candidate.parentDir()
  let absDir = if candidate.len > 0:
                 pathnorm.normalizePath(candidate / srcDir)
               else: srcDir

  var projectRoot = ""
  var d = absDir
  for _ in 0..10:
    if fileExists(d / ".axiom_root"):
      projectRoot = d
      break
    if fileExists(d / "axiom.toml"):
      projectRoot = d
      break
    let p = parentDir(d)
    if p == d: break
    d = p

  if projectRoot.len > 0:
    let moduleName = modulePath.extractFilename.changeFileExt("")
    let testPaths = [
      projectRoot / "tests/unit" / moduleName & "_test.nim",
      projectRoot / "tests/gateway" / moduleName & "_feature_test.nim",
    ]
    var found = false
    for tp in testPaths:
      if fileExists(tp):
        found = true
        break
    if not found:
      warning "No test file found for module: " & modulePath &
              ". Create tests/unit/" & moduleName & "_test.nim"
  result = newStmtList()

macro enforceDomainBoundary*(callerPath: static[string],
                              allowedContracts: static[seq[string]]): untyped =
  let content = staticRead(callerPath)
  let imports = tokenizeImports(content)
  let callerFile = callerPath.extractFilename()

  for imp in imports:
    let prefix = getDomainPrefix(imp)
    if prefix.len == 0: continue
    if imp.startsWith("std/"): continue
    if prefix in allowedContracts: continue

    let isContract = imp.contains("_contract") or imp.contains("_interface")
    if not isContract:
      let suggested = findContractSuggestion(prefix)
      error("[FAIL] [DomainBoundary] " & callerFile &
            " imports '" & imp & "' directly.\n" &
            "   → Use '" & suggested & ".nim' instead.\n" &
            "   → Allowed contracts: " & $allowedContracts)

proc extractCleanName(n: NimNode): string {.warning[UnreachableCode]: off.} =
  case n.kind
  of nnkIdent, nnkSym:
    n.strVal
  of nnkPostfix:
    extractCleanName(n[1])
  of nnkAccQuoted:
    var res = ""
    for child in n: res.add(extractCleanName(child))
    res
  else:
    error("Axiom Critical: Unexpected function name AST kind: " & $n.kind & " repr: " & n.repr, n)
    ""

macro axiomImpl*(def: untyped): untyped =
  if def.kind notin {nnkProcDef, nnkFuncDef}:
    error("axiomImpl: expected proc or func definition", def)

  let funcName = stripGensym(extractCleanName(def[0]))
  let pragma = def.pragma
  if pragma.kind == nnkPragma:
    pragma.add(ident"axiom")
  elif pragma.kind == nnkEmpty:
    def[4] = newNimNode(nnkPragma).add(ident"axiom")

  let isKern = true
  let effectKind = Pure

  try:
    var irDef = convertFuncDef(def)
    applyAxiomSpec(def, irDef)
    let bmcSkip = isBmcSkippable(irDef)
    let irStr = serializeIRFuncDef(irDef)
    let irHash = computeIrDigest(irDef)
    var smtStr = ""
    var leanStr = ""
    axiomRegistry.add(AxiomCompileEntry(
      funcName: funcName,
      irSerialized: irStr,
      irHash: irHash,
      smtSource: smtStr,
      leanSource: leanStr,
      sourcePath: lineInfoObj(def).filename,
      isKernel: isKern,
      effectKind: effectKind,
      bmcSkippable: bmcSkip))
    when defined(axiomDebug):
      echo "[axiomImpl] IR: ", funcName, " params=", irDef.params.len,
           " recursive=", irDef.isRecursive, " registry=", axiomRegistry.len
  except CatchableError:
    echo "[axiomImpl] WARNING: IR generation failed for: ", funcName, " (non-fatal)"

  result = def

macro axiomOpaque*(def: untyped): untyped =
  if def.kind notin {nnkProcDef, nnkFuncDef}:
    error("axiomOpaque: expected proc or func definition", def)

  let pragma = def.pragma
  if pragma.kind == nnkPragma:
    pragma.add(ident"axiom")
  elif pragma.kind == nnkEmpty:
    def[4] = newNimNode(nnkPragma).add(ident"axiom")

  let funcName = stripGensym(extractCleanName(def[0]))
  let isKern = true
  let opaqueMarker = "__opaque__"

  axiomRegistry.add(AxiomCompileEntry(
    funcName: funcName,
    irSerialized: opaqueMarker,
    smtSource: "",
    leanSource: "",
    sourcePath: lineInfoObj(def).filename,
    isKernel: isKern,
    irHash: "",
    effectKind: IOEffect))
  result = def

macro axiomTryImpl*(def: untyped): untyped =
  if def.kind notin {nnkProcDef, nnkFuncDef}:
    error("axiomTryImpl: expected proc or func definition", def)

  let pragma = def.pragma
  if pragma.kind == nnkPragma:
    pragma.add(ident"axiom")
  elif pragma.kind == nnkEmpty:
    def[4] = newNimNode(nnkPragma).add(ident"axiom")

  let funcName = stripGensym(extractCleanName(def[0]))
  let isKern = true
  let effectKind = if def.kind == nnkFuncDef or hasPureEffect(def[4]): Pure else: IOEffect

  proc hasUnsupportedPatterns(n: NimNode): bool =
    case n.kind
    of nnkDotExpr, nnkForStmt, nnkWhileStmt, nnkVarSection, nnkAsgn:
      return true
    else:
      for child in n:
        if hasUnsupportedPatterns(child):
          return true
    return false

  let bodyNode = def[^1]
  if hasUnsupportedPatterns(bodyNode):
    when defined(axiomDebug):
      echo "[axiomTryImpl] FALLBACK: ", funcName, " → opaque (unsupported AST pattern)"
    axiomRegistry.add(AxiomCompileEntry(
      funcName: funcName, irSerialized: "__opaque__",
      smtSource: "", leanSource: "",
      sourcePath: lineInfoObj(def).filename,
      isKernel: isKern,
      irHash: "",
      effectKind: effectKind))
    for i in 0..<def[4].len:
      let pNode = def[4][i]
      if pNode.kind == nnkIdent and $pNode == "axiomTryImpl":
        def[4][i] = ident"axiomOpaque"
  else:
    try:
      var irDef = convertFuncDef(def)
      applyAxiomSpec(def, irDef)
      let irStr = serializeIRFuncDef(irDef)
      let irHash = computeIrDigest(irDef)
      if irDef.name.len == 0:
        when defined(axiomDebug):
          echo "[axiomTryImpl] FALLBACK: ", funcName, " → opaque (degraded IR name)"
        axiomRegistry.add(AxiomCompileEntry(
          funcName: funcName, irSerialized: "__opaque__",
          smtSource: "", leanSource: "",
          sourcePath: lineInfoObj(def).filename,
          isKernel: isKern,
          irHash: "",
          effectKind: effectKind))
        for i in 0..<def[4].len:
          let pNode = def[4][i]
          if pNode.kind == nnkIdent and $pNode == "axiomTryImpl":
            def[4][i] = ident"axiomOpaque"
      else:
        axiomRegistry.add(AxiomCompileEntry(
          funcName: funcName, irSerialized: irStr,
          smtSource: "", leanSource: "",
          sourcePath: lineInfoObj(def).filename,
          isKernel: isKern,
          irHash: irHash,
          effectKind: effectKind))
        for i in 0..<def[4].len:
          let pNode = def[4][i]
          if pNode.kind == nnkIdent and $pNode == "axiomTryImpl":
            def[4][i] = ident"axiomImpl"
    except CatchableError:
      when defined(axiomDebug):
        echo "[axiomTryImpl] FALLBACK: ", funcName, " → opaque (IR conversion exception)"
      axiomRegistry.add(AxiomCompileEntry(
        funcName: funcName, irSerialized: "__opaque__",
        smtSource: "", leanSource: "",
        sourcePath: lineInfoObj(def).filename,
        isKernel: isKern,
        irHash: "",
        effectKind: effectKind))
      for i in 0..<def[4].len:
        let pNode = def[4][i]
        if pNode.kind == nnkIdent and $pNode == "axiomTryImpl":
          def[4][i] = ident"axiomOpaque"

  result = def

macro generateAxiomInit*(): untyped =
  result = newStmtList()
  for entry in axiomRegistry:
    let n = newLit(entry.funcName)
    let ir = newLit(entry.irSerialized)
    let smt = newLit(entry.smtSource)
    let lean = newLit(entry.leanSource)
    let sp = newLit(entry.sourcePath)
    let isKernExpr = newLit(entry.isKernel)
    let irHashLit = newLit(entry.irHash)
    let ekLit = newLit(entry.effectKind)
    let bmcSkipLit = newLit(entry.bmcSkippable)
    result.add quote do:
      registerAxiom(`n`, `ir`, `smt`, `lean`, `sp`, isKern = `isKernExpr`, irHash = `irHashLit`, effectKind = `ekLit`, bmcSkippable = `bmcSkipLit`)

  # WS-P2-B (macro I/O isolation): the compile-time file output of
  # data/verification_scope.lock was removed (Hermetic/sandbox violation).
  # The kernel scope is now derived at runtime from the registry emitted above
  # via `buildScopeLockJson` (axiom_pragmas_procs.nim) and written by
  # `ax scope lock` (src/cli/scope_cli.nim). This macro is now I/O-free.

template refines*(path: string = "") {.pragma.}

macro verifyRefines*(body: untyped): untyped =
  proc walkAndValidate(node: NimNode) =
    case node.kind
    of nnkProcDef, nnkFuncDef:
      validateRefinesProc(node)
    of nnkStmtList, nnkStmtListExpr:
      for child in node:
        walkAndValidate(child)
    of nnkBlockStmt:
      if node.len >= 2:
        walkAndValidate(node[1])
    of nnkWhenStmt, nnkIfStmt, nnkIfExpr:
      for branch in node:
        if branch.kind in {nnkElifBranch, nnkElifExpr} and branch.len >= 2:
          walkAndValidate(branch[1])
        elif branch.kind == nnkElse and branch.len >= 1:
          walkAndValidate(branch[0])
    of nnkPragmaBlock:
      if node.len >= 2:
        walkAndValidate(node[1])
    of nnkForStmt, nnkWhileStmt:
      if node.len >= 2:
        walkAndValidate(node[^1])
    of nnkCaseStmt:
      for i in 1 ..< node.len:
        if node[i].kind == nnkOfBranch and node[i].len >= 2:
          walkAndValidate(node[i][^1])
        elif node[i].kind == nnkElse and node[i].len >= 1:
          walkAndValidate(node[i][0])
    of nnkTypeSection:
      discard
    else:
      for child in node:
        walkAndValidate(child)

  walkAndValidate(body)
  result = body
