axiomLayer "domain"
func refinesTypeNodeToString(node: NimNode): string {.used, raises: [ValueError].} =
  case node.kind
  of nnkIdent:
    result = node.strVal
  of nnkBracketExpr:
    result = node[0].strVal & "["
    for i in 1 ..< node.len:
      if i > 1:
        result.add(", ")
      result.add(refinesTypeNodeToString(node[i]))
    result.add("]")
  of nnkPtrTy:
    result = "ptr " & refinesTypeNodeToString(node[0])
  of nnkRefTy:
    result = "ref " & refinesTypeNodeToString(node[0])
  of nnkVarTy:
    result = "var " & refinesTypeNodeToString(node[0])
  of nnkProcTy:
    result = "proc"
  of nnkSym:
    result = node.strVal
  of nnkEmpty:
    result = ""
  else:
    result = "unknown"

func getDomainPrefix*(importPath: string): string =
  let parts = importPath.replace("\\", "/").split("/")
  if parts.len >= 2:
    result = parts[1]
  else:
    result = ""

func findContractSuggestion(prefix: string): string {.raises: [].} =
  for entry in domainContractMap:
    if entry.prefix == prefix:
      return entry.contract
  result = prefix & "_contract"

func extractProcName(procDef: NimNode): string {.used, raises: [ValueError].} =
  let nameNode = procDef[0]
  if nameNode.kind == nnkPostfix and nameNode.len >= 2:
    result = nameNode[1].strVal
  elif nameNode.kind == nnkIdent:
    result = nameNode.strVal
  elif nameNode.kind == nnkPragmaExpr:
    result = extractProcName(nameNode[0])
  else:
    result = "unknown"

func extractParamTypes(procDef: NimNode): seq[string] {.used, raises: [ValueError].} =
  result = @[]
  var formalParams: NimNode = nil
  for child in procDef:
    if child.kind == nnkFormalParams:
      formalParams = child
      break
  if formalParams == nil:
    return
  for i in 1 ..< formalParams.len:
    let paramDefs = formalParams[i]
    if paramDefs.kind == nnkIdentDefs and paramDefs.len >= 2:
      let paramName = if paramDefs[0].kind == nnkIdent: paramDefs[0].strVal else: ""
      let typeStr = refinesTypeNodeToString(paramDefs[^2])
      if paramName == "ctx" and typeStr in ["PipelineContextHandle", "ptr PipelineContext"]:
        continue
      result.add(typeStr)

func extractReturnType(procDef: NimNode): string {.used, raises: [ValueError].} =
  result = ""
  var formalParams: NimNode = nil
  for child in procDef:
    if child.kind == nnkFormalParams:
      formalParams = child
      break
  if formalParams == nil:
    return
  if formalParams.len > 0 and formalParams[0].kind != nnkEmpty:
    result = refinesTypeNodeToString(formalParams[0])

func findRefinesPragma(pragmaNode: NimNode): string {.used, raises: [ValueError].} =
  result = ""
  for child in pragmaNode:
    if child.kind == nnkExprColonExpr and
       child[0].kind == nnkIdent and
       child[0].strVal == "refines" and
       child.len >= 2:
      result = child[1].strVal
      return

func validateRefinesProc(
    procDef: NimNode
) {.used, raises: [ValueError].} =
  let shadowPath = findRefinesPragma(procDef.pragma)
  if shadowPath.len == 0:
    return

  let shadowContent = slurp(shadowPath)
  let shadowAst = parseStmt(shadowContent)

  let procName = extractProcName(procDef)
  let origParams = extractParamTypes(procDef)
  let origReturn = extractReturnType(procDef)

  var shadowProc: NimNode = nil
  for node in shadowAst:
    if node.kind in {nnkProcDef, nnkFuncDef}:
      if extractProcName(node) == procName:
        shadowProc = node
        break

  if shadowProc.isNil:
    error("refines: proc '" & procName & "' not found in shadow file '" &
          shadowPath & "'", procDef)

  let shadowParams = extractParamTypes(shadowProc)
  let shadowReturn = extractReturnType(shadowProc)

  if origParams != shadowParams:
    error("refines: parameter type drift detected for '" & procName &
          "': original=" & $origParams & " shadow=" & $shadowParams, procDef)
  if origReturn != shadowReturn:
    error("refines: return type drift detected for '" & procName &
          "': original='" & origReturn & "' shadow='" & shadowReturn & "'",
          procDef)

