# BYO-Agent Phase 3 selftest 결함 수정 — 재생 의존성 핀·판정 기계 단언 (2026-11-03)

Phase 3 착지(PR #1225, merge `c89334b5a`) 직후 selftest의 첫 실행이 **판정 없는 green**이었음을 발견하고, 원인을 분리·수정한 기계 관측 기록. 등록: `data/debt_registry.json` DEBT#513 (Theater/Unenforced Claim).

## 1. 결함 관측 (첫 selftest run)

- run: https://github.com/Archright/Axiom/actions/runs/41469574000 — head `3f8725937` (PR #1225)
- workflow conclusion: `success` — 그러나 실측:

| 필드 | 실측값 |
|---|---|
| `ax prove` exit | `0` |
| `propositionVerdict` | `UNKNOWN` |
| `bugAttribution` | `Unknown` |
| `canonicalRunDigest` | `9b52c82a3c8adce30a9f31aa4c900a9dfb2491a85e05e6eb11c0af6b9cba7a25` |
| `runOutcome.verdict` / `gateVerdict` | `INCONCLUSIVE` / `FAIL` |

판정: selftest 헤더 주석이 "pinned fixture가 DISPROVED에 도달"을 판단 주장(judged assertion)으로 선언했지만 이를 **검증하는 step이 존재하지 않았다** — §8 exit 전이만 green 판정에 참여하고 단위 판정은 아무 비교도 하지 않음. 판정 없는 green = §0.9 극장(죽은 게이트).

## 2. 근본 원인 (UNKNOWN 판정 자체)

prove.log(artifact `byoa-evidence-byoa-phase3-selftest-proposals`):

```
[ce-replay] bvSliceLenActual — replay rvUnavailable: subject dep resolution failed:
serialization, faststreams, stew, results not found in nimble store
(searched: /home/runner/.nimble/pkgs2, /home/runner/.nimble/pkgcache)
```

인과 사슬: GitHub 러너의 nimble store가 공백 → `D2AgentSubjectDepPackages`(serialization·faststreams·stew·results, `src/verification/counterexample_replay.nim:161`) 해석 fail-closed → ce-replay `rvUnavailable` → `vsDisproved` 미달 → `disprovedNodes` 공집합 → pre-sieve(io_boundary) 분류 → `orchestrationPreSievedUnverifiable` → `UNKNOWN` → 5-state `SUCCESS`(exit 0).

로컬(Phase 2b)은 `~/.nimble`에 의존성이 존재해 `rvAgree` → `vsDisproved` → `DISPROVED`·exit 1 — 즉 **워크플로우가 로컬 개발 환경의 암묵적 상태(store에 의존성이 이미 있음)에 조용히 의존**한 것이 구조적 원인.

## 3. 오진단 교정

초기 진단 "jq 추출 경로 불일치(Summary 전부 n/a)"는 **오진단**이었다. artifact의 `ax_proof_state.json`에 대해 워크플로의 실제 표현식 `((.reportJson.display // .display).units // [])[0].propositionVerdict`을 재실행한 결과 `UNKNOWN`을 정상 반환 — Summary는 실측 판정을 충실히 표시했고, jq는 무죄다. 실제 결함은 ①재생 의존성 미프로비저닝 ②판정 단언 부재의 2건.

## 4. 수정 (PR `work/byoa-phase3-selftest-deps-fix`)

1. **재생 의존성 핀** — `byo-agent.yml` 신규 입력 `replay-dep-pins`(기본값 = 로컬 acceptance store가 해석한 4개 커밋, pkgs2 `nimblemeta` vcsRevision에서 유래):
   - status-im/nim-serialization `b5473564e80a4908cf6c5a038e4c4a6ca7de2223`
   - status-im/nim-faststreams `059bc2f52546ac14b583639c33372c14b1d46fa3`
   - status-im/nim-stew `4382b18f04b3c43c8409bfcd6b62063773b2bbaa`
   - arnetheduck/nim-results `df8113dda4c2d74d460a8fa98252b0b771bf1f27`

   체크아웃 후 `AXIOM_REPLAY_DEP_PATHS`로 엔진에 전달 — 엔진 재생 설계 (b)(verbatim 경로·store 탐색 우회·내용 결정론). 빈 값이면 엔진의 nimble store 탐색(설계 (a))이 그대로 사용된다.
2. **reusable workflow outputs** — `ax_prove_exit`·`ax_verdict`·`ax_attribution`·`ax_spec`·`ax_target`를 workflow_call outputs로 노출(호출자의 기계 단언 표면).
3. **selftest Job 3 acceptance** — exit `1` ∧ `DISPROVED` ∧ `BUG_SUSPECTED`를 기계 단언. UNKNOWN green은 워크플로 실패로 전환. `canonicalRunDigest`는 관측 기록(Summary)으로 인쇄.
4. **계약 정정** — `docs/spec/byo_agent_proposition_contract.md`: §8 exit 0 행("PROVED" → 단위 판정 PROVED 또는 UNKNOWN, 정직 노출), §9 재생 의존성 행·프로비저닝 문단, §11 A9(의존성 미해결 → UNKNOWN → 절대 PASS 아님).
5. **극장 등록** — DEBT#513 (Theater/Unenforced Claim, source theater_audit, FIXED).

## 5. d1 — 로컬 실증 (수정 착지 전, 핀 방식 검증)

worktree `aa26cef5c`(fix 베이스 — 이 PR은 engine 무변경, workflow·문서만 변경) + `/tmp/byoa-deps`에 상기 4개 핀 체크아웃 + CI fixture propositions 문서를 그대로 사용:

```
AXIOM_REPLAY_DEP_PATHS=/tmp/byoa-deps/nim-serialization:/tmp/byoa-deps/nim-faststreams:/tmp/byoa-deps/nim-stew:/tmp/byoa-deps/nim-results \
bin/ax prove --proposals <CI fixture proposals.json> --project …/nim-libp2p
→ exit 1 · DISPROVED · BUG_SUSPECTED
```

| 필드 | d1 실측 |
|---|---|
| exit | `1` |
| propositionVerdict | `DISPROVED` |
| bugAttribution | `BUG_SUSPECTED` |
| canonicalRunDigest | `294180890d20a35a46eb17a3b3d50bed8cb651f7bc581b25470532c91c44b590` |

부가 확증: d1 digest는 Phase 2b 로컬 관측(2026-11-02, 상이한 propositions 문서 — agent.id·explanation 텍스트가 다름)과 동일하다. 즉 ① 핀 체크아웃이 로컬 nimble store 해석을 **내용 동일하게** 재현했고 ② propositions 문서의 agent 메타데이터는 canonicalRunDigest 산화 대상이 아니다(digest는 실행 결과 — unit 행·판정·outcome — 의 정식 직렬화).

## 6. d2 — CI 관측 (브랜치 push run)

run https://github.com/Archright/Axiom/actions/runs/41564010583 — head `58c97cfbf` (브랜치 push 트리거, 2026-11-03T02:06Z; prove job 4m12s):

| 필드 | d2 실측 |
|---|---|
| workflow conclusion | `success` — Job 2(prove) `success` ∧ **Job 3(acceptance) `success`** |
| ax prove exit | `1` (Job 3 기계 단언: `[ "1" ]` PASS) |
| propositionVerdict | `DISPROVED` (기계 단언 PASS) |
| bugAttribution | `BUG_SUSPECTED` (기계 단언 PASS) |
| canonicalRunDigest | `294180890d20a35a46eb17a3b3d50bed8cb651f7bc581b25470532c91c44b590` |
| prove.log | `bvSliceLenActual — replay agreed; PROPOSITION_DISPROVED payload assembled (13 records)` — bytesview canonical acceptance와 동일 재생 경로 |

**d1(로컬) = d2(CI) digest 완전 일치** — 교차환경 결정론 관측 성립. `runOutcome.verdict FAIL/gateVerdict FAIL`는 DISPROVED의 정직한 회계(unsatisfiedCount=1 → exit 1)다.

## 7. 판정

- 판단 주장 3종이 기계 단언으로 전환되었고(§11 A9), 브랜치 push run이 exit 1·DISPROVED·BUG_SUSPECTED를 관측했으며, d1·d2의 canonicalRunDigest가 일치 — **수정은 종결된다** (merge 후 main workflow_dispatch 재실행 관측이 배포 상태 실증을 완성, §10 same-repo selftest).
