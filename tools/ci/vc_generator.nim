import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [CatchableError].}

import std/[os, strutils, sequtils]
import core/parser_utils
import compiler/ast
import verification/router

# ── Type ─────────────────────────────────────────────────────────────────

type
  ParamInfo* = tuple[name: string, typ: string]

  FuncDef = object
    sig: FuncSignature
    bodyStart: int
    bodyEnd: int
    bodyLines: seq[string]
    hasAssert: bool
    hasPreCondition: bool

# ── AST parsing (runtime-safe via compiler/ modules) ─────────────────────

proc parseFileToAst(filePath: string): PNode {.raises: [].} =
  ## Parse a .nim file into a PNode tree using shared IdentCache/ConfigRef caches.
  parser_utils.parseFileAST(filePath)

func typeNodeToString(n: PNode): string =
  if n == nil: return ""
  case n.kind
  of nkIdent:
    result = n.ident.s
  of nkBracketExpr:
    result = typeNodeToString(n[0]) & "["
    for i in 1 ..< n.len:
      if i > 1: result.add(", ")
      result.add(typeNodeToString(n[i]))
    result.add("]")
  of nkSym:
    result = n.sym.name.s
  of nkPtrTy:
    result = "ptr " & typeNodeToString(n[0])
  of nkRefTy:
    result = "ref " & typeNodeToString(n[0])
  of nkVarTy:
    result = "var " & typeNodeToString(n[0])
  of nkEmpty:
    result = ""
  else:
    result = ""

func extractName(n: PNode): string =
  if n == nil: return ""
  case n.kind
  of nkPostfix:
    if n.len >= 2: result = extractName(n[1])
  of nkIdent:
    result = n.ident.s
  of nkSym:
    result = n.sym.name.s
  of nkPragmaExpr:
    if n.len >= 1: result = extractName(n[0])
  else:
    result = ""

func extractFormalParams(n: PNode): tuple[params: seq[ParamInfo], retType: string] =
  result.params = @[]
  result.retType = ""
  var formalParams: PNode = nil
  for child in n:
    if child.kind == nkFormalParams:
      formalParams = child
      break
  if formalParams == nil:
    return
  if formalParams.len > 0 and formalParams[0].kind != nkEmpty:
    result.retType = typeNodeToString(formalParams[0])
  for i in 1 ..< formalParams.len:
    let identDefs = formalParams[i]
    if identDefs.kind == nkIdentDefs and identDefs.len >= 2:
      let typeNode = identDefs[^2]
      let typeStr = typeNodeToString(typeNode)
      for j in 0 ..< identDefs.len - 2:
        let nameNode = identDefs[j]
        if nameNode.kind == nkIdent:
          result.params.add((name: nameNode.ident.s, typ: typeStr))

func nodeIdentName(n: PNode): string =
  if n == nil: return ""
  case n.kind
  of nkIdent: result = n.ident.s
  of nkSym: result = n.sym.name.s
  else: discard

func bodyContainsResult(body: PNode): bool =
  if body == nil or body.kind == nkEmpty: return false
  let name = nodeIdentName(body)
  if name == "result":
    return true
  for i in 0 ..< body.safeLen:
    if bodyContainsResult(body[i]):
      return true
  false

func bodyHasAssert(body: PNode): bool =
  if body == nil or body.kind == nkEmpty: return false
  if body.kind in {nkCall, nkCommand}:
    if body.len > 0:
      let callee = nodeIdentName(body[0])
      if callee == "assert" or callee == "doAssert":
        return true
  for i in 0 ..< body.safeLen:
    if bodyHasAssert(body[i]):
      return true
  false

func hasRequiresPragma(n: PNode): bool =
  ## n may be a nkPragma node directly, or a parent containing nkPragma.
  if n == nil: return false
  # If n is the nkPragma itself, inspect its children directly
  if n.kind == nkPragma:
    for child in n:
      if child.kind == nkIdent and
         child.ident.s in ["requires", "ensures"]:
        return true
      if child.kind == nkExprColonExpr and
         child.safeLen >= 2 and
         child[0].kind == nkIdent and
         child[0].ident.s in ["requires", "ensures"]:
        return true
  else:
    # Search for nkPragma children
    for child in n:
      if child.kind == nkPragma:
        if hasRequiresPragma(child):
          return true
  false

