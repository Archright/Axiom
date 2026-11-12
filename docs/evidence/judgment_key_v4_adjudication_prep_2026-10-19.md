# Judgment Key v4 최종 판정 준비 — J1–J4 증거 맵·3지표 표·diff 무접촉 체크리스트

> **성격**: 판정 준비 템플릿 (adjudication preparation record) — 판정 선언이 아니다. 본 문서는 최종 판정이 확정해야 할 항목·증거 소스·기입 규칙을 **사전등록**한다; 판정 선언은 이 문서의 실행이 아니라 별도 최종 판정 기록이 한다.
> **데이터 SSOT**: `data/ci_optimization/judgment_key_v4_interim_2026-10-19.json` (관측 원장 — 본 문서는 이를 변경하지 않는다)
> **선행 문서**: `judgment_key_v4_boundary_consolidation_2026-10-19.md` (경계 통합) · `judgment_key_v4_interim_adjudication_2026-10-19.md` §9/§10 (표본 누적·세대 교체) · `mg_reuse_policy_redecision_2026-10-18.md` §2 (계약 §5 verbatim)·§4 (3지표 측정 계획) · `judgment_key_v4_boundary_watch_2026-10-19.md` §4 (완결 증거 정의)
> **관측 quirk 정본**: `docs/spec/gh_merge_admission_observation_quirks.md` Q2 · `docs/spec/gh_run_observation_quirks.md` Q3 (`--allow-escape-sequences` 필수 — 미지정 시 빈 출력+실패)
> **본 문서의 접촉면**: docs/evidence 단일 .md — `data/*.json`·`src/`·`config/`·`docs/spec/` 무접촉

기록일: 2026-10-19

## 1. 판정 항목 J1–J4 — 주장·확정 조건·증거 소스

각 항목의 기입 규칙: 증거는 **관측 원문**(API/로그)으로만 확정하고, 역추적 보간·추측 분류 금지 (boundary watch §4 완결 정의·§5 무합성 원칙 계승). `(기입)` 슬롯은 최종 판정 실행 시 착지 관측으로 채운다.

### J1 — docs .md 확장자의 무의미성 + record key 동일성

