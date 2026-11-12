# ADR-0026: 산출물별 실행 authority 단일화 — 권위 행위 봉인 (certificate·발행·판정 권위 경계 확정)

## Status

**PROPOSED (2026-09-27)** — 계획서 실행 authority 단일화(black-hawk-carnage-rogue,
rev.7)의 Phase 0 ADR 기록이다. 본 ADR은 **산출물별 생성 authority를 정확히 1개로
단일화**하고(유일 예외: mint prepare 자체 빌드 = 계약 C1 — §1·§3), **권위
행위(발행·랜딩)를 단일 writer/단일 MERGE authority로 봉인**한다. 동시 착지 문서:
ADR-0025 Amendment A1(2026-09-27) · `certification_continuity_contract.md` §5
INV-13 D6 해석 개정(2026-09-27) · ADR-0023 A1.8(e)(f). 구현(Phase 1~4) 실증
(Completion Evidence [W][B1][X][B2][F]) 완료 전 "단일화·봉인 확정" 선언 금지.

## Context

- **벽시계 실측(계획서 "배경")**: full-mode PR 게이트 런 29.2분 중 검증 4.3분 /
  중복 B-빌드 8.2m / 도구체인 6.7m / arm-shard 6.6m. 재팽창 원인 =
  `93c758c2d` + `7606e0580` + 직렬 DAG.
- **반박 판정(C1~C6·cert authority·Claim-4/5/7)**: cert = bounded 증거(≠ landable) ·
  착지 authority = native MERGE 단일 · verdict append 폐기 · mint 자체 빌드 = 계약(C1).
- **실측 앵커 (bounded historical record)**: side-ref 원장(2026-09-27 측정 —
  ledger tip `7b2cd8363`, 기준 origin/main `8e027c065`) **104건 중 12건 미착지
  subject cert** — cert 발행(104건)이 착지(92건)를 보장하지 않음의 실측.

## Decision

**Ultimate Purpose** (계획서 rev.7 원문):

> 랜딩 후보의 요구 검증이 결정론적 증거로 완결되기까지의 벽시계를 최소화한다 —
> 증거 강도(MUST 16)는 불변으로 유지하고, 산출물별 실행 authority를 단일화하며,
> 권위 행위(발행·랜딩)는 단일 writer/단일 MERGE authority로 봉인한 채 중복 계산과
> 불필요한 직렬화만 제거한다.

**용어 정정 — authority 6종 분리 유지 (수렴이 아님):**

> authority는 **execution / certificate / publication / freshness / derivation /
> MERGE** 6종으로 분리 유지한다. 본 작업은 "수렴"이 아니라 **산출물별 생성자
> 단일화 + 권위 행위 봉인**이다.

| authority | 소유 | 근거 |
|---|---|---|
| execution | org required workflow @SHA(플랫폼 고정) | ADR-0025 §2·§5 |
| certificate | mint prepare(write-tier 자체 빌드, 계약 C1) | ADR-0022 · `canonical_run_graph.md:106` |
| publication | publish 단독(ledger append, exactly-once) | ADR-0025 §14·Amendment A1 |
| freshness | GitHub ruleset strict | ADR-0025 §2 |
| derivation | trust-tier 재유도 코드(ROTATION 대상) | ADR-0025 §6 |
| MERGE | GitHub native MERGE 단일 | AGENTS.md §2 · ADR-0025 §1 |

**증거 4분리 (시간 / 구조(권위) / 인과 / 실패경로):**

- **[W] 시간**: warm ≤15m 1회 ∧ cold ≤15m 1회 + 각 probe의 per-job 캐시 상태 실측 기록.
- **[B1] 구조(권위 정규성)** · **[X] 결속(최소 핵심)** · **[B2] 인과(데이터 결속 포함)** ·
  **[F] 실패경로**: 하나라도 미달 = 미완료. 시간 미달은 [W]로 분리해 Phase 3 잔여
  재설계(구조 성립 시)로 처리한다.