# ── Indent-based body extraction (anchored at AST declaration line) ─────

proc extractBodyLines(sourceLines: seq[string]; declLine: int): seq[string] =
  let stripped = sourceLines[declLine - 1].strip()
  let indent = sourceLines[declLine - 1].len - stripped.len

  # Check if the `=` is on the declaration line itself
  let eqOnDeclLine = '=' in sourceLines[declLine - 1]

  if not eqOnDeclLine:
    # Forward declaration — no `=` on the decl line means no body
    return @[]

  let bodyStart = declLine + 1
  if bodyStart > sourceLines.len:
    return @[]

  var bodyEnd = bodyStart
  while bodyEnd <= sourceLines.len:
    let ln = sourceLines[bodyEnd - 1]
    let lnStripped = ln.strip()
    if lnStripped.len == 0:
      bodyEnd.inc
      continue
    if lnStripped.startsWith("#"):
      bodyEnd.inc
      continue
    let lnIndent = ln.len - lnStripped.len
    if lnIndent <= indent:
      break
    bodyEnd.inc

  sourceLines[bodyStart - 1 .. bodyEnd - 2]

# ── AST walker ──────────────────────────────────────────────────────────

proc collectFuncDefs(ast: PNode; sourceLines: seq[string]): seq[FuncDef] =
  result = @[]
  if ast == nil: return

  proc walk(n: PNode; acc: var seq[FuncDef]) =
    if n == nil: return
    if n.kind in {nkFuncDef, nkProcDef}:
      let name = extractName(n[0])
      if name.len == 0: return

      let (params, retType) = extractFormalParams(n)

      var pragmaNode: PNode = nil
      var bodyNode: PNode = nil
      for idx in 0 ..< n.safeLen:
        if n[idx].kind == nkPragma: pragmaNode = n[idx]
        if n[idx].kind == nkStmtList and n[idx].safeLen > 0: bodyNode = n[idx]
      let hasPre = pragmaNode != nil and hasRequiresPragma(pragmaNode)
      let body = bodyNode

      let funcStartLine = int(n.info.line)
      let rawBodyLines = extractBodyLines(sourceLines, funcStartLine)
      let bodyEnd = funcStartLine + rawBodyLines.len

      let usesRes = body != nil and body.kind != nkEmpty and bodyContainsResult(body)
      let hAssert = body != nil and body.kind != nkEmpty and bodyHasAssert(body)

      acc.add(FuncDef(
        sig: FuncSignature(
          name: name,
          params: params,
          retType: retType,
          usesResult: usesRes
        ),
        bodyStart: funcStartLine,
        bodyEnd: bodyEnd,
        bodyLines: rawBodyLines,
        hasAssert: hAssert,
        hasPreCondition: hasPre
      ))
      return

    for i in 0 ..< n.safeLen:
      walk(n[i], acc)

  walk(ast, result)

# ── Build Lean Verification Condition module ───────────────────────────

func buildLeanPrelude(): string =
  "-- Generated by Axiom VC Generator (tools/ci/vc_generator.nim)\n" &
  "-- Target: Lean 4\n" &
  "import AxiomPrelude\n" &
  "open AxiomPrelude\n\n"

func buildParamSection(params: seq[ParamInfo]): string =
  if params.len == 0: return ""
  var parts: seq[string]
  for p in params:
    let leanType = nimTypeToLean(p.typ)
    parts.add("(" & p.name & " : " & leanType & ")")
  parts.join(" ")

