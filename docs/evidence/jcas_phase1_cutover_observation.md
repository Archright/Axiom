# Judgment CAS Phase 1 — 세대 컷오버 + 첫 라이브 4조합 관측 (관측 프로토콜)

> Slice: "Judgment CAS Operational Closure" — Phase 1.
> 계약: `docs/spec/test_judgment_cas_contract.md` · 주제 정의 SSOT:
> `src/verification/judgment_cas.nim` (`JudgmentSubject` enum — s1a,
> proof_integrity, d2_golden, d2_persist).

## 1. 세대 상태 (컷오버 사실)

- Axiom main: `cbb8c0db6b391b5dd7c0db32f157da8187b727ab`
  (PR #630 merge — d2_golden Stage-4 체인 커널 실행을 카운티드 싱크
  `jCanonical()`로 배선 수정. #622의 잠복 결함이 `6767884e7` armed
  세대에서 13/14 fail-closed로 발화해 전 PR을 차단했고, Gate A
  부트스트랩 교착 하에서 SL-15 절차로 착지 — PR #630 본문·코멘트의
  로컬 armed-flush 14/14 실증 포함).
- org `.github` `admission-gate.yml` callee 핀 5 use-site:
  - 1차 회전 `347c1fc0d` → `6767884e7` (2026-10-09 02:03:50–02:04:04Z,
    PR #78/#79/#80, 컷오버 커밋 org main `94d65770`)
  - 재회전 `6767884e7` → `cbb8c0db` (2026-10-09 03:08–03:09Z,
    Dependabot PR #85/#86/#87 — #630 수정 tip 소비. 회전 가속:
    dependabot schedule 명시화 PR #84)
- 세대 정의: 컴포넌트 ⑤ TESTED tree OID = B(베이스) 체크아웃 tree
  (`admission-check.yml` `[check] Judgment CAS plan` 스텝 —
  `git rev-parse HEAD^{tree}`). PR/MG가 같은 base tree를 공유하면 같은
  세대, main이 전진하면 새 세대. PR 이벤트의 base.sha는 PR 분기 시점에
  동결된다(03:14Z 런 실측: reopen 재기동만으로 base 미갱신, 체크아웃
  ref 6767884e7 유지) — 세대 관측 차량 PR은 synchronize로 base를
  전진시켜야 한다.

## 2. 관측 대상 4조합 (live admission-gate 런)

| 조합 | 런 | 기대 basis | 의미 |
|---|---|---|---|
| (a) | PR 런 (새 세대) | 4종 전부 EXECUTED + ledger append | 첫 계측 — 기록 발행 |
| (b) | MG 런 (동일 세대) | 4종 REUSED, 커널 0회 | 동일 세대 재검증 절감 |
| (c) | MG 런 (세대 전진 후) | 4종 EXECUTED | 정당 무효화 (fail-safe 재실행) |
| (d) | PR 런 (후행 사이클, 동일 세대) | 4종 REUSED | 교차 사이클 재사용 |

로그 시그니처:

- 계획: `[check] judgment plan[<subject>] decision staged`
- 재사용: `[admission-tests] SKIP — <test> (AXIOM_JUDGMENT_CAS basis=REUSED …)`
- 신규 계측: `[admission-tests] PASS — <test> (basis=EXECUTED …)`
- 발행: certificate-mint `(P7c)` `ax evidence ledger-append` (exactly-once)

## 3. 계측 방법

- 로그는 jobs API raw 로그(라인 타임스탬프 포함)로 추출 —
  `gh api .../jobs/<id>/logs` (zip 리다이렉트 방식; `gh run view --log`는
  빈 결과를 낼 수 있음).
- 4종 스텝은 단일 step
  `[check] GO-critical admission tests (DEBT#432 …)` 안에서 구동되므로
  종목별 시간은 `RUN`/`PASS`/`SKIP` 라인 타임스탬프 차로 산출한다.
- 절감 기준(사전 실측): 4종 스텝 합 513s (37 + 143 + 23 + 310).
  본 슬라이스 신규 절감 = 3종 (proof_integrity + d2_golden + d2_persist)
  ≈ 203s (~210s) — s1a 재사용은 선행 슬라이스에서 이미 실현.

## 4. 실측 결과

실측 값은 후속 PR(본 문서 계열)에 기록한다. 계측 전 이 섹션은 비워
둔다 — 추정치로 채우는 것은 극장(§0.9)이다.
