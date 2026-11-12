-- ═══════════════════════════════════════════════════════════════════
-- ax_vacuity_check: Anti-Vacuity Semantic Linter
-- ═══════════════════════════════════════════════════════════════════
-- Lean 4 메타프로그래밍으로 theorem의 proof object를 정적 분석하여
-- sorryAx 의존성 또는 허용되지 않은 axiom 사용을 탐지하고 거부.
--
-- Architecture: Static Anti-Vacuity Gate
--   Nim은 스켈레톤 생성 시 아래 패턴을 주입:
--     theorem foo : True := by ax_vacuity_check bar
--   ax_vacuity_check가 bar theorem의 proof term을 순회하며
--   sorryAx 또는 project-defined axiom 의존성을 거부.
--
-- Policy:
--   - sorryAx 사용 → 즉시 거부 (vacuity 방어)
--   - 허용 목록 외 axiom 사용 → 거부
--   - 허용 axiom: Classical.choice, Quot.sound, propext, funext
--   - Deterministic: 동일 입력 → 동일 출력, I/O 없음
--
-- Guardrails:
--   G1: sorry 사용 금지 (전술 실패 시 Lean 컴파일 에러)
--   G2: 허용 목록 외 axiom 거부 (project-defined axiom ban)
--   G3: I/O, 외부 명령어 없음 (pure tactic)
-- ═══════════════════════════════════════════════════════════════════
import Lean.Elab.Tactic

open Lean Meta Elab Tactic

set_option linter.unusedVariables false

-- ═══════════════════════════════════════
-- Allowlist: 허용된 built-in Lean axiom
-- ═══════════════════════════════════════
-- Lean 4에서 transitive dependency로 나타나는 built-in axiom만 허용.
-- project-defined axiom은 모두 거부.
private def builtinAxiomAllowlist : NameSet :=
  let s : NameSet := {}
  let s := s.insert ``Classical.choice
  let s := s.insert ``Quot.sound
  let s := s.insert ``propext
  let s := s.insert ``funext
  s

-- ═══════════════════════════════════════
-- SorryAx 거부 패턴
-- ═══════════════════════════════════════
-- Lean 4에서 sorry 사용 시 proof term에 나타나는 axiom 이름.
-- 두 가지 형태 모두 탐지 (버전 차이 대응).
private def isSorryAx (n : Name) : Bool :=
  n == ``sorryAx || n.toString == "sorryAx" ||
  n.toString == "Lean.sorryAx"

-- ═══════════════════════════════════════
-- Expression에서 모든 상수 이름 수집
-- ═══════════════════════════════════════
-- Expr.getUsedConstants로 expression tree를 순회하여
-- 참조된 모든 constant name을 수집.
private def collectConstants (e : Expr) : Array Name :=
  e.getUsedConstants

-- ═══════════════════════════════════════
-- Axiom 여부 판별
-- ═══════════════════════════════════════
-- Environment에서 constant info를 조회하여 axiom 여부 확인.
private def isAxiomConst (n : Name) : MetaM Bool := do
  let env ← getEnv
  match env.find? n with
  | some (.axiomInfo _) => pure true
  | _ => pure false

-- ═══════════════════════════════════════
-- Vacuity check 핵심 로직
-- ═══════════════════════════════════════
-- 지정된 theorem의 proof term과 type을 순회하여
-- sorryAx 또는 허용되지 않은 axiom 의존성을 탐지.
-- contaminated 시 offending constant name을 반환.
private def checkTheoremVacuity (thmName : Name) : MetaM (Option Name) := do
  let info ← getConstInfo thmName

  -- Type에서 상수 수집
  let typeConstants := collectConstants info.type

  -- Proof term에서 상수 수집 (axiom/opaque에는 value 없음)
  let valueConstants := match info with
    | .thmInfo val => collectConstants val.value
    | .defnInfo val => collectConstants val.value
    | _ => #[]

  let allConstants := typeConstants ++ valueConstants

  for c in allConstants do
    -- 1. sorryAx 탐지 (vacuity 방어)
    if isSorryAx c then
      return some c

    -- 2. 허용 목록 외 axiom 탐지
    if ← isAxiomConst c then
      if !builtinAxiomAllowlist.contains c then
        return some c

  return none

-- ═══════════════════════════════════════
-- Tactic Syntax
-- ═══════════════════════════════════════
-- Usage: theorem foo : True := by ax_vacuity_check bar
-- bar theorem의 proof object를 분석하여 vacuity 검증.
syntax "ax_vacuity_check" ident : tactic

-- ═══════════════════════════════════════
-- Tactic Elaboration
-- ═══════════════════════════════════════
elab_rules : tactic | `(tactic| ax_vacuity_check $name:ident) => do
  -- Resolve the identifier in the current namespace/open scopes so that
  -- theorems declared inside a `namespace ... end` block can be referenced
  -- by their short name from within the same namespace.
  let thmName ← resolveGlobalConstNoOverload name

  -- Vacuity check 실행
  match ← checkTheoremVacuity thmName with
  | some offending =>
    -- contaminated: offending constant name 포함 에러 메시지
    throwError s!"ax_vacuity_check: theorem '{thmName}' depends on prohibited constant '{offending}'"
  | none =>
    -- clean: goal close (goal은 True여야 함)
    evalTactic (← `(tactic| trivial))
