# CI Epoch Record Addendum — judgment key v4 세대 전환 (2026-10-18)

> §2.5 CI Epoch Cutover — Freeze · Record · Cutover의 addendum. 정본 규칙:
> `AGENTS.md` §2.5 / `docs/agents/ci_epoch_cutover.md`. 형식 선행 기록:
> [ci_epoch_record_mg_reuse_eligibility_2026-10-18.md](ci_epoch_record_mg_reuse_eligibility_2026-10-18.md).
> 계약 근거: `docs/spec/test_judgment_cas_contract.md` §4.1 p2 + §9 v1.0.4 행 —
> 본 전환은 **계약 개정이 아니라 구현의 기존 계약(p2) 순응**이다.
> **전환 물건(동일 PR, 두 커밋 — mg-reuse-eligibility 선례)**: (1) 코드 커밋 —
> `src/verification/judgment_cas.nim` (스킴 v3→v4 · `verifierIdentity` 필드/wire
> 멤버/validate 항목 제거 · 양 collector의 B^{tree} 측정 블록 제거 ·
> `AXIOM_JUDGMENT_CAS_BASE_TREE_OID` plan/attest 소비 제거 — attest TESTED 검사 유지)
> + `.github/workflows/admission-check.yml` (judgment BASE export 3행 제거 —
> :2712-2715 TESTED/probe 앵커 유지) + `docs/spec/test_judgment_cas_contract.md`
> (§9 v1.0.4 행) + `tests/unit/test_judgment_cas.nim` (G1 11→10 · G6~G12/G11
> 시그니처 갱신 · G12 closureWire 고정 멤버 집합 회귀 핀 신설);
> `tests/verification/test_evidence_cas_identity.nim` **무변경** — evidence 측
> `verifierIdentity` B^{tree} 결속은 SL-15 evidence identity의 정당한 바인딩으로
> 유지(§2 Q2). (2) 핀 커밋 — `config/trusted_writer_set.json`
> (trustedCheckerTreeClosure 재앵커 + trustedAdmissionWorkflowSha 회전) +
> `config/policy/epoch_manifest.json` (productionExecutionPin 회전) + 본 문서.

## 1. Freeze

