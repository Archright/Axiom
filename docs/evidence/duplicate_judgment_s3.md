# Duplicate Judgment (S3) — CI-pareto P3 중복 판정

> P3/S3 판정 산출물. Census `docs/evidence/canonical_run_graph.md` §C D1–D9 후보를
> **4-property 검사**(동일 계산 → 동일 증거 → 동일 권위 소비자 → 제거 시 trust 보존)로 판정.
> file:line은 2026-09-25 working tree 기준. 판정 규칙: **REMOVABLE / KEEP / NEEDS-PROOF**.

## 판정 요약

| # | 판정 | 1줄 사유 |
|---|---|---|
| D1 | **NEEDS-PROOF** | mint B-빌드는 의도된 권위 재유도(privileged tier) — 제거는 빌드 결정론+증거 등가 실험 선행 필수 (DANGER) |
| D2 | **KEEP** | 권위 레이어 격리의 핵심 — mint는 생산자 자가 보고를 신뢰하지 않음 (certificate-mint.yml:43-51, :394-403) |
| D3 | **KEEP** | 동일 쿼리·**반대 판정 의미론**(idempotent vs 발행 차단) — 각자 고유 의무, 어느 쪽도 제거 불가 |
| D4 | **KEEP** | dry-run = 관측 기록(상태 전이 없음) vs apply/landing = 액추에이터 — 계산·증거·소비자 모두 다름 |
| D5 | **KEEP** | 동일 스크립트 ≠ 동일 검증 대상 — 권위 경로 vs 착지 후 관측, 소비자·환경 상이 (동일 코드+독립 신뢰 경계) |
| D6 | **KEEP** | admission은 데이터 단계만 inline(setup-hooks **제외**) — 같은 target이 아님, 소비자·의무 상이 |
| D7 | **KEEP** | 로컬 = 유일 기계 강제 경계, 원격 = 관측 — 소비자 상이, 로컬 제거 시 ratchet 강제 소멸 |
| D8 | **KEEP** | 86집합은 **커밋별 독립 감사 대상** — 시간적 반복 ≠ 계산 중복; select가 무Δ 실행을 이미 제거 |
| D9 | **KEEP** | witness(무서명) vs certificate(서명) — 산출물·소비자 상이, 제거 = TrustedWriterSet 의미 붕괴 |

결과: **REMOVABLE 0 / KEEP 8 / NEEDS-PROOF 1**. "중복 0건"은 목표가 아니며(계획 키 룰)
실측상 전 항목이 의도된 레이어 설계 또는 서로 다른 신뢰 경계다.

## D별 4-property 검사

### D1 — admission `make ci-bootstrap` (admission-check.yml:136-151, make :139) vs mint (certificate-mint.yml:227-231, make :230)
- Q1 **O** 동일 B·동일 레시피. 단 admission은 +`lake build ircheck`(:144)+manifest(:153-166), mint는 ci-bootstrap만
- Q2 **O** 모두 B-built bin/ax. 단 **별개 인스턴스**: admission 산출물 `admission-check-base-artifacts`(:168-177)를 mint는 소비 안 함
- Q3 **△** 둘 다 Gate A의 bin/ax지만 **신뢰 계층 다름**: admission ax = 무서명 witness 생산(비권위), mint ax = 서명·원장 기록(권위, TWS 단일 라이터 — config/trusted_writer_set.json; certificate-mint.yml:35-38). mint 헤더 "privileged tier performs ZERO untrusted computation"(:43-51)이 **재유도를 계약**으로 고정
- Q4 **X (미입증)** mint가 admission 아티팩트 사용 = 권위 계층이 생산자 산출물 실행 → 재유도 체인 붕괴. 단 프로비넌스 도구(manifest build_sha==B + sha256, admission-check.yml:153-166, :229-248)와 TWS 핀(:290-300)은 **이미 존재** — 등가 입증 시 제거 가능한 구조
- **판정: NEEDS-PROOF** (계획 DANGER 플래그와 일치)

**필요 실험 (J1/J2, docs/spec/ci_optimization_tcb_judgments.md):** ① J1 Semantic Parity(§1)+N≥5(§4.2): 동일 B에서 `make ci-bootstrap` 반복 → bin/ax byte-결정론(`tcb_judgments.nim --judgment parity`; 제외 = telemetry §1.1). ② J2 Evidence Equivalence(§2): 동일 witness에 (a) mint 자체 빌드 ax vs (b) admission artifact(manifest 검증: build_sha==B, recipe_id, sha256 핀) 사용 ax — `cert attest --sign` 산출 certificate **13-field canonical identity**(ci_optimization_tcb_judgments.md:117; certificate_identity.nim:32-36) + ledger subjectId(§2.4) 동일성. ③ 부수: mint (3)의 run-scoped+이름+sha 핀 패턴(:341-392)이 bin/ax 전송에도 적용 가능 확인. — PASS 시 최소 제거안: mint :227-231 → `download-artifact admission-check-base-artifacts`+manifest 검증(admission-check.yml:229-248 패턴). **구현은 본 작업 범위 아님**

