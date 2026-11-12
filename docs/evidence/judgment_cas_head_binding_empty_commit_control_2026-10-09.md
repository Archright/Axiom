# Judgment CAS — HEAD 바인딩 의미론 폐쇄: 빈 커밋 대조군 실측 (PR #617)

> **성격**: 반증 가능 실측 증거 — Judgment CAS closure가 **런 HEAD(커밋 OID)를 바인딩하지 않고
> 검증자 체크아웃 트리(성분 ⑤ = B^{tree})를 바인딩한다**는 예측의 제어 실험.
> **정본 계약**: `docs/spec/test_judgment_cas_contract.md` (§4 9성분) ·
> `docs/evidence/judgment_cas_reused_hit_root_cause_2026-10-09.md` (#611 HIT / #613 MISS 원인 —
> 성분 ⑤ = B^{tree}, 검증자 세대 전진만이 무효화) · phase3 증거
> `docs/evidence/test_judgment_cas_s1a_phase3_2026-10-09.md` (Evidence ①–⑩, 부정 경로 ③④⑤).
> **실험 설계**: `git commit --allow-empty`로 **런 HEAD만 이동**(트리 0바이트 불변)시켜도
> closure/key가 불변임을 (1) 로컬 정적 유도, (2) CI 라이브 사이클에서 실측한다.
> **실측 창**: 2026-10-08T23:26Z – 2026-10-09T00:4xZ (로컬 worktree 유도 + GitHub Actions REST·런 로그).
> **측정 위치**: worktree `orca/workspaces/Axiom/head-semantics-exp`, 브랜치 `test/empty-commit-control`
> → **PR #617 MERGED 2026-10-09T00:27:06Z, merge SHA `f1c207d64621ad832d4e96e28c7b4c3ffa2b8bc1`**.
> **배경 세대 주의**: 실측 창 동안 페럿이 #615(23:25:27Z)·#616(23:38:30Z)·#618(23:55:30Z)·
> #619(00:08:48Z)·#620(~00:19Z)를 연속 착지시켰다 — 세대(B^{tree})가 측정 중 전진한 사실과 그 축을
> §4 세대 지도에 함께 기록한다(관측을 부정하지 않고 정적 모델로 설명한다, §0.6).

## 1. Phase 1 — 로컬 정적 확정: 빈 커밋 전후 closure/key 불변

`bin/ax cert judgment-plan --decision` (armed: `AXIOM_JUDGMENT_CAS_ENABLED=1`,
`TESTED_TREE_OID`=`BASE_TREE_OID`=`git rev-parse HEAD^{tree}`) 을 빈 커밋 생성 전후에 동일
env·cwd로 실행:

| 상태 | HEAD (런 커밋 OID) | HEAD^{tree} (성분 ⑤) | evidenceKey (H(closure wire)) |
|---|---|---|---|
| pre | `18bb557faadc…` | `7601c375dd7f…` | `751903568adf487bda92516c6302083b657e6880f9a7fdc90ee019fde5237d80` |
| post (empty commit `09f8f2327`) | `09f8f2327d81…` | `7601c375dd7f…` (**불변**) | `751903568adf…` (**불변**) |

- plan 라인도 양쪽 동일: `AXIOM_JUDGMENT_CAS: EXECUTED — no record for the current closure (fresh judgment)`
  (로컬 env 키는 러너 env 키와 다르므로 레저 HIT이 없을 것이란 예측대로 — fail-closed EXECUTED).
- **판정**: HEAD 커밋 OID는 closure wire의 어떤 성분에도 불입되지 않는다. 트리 OID(⑤)만 바인딩.
  불변 확인 후 실험 진행(사전 조건 충족). **PASS**

## 2. Cycle 1 — PR 런(37859919931, 빈 커밋 1): 독립 런 헤드의 동일 키 수렴

PR-run **37859919931** (pull_request, head_sha `09f8f2327d81…` = 빈 커밋, 트리는 base와 동일):

