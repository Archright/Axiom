# Judgment Key v4 중간 판정 — REUSED 2/2·wall 414–437s (INTERIM — INSUFFICIENT)

> **판정 상태**: **INTERIM — n=2 < 사전등록 ≥5, INSUFFICIENT. 성공 선언이 아니다.**
> ≥5 확정은 후속 랜딩 누적으로만 가능하다(본 문서 후속 addendum 또는 JSON 갱신 — 역추적 보간 금지).
> **데이터 SSOT**: `data/ci_optimization/judgment_key_v4_interim_2026-10-19.json`
> **선행 문서**: `mg_reuse_cutover_e2e_2026-10-18.md` (Addendum 1–3 — v4 E2E 차량·첫 세대 EXECUTED·REUSED 재개 확정) · `ci_epoch_record_judgment_key_v4_2026-10-18.md` (v4 epoch 기록)

기록일: 2026-10-19 · 관측 창: 2026-10-18T13:00–15:00Z (post-v4 MG 병합 2건)
원시 로그: `/tmp/mg_census/` (세션 로컬·휘발) — 모든 수치는 §8 재현 명령으로 GitHub 원문에서 재검증 가능하다.

## 1. 관측 대상 (post-v4 census)

v4 스킴 이후 merge-group 병합 2건 — 두 건 모두 docs-only:

| PR | 판정 | mergedAt | merge commit | head |
|---|---|---|---|---|
| #926 | MERGED | 2026-10-18T14:09:55Z | `9ae1f77a6c39e9ed` | `e9d6c14741403d97` |
| #927 | MERGED | 2026-10-18T14:26:48Z | `2d672dbad07d6c05` | `25f25fc4eccbe89e` |

## 2. REUSED 실증 — MG wall

| 착지 | MG 런 (admission-gate, merge_group) | wall | 목표 밴드 401–550s | vs #925 717s |
|---|---|---|---|---|
| #926 | `39134186961` — success (14:02:16 → 14:09:33Z) | **437s** | ✓ | −280s (−39.0%) |
| #927 | `39135473401` — success (14:19:31 → 14:26:25Z) | **414s** | ✓ | −303s (−42.3%) |

대조 베이스라인(같은 창):

- **#925 docs EXECUTED 717s** — run `39132586441` (13:40:35 → 13:52:32Z), 4주체 원 실행 + v4 record mint (첫 세대 고아화 부트스트랩)
- **#924 code 695s** — run `39130593997` (13:13:24 → 13:24:59Z), 구세대 베이스라 v3 동작으로 실행 (정상 부트스트랩 — `mg_reuse_cutover_e2e_2026-10-18.md` Addendum 3 각주)

→ REUSED 실측 절감 **~270–300s** (717s → 437/414s). 목표 밴드 401–550s(`mg_reuse_cutover_e2e_2026-10-18.md` E2E 목적 선언)에 **2/2 진입**.

## 3. 4주체 record ID 동일성 + mint fail-closed 바인딩

두 랜딩에서 관측된 record ID — **완전히 동일**:

| 주체 (lane) | record ID | #926 | #927 |
|---|---|---|---|
| s1a (lane 0) | `eba3e79cea75` | REUSED | REUSED |
| proof_integrity | `60a4ee8d4948` | REUSED | REUSED |
| d2_golden | `0fd9965ca24d` | REUSED | REUSED |
| d2_persist | `1487289bf7b2` | REUSED | REUSED |