### §1 설계 원칙 (계획서 규칙 1–10)

1. **산출물별 생성 authority 정확히 1개** (예외: mint prepare 자체 빌드 = 계약 —
   `canonical_run_graph.md:106`, ADR-0022) / 소비자 재생성 금지
2. **authority 산출물 = immutable artifact + digest 기록 + 필드 결속 + 서명**
   (전송 무결성·불변성 = 플랫폼 TCB — 중복 구현 금지)
3. **독립 검증 병렬**
4. **join = 실제 의존 지점만** (prepare←admission, publish←gateway+prepare)
5. **cache miss = 성능(J3)**
6. **cache key = artifact identity** (교차 PR 기대 금지)
7. **K=8 등 = MUST 아님** (ADR-0023 구속 — 값 변경은 별도 개정; ADR-0023 A1.8(f)
   "POLICY 다이얼 금지" 의미 확정)
8. **GitHub orchestration 재구현 금지**
9. **최종 verdict만 merge 허용 판단**
10. **권위 행위 = 시간 인과 + 데이터 인과(동일 canonical identity 검증 포함)
    이중 결속**

> **해석 기록 (2026-09-29, 규칙 6 "cache key = artifact identity")**: tree-OID 기반 B-cache 키는 규칙 6의 강화다 — 키가 빌드의 실질 입력(트리 내용)을 식별하며, cross-PR 키 공유는 기존 commit-SHA 키도 이미 허용한 속성(동일 base 트리 = 동일 키)이다. 본 기록은 규칙 개정이 아니라 해석이며, 실제 결정은 ADR-0025 Amendment B에 있다.

### §2 신규 job 6문항 (Phase 2 2-stage mint 신규 job 심사)

신규 job 도입은 6문항 전부를 통과해야 한다(계획서 원문):

1. **왜** — 어떤 산출물/판정을 위해 필요한가
2. **유일 증거** — 그 job만이 생산 가능한 증거인가
3. **재생성 아닌가** — 기존 authority 산출물의 소비자 재생성인가(금지)
4. **병렬인가** — 독립 의존성을 갖고 기존 job과 병렬 가능한가
5. **artifact 불가인가** — job 없이 artifact로 대체 불가능한가
6. **권위 행위의 시간·데이터 선행 조건이 모두 모인 뒤인가** — 발행·판정 job인 경우
   §1-10 이중 결속의 선행 조건이 전부 충족된 뒤에만 배치되는가

### §3 cert authority 판정 — certificate = bounded 증거 · subject-certification authority (≠ landable)

- certificate는 (B, H, evidence)에 대한 서명된 **bounded 증거**이자
  **subject-certification authority**(그 subject의 인증 권위)일 뿐이다 —
  착지 가능 객체(landable)가 **아니다**.
- **착지 authority = native MERGE 단일**(AGENTS.md §2, ADR-0025 §1 M-B) — cert
  발행 여부는 착지 여부를 결정하지 않는다(실측 앵커: 104건 중 12건 미착지).
- **verdict·post-verdict의 ledger append는 폐기** — 발행(publish) 단일 writer
  위반(ADR-0025 Amendment A1 · 계획서 [B1]).
- **mint prepare 자체 빌드 = 계약 예외(C1)** — write-tier의 신뢰 re-verification
  체인 유지를 위한 정당한 산출물이다. 같은 바이트 2회 자체는 버그가 아니며,
  **버그 = 산출물별 authority 2개 또는 소비자 재생성**이다.