| 관측 | 원문 (런 로그, 2026-10-09 발췌) |
|---|---|
| plan (23:36:53Z) | `AXIOM_JUDGMENT_CAS: EXECUTED — no record for the current closure (fresh judgment)` |
| tested tree (23:45:33Z) | `[check] AXIOM_JUDGMENT_CAS armed (tested tree 4edf0687b42c)` |
| s1a | `RUN make test-fast-one T=tests/unit/test_s1a_lean_golden.nim` (23:37:32Z) → `PASS — … (basis=EXECUTED — fresh judgment measured)` (23:42:43Z, **~311 s**) |
| 4/4 | `PASS — 4/4 GO-critical admission tests green (proof_integrity, s1a_lean_golden, d2_golden, d2_persist)` (23:45:31Z) |
| judgment mint | `MINT_JUDGAPPEND: OK — idempotent no-op (judgment key 413a30ffa7e7 already stored, append exactly-once: 0)` (23:46:56Z) |
| evidence mint | `MINT_EVAPPEND: OK — evidence record appended (key 4ef3e437e75a, append exactly-once: 1)` (23:46:54Z) |

**핵심 실측 — cross-run 동일 키 바인딩**: 본 런이 새로 실행한 s1a(커널 실측 ~311 s)가 산출한
판정 키는 **`413a30ffa7e7…`로, 74초 전(23:37:27Z) 다른 런이 레저에 append한 레코드와
bit-동일**했다. 그 런은 **#616의 merge_group 런 37859116355** (런 헤드 `10bbe6b1…` = GitHub
합성 큐 후보 커밋, tested tree `4edf0687b42c`, plan EXECUTED 23:29:22Z, s1a PASS 23:33:51Z):

- 서로 다른 이벤트(pull_request vs merge_group)·서로 다른 런 헤드 커밋(`09f8f2327` vs
  `10bbe6b1`)·서로 다른 헤드 트리인 두 런이, 동일한 검증자 세대(B^{tree} = `4edf0687b42c`)에서
  **독립적으로 동일한 closure key를 유도**했다.
- 본 런의 plan consult(23:36:53Z)가 상대의 mint(23:37:27Z)보다 74초 빨라 REUSED 스킵 대신
  정당한 fresh 실행이 일어났고, mint exactly-once 어서션(exactly-once: 0)이 두 실행을 하나의
  사실로 바인딩했다. **"런 HEAD = provenance" 가설의 직접 반증 — provenance 축은 B^{tree}. PASS**

## 3. Cycle 2 — 두 번째 빈 커밋(7bcef0930, 00:10:27Z push): PR 레인 REUSED 실측

같은 PR에 빈 커밋을 하나 더 push(런 헤드 `09f8f2327` → `7bcef0930`, 트리 불변) — synchronize
이벤트의 PR-run:

| 관측 | 원문 (런 37863398592 로그) |
|---|---|
| plan (00:16:08Z) | `AXIOM_JUDGMENT_CAS: REUSED — record 413a30ffa7e7 re-verified (closure re-derivation + executionEpoch + per-read re-hash all passed)` |
| tested tree (00:18:03Z) | `[check] AXIOM_JUDGMENT_CAS armed (tested tree 4edf0687b42c)` |
| s1a | `SKIP — tests/unit/test_s1a_lean_golden.nim (AXIOM_JUDGMENT_CAS basis=REUSED — record re-verified, no kernel run this attempt)` (00:16:31Z) — **Lean 커널 실행 0회** |

