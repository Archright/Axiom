import std/unittest
import std/macros
import std/strutils
import core/parser_utils
import core/trusted/pnode_to_canon
import core/trusted/ast_to_ir
import shared/canonical_ast

# WP1.5-a anchor: the parser frontend (PNode → pnodeToCanon → CanonNode) and
# the compiler frontend (macro-context NimNode → toCanon → CanonNode) must
# converge on identical IRFuncDef serializations for frontend-equivalent
# fixtures (R2 scope: no macro expansion / semantic resolution involved).

macro captureIr(body: untyped): untyped =
  ## Compiler-frontend leg: runs inside macro expansion where `body` is a real
  ## NimNode. Converts through toCanon → convertFuncDefCanon and returns the
  ## serialized IR as a compile-time string literal.
  # untyped macro argument arrives wrapped in nnkStmtList — unwrap to the def.
  var fn = body
  if fn.kind == nnkStmtList and fn.len > 0:
    fn = fn[0]
  let ir = convertFuncDefCanon(toCanon(fn))
  newLit(serializeIRFuncDef(ir))

const GoldenFn = """
func swapBytesNim(x: uint32): uint32 =
  let v = (x shl 16) or (x shr 16)
  ((v shl 8) and 0xff00ff00'u32) or ((v shr 8) and 0x00ff00ff'u32)
"""

const SmallFn = """
func inc2(a: int): int =
  let b = a + 1
  b + 1
"""

proc parseLeg(fixture: string): string =
  ## Parser frontend leg: parseStringAST → findFuncDefP → pnodeToCanon
  ## → convertFuncDefCanon → serialize.
  let ast = parseStringAST(fixture)
  check not ast.isNil
  let nameH = if fixture.contains("swapBytesNim"): "swapBytesNim" else: "inc2"
  let typeH = if nameH == "swapBytesNim": "uint32" else: ""
  let defNode = findFuncDefP(ast, nameH, typeH)
  check not defNode.isNil
  let irP = axiomBodyCanon(pnodeToCanon(defNode))
  serializeIRFuncDef(irP)

suite "WP1.5-a semantic bridge equivalence":

  test "golden swapBytesNim: compiler-front vs parser-front serialize identically":
    let serN = captureIr:
      func swapBytesNim(x: uint32): uint32 =
        let v = (x shl 16) or (x shr 16)
        ((v shl 8) and 0xff00ff00'u32) or ((v shr 8) and 0x00ff00ff'u32)
    let serP = parseLeg(GoldenFn)
    check serN.len > 0
    check serN == serP

  test "synthetic inc2: both frontends produce identical serialized IR":
    let serN = captureIr:
      func inc2(a: int): int =
        let b = a + 1
        b + 1
    let serP = parseLeg(SmallFn)
    check serN == serP
