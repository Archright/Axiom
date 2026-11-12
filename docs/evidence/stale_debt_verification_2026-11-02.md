# debt_integrity_gate STALE 10건 — 등록 서술 항목별 검증 기록 (2026-11-02)

> **종류**: 검증 기록 문서 (verification record). **이 문서는 결정을 대리하지 않는다.**
> D3(증거 기반 close vs registration-class 예외 설계 vs 혼합·보류)의 권한은 인간 전용이며
> 본 문서는 어느 옵션도 권고하지 않는다 — 판정·관측·증거의 나열만을 담는다
> (`docs/evidence/nimtry_ratchet_budget_request_2026-11-02.md` §5·§7 형식 준수).
> **Date**: 2026-11-02 · **Branch**: `docs/stale-debt-verification-2026-11-02`
> (worktree off `origin/main` @ `291cb2f081eb3f25a74b78db2d3fdd36ab4a731e`)
> **Scope**: 본 문서 1건 — `data/debt_registry.json`·게이트 코드·Makefile·`.github/**`·`src/gate/**` 수정 0건.
> 본 문서는 close·레지스트리 수정·게이트 변경을 수행하지 않는다(인간 소관).
> **검증 대상**: DEBT-CI#003, DEBT#432, #472, #496, #504, #505, #506, #507, #509, #512 (open 10건).

---

## §0. 측정 환경