- **C1 개정문 (epoch N+5, 2026-09-29 — C5/C1 계약 개정, SL-04 승격 동반)** —
  mint prepare의 자체 빌드(계약 예외 C1)를 **폐기**하고, admission lane이
  `build-base-artifacts`로 발행한 **B-결속 바이트**(manifest `build_sha == B` +
  per-file sha256, SL-08 — admission-check.yml build-base-artifacts job)를
  prepare가 소비한다(run-scoped API + trusted-name + build_sha==B + sha256 pin
  전량 fail-closed 검증 — certificate-mint.yml `[mint] Consume admission
  B-built bin/ax` 스텝). 효과:
  - **authority 정규성 [B1]**: single build site = admission lane 1개 — D1
    (중복 빌드) 해소, 소비자 재생성 0 전체 성립 (prepare·publish·gateway 소비).
  - **검증 경로 불변**: publish [X]1~5 결속(P1/P2/P3/P4) 및 prepare (4)
    verify / (5) sign 경로의 코드·판정은 그대로 — 소비 source만 변경.
  - **신뢰 논거**: 자체 빌드가 "B 소스에서 재생성"을 보장하던 바이트 신뢰를,
    B-결속 manifest(플랫폼 artifact 다이제스트 하의 불변 바이트 + build_sha==B)
    검증이 대체한다. prepare의 서명·검증 권한과 [X] 결속 체인은 무변경.
  - **잔여(문서화된 수용)**: prepare는 더 이상 스스로 빌드하지 않으므로
    "privileged tier 독립 재빌드"라는 기존 체인은 제거된다 — 대신 단일 빌드
    authority + 바이트 pin으로 대체되며, 이는 본 개정의 의도된 범위다.

### §4 two-product 정의 — read-tier B-verifier vs candidate-runner

계획서 [B1]의 산출물별 authority 4행:

```
read-tier B-산출물       → authority = admission 단독 · 소비자 재생성 0
candidate-산출물/arch    → authority = candidate-build 1개/arch · shard 재생성 0 (compile=0)
mint prepare cert        → authority = single build site(admission lane build-base-artifacts) 1개
                          · 소비 (C1 개정 2026-09-29 — §3 개정문)
ledger record            → authority = publish 단독 · append exactly-once(첫1/재실행0)
```

- **two-product**: read-tier(B-verifier — gateway 검증 경로가 소비하는 산출물)와
  candidate-runner(후보 빌드·arch 단위 실행 산출물) 두 부류를 분리 유지한다 —
  read-tier authority = admission 단독, candidate authority = candidate-build
  1개/arch(arm = 동일-아키 1회 → shard가 download-artifact로 소비, x64 재사용 금지
  불변; 계획서 Phase 2-9).
- read-tier와 prepare는 **같은 trust boundary로 통합된 정당한 산출물** (C1
  개정 2026-09-29 — prepare가 admission lane B-결속 바이트를 소비) — 관측
  프록시: read-tier=1, candidate=1/arch, shard compile=0, prepare 소비=1
  (자체빌드 0), append exactly-once. 버그 = 산출물별 authority 2개 또는
  소비자 재생성.

### §5 [W] 시간 증거 — cold-path 필수 (rev.7 상향 근거 원문)

계획서 rev.7 주석 원문:

> (rev.7 — [W] 상향 근거: warm×2 통과는 "최선의 환경" 통과일 뿐. 실측 cold 16–20m가
> fresh runner에서의 실제 상한이라면 ADR-0023 15분은 cold-path에서 못 지킨 계획이
> 된다. cold-path = 직렬 job 중 B-miss(캐시 복원 실패)가 실측된 런. 2-stage 설계
> 기대치: cold ≈14.5m / warm ≈12–13m — 목표 달성 가능하나 임계 근접, 미달 시
> Phase 3 잔여 재설계.)

- [W] = warm ≤15m 1회 ∧ **cold ≤15m 1회** + 각 probe의 per-job 캐시 상태 실측 기록.
- **warm×2로는 부족** — warm 통과는 최선 환경 통과일 뿐이며, cold-path(캐시 복원
  실패가 실측된 런)에서의 상한이 지연 예산(ADR-0023 A1.8 — CI wall-clock ≤15분)과의
  실제 정합이다.
- cold-path 판정 = 직렬 job 로그에 B-miss("Cache not found"/미복원) 실측. [W] cold
  1회 부재 또는 1건이라도 >15분 = 미완료(Phase 3 잔여 재설계 후 재측정).

