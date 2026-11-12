{.push raises: [].}
import core/trusted/layer_declaration
axiomLayer "domain"
import core/trusted/axiom_pragmas
import std/macros
import std/strutils
# ── 절대 경로 패턴 상수 ──
const AbsolutePathPatterns* = [
  "/home/", "/Users/", "C:\\", "/root/", "/opt/runner/"
]
func checkPathInvariant(node: NimNode) =
  ## AST 내 문자열 리터럴 노드만 필터링하여 절대 경로 패턴 검사
  ## 디스크 I/O 없음 — 컴파일러가 이미 파싱한 AST 활용
  case node.kind
  of nnkStrLit, nnkRStrLit, nnkTripleStrLit:
    let strVal = node.strVal
    for pat in AbsolutePathPatterns:
      if pat in strVal:
        error("HARDCODED ABSOLUTE PATH DETECTED: " & strVal &
              " | Use runtime path resolution (getAppDir)")
  else:
    for child in node:
      checkPathInvariant(child)
func emitDebtHints(node: NimNode) {.used.} =
  ## {.axiomDebt: "DEBT#243".} 발견 시 컴파일러 힌트로 메타데이터 방출
  ## 파일 시스템에 직접 쓰지 않음 → 병렬 컴파일 안전
  if node.kind == nnkPragmaExpr:
    for pragma in node:
      if pragma.kind == nnkCall and pragma[0].strVal == "axiomDebt":
        let debtId = pragma[1].strVal
        let msg = "AXIOM_DEBT:" & debtId & "|" & $node.lineInfoObj.line
        hint(msg)
macro axiomCollect*(moduleBody: untyped): untyped =
  ## 모듈 AST를 한 번만 순회하여:
  ## 1. {.axiomDebt.} pragma 탐지 → 힌트 스트림 방출
  ## 2. 문자열 리터럴 절대 경로 검사 → 컴파일 에러
  ## -d:axiomScan 플래그가 없으면 no-op (제로 오버헤드)
  result = moduleBody
  when defined(axiomScan):
    for node in result:
      emitDebtHints(node)
      checkPathInvariant(node)

# end emitDebtHints
