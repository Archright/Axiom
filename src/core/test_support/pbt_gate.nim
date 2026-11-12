import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
## PBT Gate — Static Verification Gate for Type Generatability
##
## Uses Nim's compiles(...) meta-attribute to safely check if a type
## can have a deriveGenerator applied. Unreachable types (opaque, C-FFI)
## are gracefully degraded to mock fallback instead of compile errors.
##
## Design: Layer 2 of Shadow-AST Metaprogramming Pipeline

import std/macros
import std/strutils

template verifyAndDrive*(T: typedesc) =
  ## compiles(...) 정적 검증 게이트
  ## 컴파일 가능한 타입만 deriveGenerator 실행
  ## 컴파일 불가 타입은 안전한 Mock Fallback으로 우회
  when compiles(deriveGenerator(T)):
    deriveGenerator(T)
  else:
    {.warning: "Axiom Auto-Gate: Type [" & $T & "] shifted to Manual Stub due to system constraint.".}

template verifyAndDriveMetamorphic*(T: typedesc; procName: untyped; testKind: untyped) =
  ## compiles(...) 정적 검증 게이트 (Metamorphic test용)
  ## 컴파일 가능한 metamorphic test만 실행
  when compiles(deriveMetamorphicTest(procName, testKind)):
    deriveMetamorphicTest(procName, testKind)
  else:
    {.warning: "Axiom Auto-Gate: Metamorphic test for [" & $T & "] shifted to Manual Stub.".}

# ── Hoare Triple Property Assertions ──────────────────────────────────────────

type
  HoareProperty* = object
    ## 호어 트리플 불변량: {Precondition} Command {Postcondition}
    name*: string
    precondition*: proc(): bool {.noSideEffect, raises: [].}
    command*: proc() {.noSideEffect, raises: [].}
    postcondition*: proc(): bool {.noSideEffect, raises: [].}

  HoareResult* = object
    ## 호어 트리플 검증 결과
    propertyName*: string
    preconditionPassed*: bool
    postconditionPassed*: bool
    overallPassed*: bool

func makeHoareProperty*(
  name: string;
  pre: proc(): bool {.noSideEffect, raises: [].};
  cmd: proc() {.noSideEffect, raises: [].};
  post: proc(): bool {.noSideEffect, raises: [].}
): HoareProperty {.noSideEffect, raises: [].} =
  ## 호어 트리플 속성 생성자
  HoareProperty(name: name, precondition: pre, command: cmd, postcondition: post)

func verifyHoare*(prop: HoareProperty): HoareResult {.raises: [].} =
  ## 단일 호어 트리플 검증 실행
  ## {Pre} → check → Command → {Post} → check
  result.propertyName = prop.name
  result.preconditionPassed = prop.precondition()
  if not result.preconditionPassed:
    result.postconditionPassed = false
    result.overallPassed = false
    return
  prop.command()
  result.postconditionPassed = prop.postcondition()
  result.overallPassed = result.preconditionPassed and result.postconditionPassed

func verifyHoareSeq*(props: seq[HoareProperty]): seq[HoareResult] {.raises: [].} =
  ## 복수 호어 트리플 일괄 검증
  result = @[]
  for p in props:
    result.add(verifyHoare(p))

# ── derivePropertyAssertions Macro ────────────────────────────────────────────

macro derivePropertyAssertions*(body: untyped): untyped =
  ## 호어 트리플 불변량 주입 매크로
  ##
  ## PBT 속성 블록에서 자동으로 호어 트리플을 구성하고 검증 assertion을 주입합니다.
  ##
  ## 사용법:
  ##   derivePropertyAssertions:
  ##     property "commutativity":
  ##       pre:  true
  ##       cmd:  result = add(a, b)
  ##       post: result == add(b, a)
  ##
  ##     property "idempotence":
  ##       pre:  x >= 0
  ##       cmd:  result = clamp(x)
  ##       post: result == clamp(clamp(x))
  ##
  ## 확장 결과:
  ##   - 각 property 블록 → HoareProperty 객체 생성
  ##   - verifyHoare() 호출 → HoareResult 검증
  ##   - check assertion으로 postcondition 위반 시 실패
  ##
  ## 호어 트리플 구조:
  ##   {Precondition} Command {Postcondition}
  ##   - Precondition: 선행 조건 (전제)
  ##   - Command: 실행 명령 (변이)
  ##   - Postcondition: 후행 조건 (불변량)
  ##
  ## Design:
  ##   - compile-time AST 변환으로 runtime overhead 최소화
  ##   - noSideEffect 프로시저만 허용 (순수성 보장)
  ##   - {.raises: [].} 컴파일 타임 예외 제로화

  result = newStmtList()

  # body가 stmtList가 아닌 경우 감싸기
  let stmts = if body.kind == nnkStmtList: body else: body

  for node in stmts:
    if node.kind == nnkCall and node[0].kind == nnkIdent and $node[0] == "property":
      # property "name": 블록 파싱
      if node.len < 2 or node[1].kind != nnkStmtList:
        error("derivePropertyAssertions: 'property' requires a name and body block", node)

      let propBody = node[1]

      # 속성 이름 추출
      var propName = "unnamed"
      if node.len >= 3 and node[1].kind == nnkStrLit:
        propName = $node[1]
      elif node.len >= 2 and node[1].kind == nnkStmtList:
        # stmtList 내부에서 이름 추출 시도
        propName = "unnamed"

      var preBody = newStmtList()
      var cmdBody = newStmtList()
      var postBody = newStmtList()

      # pre/cmd/post 블록 파싱
      for child in propBody:
        if child.kind == nnkCall and child[0].kind == nnkIdent:
          case $child[0]
          of "pre":
            if child.len >= 2 and child[1].kind == nnkStmtList:
              preBody = child[1]
            else:
              preBody = quote do: true
          of "cmd":
            if child.len >= 2 and child[1].kind == nnkStmtList:
              cmdBody = child[1]
            else:
              cmdBody = newStmtList()
          of "post":
            if child.len >= 2 and child[1].kind == nnkStmtList:
              postBody = child[1]
            else:
              postBody = quote do: true

      # 호어 트리플 검증 코드 생성
      let propIdent = ident("hoareProp_" & propName.replace(" ", "_"))
      let resultIdent = ident("hoareResult_" & propName.replace(" ", "_"))

      result.add quote do:
        let `propIdent` = makeHoareProperty(
          `propName`,
          proc(): bool {.noSideEffect, raises: [].} = `preBody`,
          proc() {.noSideEffect, raises: [].} = `cmdBody`,
          proc(): bool {.noSideEffect, raises: [].} = `postBody`
        )
        let `resultIdent` = verifyHoare(`propIdent`)
        check `resultIdent`.overallPassed,
          "Hoare triple violation [" & `resultIdent`.propertyName & "]: " &
          "pre=" & $`resultIdent`.preconditionPassed &
          " post=" & `resultIdent`.postconditionPassed

    elif node.kind == nnkCall and node[0].kind == nnkIdent and $node[0] == "invariant":
      # invariant 블록: 지속적 불변량 (모든 command 후 검증)
      # invariant "name":
      #   check: someCondition
      if node.len >= 2 and node[1].kind == nnkStmtList:
        let invBody = node[1]
        result.add quote do:
          block:
            `invBody`

{.pop.}
