{.push raises: [].}

import std/unittest
import core/parser_utils
import compiler/ast
import core/parsers/pnode_nav
import core/symbol_graph/global_symbol_graph_builder_part2

suite "procNameFromDeclNode - export marker regression":
  test "exported proc name extracted correctly (nkPostfix)":
    let source = "proc decodedLength*(btype: typedesc[Base36Types], length: int): int =\n  (length * 179) div 277\n"
    let ast = parseStringAST(source)
    check not ast.isNil
    let procNodes = findNodesP(ast, ProcDefKinds)
    check procNodes.len > 0
    for procNode in procNodes:
      if procNode.len > 0 and not procNode[0].isNil:
        let name = procNameFromDeclNode(procNode[0])
        check name == "decodedLength"

  test "non-exported proc name extracted correctly (nkIdent)":
    let source = "proc newAlphabet36(): string =\n  result = \"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ\"\n"
    let ast = parseStringAST(source)
    check not ast.isNil
    let procNodes = findNodesP(ast, ProcDefKinds)
    check procNodes.len > 0
    for procNode in procNodes:
      if procNode.len > 0 and not procNode[0].isNil:
        let name = procNameFromDeclNode(procNode[0])
        check name == "newAlphabet36"

  test "exported func name extracted correctly (nkPostfix)":
    let source = "func encodedLength*(data: string): int =\n  data.len * 2\n"
    let ast = parseStringAST(source)
    check not ast.isNil
    let funcNodes = findNodesP(ast, {nkFuncDef})
    check funcNodes.len > 0
    for funcNode in funcNodes:
      if funcNode.len > 0 and not funcNode[0].isNil:
        let name = procNameFromDeclNode(funcNode[0])
        check name == "encodedLength"