### §6 [B1] 생성 authority 정규성 — 해석문

- 본질: **각 필수 산출물마다 정당한 생성 authority가 정확히 하나, 소비자 재생성 0**.
- 관측 프록시(잡/스텝): read-tier=1, candidate=1/arch, shard compile=0, prepare
  소비=1(자체빌드 0 — C1 개정 2026-09-29), append exactly-once.
- **판정 원칙**: read-tier와 prepare는 같은 trust boundary(admission lane 빌드
  authority)의 산출물 — 소비자 재생성 0. **버그 = 산출물별 authority 2개 또는
  소비자 재생성**.

### §7 [X] artifact-evidence 결속 계약 (최소 핵심 5종)

1. **artifact identity**: run-scoped API + trusted-name(정확히 1개) + artifact-ids
   다운로드(TOCTOU 회피)
2. **file digest**: prepare 산출 직후 cert_sha256 계산 → provenance 기록(전송
   무결성은 플랫폼 다이제스트 검증이 담당)
3. **field binding**: subjectId/baseSha/headSha/certTree/evidenceDigest == 재유도·prepare
   산출값
4. **signature/closure**: Ed25519 + 구조 closure(canonical 바이트 커버)
5. **CAS 원자성**: 3분기 reconciliation(exactly-once)

- sidecar `cert.sha256` 비교 메커니즘 **폐기**(서명+전송 다이제스트와 중복 — sha256은
  provenance 기록용) · 결정적 파일명 = 운영 수단(trust 주장 제외).
- tamper 6종: (1)trusted-name 위반 artifact (2)교체된 cert (3)필드 변조 (4)타 런
  artifact (5)타 head stale (6)CAS 경합·double-append race — 전부 fail-closed.

### §8 [B2] 시간 인과 + 데이터 인과

- **시간 인과(필요)**: `needs: [prepare, gateway]` + append 타임스탬프 ≥
  max(gateway, prepare).completed(보조).
- **데이터 인과(핵심 — 같은 후보의 성공임 증명)**:
  (a) gateway run.headSha == cert.headSha ∧ (b) gateway canonical tree identity ==
  re-derived cert.certTree ∧ (c) gateway conclusion == success.
  append record provenance = {cert_sha256, gateway run_id, gateway headSha, gateway
  tree identity, conclusion=success, field-binding 통과}.
- **(b) 정정 (rev.7)** — "digest가 같다"가 아니라 **동일 canonical identity 검증**:
  전제 확정이 구현 선행 조건(semantic domain — 기본 해 = tree-identity 라인의
  canonical tree SHA(`testedTreeDigest` — `IDENTITY: OK … tested tree == merge
  candidate tree` 실측 계열)); gateway 산출이 다결과 manifest digest라면 단순
  equality 금지 → publish가 gateway 결과에서 canonical tree identity 필드를
  추출/재유도해 비교한다. **semantic domain 확정 전 (b) 구현 금지**(계획서 위험 ⑤).

### §9 [F] failure-path 관측

gateway 실패 → publish skipped → verdict FAILURE(NO-GO) → 병합 차단 실측
(fault-injection draft PR, 관측 후 즉시 닫기). skipped publish의 success/부재 오해
경로 0의 기계 판정.

### §10 D6 원자성 규칙 (3분기 reconciliation) — INV-13 D6 연동

**A. 멱등**: ledger record로부터 subjectId 재계산 == 키 ∧ record certTree ==
re-derived tree(mergeSha) — record 정당성 확인(손상 = fail-closed). **witness
digest는 run-scoped — 교차 런 정체성 금지**. 사슬: 같은 논리적 증거 → 같은
evidenceDigest → 같은 wire → 같은 subjectId → append exactly-once.
(문서화: `certification_continuity_contract.md` §5 INV-13 D6 해석 개정 2026-09-27.)
**B. CAS 정상 경로**: `성공 → 1 / 실패→재조회→(A)성립 → PASS(0) / 불성립 →
FAIL-CLOSED` — 재시도 루프 내부 reconciliation.
**C. createdAt 회전**: 방어 = B의 hard reconciliation + exactly-once assertion.