| 항목 | 값 |
|---|---|
| freeze tag | `ci-freeze-judgment-key-v4-20261018` (annotated) — **변경 이전 세대**(스킴 v3 + wire `verifierIdentity` 멤버; judgment_cas.nim blob `0c90e0a7a5…`, admission-check.yml blob `ab4460fa36…`)를 가리킨다 |
| tag → commit | `582a3e9b7` (main — PR #922 병합 지점; 롤백 기준선) |

## 2. Record — 세대 상태 전이

### 2.1 구세대 (v3 — `axiom.judgment.cas.key.v3`)

- closure wire가 narrowing-only 멤버 `verifierIdentity`를 운반했다 —
  H(**B^{tree}**, recipe, pins) (`evidence_cas.nim` `collectVerifierIdentityInputs`
  → `composeVerifierIdentity`, judgment 쪽 소비는 `judgment_cas.nim` collector 2곳).
- B는 매 merge_group 착지마다 "직전 랜딩의 머지 결과"로 전진하므로 — S가 불변인
  docs-only 랜딩 사이에서도 — 클로저 키가 매 랜딩 전진했다. 이것이 v1.0.3이 성분 ⑤에서
  제거한 과잉 무효화(문서 머지마다 키 전진)가 부재 멤버로 재유입된 경로이며,
  §4.1 p2("OID는 closure wire 어디에도 없다 — 타입이 계약") 위반이다.
- **음성 관측(#922)**: E2E 검증 차량 PR #922(docs-only)의 착지가 REUSED 없이
  종료 — 매 랜딩 키 전진의 실측 결과. 근거 보고서(§0-§5 전수 조사): B^{tree}는
  judgment BASE env의 유일한 소비가 verifierIdentity 조성이며, S 자체·S 도출 권위·
  decision-file 교차검증·probe 정체성은 전부 TESTED env(유지)로 흐른다.

### 2.2 신세대 (v4 — `axiom.judgment.cas.key.v4`)

- **wire 멤버 완전 제거**: `JudgmentClosure`는 고정 10멤버(9성분 — ①+②는 1멤버 — +
  narrowing-only `completenessKeys`·`schemaVersion`)만 운반한다. 트리 OID는 wire의
  어디에도 존재하지 않는다 — p2의 "타입이 계약"을 구현이 따른다. G12 회귀 핀이
  wire 키 집합 == 고정 멤버 집합(+스킴 구분자)을 단언한다.
- **판정 관련 소실 없음**: 검증자 실행 정체성은 ④ toolchainBundle + ⑧ compilerPins
  (§5(e)), 검증자 소스·정책·스펙·컴파일 입력은 ⑤ S(§4.1 배제표)가 계속 결속;
  recipe/pins는 이미 ⑦/⑧ 멤버로 결속. B^{tree}의 유일한 고유 기여(N 배제 오분류
  catch-all)는 등록된 잔여 위험(RR-1~4) + p4 fail-closed가 흡수한다 — v1.0.3 §4.1이
  이미 심판한 배분.
- **evidence 측 불변**: `AXIOM_EVIDENCE_CAS_BASE_TREE_OID` → `verifierIdentity` →
  EvidenceKey 결속은 그대로 유지. `evidence_cas.nim`·
  `tests/verification/test_evidence_cas_identity.nim` 무변경.
- **구세대 레코드 고아화(계약 §9)**: 스킴 문자열이 키 유도의 도메인 구분자이므로
  v3 레코드는 v4 키와 절대 충돌하지 않는다(재검증 불가·오염 불가 — 원장
  exactly-once 가드 그대로). 원장 `axiom/evidence-cas`의 v3 레코드는 불변 원장
  역사로 남는다.
- **첫 착지 1회 EXECUTED (예상 전이)**: v4 코드가 B에 포함된 첫 착지는 원장에 v4
  레코드가 없으므로 `no record for the current closure` → EXECUTED(원 실행)로
  1회 전진하고 v4 레코드를 mint한다. 이후 동일 클로저(docs-only) 랜딩은 REUSED로
  재개된다 — §5 5조건은 무변경이며, same-key reuse는 **byte-identical canonical
  projection**을 반환한다(J1, §2.5).
- **활성화 순간**: 본 PR의 merge_group 런은 B가 구세대 코드이므로 구세대 동작으로
  실행된다(정상 부트스트랩). v4 동작의 활성화는 본 랜딩 이후 최초의 B=v4 코드 착지
  (EXECUTED 1회) + 컨트롤러 재핀(§4.3 — 신세대 yml blob이 레인 런에 도달)이다.

### 2.3 회전 (핀 — derive_checker_closure 유도값, 추측 금지)

`bin/derive_checker_closure --ref HEAD` → 정확히 1멤버 변경, 멤버십 불변(876
엔트리). 핀 재앵커 후 `pin@H == derived(H)` 기계 검증: 멤버십 876==876, 라인 집합
완전 일치.

| 멤버 | 구핀 blob | 신핀 blob (유도값) |
|---|---|---|
| `src/verification/judgment_cas.nim` | `0c90e0a7a5823287e6486f90d7ec986b6c6615d4` | `81abcf7be57a130bb997ce864e08eb4c8ede2460` |

**핀 회전(A2 원자 쌍 — "두 값 외 변경 없음")**: `trustedAdmissionWorkflowSha` +
`productionExecutionPin` → 본 세대 admission-check.yml blob `09e8db1dea2851d936acb0d1581ae3cec06e8b7d`
(구핀 `ab4460fa36dd7a93756082d9dc0605d3822aefb3`). yml 변경 + TWS 값 변경 +
manifest 핀 변경이 하나의 그룹(커밋 2)으로 착지.

### 2.4 검증 상태 (기계 관측 — 착지 전)

| 검증 | 결과 |
|---|---|
| `make test-fast-one T=tests/unit/test_judgment_cas.nim` (G1–G14 전수) | **PASS — 203 assertions, 0 FAIL, 0 SKIP** (G12 p2 회귀 핀 포함 — closureWire 키 집합 == 고정 10멤버+스킴 구분자·no tree-OID-typed member; 스킴 상수 v4 단언; 2026-10-18 종료) |
| `bin/tcb_judgments selftest` | PASS — 12/12 (모든 판정의 FAIL 경로 생존) |
| J1 parity | PASS — **이형 프로세스 2회 독립 실행(run1 21:17Z·run3 21:44Z)의 flush 투영 cross-run byte-identical**: stored `a4db29d62489b5c4d16d536cf0519fb8ad9df83ad2f50988c3d215e64ba5d247` == readopted 동일; `bin/tcb_judgments --judgment parity` PASS exit 0; 음성 대조(verdict 변조 KERNEL_TIMEOUT) → **FAIL exit 2** — 판정기 생존 |
| J2 canonical-identity-set | PASS exit 0 (동일 파일 쌍) / 음성 대조(판정 변조) → FAIL exit 2 |
| J3 cache-manifest | PASS — `.github/actions/setup-axiom-toolchain/action.yml` (exit 0; nimcache·.axiom/cache coverage-gap은 report-only — 선대 기록과 동일) |
| `make check-workflow-shell-syntax` | PASS — 173 run 블록, failures=0 |
| `bin/ax` 컴파일 | PASS (수정 judgment_cas.nim 포함) |
| `pin@H == derived(H)` | PASS — 멤버십 876==876, 라인 집합 완전 일치(유출: `derive_checker_closure --ref origin/main` vs `--ref HEAD` diff = judgment_cas.nim blob 1멤버만) |
| `make push-admissibility` | (푸시 시 관측) |

### 2.5 J1 근거 (same-key reuse는 byte-identical canonical projection — §5 조건 무변경)

- 페이로드 순수성(구조적 보장, 무변경): G10(b) 동일 클로저 재flush → 바이트 동일 +
  G10(c) exactly-once 재-append → `alreadyPresent` no-op + G10(d) same-key/different-
  payload 거부 가드 생존.
- J1 기계 판정: 원장 저장 페이로드(stored) vs 재채택 페이로드(readopted) 바이트 대조
  `sha256` + `bin/tcb_judgments --judgment parity` — **이형 프로세스 2회 독립
  flush(run1·run3)의 투영이 cross-run byte-identical**(양측
  `a4db29d6…a5d247`) + parity PASS exit 0. 음성 대조(판정 변조) → parity FAIL
  (exit 2) — 판정기가 생존한다는 음성 대조 포함.
- 스킴 전환과 J1의 관계: v4는 클로저→키 유도만 바꾼다(투영 멤버 무이동 — 페이로드
  스키마 v2 유지). same-key(=v4 키) reuse의 바이트 동일성은 v3와 동일 보장이다 —
  조건 (a)-(e) 집합은 §5 그대로.

## 3. Tombstone

**"narrowing-only 멤버를 통한 랜딩당 키 전진"의 종료 선언(p2 순응 이행).** 구세대의
verifierIdentity 소비 블록(양 collector)·plan/attest BASE env 소비·워크플로 BASE
export 3행은 본 전환으로 끝난다. 이것은 **우회·면제·required-check 제거가 아니다**:
required check `admission-check`(ruleset)는 불변이며, 신세대는 p2의 키 비참여를
**구현 수준에서 강제**한다(강화 — wire 타입이 계약). 폐기되는 실행 경계는 없다 —
키 유도의 세대 교체만 기록된다. rollback: freeze 태그
`ci-freeze-judgment-key-v4-20261018`에서의 원자 revert(코드+yml+핀).

## 4. 측정

- 본 PR은 실행-축 전진(스킴 v4 + 코드 변경 → 키 전진 → EXECUTED)이므로 after 표본이
  아니다. after 표본: 본 세대 착지 + 컨트롤러 재핀 후 docs-only PR ≥2건의 MG 런 —
  첫 착지 EXECUTED(v4 mint) → 후속 착지 REUSED(`basis=REUSED`,
  `no record for the current closure` 부재) 관측이 §9 고아화의 생산 수용이다.
- MG wall 기대: REUSED 레인은 s1a 원 실행(~274s/런)을 건너뛴다 —
  `mg_reuse_cutover_e2e_2026-10-18.md`의 401–550s 회귀 기대치가 이번에야 실현된다.

## 5. Open items (§0.9)

1. **§4.3 org ruleset 재핀** — 컨트롤러(Archright/.github)가 본 세대 Axiom main SHA로
   재핀하는 PR + 양 ruleset PUT(freeze 2→0 → PUT → readback → unfreeze 2) — 본 랜딩
   후 별도 컷오버 단계.
2. **after 표본 관측** — 위 §4 절차.
3. **E2E addendum** — `mg_reuse_cutover_e2e_2026-10-18.md`에 #922 음성 관측 + 본 수정
   addendum(별도 docs-only PR로 착지).