func buildTheoremBlock(fd: FuncDef; verifier: Verifier): string =
  let propName = fd.sig.name & "_spec"
  let params = buildParamSection(fd.sig.params)
  var tb = "theorem " & propName & " " & params & " : Prop :=\n"
  tb.add("  by\n")
  if verifier.kind == z3Target:
    tb.add("    -- Z3 BMC target (bounded loop)\n" &
           "    -- VC stub: replace with Z3-generated invariant\n" &
           "    sorry\n")
  else:
    tb.add("    -- Lean target: " & verifier.reason & "\n" &
           "    -- VC stub: replace with inductive proof or invariant\n" &
           "    sorry\n")
  tb

func buildDefBlock(fd: FuncDef): string =
  let retType = if fd.sig.retType.len > 0: nimTypeToLean(fd.sig.retType) else: "Unit"
  let params = buildParamSection(fd.sig.params)
  var db = "-- Translated from Nim func " & fd.sig.name & "\n"
  db.add("def " & fd.sig.name & " " & params & " : " & retType & " :=\n")
  db.add("  by\n")
  db.add("    -- body not translated in stub phase\n")
  db.add("    sorry\n\n")
  db

proc buildSourceVcModule(fds: seq[FuncDef]; filePath: string): string =
  var lines: seq[string]
  lines.add(buildLeanPrelude())
  lines.add("-- Source: " & filePath)
  lines.add("")
  for fd in fds:
    let verifier = routeVerification(fd.bodyLines.join("\n"), fd.sig.name)
    lines.add(buildDefBlock(fd))
    lines.add(buildTheoremBlock(fd, verifier))
    lines.add("")
  lines.join("\n")

# ── Entry point ─────────────────────────────────────────────────────────

proc extractFunctionsFromFile(filePath: string): seq[FuncDef] =
  let ast = parseFileToAst(filePath)
  let content = readFile(filePath)
  let sourceLines = content.splitLines()
  result = collectFuncDefs(ast, sourceLines)

proc generateVcFile(fds: seq[FuncDef]; sourcePath: string; outputDir: string) =
  let leanSource = buildSourceVcModule(fds, sourcePath)
  let baseName = sourcePath.extractFilename().changeFileExt("")
  let outPath = outputDir / baseName & ".vc.lean"
  createDir(outputDir)
  writeFile(outPath, leanSource)
  echo "Generated: " & outPath

proc printExtraction(fds: seq[FuncDef]) =
  for fd in fds:
    let verifier = routeVerification(fd.bodyLines.join("\n"), fd.sig.name)
    echo "func " & fd.sig.name & "(" & fd.sig.params.mapIt(it.name & ": " & it.typ).join(", ") & ")"
    if fd.sig.retType.len > 0:
      echo "  returns: " & fd.sig.retType
    echo "  usesResult: " & $fd.sig.usesResult
    echo "  hasAssert: " & $fd.hasAssert
    echo "  hasPreCondition: " & $fd.hasPreCondition
    echo "  verifier: " & $verifier.kind & " (" & verifier.reason & ")"
    echo "  bodyLines[" & $fd.bodyStart & "-" & $fd.bodyEnd & "]: " & $fd.bodyLines.len
    if fd.bodyLines.len > 0:
      echo "  body text: " & fd.bodyLines.join("|")
    echo ""

proc main() =
  if paramCount() < 1:
    stderr.writeLine("Usage: vc_generator <source.nim> [--output <dir>] [--print]")
    quit(1)
  let sourceFile = paramStr(1)
  if not fileExists(sourceFile):
    stderr.writeLine("Error: file not found: " & sourceFile)
    quit(1)
  var outputDir = "generated_vcs"
  var printMode = false
  var i = 2
  while i <= paramCount():
    let arg = paramStr(i)
    if arg == "--output" and i < paramCount():
      i.inc
      outputDir = paramStr(i)
    elif arg == "--print":
      printMode = true
    i.inc
  let fds = extractFunctionsFromFile(sourceFile)
  if fds.len == 0:
    echo "No func/proc definitions found in " & sourceFile
    quit(0)
  if printMode:
    printExtraction(fds)
  else:
    generateVcFile(fds, sourceFile, outputDir)
  echo "Done: " & $fds.len & " functions processed"

when isMainModule:
  main()

{.pop.}