- **기준 HEAD**: `291cb2f081eb3f25a74b78db2d3fdd36ab4a731e` (작업 시작 시점 origin/main,
  merge of PR #1194). 모든 관측은 이 트리의 격리 worktree에서 수행했다.
- **worktree**: `<user-home>/worktrees/stale-debt-verify` (저장소 외부 경로 — repo 내
  `.worktrees/` 미사용). branch `docs/stale-debt-verification-2026-11-02`.
- **참고 관측**: main clone의 로컬 HEAD는 `f0aecfe0d`로 origin/main보다 뒤처져 있었고, 요청서
  문서(#1190)는 로컬 working tree에 없었다 — 본 검증은 base 커밋 트리에서 `git show`로 직접
  확보해 진행했다.
- **바이너리 재빌드** (worktree 내, Nim 2.2.10, `bin/` 미추적):
  - `make ci-compile-ax ci-compile-gate-hook` (정의: `ci/checker.mk:529-530`, `:523-524`;
    Makefile이 `ci/checker.mk`를 include — Makefile:11)
  - `make bin/nimtry` (룰: Makefile:146-147) · `make bin/debt_engine` (룰: Makefile:156-157)
  - `nim c --hints:off -d:release -o:bin/debt_integrity_gate src/gate/runners/debt_integrity_gate.nim`
    (make 룰 부재 — gate runner 컴파일 관례와 동일 형식)
  - 빌드 완료 확인: `BOOTSTRAP_ALL_OK` (4종 모두 존재·실행 가능)

## §1. 판정 기준 (전 항목에 동일 적용)

레지스트리 `description`(최신 REVERIFY 포함)에서 검증 가능한 클레임을 추출해, base 트리
(`291cb2f08`)의 코드·Makefile·workflow 정적 관측과 대조한다.

| 판정 | 정의 |
|---|---|
| **still-holds** | 등록 서술이 기술하는 결함/상태가 base 트리에서 동일하게 관측된다 (핵심 클레임 전부가 관측과 일치; 라인 이동 등 표면 드리프트는 비고에 기록). |
| **partially-holds** | 클레임의 일부는 관측과 일치하고 일부는 불일치다 (불일치 항목과 그 착지 근거를 명시). |
| **resolved** | 서술된 결함이 base 트리에서 더 이상 관측되지 않는다 (해소 근거·시점을 명시). |
| **unverifiable** | 핵심 클레임이 정적 트리 관측만으로 판정 불가다 (런타임·외부 상태 전제). 하위 클레임 단위의 미재현은 비고로 기록하고 판정에는 부여하지 않는다. |

런타임 역사 클레임(특정 run ID의 관측 등)은 정적 재관측이 원칙적으로 불가하므로, 성립·불성립
어느 쪽으로도 판정하지 않고 비고에 "런타임 역사(정적 재관측 불가)"로 표기한다.

## §2. 재실측 기록 (command → observation → exit)

측정 일시 2026-11-02, 환경 §0. 요청서 §8과 동일한 3-측정을 base 트리에서 재수행했다.

| # | 명령 | 관측 | exit |
|---|---|---|---|
| 1 | `bin/nimtry src/` (= `make check-arch` 본체, Makefile:217) | `PASS — 4249 violations (debt anchored) (errors: 370, warnings: 3879, 14 resolved) (cache: 0 hits, 1328 misses)` | **0** |
| 2 | `bin/debt_integrity_gate` | `nimtry — Active Violations: 4249 / Historical Baseline Cap: 4263`, `Registry: 243 entries (30 open, 0 accepted)`, `Code: 23 {.axiomDebt.} markers found`, **STALE ERROR 10건**(아래 목록) → `10 stale debt(s) — FAIL` | **1** |
| 3 | `bin/debt_engine --validate` (= CI debt-registry-gate와 동일 명령) | `Checks: 1531 total, 1531 passed, 0 failed`, `Metric evaluation: 3 PASS, 1 DRIFT`(nimtry_violations projection=0 vs ledger 1 — advisory), `All debt validation checks passed.` | **0** |

STALE 10건 재확인 목록 (§2 측정 2번의 ERROR 라인 순서 그대로): DEBT-CI#003, DEBT#432,
DEBT#472, DEBT#496, DEBT#504, DEBT#505, DEBT#506, DEBT#507, DEBT#509, DEBT#512 — 요청서 §5
표와 동일하다. WARN 라인은 0건이다. 즉 요청서 §8의 실측이 base 트리에서 그대로 재현됐다.

## §3. 항목별 검증

형식: **등록 클레임**(레지스트리 `description` 원문에서 추출한 검증 가능 클레임의 요약 —
축약 표기는 `[ ]`로 원문 인용), **관측**(base 트리, 파일:라인), **판정**, **비고**.

### 3.1 DEBT-CI#003 — still-holds

- **등록 클레임**: `[both LACK overwrite]` — `runner-pool-acceptance.yml`의 `candidate-arm64`
  업로드(retention-days: 3)와 `ci-bootstrap-artifacts` 업로드(retention-days: 3)에 `overwrite`
  가 없다. consumer는 candidate-arm64 = fail-closed same-run(compile=0, per-file sha256 결속),
  ci-bootstrap-artifacts = fail-open cross-run(`ci-cache-publisher.yml` 존재 가드 + cross-run
  download). admission-check의 두 hot-path site는 sanctioned 형식(`overwrite: true`) 보유.
  (등록은 라인 번호를 브랜치 트리 `4554c48f3` 기준으로 명시하고 pre-#710 main 번호를 괄호 병기.)
- **관측**: `candidate-arm64` 업로드 `.github/workflows/runner-pool-acceptance.yml:915-920`
  (name :919, retention-days: 3 :920), `ci-bootstrap-artifacts` :806-811 (name :810,
  retention-days: 3 :811). 파일 전체에서 `overwrite` 매치 **0건** — 양 site 모두 무 `overwrite`
  유지. consumer: shard 소비 leg가 "pure CONSUMER of candidate-arm64"(:990-996)로 download
  (:1023-1026) 후 per-file sha256 결속·fail-closed 검증(:1029-1049, `CANDIDATE-CONSUME OK
  (aarch64) — compile=0, … products sha256-bound`); `ci-cache-publisher.yml` cross-run
  RUN_ID :210, 부재 시 `[publish-skip]` :233. `admission-check.yml`의 `overwrite: true`는
  :595와 :641(등록 표기 :543/:589에서 라인 이동, sanctioned 형식 존재 유지).
- **판정**: **still-holds** (repo 상태 클레임 전부 관측과 일치).
- **비고**: vendor 문서·2개 run의 충돌 실측(37176994649/37183851918)은 런타임 역사로 정적
  재관측 불가. 등록 서술 자체가 라인 기준을 브랜치 트리로 한정했으므로 main 라인 번호와의
  차이는 드리프트가 아니다.

### 3.2 DEBT#432 — partially-holds

- **등록 클레임** (REVERIFY 2026-10-07, lastVerifiedAt `2026-10-07T00:00:00Z`): ①
  resolve_node_outcome·evidence_propagation·candidate_eligibility·execution_identity_propagation·
  bundle_digest·promotion_semantics·certificate_eligibility·proof_state_machine 8종이
  TESTS_FAST_UNIT(Makefile:78-92)과 CONTRACT_UNIT_TESTS(Makefile:711-720, verify-contract-unit
  G2)에 와이어돼 있다. ② ci-unit-tests 타깃과 CI-job leg는 소멸했다(CI epoch cutover). ③
  `proof_integrity_test.nim`·`test_s1a_lean_golden.nim`·`test_d2_golden.nim`·`test_d2_persist.nim`
  4종은 "tests/unit/에 존재하나 어떤 Makefile lane에도 와이어돼 있지 않다". ④ "no current
  workflow consumes test-fast/verify-contract". ⑤ Makefile은 FROZEN 표면이다.
- **관측**: ① 성립 — 8종 모두 `TESTS_FAST_UNIT` (Makefile:79-86, 변수 선두 :63)과
  `CONTRACT_UNIT_TESTS` (Makefile:750-759, 등록 :711-720에서 라인 이동)에 존재;
  `verify-contract-unit` 타깃 :760, verify-contract fanout :717. ② 성립 — `ci-unit-tests`는
  Makefile·ci/checker.mk에서 매치 0. ⑤ 성립 — Makefile은 `config/repository_surface.json`
  v51 이래 FROZEN 15 열거 멤버("Makefile(실행 게이트 집합 단일 정의점…)"). **③④ 불성립** —
  `.github/workflows/admission-check.yml`가 4종을 `make test-fast-one` 레인으로 실행한다:
  과목 매핑 :1597-1600·매트릭스 :2901-2910(`tests: tests/unit/proof_integrity_test.nim
  tests/unit/test_d2_golden.nim tests/unit/test_d2_persist.nim` + s1a solo lane-0 :2815),
  실행 `make test-fast-one T="$t"` :3562(타깃 정의 Makefile:1036-1039), 과목명
  s1a/proof_integrity/d2_golden/d2_persist 분기 :3554. 착지 커밋: `f12ea744c` 2026-10-08
  "fix(admission)!: wire GO-critical tests into admission verdict (DEBT#432, G2a)" 및
  `b85baabce` 2026-10-09 — 등록 lastVerifiedAt(2026-10-07) 다음 날.
- **판정**: **partially-holds** (①②⑤ 성립, ③④ 불성립).
- **비고**: `verify-contract-unit` 자체는 여전히 어떤 workflow에도 소비되지 않는다
  (`.github/**`에서 `verify-contract` 매치는 주석과 `verify-contract-release-e2e-full`뿐 —
  별개 타깃).

### 3.3 DEBT#472 — still-holds

- **등록 클레임**: certificate-mint (P6)는 skipped gateway-lane job에 대해 허용 사유의
  '존재'만 검증한다(① B-tree epoch manifest의 SL-09 notYet, ② ci-select-decision envelope의
  mode=none). skip 집합의 identity(어느 job이 스킵됐는지·n_skip이 기대치와 일치하는지)는
  검증하지 않는다. SL-09 승격 시 재점검(follow-up only).
- **관측**: `.github/workflows/certificate-mint.yml` 실존(2672행 — 등록 시점 1624행에서 대폭
  성장, blob 갱신). skip 검증 블록 :2080-2124: n_skip 계수 :2086, 사유 존재 검증 — epoch
  manifest `notYetImplementedSlices | index("SL-09")` :2093-2094 또는 `mode == "none"`
  envelope :2117, 미충족 시 fail-closed :2120, OK 메시지는 `skipped $n_skip [$skip_reason]`
  기록만 :2124 — **skip 집합 identity·n_skip 기대치 비교는 존재하지 않는다**. SL-09 미승격:
  `config/policy/epoch_manifest.json`의 `notYetImplementedSlices`에 SL-09 포함 — 재점검
  트리거 미충족.
- **판정**: **still-holds**.
- **비고**: 등록의 스텝 라인(:1381-1417 @ blob 9c4164bb0f)과 :48 주석 위치는 현재 블록
  (:2020-2124)으로 이동 — 로직 내용은 등록 서술과 동일.

### 3.4 DEBT#496 — still-holds

- **등록 클레임**: IR에는 void 타입이 없다(grep irtVoid over axiom_ir.nim: 0매치). statement
  translator는 nnkDiscardStmt/ckDiscardStmt를 drop하고 void형 본체를 거부하지 않고
  irLit(0)+retType=irtBitVec64로 조작한다. axiomImpl은 axiomTryImpl의 hasUnsupportedPatterns
  guard 없이 hardcoded effectKind=Pure·isKern=true로 등록한다. 오늘날 도달 가능성 0 — src/
  에 void 반환 axiomImpl/axiomTryImpl 함수가 없고, lossy materialization은
  translationLossFree=false/bindingUniverseComplete=false로 fail-close된다(semantic facts
  전부 기각, census eligibility 상실, loss-marked 본체의 합성 claim 반입 거부).
- **관측**: `src/core/trusted/axiom_ir.nim`에서 `irtVoid` 매치 **0**. `ast_to_ir.nim`:
  nnkDiscardStmt drop :716-717(등록과 동일 라인), irLit(0) fallback :970-971(등록 :969-970,
  1행 이동), convertFuncDef void 기본 `retType: irTypeBitVec64(), body: irLit(0)` :1371-1372
  (등록 :1367-1370, 이동), ckDiscardStmt drop :1262(등록 :1255-1256, 이동).
  `axiom_pragmas_macros.nim`: axiomImpl :674(등록 :674-712 선두 일치), `let isKern = true`
  :685·`let effectKind = Pure` :686(hardcoded), hasUnsupportedPatterns guard는 axiomTryImpl
  측에만 존재 — 정의 :753, 적용 :764(등록 :753-761). fail-close 체인:
  `src/verification/obligation/semantic_environment.nim:220-225` Gate 1 —
  `not (completeness.translationLossFree and completeness.bindingUniverseComplete)` →
  `return result  # reject ALL facts — empty environment`(등록 :219-222, 소폭 이동);
  `external_ir_materializer.nim` lossFree/bindingComplete 플래그 부여 :573-579(등록
  :293-302에서 이동); `candidate_eligibility.nim`(등록 경로 `src/verification/batch_uap/` →
  현재 `src/verification/obligation/`으로 이동) buvLossyPropositionRegion :362/:426·
  buvLossyBindingRegion :364/:428·`result.rejection = some(crrSemanticUnresolvedFact)` :502.
  void 반환 스캔: `{.axiomImpl.}`/`{.axiomTryImpl.}` 사이트 128건 중 `: void` 반환 **0건**
  (등록의 2026-10-08 스캔과 동일 결과).
- **판정**: **still-holds** (결함 메커니즘·봉쇄 체인 전부 관측과 일치).
- **비고**: 다수 라인 앵커 이동 + 파일 2건 재배치(candidate_eligibility, 등록 텍스트는
  경로를 파일명만 표기) 표면 드리프트. 등록이 인용한 `axiom_engine.nim:1558-1563`(합성 claim
  carrier의 loss-marked 본체 반입 거부) 범위는 현재 무관한 코드(TOML 검증기)이고 파일은
  4,700행대로 성장 — 동일 주제의 현재 위치는 합성 carrier의 loss 플래그 결합부
  :3659-3666(`composite.translationLossFree = outerFd.translationLossFree and …`, fail-closed
  주석 :3034/:3226/:3453)과 loss-marked placeholder 언급 :3868이다. 재현 스크립트 2종은
  gitignored(tmp/)라 트리에서 비재실행 — 기재된 재현 결과는 런타임 역사.

### 3.5 DEBT#504 — still-holds

- **등록 클레임**: private `tierToCertStatusString`(:202-213)이 'Mirrors
  cert_writer.tierToStatusString' 주석과 함께 정준 매핑을 재유도한다(DECISION-0630 semantic
  authority split). 분기별 불일치: vtZ3Only→certZ3Verified·vtKInduction→certZ3Verified(정준은
  certZ3Candidate), vtUfAbstract→certLeanVerified(정준은 certZ3Candidate), vtNone→certRed
  (정준은 certNoObligation); vtDual→certGreen·vtLeanOnly→certLeanVerified만 일치. 유일 소비자
  applyProofStateSyncStatus(:215, 미러 호출 :234), tierFromEvidence 공급(:225),
  proof_state_convergence.nim:61에서 호출.
- **관측**: `src/verification/proof_state_projection.nim:202-213` — 미러 존재, 'Mirrors
  cert_writer.tierToStatusString' 주석 :203, 6개 분기가 등록 서술과 **정확히 동일**
  (vtDual→certGreen :207, vtZ3Only→certZ3Verified :208, vtLeanOnly→certLeanVerified :209,
  vtNone→certRed :210, vtKInduction→certZ3Verified :211, vtUfAbstract→certLeanVerified :212).
  정준 매핑 `src/core/types/certificate_types.nim:95-105` — vtZ3Only/vtKInduction/
  vtUfAbstract→certZ3Candidate, vtNone→certNoObligation (등록과 동일). 소비 체인 전 라인 일치:
  applyProofStateSyncStatus :215, tierFromEvidence :225, 미러 호출 :234,
  `proof_state_convergence.nim:61`.
- **판정**: **still-holds**.
- **비고**: 등록 contentHash 재검증 — 현재 :202-213 블록(후행 개행 제거, 등록 §6 규약)의
  sha256 = `a81e870d639db64101666dad8799e63972d9f9b0ee44b481c9c90ba675b95b35`로 **등록값과
  완전 일치**. 즉 블록은 등록 시점(2026-10-12) 이후 바이트 불변이고, 등록이 부분 인용한
  'Kept local to preserve {.raises: []}…' 주석 문장도 등록 당시부터 존재했다.

### 3.6 DEBT#505 — partially-holds

- **등록 클레임**: `runCounterexampleReplay`(counterexample_replay.nim:563-586)와
  `runRustCounterexampleReplay`(rust_replay_adapter.nim:560-584)는 의도적 레인 파티션 위의
  **동일한** 관측 전용 오케스트레이션 스켈레톤(bind → harness 실행 → post-run integrity 확인 →
  agreement 판정; 각 레인 고유 타입·헬퍼)이다. 위반 지문은 nimtry_baseline(v2)에 앵커돼
  `bin/nimtry src/`가 통과한다. 일반 스켈레톤 추출은 후속 슬라이스.
- **관측**: 양 proc 모두 존재하나 이동 — `runCounterexampleReplay*`
  counterexample_replay.nim:**1077** (등록 :563, +514행), `runRustCounterexampleReplay*`
  rust_replay_adapter.nim:**735** (등록 :560, +175행). 스켈레톤 형상: Nim lane
  bindSubjectIntegrity → synthesizeAndRunHarness → confirmPostRunIntegrity →
  decideReplayAgreement (:1089-1097); Rust lane bindRustSubjectIntegrity →
  synthesizeAndRunRustHarness → **rustReplayCommandMismatch 검증 단계 추가**(:764-770,
  등록 이후 신규) → confirmRustPostRunIntegrity → decideRustReplayAgreement (:771-775).
  앵커: `bin/nimtry src/` PASS exit 0(§2 측정 1번, 신규 미앵커 지문 0) — baseline
  `data/nimtry_baseline.json`에 양 파일 지문 존재(counterexample_replay.nim 8건,
  rust_replay_adapter.nim 4건).
- **판정**: **partially-holds** (의도적 파티션 복제 상태·앵커는 성립, "동일한
  스켈레톤"의 정확한 동일성과 라인·contentHash 앵커는 불성립).
- **비고**: 등록 contentHash(본문 블록 d7d19785…)는 현재 본문과 불일치(현재 :1077-1097
  재계산값 `30579c7d…`) — 라인 이동+본문 변경의 표면 드리프트. Rust 랜의 추가 단계는
  등록 이후 착지한 증거-무결성 admission으로, "dry-duplicate 지문 쌍" 전제 자체는 현재
  스캐너 관측(§2 측정 1번 PASS)과 모순되지 않는다.

### 3.7 DEBT#506 — resolved

- **등록 클레임**: `make build`(Makefile:943-947)는 bin/ax를 -d:release 없이 컴파일하고,
  `verify-contract-release-e2e-full`(Makefile:883-935)은 컴파일 스텝·모드 단언이 없으며, 유일한
  live caller인 `axiom-operational-slice.yml:42-53`이 컴파일 없이 E2E를 실행하므로 required
  check가 debug 바이너리를 release-named E2E한다.
- **관측 (해소)**: `.github/workflows/axiom-operational-slice.yml:42-48` — required check의
  E2E(:79 `make verify-contract-release-e2e-full`) **이전에** `run: make ci-compile` 스텝이
  존재하고, 주석이 "make ci-compile (ci/checker.mk) is THE release build authority:
  -d:release + AXIOM_HERMETIC_BUILDING=1 … `make build` was a -d:allowMissingZ3 nim-check
  build"로 명시한다. `make ci-compile` → `ci-compile-products`(checker.mk:497) →
  `ci-compile-ax`(checker.mk:529-530, `-d:release … -o:bin/ax src/cli/main.nim`)로 required
  check가 소비하는 bin/ax는 -d:release로 빌드된다(B-cache HIT 시에는 재컴파일 대신
  `--check-provenance` 재단언, 주석 :43-47). 변경 시점: `0d3336ae7` 2026-10-24 "verify(contract):
  bind acceptance evidence to the tested binary (Phase 0)" — 등록(2026-10-23) 다음 날.
  등록된 구조 사실 중 타깃 자체의 성질은 여전히 성립: `verify-contract-release-e2e-full`
  (Makefile:885-938)에는 컴파일 스텝·-d:release 모드 단언이 없고 동일 실행체 해시 결속만
  있다(:889 HASH_A, :935 HASH_B 비교); 형제 타깃들의 -d:release 리빌드도 그대로(:644, :808,
  :847). `build` 타깃(현재 Makefile:945-949)은 여전히 `-d:allowMissingZ3` 비릴리스다 — 다만
  required check의 바이너리 공급원이 아니게 됐다.
- **판정**: **resolved** — 등록된 결함 상태("required check가 debug 바이너리를 E2E")가 base
  트리에서 관측되지 않는다.
- **비고**: 해소는 호출자(워크플로 빌드 스텝) 계층에서 이뤄졌다. `verify-contract-release-e2e-full`
  호출부 전수: Makefile 정의·주석, `axiom-operational-slice.yml`(유일한 live CI caller —
  등록 서술과 동일), 카탈로그/주석 참조뿐.

### 3.8 DEBT#507 — still-holds

- **등록 클레임**: `projectRunOutcome`(decision_algebra.nim:188-228) CONTINUE 분기는
  NOT_VERIFIABLE-demoted run(verified=0 ∧ failed=0 ∧ timeout=0)을 exit 0으로 사상한다.
  ax report가 동일 규칙을 사용한다(wf_runners.nim:195-197). HEAD에서 theater가 아닌 이유는
  CI 보상 — verify-contract-release-e2e-full의 verdict/exit 일치 단언(Makefile:905-907)과
  SATISFIED+FRESH 단언(:925-927), negative control(manifest.json:48), 워크플로에
  `|| true`/`continue-on-error` 부재. 제품 exit-code 수정은 pinned-file rotation follow-up
  (Makefile:880-881).
- **관측**: `src/core/utils/decision_algebra.nim:188-228` — 등록과 **동일 라인**. CONTINUE
  규칙 :223-228: `failedCount == 0 ∧ timeoutCount == 0`에서 verified>0(성공) 또는
  verified==0(empty/no-obligation run) → `OutcomeContinue` — 주석에 §7 근거 병기. ax report
  경로: `src/cli/wf_runners.nim:195-197`는 등록 이후 재편된 `axProofShortcutExitCode`
  (정의 :46-75) 호출부이며, 이 래퍼는 :73에서 `runExitCode(projectRunOutcome(reportNode))`로
  **동일 규칙을 소비**한다("A second local derivation would be a second authority" 주석 유지)
  — 등록된 "단일 규칙" 클레임은 유지. CI 보상: verdict/exit 일치 단언 Makefile:906-910(등록
  :905-907, 소폭 이동), SATISFIED+FRESH :926-929(등록 :925-927), run↔cert identity :922-925,
  해시 결속 :931-935(등록 :922-927 범위에서 이동). negative control:
  `data/promotions/axiom-operational-slice-activation/manifest.json:48` — 등록 인용과
  원문 일치("…GateVerdict=FAIL -> make verify-contract-release-e2e-full Error 1 -> check
  FAILURE"). `axiom-operational-slice.yml`에서 `continue-on-error` 0건, `|| true` 0건.
  Makefile:880-881 rotation follow-up 주석 존재.
- **판정**: **still-holds**.
- **비고**: exit 경로의 래퍼 재편(axProofShortcutExitCode — blockingFailure·fatalErrors
  fail-closed 선검사 추가)은 표면 변화이며 등록 클레임의 핵심(CONTINUE 규칙·단일
  authority·CI 보상)은 전부 관측과 일치.

### 3.9 DEBT#509 — still-holds

- **등록 클레임**: (a) `ci/checker.mk:16-17`·`Makefile:15-16`의
  `CHECKSUMS_PATH := $(wildcard $(NIMBLE_PKGS)/checksums-*)` / `FUSION_PATH := $(wildcard
  …fusion-*)` — 패키지 부재 시 wildcard가 빈 문자열로 확장되어 `--path:` 빈 인자로 흡수된다
  (no-op, fail-open). (b) `config.nims:337-339`가 noNimblePath 후 nimble.paths 존재 시에만
  재활성화하는데 nimble.paths는 gitignored이고 A cache 경로(~/.nimble, ~/.choosenim, ~/.elan,
  ~/.local/bin) 밖이므로 캐시 복원은 nimble.paths를 만들 수 없다. (c) `Install project Nim
  dependencies` 스텝의 `if:`(cache-hit != true ‖ a-verify-ok != true ‖ a-probe-ok != true)가
  false면 설치가 스킵되어 "Verify OK"와 "dependencies not installed"가 동시 성립한다. (d)
  A-probe/verify는 nim/lean/z3 버전만 검사하고 nimble 패키지 집합은 검사하지 않는다. (e) 부분
  설치 캐시 커밋 실측(847MB, run 시각 등)과 `checksums/sha2` 컴파일 실패 2건은 런타임 관측.
- **관측**: (a) `ci/checker.mk:15-17`·`Makefile:14-16` — 등록과 동일 라인의 wildcard 정의.
  빈 확장 데모(결정론적, GNU make 의미): `/nonexistent` 경로 wildcard로
  `$(info [--path:$(C)])` 실행 → `[--path:]` 출력(빈 인자 no-op). (b) `config.nims:337-339`
  — `switch("noNimblePath")` :337, `when withDir(thisDir(), system.fileExists("nimble.paths"))`
  :338-339; nimble.paths는 `.gitignore:210`; A-layer 경로는 composite action 문서·구현
  `.github/actions/setup-axiom-toolchain/action.yml:54` "~/.nimble, ~/.choosenim, ~/.elan,
  ~/.local/bin ONLY" — nimble.paths(저장소 디렉터리 상대)는 캐시 경로 밖. (c)
  action.yml:804-810 — 스텝명·`if:` 조건이 등록 서술과 **원문 일치**(추가 가드
  keygen-only/provision-scope/skip-nimble-install 포함). (d) `AXIOM_CACHE_A_VERIFY: OK` 라인
  :390 — `nim=2.2.10 lean=4.33.0 z3=4.13.3 gccFp=… glibcFp=… key=…` — nimble 패키지 집합
  검사는 계속 없음(등록 이후 gcc/glibc 지문 검사로 확장 — 표면 변화). (e) 런타임 역사(정적
  재관측 불가). 소비 지점: `src/cli/install_ax_cas.nim:23`·`src/core/crypto/hash_kernel.nim:10`
  의 `import checksums/sha2` — 등록과 동일 라인.
- **판정**: **still-holds** (정적 메커니즘 클레임 전부 관측과 일치).
- **비고**: lock-completeness witness stamp 가드(action.yml:55-57, :813-816 "partial ~/.nimble
  must never win the first-save race")는 등록(2026-10-27) 이전 착지분(`257a9319a` 2026-09-24)으로
  현재 존재 — 사후 완화가 아니라 등록 당시 기존 가드다. (e)의 캐시 내용·run별 관측은 재현
  불가 항목으로 기록(§1 기준).

### 3.10 DEBT#512 — still-holds

- **등록 클레임**: `matchesStatus`(src/gate/runners/debt_integrity_gate.nim:60-62)는
  `["open","closed","deferred","resolved"]`만 허용하고, `data/debt_schema.json:12-16`의
  statusEnum은 `["open","closed","accepted","deferred","in_progress"]` — 스키마 정준
  in_progress·accepted는 게이트가 거부하고 게이트 허용 resolved는 스키마에 부재(양방향
  드리프트). validateDebtRegistryImpl(:121-122)이 invalid로 판정·FAIL. entry-level status는
  자유 서술 허용으로 문서화(debt_schema.json:176-180). contentHash는 matchesStatus 정준
  본문의 sha256=6ad7558f…, statusEnum 블록 sha256=69e80b46….
- **관측**: `src/gate/runners/debt_integrity_gate.nim:60-61` — `s in ["open", "closed",
  "deferred", "resolved"]` 그대로; validateDebtRegistryImpl의 status invalid 판정 :121-122.
  `data/debt_schema.json:12-16` — `["open", "closed", "accepted", "deferred", "in_progress"]`
  그대로; entry-level 자유 서술 문서 :176-180. **양방향 드리프트 그대로**. 대상 2파일은 등록
  시점(ad8f67238) 트리와 **바이트 불변**(`git diff ad8f67238..291cb2f08 -- <2파일>` 공백 —
  변경은 debt_registry.json +19행, nimtry_baseline.json뿐). contentHash 재검증:
  matchesStatus 본문 :60-61(후행 개행 제거) sha256 = `6ad7558fadeb774b00c6f1d5910cbf5fd3a550784b080973eac2d3c42e901ed8`
  — **등록값과 완전 일치**.
- **판정**: **still-holds**.
- **비고**: statusEnum 블록 해시(등록값 69e80b46…)는 6종 슬라이싱 변형(:12-16/:12-15/:13-16 ×
  개행 유지/제거 × 들여쓰기 유지/제거) 어느 것으로도 미재현(예: :12-16 개행 유지
  f48a0004…, 제거 5dc90309…) — 파일이 불변임이 diff로 확인되므로 **내용 드리프트가 아니라
  등록 측 직렬화 규약의 미재현**으로 기록한다.

## §4. DEBT#506·#507·#509 — GitHub Actions 공식문서 대조

출처: GitHub Actions 공식 문서(context7 `/websites/github_en_actions` — docs.github.com
"Workflow syntax"·"Expressions"·"Use jobs" 참조 스니펫, 2026-11-02 조회). 세 항목의 클레임이
워크플로 의미론(스텝 실패 전파·스킵·조건부 실행)에 의존하는 부분을 공식 의미와 대조한다.

| 공식 문구 (인용) | 의미 | 이 기록에서의 적용 |
|---|---|---|
| `jobs.<job_id>.steps[*].continue-on-error` — "Prevents a job from failing when a step fails. Set to `true` to allow a job to pass when this step fails." | continue-on-error가 **없으면**(기본 false) 실패한 스텝은 잡을 실패시킨다. | **DEBT#507**: `axiom-operational-slice.yml`에 continue-on-error 0건·`\|\| true` 0건이므로 `make verify-contract-release-e2e-full`의 exit 1은 잡 실패→required check 실패로 전파된다. 등록이 기술한 "CI가 verdict/exit 일치 단언으로 보상한다"의 강제력은 공식 의미와 정합이다. |
| `jobs.<job_id>.continue-on-error` — "Prevents a workflow run from failing when a job fails." | 잡 수준 생략도 동일하게 run 실패를 막는다. | 상기 3건 대상 워크플로에 잡 수준 continue-on-error도 관측되지 않았다(§3.7·§3.9). |
| `always()` — "Causes the step to always execute and returns true, even when canceled." (+ 경고: 임계 실패 가능 작업에는 `if: ${{ !cancelled() }}` 권고) | `always()`는 실패·취소와 무관하게 실행을 강제하는 상태 함수다. | **DEBT#509**: 등록이 기술한 스킵은 `if:` 조건이 false가 된 **조건부 미실행**이며 always() 남용이 아니다 — "skipped because its `if:` was false"는 공식 조건부 실행 의미와 정합(스킵 ≠ 실패, 잡을 실패시키지 않는다). 이것이 등록이 지적한 fail-open("Verify OK와 dependencies not installed 동시 성립")의 구조다. |
| `needs` — "If a job fails or is skipped, all jobs that need it are skipped unless the jobs use a conditional expression that causes the job to continue." | 실패/스킵은 needs 체인을 따라 전파된다. | **DEBT#506**: required check 잡 내 스텝 순서(빌드 :42-48 → E2E :79)는 동일 잡의 순차 실행이므로 `-d:release` 빌드가 E2E에 선행함이 워크플로 구조로 보장된다(§3.7 해소 근거). |

- **충돌 관측**: 3건의 등록 클레임 중 공식 의미와 충돌하는 것은 없다. 유의점: DEBT#507의
  registered 메커니즘("exit 0 on NOT_VERIFIABLE-only")은 GitHub의 스텝 실패 판정(non-zero exit)
  위에서 동작하는 **제품 측 exit 규칙**이며, 공식 문서는 그 규칙 자체를 정의하지 않는다 —
  공식 계층은 "그 exit code를 내는 run 스텝이 잡을 실패시키는가"만 규정한다(continue-on-error
  부재 → 시킴). 이 구조 분리는 등록 서술("gateVerdict=FAIL surfaces in report/state only;
  CI compensates via the G7-full verdict assert")과 정합이다.
- vendor 문서 대조(DEBT-CI#003의 upload-artifact immutability/overwrite 등)는 본 기록의
  context7 대조 범위(#506/#507/#509) 밖이며, 등록이 인용한 vendor 문구는 원문 그대로
  레지스트리에 존재한다.

## §5. 판정 분포 요약

| 판정 | 건수 | 항목 |
|---|---|---|
| still-holds | **7** | DEBT-CI#003, DEBT#472, DEBT#496, DEBT#504, DEBT#507, DEBT#509, DEBT#512 |
| partially-holds | **2** | DEBT#432 (③④ 불성립 — 4종 테스트가 admission-check test-fast-one 레인으로 와이어됨, f12ea744c 2026-10-08), DEBT#505 (proc 대형 이동 + Rust 랜 검증 단계 추가, 복제 상태·앵커는 성립) |
| resolved | **1** | DEBT#506 (required check가 `make ci-compile` = -d:release 권위를 E2E 전 실행, 0d3336ae7 2026-10-24) |
| unverifiable | **0** | — |

보조 사실: (i) still-holds 7건 중 DEBT#504·DEBT#512의 핵심 contentHash는 등록값과 완전
재현됐다(블록 바이트 불변). (ii) resolved 1건(#506)과 partially-holds 2건(#432·#505)의
상태 변화는 **모두 등록 시점 이후 착지한 제3의 커밋**에 기인한다(0d3336ae7·f12ea744c/b85baabce·
rust 레인 변경). (iii) 게이트 재실측(§2)에서 STALE 10건·exit 1은 요청서 §8과 동일하게
재현됐다 — 본 기록은 close·레지스트리 수정·게이트 변경을 수행하지 않았다.

## §6. 실측 기록 일람 (§2 외 보조 관측)

| 명령 | 관측 | exit/결과 |
|---|---|---|
| `git rev-parse origin/main` (main clone, 작업 시작) | `291cb2f081eb3f25a74b78db2d3fdd36ab4a731e` | base 확정 |
| `make ci-compile-ax ci-compile-gate-hook` → `make bin/nimtry bin/debt_engine` → `nim c … debt_integrity_gate` (worktree) | 4종 빌드 완료 (`BOOTSTRAP_ALL_OK`, 184s) | 0 |
| `grep -c irtVoid src/core/trusted/axiom_ir.nim` | `0` | 0매치 |
| `grep -c overwrite .github/workflows/runner-pool-acceptance.yml` | `0` | 0매치 |
| `grep -c "continue-on-error\|\|\| true" .github/workflows/axiom-operational-slice.yml` | `0 / 0` | 0매치 |
| `git diff --stat ad8f67238 291cb2f08 -- data/debt_schema.json src/gate/runners/debt_integrity_gate.nim` | (공백 — 불변) | drift 없음 |
| `sed -n '60,61p' …debt_integrity_gate.nim \| sha256sum` (후행 개행 제거) | `6ad7558f…901ed8` — 등록 contentHash와 일치 | 재현 |
| `sed -n '202,213p' …proof_state_projection.nim \| sha256sum` (후행 개행 제거) | `a81e870d…5b95b35` — 등록 contentHash와 일치 | 재현 |
| make wildcard 빈 확장 데모 (`$(info [--path:$(C)])`, 존재하지 않는 glob) | `[--path:]` | 재현 |
| `{.axiomImpl.}`/`{.axiomTryImpl.}` 사이트 스캔 (src/) | 128건, 그중 `: void` 반환 0건 | 0 |