- `pull_request.base.sha`는 **PR 오픈 시점(23:31:28Z)에 동결**된다(= `ee6efd9c`, #615 직후 main)
  — 두 빈 커밋 모무(無)효와 무관하게 B^{tree}는 `4edf0687b42c`로 고정.
- **판정**: 사이클 1과 **다른 런 헤드 커밋**(`7bcef0930` ≠ `09f8f2327`)에서 plan이
  **REUSED로 열리고 s1a가 스킵(커널 0회), witness basis=REUSED** —
  "런 HEAD가 움직여도 B가 같으면 REUSED"의 직접 실측. **PASS**

## 4. Cycle 2 MG 런(37863424963) + 세대 지도

큐 진입(00:10:43Z) 시점의 병합 그룹 합성 base는 **`77203ab5`(#620 착지 세대)**였다 —
내 PR-run의 동결 base(`ee6efd9c`)와 다른, 미측정 신세대. MG-run:

| 관측 | 원문 (런 37863424963 로그) |
|---|---|
| plan (00:16:14Z) | `AXIOM_JUDGMENT_CAS: EXECUTED — no record for the current closure (fresh judgment)` |
| tested tree (00:24:54Z) | `[check] AXIOM_JUDGMENT_CAS armed (tested tree 77e403f9a022)` |
| s1a | `PASS — … (basis=EXECUTED — fresh judgment measured)` (00:22:02Z, ~322 s) · 4/4 green (00:24:49Z) |
| judgment mint | `MINT_JUDGAPPEND: OK — judgment record appended (key fe06f08d51c1, append exactly-once: 1)` (00:26:03Z) — 레저 append 동일 시각 확인 |
| evidence mint | `MINT_EVAPPEND: OK — evidence record appended (key c2c057526732, append exactly-once: 1)` (00:26:00Z) |

- MG가 REUSED가 아니라 **EXECUTED로 열린 것은 #613(root-cause §2)과 동일 축**이다:
  큐 합성 시점 사이 main이 #619(00:08:48Z)·#620(~00:19Z) 착지로 `77e403f9a022` 세대로 전진해
  있었고, 그 세대의 레코드는 부재했다 — **정당한 fail-closed 재측정**(극장 아님, 계약 방향).
- 본 MG가 민팅한 `fe06f08d51c1`(세대 `77e403f9a022`)은 **내 빈 커밋 병합 커밋 `f1c207d6`의
  트리와 동일**하다(빈 병합 — 트리 불변) → 같은 세대로 큐에 합성되는 다음 PR의 MG 런은
  본 레코드로 REUSED에 진입해야 한다(§5 검증).

### 4.1 세대 지도 — 측정 창 전체

| 런 | 이벤트 | 런 헤드 커밋 | tested tree ⑤ | plan | 판정 레코드 |
|---|---|---|---|---|---|
| 37859116355 (#616 MG) | merge_group | `10bbe6b1`(큐 후보) | `4edf0687b42c` | EXECUTED (23:29:22Z) | append `413a30ff…` (23:37:27Z) |
| 37859919931 (#617 PR-1) | pull_request | `09f8f2327`(빈 커밋) | `4edf0687b42c` | EXECUTED (23:36:53Z) | **동일 키 — append exactly-once: 0** |
| 37863398592 (#617 PR-2) | pull_request | `7bcef0930`(빈 커밋 2) | `4edf0687b42c` | **REUSED** (00:16:08Z) | 재검증 — s1a SKIP |
| 37863424963 (#617 MG) | merge_group | 큐 후보 | `77e403f9a022` | EXECUTED (00:16:14Z) | append `fe06f08d…` (00:26:03Z) |

- 세대 축(⑤)은 main 병합마다 전진 — 각 신세대 첫 측정 런은 fail-closed EXECUTED. 런 헤드 축은
  그 어떤 런에서도 키에 불입되지 않았다(빈 커밋 2건 + 큐 합성 후보 전부 같은 세대 키로 수렴).

## 5. 후속 관측 — 동일 세대 차기 큐 런: **MG 레인 REUSED 실측** + append 경합 fail-closed

내 병합 커밋 `f1c207d6`는 빈 병합이므로 tree = `77e403f9a022`. 같은 세대로 큐에 합성된
차기 PR들의 MG-run 관측 — **내 MG-run이 민팅한 `fe06f08d51c1`이 merge_group 레인에서
재검증되었다**.

### 5.1 #622 MG-run 37865330190 — **REUSED + Lean 커널 0회 (merge_group 레인)**

| 관측 | 원문 (런 37865330190 로그) |
|---|---|
| plan (00:38:32Z) | `AXIOM_JUDGMENT_CAS: REUSED — record fe06f08d51c1 re-verified (closure re-derivation + executionEpoch + per-read re-hash all passed)` |
| tested tree (00:42:04Z) | `[check] AXIOM_JUDGMENT_CAS armed (tested tree 77e403f9a022)` |
| s1a | `SKIP — tests/unit/test_s1a_lean_golden.nim (AXIOM_JUDGMENT_CAS basis=REUSED — record re-verified, no kernel run this attempt)` (00:39:11Z) — **Lean 커널 실행 0회** |

- 레코드 `fe06f08d51c1`의 민팅 런은 **본 실험의 MG-run 37863424963**(런 헤드 = 내 큐 후보
  커밋)이고, 재검증 런은 #622의 MG-run(다른 런 헤드, 다른 PR) — **merge_group 레인에서
  `basis=REUSED` + `no kernel run`의 반증 가능 형태가 실측되었다**.
- 성립 조건 자체가 본 실험의 산출물이다: 내 PR이 빈 병합이 아니었다면 #622의 큐 후보
  트리는 `77e403f9a022`와 달라져 REUSED가 아니라 fail-closed EXECUTED로 열렸을 것이다.

### 5.2 #621 MG-run 37864249747 — 키 재수렴 + append 경합 fail-closed (대조 관측)

내 병합 커밋과 같은 세대로 큐에 합성된 다음 PR(#621, 큐 base `f1c207d6`)의 MG-run 37864249747 관측:

| 관측 | 원문 (런 37864249747 로그) |
|---|---|
| plan (00:25:51Z) | `AXIOM_JUDGMENT_CAS: EXECUTED — no record for the current closure (fresh judgment)` — 내 mint(00:26:03Z)보다 **12초 빠른 consult** |
| tested tree (00:30:16Z) | `[check] AXIOM_JUDGMENT_CAS armed (tested tree 77e403f9a022)` — **내 MG와 동일 세대** (내 빈 병합이 두 후보의 트리를 일치시킨 덜) |
| s1a | `PASS — … (basis=EXECUTED — fresh judgment measured)` (00:28:48Z) — 같은 세대 3번째 독립 측정 |
| judgment mint (00:31:38Z) | `MINT_JUDGAPPEND: FAIL — judgment ledger-append failed (transport/validation) (fail-closed)` → 런 실패 |

- **키 재수렴의 반복**: 내 MG(consult 00:16:14Z)와 #621 MG(consult 00:25:51Z)는 서로 다른
  런 헤드(각자의 큐 후보 커밋)에서 **동일 세대 `77e403f9a022`의 consult**를 수행했다 —
  #621은 내 mint 12초 전 consult라 fresh 실행으로 열렸고, mint 단계에서 레저 push가
  경합/transport로 실패해 **fail-closed로 런이 실패했다**(은폐 없음 — §0.9 방향 준수).
  본 실패는 타 워크스트림 PR의 운영 이벤트로서 여기서는 관측만 기록한다(판정·수정 대상 아님).
- 이 관측은 §2·§3의 수렴 패턴(같은 세대 → 독립 런이 같은 키)을 세 번째로 반복 확인시킨다.

## 6. Acceptance (phase3 Evidence ①–⑩ 대응)

| # | 항목 | 방법 | 실측 | 판정 |
|---|---|---|---|---|
| ① | s1a 비용 | 본 사이클 런 로그 | EXECUTED 실행 시 **~311 s**(23:37:32→23:42:43Z) / ~322 s(00:16:4x→00:22:02Z) — phase3 309.2/310.0/310.5 s와 일관 | PASS |
| ② | PR/MG EXECUTED·REUSED 형태 | 런 로그 | PR EXECUTED: 37859919931(311 s) · **PR REUSED + SKIP(커널 0회): 37863398592** — 런 헤드가 다른 두 커밋, 동일 세대 키 `413a30ff` · MG EXECUTED: 37863424963(세대 전진 — §4, append `fe06f08d` exactly-once: 1) · **MG REUSED + SKIP(커널 0회): 37865330190(§5.1, 내 레코드 재검증)** · 실험 런 4건이 EXECUTED/REUSED × PR/MG 전 조합을 커버 | PASS |
| ③ | 폐쇄 1요소 변경 → 실제 실행 | `make test-fast-one T=tests/unit/test_judgment_cas.nim` (본 트리 재실행, 2026-10-09) | **85 PASS / 0 FAIL / 0 SKIP, exit 0** — `a record under a different key is not this closure's record → jExecuted`, `[d2_persist] a record under another subject's key …`, `a stale executionEpoch → jExecuted` (phase3 66 → 85로 확대) | PASS |
| ④ | 레코드 변조 → 바인딩 실패 | 동일 스위트 | `the published record binds key + payload + payloadSha256` · `a different requested key fails the binding` · `a tampered evidence file is refused (fail-closed)` PASS | PASS |
| ⑤ | 부재·손상 → 실제 실행 | 동일 스위트 | `an empty ledger → jExecuted (the s1a runs)` · `armed without a tested tree OID → jExecuted (fail-closed)` · `armed without a base tree OID → jExecuted (fail-closed)` · `[d2_persist] a tampered stored payload → jExecuted` PASS | PASS |
| ⑥ | basis 표기 | 런 로그 원문 | PR `basis=EXECUTED — fresh judgment measured` PASS 라인(37859919931) · **`basis=REUSED — record re-verified, no kernel run this attempt` SKIP 라인(37863398592)** · MG PASS 라인(37863424963) — 어휘 EXECUTED/REUSED 라이브 발화 | PASS |
| ⑦ | 트리 무변경 (대조군 순수성) | `git diff` | 실험 PR #617의 소스 diff **空**(빈 커밋 2개만) — 병합 커밋 `f1c207d6`의 트리 = 직전 main 트리 `77e403f9a022` 불변 | PASS |
| ⑧ | G7 + digest ×2 | `make verify-contract-release-e2e-full`; `bin/ax report --canonical-digest` ×2; `bin/hermetic_build --check-source-hash` | **G7 PASS**: exit 0, `G7 pass (tier=dual-verified status=not_verifiable)`, `[lean-verify] PASS — proofs/ directory builds cleanly`. **digest ×2 동일**: `784719569b11a27f80aed7f15e2322ab7e856ba4618e877748694c3a823ffe46`. **source-hash PASS**: tree=embedded=`1407641109568804913` | PASS |
| ⑨ | 부정 fixture 동일 차단 | 동일 스위트(③–⑤) | timeout FAIL 재사용 차단 계열 전부 PASS(85 PASS 중) | PASS |
| ⑩ | PR→queue→main 병합 SHA | gh api pulls/617 | **MERGED 2026-10-09T00:27:06Z, merge SHA `f1c207d64621ad832d4e96e28c7b4c3ffa2b8bc1`** — merge_group 런 3건 중 admission-gate 37863424963 success(landing-integrity 37863424365 · probe-merge-queue 37863424373 success) | PASS |

## 7. 재현 명령

```
# Phase 1 (로컬 정적 확정)
cd <worktree> && export AXIOM_JUDGMENT_CAS_ENABLED=1 T=$(git rev-parse 'HEAD^{tree}') \
  AXIOM_JUDGMENT_CAS_TESTED_TREE_OID=$T AXIOM_JUDGMENT_CAS_BASE_TREE_OID=$T \
  AXIOM_JUDGMENT_CAS_RECORD_PATH=/tmp/r.json GITHUB_TOKEN=$(gh auth token)
bin/ax cert judgment-plan --decision /tmp/d1.json   # 빈 커밋 전
git commit --allow-empty -m "control"
bin/ax cert judgment-plan --decision /tmp/d2.json   # 빈 커밋 후 — evidenceKey 불변

# 런 로그 추출 (텍스트 응답 — gh api는 escape-sequence 보호로 차단되므로 curl 사용)
TOKEN=$(gh auth token); curl -sL -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/Archright/Axiom/actions/jobs/<JOB_ID>/logs" -o job.log
grep -a "AXIOM_JUDGMENT_CAS:" job.log
grep -a "MINT_JUDGAPPEND: OK" job.log

# 레저
git fetch origin 'refs/heads/axiom/evidence-cas:refs/remotes/origin/ecas'
git log --format='%H %cI %s' origin/ecas | head -20

# acceptance
make verify-contract-release-e2e-full
bin/ax report --canonical-digest   # ×2 동일
make test-fast-one T=tests/unit/test_judgment_cas.nim
gh api repos/Archright/Axiom/actions/runs/<id>/jobs
gh api repos/Archright/Axiom/pulls/617 --jq '{mergedAt, mergeCommit: .mergeCommit.oid}'
```
