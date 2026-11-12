# boLtU 수직 슬라이스 착지·증거 폐쇄 — unsigned 비교의 IR 거주 의미 보존 (2026-11-02)

> **종류**: 착지 증거 폐쇄 문서 (landing evidence closure) — PR #1222
> (`feat(ir): boLtU — operator-resident unsigned strict comparison (wire ordinal 16)`)의
> 구현·검증·착지·MERGE_SHA 재현 증거를 기록한다. docs-only — 코드·게이트·핀 변경 0건.
> **규율**: 착지 관측은 GET-only(`tools/ci/landing_observe.sh`·`gh pr view`)·`gh` 네이티브
> 인증(AGENTS.md §2.4). 모든 게이트·필수검사·병합 권위는 GitHub다(Authority ≠ Adapter,
> §2.3). 본 문서는 Reporter다.
> **Date**: 2026-11-02 (UTC) · **PR**: #1222 · **브랜치**: `work/boltu-unsigned-ir-op-2026-11-02`
> · **MERGE_SHA**: `f00503d75cc27d99add0c563363390ceb3d07c23`
> · **HEAD(브랜치)**: `6ad13a8dc5e7f6287539271108f0684990114409`
> (구현 `f07bd1db6` + pin reanchor `6ad13a8dc`) · **base**: `a241012ed`

---

## §0. 판정 요약

**Terminal Outcome — VERIFICATION_COMPLETE (이 슬라이스 범위 한정)**:

> 생산자가 결정한 unsignedness가 `boLtU`(wire ordinal 16)로 IR에 거주하고, SMT
> (`bvult`)·Lean(`BitVec.ult`)·replay(unsigned 순서) 세 어댑터가 동일 의미를
> 실행하며, 잘못된 signedness 변이 3종이 즉시 검출되고, MERGE_SHA detached cold
> worktree에서 양성 인증의 **정본 identity가 동일 해시로 재생산**되었다.

**명시적 범위 한정 (과장 금지)**:
- Rust LLBC `<` 입장 지원은 확장하지 않았다 — BinaryOp는 Eq에서 폐쇄 유지,
  `Lt`/`Sub` → `rceUnsupportedGrammar` 회귀 시험 착지(§1).
- u64 덧셈·overflow 의미는 이 슬라이스가 증명한 것이 아니다 — 양성 프로브
  `u64_add`/`u64_echo`는 인증 재현성의 측정 수단이다(§4).
- **mutant 반례 CONFIRMED는 이 환경에서 성립하지 않았다** — 3개 커밋 제어 대조
  (base/브랜치/MERGE_SHA)로 mutant 판정 경로의 **회귀 부재**를 입증했고, CONFIRMED
  미성립은 boLtU 이전부터 존재하는 사전 조건이다(§3).

---

## §1. 착지 증거 (GitHub merge authority)

| 단계 | 관측 | 증거 |
|---|---|---|
| push | 원격 도달 1회 | `git push origin work/boltu-unsigned-ir-op-2026-11-02` rc=0, `* [new branch]` |
| pre-push | 13종 게이트 통과 | dry-run(2차, pin reanchor 후) rc=0 → 실제 push 훅 `[PASS] Pre-push checks passed` |
| PR | #1222 생성 | `gh pr create` rc=0 |
| pr-head 필수검사 | 5종 OK | admission-check·axiom-operational-slice·bsec-integrity·debt-registry-gate·generation-acceptance |
| merge queue | 그룹 헤드 `f00503d75` 진입 | entry AWAITING_CHECKS position 1 (14:29:28Z) |
| merge_group 8런 | admission-gate **success** 포함 전부 success | run 41462433927 (admission-gate) completed/success |
| 착지 | **MERGED** | state=MERGED ∧ mergedAt=2026-11-02T14:42:21Z ∧ mergeCommit.oid=`f00503d75…` ∧ **parents==2** ∧ graphql↔rest consistent — `landing_observe.sh` VERDICT: **TERMINAL_SUCCESS** |
| 로컬 main | fast-forward | a241012ed → f00503d75 (`git merge --ff-only origin/main`) |

