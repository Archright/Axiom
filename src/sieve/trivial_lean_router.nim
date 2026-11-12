import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
## Type-Level Encoding Fast-Path Router (Refinement Typed IR v5)
##
## 분류 조건: Lean 커널이 정제 타입 정의를 수락하는가
## 전술(bv_decide, omega) 미사용 — TCB = AST 스캐너 + Lean 커널만
##
## Pipeline: classifyTypeLevel → irToLeanRefinedModule → LSP type-check
## If Lean kernel accepts the refined definition, rfl verification suffides.
## Otherwise, fall back to Z3 BMC (tlComplex).

import std/options
import std/strutils
import core/trusted/axiom_ir
import core/trusted/ir_to_lean
import core/lean_lsp_types
import core/results
import infrastructure/logging_facade
import verification/lean_lsp_protocol  ## exports checkLeanSource

# ── Types ───────────────────────────────────────────────────────────────────

type
  LeanRouterError* = object of CatchableError

  TypeLevelLayer* = enum
    tlTypeLevelEncoding  ## 정제 타입으로 rfl 검증 가능 (전제조건 포함)
    tlComplex            ## Z3 BMC 위임

  TypeLevelRouterVerdict* = object
    layer*: TypeLevelLayer
    leanSource*: string
    compiled*: bool
    axiomsUsed*: seq[string]  ## Axiom names captured from `#print axioms` (Stage 1.5 gate)
    error*: string

# ── Pre-processing filter ──────────────────────────────────────────────────

func hasUnsupportedType*(t: IRType): bool {.raises: [].} =
  ## Returns true for IR types that cannot be Lean-encoded.
  ## irtBitVec64, irtBool, irtString, irtList are all supported.
  ## Future unsupported types (e.g. irtFloat) would return true here.
  false

func hasStringOrListType*(t: IRType): bool {.raises: [].} =
  ## Returns true for irtString or irtList types.
  case t.kind
  of irtBitVec64, irtBool, irtEnum, irtVariant: false
  of irtString, irtList: true

func classifyTypeLevel*(f: IRFuncDef): bool {.gcsafe, raises: [].} =
  ## 전처리 필터: IR에 제약이 있고, 구조적으로 단순한지 확인.
  ## 복잡한 함수는 Lean 코드 생성 자체를 건너뜀 (오버헤드 = 0).
  ##
  ## bitvec/bool functions: reject irCall, irRecCall, irLoop, boMul.
  ## string/list functions: stricter — only irVar, irIf, irCase, irLet,
  ##   irLit, irStringLit, irFloatLit allowed (no irBinOp, irUnaryOp).

  # Unsupported types → reject immediately
  for p in f.params:
    if hasUnsupportedType(p.ty):
      return false
  if hasUnsupportedType(f.retType):
    return false

  # Detect string/list types for stricter body complexity check
  var hasStrOrList = hasStringOrListType(f.retType)
  if not hasStrOrList:
    for p in f.params:
      if hasStringOrListType(p.ty):
        hasStrOrList = true
        break

  # 전제조건이 하나도 없으면 type-level encoding 불가
  var hasConstraints = f.preConditions.len > 0
  if not hasConstraints:
    for p in f.params:
      if p.constraint.isSome:
        hasConstraints = true
        break
  if not hasConstraints:
    return false

  # 복잡한 구조 거부 (즉시 tlComplex)
  if f.isRecursive:
    return false

  # 바디 순회로 복잡한 노드 감지.
  # strict=true (string/list): reject ALL irBinOp, irUnaryOp — only
  #   structural patterns (irIf, irCase, irLet) and leaves allowed.
  # strict=false (bitvec/bool): original — only reject irCall, irRecCall,
  #   irLoop, and irBinOp with boMul.
  proc hasComplexNode(e: IRExpr, strict: bool): bool {.raises: [].} =
    if e == nil: return false
    case e.kind
    of irCall:    return true
    of irRecCall: return true
    of irLoop:    return true
    of irBinOp:
      if strict: return true
      if e.binOp == boMul: return true
      return hasComplexNode(e.binLhs, strict) or hasComplexNode(e.binRhs, strict)
    of irUnaryOp:
      if strict: return true
      return hasComplexNode(e.unaryArg, strict)
    of irLet:     return hasComplexNode(e.letVal, strict) or hasComplexNode(e.letBody, strict)
    of irIf:      return hasComplexNode(e.ifCond, strict) or hasComplexNode(e.ifThen, strict) or hasComplexNode(e.ifElse, strict)
    of irCase:
      for branch in e.caseBranches:
        if hasComplexNode(branch.body, strict): return true
      return hasComplexNode(e.caseDefault, strict)
    else:         return false

  return not hasComplexNode(f.body, hasStrOrList)

# ── Router (I/O boundary: LSP client) ──────────────────────────────────────

proc routeToTypeLevel*(f: IRFuncDef,
                       lspClient: LeanLspClient): TypeLevelRouterVerdict {.raises: [LeanRouterError].} =
  ## 1. 전처리 필터
  if not classifyTypeLevel(f):
    return TypeLevelRouterVerdict(layer: tlComplex, compiled: false)

  {.push warning[BareExcept]: off.}
  try:
    ## 2. 정제 타입 Lean 코드 생성
    let leanResult = irToLeanRefinedModule(f)
    if leanResult.isErr:
      logWarn("trivial_lean_router",
        "irToLeanRefinedModule failed (" & leanResult.error &
        ") — falling back to Z3 BMC")
      return TypeLevelRouterVerdict(
        layer: tlComplex,
        compiled: false,
        error: "irToLeanRefinedModule: " & leanResult.error
      )
    let leanSource = leanResult.get

    ## 2b. Defensive sorry gate — the type-level path is sorry-free by
    ##     construction (emits only `def` with (h_pre : Prop) params), but this
    ##     substring gate adds defense-in-depth: if the generated Lean source ever
    ##     contains "sorry"/"sorryAx", reject and fall through to Z3 BMC (fail-open).
    if leanSource.contains("sorry") or leanSource.contains("sorryAx"):
      logWarn("trivial_lean_router",
        "generated Lean source contains sorry/sorryAx — falling back to Z3 BMC")
      return TypeLevelRouterVerdict(
        layer: tlComplex,
        leanSource: leanSource,
        compiled: false,
        error: "generated Lean source contains sorry/sorryAx"
      )

    ## 3. LSP 타입 체크 + `#print axioms` axiom-aware gate (EOF 배리어)
    let uri = "file:///trivial_router_" & f.name & ".lean"
    let checkResult = checkLeanSourceWithAxioms(lspClient, uri, f.name, leanSource)

    ## 4. LSP 결과 처리
    if checkResult.isErr:
      logWarn("trivial_lean_router",
        "LSP unavailable/failed (" & checkResult.error &
        ") — falling back to Z3 BMC")
      return TypeLevelRouterVerdict(
        layer: tlComplex,
        leanSource: leanSource,
        compiled: false,
        error: "LSP check failed: " & checkResult.error
      )
    let outcome = checkResult.get
    let compiled = outcome.compiled
    return TypeLevelRouterVerdict(
      layer: if compiled: tlTypeLevelEncoding else: tlComplex,
      leanSource: leanSource,
      compiled: compiled,
      axiomsUsed: outcome.axiomsUsed,
      error: if not compiled: "Lean kernel rejected refined definition (or axiom set unsafe)" else: ""
    )
  except CatchableError as e:
    raise newException(LeanRouterError, "LSP check failed: " & e.msg)
  except Exception as e:
    raise newException(LeanRouterError, "LSP check failed: " & e.msg)
  {.pop.}

{.pop.}
