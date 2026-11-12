# 사전 존재 메트릭 드리프트 포렌식 — check-arch LCOM 위반 · check-debt nimtry DRIFT

**날짜**: 2026-10-31
**대상 커밋**: `origin/main` = `53e49e1139a35d854946f3d7d8d4a78b37a66e31` (Merge PR #1132)
**성격**: 조사 전용(evidence) — **수정 없음**. 재앵커·소스 수리·정책 면제는 모두 별도 CONTROLLED 계획 경로의 대상이다(§6).
**측정 환경**: worktree `<user-home>/axwt/invm` (branch `work/inv-met`, clean checkout of `origin/main`), Nim 2.2.10 (repo pin), macOS/Linux 로컬 재현.

---

## 1. 요약 (Conclusion First)

| 항목 | 판정 |
|---|---|
| `make check-arch` FAIL 원인 | `52feb9354`(2026-10-25 10:08 KST, perf 커밋)가 `src/verification/obligation/lean_kernel_boundary.nim`에 `measuredBinaryDigest` proc을 추가 → 모듈 LCOM이 **정확히 0.6(경계, 여유 0)** → **139/231 = 0.6017316…(>0.6)** 로 횡단. v2 베이스라인(2026-10-21 앵커)에 없는 **신규 ERROR 위반**이라 nimtry가 exit 1 (`src/gate/nimtry/nimtry_cli.nim:473-482`) |
| `make check-debt` DRIFT 원인 | ledger `BUDGET#004.current=15`는 **2026-10-24 18:11 `1f82b8d68`**에서 `--sync-budget` 재물질화로 기록된 **nimtry 실패 출력 줄 수 스냅샷**(당시 19건 신규 경고 → 15라인). 현재 projection `2`는 **같은 줄 수 휴리스틱**이지만 `52feb9354` 이후 nimtry가 **신규 ERROR 존재 시 경고 출력을 생략하고 return**(`src/gate/nimtry/nimtry_cli.nim:474-482`)하기 때문에 나오는 값. 실제 신규 위반은 **23건(1 error + 22 warning)**(`--diff-baseline` 실측). 즉 15와 2는 **서로 다른 출력 브랜치의 줄 수**이지 위반 수가 아니다 |
| 분류 (i) LCOM | **(a)에 준함(소스 건전) + 정책 판정 필요** — 임계 권위는 불변(기준 이동 아님), 소스 변화는 합법적·문서화된 perf 메모이제이션 헬퍼(의미 결합 아님). 여유 0 경계에서의 휴리스틱 경계 횡단. 수리(분리) vs `[lcom_overrides]` 면제는 문서화된 정책 절차의 결정 사항 — 어느 쪽이든 CONTROLLED 경로. 순수한 "(a) 재앵커만이 정답"은 아님(§5.1) |
| 분류 (ii) nimtry DRIFT | **(a) 낡은 ledger 스냅샷 + 측정 출력 의미 변화** — 소스는 건전(경고 22건은 앵커 이전부터 축적된 기존 관리 부채). 문서화된 정본 처방 = v18 2단계(재앵커 + ledger 동기화)가 정확히 이 상황의 처방(§5.2). confidence: 높음(역사 커밋 재측정으로 확정) |
| 상호의존성 (신규 발견) | **재앵커 2단계만으로 DRIFT가 0이 되려면 재앵커가 LCOM ERROR까지 흡수해야 한다.** ERROR가 베이스라인에 없는 한 check-arch는 계속 FAIL하고 projection은 계속 2(마스킹 때문에 경고 수와 무관) |

---

## 2. 재현 (Reproduction)

### 2.1 명령과 출력 원문

```
$ cd <user-home>/axwt/invm && make bin/nimtry bin/debt_engine   # 표준 빌드 경로
$ make check-arch
=== [2/4] Architecture Violation Check ===
❌ Architecture check FAILED (nimtry exit 1):
[ERROR] nimtry_cli: [nimtry] FAIL: 1 new ERROR violations not in baseline (debt anchoring)
[ERROR] nimtry_cli:   [error] SOLID — [solid-srp] src/verification/obligation/lean_kernel_boundary.nim: LCOM=0.6017316017316017 exceeds threshold 0.6 (low cohesion — SRP violation)
make: *** [Makefile:214: check-arch] 오류 1   (exit 2)
```

```
$ make check-debt     # exit 0 — DRIFT는 비치명적 경고(INFO disposition)
=== Part D: Budget metric evaluation ===
  ⚠️  nimtry_violations DRIFT (projection=2 vs ledger 15)
=== Part D.1: Policy disposition resolution ===
  ✅ nimtry_violations disposition=INFO / direction=MAINTAINED
  Metric evaluation: 3 PASS, 1 DRIFT
  All debt validation checks passed.   (exit 0)
```

### 2.2 두 타깃의 강제 경계 (task 사실관계 재검증)

- `check-arch`는 `GATES_STATIC`(Makefile:39) 소속 — `local-ci`/`local-verify-static`에서만 실행, `PUSH_ADMISSIBILITY_GATES`(Makefile:61)에 **없음** → push 게이트가 아니다.
- `check-debt`는 `PUSH_ADMISSIBILITY_GATES`(Makefile:61)에 있으나 sound input-set scoping skip predicate(Makefile:457-499)이 docs-only diff를 loud SKIP하며, 실행돼도 DRIFT는 INFO disposition으로 exit 0이다. → 두 실패 모두 pre-commit/pre-push가 차단하지 않는 **로컬 make 타깃 관측**이라는 task 사실관계와 일치.

---

## 3. (i) LCOM 위반 포렌식

### 3.1 임계 0.6의 권위 (file:line)

- 전역 임계 SSOT: `src/gate/architecture_policy.lock:93-95` — `[cohesion]` 섹션의 `lcomThreshold = 0.6` / `tccThreshold = 0.3`
- 파서: `src/core/policy/parsers/parse_cohesion.nim:20-25` (`max_lcom`/`lcomThreshold` → `policy.cohesion.maxLcom`)
- 적용: `src/gate/cohesion_enforce.nim:88-107` — `lcom > maxLcom` 위반 artifact 생성(단, per-module `lcomOverrides` 우선, `:90-94`)
- nimtry 질의: `src/gate/nimtry/solid_queries.nim:40-46` — `solid-srp` 질의가 `rule="SOLID"`, `severity="error"`로 `checkCohesionV2` 연결
- LCOM 정의: `src/gate/cohesion_enforce.nim:31-37` — `LCOM = 1 - (연결 쌍 수)/(전체 함수 쌍 수)`, 두 함수가 식별자 1개라도 공유하면 "연결"

### 3.2 결정적 측정 — 임계 횡단 커밋 특정

측정 방법: 프로덕션 경로와 동일한 `extractModuleFactsV4`(`src/gate/nimtry/nimtry_extract_part3_part2.nim:239`) + `computeCohesion`(`src/gate/cohesion_enforce.nim:31`)을 임포트하는 프로브(/tmp, 저장소 무변경)로 각 커밋의 파일 내용을 직측. 프로브가 HEAD 파일에서 산출한 `lcom=0.6017316017316017`는 게이트 보고값과 **정확히 일치** → 측정 경로 타당성 교차 검증.

| 파일 버전 | 함수 수 | 전체 쌍 | 연결 쌍 | LCOM | 판정 |
|---|---|---|---|---|---|
| `52feb9354^` (마지막 베이스라인 앵커 당시 내용) | 21 | 210 | 84 | **0.6 (정확히, 126/210)** | 위반 아님 (0.6 초과 아님) |
| `52feb9354` = HEAD | 22 | 231 | 92 | **0.6017316017316017 (= 139/231)** | **위반 (>0.6)** |

**횡단 커밋**: `52feb9354` "perf(verification): hash the bound toolchain binaries once per process" (Author date 2026-10-25 10:08:27 +0900). 이 커밋은 **이 파일 1개만** 변경(`git show --stat`, +58/−10)했고, 변경 내용은 `measuredBinaryDigest` proc + `binaryDigestMemo` threadvar 추가. 파일의 마지막 베이스라인 앵커(`f77fea559`, commit date 2026-10-21 21:05:37 +0900) 이후의 **유일한 변경**이다(`git log --follow -- src/verification/obligation/lean_kernel_boundary.nim`).

수학적 원인: 모듈이 임계 **경계에 정확히 0.6(여유 0)**로 놓여 있던 상태에서 22번째 함수가 21개 신규 쌍을 추가 — 이 중 8쌍 연결(`measuredBinaryDigest`는 모듈의 digest/IO 계열 함수 8개와 식별자 공유), 13쌍 비연결 → (84+8)/(210+21)=92/231 → LCOM 139/231≈0.60173.

### 3.3 측정 안정성 (결정론 근거)

- `cohesion_enforce.nim`·`nimtry_extract_*`·`solid_queries.nim`·`architecture_policy.lock`은 **2026-10-20 이후 무변경**(git log 실측) → 같은 파일 내용이면 같은 LCOM.
- nimtry 캐시는 콘텐츠 SHA-256 + policyHash + binaryHash + nimVersion 4중 키(`src/gate/nimtry/nimtry_cache.nim:64-100`, 캐시 저장소는 repo-local `.nimcache/nimtry`) → 역사 커밋 간 측정 오염 없음(임시 detached 워크트리마다 cold 캐시).

---

## 4. (ii) nimtry DRIFT 포렌식

### 4.1 projection "2"의 정체

- 평가자: `tools/debt_engine.nim:1629-1643` `evalNimtryViolations` — `bin/nimtry src/` 실행, **exit 0 → 0**, 실패 시 출력에서 `[soc-` 또는 `violation` 포함 줄 수의 **best-effort 카운트**(0이면 1로 fail-closed). 자체 주석: "data/nimtry_baseline.json은 live 측정이 아니라 archived anchor 스냅샷 — 메트릭 소스로 사용 금지".
- **출력 마스킹(핵심)**: `src/gate/nimtry/nimtry_cli.nim:473-482` — 신규 **ERROR** 위반이 존재하면 nimtry는 ERROR 줄만 출력하고 **즉시 return**(경고 줄은 출력되지 않음). 따라서:
  - HEAD 실측 `bin/nimtry --diff-baseline src/`: **New: 23, Resolved: 20, Stable: 4206** — 실제 신규 위반은 1 error(LCOM) + 22 warning(soc-surface-area/ocp/ssot/purity 등).
  - 게이트 출력은 ERROR 2줄만 → projection = **2**. 경고 22건은 오늘도 실재하지만 출력에 없다.

### 4.2 ledger "15"의 정체

- 레코드: `data/debt_ledger.json:55-67` `BUDGET#004` metric=`nimtry_violations` baseline=704 target=0 **current=15** `lastVerifiedAt=2026-10-06T02:55:10Z`(동결 — `--sync-budget`는 `lastVerifiedAt`을 보존하는 것이 도구 사양, `tools/debt_engine.nim:1579` "preserved from original").
- current 값 변천(git show로 레드저 커밋마다 직독): 10-11~13: 0/10/23/0 왕복 → 10-15/16: 23 → 10-18: 0 → 10-23: 6 → **10-24 18:11 `1f82b8d68`: 6→15** → 오늘: 15.
- `1f82b8d68`은 동일 커밋에서 `debt_registry_open` 46→47(DEBT#508 등록)도 함께 갱신 + `debt_registry.json`/`docs/DEBT_REGISTRY.md`/`src/generated/debt_constants.nim` 동반 변경 — **`bin/debt_engine --sync-budget` 재물질화의 표준 안무**와 일치. (도구 실행 로그 부재로 직접 확증은 불가 → §6 UNKNOWN-1)

### 4.3 "15"와 "2"의 비교 불가능성 — 역사 커밋 재측정

측정 방법: 각 커밋을 임시 detached 워크트리로 checkout 후 HEAD에서 빌드한 `bin/nimtry`(해당 기간 무변경 확인: `nimtry_cli.nim` 최종 변경 2026-08-16, `tools/debt_engine.nim` 평가자 최종 변경 2026-10-13)를 실행, `debt_engine`과 동일하게 `[soc-|violation` 포함 줄 수를 계산.

| 커밋 | 시각 (KST) | nimtry rc | 매칭 줄 수(=projection) | 출력 내용 |
|---|---|---|---|---|
| `1f82b8d68` | 10-24 18:11 | 1 | **15** | "FAIL: 19 new violations" — 19건 전부 **warning**(src/cli/axiom_engine.nim soc-surface-area 등), 에러 브랜치 아님 |
| `38fb320fb` | 10-24 23:10 | 1 | 18 | "FAIL: 22 new violations" — 전부 warning |
| `7a4d9dd8b` = `52feb9354^` | 10-25 00:05 (PR #1094 merge) | 1 | 18 | 동일 22건 warning |
| `52feb9354` | 10-25 10:08 | 1 | **2** | "FAIL: 1 new ERROR violations" — **경고 출력 생략(마스킹)** |
| `6d37441a8` | 10-27 18:24 | 1 | 2 | 동일 |
| HEAD (`53e49e1139`) | 10-31 | 1 | 2 | 동일 |

**결론**:
- "15"는 **2026-10-24 18:11 시점의 과도 상태(경고 19건)의 출력 줄 수**가 ledger에 스냅샷된 것.
- "2"는 **같은 줄 수 휴리스틱이지만 10-25 10:08부터 ERROR 브랜치 마스킹으로 경고가 가려진** 출력의 줄 수.
- 즉 **2 vs 15 DRIFT의 숫자 divergence 시작점은 2026-10-25 10:08 KST(`52feb9354`)이다.** (10-24 23:10~10-25 00:05 사이에도 18 vs 15의 divergence이 존재했으므로, "커밋된 15와 live projection의 불일치" 자체는 10-24 18:11 직후 소스 성장과 함께 시작.)
- 22건의 경고는 **10-21 베이스라인 앵커 이후 소스 성장으로 축적된 기존 관리 부채**로, 오늘까지 존속(`--diff-baseline` 실측) — 사라진 적이 없다. 52feb9354에서 "22→1"로 보이는 것은 위반 소멸이 아니라 **출력 마스킹**이다.

---

## 5. 정본 처방 (Canonical Prescriptions) — file:line 인용

### 5.1 nimtry DRIFT

- **v18 등록 노트 (task 지목 2단계 관례의 SSOT)**: `config/repository_surface.json:5` — "v18 (2026-09-27): nimtry DRIFT 데트앵커 등록 — **data/nimtry_baseline.json CONTROLLED** (precedent 16 managed-data kind, broad wildcard 금지; **2단계 = nimtry --update-baseline 재앵커 + budget ledger 동기화 follow-up**)". 경로 등록: 동 파일 `:70`.
- **재앵커 분류 선례**: 동 파일 `:5` v82 노트(2026-10-21) — "동일 PR에서 data/nimtry_baseline.json 재앵커 (**pre-existing measured drift** … total_violations 유지, **신규 부채 흡수 아님**; 선례 3b7a1df20 class (iii))" — 재앵커는 "기존 측정 드리프트 흡수"로 분류하는 관례가 확립돼 있다. 실행 커밋 선례: `3b7a1df20`/`e3dce78e7`/`58d11483a`/`f77fea559`(모두 2026-10-21).
- **ledger 동기화 도구**: `bin/debt_engine --sync-budget`(`tools/debt_engine.nim:1786`, dry-run 지원 `:3452`).

### 5.2 LCOM 위반

- **문서화된 면제 정책**: `docs/spec/gate_runner_lcom_policy.md`
  - `:44-51` §3 — 절차형 오케스트레이터 모듈이 SOLID-srp LCOM **유일** 위반이면 `src/gate/architecture_policy.lock`의 `[lcom_overrides]`에 `= 1.0` 면제 **가능**, 단 4 조건: (1) 오브젝트 상태 없는 절차형 오케스트레이터, (2) 사전 dead-code 제거, (3) rationale 주석(감사 추적 §0.9), (4) 나머지 전 게이트 통과.
  - `:24-40` §2 — 모듈 전체를 클래스로 보는 LCOM 휴리스틱이 절차형 모듈에서 구조적으로 오경보하는 이유 문서화.
  - `:4` 스코프는 `src/gate/runners/`로 기술되나, §3이 가리키는 기제는 일반 `[lcom_overrides]` 섹션이며 **verification 모듈 적용 선례가 존재**: `src/gate/architecture_policy.lock:308` — `src/verification/observed_audit_contract.nim = 0.0` (rationale 주석 포함). 현재 등록된 override는 52건(`:198` 섹션).
- **대안 수리 경로**: `measuredBinaryDigest`(+memo)를 IO 헬퍼 모듈로 분리하면 모듈이 21함수로 환원(LCOM 0.6 경계 복귀). 단 경계 여유 0은 그대로이므로 후속 함수 추가 시 재횡단한다. — 수리 vs 면제 선택은 정책 소유자 결정.
- **편집 권위 주의**: `src/gate/architecture_policy.lock`은 `src/gate/**` FROZEN glob 흡수 경로로, v75 선례(`config/repository_surface.json:5` v75 노트)와 같은 **FROZEN-to-CONTROLLED 재등록 정책 PR**이 선행돼야 한다.

---

## 6. 분류 판정 및 UNKNOWN

### 6.1 (i) check-arch LCOM — **(a)에 준함 + 정책 판정 필요**

- (b) "실제 아키텍처 퇴행"의 증거 **없음**: 추가된 `measuredBinaryDigest`는 커밋 메시지에 기계 검증이 붙은 합법적 perf 메모이제이션(콘텐츠 키, 의미 불변 — `52feb9354` 메시지 실측), 새로운 책임 결합이 아닌 digest/IO 계열 기존 함수 8개와 식별자를 공유하는 보조 함수다.
- (a) 순수 "기준 이동"도 **아니다**: 임계 권위(`architecture_policy.lock:94` 0.6)와 측정기는 불변이고 **소스가 정적 임계를 넘었다**. 다만 모듈은 여유 0의 경계(정확히 0.6)에 놓여 있었으므로 휴리스틱 경계 횡단 성격이 강하다(§3.2).
- **판정**: 소스 건전성 관점에서 (a) 계열. 그러나 정합적 처방은 단순 베이스라인 재앵커가 아니라 **문서화된 `[lcom_overrides]` 면제 결정(조건 4항 검토) 또는 모듈 분리**다 — 이는 CONTROLLED 표면(`architecture_policy.lock` FROZEN)·정책 절차가 요구하는 결정으로, 본 조사는 수행하지 않았다.

### 6.2 (ii) check-debt nimtry DRIFT — **(a) 낡은 ledger 스냅샷 + 측정 출력 의미 변화. 재앵커 2단계가 정본 처방.**

- 소스는 건전: DRIFT의 양변은 모두 "위반 수"가 아니라 "실패 출력 줄 수"이며, 실제 위반 집합(23건)은 10-24 이후 소스 성장분으로 앵커 래칫 정상 범위의 관리 부채다.
- 처방은 v18 2단계(`config/repository_surface.json:5`): `nimtry --update-baseline` 재앵커 → `bin/debt_engine --sync-budget` follow-up. 이때 §1 상호의존성(재앵커가 LCOM ERROR를 흡수해야 check-arch PASS → projection 0 → ledger 0)과 v82 선례의 분류 문언("신규 부채 흡수 아님") 충족 여부를 재앵커 계획 PR이 명시해야 한다.
- confidence: 높음 — 6개 역사 커밋 재측정(§4.3)으로 각 숫자의 생성 시점·내용을 직접 관측.

### 6.3 UNKNOWN

- **UNKNOWN-1**: `1f82b8d68`의 ledger current=15 기록이 `--sync-budget` 실행에 의한 것인지에 대한 직접 확증 부재. 동시 갱신 패턴(46→47, registry/codegen 동반)이 도구 안무와 일치하고 `lastVerifiedAt` 보존이 도구 사양(`tools/debt_engine.nim:1579`)과 일치하나, 실행 로그는 없다. → "sync-budget 재물질화로 판정(간접 근거), 수동 편집 가능성 배제 불가".
- **UNKNOWN-2**: 22건 경고 위반 각각의 유입 커밋 목록은 특정하지 않았다 — task 범위(DRIFT 시점·의미 규명) 밖.
- **UNKNOWN-3**: nimtry 경고 출력 마스킹(§4.1)이 의도된 사양인지 문서로 확인하지 못했다 — `nimtry_cli.nim:473-482` 동작은 실측했으나 이를 규정하는 spec 문서는 발견하지 못했다(발견 시 이 문서 갱신 필요).

---

## 7. 수정 배제 선언 (No-Fix Statement)

본 조사는 **어떤 파일도 수정하지 않았다**(측정 프로브·역사 checkout은 모두 저장소 밖 /tmp와 임시 worktree에서 수행 후 제거).

- `data/nimtry_baseline.json` 재앵커: **CONTROLLED 표면**(`config/repository_surface.json:70`) — v18 2단계 정책 PR 경로가 필요.
- `src/gate/architecture_policy.lock` `[lcom_overrides]` 면제: **FROZEN 흡수 경로** — v75 선례의 FROZEN-to-CONTROLLED 재등록 + 인간 아키텍트 승인 절차 필요.
- `src/verification/obligation/lean_kernel_boundary.nim` 수리(분리/이동): 일반 코드이나 수리-vs-면제 선택 자체가 §5.2의 정책 결정에 속한다.

모든 수리·재앵커는 별도 계획 경로(정책 PR → 본문 PR)에서 수행돼야 하며, 본 문서는 그 결정에 필요한 측정 근거만 제공한다.

---

## 부록 A. 측정 명령 목록 (재현용)

```
git worktree add <user-home>/axwt/invm -b work/inv-met origin/main   # 53e49e1139
make bin/nimtry bin/debt_engine && make check-arch ; make check-debt
bin/nimtry --diff-baseline src/                       # New:23 / Resolved:20 / Stable:4206
# 역사 재측정: git worktree add --detach <tmp> <commit>; cd <tmp>; <HEAD-bin>/nimtry src/
# LCOM 직측: extractModuleFactsV4+computeCohesion 프로브(HEAD 게이트 값과 일치 교차검증)
```
