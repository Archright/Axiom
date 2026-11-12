## Spec-pragma if-expression Canon coverage — p0d2f first-attempt gap.
##
## SSOT: docs/spec/replay_harness_config_quirks.md §Q2 "관련 기록" (the
## exit-2 lossy refusal root cause) + experiments/act2-wp-toml-b1-input-
## integrity/p0d2f/SPEC.md Amendment.
##
## Measured here:
##   1. The PNode→CanonKind table covers the expression-if branch forms:
##      pragma-context `(if c < 1: 0 else: 1)` parses as
##      nkStmtListExpr(nkIfStmt(nkElifExpr, nkElseExpr)) — the branch kinds
##      map to ckElifExpr/ckElseExpr (mirroring tools/shared/canonical_ast.nim).
##   2. The CanonNode→IR translator routes the statement-form ckIfStmt to
##      convertIfExprCanon (mirroring the NimNode path's nnkIfExpr/nnkIfStmt),
##      so an explicit spec pragma with an if-expression post ingests
##      loss-free end-to-end through the external-spec ingestion path and
##      generates obligations (never the lossy "no IR translation" refusal).
import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

import std/unittest
import std/[options, os, sets, sequtils]
import core/trusted/axiom_ir
import core/axiom_pragmas
import core/parser_utils
import core/trusted/pnode_to_canon
import core/trusted/ast_to_ir
import shared/canonical_ast
import compiler/[ast, idents]
import infrastructure/external_ir_materializer
import verification/batch_uap/ir_pipeline_runner
import verification/obligation/candidate_eligibility

setExternalSubjectMode(true)

# The p0d2f first-attempt shape: a spec pragma whose post is an if-expression.
const SourceIfExprPost = """
func p(c: int): int {.axiom: [pre: (c >= 0), post: (result == (if c < 1: 0 else: 1))].} =
  0
"""

func firstCanonOfKind(n: CanonNode; want: CanonKind): Option[CanonNode] =
  ## Depth-first first node of `want` — none when absent.
  if n.kind == want:
    return some(n)
  for c in n.children:
    let hit = firstCanonOfKind(c, want)
    if hit.isSome:
      return hit
  none(CanonNode)

proc findFuncDef(ast: PNode): PNode =
  for i in 0 ..< ast.len:
    if ast[i].kind in {nkFuncDef, nkProcDef}:
      return ast[i]
  nil

func resolverFromContent(content: string): ModuleContentResolver =
  proc(m: string): Option[string] {.raises: [], noSideEffect.} =
    some(content)

suite "spec pragma if-expression — Canon coverage (p0d2f gap)":

  test "PNode if-expression branch kinds map to ckElifExpr/ckElseExpr":
    let ast = parseStringAST(SourceIfExprPost)
    check ast != nil
    let defNode = findFuncDef(ast)
    check defNode != nil
    # pragma → axiom bracket → post entry → the paren-unwrapped comparison
    let postArg = defNode[4][0][1][1][1]
    let canon = pnodeToCanon(postArg)
    # The mission-recorded parse shape: nkStmtListExpr(nkIfStmt(branches))
    let stmtListOpt = firstCanonOfKind(canon, ckStmtListExpr)
    check stmtListOpt.isSome
    let stmtList = stmtListOpt.get
    check stmtList.children.len == 1
    check stmtList.children[0].kind == ckIfStmt
    let ifStmt = stmtList.children[0]
    check ifStmt.children.len == 2
    check ifStmt.children[0].kind == ckElifExpr
    check ifStmt.children[1].kind == ckElseExpr

  test "ckIfStmt in expression position translates loss-free via convertIfExprCanon":
    let ast = parseStringAST(SourceIfExprPost)
    check ast != nil
    let defNode = findFuncDef(ast)
    check defNode != nil
    let postArg = defNode[4][0][1][1][1]
    var ctx = initIrContext("p", @[IRFuncParam(name: "c", ty: irTypeBitVec64())])
    let postIr = convertExprCanon(pnodeToCanon(postArg), ctx)
    check not ctx.lossySeen
    # result == (if c < 1: 0 else: 1) → irEq(irVar(result), irIf(...))
    check postIr.kind == irBinOp
    check postIr.binOp == boEq
    check postIr.binLhs.kind == irVar
    check postIr.binLhs.varName == "result"
    let ifE = postIr.binRhs
    check ifE.kind == irIf
    check ifE.ifCond.kind == irBinOp and ifE.ifCond.binOp == boLt
    check ifE.ifThen.kind == irLit and ifE.ifThen.litVal == 0
    check ifE.ifElse.kind == irLit and ifE.ifElse.litVal == 1

  test "ingestion: if-expression post materializes loss-free with obligations":
    let symRef = SubjectSymbolRef(relativeModulePath: "subject/p.nim",
                                  functionName: "p")
    let (outcome, entry) = materializeExternalIR(symRef,
      resolverFromContent(SourceIfExprPost))
    # Not the lossy refusal ("axiom spec expression has no IR translation")
    check outcome == moMaterialized
    check entry.entry.name == "p"
    check entry.entry.expectedObligation == true
    check entry.funcDef.preConditions.len == 1
    check entry.funcDef.postConditions.len == 1
    # The spec channel translated loss-free (the lossy-refusal path returns
    # moUnsupportedDeclKind with "axiom spec expression has no IR
    # translation", so reaching moMaterialized with the full claim IS the
    # loss-free-spec observation; the BODY's translationLossFree bit is a
    # separate, pre-existing flag — a bare `= 0` trailing literal marks it).
    # The claim's if-expression is preserved end-to-end:
    let claim = entry.funcDef.postConditions[0]
    check claim.kind == irBinOp and claim.binOp == boEq
    check claim.binRhs.kind == irIf
    check claim.binRhs.ifThen.litVal == 0
    check claim.binRhs.ifElse.litVal == 1

  test "ingestion: the if-expression post candidate is admitted and obligation-bearing":
    let symRef = SubjectSymbolRef(relativeModulePath: "subject/p.nim",
                                  functionName: "p")
    let (outcome, entry) = materializeExternalIR(symRef,
      resolverFromContent(SourceIfExprPost))
    check outcome == moMaterialized
    check classifyCandidateEligibility(entry.entry, entry.funcDef) == elProofCandidate
    let candidates = selectProofCandidates(10, 1, "1.0", initHashSet[string](), @[entry])
    check candidates.anyIt(it.entry.name == "p" and it.entry.origin == soExternalSubject)
