# Judgment Key v4 경계 관측 프로토콜 — semantic 입력 랜딩 EXECUTED 기대·로그 검증 기록

> **성격**: 관측 프로토콜 기록 (경계 항목의 기대값·완결 정의·관측 결과) — 성공 선언이 아니다.
> **데이터 SSOT**: `data/ci_optimization/judgment_key_v4_interim_2026-10-19.json` (`observations.boundaryCandidates`)
> **선행 문서**: `judgment_key_v4_interim_adjudication_2026-10-19.md` §9 (n=3→4 addendum) · `mg_reuse_cutover_e2e_2026-10-18.md` (REUSED 장소 재결)
> **관측 quirk 정본**: `docs/spec/gh_merge_admission_observation_quirks.md` Q2 (org 필수 워크플로 run의 `gh run view` 404) · `docs/spec/gh_run_observation_quirks.md` Q3 (jobs 로그 ANSI 이스케이프 거부)

기록일: 2026-10-19

## 1. 목적 — REUSED 장소의 입력 경계

v4 eligible-REUSED-on-MG 장소(재결 2026-10-18, `#920`/`#926` 경유)에서 **어떤 변경 입력이 클로저(판정 입력)를 무효화해 EXECUTED로 되돌리고, 어떤 입력이 REUSED를 유지하는가**를 실제 착지 누적으로만 관측한다. REUSED 밴드(401–550s)는 비의미 입력 랜딩의 회귀 기대치이고, semantic 입력 랜딩은 EXECUTED(구세대 밴드 550–737s)로 되돌아가는 것이 기대다.

## 2. 관측된 semantic 입력 랜딩 — 기대 EXECUTED · 관측 EXECUTED (2026-10-19)

| PR | 입력 클래스 (PR files API 실측) | MG 런 | wall | 기대 | 관측 (로그 레벨) |
|---|---|---|---|---|---|
| #929 | docs/spec 규범 — `docs/spec/replay_harness_config_quirks.md` 단일 파일 | `39186880938` | 698s | EXECUTED | `EXECUTED — no record for the current closure (fresh judgment)` — lane-0+lane-1, 4주체 전부 |
| #930 | src/config — `src/verification/counterexample_replay.nim` 수리 + `tests/unit`·`docs/spec` 2건·`config/trusted_writer_set.json`·`data/architecture_debt.json` | `39190425325` | 697s | EXECUTED | 동일 — lane-0(s1a) + lane-1(proof_integrity·d2_golden·d2_persist) 3주체 |
| #931 | Makefile/config/data/src — `Makefile`·`config/trusted_writer_set.json`·`data/*` 3건·`docs/spec/rust_*` 2건·`src/cli` 3건·`src/verification` 2건·`tests` 3건·`docs/evidence` 1건 | `39193523600` | 702s | EXECUTED | 동일 — lane-0(s1a) + lane-1 3주체 |

대조(비의미 클래스 — REUSED 유지): **#926/#927/#928** — `docs/evidence`·`data/ci_optimization` 변경만, walls **437/414/439s**, 3연속 REUSED (`judgment_key_v4_interim_adjudication_2026-10-19.md` §9.1).

