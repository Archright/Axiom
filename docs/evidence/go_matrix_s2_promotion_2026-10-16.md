# G2 S2 승격 세레머니 기록 — 세대 전환 원자 착지 (2026-10-16)

> **종류**: 실행 증거 문서 (S2 promotion ceremony record) — G2 GO-critical 2-lane job-matrix 승격의 컨트롤러 회전·ruleset 재핀·롤백 앵커 전체 사실 등록. 사전등록 `docs/evidence/go_matrix_parallelization_prereg_2026-10-16.md` §7(롤백 앵커)·§9(검증 가능성)의 S2 의무 이행 기록이다. 판정 권위는 GitHub(ruleset·queue·MERGE 커밋)에 있다(Authority ≠ Adapter).
> **T_promotion**: 2026-10-15T18:59:14Z (Axiom PR #861 mergedAt — §4.3 golive 탐지의 `--since` 입력)

---

## 1. 세대 전환 체인 (3-leg 원자 세레머니)

| leg | PR | 머지 커밋 | 머지 시각 (UTC) | 내용 |
|---|---|---|---|---|
| Axiom | #861 | `d8bc0f0a6ecead54c6067d96dad94425ce9d9d90` | 2026-10-15T18:59:14Z | admission-check.yml 2-lane matrix + 핀 원자 회전 (blob `09125e5edda335b85513c2ce26ec8ed4ee15fa6b` = trustedAdmissionWorkflowSha = productionExecutionPin) |
| Controller | Archright/.github #223 | `b26fbbd882139a726c41271c7b1082b386b33c94` | 2026-10-15T19:03:10Z | admission-gate.yml 양 호출부(:430 attest, :650 verdict) `dc527994c987…` → `d8bc0f0a6ece…` — pin-promotion-gate **PINNED OK** ("all changed pins resolve to the epoch-promoted admission workflow blob 09125e5e — manifest == TWS, 3-way binding verified", run 38790500991) |
| Ruleset | — (API PUT) | — | 2026-10-15T19:04-05Z | org ruleset 24233738 + 23943917 sha 재핀 (아래 §2) |

불변 핀: certificate-mint `b8220e2b` (F2 #856), runner-pool-acceptance·setup-axiom-toolchain `ba773d063` — 양 leg에서 미변경.

## 2. ruleset 재핀 readback (빈 큐 창 — 2026-10-15T19:04Z)

**진입 조건 실측**: Axiom merge queue entries totalCount=0 (GraphQL), merge_group in-flight=0, queued=0 — F2 세레머니 종료 후의 조용한 창.

| ruleset | 이름 | before sha | after sha | ref | 비-sha diff |
|---|---|---|---|---|---|
| 24233738 | axiom-admission-gate | `f26306b453707ced953e827421fa9f995e39002b` | `b26fbbd882139a726c41271c7b1082b386b33c94` | absent | 서버 `updated_at` 타임스탬프만 (설정 필드 전수 바이트 동일) |
| 23943917 | landing-integrity | `f26306b453707ced953e827421fa9f995e39002b` | `b26fbbd882139a726c41271c7b1082b386b33c94` | absent | 동일 |

**freeze 창**: ruleset 20303214 (Axiom repo `main`) merge_queue `max_entries_to_build` 2→0 PUT → readback `0` → 재핀 → readback → 0→2 복원 → readback `2`. 전 구간 GET 확인.

## 3. 롤백 앵커 (사전등록 §7 — S2 의무 이행)

- **live 판독 값 (권위)**: 재핀 직전 ruleset workflows sha = `f26306b453707ced953e827421fa9f995e39002b` (예상 H₃와 일치 — 단 본 기록은 live GET 판독값이다).
- **앵커 태그**: `admission-gen-rollback-20261016` → `f26306b453…` (컨트롤러 원격, 재핀 전 생성·push — immutable reference, 삭제 금지).
- **신세대 태그**: `admission-gen-h4-20261016` → `b26fbbd882…` (컨트롤러 원격). 기존 계열 h0/h1/h2/h3b 다음의 미사용 이름.
- **복원 절차**: `docs/spec/admission-generation.md` §5 verbatim (앵커 sha 값 복원 — `ref: main` 복원 금지).

## 4. 첫 production MG 관측 (S1-deferred 검증 — 별도 후속 문서)

본 문서 착지에 사용된 merge_group admission 런이 **신세대 워크플로(b26fbbd882 → admission-check.yml@09125e5e)의 첫 production 실행**이다. per-lane EXECUTED + 실제 Judgment-CAS 기록 + D4-composite 1차 데이터는 이 런에서 추출하여 후속 증거 문서(`go_matrix_first_mg_observation_2026-10-16.md`)에 등록한다. D4-composite의 성능 판정(S3)은 사전등록 §5의 ≥5 PR 표본이 필요하며 본 관측은 그 전제 데이터다.

---

*본 문서는 세대 전환의 등록 기록이다. 판정 기준의 원본은 사전등록(2026-10-16)이며 본 문서는 그를 변경하지 않는다.*

---

## 최초 프로덕션 관측 (2026-10-15 21:07Z, amendment 2026-10-16)

> **종류**: append-only amendment — §4가 S1-deferred로 유보한 첫 production merge_group 관측의 **관측 후 기입** 등록이다. 관측 대상은 바운드 MG admission-gate 런 **38805085401**이며 모든 값은 GitHub Actions API·job 로그·PR API의 GET-only 관측값이다(`docs/spec/gh_merge_admission_observation_quirks.md` Q2·Q3 준수 — 로그 인출은 `--allow-escape-sequences` 필요). 본 amendment는 사전등록과 본문 §1–4를 변경하지 않는다.

### 착지·어드미션 판정 (권위: GitHub)

- **PR #862 MERGED** — mergeCommit `7be55445dd592fac15c94b8524115b9852cd0ef6`, mergedAt **2026-10-15T21:07:06Z**, MERGE 커밋 parents=2 (native MERGE — `tools/ci/landing_observe.sh 862` VERDICT: TERMINAL_SUCCESS, graphql↔rest consistent).
- **바운드 MG admission-gate 런 38805085401**: event=merge_group, conclusion **success**, run started 2026-10-15T20:49:46Z / updated 21:06:42Z (run wall 1016 s), head = 큐 머지 커밋 `7be55445dd59…`.

### job 타임라인 (jobs API 관측 — run 38805085401)

| job | 결론 | started_at | completed_at |
|---|---|---|---|
| attest / build-base-artifacts | success | 20:49:50Z | 20:55:04Z |
| attest / go-critical-lane (0) | success | 20:55:08Z | 21:02:13Z (wall 425 s) |
| attest / go-critical-lane (1) | success | 20:55:08Z | 21:00:15Z |
| attest / go-critical-rollup | success | 21:02:17Z | 21:02:20Z |
| attest / admission-check | success | 21:02:17Z | 21:03:52Z |
| verdict 스테이지 (verdict / admission-check) | success | 21:05:42Z | 21:06:34Z |
| 최종 집계 admission-check | success | 21:06:37Z | 21:06:41Z |

그 직후 native MERGE (2026-10-15T21:07:06Z).

### 레인 증거 (job 로그 관측)

- **양 레인 동시 시작 20:55:08Z — 병렬성 관측** (lane 0·lane 1 started_at 동일; job id 각각 116666182064 / 116666182213).
- **lane-0**: `AXIOM_JUDGMENT_CAS: EXECUTED — no record for the current closure (fresh judgment)` (20:56:07Z) → `[admission-tests] LANE lane=0 test_s1a_lean_golden duration_ms=361255` → `PASS — tests/unit/test_s1a_lean_golden.nim (basis=EXECUTED — fresh judgment measured)` → **PASS 1/1**.
- **lane-1**: EXECUTED 3건 (proof_integrity 20:56:08Z, d2_golden 20:56:09Z, d2_persist 20:56:11Z — 전부 "no record for the current closure (fresh judgment)") → `LANE lane=1 proof_integrity_test duration_ms=50323` · `test_d2_golden duration_ms=156431` · `test_d2_persist duration_ms=32650` → 전부 `PASS … (basis=EXECUTED — fresh judgment measured)` → **PASS 3/3**.
- **REUSED count 0** — 양 레인 모두 런타임 `SKIP … basis=REUSED` 라인 0건(사전등록 §2-(iv) REUSED 불산입의 만족). `[test-supply] restored … entries=0` (양 레인 — J3 공급 없는 실행).

### 정직 노트 — 결함 세대 발견과 긴급 수복

첫 관측 준비 과정에서 #861 승격 세대(h4)의 **레인 job 정의 누락 결함**(0-job 계획 거부)이 발견되었다 → §7 앵커 롤백 → **긴급 수복**: Axiom #863 (`64f78ab7d178…`, 20:05:50Z, blob `f2ad3b03…`) + 컨트롤러 #224 (`74b415c414c0a501a1df125ad92289f0bac17bde`, 20:09:52Z) + ruleset 재핀 **h4→h4b**. 결함 세대 태그 `admission-gen-h4-20261016`(`b26fbbd882…`)는 역사 기록으로 보존된다(삭제 금지). 본 런 38805085401은 h4b 세대(핀 `74b415c414c0…` → callee `64f78ab7d178…`, blob `f2ad3b03`)의 **첫 production 실행**이다.

### D4-composite 데이터포인트-1 (S3 데이터 — 판정 아님)

- **D4-composite datapoint-1 = 361.3 s** (max lane GO — lane-0 `duration_ms=361255`) vs 직렬 합 **540.8 s** / 직렬 중앙값 **545 s** (사전등록 §4.2).
- 레인 GO 1차값: lane-0 = 361.255 s · lane-1 = 50.323 + 156.431 + 32.650 = 239.404 s.
- 보조 관측(합산에 사용하지 않음): per-lane 셋업 경계 job 시작(20:55:08Z)→첫 RUN = lane-0 ≈ 59.4 s, lane-1 ≈ 63.9 s — §5-(a)의 setup 가산(기준치: 직렬 attest setup 56.9 s) 적용은 S3 실행 시 동결 텍스트에 따른다.
- **이것은 S3 데이터포인트일 뿐, 판정이 아니다** — §5 통과 기준은 ≥5 PR 표본 + 동결 명령으로만 판정한다.

### S3 INTERIM — 동결 명령 드라이런 (n=1, 2026-10-16 실행)

사전등록 `docs/evidence/go_matrix_parallelization_prereg_2026-10-16.md` §4.3의 동결 명령을 현 상태(승격 후 착지 = #862만 존재, n=1)에 대해 실행한 기록. 명령 산출물 원본은 `data/merge_latency/` 아래 커밋된다(`golive_g2matrix.*`, `g2matrix_AFTER.*`, `g2matrix_d4.*`).

| # | 동결 명령 | 결과 | 관측 요지 |
|---|---|---|---|
| 1 | D3 착지 정체성 (`gh pr list --state merged …`) | **PASS** (verbatim) | #862: created 2026-10-15T19:09:06Z → merged 21:07:06Z ⇒ D3(#862) = 7080 s |
| 2 | `tools/ci/golive_detect.sh --since <T_promotion> --tws-sha <신TWS> --out data/merge_latency/golive_g2matrix` | **FAIL exit 2** (동결 텍스트 그대로) → **PASS exit 0** (`--until` 완결형) | 동결 텍스트는 도구의 필수 인자 `--until` 누락("[golive] measure에는 --runs IDS 또는 --since X --until Y 필요"). 완결 실행: 창 내 MG 런 2건 분류 — 38796772058 pre-go-live(핀 `dc527994…`, blob `b2b8235d` ≠ TWS), **38805085401 POST-go-live**(핀 `64f78ab7d178` → blob `f2ad3b03` == TWS `f2ad3b03b357…`), boundary `first_post_run_id=38805085401` @ 20:49:46Z, `post_golive.ids = [38805085401]` |
| 3 | `tools/ci/merge_latency_audit.sh --runs @data/merge_latency/golive_g2matrix.post_golive.ids --out data/merge_latency/g2matrix_AFTER --boundary-note "…"` | **PASS exit 0** | wall=1016 s · dur_sum=994 s · gaps=17 s. **매트릭스 세대 편차**: `go_step=null`(`go_step_matches=0`) · `classification=UNKNOWN_LOG` — GO 스텝이 lane job으로 이동하여 consume job(`attest / admission-check`)의 steps[]·로그에 GO 흔적이 없음(fail-closed 기록, 침묵 폐기 없음). boundary-note는 동결 템플릿 문자 그대로 기록 |
| 4 | `tools/ci/go_critical_parallel_extraction.sh runs <t_go_live> <out>` | **기계적 exit 0, D4 값 전부 NA** (`go_mode=none`, `gc_fired=no`) | 동결 추출기는 consume job(`attest / admission-check`, job 116669415173) 단일만 조회 — LANE 행은 이제 `attest / go-critical-lane (0|1)` job 로그에 존재. **동결 명령이 매트릭스 형상에서 1차값을 수집하지 못하는 실패의 정확한 재현** |
| 5 | D4 로그 1차값 채널 (`gh api …/jobs/<JOB_ID>/logs` + grep) | **PASS** (lane job 116666182064 / 116666182213) | `[admission-tests] LANE … duration_ms=` 4행 + RUN/PASS 라인 전수 추출(lane-0 361255 · lane-1 50323/156431/32650) — G-B 1차값 채널은 레인 job 지정 시 정상 작동 |
| 6 | `tools/ci/landing_observe.sh 862` | **PASS** | VERDICT: TERMINAL_SUCCESS — state=MERGED ∧ mergedAt ∧ mergeCommit.oid ∧ parents=2 |

실행 명령 원문(placeholder 채움값 포함, verbatim):

```bash
# (2) golive — 동결 텍스트 그대로는 exit 2 (아래 첫 줄); 완결형이 관측 실행
tools/ci/golive_detect.sh --since 2026-10-15T18:59:14Z --tws-sha f2ad3b03b357fdf30976d4e2cbaf6b0927de8830 --out data/merge_latency/golive_g2matrix
tools/ci/golive_detect.sh --since 2026-10-15T18:59:14Z --until 2026-10-16T01:53:12Z --tws-sha f2ad3b03b357fdf30976d4e2cbaf6b0927de8830 --out data/merge_latency/golive_g2matrix
# (3) audit — boundary-note placeholder를 관측 first_post_run_id로 채움
tools/ci/merge_latency_audit.sh --runs @data/merge_latency/golive_g2matrix.post_golive.ids \
  --out data/merge_latency/g2matrix_AFTER --boundary-note "smoke=38805085401 excluded; g2 matrix prereg 2026-10-16"
# (4) D4 배치 추출 — t_go_live = golive boundary first_post_run_started_at
tools/ci/go_critical_parallel_extraction.sh runs 2026-10-15T20:49:46Z data/merge_latency/g2matrix_d4
# (5) D4 로그 1차값 — JOB_ID = 레인 job (레인 0 / 레인 1)
gh api --allow-escape-sequences repos/Archright/Axiom/actions/jobs/116666182064/logs \
  | grep -E "\[admission-tests\] (RUN|PASS)|duration_ms=|\[test-supply\]"
gh api --allow-escape-sequences repos/Archright/Axiom/actions/jobs/116666182213/logs \
  | grep -E "\[admission-tests\] (RUN|PASS)|duration_ms=|\[test-supply\]"
```

**적응 질문 (측정 정의 보존 — 부모 판정 대기, 본 amendment는 무단 적용하지 않음)**:

- **Q1 (golive `--until`)**: 동결 명령 텍스트가 도구의 필수 인자를 생략한다(사전등록 §4.3·§9 동일). 최소 완결은 `--until <수집 시각>` 추가뿐이다 — 창 시작(T_promotion)·TWS 등식·분류 규칙은 전부 불변. S3 실행 표준 문구에 이 완결을 명시할지는 부모 판정 사항.
- **Q2 (D4 배치 추출기의 job 소스)**: G-B 1차값 정의(`[admission-tests] LANE … duration_ms=` 행)는 그대로 유지한 채, 추출기의 job 선택을 consume job 단일에서 레인 job(`attest / go-critical-lane (0|1)`) 포함으로 확장하는 **레인-어웨어 변형**이 필요하다(도구의 LANE 파서는 이미 dual-mode — 조회 job만 확장). 이는 측정 정의 보존이지만 동결 명령 텍스트·사전등록 본문의 변경에 해당할 수 있어 **적용하지 않았다** — 사전등록의 no-peeking 규율(관측 후 기준 변경 금지, 변경은 새 날짜 등록 문서로만)에 따라 부모 판정을 요청한다. 참고: audit의 `go_step` 성분(steps[] `^\[check\] GO-critical` 매처)도 매트릭스 세대에서 0-매치다 — §4.1 D4 행(직렬 세대 attest 스텝 정의)과 §5-(a) composite 정의(lane GO 기반, 이미 고정)의 관계 정리를 Q2와 함께 판정 대기한다. 필요한 원값은 이미 위 5행(로그 1차값 채널)으로 관측·등록되어 있다.

**S3 판정 대기: n=1/≥5 (승격 PR #861 제외 규칙 준수) — 판정은 n≥5 도달 후 동결 명령으로만.**

n=1 = PR #862(승격 후 첫 착지). 승격 PR #861은 사전등록 §5 표본 정의대로 제외한다. 본 amendment는 판정을 내지 않으며(Reporter), merge-admission 권위는 GitHub에 있다(Authority ≠ Adapter).

*본 amendment는 append-only 관측 등록이다 — 사전등록(2026-10-16)과 본문 §1–4를 변경하지 않는다.*
