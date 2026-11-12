-- ═══════════════════════════════════════════════════════════════════
-- ax_solve: Axiom's Deterministic Tactic Engine
-- ═══════════════════════════════════════════════════════════════════
-- Lean 4 메타프로그래밍(MetaM/TacticM)으로 목표의 AST를 분석하고
-- 결정론적으로 전술을 선택하는 커스텀 전술.
--
-- Architecture: Internal Semantic Synthesis
--   Nim은 스켈레톤 생성 시 `by ax_solve` 한 줄만 주입.
--   ax_solve가 목표 타입/가설을 분석하여 최적 전술을 자동 선택.
--
-- Decision Tree:
--   1. intros (∀ 목표 해소)
--   2. whnf → False? → contradiction (sorry 없음)
--   3. 산술(Nat/Int)? → omega → simp only; omega
--   4. rfl → simp (sorry 없음 — 전술 실패 시 Lean 컴파일 에러)
--
-- Guardrails:
--   G1: intros 선행 (가설 이름 추측 불필요)
--   G3: try/catch 안전 패턴 (수동 get/set 금지 — tactic state 오염 방지)
--   G4: simp only 타겟팅 (bare simp 남용 방지)
-- ═══════════════════════════════════════════════════════════════════
import Lean.Elab.Tactic

open Lean Meta Elab Tactic

set_option linter.unusedVariables false

-- ═══════════════════════════════════════
-- Helper: 가설 컨텍스트에서 모순 탐지
-- ═══════════════════════════════════════
-- 로컬 가설들 중 P ∧ ¬P 쌍 또는 False 타입이 존재하는지 확인.
-- contradiction 전술을 안전하게 호출하기 전의 전제 검사.
private def hasContradictionInContext : TacticM Bool := do
  let lctx ← getLCtx
  let mut propHyps : Array Expr := #[]
  for decl in lctx do
    if decl.isImplementationDetail then continue
    try
      if ← isProp decl.type then
        propHyps := propHyps.push (← whnf decl.type)
    catch _ => pure ()
  -- 모든 가설 쌍에 대해 P와 ¬P 검사
  for i in [:propHyps.size] do
    for j in [i+1:propHyps.size] do
      let pi := propHyps[i]!
      let pj := propHyps[j]!
      -- ¬P = P → False
      if pj.isAppOfArity ``Not 1 then
        if ← isDefEq pi pj.appArg! then return true
      if pi.isAppOfArity ``Not 1 then
        if ← isDefEq pj pi.appArg! then return true
      -- False 직접
      if pi.isConstOf ``False then return true
      if pj.isConstOf ``False then return true
  return false

-- ═══════════════════════════════════════
-- Helper: 산술 목표 감지
-- ═══════════════════════════════════════
-- 목표 타입이 Nat/Int의 비교(LE/GE/LT/GT) 또는 등식(Eq/Ne)인지 확인.
-- omega 전술이 처리할 수 있는 목표 범위 판별.
private def isArithmeticGoal (goalType : Expr) : MetaM Bool := do
  let ty ← whnf goalType
  match ty.getAppFn.constName? with
  | some ``LE.le => pure true
  | some ``GE.ge => pure true
  | some ``LT.lt => pure true
  | some ``GT.gt => pure true
  | some ``Eq =>
    let args := ty.getAppArgs
    if args.size ≥ 2 then
      let lhsType ← inferType args[1]!
      let lhsReduced ← whnf lhsType
      match lhsReduced.getAppFn.constName? with
      | some ``Nat => pure true
      | some ``Int => pure true
      | _ => pure false
    else pure false
  | some ``Ne =>
    let args := ty.getAppArgs
    if args.size ≥ 2 then
      let lhsType ← inferType args[1]!
      let lhsReduced ← whnf lhsType
      match lhsReduced.getAppFn.constName? with
      | some ``Nat => pure true
      | some ``Int => pure true
      | _ => pure false
    else pure false
  | _ => pure false

-- ═══════════════════════════════════════
-- ax_solve 전술 엔진
-- ═══════════════════════════════════════
elab "ax_solve" : tactic => do
  -- ═══ G1: intros 선행 ═══
  -- by ax_solve가 ∀ S S', ... → ... 형태의 목표에 직면하면
  -- 먼저 intros로 모든 양자화 변수를 가설로 만듦.
  let goal ← getMainGoal
  if (← goal.getType).isForall then
    try evalTactic (← `(tactic| intros))
    catch _ => pure ()

  -- ═══ Phase 1: whnf 극단 환원 → False 감지 ═══
  -- invariant := False 패턴의 핵심 해결 메커니즘.
  -- whnf가 목표를 False로 환원하면:
  --   - 가설에서 모순(P ∧ ¬P 또는 False) 존재 → contradiction
  --   - 모순 없으면 전술 실패 (sorry 사용 금지 — vacuity ban 때문)
  let goal ← getMainGoal
  let goalType ← goal.getType
  let reduced ← whnf goalType
  if reduced.isConstOf ``False then
    if ← hasContradictionInContext then
      try
        evalTactic (← `(tactic| contradiction))
        return
      catch _ => pure ()
    -- sorry 금지: 전술 실패로 Lean 컴파일 에러 유도
    -- 이것이 네거티브 뮤테이션 테스트의 핵심 방어 메커니즘
    throwError "ax_solve: goal is False but no contradiction in context"

  -- ═══ Phase 2: 산술 목표 → omega ═══
  -- Nat/Int의 비교/등식에 omega 전술 적용.
  -- G4: bare simp 대신 simp only <;> omega cascade 사용.
  if ← isArithmeticGoal goalType then
    try
      evalTactic (← `(tactic| omega))
      return
    catch _ => pure ()
    try
      evalTactic (← `(tactic| simp only <;> omega))
      return
    catch _ => pure ()

  -- ═══ Phase 3: trivial (with vacuity guard) ═══
  -- True, trivial implication 등 즉시 닫히는 목표.
  -- 단, 가설이 없고 목표가 True이면 공허한 증명으로 판단하여 거부.
  -- 복합 증명의 중간 subgoal(가설 존재)은 허용.
  let goal ← getMainGoal
  let goalType ← goal.getType
  let reduced ← whnf goalType
  let lctx ← getLCtx
  let mut hasHypotheses := false
  for decl in lctx do
    if decl.isImplementationDetail then continue
    try
      if ← isProp decl.type then
        hasHypotheses := true
        break
    catch _ => pure ()
  if reduced.isConstOf ``True && !hasHypotheses then
    throwError "ax_solve: vacuous proof detected — goal is True with no hypotheses"
  try
    evalTactic (← `(tactic| trivial))
    return
  catch _ => pure ()

  -- ═══ Phase 4: rfl ═══
  -- 정의적 동치(definitional equality)로 닫히는 목표.
  try
    evalTactic (← `(tactic| rfl))
    return
  catch _ => pure ()

  -- ═══ Phase 5: simp ═══
  -- @[simp] lemma로 닫히는 목표.
  try
    evalTactic (← `(tactic| simp))
    return
  catch _ => pure ()

  -- ═══ Phase 6: 전술 실패 ═══
  -- 모든 전술이 실패하면 Lean 컴파일 에러 유도.
  -- sorry 사용 금지: vacuity ban이 sorry를 허용하지 않음.
  -- Nim 측에서 leanKernelReplayVerified := false로 설정됨.
  throwError "ax_solve: no tactic succeeded for this goal"