- lane 마커: `AXIOM_JUDGMENT_CAS[주체]: REUSED — record <id> re-verified (closure re-derivation + executionEpoch + per-read re-hash all passed)` → `SKIP — basis=REUSED — record re-verified, no kernel run this attempt`
- `no record for the current closure`: 양 랜딩 **0건**
- mint: `MINT_JUDGAPPEND: OK — idempotent no-op (judgment key <id> already stored, append exactly-once: 0)` — 4주체 × 2랜딩 전부
- fail-closed 바인딩 통과: `sha256(payload) == record payloadSha256` — 불일치 시 "tampered record?" 실패 경로가 존재하며 본 관측 창에서 발화 0건
- verdict: success — `mergeGo` / `GO` (예: #926 — baseSha `8bddab8bee` main 바운드, admission passes cleared)

## 4. red 0 — 귀속 불가 항목의 정직 기록

- MG 레인 **red 0** — 두 런 모두 `conclusion=success`, 레인 내 실패 0건.
- **publisher cancelled 2건** — 레인 귀속 불가로 기록(red 집계 제외, 실패 아님):
  - `ci-cache-publisher` run `39134770396` (createdAt 14:10:08Z) — #926 착지 직후
  - `ci-cache-publisher` run `39136039695` (createdAt 14:27:04Z) — #927 착지 직후
  - `workflow_run` 이벤트로 MG 레인 밖에서 취소 — MG 판정·REUSED 빈도에 귀속하지 않는다.

## 5. REUSED 빈도

- **landing-to-landing: 2/2** — #926 → #927 연속 REUSED (동일 클로저, 판정 입력은 docs-only 델타로 불변)
- **v4 도입 후 전체: 2/3** — #925 첫 세대 EXECUTED(스킴 고아화에 따른 정상 부트스트랩 1회) 제외 시

## 6. 판정 — 왜 INTERIM인가

사전등록 기준 ≥5 랜딩에 대해 **n=2** — 표본 부족. 관측값(414·437s, 밴드 내 2/2, red 0,
record ID 4주체 불변)은 일관되지만 **분포·안정성·이상치 빈도에 대한 주장은 불가하다**.
**INSUFFICIENT — 성공 선언 없음.** 확정은 후속 랜딩 누적으로만 수행한다.

## 7. 관측 메모 (판정 불변 — 무시하지 않고 기록)

- **`AXIOM_JUDGMENT_CAS_FORCE_EXECUTED: 1` echo가 양 랜딩의 lane env에 잔존** — 그러나 실제
  발화는 **REUSED**(4주체 SKIP·`no record for the current closure` 0건이 행위로 반증). 이 env는
  재결(2026-10-18, #920/#926 경유) 이후 **venue marker**(eligible-REUSED-on-MG의 장소 표시)로서
  의도된 잔존이며 EXECUTED 강제로 작동하지 않는다. 향후 정리 대상이나 본 판정의 근거를 변화시키지
  않는다.
- 원시 로그(`/tmp/mg_census/`)는 휘발성 — 수치 인용은 §8 명령으로 GitHub 원문과 대조한다.

## 8. 재현 명령

```bash
# 1) wall = updated_at − created_at, venue·conclusion
gh api repos/Archright/Axiom/actions/runs/39134186961 --jq '[.created_at,.updated_at,.event,.conclusion]'  # → 437s
gh api repos/Archright/Axiom/actions/runs/39135473401 --jq '[.created_at,.updated_at,.event,.conclusion]'  # → 414s
gh api repos/Archright/Axiom/actions/runs/39132586441 --jq '[.created_at,.updated_at,.event,.conclusion]'  # 대조 717s (#925 EXECUTED)
gh api repos/Archright/Axiom/actions/runs/39130593997 --jq '[.created_at,.updated_at,.event,.conclusion]'  # 대조 695s (#924)

# 2) 착지 시각·머지 커밋
gh pr view 926 --repo Archright/Axiom --json mergedAt,mergeCommit
gh pr view 927 --repo Archright/Axiom --json mergedAt,mergeCommit

# 3) 4주체 REUSED 마커 + record ID (양 런에서 동일 4개)
gh run view 39134186961 --repo Archright/Axiom --log | grep -oE "REUSED — record [0-9a-f]{16}" | sort -u
gh run view 39135473401 --repo Archright/Axiom --log | grep -oE "REUSED — record [0-9a-f]{16}" | sort -u

# 4) mint fail-closed 바인딩·멱등 no-op (append exactly-once: 0)
gh run view 39134186961 --repo Archright/Axiom --log | grep -E "MINT_JUDGAPPEND|payloadSha256"
gh run view 39135473401 --repo Archright/Axiom --log | grep -E "MINT_JUDGAPPEND|payloadSha256"
```

## 9. Addendum (2026-10-19) — n=3→4: #928(439s) 표본 반영·3연속 REUSED·경계 후보 기록

> 추가 기록: 2026-10-19 (append-only — 본문 §1–8 미변경) · 관측 창 연장: 2026-10-18T13:00Z → 2026-10-19T02:00Z
> 데이터 SSOT: `data/ci_optimization/judgment_key_v4_interim_2026-10-19.json` (본 addendum과 동시 갱신 — observedN 3, landings 3건)

### 9.1 표본 누적 — 3연속 REUSED (437/414/439s)

#928 — 본 문서를 main에 착지시킨 PR 자체 — 의 MG 런이 관측되어 원장에 추가되었다. 변경 입력은 docs/evidence·data/ci_optimization(비의미 클래스)으로, 클로저 불변 하에서 **3연속 REUSED**가 관측됐다:

| 착지 | MG 런 (admission-gate, merge_group) | wall | 밴드 401–550s |
|---|---|---|---|
| #926 | `39134186961` — success | 437s | ✓ |
| #927 | `39135473401` — success | 414s | ✓ |
| #928 | `39186429925` — success (01:40:31 → 01:47:50Z) | **439s** | ✓ |

- 4주체 record ID 불변: lane-0 `REUSED — record eba3e79cea75 re-verified (closure re-derivation + executionEpoch + per-read re-hash all passed)`, lane-1 `60a4ee8d4948`/`0fd9965ca24d`/`1487289bf7b2` — 레인 0/1 전부 REUSED, `no record for the current closure` 0건
- mint: `MINT_JUDGAPPEND: OK — idempotent no-op (judgment key eba3e79cea75 already stored, append exactly-once: 0)` — fail-closed 바인딩(`sha256(payload)==record payloadSha256`) 통과, verdict `mergeGo/GO` (baseSha `2d672dbad0` main 바운드)
- **원장 n: 3 → 4** — 기록된 REUSED 표본 3개(위 표) + 4번째 표본 = 본 addendum을 운반하는 PR 자체의 착지(docs-only; REUSED 기대). 4번째는 **착지 후 MG 런 관측으로만 확정**된다 — 사전 관측 없는 성공 선언은 없다(§6 준칙 유지).

### 9.2 경계 후보 — semantic 입력 랜딩 3건 (기대 EXECUTED, 로그 레벨 검증 완료)

#929–#931 착지에서 판정 입력의 **경계**가 관측됐다. 세 건은 wall만 선관측(697/702s)되고 로그 레벨 EXECUTED 검증은 lane-log API 갭으로 지연돼 있었다 — `gh api …/jobs/{id}/logs`는 ANSI 이스케이프 포함 응답을 사전 거부한다(quirk Q3, `docs/spec/gh_run_observation_quirks.md`). 본 addendum 관측에서 문서화된 `gh api --allow-escape-sequences` + sed 탈출 경로로 검증을 **완료**했다:

| PR | 입력 클래스 | MG 런 | wall | lane 발화 (로그 레벨) |
|---|---|---|---|---|
| #929 | docs/spec 규범 — `replay_harness_config_quirks.md` 단일 파일 | `39186880938` | 698s | `EXECUTED — no record for the current closure (fresh judgment)` — lane-0+1, 4주체 전부 |
| #930 | src/config — `counterexample_replay` 수리 | `39190425325` | 697s | 동일 (lane-0) |
| #931 | Makefile/config/data/src — rust 레인 경화 | `39193523600` | 702s | 동일 (lane-0) |

- 해석: **docs/spec 규범 변경은 판정 입력(클로저)에 편입된다** — 같은 문서 클래스라도 `docs/evidence`·`data/ci_optimization`(#926–#928, REUSED 414–439s)와 행동이 갈린다. src·Makefile·config 변경도 예상대로 클로저를 무효화했다.
- EXECUTED walls 697/698/702s는 구세대 밴드 550–737s와 정합 — REUSED 밴드(401–550s)와 분리된다.
- 경계 항목의 완결 정의·관측 프로토콜·무합성 변경 원칙은 후속 문서 `docs/evidence/judgment_key_v4_boundary_watch_2026-10-19.md`가 담당한다.

### 9.3 재현 명령 (addendum 분)

```bash
# 1) #928 wall = updated_at − created_at = 439s, venue·conclusion
gh api repos/Archright/Axiom/actions/runs/39186429925 --jq '[.created_at,.updated_at,.event,.conclusion]'

# 2) 경계 후보 walls — 698/697/702s
gh api repos/Archright/Axiom/actions/runs/39186880938 --jq '[.created_at,.updated_at,.event,.conclusion]'
gh api repos/Archright/Axiom/actions/runs/39190425325 --jq '[.created_at,.updated_at,.event,.conclusion]'
gh api repos/Archright/Axiom/actions/runs/39193523600 --jq '[.created_at,.updated_at,.event,.conclusion]'

# 3) lane 로그 레벨 발화 (quirk Q3 — --allow-escape-sequences 필수, 미지정 시 빈 출력+실패)
gh api --allow-escape-sequences repos/Archright/Axiom/actions/jobs/117850066896/logs 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "REUSED — record|no record for the current closure"   # #928 lane-0
gh api --allow-escape-sequences repos/Archright/Axiom/actions/jobs/117851319021/logs 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "EXECUTED — no record"   # #929 lane-0
gh api --allow-escape-sequences repos/Archright/Axiom/actions/jobs/117851171867/logs 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep "MINT_JUDGAPPEND"          # #928 mint 멱등 no-op
```

**판정 상태 불변: INTERIM — n<5, INSUFFICIENT, 성공 선언 없음** (§6). 확정은 후속 착지 누적으로만 수행한다.

## 10. Addendum 2 (2026-10-19) — n=3→5 확정: #934(420s)·#933(404s) 표본·사전등록 ≥5 도달

> 추가 기록: 2026-10-19 (append-only — 본문 §1–9 미변경) · 관측 창 연장: 2026-10-19T02:00Z → 08:00Z
> 데이터 SSOT: `data/ci_optimization/judgment_key_v4_interim_2026-10-19.json` (본 addendum과 동시 갱신 — observedN 5, landings 5건)
> 본 §10이 **최신 판정 상태**다 — 위 §9 말미의 "INTERIM — n<5"는 §9 시점의 역사적 상태다.

### 10.1 표본 누적 — #934·#933 착지 관측 (전부 실측, 보간 0건)

§9.1이 사전등록한 "4번째 표본 = 본 addendum을 운반하는 PR(#932) 자체의 착지"는 **REUSED가 아니라 EXECUTED로 발화**했다(boundary watch §2a — MG 런 `39198659706`, wall 670s). 따라서 4번째 표본은 #932가 아니라 그 다음 착지에서 확정됐다. merge 순서로 #932 → **#934**(04:49:59Z) → **#933**(05:17:19Z) 착지에서 lane 로그 `AXIOM_JUDGMENT_CAS` 4주체 전부 **REUSED**가 관측됐다:

| 착지 | MG 런 (admission-gate, merge_group) | wall | 밴드 401–550s | vs #925 717s |
|---|---|---|---|---|
| #926 | `39134186961` | 437s | ✓ | −280s |
| #927 | `39135473401` | 414s | ✓ | −303s |
| #928 | `39186429925` | 439s | ✓ | −278s |
| **#934** | `39200840559` — success (04:42:42 → 04:49:42Z) | **420s** | ✓ | **−297s** |
| **#933** | `39203157606` — success (05:10:26 → 05:17:10Z) | **404s** | ✓ | **−313s** |

- lane 발화 원문 (#934 — lane-0 job `117893724202`, lane-1 job `117893724188`; #933 — lane-0 job `117900728443`, lane-1 job `117900728140`):
  - `AXIOM_JUDGMENT_CAS: REUSED — record a3f14dbb8cc2 re-verified (closure re-derivation + executionEpoch + per-read re-hash all passed)` (lane-0)
  - `AXIOM_JUDGMENT_CAS [proof_integrity] : REUSED — record d6dd58e95612 re-verified …` / `[d2_golden] : REUSED — record 069929f3ce7e …` / `[d2_persist] : REUSED — record 71aff5818ab4 …` (lane-1)
  - `no record for the current closure`: 양 랜딩 **0건**, `[admission-tests] SKIP — … (AXIOM_JUDGMENT_CAS basis=REUSED — record re-verified, no kernel run this attempt)` 4주체 × 2랜딩
- mint fail-closed 바인딩 통과 + 멱등 no-op: `MINT_JUDGAPPEND: OK — idempotent no-op (judgment key a3f14dbb8cc2 already stored, append exactly-once: 0)` — #934(mint-publish job `117894757915`)·#933(job `117901717439`)
- baseSha 바운드: #934 → `c0fd9af3e87d`(#932 머지 커밋), #933 → `192034c2d54d`(#934 머지 커밋) — 양 런 conclusion=success
- **원장 n: 3 → 5** — 사전등록 ≥5 도달. 성공 선언의 근거는 위 lane 로그 원문이며, 어떤 표본도 관측 없이 포함되지 않았다.

### 10.2 기록 세대 교체 — generation 1 → 2

#934/#933이 재검증한 record ID는 §1–9의 세대(eba3e79cea75…)와 **다르다** — semantic EXECUTED 시퀀스(#929–#931)가 새 판정 입력을 남겼고, #932 EXECUTED가 그 클로저의 **새 세대**(a3f14dbb8cc2 / d6dd58e95612 / 069929f3ce7e / 71aff5818ab4)를 발행했다:

- 세대 1: #925 부트스트랩 발행 → #926/#927/#928 재사용 (437/414/439s)
- 세대 2: #932 EXECUTED 발행 → #934/#933 재사용 (420/404s)
- #932 mint-publish(job `117889346354`)에서 `MINT_JUDGAPPEND: OK — judgment record appended (key c4f219f7630f, append exactly-once: 1)` 관측 — 세대 발행의 직접 흔적. 4주체 ID 각각의 mint 라인은 직접 관측되지 않았고, 세대 2의 #932 귀속은 **타임라인 기반 추정**으로 표기한다(정직 표기 — §0.9 준칙).

### 10.3 관측 요약 (REUSED 빈도 — n=5)

- **비의미 클래스 랜딩: REUSED 5/6** — #926/#927/#928/#934/#933 REUSED, #932만 전환 EXECUTED(semantic 시퀀스 직후 첫 비의미 랜딩 — 새 세대 발행 1회 경유). 비의미 랜딩이 무조건 REUSED는 아니다.
- **semantic 랜딩: 0/8 REUSED — 전부 EXECUTED(기대 부합)** — #929/#930/#931(docs/spec 규범·src·Makefile) + #935–#939(src/verification·src/core·src/cli·tests). §10.4 참조.
- post-v4 전체: REUSED 5 / 착지 15 (#925 부트스트랩 EXECUTED 포함).
- savings 5표본: 278–313s (717s 대비), 밴드 401–550s 5/5 진입, 랜딩 런 red 0.

### 10.4 경계 — #933의 정밀화와 #937/#938 후보 기각

- **#933 (REUSED, 404s)** — `src/cli/rust_lane_cli.nim` + `docs/spec/rust_certified_subset.md`·`rust_toolchain_quirks.md` + `data/nimtry_baseline.json`·`data/benchmarks/perf_latest.json` + `config/trusted_writer_set.json` 변경에도 4주체 클로저 무효화 **안 됨**. 관측된 rust-lane 경로들은 4주체 Nim 커널 클로저에 비편입이다. #929의 "docs/spec 규범 → EXECUTED"는 verification 주체 파일(`replay_harness_config_quirks.md`)에 한정됨이 정밀화됐다 — 문서 클래스 전체가 아니다.
- **#937 (EXECUTED, 713s)·#938 (EXECUTED, 733s)** — REUSED 후보 가설을 **기각**한다. #937은 `docs/spec/replay_evidence_policy.md`(verification 주체 규범) + rust 어댑터 src 변경, #938은 `src/cli/axiom_engine.nim` + `config/spec` 계약 변경을 포함한다 — 클로저 편입 입력. semantic 입력은 8/8 EXECUTED로 기대와 부합한다.
- **#935 (744s)** — 관측 원값이 구세대 밴드(550–737s) 상단을 7s 초과. 보정 없이 원값 기록.
- **#939 (966s)** — 런이 #938 MG 런(→07:30:06Z)과 병행 실행돼 대기 포함 가능성이 있으나 원값 그대로 기록(보간 없음).

### 10.5 재현 명령 (addendum 2 분)

```bash
# 1) wall·venue·conclusion — 420s(#934)/404s(#933)
gh api repos/Archright/Axiom/actions/runs/39200840559 --jq '[.created_at,.updated_at,.event,.conclusion]'
gh api repos/Archright/Axiom/actions/runs/39203157606 --jq '[.created_at,.updated_at,.event,.conclusion]'

# 2) 4주체 REUSED 마커 + record ID (세대 2 — 양 런에서 동일 4개)
gh api --allow-escape-sequences repos/Archright/Axiom/actions/jobs/117893724202/logs 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "REUSED — record|EXECUTED — no record"   # #934 lane-0
gh api --allow-escape-sequences repos/Archright/Axiom/actions/jobs/117893724188/logs 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "REUSED — record|EXECUTED — no record"   # #934 lane-1
gh api --allow-escape-sequences repos/Archright/Axiom/actions/jobs/117900728443/logs 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "REUSED — record|EXECUTED — no record"   # #933 lane-0
gh api --allow-escape-sequences repos/Archright/Axiom/actions/jobs/117900728140/logs 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "REUSED — record|EXECUTED — no record"   # #933 lane-1

# 3) mint fail-closed 바인딩·멱등 no-op (append exactly-once: 0)
gh api --allow-escape-sequences repos/Archright/Axiom/actions/jobs/117894757915/logs 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "MINT_JUDGAPPEND"   # #934 mint-publish
gh api --allow-escape-sequences repos/Archright/Axiom/actions/jobs/117901717439/logs 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "MINT_JUDGAPPEND"   # #933 mint-publish

# 4) 세대 2 발행 흔적 (#932) + semantic 확인 (#935–#939 lane 발화는 boundary watch §8 참조)
gh api --allow-escape-sequences repos/Archright/Axiom/actions/jobs/117889346354/logs 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep "MINT_JUDGAPPEND"      # #932 mint-publish — appended (exactly-once: 1)
```

**판정 상태 (§10 — 최신): 사전등록 표본 목표 n=5 도달. REUSED 빈도 — 비의미 5/6, semantic 0/8, 전체 5/15(부트스트랩 포함). 밴드 401–550s 5/5, red 0, savings 278–313s.** 관측된 경계는 클래스별 관측이 권위며 무조건 REUSED 주장으로 확대하지 않는다 (§0.12 주장 범위 유지).