MERGE 커밋 `f00503d75`의 부모: `a5cfd5bb2`(착지 시점 main — #1219·#1220·#1221 포함)
+ `6ad13a8dc`(본 슬라이스). 병합 후보에서 admission-gate가 실행·성공했다.
Rust LLBC `<`/`Sub` 거부 회귀(`tests/unit/test_llbc_to_canonical.nim` BinaryOp
`Eq`-only)는 merge_group axiom-operational-slice·admission-gate가 통과한 트리에
포함되어 착지했다.

---

## §2. 변이 검증 — 세 어댑터 signedness 변이 3종 즉시 검출 (실측)

detached worktree `/tmp/boltu_mutant_wt` @ `f07bd1db6`에서 `tests/unit/test_binop_unsigned.nim`(27 checks)로 측정:

| 변이 | 위치 | 치환 | 검출 |
|---|---|---|---|
| A — SMT | `src/verification/obligation_smt_lowering.nim:632` | `bvult` → `bvslt` | `AssertionDefect :86 "bvult" in smtOut` |
| B — replay | `src/engine/counterexample_replay.nim:349,441` | `lu < ru` → signed reinterpret | `AssertionDefect :120 rU1.get.b == true` |
| C — Lean | `src/translation/ir_to_lean.nim:104` | `BitVec.ult` → `BitVec.slt` | `AssertionDefect :101 "BitVec.ult" in leanOut` |

baseline(pristine)·post-restore 전부 27/27 PASS. `make check-mutation-harness` PASS.

**방법론 정정 (정직 기록)**: 첫 번째 배터리는 **무효**였다 — worktree에 `bin/ax`가
없어 Security Guard가 pristine 포함 전 run을 차단했고, "DETECTED"는 가짜였다.
`make build` 후 전수 재실측했다. 변이 B의 1차 시도(`:441` 변수명 오기)는 컴파일
오류일 뿐이었음도 정정 후 재측정했다(정확한 대상: `l.get.i < r.get.i`).

---

## §3. mutant 프로브 판정 — 3개 커밋 제어 대조로 회귀 부재 입증 (가설 정정 포함)

**이전 세션 가설 정정**: pre-merge 시점의 판단 "CONFIRMED는 fixture가 원격
evidence-cas에 게시된 뒤(MERGE_SHA) 가능하다"는 **기각**됐다 — MERGE_SHA cold
실행에서 ledger가 `git/blobs/76aacb07…`을 정상 fetch(transport armed)했음에도
판정은 여전히 unconfirmed였다.

**실측 — 3개 커밋 제어 대조 (Lean olean 정상 상태, 동일 명령·동일 state 구조)**:

| 커밋 | boLtU | mutant 판정 |
|---|---|---|
| `a241012ed` (base) | 없음 | `unknown (stage=kernel): … counterexample unconfirmed (cvUnresolved precedent…)` |
| `f07bd1db6` (브랜치) | 있음 | 동일 — cvUnresolved unknown |
| `f00503d75` (MERGE_SHA) | 있음 | 동일 — cvUnresolved unknown |

세 실행 모두 kernel decline은 **동일 Lean artifact**(`axiom_kc_5d3d08e7…`,
`/tmp` 콘텐츠 주소)에서 발생했다. → **mutant 판정 경로에 boLtU 회귀 없음.**

- CONFIRMED가 성립했던 유일 관측 사례(premerge_B, `replay.verdict=rvAgree`,
  subjectGitRef `9c081ed9…`)는 **다른 환경**(Axiom2 계열, 별도 fixture/주체)의
  실행이다 — 본 저장소(base 포함)에서는 재현되지 않는 조건이다.
- 원인 코드 위치: `rust_rust_pipeline.nim` 커널 기각 후 확인 경로(Z3 SAT →
  `replayConfirmedRustDisproof` 합의)의 4단계 중 무엇이든 조용히 break하면
  cvUnresolved unknown으로 fail-closed 된다(설계상 정직한 실패). 어떤 단계가
  break하는지는 본 슬라이스 범위 밖 Follow-up이다.
- **양성 프로브의 회귀 부재는 §4에서 별도 입증** — mutant unknown은 시스템의
  fail-closed 동작이지 boLtU의 결함이 아니다.

**대조 실행 방법론 정정**: 이전 세션의 base 대조(`/tmp/boltu_base_state`)는
Lean olean 미비로 extraction 단계에서 거부된 **무효 실행**이었다(상태만
unknown으로 비교됨). 본 재실행(`/tmp/boltu_base2_state`)은 Nim+Lean 완전
빌드 후 유효한 커널 단계 도달을 확인했다.

> **§3 정정 (2026-11-03, PR #1234 — rust-confirm-seal 슬라이스)**: 본 절의 미해결
> Follow-up("어떤 단계가 break하는지는 본 슬라이스 범위 밖")이 종결됐다. break
> 지점은 4단계 확인 경로가 아니라 **봉인 predicate 자체**였다 — 구현
> (`porcelainClean`)이 G2 정본의 상대 pre/post 의미("unchanged across the run",
> replay_evidence_policy.md §4)에서 이탈해 **절대적 clean 트리**를 요구했고, 사전
> 존재 노이즈(미추적 파일·스탬프 드리프트)가 있는 정상 저장소 상태에서 Z3 SAT →
> rustc replay → rvAgree 합의까지 도달한 실제 반례가 봉인에서 cvUnresolved로
> fail-closed됐다. 동일 fixture(`axiom_u64_probe`)·동일 주체·동일 명제에서
> predicate v2(`worktreeStable`, pre/post 상대 비교 4-leg) 착지 후 mutant는
> **CONFIRMED**(a=594475149730709119, b=14852871580170916868, rvAgree)로
> 판정된다 — 본 저장소에서 "재현되지 않는 조건"이 아니었음이 MERGE_SHA
> detached cold 재현으로 입증됐다. premerge_B 관측(다른 환경)이 유일한 rvAgree
> 사례였던 것은 환경 특수성이 아니라 그 환경만 사전 노이즈가 없었기 때문이다.
> 본 절의 나머지 결론(세 커밋에서 봉인 오작동이 사전 존재 — boLtU 회귀 아님)은
> 그대로 유효하다. 전 과정:
> docs/evidence/rust_confirm_seal_2026-11-03.md

---

## §4. MERGE_SHA cold acceptance — detached 재현 (실측)

`git worktree add --detach /tmp/boltu_cold_wt f00503d75…` — gh_env.txt 없는 트리,
신규 state dir(`/tmp/boltu_cold_state`). Nim `make build` rc=0, Lean `lake build`
21 jobs rc=0 후:

| 프로브 | 판정 | 인증서 |
|---|---|---|
| `axiom_u64_probe::u64_add` | **verified 1/1** | `8fd2dae5215d11192e40e753a5e917bc4c8504abfedf2328f98fa409f218fc87` — **정본 identity 해시 재생산** |
| `axiom_u64_probe::u64_echo` | **verified 1/1** | `5e7fb80989ae05e55da39c0d4efe0112e72632cc45ae520d2cf192d3f83c81a9` — **정본 identity 해시 재생산** |
| `axiom_u64_probe::u64_add_mutant` | unknown (§3) | (발급 없음 — 커널 기각) |

**인증서 재현의 정확한 의미 (과장 금지)**:
- **동일**: 파일명(콘텐츠 주소 identity)·`certificateDigest`·`propositionHash`·
  `sourceHash`·`irHash`·`leanSourceHash` — 정본 검증 콘텐츠 전부 바이트 동일.
- **상이(정상)**: `modulePath`·`claimDigest`·`journalRef`·`journalCommitId`·
  `trustCommitId`·`signature`·`evidenceId`·`identityDigest`·`kaaDigest`·
  `inputHash`·`executionContractDigest`·`canonicalKaa.executionIdentity` — 이번
  실행의 절대 경로·journal 인스턴스·서명을 결속하는 실행-바인딩 필드.
  detached worktree의 상이한 절대 경로에서 정본 identity가 불변임을 입증하는
  것이 이 재현의 요점이다.
- pre-merge 재현(동일 저장소 경로)에서는 전체 파일이 바이트 동일이었음이 이미
  확인되어 있다(이전 세션, 해시 동일).

**재현 전제 2건 (정직 기록)**:
1. scope lock은 `$AXIOM_STATE_DIR/data/verification_scope.lock` 위치여야 한다
   (루트에 두면 rust lane이 fail-closed 거부 — 실측 정정).
2. detached worktree는 git 트리만 복사하므로 Lean olean(`proofs/.lake`)이 없다 —
   `lake build` 선행 없이 프로브하면 RustReferenceExtractor가 `unknown module
   prefix 'IR'`로 거부한다(실측; Nim 빌드만으론 불충분).

**porcelain**: cold·base 양 worktree 모두 유일 변경
` M src/generated/build_metadata.json` — 문서화된 빌드 스탬프 퀴크(기존 계약,
이 슬라이스 무관). gh_env.txt는 cold 트리에 부재(확인) — 주체 트리 오염 0건.

---

## §5. 사전 결함 2건 — 문서화만, 수리하지 않음 (별도 슬라이스)

1. **`proofs/IR/AxiomIRExpr.lean` `binOpOfOrdinal` 5..11 arms**: Lean 생성자 서수를
   wire 서수로 잘못 표기한 스테일 표(ircheck-experiment 확인; production 경로
   아님 — 12(eq)·16(boLtU)은 실측 정상). 본 슬라이스는 16 arm만 추가했다.
2. **`proofs/MetaCheckIR.lean` `irexprToLeanExpr`**: 암시적 타입 인자 미전달·
   inferType 검사 부재 — 기존 `.lt`와 동일 스타일로 `.ltU`를 유지(신규 극장화
   금지; MetaCheckIR은 어댑터 감사 보조 수단).

발견 ≠ 권한(AGENTS.md §2.2): 두 건 모두 이 슬라이스 범위 밖 Follow-up이다.

---

## §6. 운영 관측 — 실제 push 1차 시도의 무음 실패 (인프라, 게이트 아님)

첫 실제 push(14:00:03→14:01:26Z, 83.6s)가 **게이트 판정 없이** 실패했다:
`git_access_scan` UNRESOLVED 표 출력 중 훅 프로세스 트리가 신호로 사망 —
`git_access_scan: PASS` 라인·make 최종 판정·`[Pre-push FAIL/PASS]` 문구 전부
부재, 커널 로그·OOM 증거 없음(메모리 20Gi 가용), 좀비 없음. 동일 스냅샷
(`~/.cache/axiom/push-admissibility/6ad13a8dc…`)에서 훅과 동일한 `make
push-admissibility` 수동 재실행 → **MAKE_RC=0, 13종 green** (게이트·콘텐츠는
결정적 PASS). dry-run(13:57:04Z, 89s)도 동일 OID PASS. 원격 도달 0회였으므로
출력을 파일 리다이렉트로 받아 재시도 1회 → rc=0 착지. **원격 도달은 총 1회**다.

---

## §7. 결론

이 슬라이스가 실제 운영으로 입증한 것: **의미의 결정은 생산자에서 1회, IR이 그
사실을 보존하며, 모든 하위 어댑터(SMT·Lean·replay)가 동일 의미를 실행하고,
변이가 즉시 검출되며, 인증의 정본 identity가 MERGE_SHA에서 재현된다.** 검증
강도는 낮추지 않았다(게이트 13종·필수검사 5종·merge queue admission-gate 전부
통과). Unsupported 영역(Rust LLBC `<`)은 여전히 fail-closed고, mutant 판정
경로의 회귀 부재는 3개 커밋 제어 대조로 입증했다.