### D2 — mint witness 재검증 + `attest --sign` (certificate-mint.yml:404-429; :416-417)
- Q1 **O**(커널 체인 a-f 재실행) 그러나 연산은 `--witness-only`(생산) vs `--sign`(검증+정규화+서명)으로 **다름** — mint "re-derives every digest itself… never signed as-is"(:397-400)
- Q2 **X** witness.json(무서명) vs certificate.json(Ed25519 서명, (B,H) 바인딩)
- Q3 **X** witness = mint 입력(:380-392), certificate = Landing CAS 소비(landing_cli.nim:19-21, :26-32)
- Q4 **X** 제거 시 권위 계층이 생산자 자가 보고를 서명 → TWS 의미 붕괴
- **판정: KEEP** — 의도된 2-계층 재검증(privileged tier must not trust producer's self-report)

### D3 — `cert ledger-list` 2회 (admission-check.yml:449-461 vs certificate-mint.yml:436-451)
- Q1 **O** 동일 명령(`ledger-list | grep -qx $subjectId`)·동일 B-built ax·동일 원장. 단 **판정 분기 반대**: admission = 존재 시 **OK**(idempotent, :458) / mint = 존재 시 **FAIL**(이중 발행 차단, :449)
- Q2 **X** 산출물 없음(읽기 전용) — 문맥별 게이트 의미 상이
- Q3 **X** admission: 자기 재실행 안전(무권위, mint 발행 후 red-block 관측 역사 :441-448) / mint: 원장 단일 발행 권위
- Q4 **X** 어느 쪽 제거 시 idempotency 또는 이중 발행 차단 중 하나 소멸
- **판정: KEEP** — 동일 쿼리가 **반대 의미론**. Census Q1=X는 명령 수준 동일성을 인정하되 의미론 차이로 본 것 — 결론 동일

### D4 — `ax merge --dry-run` (admission-check.yml:489-506, :495) vs `--apply`/`ax landing`
(merge_cli.nim:1263, :1312, :1416, :1362-1373; landing_cli.nim:15-35)
- Q1 **X** dry-run = MergeAdmissible 평가만·verdict를 gate_history.jsonl 기록·exit 0 무관(:479-488) vs apply/landing = stale-eval guard(merge_cli.nim:1437-1443) 후 **상태 전이**(updateRefs, landing_cli.nim:31)
- Q2 **X** 관측 로그(OBSERVATION) vs 실제 main 상태 전이(certificate 기반 CAS)
- Q3 **X** 관측 기록은 권위 없음(:486-487 "NOT a claim"); apply 경로 소비자 = Landing CAS
- Q4 **O** dry-run 제거는 권위에 무영향(결코 admit 안 함). 그러나 B-built ax 평가의 fail-closed 스모크 역할(:494-500)
- **판정: KEEP** — 계산·증거·소비자 전부 상이. "= 중복" 성립 안 함

### D5 — Lake build smoke (admission-check.yml:114-131 vs runner-pool-acceptance.yml:220-238)
- 실측: 스크립트 **byte-동일**(diff 확인 — 차이는 step 이름·`timeout-minutes: 5`뿐)
- Q1 **O** 동일 스크립트·동일 toolchain 핀(leanprover/lean4:v4.33.0) / Q2 **O** 둘 다 fail-closed 스모크(산출물 없음)
- Q3 **X** admission = **권위 경로**(Gate A artifact 방송 전 검증, :111-113) / runner-pool = 착지 후 관측(자체 호스팅 러너 툴체인 — Lake.olean 사고 run 35678120915 근거, :213-219). **검증 대상(러너 플릿 툴체인)도 다름**
- Q4 **X** admission 쪽 제거 시 권위 경로 조기 fail-closed 소멸; runner-pool 쪽 제거 시 8개 레그 툴체인 사고 조기 탐지 소멸
- **판정: KEEP** — "동일 코드 + 독립 신뢰 경계 = 중복 아님"(계획 키 룰). 통합 불가(별개 런·환경)

### D6 — `make ci-bootstrap-cheap` (admission-check.yml:468-477 vs runner-pool-acceptance.yml:416-422)
- 실측: admission은 **target 호출이 아닌 3단계 inline** — install_ax_cas(:471)+`ax scope hash`(:473)+`ax baseline check`(:475). `make ci-bootstrap-cheap`(Makefile:849-853)의 `setup-hooks`(:851)는 **의도적으로 제외**(admission 주석 :463-467 "data-relevant steps")
- Q1 **△** 데이터 단계만 겹침(3/4); runner-pool은 target 전체 실행(:421) / Q2 **O** scope hash/baseline 통과 신호
- Q3 **X** admission = 권위 경로 환경 무결성(envDigest/scopeDigest가 certificate 입력 경로, :342-348) / runner-pool = 착지 후 레그 프로비저닝
- Q4 **X** admission 제거 시 권위 경로의 scope/baseline 증거 의무 소멸
- **판정: KEEP** — Census "동일 시퀀스" 주장은 **부분 부정확**(setup-hooks 제외 → 동일 target 아님); 판정은 동일

### D7 — repository-surface ratchet 원격 (repository_surface.yml:55-73) vs 로컬 (Makefile:356, :367-373)
- Q1 **O** 동일 base-policy binding(merge-base origin/main HEAD) × 동일 diff 판정(`surface_guard --policy base --diff`, repository_surface.yml:49-56, :70-73 vs Makefile:368-373)
- Q2 **O** 동일 ratchet 판정 결과
- Q3 **X** 원격 = PR 관측 체크(required 아님, merge authority 무변 — repository_surface.yml:1-8) / 로컬 = **유일한 기계 강제 경계**(pre-push; Makefile:357-359)
- Q4 **X** 로컬 제거 시 강제 소멸(관측만 남음 → ratchet 무의미); 원격 제거 시 PR 가시성 소멸(강제 유지). 어느 쪽도 대체 불가
- **판정: KEEP** — 동일 계산이 **강제 vs 관측** 경계에 의도적으로 배치됨

### D8 — gateway 86-test suite full vs selected, 인접 커밋 연속 full
- 실측: push@main → select가 provenRequired(Δ) 판정(runner-pool-acceptance.yml:72-158); tag push → full 고정(:25-27, :39). W8(gateway) 영향 = src/ 변경 시(tools/ci/impact_closure_selector.nim:452-457) → full/gatewayTestScope ALL(selector :810-822). "인접 커밋 연속 full" = 두 커밋 모두 src/를 건드릴 때 발생
- Q1 **X** 86개 집합은 같으나 **검증 대상 트리가 다름**(커밋 N vs N+1) — 입력 상이 → 동일 계산 아님
- Q2 **X** executed record가 decisionHash+shard로 **커밋별 바인딩**(runner-pool-acceptance.yml:435-444, :310-319) — 증거는 자기 커밋 전용
- Q3 **X** 각각 독립 계약: tag=full(A1.3 고정), push@main=select 판정 + A3 proof-reconcile(:521-566)
- Q4 **X** N+1 커밋 실행 제거 시 해당 커밋의 게이트웨이 감사 공백(per-commit 감사 의무). 무Δ 커밋은 select가 이미 mode=none으로 제거
- **판정: KEEP** — 시간적 반복은 커밋별 감사 계약이지 계산 중복 아님

### D9 — `attest --witness-only` (admission-check.yml:418-439, 호출 :429-437) vs `attest --sign` (certificate-mint.yml:404-429)
- Q1 **O** 동일 B-built 커널 체인·동일 evidence 입력
- Q2 **X** **무서명 witness**(admission) vs **서명 certificate**(mint) — 산출물 유형이 다름(서명 여부가 전부)
- Q3 **X** witness = mint 입력(:380-392), certificate = Landing CAS 소비(landing_cli.nim:19-21)
- Q4 **X** mint 재유도 제거 = 생산자 자가 보고 직접 서명 → TWS 단일 라이터 의미 붕괴(certificate-mint.yml:43-51)
- **판정: KEEP** — D2와 동일한 의도된 2-계층 재검증의 다른 얼굴

## 실측 정정 (Census 주장 중 실제와 다른 점)

| # | Census 주장 | 실측 |
|---|---|---|
| D4 | "admission vs later `ax merge --apply`/`ax landing`" | 정확 — `--apply`는 merge_cli.nim:1263/:1416 usage에 존재, 실제 적용 경로는 `ax landing` 서브프로세스(merge_cli.nim:1362-1373) |
| D6 | "`make ci-bootstrap-cheap` duplicated" | **부분 부정확** — admission은 target 호출이 아닌 3단계 inline(setup-hooks 제외, :463-467). 동일 target 중복이 아님 |
| D2/D9 | attest 라인 :413-439 | 실제 스텝 :418-439(주석 :412-417) — 5행 drift, 판정 무영향 |
| D8 | "인접 커밋 연속 full = 같은 집합 재계산" | 사실이나 입력 트리가 상이(커밋별) — 계산 중복 아님. 무Δ는 select가 이미 제거(selector :810-836) |
| D5 | "동일 코드 복붙" | 확인됨(byte-동일, 이름·timeout 차이만) — 단 검증 대상 환경이 상이 |

## 결론

9건 전부 KEEP 또는 NEEDS-PROOF. 제거 가능한 중복 **0건** — 모든 후보가 의도된 2-계층
재검증 / 서로 다른 신뢰 경계 / 커밋별 독립 감사 계약 위에 있다. D1만이 유일한 잠재
최적화 지점이며, J1(빌드 결정론) + J2(증명서 identity 등가) 실험 통과 전에는 접근 금지.