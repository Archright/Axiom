# WP4-d Open Issue — 같은 시그니처, 다른 scope 의 심볼 identity

EXPERIMENT_ID=act2-wp4d-symbol-identity
STATUS=OPEN (판정 보류 — WP5/WP6 topology scope-awareness 에서 검토)

## 문제

decl-text digest (다중줄 시그니처 SHA-256) 는 **시그니처가 다른** duplicate 를
분리한다 (getBitsBE func/template → PASS). 그러나 **시그니처가 완전히 같은**
정의들이 **서로 다른 scope/branch** 에 존재하면 decl-text 가 동일해져 분리되지
않는다.

## 실측 사례 (모두 같은 module, 같은 이름, 같은 시그니처 — 그러나 다른 scope)

nim-stew:
- `interval_set::one` — line 218/240/244/251 (서로 다른 generic 블록)
- `bitops2::checkedScan` — line 206/253 (플랫폼 when 브랜치)
- `bitops2::bitScan` — line 220/258 (플랫폼 when 브랜치)
- `lentutils::maybeLent` — line 20/24 (게이트/특수화)
- `shims.macros::generator` — line 440/450 (다른 scope iterator)

Axiom self:
- `core.trusted.contract_synthesis::walk` — 19/63/273
- `verification.dependency_analyzer::dfs` — 151/211
- `verification.obligation.post_satisfaction::peel` — 202/255
- `infrastructure.native_cgroup::createCgroupSlice*` — 95/238
- `infrastructure.native_cgroup::defaultConfig*` — 206/255
- `gate.runners.debt_scan_gate::walkRec` — 165/222 (중첩 proc)
- `gate.runners.decision_binding_gate::walkRec` — 249/303 (중첩 proc)
- `verification.solver.z3_pool::z3WorkerHasData` — 39/51
- `gate.runners.runner_process_pool::drainAvailableBytes` — 213/238
- 등

## 왜 discriminator 로 분리하면 안 되는가

Nim 언어 규칙상 **같은 scope 에 동일 시그니처 중복 정의는 컴파일 오류**다.
이들이 공존하는 이유는 각자 서로 다른 scope/branch(플랫폼 when 블록, 중첩
proc, generic 특수화, forward declaration 쌍) 에 있기 때문이다.

또한 cst_offset_extractor / native_cgroup 의 경우는 **forward declaration +
implementation** 쌍으로, 동일 함수의 시그니처 재선언이다. 이 둘을 "다른 심볼"로
분리하면 오히려 잘못이다 (같은 digest 로 병합되는 게 맞다).

## Open Issue 로 기록하는 이유 (사용자 추가 규칙 준수)

> WP0-b/c 에서 확정된 identity 를 제외하고, 새로운 identity 후보가 발견되면
> "현재 계약에 이미 포함됨? → yes 재사용 / no → Open Issue 로 기록, 임의 편입 금지"

여기서 요구되는 것은 "같은 시그니처 + 다른 scope" 를 구분하는 identity 이다.
이는 **D1~D4 에 정의된 canonical identity 범위 밖**이며, 현재 확정된
discriminator(decl-text) 만으로는 불가능하다. 따라서:

- 임의로 더 큰 discriminator(파라미터 AST, IR signature 등 — sem 이후라 scan-time 불가)
  를 즉석 편입하지 **않는다**.
- 대신 scope-awareness (line-based scanner 가 when/블록/중첩 proc 을 scope 로
  구분하는가) 를 WP5/WP6 topology 에서 판정한다.

## 판정 포인트 (후속 WP)

1. Axiom topology_parser.nim 이 scope/블록을 인식하는가?
   - 인식한다 → 동일 decl-text 도 scope 로 분리 → 문제 없음 (discriminator 와
     직교 보완)
   - 인식 못 한다 → 같은 nodeId 로 평탄화 → WP6 에서 scope-aware disambiguation
     필요. 단 이때도 decl-text 가 같은 정의끼리만 각별 취급.

## 현재 blocker 와의 관계

현재 blocker(getBitsBE) 는 func vs template 의 **다른 시그니처** collision 이며,
decl-text digest 로 **완전 해소**된다. Open Issue 는 WP4-d 진행을 막지 않는다.
