# Test-Judgment CAS Contract — GO-critical admission 테스트 판정의 재사용 근거 (§15.3-class)

> **Status**: Phase 0 — NORMATIVE CONTRACT ONLY (no implementation, no CI wiring, no code
> change). This document defines the vocabulary and the five-condition reuse basis for
> **test-judgment reuse** (reusing a prior GO-critical admission test execution's judgment)
> before any implementation slice may wire it.
> **작성일**: 2026-10-08. **최종 개정**: v1.0.6 (2026-11-01 — §4 성분 ⑤ R = 후보 M^{tree} 실측 정정, 스킴 v5 무변경).
> **계열**: `docs/spec/execution_accounting_contract.md` §15 어휘를 재사용한다 — 새 분류
> 체계를 만들지 않는다. **freeze 비개정**: `docs/spec/productization_contract_freeze_v1.md`
> (FROZEN, E1–E5)은 본 문서로 인해 변경되지 않는다 (§2 — SL-15 전례).
> **비용 근거(실측)**: `docs/evidence/go_critical_test_cost_2026-10-08.md` (§0.11 — 숫자는
> 원 계산 경로: run ID + 측정 명령 기록).

---

## 1. 목적과 대상 (Purpose & Target)

**Test-judgment**는 GO-critical admission 테스트 1건의 실행 판정이다:
`make test-fast-one T=<test>` 1회의 (컴파일+실행) 결과 — `PASS`/`FAIL` 종결 상태와 그
판정 projection. 대상 집합은 DEBT#432 Slice B로 어드미션에 배선된 4종
(`.github/workflows/admission-check.yml:751`):

- `tests/unit/proof_integrity_test.nim`
- `tests/unit/test_s1a_lean_golden.nim` (producer E2E: funcDef → IR → Lean 4.33 kernel
  ACCEPT → KAA → vdVerified)
- `tests/unit/test_d2_golden.nim`
- `tests/unit/test_d2_persist.nim`

**문제(실측)**: 동일 head tree가 하루 안에 pull_request 체크 단계와 merge_group 큐 단계에서
같은 4테스트를 **전부 재실행**한다 (PR #603 실측: 4합 523.7s + 512.3s ≈ 17.3분의 동일
계산 — `docs/evidence/go_critical_test_cost_2026-10-08.md` §3.2). s1a 단건은 런당 평균
274.0s(스텝의 59.2%).

**이 문서가 정의하는 것**: 사전 실행 판정을 **REUSED satisfaction**으로 분류하기 위한
상태 어휘(§3)와 5조건 근거(§5), fail-closed 규칙(§6), 그리고 "서명 아님"의 의미(§7).
**이 문서가 허용하지 않는 것**: 그 자체로 어떤 구현·배선도 (§8).

## 2. Freeze 비개정 — SL-15 전례 (No ContractRevision)

`productization_contract_freeze_v1.md` §3은 E1–E5(테스트 존재·CI 실행·실패 전파·뮤턴트
사망·릴리스 E2E)를 동결하며, E2 위반("CI가 실행하지 않는 테스트는 보존 증거가 아님")이
개정 없이는 불가하다. Test-judgment reuse는 이 동결을 **개정하지 않는다**:

- **EXECUTED가 기본 경로로 유지된다.** 재사용은 CI 실행을 대체하는 것이 아니라, CI가
  이미 실행한 판정의 재분류다. E2("CI executes them")는 변하지 않는다 — 재사용이
  성립하지 않는 모든 경우(§6) 원래 실행이 발화한다.
- **REUSED는 fresh-execution 증거가 아니다.** `execution_accounting_contract.md` §15.0의
  부정 절반이 그대로 적용된다 — 재사용은 acceleration이지 fresh-execution witness가
  아니며, 재사용은 그 자체로 어드미션 verdict를 만들지 못하고(§17 rule-8의 basis 요건),
  §5 조건 재검증을 통과한 REUSED만이 satisfaction으로 분류된다.
- **전례**: Evidence CAS(SL-15, PR #493)는 동일한 구조 — §15.3 스킵의 제도화 — 로
  freeze 개정 없이 착지했다 (`docs/evidence/evidence_cas_baseline_2026-10-06.md`).
  HIT = "the sanctioned §15.3 skip of chain stages b+c, after full re-verification";
  MISS = 정본 레코드 생성; NO-FIRE = byte-identical legacy 경로. 본 계약은 동일 3상태
  구조를 test-judgment에 적용한다.

Scope Closure Rule(§2.3) 관점: 본 문서는 새 acceptance predicate을 도입하지 않는다 —
기존 §15 어휘(REUSED/FRESH, PROVEN basis)를 검증 실행의 한 종류(test-judgment)에
적용하는 규범 문서다.

## 3. 상태 어휘 — EXECUTED / REUSED (기존 축 재사용)

`execution_accounting_contract.md` §15.1의 3축을 test-judgment에 투영한다 (새 축 없음):

| Status | SatisfactionSource (§15.1) | ExecutionEvidence (§15.1) | 판정 성립 |
|---|---|---|---|
| **EXECUTED** | FRESH | ATTEMPTED | 이번 어드미션 실행에서 테스트가 실제 실행(컴파일+런)되어 종결 판정을 산출 |
| **REUSED** | REUSED | NOT_ATTEMPTED | 이번 실행에서는 실행하지 않았고, §5 5조건을 통과한 사전 실행의 test-judgment를 satisfaction으로 채택 |

Run-level 대응: EXECUTED 판정은 §17 rule-7의 `PASS basis PROVEN` 재료, REUSED 판정은
§17 rule-8의 `PASS basis REUSED` 재료다 — rule-8의 전제("VDA verified the per-row
5-condition basis")가 본 계약의 §5 그 자체다. REUSED basis 미성립 행은 rule-4
(PENDING → INCONCLUSIVE)로 떨어지며 PASS 재료가 되지 못한다.

NO-FIRE(배선 부재/미도입) = 이 어휘 자체가 발화하지 않는 상태다: 모든 test-judgment는
EXECUTED이고 시스템은 오늘과 byte-identical하게 동작한다 (SL-15의 NO-FIRE와 동일).

**s1a의 REUSED (v1.0.5 — 2026-10-18 재결정의 계약화)**: s1a judgment도 다른 subject와
**동일한 5조건**(§5)으로 REUSED가 성립한다 — landing venue(merge_group)를 포함해 어느
venue에서든 같다. v1.0.4까지 s1a는 landing venue에서 plan 단계가 REUSED를 내지 않았고
(GO lane·attest가 REUSED s1a를 hard-fail), 그 결과 "착지마다 s1a를 다시 실행"이 강제되었다.
v1.0.5는 그 예외를 **삭제**한다: 2026-10-18의 재결정은 이제 계약이다. 단, REUSED 승인된
exec record는 `verdict=UNKNOWN basis=REUSED`로 기록된다 — EXECUTED/PASS와 동일하게
표현·기록하지 않는다(§5.3 UNKNOWN 원칙). 승인의 근거는 decision·attest의 basis/decision
대조이지 실행 결과가 아니다.

## 4. Test-judgment closure identity — 9성분 (조건 (a)의 정체성)

REUSED의 키는 "같은 테스트 판정"이 아니라 "같은 **실행 클로저**"다. 클로저 지문은 아래
9성분의 결합 해시다(구성 순서는 직렬화 규격으로 구현 슬라이스가 고정하며, 본 문서는
성분 집합을 고정한다). 성분 1–3은 WorkUnitFingerprint의 `sourceClosureDigest`
(`workunit_fingerprint_cas_contract.md` §2.1)를 테스트 실행으로 특화한 것이고, 성분 4,
8–9는 `toolchainDigest`/`executionConfigDigest`에 대응한다.

| # | 성분 | 내용 | 원 계산 경로(구현 참조) |
|---|---|---|---|
| 1 | 테스트 소스 digest | 테스트 파일 자체의 SHA-256 | `sha256(tests/unit/test_s1a_lean_golden.nim)` |
| 2 | 전이 클로저 digest | 테스트가 import하는 src/ 전이 종속 closure의 결합 digest | P2 dependency closure (ADR-0017 보존본 참조) |
| 3 | 픽스처 digest | 테스트가 읽는 golden/fixture 입력의 결합 digest | 테스트가 로드하는 데이터 파일 집합 |
| 4 | 툴체인 번들 digest | canonical execution bundle fingerprint | `identity.nim:188` (`canonicalExecutionBundleFingerprint`) |
| 5 | 검증자 세대 집합 digest | **⑤ v3 — semantic set digest**: S = TreeUniverse(R) − N 의 집합 digest (정렬된 `git ls-tree -r -z <R>` NUL-레코드 스트림의 sha256 — 도출 권위는 단일 모듈 `src/verification/semantic_set_derivation.nim`, §4.1). R(피험 트리 OID) 자체는 **키 밖 probe 앵커**다 — b-probe-tree 4명제(§4.1): 호출자 객체 저장소 해석 가능 / 키 비참여 / decision-file provenance 일치 / 검증 불가 시 REUSED 금지→EXECUTED 폴백. v1.0.2까지의 B^{tree} 전체 결속은 문서 머지마다 과잉 무효화를 만들었다 — v1.0.3이 이를 **정밀화**한다 (참 무효화는 보존: 검증자 소스·정책·스펙·컴파일 입력 변경은 §4.1 배제표가 S에 유지하므로 여전히 키를 전진). R은 **후보 피험 트리 M^{tree}**다 — 베이스 팁 ∪ PR 변경의 merge-queue 후보 머지 커밋 트리(B/M 분할 f96f37f5d, 2026-10-20; 워크플로 judgment plan이 `AXIOM_JUDGMENT_CAS_TESTED_TREE_OID` = M^{tree}를 export — pre-split B-only 세대의 레코드는 이 클로저를 재유도할 수 없다). 커밋 OID는 9성분 어디에도 없으며, 트리 OID 차이와 N-class 델타 자체는 키를 움직이지 않는다 (2026-10-31 실측 정정 — 근거 `docs/evidence/judgment_key_v5_adjudication_2026-10-31.md`) |
| 6 | env 스냅샷 digest | 실행 허용 환경(allowedEnv) 스냅샷 | `ExecutionContract.allowedEnv` (`identity.nim:107-114`) |
| 7 | recipe digest | 빌드·실행 레시피 바이트 (`make test-fast-one` + NIM 플래그 + 출력 경로) | `Makefile:965-968` 레시피 + `tests/config.nims` 무결성 가드 조건 |
| 8 | NimVersion | 테스트 바이너리 컴파일러 버전 (성분 4의 구성원이지만 단독 노출) | bundle `nimVersion` (`identity.nim:178-186`) |
| 9 | 실행 구성 digest | 타임아웃·자원·workdir 등 ExecutionContract 밖 실행 파라미터 | `workunit_fingerprint_cas_contract.md` §2.1 `executionConfigDigest` |

**성분 1–3의 유도 위치 (v1.0.5)**: 성분 1–3은 이제 **작업 디렉터리가 아니라 피험 트리(M)의 git 객체**에서
유도된다 — 도출 권위 `src/verification/tested_tree_closure.nim`, 규칙·잔여 위험은 §4.2. 성분 4·6–9는
**executor/process 측정 그대로**다(executor 소유). 즉 **선택적 트리 유도**다: ①②③(+⑤)은 M에서,
④⑥⑦⑧⑨는 실행 주체에서. 이 분할이 plan(lane)과 attest의 키 일치를 **workdir 독립**으로 만든다
(§4.2.4). v1.0.4까지 ①②는 작업 디렉터리 상대 one-hop 측정이라 workdir가 흔들리면 키가 흔들렸다.


**ciGeneration은 9성분 어디에도 없다** — §15.4가 금지한다 (§5 조건 (b) 참조).

**클로저 동일 불변식은 검증자 세대 스코프다 (v1.0.1, v1.0.3 정밀화)**: 9성분 동일성은 "테스트가 읽는 입력(성분 1–4, 6–9)이 같다"와 "같은 검증자 세대(성분 5 — v3에서는 semantic set digest, §4.1)다"의 결합이다. main 측 커밋은 **S의 멤버를 변경할 때만** 클로저를 무효화한다 — non-normative 문서(docs/evidence 등 배제표 N-class) 변경은 더 이상 세대를 전진시키지 않으며(과잉 무효화 제거), normative 면(docs/spec, docs/agents, config/policy, config/templates)·컴파일 입력·소스·픽스처 변경은 여전히 키를 전진시킨다(참 무효화 보존 — §5(e) fail-closed 재측정의 축소가 아닌 정밀화). 새 세대에서 1회 원 실행 후 재사용이 재개된다. 반대로 커밋 OID·트리 OID 자체는 9성분 어디에도 없다 — ⑤가 보는 것은 후보 피험 트리 M^{tree}의 N-외 콘텐츠뿐이므로, N-class docs-only PR은 트리 OID가 달라도 동일 키로 재사용된다(2026-10-31 실측 — 다른 트리 OID에서 byte-identical 64-hex evidenceKeys; normative 1행 변경은 EXECUTED). (실측: #613 사이클 — PR-run 37818247021이 동일 B 세대 레코드 `7468b243…`을 REUSED, MG-run 37819660335는 세대 전진(#612 착지)으로 EXECUTED).

**HEAD 의미 3분법 (v1.0.2, v1.0.3 정밀화)**: 위 두 절의 "git 참조"는 세 의미로 분해된다 — ① 인과 입력(성분 1–4·6–9) ② 검증자 세대(성분 5 — v3: semantic set digest S; **약화 금지** — 축소 시 극장 경로 + 원장 same-key/different-payload 충돌. v3의 N 배제표 도입은 전진 조건의 **정밀화**지 약화가 아니다: 전진하는 변경 집합은 컴파일 입력·소스·정책·스펙·픽스처를 전부 포함하며, 배제되는 것은 무영향 근거가 등록된 비영향 클래스뿐이다) ③ 기록 정체성(run HEAD·mergeSha·runId·prHeadSha + probe tree OID = provenance 블록 한정, identity 비참여 — 단 probe OID는 §4.1 4명제의 검증 대상으로서 decision-file provenance에 기록된다). `obligation_semantics.md` §2.1a `|git=`(subjectGitRef)는 subject 고정 identity로 별개이며 본 계약 어디서도 개정되지 않는다. 전문·결정 기록·d2_golden 판정: [head_binding_semantics.md](./head_binding_semantics.md).

## 4.1 도출 권위 — 단일 도출기·정규화·분할 검증·잔여 위험 (v1.0.3)

성분 5의 집합 도출 권위는 **정확히 하나**다: `src/verification/semantic_set_derivation.nim`
(단일 도출기 모듈 + 단일 배제표 N). 다른 어떤 모듈도 S를 산출하거나 배제를 선언할 수 없다.

**핵심 공식** (기본-포함, default-include):

```
S = TreeUniverse(R) − N
검증(포함-증인): W ⊆ S ∧ W ∩ N = ∅   ← 위반 = 도출 FAIL (fail-closed → EXECUTED)
분할 검증: S ∪ N == TreeUniverse (각 경로가 정확히 한쪽에만 — 중복·누락 0, 기계 단언)
```

**정규화 3건 (사용자 보정 반영 — 비가역 결정)**:

1. **무손실 인코딩**: `path:sha256` 줄 형식 금지(개행 경로 모호). canonical 요소는
   `git ls-tree -r -z <testedTree>`의 NUL 레코드(`<mode> <type> <sha>\t<path>`) 그대로 —
   파일 유형(blob/tree/commit = 심볼릭 링크 120000·gitlink 160000 포함)과 모드가 자동
   결속된다. 정렬은 전체 레코드 바이트 순(LC_ALL=C 등가 — 로캘 무관 memcmp). 집합
   digest = 정렬·NUL-종단 레코드 스트림의 sha256.
2. **git 객체 도출 원칙**: 파일 내용은 절대 작업 디렉터리에서 읽지 않는다 — ls-tree의
   blob sha가 내용 정체성(git 객체 저장소 전용). 트리 밖 입력이 검증에 영향을 주면 다른
   키 성분(env/recipe/toolchain — 이미 존재)으로 결속되거나 도출 거부(fail-closed).
3. **상대 완전성 명시**: W ⊆ S는 "알려진 입력이 배제되지 않음"만 증명한다. (a) 배제표 N의
   각 규칙은 무영향 근거를 코드 인접 문자열로 필수 기재(빈 근거 = 도출기 자체 결함),
   (b) 분할 검증을 기계 단언, (c) 동적 경로·미발견 입력은 아래 잔여 위험 등록부에
   문서화 — 삭제 주장은 금지된다.

**b-probe-tree 4명제** (트리 OID의 키 밖 보존 조건 — 전부 기계 검증 대상):

| # | 명제 | 내용 |
|---|---|---|
| p1 | 호출자 객체 저장소 해석 가능 | probe OID는 호출자 checkout의 git 객체 저장소에서 `rev-parse --verify <oid>^{tree}`·`ls-tree`로 해석된다 — 로컬 파일시스템 추측 아님 |
| p2 | 키 비참여 | OID는 closure wire 어디에도 없다 (타입이 계약 — `JudgmentClosure.semanticSetDigest`만 존재). docs-only 커밋: probe 전진 + 키 불변 |
| p3 | provenance 일치 | plan의 decision file이 probe OID를 기록하고, attest가 현재 probe와 대조한다 (한 어드미션 런 = 하나의 트리) |
| p4 | 검증 불가 시 REUSED 금지 → EXECUTED 폴백 | probe 미해석·비정형·파생 실패는 절대 REUSED 근거가 아니다 — 원 실행이 발화한다 |

**게이트-축/실행-축 분리 (docs/spec 문언)**: normative 면(docs/agents, docs/spec,
config/policy)은 두 개의 독립 축에서 동시에 의미를 가진다 — **게이트-축**
(proof_unit_consistency_gate (g)가 docs/agents·docs/spec·config/policy를 스캔하는
규범 집행 축)과 **실행-축**(본 계약의 judgment key가 재사용을 무효화하는 축). v3는
실행-축의 전진 조건을 S로 정밀화할 뿐, 게이트-축을 대체하지 않는다 — normative 면은
배제 금지(W∩N=∅ 강제)이므로 어느 축에서도 조용히 사라지지 않는다. 반대로
non-normative 문서(docs/evidence 등)는 게이트-축의 대상이 아니며 실행-축에서도
배제된다 — 두 부재는 독립적 사실이다.

**잔여 위험 등록부 (상대 완전성 — 삭제 주장 금지)**:

| # | 잔여 위험 | 통제 |
|---|---|---|
| RR-1 | 선언되지 않은 computed-path staticRead(동적 컴파일 입력)가 배제표에 흡수될 위험 (k12 사각지대) | 도출기가 `ComputedStaticReadTargets`(정적 해석 대상 전수)·`ComputedStaticReadSites`(동적 사이트 파일)를 선언 + T6 표류 가드(실트리 staticRead 전수 ⊆ 선언)가 회귀 차단. 미선언 신규 사이트 = T6 FAIL |
| RR-2 | 선언된 증인 집합 W 밖의 런타임 파일 읽기(테스트 바이너리가 배제-class 파일을 실행 중 읽는 경우) | W는 선언된 known-input 집합이다 — 미지 런타임 읽기는 무영향이 아니라 '미증명'으로 운반된다. 배제표 규칙의 무영향 근거가 유일한 정당성 |
| RR-3 | 커밋 없이 재생성된 generated 파일 (src/generated/**) — workdir와 트리의 일시적 분기 | ⑤는 커밋된 트리만 본다; 나머지 성분(①–④·⑥–⑨)이 workdir를 측정하므로 분기는 어느 한쪽에서 전진을 만든다. 두 측정의 결합이 분기 흡수 |
| RR-4 | 서브모듈(gitlink 160000) 내부 변경 — `ls-tree -r`은 gitlink에서 멈춘다 | 기록되는 것은 고정 커밋 sha(올바른 정체성). 서브모듈 체크아웃 내부 바이트는 본 키의 대상이 아니다 |

## 4.2 M-tree 유도 — ①②③의 도출 권위와 R-NT 의존성 규칙 (v1.0.5)

성분 ①(테스트 소스 클로저)과 ③(픽스처)이 **작업 디렉터리가 아니라 피험 트리(M)의 git 객체**에서
유도된다. 도출 권위는 단일 모듈 `src/verification/tested_tree_closure.nim`이다 — ⑤의 도출 권위
(`src/verification/semantic_set_derivation.nim`)를 **확장하지 않고** 그 git 경계·레코드 정규화·다이제스트
함수를 재사용한다(단일 도출 권위 원칙 유지).

**왜 바꾸는가 (v4의 결함)**: v4의 ①은 `computeTransitiveHash(testPath, ".")` — 작업 디렉터리 상대
**one-hop** 측정이었다. package-style import(`import core/types/results`)가 전혀 해석되지 않아 측정 클로저는
19개 파일에 depth ≥ 2 = 0이었다 — 즉 실제 컴파일되는 소스의 대부분이 클로저 **밖**에 있었다. v5는 M의 트리에서
**다홉**으로 해석해 정직한 클로저를 측정한다(측정: s1a 222 파일 — v4의 19 대비).

**해석 순서 (컴파일러와 동일)**: import는 (1) importing 파일의 own 디렉터리, (2) 컴파일러의 `--path` 루트
(`src`·`tools`·`.`·`tests/gateway`·`src/shared_types` — config.nims + config/paths.nims의 집합) 순으로 해석된다
(compiler/options.nim `findModule` → `findFile`). `.`/`..`로 시작하는 token은 importing 파일에 대해
**엄격히** 상대다(컴파일러는 search path로 fallback하지 않는다). 컴파일러보다 좁게 해석하면 클로저가
과소 측정되고(위험), 넓게 해석하면 과잉 무효화가 된다 — 같은 루트 집합·같은 순서를 쓴다.

**import 추출**: Nim **AST**(`core/parser_utils.parseStringAST` over `compiler/parser`) — 라인 파서는
주석과 문자열 리터럴을 오독한다(`# ... import x` 주석이나 `import`가 mention된 docstring이 클로저에
들어가고, 진짜 import는 빠진다). `std/[a, b]` 괄호 그룹·`from X import y`·`as` 별칭·상대 경로
(`../../src/...`는 AST에서 prefix 표현식)를 모두 처리한다.

### R-NT 규칙 (verbatim) — 모든 import는 정확히 하나의 분류

| 분류 | 조건 | 클로저 입력 | 재사용 |
|---|---|---|---|
| (a) 트리 경로 | M의 경로로 해석됨 | 해당 경로의 **blob OID** (레코드 `<mode> <type> <oid>\t<path>`의 정렬·NUL-종단 스트림 sha256 — ⑤와 동일한 무손실 정규화) | 허용 |
| (b) 핀된 외부 모듈 | M의 `nimble.lock`가 핀하는 nimble 패키지, 또는 `nimble.lock`의 "nim" 엔트리가 커버하는 compiler-shipped 모듈(`compiler/*`) | lock 항목 정체성(name+version+vcsRevision+checksums.sha1) — **M의 `nimble.lock` 멤버십을 요구** | 허용 |
| (c) build-generated | M에 없으나 빌드가 생성하는 모듈 | 커밋된 템플릿의 blob OID (tree-bound) + 빌드 치환값(§4.2.2 executor-bound) | 전 값이 결속된 경우에만 허용 |
| (d) 미해석·미핀 | (a)(b)(c) 어느 것도 아님 | — | **불가** — plan은 jExecuted. "기록하고 건너뛴" 의존성으로 REUSED는 결코 허용되지 않는다 |

모든 (b)/(c)/(d) hit은 **decision file에 기록**된다 — 조용한 skip은 없다. (d) hit은 클로저를 재사용
불가능으로 만들어 plan이 jExecuted로 폴백하며, 그 사유 문자열에 hit이 명시된다.

**stdlib 클래스**: `std/**`·`system`·`nimsuggest/**`는 컴파일러 동봉이며 성분 ⑧(컴파일러 핀)이 결속한다 —
클로저 입력이 아니다. 단어 하나짜리 token을 stdlib로 **가정하지 않는다**: 단어 하나짜리 nimble 패키지
(`ed25519`)는 **M의 lock이 결정하는** (b) hit이다(v4의 라인 파서 휴리스틱은 `ed25519`을 stdlib로 오독했다).

### 4.2.1 ①과 ③의 해시 선택 (결정)

①은 **해결된 트리 멤버들의 blob OID**에 대해 해시한다 — 멤버 경로·모드·타입·blob OID를 ⑤와 동일한
`<mode> <type> <oid>\t<path>` 레코드로 직렬화해 전체 바이트 순으로 정렬·NUL-종단한 뒤 sha256을 취한다
(내용 동일성의 유일한 원천은 git 객체 저장소의 blob OID — 작업 디렉터리는 읽지 않는다). ③도 **같은 방식**으로
픽스처 경로 3개의 M-tree blob에서 digest를 낸다. **이유**: 성분 ⑤가 이미 그 정규화를 쓰고 있으므로 규범이
하나로 유지되고, workdir가 흔들려도 plan/attest의 키가 일치한다(§4.2.4). v4의 ③(작업 디렉터리 **내용**
digest)은 v5에서 트리 blob digest로 대체된다 — 세대 컷(v5)으로 구 레코드는 자연히 고아화된다.

### 4.2.2 (c) build-generated의 결속 · drift guard · 잔여 위험(RR-6)

`generated/build_env`는 gitignored — 어떤 트리에도 없다(빌드 산출물). 따라서 (c)로 떨어진다. 허용 조건:
- **tree-bound**: 커밋된 템플릿 `src/generated/build_env.nim.default`의 blob OID가 클로저 멤버다 →
  템플릿이 정의하는 상수값은 트리로 결속된다. `BuildEnvZ3Version`은 추가로 ⑧(컴파일러 핀)의 Z3 핀으로
  결속된다.
- **executor-bound**: 빌드가 **치환**하는 값(커밋 해시·커밋 수·빌드 일자·소스 해시·검증자 빌드 ID·
  verifier 소스 해시·프로젝트 루트)은 **executor 세대의 정체성**(④ toolchain + TWS/epoch 핀)에 결속되며
  클로저 wire에는 **의도적으로** 결속되지 않는다 — §4.1 p2(트리 OID는 wire 어디에도 없다)를 되살리면
  매 main 랜딩마다 키가 전진하는 과잉 무효화가 된다(v1.0.4가 제거한 바로 그 결함).
- **drift guard**: 템플릿의 export 심볼 집합과 선언된 심볼 집합(`tested_tree_closure.BuildGeneratedModules`)이
  다르면(새 상수 추가/삭제) 클로저는 **재사용 불가**가 된다 — 선언이 갱신되기 전까지 조용히 통과하지 않는다.

### 4.2.3 narrowing-only 멤버 — 핀 정체성

핀 정체성(lock 항목 identity)은 클로저 wire의 **narrowing-only 멤버**로 실린다 — `completenessKeys`/
`schemaVersion` 전례와 같다. 핀 변경은 이미 ⑤(nimble.lock은 정규 carve-out — W∩N=∅ 강제)와 ⑦(recipe 멤버)이
전진시키므로, 이 멤버는 **새로운 무효화 원천이 아니다** — 재사용이 어느 핀 위에 서 있는지를 **기록**한다.
narrowing-only: REUSED를 EXECUTED로만 바꿀 수 있다(오래된 기록을 되살리지 않는다).

### 4.2.4 plan/attest 키 일치 (workdir 독립)

성분 ①②③(+⑤)이 M의 트리에서 유도되므로 plan(lane)과 attest는 **어떤 작업 디렉터리에서 실행해도** 같은
클로저를 낸다. ④⑥⑦⑧⑨는 executor/process 측정값이라 실행 경로에 종속된다 — 현행 구조(양측이 같은 B
checkout·같은 cwd 문자열)를 유지하며 신규 의무를 추가하지 않는다.

### 4.2.5 잔여 위험 등록부 (추가분)

| # | 잔여 위험 | 통제 |
|---|---|---|
| RR-5 | (b)는 **핀을** 결속하지 **해석된 패키지 바이트**를 결속하지 않는다 — 공급망 변이(등록되지 않은 변이·삭제)는 이 키로 검출되지 않는다 | 핀 뒤 콘텐츠는 ④ toolchain 측정과 같은 취약 계층. §4.2.3 — "내용 미검증"으로 명시(삭제主张 금지) |
| RR-6 | (c)의 executor-bound 치환값은 클로저 wire가 아니라 executor 세대 정체성(④ + TWS/epoch 핀)에 결속된다 | §4.2.2 — 심볼 열거 + drift guard. "미측정"이 아니라 "다른 축에 결속"으로 기록 |

## 5. REUSED 성립 5조건 (test-judgment 적용 — §15.3 표의 투영)

사전 test-judgment 레코드(판정 projection + 클로저 지문 + content digest를 담는
canonical JSON)는 아래 5조건을 **모두** 통과할 때만 REUSED satisfaction이다. 표의
"§15.3 대응" 열은 원 조건과의 동일성을 고정한다 — 새 조건 체계가 아니라 동일 조건의
대상 치환이다.

| # | 조건 | test-judgment 적용 | 검증 대상 | §15.3 대응 |
|---|---|---|---|---|
| (a) | 클로저 동일성 | 레코드의 9성분 클로저 지문 == 현재 실행의 재계산 지문 (§4 — v3: 성분 5는 semantic set digest, §4.1 단일 도출 권위) | 테스트의 현재 전이 소스 클로저·픽스처·트리 | (a) subject identity — `subjectFingerprint` 대조 |
| (b) | executionEpoch 일치 | 레코드 `validatedAtEpoch == ctx.currentEpoch` — `sha256(toolchainIdentity \| executionConfigDigest \| executionBundleFingerprint)` | 현재 `executionEpoch` (§15.4) | (e)의 epoch 절반 — `validatedAtEpoch` 대조 |
| (c) | per-read 재해시 | 레코드 바이트를 **읽을 때마다** 재계산한 SHA-256 == 레코드 `contentDigest` | 저장 레코드 자체 | (d) evidence artifact — `artifactVerified` 패턴 (IO-side reader가 매 읽기 재해시) |
| (d) | witness 바인딩 | 레코드에 봉인된 **판정 projection + 그 digest**가 재독출 바이트와 동일 (byte-equality) — mint exactly-once append의 입력 정합 (P7b 상당, §7) | 판정 projection(종결 상태·판정 digest·subject 결속) | (d)의 digest byte-equality를 판정 projection으로 특화 |
| (e) | 도구 정체성 | 판정을 산출한 실행 주체의 도구 정체성(B-built ax identity·툴체인 번들) == 현재 도구 정체성 — **v1.0.3 정밀화**: 검증자의 소스·정책·스펙·컴파일 입력 변경은 ⑤(S)를 통해 계속 키를 전진시킨다(§4.1). 본 조건은 B executor의 측정 정체성(번들·핀)만 담당하며 v3로 인해 변경되지 않는다 | B executor tree의 바이너리 identity | (b)+(e) execution/tool identity — `executionBundleFingerprint`·`toolchainIdentity` 대조 |

**타임스탬프는 audit-only다**: `recordedAt` 등 시각 필드는 감사 투영일 뿐 조건 입력이
아니다. 정체성에 들어가는 시간 양은 `executionEpoch`(§5-b)뿐이고, 이는 클로저 이동에만
움직인다 — `ciGeneration`은 identity 구성원이 될 수 없으며(§15.4 "never an identity
constituent"), 워크플로 위상 변경(cutover)만으로 유효한 판정이 무효화되거나 반대로
무효한 판정이 살아나는 경로를 금지한다.

**per-unit 결합 규칙(§15.3 per-unit rule 재사용)**: 4테스트 블록의 REUSED 성립은 4건
전부의 조건 통과를 요구한다 — 하나라도 기각되면 블록 전체가 fail-closed로 EXECUTED
전환한다(§6).

**s1a에도 동일 적용 (v1.0.5)**: 5조건은 s1a를 포함한 **모든** judgment subject에 동일하게 적용된다 —
landing venue(merge_group)를 포함한 모든 venue에서 같다. v1.0.4까지는 s1a만 예외였고(landing venue에서
REUSED 금지), 그 예외는 2026-10-18 재결정의 계약화로 **폐기**되었다. 조건 (a)의 클로저 동일성은 v5에서
M-tree 유도의 ①②③으로 판정되고(§4.2), (b)·(c)·(d)·(e)는 다른 subject와 동일한 기계다(plan-time consult →
attest 재인증 → rootRecord provenance).

**REUSED의 표현 원칙 (UNKNOWN)**: REUSED로 승인된 실행의 exec record는 `verdict=UNKNOWN basis=REUSED`로
기록된다 — EXECUTED/PASS와 **동일한 실행 결과로 표현·기록하지 않는다**. 승인의 근거는 decision의 basis와
attest의 재인증 대조(레코드 재-fetch·재해시·epoch 대조·projection byte-equality)이지 "실행 결과"가 아니다.
(§15.4 "ciGeneration은 identity 구성원이 될 수 없음"과 같은 방향의 표현 규율.)

## 6. Fail-closed (조건 불충족 → 원래 검증 실행)

- 5조건 중 하나라도 불충족(누락 레코드·digest 불일치·epoch 불일치·도구 정체성 불일치·
  projection 비일치) → **REUSED 아님 → 해당 테스트를 원래대로 실행한다**
  (`make test-fast-one` — 레시피·플래그·게이트 무변경). 이는 §15.3의 "basis NOT
  established → PENDING"과 달리 test-judgment에는 더 강한 기본값을 쓴다: 어드미션
  블록에는 count-only PENDING 경로가 없으므로, 미성립은 항상 "EXECUTED로 회귀"다.
- **NO-FIRE 기본**: 계약 미배선·scope 미지정 런은 레코드 조회 자체가 없다 — 오늘의
  byte-identical 실행 (SL-15 NO-FIRE 구조 재사용).
- **조회 실패도 MISS다**: 사이드레프 조회의 네트워크·권한 실패는 HIT로 절대 해석되지
  않는다 (Evidence CAS의 "GITHUB_TOKEN not set → fail-closed" 전례,
  `evidence_cas_baseline_2026-10-06.md` §incident).
- **timeout/불완전 판정은 REUSED 대상이 아니다**: TIMEOUT·비종결·비정상 종료 판정은
  §17 rule-2의 INCONCLUSIVE 재료 — 불완전 증거(incomplete evidence)이므로 레코드로
  저장될 수는 있어도(audit-only) 절대 재사용되지 않는다. `recordedStatus`가 종결
  PASS인 레코드만 (d)의 witness 바인딩을 가질 수 있다. 반대 방향도 고정: FAIL은
  재사용의 대상이 아니라 원 실행의 종결 결과로 전파된다(E3 — non-zero → job FAIL
  경로는 재사용과 무관하게 유지).

## 7. "서명 아님" — 위조 방어의 실체 (Explicit Non-Signature)

test-judgment 레코드는 **Ed25519 서명된 certificate가 아니다** — witness급 무서명
산출물이다 (`duplicate_judgment_s3.md` D9의 witness(무서명) vs certificate(서명) 구분
그대로). 위조 방어는 서명이 아니라 다음 세 기제의 결합이다:

1. **해시 바인딩**: 레코드는 자기 판정 projection의 SHA-256(content digest)과 9성분
   클로저 지문(§4)을 결속하며, 소비자는 **매 읽기마다 재해시**한다(§5-c). 키 조작·
   페이로드 스왑은 digest 불일치로 즉시 fail-closed 된다.
2. **mint 단일 append**: 레코드의 원장 편입은 privileged tier(mint)의 **exactly-once
   append**뿐이다 (P7b — `admission-check.yml:1125-1146` "produced on MISS … rebound
   on HIT (same key + same payload bytes — the append is an idempotent no-op)"). 생산
   어드미션 런은 자기 레코드를 발행만 하고 원장에 쓰지 않는다 — TrustedWriterSet 단일
   라이터 불변이 그대로 유지된다.
3. **read-only attest**: 소비(attest) 경로는 원장 사이드레프를 **읽기 전용**으로
   consult하고, HIT 재결속은 "same key + same payload bytes"일 때만 성립한다.

이 구조는 SL-15 Evidence CAS와 동일한 방어 모델이며, 서명 부재가 위조 허용을 의미하지
않는다: 서명이 증명하는 것(발행 주체 귀속)은 여기서 원장 exactly-once성과 해시 결속이
대신 담당하고, 그 대가로 소비 경로는 서명 검증이 아닌 **재해시+재유도 대조**(§5 전체)
를 수행한다. 서명을 추가하는 변경은 본 계약의 확장이며 별도 슬라이스로만 가능하다.

## 8. 본 문서가 승인하지 않는 것 (Out of Scope — 구현 전제)

1. **구현·배선 금지**: 본 문서는 규범 정의만 담는다. 구현 슬라이스는 별도 workstream
   브랜치(§2.1)에서, 최소 (i) 9성분 클로저 재계산기, (ii) 레코드 스키마+content digest,
   (iii) mint append 소비처, (iv) fail-closed 회귀 배선을 계약 준수로 제공해야 한다.
2. **TCB 판정 의무**: 구현 후보는 `ci_optimization_tcb_judgments.md`의 4 판정(J1
   semantic parity·J2 evidence equivalence·J3 cache soundness — restore-keys 금지·
   J4 worker determinism)을 통과해야 VALID다. 특히 J3: "판정은 항상 재계산된다" 원칙과
   본 계약의 관계는 §2의 문장(재사용은 판정 재분류지 재계약이 아니다)으로 통제된다.
3. **freeze 개정 아님**: E1–E5·P1–P6의 어떤 문구도 본 문서로 변경되지 않는다(§2).
   본 계약을 이유로 한 동결 축소 시도는 Scope Closure Rule 위반이다.
4. **효과 수치 선주장 금지**: HIT-path 절감 효과는 구현 후 실측으로만 주장한다.
   baseline은 `docs/evidence/go_critical_test_cost_2026-10-08.md`(s1a 평균 274.0s,
   스텝 평균 462.4s, 런 평균 923.1s — 2026-10-08 창, n=7)다.

## 9. 변경 이력

| 버전 | 날짜 | 변경 |
|---|---|---|
| v1.0.0 | 2026-10-08 | Phase 0 초안 — 상태 어휘(§3), 9성분 클로저 identity(§4), REUSED 5조건(§5), fail-closed(§6), non-signature(§7) 규범. 실측 baseline: `go_critical_test_cost_2026-10-08.md` |
| v1.0.1 | 2026-10-09 | §4 성분 5 원 계산 경로 정정 — "H/G tree OID" → B^{tree} (구현·런 실측 일치: #613 사이클 env 덤프). §4에 클로저 동일 불변식의 검증자 세대 스코프 명시. 근거: `docs/evidence/judgment_cas_reused_hit_root_cause_2026-10-09.md` |
| v1.0.2 | 2026-10-09 | §4에 HEAD 의미 3분법 명시(① 인과 입력 ② 검증자 세대 B^{tree} 유지·약화 금지 ③ 기록 정체성 provenance 한정) + §2.1a 비개정 선언. 전문·결정 기록·d2_golden 판정은 `docs/spec/head_binding_semantics.md`로 위임 — 성분 집합·5조건·fail-closed 무변경 |
| v1.0.3 | 2026-10-10 | **§4.1 신설 — ⑤의 단일 도출 권위 개정 (VS-2)**: 성분 5를 B^{tree} 전체 결속에서 semantic set digest S = TreeUniverse(R) − N으로 정밀화 (근거: ⑤=B^{tree}는 문서 머지마다 과잉 무효화 — v1.0.2가 이미 인정한 결함; 정밀화이며 참 무효화는 보존 — 검증자 소스·정책·스펙·컴파일 입력은 S에 유지되어 여전히 키를 전진). 정규화 3건(무손실 ls-tree -z 인코딩·git 객체 도출 원칙·상대 완전성) + 분할 검증 기계 단언 + b-probe-tree 4명제(키 밖 probe 앵커) + 잔여 위험 등록부 + 게이트-축/실행-축 분리 문언. 스킴 v2→v3 (구 세대 레코드 고아화, 새 세대 첫 실행=EXECUTED, 원장 payloadSha256 봉쇄 상속 — 페이로드 스키마는 v2 유지). 구현: `src/verification/semantic_set_derivation.nim` (단일 도출기) + `judgment_cas.nim` ⑤ 교체 |
| v1.0.4 | 2026-10-18 | **§4.1 p2 구현 순응 — closure wire의 트리 OID 완전 배제 (스킴 v3→v4)**: v3 클로저는 narrowing-only 멤버 `verifierIdentity`(= H(B^{tree}, recipe, pins) — evidence_cas `composeVerifierIdentity`)를 wire로 운반해 §4.1 p2("OID는 closure wire 어디에도 없다 — 타입이 계약")를 위반했고, B는 매 랜딩마다 전진하므로 S가 불변인 docs-only 랜딩 사이에서도 키가 전진했다 — v1.0.3이 ⑤에서 제거한 과잉 무효화가 부재 멤버로 재유입된 것. 본 개정은 **계약 개정이 아니라 구현의 기존 계약 순응**이다 — `verifierIdentity` 멤버·양 collector의 B^{tree} 측정 블록·`AXIOM_JUDGMENT_CAS_BASE_TREE_OID` env 봉선을 제거하고(§4 성분 1–9+narrowing-only 완전 보존), 검증자 실행 정체성은 ④+⑧(§5(e)), 검증자 소스·정책·스펙은 ⑤ S가 계속 결속. **Evidence CAS 측은 불변** — `AXIOM_EVIDENCE_CAS_BASE_TREE_OID`→`verifierIdentity` 결속은 SL-15 evidence identity의 정당한 B^{tree} 바인딩으로 유지(테스트 핀 유효). 스킴 v3→v4 (v2→v3 전례대로 구 세대 레코드 고아화 — 신세대 첫 실행 1회 EXECUTED 후 REUSED 재개, 원장 payloadSha256 봉쇄 상속, 페이로드 스키마 v2 유지·투영 멤버 무이동). 구현: `src/verification/judgment_cas.nim` + `.github/workflows/admission-check.yml` (judgment BASE export 3행 제거 — TESTED/probe 앵커 유지) |
| v1.0.5 | 2026-10-21 | **§4.2 신설 — ①②③의 M-tree 유도 + R-NT 규칙 + s1a REUSED 계약화 (스킴 v4→v5)**: ①(테스트 소스 클로저)·③(픽스처)이 **작업 디렉터리가 아니라 피험 트리(M)의 git 객체**에서 유도된다(신규 도출 권위 `src/verification/tested_tree_closure.nim` — ⑤의 git 경계·정규화·다이제스트를 재사용, 확장 아님). v4의 ①은 workdir 상대 **one-hop** 측정이라 package-style import가 전혀 해석되지 않았다(19 파일·depth ≥ 2 = 0) — v5는 **다홉** 해석의 정직한 클로저(측정 s1a 222 파일)를 산출하고, plan/attest의 키 일치를 **workdir 독립**으로 만든다(§4.2.4). 의존성 규칙 **R-NT** 4분류를 규범화: (a) 트리 경로 → blob OID, (b) 핀된 외부 모듈 → `nimble.lock` 항목 정체성(name+version+vcsRevision+sha1, M의 lock 멤버십 요구), (c) build-generated → 커밋된 템플릿 blob(tree-bound) + executor 세대 정체성에 결속된 치환값(§4.2.2 executor-bound, drift guard 포함), (d) 미해석·미핀 → **재사용 불가**(jExecuted 폴백 — "건너뛴 미핀 의존성"은 REUSED를 주지 않는다). 모든 (b)/(c)/(d) hit은 decision file에 기록된다(조용한 skip 금지). stdlib 클래스는 ⑧가 결속하고, 단어-하나 token은 stdlib로 가정하지 않는다(단어-하나 nimble 패키지는 lock이 결정하는 (b)). 핀 정체성은 **narrowing-only wire 멤버**(§4.2.3 — 핀 변경은 이미 ⑤+⑦이 전진시키므로 새 무효화 원천이 아니다). **s1a REUSED 계약화**: 2026-10-18 재결정이 계약이 되어 s1a도 다른 subject와 **동일한 5조건**으로 landing venue를 포함한 모든 venue에서 REUSED가 성립한다(plan의 s1a 강제 제거 + GO lane의 s1a REUSED 거부·EXECUTED+1/1 강제 제거 + attest의 s1a REUSED 거부·EXECUTED+PASS 강제 제거) — 단 REUSED 승인 record는 `verdict=UNKNOWN basis=REUSED`로 표현한다(§5 UNKNOWN 원칙). 잔여 위험 RR-5((b)는 핀을 결속하나 해석된 패키지 **바이트**는 결속하지 않음)·RR-6((c)의 executor-bound 치환값은 executor 세대 정체성 축에 결속) 추가. **스킴 v4→v5**: scheme 문자열("schema" wire 멤버) 컷만으로 v4 레코드는 전부 키 미스로 **자연 고아화**된다(v2→v3→v4 전례) — 구 레코드는 불변 원장 이력으로 남고 v5 append와 충돌·재검증될 수 없다; 신세대 첫 실행은 EXECUTED(재-mint) 후 REUSED가 재개된다. 페이로드 스키마 v2 유지(투영 멤버 무이동) — 원장 payloadSha256 봉쇄 상속. 구현: `src/verification/tested_tree_closure.nim`(신규) + `src/verification/judgment_cas.nim` + `.github/workflows/admission-check.yml` |
| v1.0.6 | 2026-11-01 | **§4 성분 ⑤ 원 계산 경로 실측 정정 — R = 후보 피험 트리 M^{tree} (스킴 무변경)**: v1.0.3-era 문언의 pre-split H/G-vs-B 프레이밍("H/G 피험 커밋 트리가 아니다"·"PR 자체 커밋(H/G 트리)은 9성분 어디에도 들어가지 않는다")을 현재 구현 시맨틱으로 정정 — 피험 트리 R은 **후보 M^{tree}**(베이스 팁 ∪ PR 변경의 merge-queue 후보 머지 커밋 트리, B/M 분할 f96f37f5d 2026-10-20; `admission-check.yml` judgment plan이 `AXIOM_JUDGMENT_CAS_TESTED_TREE_OID` = M^{tree}를 export — pre-split B-only 세대의 레코드는 이 클로저를 재유도할 수 없다)이고, 키는 콘텐츠 digest만으로 구성된다 — 커밋 OID는 9성분 어디에도 없으며 트리 OID 차이·N-class 델타 자체는 키를 움직이지 않는다(N-class docs-only는 다른 트리 OID에서도 동일 키 재사용, normative 1행 변경은 EXECUTED). 성분 집합·5조건·fail-closed·스킴 v5 무변경. 근거: `src/verification/judgment_cas.nim:421-468`(9성분 클로저 — digest 전용, OID 멤버 부재) + `src/verification/semantic_set_derivation.nim:20-24`(R = TESTED tree = `AXIOM_JUDGMENT_CAS_TESTED_TREE_OID`) + `.github/workflows/admission-check.yml:3126-3216`(M^{tree} 유도·export) + 2026-10-31 운영 실측 `docs/evidence/judgment_key_v5_adjudication_2026-10-31.md` |
