# Rust 반례 CONFIRMED 판정 경로 복구 — G2 worktree 봉인 v2 착지·증거 폐쇄 (2026-11-03)

> **종류**: 착지 증거 폐쇄 문서 (landing evidence closure) — PR #1234
> (`fix(rust-lane): G2 worktree seal v2 — pre/post relative predicate
> (worktreeStable) restores counterexample CONFIRMED (boltu §3 root cause)`)
> 의 구현·검증·착지·MERGE_SHA 재현 증거를 기록한다. docs-only — 코드·게이트·핀 변경 0건.
> **규율**: 착지 관측은 GET-only(`tools/ci/landing_observe.sh`·`gh pr view`)·`gh` 네이티브
> 인증(AGENTS.md §2.4). 모든 게이트·필수검사·병합 권위는 GitHub다(Authority ≠ Adapter,
> §2.3). 본 문서는 Reporter다.
> **Date**: 2026-11-03 (UTC) · **PR**: #1234 · **브랜치**: `work/rust-confirm-seal-2026-11-03`
> · **MERGE_SHA**: `171c4906867301930d8f63a1706e35b67742d619`
> · **HEAD(브랜치)**: `e489850d5` (구현 `5f8ca6767` + pin reanchor `e489850d5`)
> · **base**: `a21558428` (main @ PR 생성 시점)

---

## §1. Ultimate Purpose — 판정은 환경이 아니라 검증 입력의 함수

Z3가 찾은 반례 후보가 rustc replay로 확정될 때, 판정이 무관한 환경 상태(빌드 스탬프·
미추적 파일)가 아니라 **검증 입력(주체 identity·명제·고정 툴체인)의 함수**가 되도록
Rust 반례 CONFIRMED 판정 경로를 실제 운영 상태로 복구한다.

**무결성 원칙 (3항, 슬라이스 계약)**:
1. 검증 시작 전부터 존재한 환경 잡음은 판정의 원인이 되지 않는다.
2. 검증 도중 검증 대상·유효 입력이 변경되면 판정을 확정하지 않는다.
3. 판정은 환경의 청결도가 아니라 검증 입력과 증거의 무결성으로 결정된다.

## §2. 근본 원인 — boltu §3 가설 종결

boltu 슬라이스(docs/evidence/boltu_unsigned_ir_op_observation_2026-11-02.md §3)는
`axiom_u64_probe::u64_add_mutant`가 세 기준 커밋에서 모두 `cvUnresolved unknown`으로
fail-closed되며 "확인 경로 4단계 중 무엇이 조용히 break하는지는 Follow-up"이라고
기록했다. 본 슬라이스가 확정한 원인:

- break 지점은 4단계 확인 경로가 아니라 **봉인 predicate 자체**였다.
- 구현(`porcelainClean`)이 G2 정본(`docs/spec/replay_evidence_policy.md` §4 —
  "unchanged across the run", "the observation must be of the subject as hashed")의
  **상대 pre/post 의미**에서 이탈해, confirm 시점의 **절대적 clean 트리**를 요구했다.
- 사전 존재 노이즈(미추적 파일 `gh_env.txt`, 빌드 스탬프 드리프트)가 있는 정상 저장소
  상태에서 봉인이 항상 깨졌고, Z3 SAT → rustc replay → rvAgree 합의까지 도달한
  실제 반례가 봉인에서 `cvUnresolved`로 fail-closed됐다.
- 즉 **구현이 계약에서 이탈**한 것이었다 — 본 슬라이스는 새 정책을 만든 것이 아니라
  구현을 계약으로 복귀시켰다 (G2 조건 수 불변, 경로 면제 0건).

## §3. 봉인 predicate v2 (Trust Fact — 착지된 계약)

```
worktreeStable ⟺
  (a) moduleSha256(pre) == moduleSha256AfterRun                  [주체 모듈 콘텐츠]
  (b) subjectInputsDigest(pre) == subjectInputsDigest(post)      [신규 — ① 마감:
      주체 크레이트 루트(모듈에서 Cargo.toml 상향, repoRoot 경계, 실패 시 모듈 부모)의
      `git ls-files --full-name --cached --others --exclude-standard` 열거 →
      (relpath 정렬, 파일별 sha256) 전체 해시]
  (c) repoStatus(pre) == repoStatus(post)                        [`git status --porcelain --untracked-files=all`]
  (d) repoTrackedDigest(pre) == repoTrackedDigest(post)          [`git diff HEAD --no-color --no-renames --no-ext-diff`]
```

- 사전 노이즈는 모든 leg의 **양변에 동일하게 존재** → 봉인을 깨지 않는다 (원칙 1).
- 실행이 만든 drift는 정확히 **한 변**을 움직인다 (원칙 2). 무시하는 경로는 0개.
- (b)는 `git status`(미추적 경로만)·`git diff HEAD`(미추적 콘텐츠 제외)가 관측할 수
  없던 **미추적 파일 내용 전용 변경** 갭을 마감한다 — N1b 음성 대조의 핵심 증명.
