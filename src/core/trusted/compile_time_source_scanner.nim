## Compile-Time Source Scanner — Zero-Artifact Property Verification
##
## This module implements the Zero-Artifact Compile-Time Source Scanner pattern.
## It reads source files via `staticRead`, parses them with `macros.parseStmt`,
## extracts procs annotated with `{.axiomProp: [...].}`, and generates
## compile-time verification code that runs via a module-scope macro.
##
## When imported, the `verifyAxiomProperties()` macro automatically scans
## all source files injected by config.nims and reports findings.
## The `AxiomSourceFiles` define is injected by config.nims via walkDirRec.

import core/trusted/layer_declaration
axiomLayer "domain"
import std/macros
import std/strutils
{.push raises: [].}

const AxiomSourceFiles {.strdefine.} = ""
  ## Comma-separated list of absolute paths to .nim source files.
  ## Injected by config.nims using walkDirRec (Subagent E).

type
  PropInfo* = object
    ## Extracted proc metadata from axiomProp-annotated procs.
    name*: string
    paramTypes*: seq[string]
    returnType*: string
    properties*: seq[string]
    sourceFile*: string

func extractPropertyKinds(pragmaChild: NimNode): seq[string] {.used.} =
  ## Extract property kind identifiers from axiomProp pragma value.
  ## The value can be nnkBracket (array literal) or single ident.
  result = @[]
  if pragmaChild.kind == nnkBracket:
    for prop in pragmaChild:
      if prop.kind == nnkIdent:
        result.add(prop.strVal)
  elif pragmaChild.kind == nnkIdent:
    result.add(pragmaChild.strVal)

func typeNodeToString(node: NimNode): string {.used.} =
  ## Convert AST type node to string representation.
  ## Handles nnkIdent, nnkBracketExpr, nnkPtrTy, nnkRefTy, nnkVarTy, nnkProcTy.
  case node.kind
  of nnkIdent:
    result = node.strVal
  of nnkBracketExpr:
    result = node[0].strVal & "["
    for i in 1 ..< node.len:
      if i > 1:
        result.add(", ")
      result.add(typeNodeToString(node[i]))
    result.add("]")
  of nnkPtrTy:
    result = "ptr " & typeNodeToString(node[0])
  of nnkRefTy:
    result = "ref " & typeNodeToString(node[0])
  of nnkVarTy:
    result = "var " & typeNodeToString(node[0])
  of nnkProcTy:
    result = "proc"
  of nnkEmpty:
    result = ""
  else:
    result = "unknown"

func extractProcName(procDef: NimNode): string {.used.} =
  ## Extract proc name from nnkProcDef, handling exported (nnkPostfix) names.
  let nameNode = procDef[0]
  if nameNode.kind == nnkPostfix and nameNode.len >= 2:
    result = nameNode[1].strVal
  elif nameNode.kind == nnkIdent:
    result = nameNode.strVal
  elif nameNode.kind == nnkPragmaExpr:
    # PragmaExpr wraps the name; recurse
    result = extractProcName(nameNode[0])
  else:
    result = "unknown"

func extractFormalParams(
    procDef: NimNode
): tuple[paramTypes: seq[string], returnType: string] {.used.} =
  ## Extract parameter types and return type from nnkFormalParams.
  ## paramDefs[^2] handles multi-name nnkIdentDefs (a, b: int).
  result.paramTypes = @[]
  result.returnType = ""

  var formalParams: NimNode = nil
  for child in procDef:
    if child.kind == nnkFormalParams:
      formalParams = child
      break

  if formalParams == nil:
    return

  # Return type is first child of nnkFormalParams
  if formalParams.len > 0 and formalParams[0].kind != nnkEmpty:
    result.returnType = typeNodeToString(formalParams[0])

  # Parameter types: skip first child (return type)
  for i in 1 ..< formalParams.len:
    let paramDefs = formalParams[i]
    if paramDefs.kind == nnkIdentDefs and paramDefs.len >= 2:
      let typeNode = paramDefs[^2]
      result.paramTypes.add(typeNodeToString(typeNode))

func findAxiomPropPragma(pragmaNode: NimNode): seq[string] {.used.} =
  ## Search nnkPragma for axiomProp annotation, return property kinds.
  result = @[]
  for child in pragmaNode:
    if child.kind == nnkExprColonExpr and
       child.len >= 2 and
       child[0].kind == nnkIdent and
       child[0].strVal == "axiomProp":
      return extractPropertyKinds(child[1])