## Consequences

**긍정:** 산출물별 생성 authority가 단일화되어 권위 산출물의 감사가 결정적이 된다.
발행(publish 단일 writer)·판정(verdict 단일)·착지(native MERGE 단일)가 봉인되어
권위 행위의 중복 경로가 구조적으로 제거된다. D6 멱등 해석(record 재계산 정당성 +
CAS 3분기)으로 재실행 안전성이 멱등 판정 자체에 포함된다.

**부정(residual):** [B2](b)의 semantic domain 확정 전까지 데이터 인과는 준비 계약이며
구현(Phase 2)을 선행할 수 없다. cold ≤15m은 실측 전까지 예정 계약(임계 근접 —
Phase 3 잔여 재설계 가능). mint 자체 빌드(C1)는 epoch N+5 계약 개정(§3 개정문,
2026-09-29)으로 **해소**되었다 — prepare는 admission lane B-결속 바이트를 소비한다
(의도된 수용: privileged 독립 재빌드 체인 → 단일 빌드 authority + 바이트 pin).

## 잔여 한계 (Residual Limits)

- **실증 의존**: [W](cold 포함) · [B1] · [X](tamper 6종) · [B2](canonical identity
  확정) · [F] · [D](D6 사슬 + exactly-once) · [E](MUST 재판정)는 Phase 1~4 실증
  전까지 주장이 아닌 예정 계약이다. 본 ADR의 green = 문서 착지이며 완료 증거가
  아니다(계획서 "PR CI 성공만으로 완료 주장 금지").
- **범위 밖 (계획서 Out of Scope)**: MUST 16 의미 변경 · mint 자체 빌드 제거(C1) —
  epoch N+5 계약 개정(§3)으로 범위 안 전환 완료 (2026-09-29) · verdict append(폐기) ·
  sidecar cert.sha256 비교 · J3 cache-manifest(S5) · K=8 변경
  (별도 개정) · 새 trust authority · self-hosted·러너 인프라 · merge queue ·
  DEBT#462·Landing App · required workflow·status 체계 · 툴체인·cert 스키마 변경.

## References

- 프로젝트 계획서: 실행 authority 단일화(black-hawk-carnage-rogue, **rev.7** —
  Ultimate Purpose · 용어 · 증거 구조([W][B1][X][B2][F]) · D6 · 배경(실측+반박
  판정) · 설계 원칙(규칙 1–10 + 6문항) · In Scope Phase 0-4 · Completion Evidence ·
  위험 ①~⑥) — 본 ADR의 결정 출처(승인된 계획).
- ADR-0025 — §1 M-B(착지 = native MERGE) · §2(2권위) · §5(SHA pin) · §8(a)(verdict
  fail-closed + U1) · §14(ledger 동시성) · Amendment A1(2026-09-27)
- `docs/spec/certification_continuity_contract.md` — §5 INV-13(1 cert per subjectId)
  + D6 해석 개정(2026-09-27)
- `docs/evidence/canonical_run_graph.md:106`(D1 — mint 자체 빌드) · :109(D4 — dry-run
  관측 기록)
- ADR-0022(C1 — mint 자체 빌드 계약 예외) · ADR-0023 A1.8(b)(K 다이얼) ·
  A1.8(f)(POLICY 다이얼 의미 확정) · ADR-0009(decision-binding framework)
- 실측 — side-ref 원장 tip `7b2cd8363`(2026-09-27, 기준 origin/main `8e027c065`):
  104건 중 12건 미착지 subject cert

---

*작성일: 2026-09-27. PROPOSED — 계획서 Phase 0 ADR 기록. Phase 1~4 실증([W]
cold-path 포함 · [B1] · [X] · [B2] · [F]) 완료 전 "단일화·봉인 확정" 선언 금지.*