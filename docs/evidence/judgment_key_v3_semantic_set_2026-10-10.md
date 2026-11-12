# Judgment Key ⑤ v3 — 의미-집합 digest 정밀화 운영 선언 (VS-2)

> **Status**: 운영 선언 문서 (docs-only — 추적 대상 소스 무변경). 본 문서는 test-judgment
> CAS 재사용 키 **성분 ⑤(검증자 세대 축)의 v3 semantic set digest 정밀화** 슬라이스의
> 설계 요지·로컬 검증 실측·상대 완전성 근거를 기록한다.
> **구현 반송**: **PR #695** (`feat/judgment-key-v3` — 병렬 착지 중, 본 문서는 그 판정
> 면만 서술하며 구현 트리를 변경하지 않는다).
> **정본 계약**: `docs/spec/test_judgment_cas_contract.md` **v1.0.3** (§4.1 신설 — #695가
> 반송하는 개정; 본 문서는 그 계약에 대응하는 실행 증거다).
> **선행 슬라이스**: PR #691 (VS-1 — S5 ircheck 공급 복원, DEBT#502) — MERGED `b64053c7f`.
> **작성일**: 2026-10-10. **측정 위치**: 구현 슬라이스 로컬 워크트리 (`feat/judgment-key-v3`,
> head `35dd04862` — 문서 작성 시점 PR #695 head).
> **비개정**: freeze(E1–E5)·`obligation_semantics.md` §2.1a 개정 없음 — v3는 성분 ⑤의
> **도출 정밀화**지 9성분 집합·REUSED 5조건·fail-closed의 변경이 아니다.

---

## §1. 설계 요지

**무엇을 바꾸는가**: 재사용 키의 성분 ⑤를 v2의 B^{tree} 전체 결속에서 **의미-집합
digest**로 정밀화한다. v2는 docs-only main 커밋마다 전 세대를 무효화하는 과잉 무효화를
갖았고(`docs/spec/head_binding_semantics.md` §2가 "수용"으로 기록한 결함), v3는
**S의 멤버가 바뀔 때만** 세대를 전진시켜 이를 제거한다 — normative 면(docs/spec·
docs/agents·config/policy·config/templates)·컴파일 입력(staticRead 대상 전수)·소스·
픽스처는 배제 금지(W∩N=∅ 강제)로 S에 유지해 **참 무효화는 보존**한다.

1. **단일 도출 권위**: 도출기 1개(`semantic_set_derivation.nim` — 배치 src/verification/,
   PR #695 반송) + 배제표 1장(NoEffect 규칙 배열 — `src/gate/proof_unit_catalog.nim`의
   CertifiedNoEffect 접두·확장·루트와 impact_closure_selector carve-out을 흡수한
   **단일 표**). 다른 어떤 모듈도 S를 산출하거나 배제를 선언할 수 없다. 기본-포함
   (default-include) 공식:

   ```
   S = TreeUniverse(R) − N      (R = 피험 트리, N = 인증된 무영향 배제표)
   ```

2. **정규화 (무손실·git 객체·상대 완전성)**:
   - canonical 요소 = `git ls-tree -r -z` **NUL 레코드**(`<mode> <type> <sha>\t<path>`)
     그대로 — 파일 **유형**(blob/tree/commit, 심볼릭 링크 120000·gitlink 160000 포함)과
     **모드**(100644/100755/120000/160000)가 경로에 자동 결속되고, 개행 경로도
     무손실이다(`path:sha256` 줄 형식은 개행 모호로 금지).
   - 정렬 = 전체 레코드 **바이트 순**(LC_ALL=C 등가 memcmp) + **스트림 sha256**
     (정렬·NUL-종단 레코드 스트림 해시).
   - **작업 디렉터리 읽기 금지** — 내용 정체성은 ls-tree blob sha뿐(git 객체 저장소
     전용). 트리 밖 입력이 검증에 영향을 주면 다른 키 성분(env/recipe/toolchain — 이미
     존재)으로 결속되거나 도출이 거부된다(fail-closed).
3. **트리 OID = 키 밖 probe 앵커(4명제)**: 트리 OID 자체는 키에 들어가지 않고
   probe 앵커로만 존재한다 — **p1** 호출자 git 객체 저장소 해석 가능 / **p2** 키
   비참여(타입이 계약 — closure는 `semanticSetDigest`만 운반) / **p3** decision-file
   provenance 일치(plan이 기록, attest가 대조 — 한 어드미션 런 = 하나의 트리) /
   **p4** 검증 불가 → REUSED 금지 → EXECUTED 폴백.
4. **스킴 v2→v3**: v2 세대는 원장 이력으로 고아화된다 — 새 세대의 첫 실행 = EXECUTED
   (원 실행 후 재민트). payload 스키마는 v2 유지 → `payloadSha256` 봉쇄 상속.
   v3 전진 조건은 v2의 **부분집합**(엄격 축소)이라 구 세대와 키 충돌이 없다.
5. **게이트-축/실행-축 분리 + §5(e) 정밀화**: proof_unit_consistency_gate의 normative
   스캔 축(게이트-축)과 본 키의 재사용 무효화 축(실행-축)은 **독립** — normative 면은
   배제 금지라 어느 축에서도 조용히 사라지지 않는다. 검증자의 소스·정책·스펙·컴파일
   입력 변경은 ⑤(S)를 통해 계속 키를 전진시키며, §5(e)는 B executor의 측정 정체성
   (번들·핀)만 담당한다.
6. **계약 v1.0.3**: §4.1 신설(핵심 공식·정규화 3건·b-probe-tree 4명제·축 분리·잔여
   위험 등록부) + §4/§5(e) 정밀화 문언. 성분 집합·5조건·fail-closed는 무변경.

## §2. 로컬 검증 실측 (2026-10-10)

| # | 회귀 | 명령 | 관측 | 판정 |
|---|---|---|---|---|
| M1 | 신규 도출기 (T1–T6) | `make test-fast-one T=tests/unit/test_judgment_set_derivation.nim` | 최종 라인 **"All judgment semantic-set derivation tests PASSED"** — T6 census: **2,350 .nim**, literal staticRead 대상 **25종** 전수 선언 일치, computed 사이트 **47곳** 전수 선언 일치, 미해석 리터럴 **4건** lenient skip(표류 가드 관측 범위 밖 표기) | **PASS** |
| M2 | judgment_cas 전체 (G1–G10) | `make test-fast-one T=tests/unit/test_judgment_cas.nim` | **146 PASS / 0 FAIL**, 최종 라인 **"All judgment CAS tests PASSED"** (변경 클로저 → jExecuted 드릴 포함) | **PASS** |

두 회귀 모두 `git archive HEAD` 시드(커밋 트리 전용 — 작업 디렉터리 미사용) 위에서
실행됐다: 도출이 어드미션 워크플로가 넘기는 동일 입력 면(committed bytes)에서
단언된다는 설계 자체를 테스트가 재현한다.

## §3. 상대 완전성 5요소 (삭제 주장 금지)

W ⊆ S는 "알려진 입력이 배제되지 않았다"까지만 증명한다. 완전성 주장의 구조 5요소:

| # | 요소 | 내용 |
|---|---|---|
| 1 | **커밋된 SSOT (배제표)** | 배제표 N은 커밋된 단일 도출기 모듈 내부의 단일 표다. 각 규칙은 무영향 근거(코드 인접 문자열)를 필수로 운반하며 공란 = 도출기 자체 결함 — 매 도출 시 표 검증이 단언한다 |
| 2 | **포함-증인** | W ⊆ S ∧ W ∩ N = ∅ — 레시피·피험 소스·픽스처·staticRead 대상으로 구성된 증인 집합이 S 안에 있고 배제 클래스와 교차하지 않음을 매 도출 시 단언; 위반 = 도출 FAIL (fail-closed → EXECUTED) |
| 3 | **분할 검증** | S ∪ N == TreeUniverse — 각 트리 경로가 정확히 한쪽에만 속함(중복 0·누락 0), 기계 단언 |
| 4 | **인증된 제외** | 배제 규칙 각각이 no-effect ground를 운반한다(예: `.github/` = runner가 소비하는 워크플로 위상 — 판정 바이너리에 컴파일·실행되지 않음). 근거 없는 배제는 존재할 수 없다 |
| 5 | **잔여 위험 등록부** | 아래 RR-1~4 — 동적 경로·미발견 입력 메커니즘의 한계를 '삭제'로 주장하지 않고 등록한다 |

| # | 잔여 위험 | 통제 |
|---|---|---|
| RR-1 | 선언되지 않은 computed-path staticRead(동적 컴파일 입력 — k12 사각지대) | computed staticRead 대상·사이트 전수 선언(사이트 47곳 포함) + **T6 스캔 표류 가드**가 실트리 census로 미선언 신규 사이트·대상을 회귀 차단 |
| RR-2 | 선언된 증인 집합 W 밖의 런타임 파일 읽기 | '미증명'으로 운반된다(무영향 아님) — 배제 규칙의 무영향 근거가 유일한 정당성 |
| RR-3 | 커밋 없이 재생성된 generated 파일(workdir↔트리 일시 분기) | ⑤는 커밋 트리만 본다; 나머지 성분(①–④·⑥–⑨)이 workdir를 측정 — 두 측정의 결합이 분기를 흡수 |
| RR-4 | 서브모듈(gitlink 160000) 내부 변경 | 기록되는 것은 고정 커밋 sha(올바른 정체성) — 서브모듈 내부 바이트는 본 키의 대상이 아니다 |

## §4. T1–T6 회귀 표

테스트 파일 `tests/unit/test_judgment_set_derivation.nim` (PR #695 반송). 각 행의
시나리오 문언은 테스트 소스의 선언과 1:1이며, 실측 결과는 §2 M1 런에서 관측됐다.

| # | 시나리오 | 단언 내용 | 실측 |
|---|---|---|---|
| T1 | determinism + independent re-derivation + partition coverage | 동일 시드 2회 도출 동일(동일 2회 동일) + ls-tree→classify→sort→sha256 독립 재도출 일치 + 분할 덮음(S∪N=universe) + 배제표 자기일관 | **PASS** |
| T2 | excluded-class byte change (docs/evidence) | **docs-only 불변** — 배제-class 바이트 변경 시 probe 트리 OID는 전진, 키 멤버는 불변(p2) | **PASS** |
| T3 | normative face mutation (docs/spec) | **정책·스펙 면 변경 시 전진** — 컴파일·게이트가 소비하는 normative 면 변경 → digest 전진 | **PASS** |
| T4 | computed staticRead target mutation (config/templates·config/policy) | computed 정적 읽기 대상 변경 → digest 전진(k12 carve-out 증명) | **PASS** |
| T5 | fail-closed: probe/witness | **멤버 부재→거부** — 미해석 probe(40-zero·비hex, p1/p4)·배제 증인(W∩N=∅)·결손 증인(W⊆S) 전부 거부 | **PASS** |
| T6 | k12 drift guard | **도출기 선언 ⊇ literal+computed staticRead** — 실트리 census 2,350 .nim: literal 대상 25 전수 선언 일치 + computed 사이트 47 전수 선언 일치(미해석 4건 lenient skip) | **PASS** |

## §5. 참조

| 대상 | 지위 |
|---|---|
| PR #695 — feat(verification): VS-2 judgment key ⑤ v3 semantic set digest (계약 v1.0.3) | **구현 반송** — 작성 시점 OPEN, 병렬 착지 |
| PR #691 — fix(ci): S5 ircheck 공급 복원 (DEBT#502) | **MERGED** `b64053c7f` — VS-1 |
| `docs/spec/test_judgment_cas_contract.md` v1.0.3 | 정본 계약 — §4.1(#695 반송 개정) |
| `docs/spec/head_binding_semantics.md` | v2 세대 축 결정 기록(§2 과잉 무효화 수용 — v3가 정밀화하는 대상) |
| DEBT#502 — S5 build-skip supply 재사용 불가 | VS-1(#691)이 폐쇄 |

## §6. 착지 체인 (`git log origin/main --oneline -15`, 2026-10-10 기준)

| 순 | PR | 병합 커밋 | 내용 |
|---|---|---|---|
| 1 | #697 | `54dd784bf` | SPEC-B36-COUT S2 판정 기록 (docs/evidence) |
| 2 | #694 | `650699784` | base36 C_out 판정 코어 — single-origin carrier + P4 터미널 (ROTATION) |
| 3 | #692 | `d66a6f0cb` | B4 정량자 닫기 (docs/history) |
| 4 | #691 | `b64053c7f` | **S5 ircheck 공급 복원 (DEBT#502) — VS-1** |
| 5 | #690 | `83503ef68` | A2-2 양성 픽스처 |
| 6 | #689 | `15da70d87` | SPEC-B36-COUT 계약 채택 (S0) |
| 7 | #688 | `9d82b5ca9` | ④ pin-anchor 전 경로 평가 정정 |

병렬 진행(작성 시점 OPEN — 본 PR은 건드리지 않음): **#695**(본 슬라이스 구현),
**#696**(게이트 빌드 전 nimble build 선행). 본 문서를 반송하는 PR은
`docs/judgment-key-v3-evidence`이며, 병합 SHA는 GitHub 원장 기록이 권위다(§2.3).

## §7. 재현 명령

```
make test-fast-one T=tests/unit/test_judgment_set_derivation.nim   # M1 — T1–T6 (PR #695 트리)
make test-fast-one T=tests/unit/test_judgment_cas.nim              # M2 — G1–G10 (PR #695 트리)
gh pr view 695 --json state,mergedAt,mergeCommit                    # 구현 반송 상태
git log origin/main --oneline -15                                   # 착지 체인
```