- **주장**: docs/evidence 아래 .md 전용 변경은 판정 입력(9성분 클로저)을 변동시키지 않는다 — 관측으로 확정되는 것은 확장자 일반이 아니라 **record key(클로저 지문)의 동일성**이다. 착지 간 record key가 동일하게 유지되면 docs .md 변경은 클로저 비편입으로 확정한다.
- **확정 조건**: docs-only 착지에서 4주체 전부 REUSED 발화 + 착지 간 record id 4개 집합 동일.
- **증거 소스 (정확한 소스)**:
  - 착지 집합: #926 (MG 런 `39134186961`) / #927 (`39135473401`) / #928 (`39186429925`) / #934 (`39200840559`) + consolidation 문서·본 문서의 착지 런 (기입: `MG_RUN_ID_A` / `MG_RUN_ID_B`)
  - 입력 클래스 실측: `gh api repos/Archright/Axiom/pulls/<N>/files --jq '.[].filename'` — docs/evidence/*.md 외 0건이어야 한다 (#928의 `data/ci_optimization` 동반 사례는 클래스 경계 주석으로 분리 기록 — consolidation §3)
  - lane 로그 발화: `gh api --allow-escape-sequences repos/Archright/Axiom/actions/jobs/<LANE0_JOB_ID>/logs 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "REUSED — record|EXECUTED — no record"`
  - 대조 경계: #929 (run `39186880938`, docs/spec 규범 1건 → EXECUTED) — "문서" 내부에도 클로저 편입 경로가 존재함을 보이는 관측. J1의 주장은 docs/evidence .md에 한정되며 docs/spec·docs/agents 등으로 확대되지 않는다 (§0.12 주장 범위 유지).

### J2 — verdict success + mint fail-closed 바인딩 + record ID 동일성

- **주장**: 각 표본 착지의 verdict가 success이고, mint-publish가 fail-closed 바인딩 `sha256(payload)==record payloadSha256`을 통과하며(멱등 no-op), record ID 4개가 착지 간 동일하다.
- **증거 소스**:
  - run 결속: `gh api repos/Archright/Axiom/actions/runs/<MG_RUN_ID> --jq '[.conclusion,.event,.head_branch]'` → `success`, `merge_group`, `gh-readonly-queue/main/pr-<N>-*` (venue·wall은 consolidation §2/§3 표 원값)
  - verdict job: `verdict / admission-check` job 로그 (예: #934 job `117894758575`) — grep: `grep '"result":"mergeGo"'` — 원문 예: `{"prNumber":934,"headSha":"6f8204426be1…","baseSha":"c0fd9af3e87d…","verdict":{"result":"mergeGo","reasonCode":"GO","reason":"admission passes cleared (base provenance bound to main c0fd9af3e87d; landing freshness enforced by merge-queue invalidation — ADR-0027 P5)"},…}`
  - mint job: `gh api --allow-escape-sequences repos/Archright/Axiom/actions/jobs/<MINT_ID>/logs 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep "MINT_JUDGAPPEND"` — 성공 원문 `MINT_JUDGAPPEND: OK — idempotent no-op (judgment key <id12> already stored, append exactly-once: 0)`; 실패 원문 `MINT_JUDGAPPEND: FAIL — $1 (fail-closed)` — **fail-closed 구조의 직접 증거**(성공 라인만으로는 부족). job id: #934 mint-publish/publish `117894757915`, #933 `117901717439`, 세대 발행 #932 `117889346354`
  - record ID 동일성 (세대 2): s1a_lane0 `a3f14dbb8cc2` · proof_integrity `d6dd58e95612` · d2_golden `069929f3ce7e` · d2_persist `71aff5818ab4` — #934/#933 상이한 런에서 동일 4개 (adjudication §10.1/§10.2)
  - 원장 필드: `landings[].payloadSha256Binding` = "pass — sha256(payload)==record payloadSha256 (fail-closed; tampered-record 경로 발화 0건)"

### J3 — miss→EXECUTED fail-closed + no-record 이유 라인

- **주장**: 클로저 미적중(miss)은 그림자 REUSED로 절대 발화하지 않고 **EXECUTED**로 fail-closed 전환하며, 그 이유 라인이 lane 로그에 남는다.
- **증거 소스**:
  - 이유 라인 원문: `AXIOM_JUDGMENT_CAS: EXECUTED — no record for the current closure (fresh judgment)` (lane-0/s1a) · `AXIOM_JUDGMENT_CAS [proof_integrity] : EXECUTED — no record …` / `[d2_golden] : …` / `[d2_persist] : …` (lane-1 3주체)
  - 관측 집합: semantic 랜딩 6건 — #932 `39198659706` / #935 `39203766464` / #936 `39212037549` / #938 `39215079947` / #939 `39215742092` / #942 `39226469788` (lane job id — consolidation §2 표)
  - grep: `gh api --allow-escape-sequences repos/Archright/Axiom/actions/jobs/<LANE_JOB_ID>/logs 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "EXECUTED — no record"`
  - 대조 0건 확인: REUSED 표본에서 `grep -c "no record for the current closure"` → 0 (adjudication §10.1 — #934/#933 4주체×2 랜딩)
  - 실행 생략 증거: `[admission-tests] SKIP — $t (AXIOM_JUDGMENT_CAS basis=REUSED — record re-verified, no kernel run this attempt)` — REUSED 시 커널 미실행의 직접 라인

### J4 — 상이한 런 간 동일 record ID 재사용 + 계약 §5 조건 로그 라인

- **주장**: 서로 다른 MG 런에서 동일 record id가 `re-verified`로 재검증되며, 그 로그 라인은 계약 §5 REUSED 성립 조건 중 (a) 클로저 동일성·(b) executionEpoch 일치·(c) per-read 재해시의 **로그 투영**을 담는다.
- **증거 소스**:
  - 원문: `AXIOM_JUDGMENT_CAS: REUSED — record a3f14dbb8cc2 re-verified (closure re-derivation + executionEpoch + per-read re-hash all passed)` — #934 lane-0 job `117893724202` / #933 lane-0 job `117900728443` (동일 id·상이한 런 — 재사용의 직접 쌍)
  - 계약 §5 5조건 원문 위치: `docs/spec/test_judgment_cas_contract.md:166-172` — (a) 클로저 동일성 `(b) executionEpoch 일치 (c) per-read 재해시 (d) witness 바인딩 (e) 도구 정체성` (재결 §2 verbatim 인용)
  - per-unit 결합 규칙: `docs/spec/test_judgment_cas_contract.md:180-182` — 4건 전부의 조건 통과 요구, 하나라도 기각 시 블록 전체 fail-closed EXECUTED 전환 (계약 §6)
  - 범위 주의: 상기 로그 라인은 (a)(b)(c)의 투영이다 — (d)(e)의 직접 로그 투영은 아니며, J4의 확정 범위는 "동일 id 재사용 + (a)(b)(c) 투영 라인"으로 한정한다. (d)(e)는 mint fail-closed 바인딩(J2)·원장 `payloadSha256Binding` 필드로 보강 관측한다 — 로그에 없는 조건을 로그에서 확정했다고 쓰지 않는다 (§0.9).
- **기입 슬롯**: 본 문서 착지 런의 재검증 쌍 (lane job id 2개 + record id) — (기입)

## 2. 3지표 표 스켈레톤 (재결 §4 동결 공식 — 한 글자 변경 없음)

| 지표 | 정의 (동결 — 재결 §4, `post_a_d3_decomposition_2026-10-17.md`) | 기준선 (신세대 clean) | 표본 값 (착지 후 기입 — 원값만) |
|---|---|---|---|
| preflight (D1) | PR 생성→첫 required-green | 평균 **287.5s (29.0%)** | (기입 — 표본별 중앙값/원값) |
| MG wall | merge_group 런 created→updated (runs REST) | 평균 **666.8s (67.3%)** — 본 정책의 직접 표적 | (기입) |
| D3 | 생성→mergedAt | 중앙값 **1006s ≤ 1256s 목표 (4/4)** | (기입) |

- 기입 규칙: runs REST `created_at`/`updated_at` 원값만 (Q2 우회). **판정은 중앙값 비교 (before vs after, n≥5)** — 단일 런 최저치 아님; 401–402s는 baseline이지 guarantee가 아님 (재결 §4).
- 실행-축 전진 PR은 효과 표본에서 분리 보고 (키 전진 → MISS → EXECUTED는 정상 — 재결 §4 절차).

## 3. diff trust-path 무접촉 체크리스트 (판정 실행 시 표본별 확인)

trustSurface(`config/policy/merge_admission.json`) 14개 패턴과의 **교집합 0** 확인:

- [ ] `gh api repos/Archright/Axiom/pulls/<N>/files --jq '.[].filename'` 산출 ∩ 다음 = ∅ — `.github/workflows/repository_surface.yml`, `.github/workflows/runner-pool-acceptance.yml`, `.github/workflows/admission-check.yml`, `.github/workflows/certificate-mint.yml`, `.github/workflows/bsec-integrity.yml`, `.github/actions/setup-axiom-toolchain/**`, `config/policy/merge_admission.json`, `config/app_landing_binding.json`, `config/executor_authority.json`, `config/trusted_writer_set.json`, `src/cli/merge_cli.nim`, `src/core/trusted/trust_boundary.nim`, `src/verification/verification_subject.nim`, `experiments/act2-wp-toml-b1-input-integrity/bsec/replay.sh`
- [ ] `data/*.json` 무접촉 (semantic 데이터 — 원장 갱신은 별도 권한 절차; consolidation §4.4)
- [ ] `src/`·`tests/`·`config/`·`Makefile`·`docs/spec/` 무접촉 (클로저 편입 성분 — #929/#930/#931/#935–#939 관측 참조)
- [ ] 변경 파일 = `docs/evidence/*.md` 뿐
- [ ] 착지 방식: GitHub 네이티브 **MERGE** 커밋 — parent2 == PR head (INV-1; 병합 판정 권위 GitHub — AGENTS.md §2.3)
- [ ] identity 3중 결속: PR head_sha == MG 런 `head_sha` == mergeCommit parent2 (boundary watch §4.1 venue 결속)

## 4. 판정 실행 규칙 (사전등록 — no-post-hoc)

1. 표본 기입 완료 후 J1–J4 **전부** 관측 확정 시에만 최종 판정 기록을 선언한다 — 미확정 항목은 "미확정"으로 남긴다 (확인은 후속 착지 누적으로만).
2. 판정은 본 문서에 사전등록된 항목·기준으로만 수행한다 — 관측 후 기준·항목의 사후 변경 금지 (consolidation §4 무사후 게이트 변경 원칙 계승).
3. 관측은 Reporter로 기록한다; 병합(merge-admission) 판정 권위는 GitHub다 (AGENTS.md §2.3 — 본 문서는 authority가 아니다).
4. `data/*.json` 갱신이 필요하면 별도 권한 절차로만 한다 — 본 문서 계보의 .md 착지는 원장을 변경하지 않는다.

## 5. 재현 명령 (판정 실행 시 사용)

```bash
# 0) 표본 착지 런 결속 (venue·wall·conclusion)
gh api repos/Archright/Axiom/actions/runs/<MG_RUN_ID> --jq '[.id,.created_at,.updated_at,.event,.conclusion,.head_branch]'

# 1) lane 발화 원문 (Q3 — --allow-escape-sequences 필수)
gh api --allow-escape-sequences repos/Archright/Axiom/actions/jobs/<LANE0_JOB_ID>/logs 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "REUSED — record|EXECUTED — no record"
gh api --allow-escape-sequences repos/Archright/Axiom/actions/jobs/<LANE1_JOB_ID>/logs 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -cE "REUSED — record|no record for the current closure"

# 2) mint fail-closed 바인딩·멱등 no-op
gh api --allow-escape-sequences repos/Archright/Axiom/actions/jobs/<MINT_ID>/logs 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep "MINT_JUDGAPPEND"

# 3) 입력 클래스·trust-surface 교집합 실측
gh api repos/Archright/Axiom/pulls/<N>/files --jq '.[].filename'

# 4) J4 재검증 쌍 (동일 id·상이한 런)
gh api --allow-escape-sequences repos/Archright/Axiom/actions/jobs/117893724202/logs 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep "REUSED — record"   # #934 lane-0
gh api --allow-escape-sequences repos/Archright/Axiom/actions/jobs/117900728443/logs 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep "REUSED — record"   # #933 lane-0
```
