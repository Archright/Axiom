# s1a test-judgment CAS — Phase 3 Completion Evidence (PR #606)

> Vertical Slice 실행 증거 — **SL-18 s1a test-judgment CAS** (9성분 closure + witness
> 바인딩 + SL-18 원자 쌍)의 병합 후 완료 증거. 정본: `docs/spec/test_judgment_cas_contract.md`
> (§4 9성분, §5 REUSED 5조건, §7 non-signature) · body PR **#606**(merge `79ac7bb4d6e1bcfb6924c67d77b3a9947fcb4bdf`).
> 실측: 2026-10-08 14:49–15:13Z (GitHub Actions REST·런 로그) + 2026-10-09 로컬 (병합 트리 `79ac7bb4d`)
> + **핀 회전 후 라이브 사이클 2026-10-08 16:48–17:18Z(#611: PR-run 37811664465 · MG-run 37813905412)**.
> 측정 위치: worktree `orca/workspaces/Axiom/judgment-cas-s1a`, 브랜치 `docs/judgment-cas-phase3-evidence`.

## 1. Completion Evidence 1–10

| # | 항목 | 방법 | 실측 | 판정 |
|---|---|---|---|---|
| ① | s1a 비용 | #604 기록 재사용 (재관측 없음) | **309.2 / 310.0 s** (PR 런 per-run 실측, #606 body에 인용). 참고: 본 사이클 PR-run 177.2 s · MG-run 232.1 s (warm cache 변동) | PASS |
| ② | 정상 PR→MG: PR EXECUTED+append / MG REUSED | 런 로그 관찰 — 구세대(37794843057/37796749342: 핀 `8e165cb16` 고정 → plan 미실행, fail-closed EXECUTED 유지, §3) 이후 **핀 회전 후 라이브 사이클(#611): PR-run 37811664465 · MG-run 37813905412**. PR: plan `AXIOM_JUDGMENT_CAS: EXECUTED — no record for the current closure (fresh judgment)` → s1a **fresh 실행 310.5 s**(16:54:42→16:59:53Z) + `MINT_JUDGAPPEND: OK — judgment record appended (key b5b10096965b, append exactly-once: 1)`(`MINT_JUDGAPPEND_COUNT=1`) + SL-15 `MINT_EVAPPEND: OK — evidence record appended (key a039db6461fe, append exactly-once: 1)`. MG: plan `AXIOM_JUDGMENT_CAS: REUSED — record b5b10096965b re-verified (closure re-derivation + executionEpoch + per-read re-hash all passed)` → `[admission-tests] SKIP — tests/unit/test_s1a_lean_golden.nim (AXIOM_JUDGMENT_CAS basis=REUSED — record re-verified, no kernel run this attempt)` + s1a `RUN make test-fast-one` **0건**(Lean 커널 실행 0회) + 4/4 요약 `s1a_lean_golden [basis=REUSED — no run]` + `MINT_JUDGAPPEND: OK — idempotent no-op (judgment key b5b10096965b already stored, append exactly-once: 0)`(`MINT_JUDGAPPEND_COUNT=0`). attest 동일 job 9m40s(PR)→4m35s(MG). 양 런 verdict `mergeGo`. append exactly-once 1↔0 라이브 실증 | **PASS** |
| ③ | 폐쇄 1요소 변경 ×4(fixture/HEAD/recipe/env) → 실제 실행 | `make test-fast-one T=tests/unit/test_judgment_cas.nim` (병합 트리) | **66 PASS / 0 FAIL / 0 SKIP, exit 0, 10m18s** — fixture·HEAD(tree)·recipe·env 각 변경 시 REUSED 거절 → EXECUTED 전환 케이스 전부 PASS | PASS |
| ④ | 레코드 변조 → 바인딩 실패 | 동일 스위트 | 변조 레코드(payloadSha256 불일치·키/바이트 비바인딩) → 바인딩 실패 판정 PASS | PASS |
| ⑤ | 부재·손상 → 실제 실행 | 동일 스위트 | `an empty ledger → jExecuted (the s1a runs)` · `armed without a tested tree OID → jExecuted` · `armed without a record path → jExecuted` — 부재/손상 시 항상 실행(fail-closed) PASS | PASS |
| ⑥ | basis 표기 | 소스 검증 + 스위트 | `admission-check.yml:823` `SKIP — $t (AXIOM_JUDGMENT_CAS basis=REUSED — record re-verified, no kernel run this attempt)` · `:832` `PASS — $t (basis=EXECUTED — fresh judgment measured)` · `certificate-mint.yml:1754` `.semantic.judgment.basis` 소비. 스위트에서 basis 어휘(REUSED/EXECUTED/jExecuted fail-closed) 전부 검증. **CI 발화 실측(②의 신세대 사이클)**: PR-run 37811664465에서 `basis=EXECUTED` PASS 라인, MG-run 37813905412에서 `basis=REUSED` SKIP 라인 원문 발화 확인 | PASS (소스+로컬+CI 발화) |
| ⑦ | 기존 3종 GO-critical 무변경 | `git diff 9d36342a0..79ac7bb4d -- <3종>` | `proof_integrity_test.nim`·`test_d2_golden.nim`·`test_d2_persist.nim` **빈 diff**. `attestation_witness.nim` = 순수 추가형(옵션 `judgment` 파라미터 — 비무장 시 레거시 바이트 동일, E-A golden 보존). CI에서 4종 모두 양쪽 런 PASS | PASS |
| ⑧ | G7 + digest×2 | `make verify-contract-release-e2e-full`; `bin/ax report --canonical-digest` ×2 (hermetic 재빌드 후, `bin/hermetic_build --check-source-hash` PASS: tree=embedded=`-4926154942036098296`) | **G7 PASS**: exit 0, `G7 pass (tier=z3-verified status=not_verifiable)`, `[lean-verify] PASS — proofs/ directory builds cleanly`. **digest×2 동일**: `2f29650667f609e5b1145cab2a0eef7db45ee6046a8273a2805b3f1e0931c20a` | PASS |
| ⑨ | 부정 fixture 동일 차단 | 동일 스위트 | `a non-accept verdict is rejected (timeout FAIL is never reusable)` 등 부정 판정 재사용 차단 PASS | PASS |
| ⑩ | PR→queue→main 병합 SHA | `gh pr view 606` + runs API | **MERGED 2026-10-08T15:11:16Z, merge SHA `79ac7bb4d6e1bcfb6924c67d77b3a9947fcb4bdf`** — merge_group 런 3건 전부 success: admission-gate 37796749342 · landing-integrity 37796748416 · probe-merge-queue 37796748541 (head_sha 모두 `79ac7bb4d`) | PASS |

## 2. GO-critical 4종 벽시간 (런 로그 스텝 타이밍)

| 테스트 | PR-run (37794843057) | MG-run (37796749342) |
|---|---|---|
| proof_integrity_test | 29.3 s | 31.0 s |
| test_s1a_lean_golden | **177.2 s** (커널 실측) | **232.1 s** (커널 실측) |
| test_d2_golden | 91.2 s | 111.0 s |
| test_d2_persist | 16.2 s | 18.5 s |

두 런 모두 s1a가 커널을 실제 실행(REUSED skip 없음) — ②의 관측과 일치.

**핀 회전 후 라이브 사이클(#611, 신세대)**: PR-run 37811664465 s1a **310.5 s**(`basis=EXECUTED` — fresh
judgment) · MG-run 37813905412 s1a **스킵**(`basis=REUSED` — no kernel run this attempt; attest 동일 job
9m40s → 4m35s). ②의 PASS 근거.

## 3. 세대 전환 잔여(§2.5 CI Self-Bootstrap)

- **원인**: GitHub required workflow `admission-gate.yml`는 저장소 refs 밖(org 관리)에 존재하며
  `referenced_workflows`가 `Archright/Axiom/.github/workflows/{admission-check,runner-pool-acceptance,certificate-mint}.yml@8e165cb166a2d29be18965642c530642d8525040`(#587 병합)로 고정.
- **효과**: 본 PR이 착지한 Judgment CAS plan/loop/mint 마커(`basis=REUSED/EXECUTED`, `MINT_JUDGAPPEND_COUNT`)는
  required workflow 핀이 본 PR 이후 커밋으로 전환되는 **다음 일관 세대(coherent generation)** 부터 라이브가 된다.
  전환 전까지 라이브 경계는 구세대로서 fail-closed(EXECUTED)를 유지 — in-place 혼합 없음(§2.5 불변식 준수).
- **조치 필요**: org required workflow 핀 갱신(관리자 권한) — 본 문서 착지 후 별도 결정.

### 3.1 핀 회전(세대 전환) 착지 — 2026-10-09

- **메커니즘**: org `Archright/.github`의 ruleset `pin-promotion-gate-required`(2026-10-08 활성,
  required check `pin-promotion-gate (DEBT#473)`, bypass 없음) 하에서 핀 회전의 유일한 정합 경로는
  dependabot 회전이다 — `pin-promotion-gate.yml`이 비-dependabot 배우자의 핀 변경을 fail-closed로
  판정하고(Axiom 읽기 토큰이 dependabot PR에만 노출), 직접 push는 ruleset에 의해 거부된다(실측).
- **실행**: 기존 dependabot PR **#74**(admission-check)·**#75**(runner-pool-acceptance)·
  **#76**(certificate-mint)에 `@dependabot recreate` → 기존 대상 `d7d81e0f`(#606 이전 세대 —
  기존 green 체크는 promotion 이전 평가로, 병합 시 DEBT#473 "신규 핀 + 구세대 내용" 창)을
  폐기하고 Axiom main tip **`347c1fc0d`** 로 재해석 → 3 PR 병합으로 일관 세대 전환(§2.5).
- **정합 근거**: 핀 커밋 `347c1fc0d`에서 `admission-check.yml` blob
  `ba827508f3ff7df4048703c54665532fa02e7394` == `config/policy/epoch_manifest.json`
  `productionExecutionPin` == `config/trusted_writer_set.json` `trustedAdmissionWorkflowSha`
  (PREPARED·PINNED 상태 정합 — gate가 콘텐츠 어드레싱으로 재검증).
- **첫 라이브 사이클 실측(#611, 2026-10-08T16:48–17:18Z)**: 최초 PR-run `37810474390`은 핀 머지
  이전 트리거로 구세대 확정(plan 스텝 부재) → 명시 취소하고 close+reopen으로 재트리거.
  PR-run **`37811664465`** s1a **EXECUTED 310.5 s** + judgment append exactly-once:1(`MINT_JUDGAPPEND_COUNT=1`)
  · MG-run **`37813905412`** s1a **REUSED**(record `b5b10096965b` 재검증, Lean 커널 0회) + append
  no-op:0(`MINT_JUDGAPPEND_COUNT=0`) — §1 ② PASS 전환 근거. #611 병합 `68570482930010d810d4ce6c60fd75d0cfc3f9cf`
  — GitHub merged_at 권위값 **2026-10-08T17:16:48Z**(pulls API, §2.3), merge_group 런 3건
  success(admission-gate `37813905412` · landing-integrity `37813904629`(17:07:13Z) · probe-merge-queue `37813904899`(17:06:06Z)).

## 4. 재현 명령

```
gh api repos/Archright/Axiom/actions/runs?head_sha=79ac7bb4d6e1bcfb6924c67d77b3a9947fcb4bdf
gh run view 37796749342 --log            # MG 런 (SL-15 HIT 라인)
make test-fast-one T=tests/unit/test_judgment_cas.nim   # 66 PASS / 0 FAIL
git diff 9d36342a0..79ac7bb4d -- tests/unit/proof_integrity_test.nim tests/unit/test_d2_golden.nim tests/unit/test_d2_persist.nim
make build && bin/hermetic_build --check-source-hash
make verify-contract-release-e2e-full     # G7
bin/ax report --canonical-digest          # ×2 동일
gh api repos/Archright/Axiom/actions/runs/37813905412/jobs   # MG 런(REUSED 사이클) jobs
gh api -H "Accept: application/vnd.github.raw" repos/Archright/.github/contents/.github/workflows/admission-gate.yml   # 핀 = 347c1fc0d (신세대)
```

## 5. 라이브 실측 완료 — 2026-10-09 마감 (로그 원문 발췌)

런 로그는 zip 리다이렉트로만 제공된다 — `gh api repos/Archright/Axiom/actions/runs/<id>/logs > run.zip && unzip` 후 grep.
이전 시도의 빈 결과는 로그 부재가 아니라 추출 형식 문제였고, 본 절의 모든 라인은 2026-10-09
에이전트가 런 로그 zip에서 발췌한 기계 관측 원문이다.

| 관측 | PR-run 37811664465 (pull_request) | MG-run 37813905412 (merge_group) |
|---|---|---|
| plan | `AXIOM_JUDGMENT_CAS: EXECUTED — no record for the current closure (fresh judgment)` (16:54:05.476Z) | `AXIOM_JUDGMENT_CAS: REUSED — record b5b10096965b re-verified (closure re-derivation + executionEpoch + per-read re-hash all passed)` (17:10:44.454Z) |
| s1a 커널 | `[admission-tests] RUN make test-fast-one T=tests/unit/test_s1a_lean_golden.nim` (16:54:42.854Z) → `[admission-tests] PASS — tests/unit/test_s1a_lean_golden.nim (basis=EXECUTED — fresh judgment measured)` (16:59:53.354Z, **310.5 s 실측**) | `[admission-tests] SKIP — tests/unit/test_s1a_lean_golden.nim (AXIOM_JUDGMENT_CAS basis=REUSED — record re-verified, no kernel run this attempt)` (17:11:22.364Z) — s1a `RUN` 0건 = **Lean 커널 실행 0회** |
| 4/4 요약 | `(proof_integrity, s1a_lean_golden, d2_golden, d2_persist)` (17:02:39.912Z) | `(proof_integrity, s1a_lean_golden [basis=REUSED — no run], d2_golden, d2_persist)` (17:14:09.625Z) |
| judgment CAS | `MINT_JUDGAPPEND: OK — judgment record appended (key b5b10096965b, append exactly-once: 1)` / `MINT_JUDGAPPEND_COUNT=1` (17:04:03.398Z) | `MINT_JUDGAPPEND: OK — idempotent no-op (judgment key b5b10096965b already stored, append exactly-once: 0)` / `MINT_JUDGAPPEND_COUNT=0` (17:15:39.936Z) |
| evidence CAS | `MINT_EVAPPEND: OK — evidence record appended (key a039db6461fe, append exactly-once: 1)` (17:03:58.245Z) | `MINT_EVAPPEND: OK — idempotent no-op (evidence key a039db6461fe already stored, append exactly-once: 0)` (17:15:37.399Z) |
| verdict | `mergeGo (GO)` (17:04:34Z) | `mergeGo (GO)` (17:16:11Z — 병합 37초 전) |
| attest job | admission-check 16:53:11→17:02:51Z (**9m40s**) | admission-check 17:09:47→17:14:22Z (**4m35s**) |

- 동일 판정 키 `b5b10096965b`·증거 키 `a039db6461fe`: PR 런 append(exactly-once: 1) → MG 런
  idempotent no-op(exactly-once: 0) — **§1 ② PASS 전환의 기계 관측 근거**.
- 병합 체인: MG-run admission green(17:14:22Z) → verdict `mergeGo`(17:16:11Z) → GitHub 병합
  (merged_at **17:16:48Z**). merge commit `68570482930010d810d4ce6c60fd75d0cfc3f9cf`는
  merge-queue가 17:05:28Z에 합성한 후보 커밋으로, 3개 merge_group 런의 head_sha이기도 하다.
- **비고(관측 소재)**: probe-merge-queue 런 `37813904899`에는 Judgment CAS 스텝이 없다
  (`probe-judge` job skipped — payload 덤프 전용 probe) — Judgment CAS 관측의 유일한 소재는
  admission-gate 런이다(§2.3 Authority ≠ Adapter — 런 ID만으로 관측 소재를 추단하지 않는다).