- 개명: `porcelainClean` → `worktreeStable` (레코드 필드·payload 폴드
  `replay.worktreeStable=`·테스트·규범 문서 4종 전수). 코드 소비자 0, quartet g4는
  `replay.*` 라인 전체 계수라 개명 무영향(axiom_engine.nim:2675-2687 직독 확인).
- confirmStep 비-agree 분기가 replay diagnostics를 reason에 노출한다 (관측화만 —
  분류·exit·상태기계 불변, cvUnresolved fail-closed 폴드 유지).

## §4. 사전 착지 검증 (구현 슬라이스 — 전부 실측)

| 검증 | 결과 |
|---|---|
| `make build` · `lake build` | rc=0 · 21 jobs rc=0 |
| 유닛 | rust_replay_adapter 37 OK · counterexample_replay 31 OK · three-cases 10 OK |
| drift (N1a/N1b/대조군) | 3/3 — N1b는 (b)만 검출하는 갭의 직접 증명 |
| 게이트웨이 수용 | [OK] 25 / [FAILED] 0, GATEWAY_EXIT=0 (mutant CONFIRMED ×3 exit 1, 노이즈 케이스 포함) |
| `make test-fast` | EXIT=0 — 유닛 47 green, debt validation 1532/1532 PASS |
| `make test` | EXIT=0 — 컨트랙트 파이프라인 E2E [OK], perf **[PERF OK] −16.2%** |
| `bin/debt_engine --validate` | exit 0, 6 PASS / 0 DRIFT (nimtry 4261 재앵커) |
| 변이 검증 | 봉인 3개 비교 leg 동시 sabotage → N1a/N1b FAIL 라인 확보 (mutation killed), 무drift 대조군 OK |

**DEBT#505 재앵커**: predicate v2가 DEBT#505 앵커(두 리플레이 함수 본문 contentHash)와
nimtry dry-duplicates 베이스라인을 깸 → 문서화된 컨벤션(커밋 `90604006e`) 그대로
`bin/nimtry src/ --update-baseline`(4263→4261) + `bin/debt_engine --regen-arch`(2건) +
`bin/debt_integrity_gate --update-baseline` + 원장 `--sync-budget` 수행. `.txt` 언어밴
1건은 재앵커 이후 착지한 `174bbc7d0`의 HEAD 드리프트(본 변경 아님) — 선례와 동일하게
함께 앵커.

**Premerge 관측 (P1, 수용 기준 ①)**: 사전 노이즈(`?? gh_env.txt` + 수정 트리 20파일)
존재 상태에서 `axiom_u64_probe::u64_add_mutant` →
`failed (stage=kernel): spec declined by kernel; counterexample CONFIRMED:
input.a=594475149730709119, input.b=14852871580170916868,
propertyViolated=(= result (bvadd a b)), replay.verdict=rvAgree, replay.exitCode=0,
replay.worktreeStable=true` + subjectInputs/repoFootprint pre==post — exit 1.
실행 후 `git status` 바이트 동일 (주체 불변).
양성 프로브 인증서 콘텐츠 주소가 MERGE_SHA 선례(boltu §4)와 바이트 동일
(`8fd2dae5…`, `5e7fb809…`) — 어댑터 변경이 검증 콘텐츠 정본성을 흔들지 않음.

## §5. 착지 관측 (GitHub authority — GET-only)

- pre-push: dry-run 1차 rotation pin 미앵커로 **정상 fail-closed** →
  `bin/reanchor_pin --ref 5f8ca6767… --write` → 커밋 `e489850d5` → dry-run 2차
  게이트 14종 green → **실제 push 1회**.
