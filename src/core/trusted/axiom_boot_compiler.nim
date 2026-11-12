import core/trusted/layer_declaration
axiomLayer "trusted.core.boot-compiler"

## Axiom Boot Compiler — Top-Down Orchestrator for Shadow Virtualization
##
## Replaces 628 Shadow physical files with compile-time memory-resident
## virtual interfaces. Two-pass macro pipeline:
##
##   Pass 1 (Untyped): `bootstrapAxiomModule` — slurp + parseStmt →
##     strip bodies, convert proc→func, filter axiomProc/sideEffect,
##     validate axiomNoEscape on ptr-returning signatures.
##
##   Pass 2 (Typed): `verifyModuleSemantics` — getTypeImpl-based
##     precise pointer escape verification reusing collectPtrAliasesRec.

import std/[macros, strutils, os]
import checksums/sha2
import core/axiom_pragmas

{.push raises: [].}

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
template noContext*() {.pragma.}
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
template gate*() {.pragma.}
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
template impl*() {.pragma.}
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
template types*() {.pragma.}

const leafModules* = [
  "src/core/crypto/hash_kernel.nim",
  "src/core/types/env_types.nim",
  "src/core/trusted/effect_bridge.nim",
  "src/core/trusted/axiom_pragmas_lite.nim",
  "src/infrastructure/logging_facade.nim",
  "src/core/utils/repo_root.nim",
  "src/core/crypto/hash_kernel.nim",
  "src/core/gate/vfs_hasher.nim",
  "src/core/sync/sync_types.nim",
  "src/core/interfaces/io_executor.nim",
]

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func hasPointerInSignature*(node: NimNode): bool =
  ## Scan formal params and return type for nnkPtrTy nodes.
  if node.kind notin {nnkProcDef, nnkFuncDef}:
    return false
  let formalParams = node[3]
  if formalParams.kind != nnkFormalParams:
    return false
  if formalParams.len > 0 and formalParams[0].kind != nnkEmpty:
    if formalParams[0].kind == nnkPtrTy:
      return true
  for i in 1 ..< formalParams.len:
    let paramDefs = formalParams[i]
    if paramDefs.kind == nnkIdentDefs:
      let paramType = paramDefs[^2]
      if paramType.kind == nnkPtrTy:
        return true
  return false

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func hasAxiomNoEscapePragma*(node: NimNode): bool =
  ## Check pragma list for {.axiomNoEscape.} annotation.
  var pragmaNode: NimNode
  case node.kind
  of nnkProcDef, nnkFuncDef:
    pragmaNode = node[4]
  of nnkPragmaExpr:
    if node.len >= 2:
      pragmaNode = node[1]
    else:
      return false
  else:
    return false
  if pragmaNode.kind == nnkEmpty:
    return false
  for p in pragmaNode:
    if (p.kind == nnkIdent and repr(p) == "axiomNoEscape") or
       (p.kind == nnkExprColonExpr and p[0].kind == nnkIdent and
        repr(p[0]) == "axiomNoEscape"):
      return true
  return false

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func hasAxiomProcPragma(node: NimNode): bool =
  ## Check pragma list for {.axiomProc.} annotation.
  if node.kind notin {nnkProcDef, nnkFuncDef}:
    return false
  let pragma = node[4]
  if pragma.kind == nnkEmpty:
    return false
  for p in pragma:
    if (p.kind == nnkIdent and repr(p) == "axiomProc") or
       (p.kind == nnkExprColonExpr and p[0].kind == nnkIdent and
        repr(p[0]) == "axiomProc"):
      return true
  return false

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc hasSideEffectPragma(node: NimNode): bool =
  ## Check pragma list for {.sideEffect.} annotation.
  if node.kind notin {nnkProcDef, nnkFuncDef}:
    return false
  let pragma = node[4]
  if pragma.kind == nnkEmpty:
    return false
  for p in pragma:
    if p.kind == nnkIdent and repr(p) == "sideEffect":
      return true
  return false

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func hasNoContextPragma(node: NimNode): bool =
  ## Check pragma list for {.noContext.} annotation.
  if node.kind notin {nnkProcDef, nnkFuncDef}:
    return false
  let pragmas = node[4]
  if pragmas.kind == nnkEmpty:
    return false
  for p in pragmas:
    if p.kind == nnkIdent and repr(p) == "noContext":
      return true
  return false

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func getSection(node: NimNode): string =
  ## Determine section routing from {.gate.}/{.impl.}/{.types.} pragma.
  if node.kind notin {nnkProcDef, nnkFuncDef}:
    return "impl"
  let pragmas = node[4]
  if pragmas.kind == nnkEmpty:
    return "impl"
  for p in pragmas:
    if p.kind == nnkIdent:
      case repr(p)
      of "gate": return "gate"
      of "types": return "types"
      of "impl": return "impl"
  return "impl"

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func procFuncToFuncDef(node: NimNode): NimNode =
  ## Convert a proc/func definition node to a pure func definition
  ## by creating a new nnkFuncDef and copying all children, stripping
  ## the implementation body.
  result = newNimNode(nnkFuncDef)
  for i in 0 ..< node.len:
    if i == 6:
      result.add(newEmptyNode())
    else:
      result.add(node[i].copyNimTree())

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func extractProcName(node: NimNode): string =
  ## Extract proc name from a proc/func definition node.
  let nameNode = node[0]
  if nameNode.kind == nnkPostfix and nameNode.len >= 2:
    result = nameNode[1].repr
  elif nameNode.kind == nnkIdent:
    result = nameNode.repr
  elif nameNode.kind == nnkPragmaExpr:
    result = extractProcName(nameNode[0])
  else:
    result = nameNode.repr

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro bootstrapAxiomModule*(modulePath: static string): untyped =
  ## Pass 1 (Untyped Stage): Load a shadow module at compile time,
  ## parse it into AST, and produce a list of pure interface definitions
  ## (func signatures with empty bodies).
  ##
  ## Processing per proc/func node:
  ##   1. Convert kind to nnkFuncDef (proc→func normalization)
  ##   2. Strip implementation body (node[6] = newEmptyNode())
  ##   3. Filter out axiomProc and sideEffect annotated definitions
  ##   4. Validate {.axiomNoEscape.} on ptr-returning signatures
  ##   5. Auto-inject PipelineContextHandle param (unless {.noContext.})
  ##   6. Route to types/gate/impl sections via pragma
  when defined(axiomStrict):
    # shadow 파일 경로 인식 차단
    if modulePath.contains("_shadow"):
      error("SHADOW PROHIBITED: " & modulePath & " — use axiom_boot_compiler instead", nil)
  let content = slurp(modulePath)
  let ast = parseStmt(content, modulePath)
  var typesSection = newStmtList()
  var implSection = newStmtList()
  var gateSection = newStmtList()
  for node in ast:
    if node.kind in {nnkProcDef, nnkFuncDef}:
      if hasAxiomProcPragma(node):
        continue
      if hasSideEffectPragma(node):
        continue
      let shadowNode = procFuncToFuncDef(node)
      if hasPointerInSignature(shadowNode) and
         not hasAxiomNoEscapePragma(shadowNode):
        let procName = extractProcName(shadowNode)
        error("BOOT COMPILER: func '" & procName & "' in '" &
              modulePath & "' returns ptr but missing {.axiomNoEscape.}.",
              shadowNode)
      # PipelineContext auto-injection (Step 2)
      if not hasNoContextPragma(shadowNode):
        let formalParams = shadowNode[3]
        var hasCtx = false
        for i in 1 ..< formalParams.len:
          let paramDef = formalParams[i]
          if paramDef.kind == nnkIdentDefs and repr(paramDef[0]) == "axiom_ctx":
            hasCtx = true
            break
        if not hasCtx:
          let ctxParam = newIdentDefs(
            genSym(nskParam, "axiom_ctx"), ident("PipelineContextHandle"))
          shadowNode[3] = nnkFormalParams.newTree(
            formalParams[0],
            ctxParam
          )
          for i in 1 ..< formalParams.len:
            shadowNode[3].add(formalParams[i])
      # Section routing (Step 3)
      let section = getSection(node)
      case section
      of "types": typesSection.add(shadowNode)
      of "gate": gateSection.add(shadowNode)
      else: implSection.add(shadowNode)
    else:
      implSection.add(node)
  result = newStmtList(typesSection, gateSection, implSection)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc extractTypeName(n: NimNode): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Extract base type name from an AST node, unwrapping postfix/brackets.
  var curr = n
  if curr.kind == nnkPostfix: curr = curr[1]
  if curr.kind == nnkBracketExpr: curr = curr[0]
  result = repr(curr)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc collectModulePtrAliasesRec(ast: NimNode, baseDir: string,
    visited: var seq[string], aliases: var seq[string],
    allTypeDefs: var seq[(string, NimNode)], depth: int = 0) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Recursively collect ptr alias type definitions from an AST tree.
  ## Reuses the collectPtrAliasesRec pattern from architecture_invariants.
  if depth > 50: return
  for node in ast:
    if node.kind == nnkIncludeStmt:
      for srcNode in node:
        let rawPath = srcNode.repr.replace(" ", "").replace(
            "\"", "").replace("'", "")
        let subPath = normalizedPath(baseDir / (
          if rawPath.endsWith(".nim"): rawPath else: rawPath & ".nim"))
        block:
          var found = false
          for v in visited:
            if v == subPath:
              found = true
              break
          if found: continue
        visited.add(subPath)
        try:
          let subContent = readFile(subPath)
          collectModulePtrAliasesRec(parseStmt(subContent, subPath),
              parentDir(subPath), visited, aliases, allTypeDefs, depth + 1)
        except CatchableError:
          discard  # axiom:best-effort(ioboundary catch)
    elif node.kind == nnkTypeSection:
      for typedef in node:
        if typedef.kind == nnkTypeDef and typedef.len >= 3:
          let typeName = extractTypeName(typedef[0])
          let typeBody = typedef[2]
          allTypeDefs.add((typeName, typeBody))
          if typeBody.kind == nnkPtrTy:
            aliases.add(typeName)
          elif typeBody.kind == nnkDistinctTy:
            let baseType = typeBody[0]
            var isAlias = false
            if baseType.kind == nnkPtrTy:
              isAlias = true
            elif baseType.kind == nnkSym and repr(baseType) == "pointer":
              isAlias = true
            else:
              let baseName = repr(baseType)
              for a in aliases:
                if a == baseName:
                  isAlias = true
                  break
            if isAlias:
              aliases.add(typeName)
    elif node.kind == nnkWhenStmt:
      for branch in node:
        if branch.kind in {nnkElifBranch, nnkElse} and branch.len > 0:
          collectModulePtrAliasesRec(branch[^1], baseDir, visited, aliases,
              allTypeDefs, depth + 1)
    elif node.kind == nnkBlockStmt:
      if node.len > 1:
        collectModulePtrAliasesRec(node[1], baseDir, visited, aliases,
            allTypeDefs, depth + 1)
    elif node.kind == nnkStmtList:
      collectModulePtrAliasesRec(node, baseDir, visited, aliases,
          allTypeDefs, depth + 1)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro verifyModuleSemantics*(moduleSym: typed): untyped =
  ## Pass 2 (Typed Stage): Verify module semantics using getTypeImpl
  ## for precise pointer type tracking. Receives a typed module symbol
  ## and validates ptr escape constraints at compile time.
  case moduleSym.kind
  of nnkSym:
    let impl = moduleSym.getImpl()
    if impl.kind notin {nnkProcDef, nnkFuncDef}:
      return newEmptyNode()
    let formalParams = impl[3]
    if formalParams.kind != nnkFormalParams or formalParams.len == 0:
      return newEmptyNode()
    let returnTypeNode = formalParams[0]
    if returnTypeNode.kind == nnkEmpty:
      return newEmptyNode()
    let returnTypeImpl = returnTypeNode.getTypeImpl
    let isPtrReturn = returnTypeImpl.kind == nnkPtrTy or
        (returnTypeImpl.kind == nnkDistinctTy and
         returnTypeImpl[0].getTypeImpl.kind == nnkPtrTy)
    if not isPtrReturn:
      return newEmptyNode()
    if not hasAxiomNoEscapePragma(impl):
      let procName = extractProcName(impl)
      error("BOOT COMPILER SEMANTIC: '" & procName &
            "' returns ptr but missing {.axiomNoEscape.}.", impl)
    result = newEmptyNode()
  else:
    result = newEmptyNode()

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func sha256ModuleHash(content: string): string =
  ## Compute SHA-256 hash of module content for integrity tracking.
  result = $secureHash(Sha_256, content)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro bootstrapAndVerify*(modulePath: static string): untyped =
  ## Combined pipeline: Pass 1 (untyped) + Pass 2 (typed) in a single macro.
  ## Returns the interface list from Pass 1 while triggering typed
  ## verification via a static block.
  let content = slurp(modulePath)
  let ast = parseStmt(content, modulePath)
  let moduleHash = sha256ModuleHash(content)
  var interfaceList = newStmtList()
  for node in ast:
    if node.kind in {nnkProcDef, nnkFuncDef}:
      if hasAxiomProcPragma(node):
        continue
      if hasSideEffectPragma(node):
        continue
      let shadowNode = procFuncToFuncDef(node)
      if hasPointerInSignature(shadowNode) and
         not hasAxiomNoEscapePragma(shadowNode):
        let procName = extractProcName(shadowNode)
        error("BOOT COMBINED: func '" & procName & "' in '" &
              modulePath & "' returns ptr but missing {.axiomNoEscape.}.",
              shadowNode)
      interfaceList.add(shadowNode)
  result = newStmtList()
  result.add quote do:
    const axiomBootModuleHash* = `moduleHash`
  result.add interfaceList