func tokenizeImports*(source: string): HashSet[string] {.raises: [].} =
  result = initHashSet[string]()

  let lines = source.splitLines()
  var inBracket = false
  var bracketPrefix = ""
  var bracketAccum = ""

  for line in lines:
    let stripped = line.strip()

    if stripped.len == 0 or stripped.startsWith("#"):
      continue

    let normalized = line.replace("\\", "/")

    if inBracket:
      bracketAccum &= " " & normalized
      if "]" in normalized:
        inBracket = false
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

    let s = normalized.strip()
    if s.startsWith("from ") and " import " in s:
      let fromEnd = 5
      let importStart = s.find(" import ")
      if importStart > fromEnd:
        let modPath = s[fromEnd ..< importStart].strip()
        if modPath.len > 0:
          result.incl(modPath)
      continue

    if "import " in normalized:
      let importIdx = normalized.find("import ")
      if importIdx >= 0:
        let afterImport = normalized[importIdx + 7 .. ^1].strip()

        if "[" in afterImport and "]" notin afterImport:
          let openIdx = afterImport.find('[')
          bracketPrefix = afterImport[0 ..< openIdx].strip()
          if bracketPrefix.len > 0 and bracketPrefix[^1] == '/':
            bracketPrefix = bracketPrefix[0 ..< ^1]
          inBracket = true
          bracketAccum = afterImport
          continue

        if "[" in afterImport and "]" in afterImport:
          let openIdx = afterImport.find('[')
          let closeIdx = afterImport.rfind(']')
          var prefix = afterImport[0 ..< openIdx].strip()
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

        for modEntry in afterImport.split(','):
          let modPath = modEntry.strip()
          if modPath.len > 0:
            let parts = modPath.split(" as ")
            let cleanPath = parts[0].strip()
            if cleanPath.len > 0:
              result.incl(cleanPath)

func countNestingDepth*(node: NimNode, currentDepth: int = 0): int {.raises: [].} =
  result = currentDepth
  if node.kind == nnkEmpty:
    return
  case node.kind
  of nnkProcDef, nnkFuncDef, nnkMethodDef:
    if node.len > 6:
      result = max(result, countNestingDepth(node[6], currentDepth))
  of nnkIfStmt:
    for branch in node:
      if branch.kind == nnkElifBranch or branch.kind == nnkExceptBranch:
        if branch.len > 1:
          result = max(result, countNestingDepth(branch[^1], currentDepth + 1))
      elif branch.kind == nnkElse:
        if branch.len > 0:
          result = max(result, countNestingDepth(branch[0], currentDepth + 1))
      elif branch.kind == nnkOfBranch:
        for i in 1 ..< branch.len:
          result = max(result, countNestingDepth(branch[i], currentDepth + 1))
  of nnkCaseStmt:
    for child in node:
      if child.kind == nnkOfBranch:
        for i in 1 ..< child.len:
          result = max(result, countNestingDepth(child[i], currentDepth + 1))
      elif child.kind == nnkElse:
        if child.len > 0:
          result = max(result, countNestingDepth(child[0], currentDepth + 1))
  of nnkWhileStmt:
    if node.len > 1:
      result = max(result, countNestingDepth(node[1], currentDepth + 1))
  of nnkForStmt:
    if node.len > 0:
      result = max(result, countNestingDepth(node[^1], currentDepth + 1))
  of nnkTryStmt:
    for child in node:
      if child.kind == nnkExceptBranch:
        if child.len > 1:
          result = max(result, countNestingDepth(child[^1], currentDepth + 1))
      elif child.kind == nnkFinally:
        if child.len > 0:
          result = max(result, countNestingDepth(child[0], currentDepth + 1))
  of nnkBlockStmt:
    if node.len > 1:
      result = max(result, countNestingDepth(node[^1], currentDepth + 1))
  of nnkStmtList:
    for child in node:
      result = max(result, countNestingDepth(child, currentDepth))
  else:
    for i in 0 ..< node.len:
      result = max(result, countNestingDepth(node[i], currentDepth))

proc extractDebtParams(args: NimNode): DebtParams {.raises: [].} =
  if args.len == 0: return DebtParams(severity: sevMedium, valid: false)
  if args[0].kind != nnkStrLit:
    error("Axiom Pragma Error: first argument must be a static string debt ID.", args[0])

  var parts: seq[string]
  parts.add("\"" & args[0].strVal & "\"")
  for i in 1 ..< args.len - 1:
    let arg = args[i]
    case arg.kind
    of nnkExprEqExpr:
      parts.add(arg[0].strVal & "=\"" & arg[1].strVal & "\"")
    of nnkStrLit:
      parts.add("\"" & arg.strVal & "\"")
    else: error("Unsupported argument syntax.", arg)

  let reconstructed = "axiomDebt(" & parts.join(", ") & ")"
  result = parseDebtParams(reconstructed)

  if result.valid and result.severity notin {sevLow, sevMedium, sevHigh, sevCritical}:
    error("Invalid severity level '" & $result.severity & "'.", args[0])

func hasPureEffect(pragmaNode: NimNode): bool {.raises: [].} =
  if pragmaNode.kind == nnkEmpty: return false
  for pragma in pragmaNode:
    if pragma.kind == nnkExprColonExpr:
      if pragma[0].eqIdent("axiomEffect") and pragma[1].eqIdent("Pure"):
        return true
    elif pragma.kind == nnkIdent and pragma.eqIdent("pure"):
      return true
  false