- PR-head 필수 5종(ruleset#20303214): admission-check·bsec-integrity·
  debt-registry-gate·generation-acceptance·axiom-operational-slice 전부 pass
  (axiom-operational-slice 8m22s).
- merge queue(position 1) — merge_group 8종(admission-gate run 41582451140·
  axiom-operational-slice·bsec-integrity·debt-registry-gate·generation-acceptance·
  landing-integrity·observer-manifest-consistency·probe-merge-queue) 전부 **success**.
- `tools/ci/landing_observe.sh 1234` 최종 판정: **VERDICT: TERMINAL_SUCCESS** —
  state=MERGED ∧ mergedAt=2026-11-03T05:23:01Z ∧
  mergeCommit.oid=171c4906867301930d8f63a1706e35b67742d619 ∧ parents==2 ∧
  graphql↔rest 일치.
- (관측 규율 준수 기록: 중간 2회 REST rate limit 403으로 VERDICT: UNKNOWN fail-closed —
  리셋 후 규약대로 새 단일 관측 패스로 종결. 관측 차단이 착지를 지연시키지는 않았다 —
  병합 권위는 GitHub다.)

## §6. MERGE_SHA cold acceptance — detached 재현 (실측)

`git worktree add --detach /tmp/rust_confirm_cold_wt 171c49068…` — clean 트리에서
Nim `make build` rc=0, Lean `lake build` 21 jobs rc=0 후:

| 관측 | 결과 |
|---|---|
| **① 스탬프 dirty 사전 노이즈 양성** | `make build`가 남긴 `M src/generated/build_metadata.json` 존재 상태(스탬프 복원 없이)에서 `u64_add_mutant` → **`failed: counterexample CONFIRMED: input.a=594475149730709119, input.b=14852871580170916868, replay.verdict=rvAgree, replay.worktreeStable=true`** + subjectInputs/repoFootprint pre==post — exit 1. `replay.subjectGitRef=171c4906867301930d8f63a1706e35b67742d619` — 판정이 MERGE_SHA 자체에 결속됐다. |
| **② 양성 인증서 재현** | `u64_add` → `8fd2dae5…` · `u64_echo` → `5e7fb809…` — 콘텐츠 주소(파일명)가 boltu MERGE_SHA(11-02)·premerge(본 슬라이스 착지 전)·MERGE_SHA `171c49068` cold(착지 후) 3세대 바이트 동일. 내부 해시(`propositionHash` 671fbfbf…/8bea5e96…, `sourceHash` 9f208917…, `irHash`, `leanSourceHash` 60f38e61…/a5150f0d…) 전부 premerge 기준점과 동일. |
| **③ clean 상태 동일 판정** | 스탬프 복원(`git checkout --`) 후에도 동일 CONFIRMED (동일 a/b·rvAgree·worktreeStable=true). **핵심 관측**: noisy 실행과 clean 실행의 `repoFootprint` **값**은 상이(525fd95b… vs b34c2f49…)하나 각 실행 내 pre==post가 유지되고 판정은 동일 — 봉인이 상대적이며 판정이 환경 상태에 **불변**임을 입증한다. |
| **②′ drift 음성 대조 (MERGE_SHA 재현)** | standalone `nim c -d:release -r tests/gateway/rust_drift_probe_test.nim` → **3/3 [OK]**: N1a(run-made file creation — rvUnavailable + pinned drift diagnostic + worktreeStable==false)·N1b(content-only untracked overwrite — (b) digest가 검출, porcelain 판독이 볼 수 없던 갭)·대조군(pure subject → rvAgree + worktreeStable==true). DRIFT_EXIT=0. |
| **정직한 fail-closed 관측** | cold 첫 시도(Lean `lake build` 선행 전)는 extraction 단계에서 `unknown module prefix 'IR'`로 기각 — `unknown` 판정·위조 통과 없음. boltu §4의 "무효 실행" 교훈과 동일: 유효 대조는 Nim+Lean 완전 빌드 후. |
| 실행 후 트리 | prove 3종 실행 후 `git status` 변화 없음(주체 불변 — 각 실행이 스스로 만든 drift 0건) |

## §7. boltu §3 정정

본 슬라이스는 boltu §3("mutant 프로브 판정 — 3개 커밋 제어 대조로 회귀 부재 입증")의
미해결 Follow-up을 종결한다. `docs/evidence/boltu_unsigned_ir_op_observation_2026-11-02.md`
§3에 정정 주석을 추가했다 (본 PR의 파일 변경):

- **break 지점 재판정**: "확인 경로 4단계 중 무엇이든 조용히 break" 가설 → 실제
  원인은 **봉인 predicate 자체** (절대 clean 요구로의 구현 이탈). 확인 경로의
  4단계는 모두 정상 동작했다.
- **"본 저장소에서 재현되지 않는 조건" 기각**: 동일 fixture·주체·명제에서
  predicate v2 착지 후 MERGE_SHA cold 실행이 CONFIRMED로 재현. premerge_B(다른
  환경)가 유일한 rvAgree 관측이었던 것은 환경 특수성이 아니라 그 환경만 사전
  노이즈가 없었기 때문이다.
- **boLtU 회귀 부재 결론은 그대로 유효** — 세 커밋 대조가 입증한 것(봉인 오작동이
  base부터 존재한 사전 조건, boLtU가 만든 결함 아님)은 본 슬라이스의 근본 원인
  분석과 정확히 일치한다.

## §8. 범위 밖 (명시적 — 유보 목록)

판정 정책 완화(봉인 fail-closed·rroPanicked 비확정 불변) / 새 증명 체계 /
binOpOfOrdinal 5~11 / MetaCheckIR 타입 인자 / containsU64Lit 통합 / Ref·Adt /
serde_json C1~C8 / CI 최적화 / Aeneas / 빌드 스탬프 tracked-밖 이동(독립 슬라이스) /
rustc dep-info 전체 입력 클로저(본 슬라이스는 주체 루트 다이제스트로 경계 명시) /
DEBT#505 레지스트리 엔트리 contentHash 갱신(선례: 재앵커 커밋은 레지스트리 소유
계층 미수정 — 후속 슬라이스) / rust 레인 게이트웨이 테스트의 CI 샤드 등록(기존
rust 레인 테스트 4종 모두 로컬 수용 증거 관례 — 본 슬라이스도 동일 관례 준수,
기계 검증은 MERGE_SHA cold acceptance가 담당).