관측 해시: `docs/spec` 규범 변경(#929, 단일 파일)만으로도 **4주체 전체**가 fresh judgment로 재실행됐다 — 같은 "문서" 클래스라도 `docs/evidence`·`data/ci_optimization`(비의미, REUSED 유지)과 `docs/spec`(규범, semantic 입력)은 행동이 갈린다. src·Makefile·config·tests 변경도 예상대로 클로저를 무효화했다.

### 2a. 경계 이동 관측 — #932 (비의미 클래스 랜딩이 EXECUTED로 발화, 2026-10-19)

semantic 시퀀스(#929–#931) 이후 **첫 비의미 클래스 랜딩** — 본 문서의 쌍동 PR인 n=4 addendum 원장 착지(#932, `docs/evidence`+`data/ci_optimization` 변경) — 는 **REUSED가 아니라 EXECUTED로 발화**했다:

- MG 런 `39198659706` (merge_group, success, 04:16:39 → 04:27:49Z) — wall **670s** (EXECUTED 밴드 550–737s)
- lane-0: `AXIOM_JUDGMENT_CAS: EXECUTED — no record for the current closure (fresh judgment)` (job `117887210829`) — lane-1 3주체 동일 (job `117887210917`)
- `AXIOM_JUDGMENT_CAS_FORCE_EXECUTED: 1` venue marker는 기존과 동일 잔존 — 발화은 클로저 미적중이지 장소 부적격이 아니다

해석 유보(원인 규명은 후속 과제): #928까지는 동일 입력 클래스가 REUSED였으므로, 이 관측은 **경계가 이동했거나** #929–#931 EXECUTED 시퀀스가 남긴 저장 레코드와 후보 클로저가 어긋남을 뜻한다. REUSED 빈도 집계에는 REUSED 아닌 착지로 기록하며(스테이크 3연속은 #926–#928에서 종료), 후속 비의미 랜딩의 발화가 이를 확인·부정한다. 본 문서 착지 자체가 그 다음 관측점이다.

## 3. lane-log API 갭 — 문서화된 org-run quirk 맥락

MG 런의 로그 레벨 검증이 지연됐던 원인은 두 겹의 문서화된 quirk다:

1. **org 필수 워크플로 run 404** — admission-gate는 조직 저장소 `Archright/.github`의 `.github/workflows/admission-gate-v2.yml`(org ruleset 25218071)이 원천인 org required workflow다. 그 run의 `gh run view <id>`·`--log`는 `workflow_id`를 현 저장소 workflows 엔드포인트로 재해석 → `failed to get run: HTTP 404` (Q2, 원기록 `gh_org_required_workflow_run_quirks.md`). run 자체는 `repos/Archright/Axiom/actions/runs/{id}` REST로 정상 조회된다.
2. **jobs 로그 ANSI 이스케이프 사전 거부** — `gh api repos/…/actions/jobs/{id}/logs`는 응답이 터미널 이스케이프 시퀀스를 포함하면 거부한다: `the response contains terminal escape sequences; pass --allow-escape-sequences to output it anyway` (미지정 시 **빈 출력 + 실패**). (Q3, `gh_run_observation_quirks.md`)

정규 관측 경로(본 문서 §2 전체가 사용):

```bash
# run 메타·wall = updated_at − created_at (Q2 우회 — runs REST)
gh api repos/Archright/Axiom/actions/runs/<MG_RUN_ID> --jq '[.created_at,.updated_at,.event,.conclusion]'
# 레인 잡 목록
gh api repos/Archright/Axiom/actions/runs/<MG_RUN_ID>/jobs --jq '.jobs[] | select(.name | test("go-critical-lane")) | [.id,.name,.conclusion]'
# 레인 로그 본문 (Q3 — --allow-escape-sequences 필수 + sed 탈출)
gh api --allow-escape-sequences repos/Archright/Axiom/actions/jobs/<LANE_JOB_ID>/logs 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "REUSED — record|EXECUTED — no record"
```

## 4. 경계 항목의 완결 증거 (completion definition)

경계 후보(입력 클래스 → 기대 basis)가 "확정"하려면 실제 착지에서 다음 전부가 관측돼야 한다:

1. **venue**: `admission-gate`(org required workflow), `event=merge_group`, run `head_sha` == PR 머지 커밋 — 원장 landings 엔트리와 동일 결속.
2. **wall**: run `created_at`/`updated_at` delta — runs REST 원문 (§3 경로).
3. **lane 발화**: 레인 잡 로그의 주체별 `AXIOM_JUDGMENT_CAS` 라인 — 기대 EXECUTED면 `EXECUTED — no record for the current closure (fresh judgment)`, 기대 REUSED면 `REUSED — record <id> re-verified`.
4. **입력 클래스 분류**: PR files API의 실제 변경 파일 목록 — 제목·추측 기반 분류 금지.

## 5. 무합성 변경 원칙 (no synthetic changes)

경계 관측은 **실제 개발 착지의 누적**으로만 진행한다. 관측을 위해 입력 클래스를 인위적으로 격리하는 프로브 PR(예: config-only 더미 변경, 문서 한 줄 수정)을 만들지 않는다. 미관측 클래스는 "미확정"으로 남고, 후속 실제 착지가 그 클래스를 운반할 때 §4의 증거로 확정한다. 이는 원장의 사전등록 준칙(`judgment_key_v4_interim_adjudication_2026-10-19.md` — 역추적 보간 금지, 확인은 후속 랜딩 누적으로만)과 동일한 정직성 계약이다.

## 6. 미확정 경계 항목 (open items — 합성 프루브 없이 대기)

- 비의미 클래스(`docs/evidence`·`data/ci_optimization`)의 REUSED **재개 조건** — #932가 EXECUTED 발화(§2a): 경계 이동 확인·원인 규명이 선행된다
- `config/` 정책 파일 **단독** 변경 — #930/#931은 src 동반이라 단독 효과 미분리
- `tests/` **단독** 변경
- `data/` 정책성 데이터(`ci_optimization` 외) 단독 변경
- 문서 경계의 나머지: `docs/guides`·`docs/adr`·`docs/agents` 등 비규범 문서 (`docs/evidence`는 REUSED 관측, `docs/spec`은 EXECUTED 관측 — 그 외 경로 미관측)

## 7. 재현 명령

```bash
gh api repos/Archright/Axiom/actions/runs/39186880938 --jq '[.created_at,.updated_at,.conclusion]'  # → 698s (#929)
gh api repos/Archright/Axiom/actions/runs/39190425325 --jq '[.created_at,.updated_at,.conclusion]'  # → 697s (#930)
gh api repos/Archright/Axiom/actions/runs/39193523600 --jq '[.created_at,.updated_at,.conclusion]'  # → 702s (#931)
gh api repos/Archright/Axiom/pulls/929/files --jq '.[].filename'   # 입력 클래스 실측 (#930/#931 동일)
gh api --allow-escape-sequences repos/Archright/Axiom/actions/jobs/117851319021/logs 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep "EXECUTED — no record"  # #929 lane-0
gh api --allow-escape-sequences repos/Archright/Axiom/actions/jobs/117862080147/logs 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -c "EXECUTED — no record"  # #930 lane-1 → 3
```

## 8. Addendum (2026-10-19 후반) — REUSED 재개 확정(#934/#933)·경계 정밀화·semantic 확인(#935–#939)

> 추가 기록: 2026-10-19 (append-only — §1–7 미변경) · 데이터 SSOT: `data/ci_optimization/judgment_key_v4_interim_2026-10-19.json` (observedN 3→5 동시 갱신)
> 합성 프루브 없음 — 본 절의 전체 표본은 실제 개발 착지다 (§5 준칙 유지).

### 8.1 §6 open item 해소 — 비의미 클래스 REUSED 재개

§2a의 "본 문서 착지 자체가 그 다음 관측점" 예언대로, 본 문서의 착지(#934)가 그 관측점이 됐다. #932 전환 EXECUTED가 발행한 기록 세대 2(a3f14dbb8cc2 / d6dd58e95612 / 069929f3ce7e / 71aff5818ab4)를 다음 두 비의미 랜딩이 재사용했다:

| 착지 | 입력 클래스 (PR files API 실측) | MG 런 | wall | 기대 | 관측 (lane 로그) |
|---|---|---|---|---|---|
| #934 | docs/evidence — 본 문서 1건 (비의미) | `39200840559` | 420s | REUSED 또는 EXECUTED (§2a 미해소) | **REUSED — 4주체 전부** (lane-0 `117893724202`, lane-1 `117893724188`), no-record 0건 |
| #933 | rust-lane 경로 — `src/cli/rust_lane_cli.nim` + `docs/spec/rust_*` 2건 + `data/nimtry_baseline.json`·`data/benchmarks/perf_latest.json` + `config/trusted_writer_set.json` | `39203157606` | 404s | 미등록 (신규 클래스) | **REUSED — 4주체 전부, 세대 2 동일 ID** (lane-0 `117900728443`, lane-1 `117900728140`), no-record 0건 |

- 재개 조건의 확정: semantic 시퀀스 직후 첫 비의미 랜딩(#932)은 1회 전환 EXECUTED(새 세대 발행)를 거치고, **그 이후의 비의미 랜딩부터 REUSED가 재개된다** — #934·#933 두 표본으로 확인. mint: `MINT_JUDGAPPEND: OK — idempotent no-op (judgment key a3f14dbb8cc2 already stored, append exactly-once: 0)` — #934 job `117894757915` / #933 job `117901717439`, fail-closed 바인딩 통과.
- adjudication 문서 §9.1이 #932 착지를 "4번째 REUSED 표본"으로 사전등록했으나 실발화는 EXECUTED였다 — 사전등록 표본은 **관측으로만 확정**된다는 준칙(역추적 보간 금지)대로 n에 포함하지 않았고, 4·5번째 표본은 #934/#933으로 도달했다.

### 8.2 경계 정밀화 — 클로저는 경로별로 판정된다 (문서 클래스 전체가 아니다)

- **#933 (REUSED 유지)** — `docs/spec` 규범 2건(`rust_certified_subset.md`·`rust_toolchain_quirks.md`)과 `src/cli/rust_lane_cli.nim` 변경에도 4주체 클로저가 무효화되지 않았다. §2의 "#929 docs/spec → EXECUTED" 해석을 정밀화한다: **verification 주체 파일(`replay_harness_config_quirks.md`)만 클로저에 편입**되며, 문서 클래스 전체가 아니다. 관측된 rust-lane 경로들은 4주체 Nim 커널 클로저 밖이다. 일반화는 관측된 파일 경로에 한한다.
- **#935–#939 semantic 확인 — 5/5 EXECUTED (기대 부합)**:

| PR | 입력 클래스 (files API 실측) | MG 런 | wall | lane 발화 |
|---|---|---|---|---|
| #935 | src/verification 2건 + tests 3건 (BMC error guard) | `39203766464` | 744s | EXECUTED — 4주체 (lane-0 `117902469086`, lane-1 `117902469124`) |
| #936 | src 12건 + tests 5건 (operational closure) | `39212037549` | 670s | EXECUTED — 4주체 (lane-0 `117927879109`, lane-1 `117927879080`) |
| #937 | src/cli·src/verification rust_* + docs/spec/replay_evidence_policy.md 등 | `39214437187` | 713s | EXECUTED — 4주체 (lane-0 `117935375329`, lane-1 `117935375204`) |
| #938 | src/cli/axiom_engine.nim + config/spec sidecar 계약 + docs/spec | `39215079947` | 733s | EXECUTED — 4주체 (lane-0 `117937405763`, lane-1 `117937405789`) |
| #939 | src/verification/cert_promotion.nim + config | `39215742092` | 966s | EXECUTED — 4주체 (lane-0 `117940820976`, lane-1 `117940821095`) |

- **#937/#938 REUSED 후보 가설 기각** — 두 PR 모두 클로저 편입 입력(verification 주체 규범 문서·engine 주체 src)을 운반했다. semantic 입력 8/8 EXECUTED로 §1의 기대와 부합.
- wall 원값 주의: #935 744s(구세대 밴드 상단 737s 초과 — 원값 기록), #939 966s(#938 MG 런과 병행 실행 병기 — 대기 포함 가능성, 보간 없음).

### 8.3 비착지 red 런 기록 (landing census 제외)

#933의 stale-base merge 시도 2건이 admission failure로 소멸했다 — 착지가 아니므로 REUSED 빈도·red 집계 모두 제외하되 원장에 정직 기록한다:

- run `39199399237` (head `5683704622f5`, parent c0fd9af3e87d) — 04:25:32 → 04:36:48Z, failure
- run `39200951071` (head `6d7669b14578`, parent 192034c2d54d) — 04:44:02 → 04:50:50Z, failure

### 8.4 GitHub Actions 의미론 대조 (Context7 `/websites/github_en_actions` 조회 — 2026-10-19)

- `on.merge_group`(`types: [checks_requested]`, `branches` 필터는 대상 브랜치명 평가): MG 런은 **병합 예정 결과(merge group)를 대상 브랜치에 대해 검증**한다 — 본 관측에서 run `head_sha`가 항상 PR 머지 커밋(#934 → `192034c2d54d`, #933 → `27e731043eed`)과 일치한 것과 부합. 착지 census의 venue 결속(§4.1)은 이 의미론에 근거한다.
- `actions/cache` 의존성 캐시: 복원은 **정확한 key 일치 우선 → 부분 일치 → `restore-keys` 순차 폴백**, 캐시 스코프는 현재 브랜치·기본 브랜치로 제한. judgment CAS의 재사용은 이보다 **엄격하다** — 클로저 불일치 시 폴백 없이 `EXECUTED — no record for the current closure`(키 미스)로 발화하고, 일치 시에만 `REUSED — record <id> re-verified`로 재검증(re-derivation + executionEpoch + per-read re-hash)한다. 본 관측의 클래스별 발화 분리(#933 REUSED vs #937 EXECUTED)는 이 정확-키 의미론과 정합이다.

### 8.5 재현 명령 (addendum 분)

```bash
# walls — 420s(#934)/404s(#933)/744s(#935)/670s(#936)/713s(#937)/733s(#938)/966s(#939)
for r in 39200840559 39203157606 39203766464 39212037549 39214437187 39215079947 39215742092; do
  gh api repos/Archright/Axiom/actions/runs/$r --jq '[.id,.created_at,.updated_at,.conclusion]'
done

# lane 발화 (quirk Q3 — --allow-escape-sequences 필수)
gh api --allow-escape-sequences repos/Archright/Axiom/actions/jobs/117893724202/logs 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "REUSED — record|EXECUTED — no record"  # #934 lane-0 → REUSED
gh api --allow-escape-sequences repos/Archright/Axiom/actions/jobs/117900728140/logs 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -c "REUSED — record"                    # #933 lane-1 → 3
gh api --allow-escape-sequences repos/Archright/Axiom/actions/jobs/117935375329/logs 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep "EXECUTED — no record"                  # #937 lane-0

# 입력 클래스 실측 (제목·추측 기반 분류 금지 — §4.4)
gh api repos/Archright/Axiom/pulls/933/files --jq '.[].filename'
gh api repos/Archright/Axiom/pulls/937/files --jq '.[].filename'
```
