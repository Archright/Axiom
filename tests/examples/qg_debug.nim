import os, tables, strutils
import compiler/[ast, parser, options, llstream, idents, pathutils]

proc dumpNode(n: PNode; depth: int = 0) =
  let indent = "  ".repeat(depth)
  case n.kind
  of nkIdent:
    echo indent, "nkIdent: ", n.ident.s
  of nkStrLit..nkTripleStrLit:
    echo indent, "nkStrLit: ", n.strVal
  of nkDotExpr:
    echo indent, "nkDotExpr:"
    for i in 0 ..< n.safeLen: dumpNode(n[i], depth + 1)
  of nkInfix:
    echo indent, "nkInfix:"
    for i in 0 ..< n.safeLen: dumpNode(n[i], depth + 1)
  of nkPrefix:
    echo indent, "nkPrefix:"
    for i in 0 ..< n.safeLen: dumpNode(n[i], depth + 1)
  of nkImportStmt:
    echo indent, "nkImportStmt:"
    for i in 0 ..< n.safeLen: dumpNode(n[i], depth + 1)
  of nkFromStmt:
    echo indent, "nkFromStmt:"
    for i in 0 ..< n.safeLen: dumpNode(n[i], depth + 1)
  else:
    echo indent, $n.kind, " (len=", n.safeLen, ")"

let filePath = "src/gate/ast_architecture_gate.nim"
let source = readFile(filePath)
let cache = newIdentCache()
let config = newConfigRef()
var stream = llStreamOpen(source)
let absFile = AbsoluteFile(filePath)
var p: Parser
openParser(p, absFile, stream, cache, config)
let topNode = parseAll(p)
closeParser(p)

for i in 0 ..< min(10, topNode.safeLen):
  if topNode[i].kind == nkImportStmt:
    echo "--- Import [", i, "] ---"
    dumpNode(topNode[i])