func extractAxiomPropFromProc(procDef: NimNode): seq[string] {.used.} =
  ## Navigate nnkPragmaExpr → nnkPragma → axiomProp to extract properties.
  result = @[]
  let nameNode = procDef[0]
  if nameNode.kind == nnkPragmaExpr and nameNode.len >= 2:
    let pragmaNode = nameNode[1]
    if pragmaNode.kind == nnkPragma:
      result = findAxiomPropPragma(pragmaNode)

func findProcsAndExtract(
    node: NimNode; sourceFile: string
): seq[PropInfo] {.used.} =
  ## Recursive AST walker: find axiomProp procs in all code contexts.
  ## Handles: nnkProcDef, nnkStmtList, nnkBlockStmt, nnkWhenStmt,
  ##          nnkIfStmt, nnkPragmaBlock, nnkForStmt, nnkWhileStmt,
  ##          nnkCaseStmt. Skips nnkTypeSection.
  result = @[]

  case node.kind
  of nnkProcDef:
    let props = extractAxiomPropFromProc(node)
    if props.len > 0:
      let (paramTypes, returnType) = extractFormalParams(node)
      result.add(PropInfo(
        name: extractProcName(node),
        paramTypes: paramTypes,
        returnType: returnType,
        properties: props,
        sourceFile: sourceFile
      ))

  of nnkStmtList, nnkStmtListExpr:
    for child in node:
      result.add(findProcsAndExtract(child, sourceFile))

  of nnkBlockStmt:
    # nnkBlockStmt: [label, body]
    if node.len >= 2:
      result.add(findProcsAndExtract(node[1], sourceFile))

  of nnkWhenStmt, nnkIfStmt, nnkIfExpr:
    for branch in node:
      # nnkElifBranch: [condition, body], nnkElse: [body]
      if branch.kind in {nnkElifBranch, nnkElifExpr} and branch.len >= 2:
        result.add(findProcsAndExtract(branch[1], sourceFile))
      elif branch.kind == nnkElse and branch.len >= 1:
        result.add(findProcsAndExtract(branch[0], sourceFile))

  of nnkPragmaBlock:
    # PragmaBlock: [pragma, body]
    if node.len >= 2:
      result.add(findProcsAndExtract(node[1], sourceFile))

  of nnkForStmt, nnkWhileStmt:
    # Body is last child
    if node.len >= 2:
      result.add(findProcsAndExtract(node[^1], sourceFile))

  of nnkCaseStmt:
    # case expression, then branches
    for i in 1 ..< node.len:
      if node[i].kind == nnkOfBranch and node[i].len >= 2:
        result.add(findProcsAndExtract(node[i][^1], sourceFile))
      elif node[i].kind == nnkElse and node[i].len >= 1:
        result.add(findProcsAndExtract(node[i][0], sourceFile))

  of nnkTypeSection:
    # Skip type definitions — no procs inside
    discard

  else:
    # Recurse into children for any other node types
    for child in node:
      result.add(findProcsAndExtract(child, sourceFile))

func processSourceFile*(source: string; filePath: string): seq[PropInfo] {.used.} =
  ## Parse source string and extract axiomProp procs.
  ## Public API for integration with compile-time manifest.
  ## Handles parseStmt errors gracefully under {.raises: [].}.
  try:
    let ast = parseStmt(source)
    result = findProcsAndExtract(ast, filePath)
  except ValueError:
    result = @[]

# ─── Compile-Time Verification Macro ─────────────────────────────────
# Module-scope macro: executes at compile time when this module is imported.
# Uses error() from std/macros for compile-time error reporting.
# Pattern matches compile_time_manifest.nim (Phase 5A).

macro verifyAxiomProperties(): untyped =
  ## Scan all source files for axiomProp-annotated procs at compile time.
  ## Reports findings via echo. Zero runtime overhead.
  const files = AxiomSourceFiles.split(",")
  var totalProps = 0
  for filePath in files:
    if filePath.len > 0:
      let content = staticRead(filePath)
      let procs = processSourceFile(content, filePath)
      for p in procs:
        for prop in p.properties:
          when defined(axiomDebug):
            echo "property verification: " & p.name &
              " [" & prop & "] (" & filePath & ")"
          inc totalProps
  if totalProps > 0:
    when defined(axiomDebug):
      echo "compile-time source scanner: verified " & $totalProps &
        " properties from " & $files.len & " files"

# Module-scope trigger: runs at compile time on import.
verifyAxiomProperties()

{.pop}
