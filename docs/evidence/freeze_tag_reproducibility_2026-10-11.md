# freeze 태그 재현성 — 판정 기록 (2026-10-11)

## 문제

`tests/ci/test_admission_venue_split.nim` · `tests/ci/test_s5_build_skip.nim`는
`git show ci-frozen-2026-10-09-venue-split:<file>` 결과를 `doAssert code == 0`로
묶는다. freeze 태그가 없는 클론에서는 이 git 호출이 exit 128
(`fatal: invalid object name`)로 실패하고 테스트가 hard-FAIL한다.

실측(2026-10-11): 로컬 `ci-frozen-*` 태그 7개 중 origin에는
`ci-frozen-2026-09` 1개만 존재(`git ls-remote --tags origin`). 6개 미푸시 태그의
대상 커밋은 전원 `origin/main` 히스토리에 도달 가능하다(새 객체 없음).

## 선택지 평가

| 선택지 | 판정 | 근거 |
|---|---|---|
| (a) 태그 push | **이론상 최선이나 실측 차단** | 태그 대상이 전원 origin/main 도달 → push 시 일반 클론이 자동 수신(git-scm git-fetch: "By default, any tag that points into the histories being fetched is also fetched"). 그러나 아래 "push 실측" — 6개 전원 push-admissibility 게이트 fail-closed. 게이트 개정은 CI 경계 변경(AGENTS.md §2.5 epoch cutover, 인간 권한 선행)이라 본 작업 범위 밖. `--no-verify`·server API 우회는 §0.9/§4 위반으로 불가 |
| (b) 로컬 태그 + 소리 있는 skip | **채택** | 태그가 있으면 기존 단정 100% 무변경 실행. 없으면 unittest `skip()`으로 `[SKIPPED]` + 사유·복구 명령 출력 — 조용한 통과(극장)가 아니라 결정적 강등. frozen 상태 중복 없음, 태그 SSOT 보존 |
| (c) frozen 원문 벤더 fixture | 기각 | frozen 상태의 복제 = 중복 의미 상태 금지(AGENTS.md §1) 위반 + freeze마다 fixture 회전 부담. 태그 blob과의 정합 단정은 다시 태그를 요구(순환) |
| (d) 현상 유지 | 기각 | 태그 없는 모든 클론에서 hard-FAIL 지속 — 재현성 문제 방치 |

## push 실측 (2026-10-11, 전원 fail-closed — 우회 없음)

| 태그 | 게이트 결과 |
|---|---|
| `ci-frozen-2026-10-09-venue-split` | epoch_transaction_gate FAIL — catalog↔manifest / manifest↔engine SL-02 불일치 (스냅샷 vs HEAD epoch 착전 비교) |
| `ci-frozen-2026-10-08` | epoch_transaction_gate FAIL — 5건 epoch transaction 위반 |
| `ci-frozen-2026-10-01` | projection drift FAIL — (h) gates.json projection, (i) core.hooksPath writer, (j) debt registry role sets (22건) |
| `ci-frozen-2026-09-30` | 동일 (h)(i)(j) — 23건 |
| `ci-frozen-2026-09-28` | 동일 (h)(i)(j) — 23건 |
| `ci-frozen-2026-09-30` 등 나머지 | 상기 동일 |

구조적 원인: `.githooks/pre-push` Part 4는 푸시 OID를 worktree 스냅샷으로 떠서
`make push-admissibility`로 심사한다. 이 심사는 "푸시 = HEAD로의 epoch 착전"
가정의 브랜치 지향 판정이라, 이미 여러 세대를 지나온 HEAD와 과거 freeze 커밋을
비교하는 태그 push는 구조적으로 false-positive 된다. origin에 있는 유일한
`ci-frozen-2026-09`는 게이트가 push-target OID 심사를 갖기 전 시점의 푸시다.
→ **(a)의 진정한 승격은 push-admissibility에 태그 push용 심사 경로(불변 참조
등록으로서의 태그)를 마련하는 게이트 개정이 선행돼야 한다 — Follow-up.**

## 구현 (선택지 b)

두 테스트에 동일 idiom 추가:

- `freezeTagMissing(): bool` — `git rev-parse -q --verify refs/tags/<FreezeTag>` 로컬 부재 판정
- `frozenFile(rel)` — 기존 `runGit("show <tag>:<file>")` 그대로 (단정 무변경)
- 호출층은 `if freezeTagMissing(): echo 사유 + skip() / else: 기존 검증 전체` —
  `skip()`은 실행을 중단하지 않는다(Nim 2.2.10 std/unittest: 상태만 SKIPPED로
  표시)므로 호출층이 부재 경로를 먼저 닫는다.

태그가 있는 클론(정본 개발 클론)에서는 어떤 단정도 약화되지 않는다.

## 검증 실측

| 조건 | 결과 |
|---|---|
| 태그 있음(개발 클론) | 두 테스트 전 스텝 `[OK]`, exit 0 — 변경 전과 동일 |
| 태그 없음 시뮬레이션(개발 클론 + `git rev-parse` fail shim) | freeze 대비 2 테스트 `[SKIPPED]` + `[freeze-tag-missing] … 복구: git fetch origin tag …` 출력, `[FAILED]` 0, exit 0 |
| **진짜 신규 클론**(`git clone --no-tags git@github.com:Archright/Axiom`, `nimble build` 후) | 태그 0개 확인, 위와 동일 — `[SKIPPED]` 2건, `[FAILED]` 0, exit 0. (변경 전 동일 클론에서는 `git show` exit 128로 hard-FAIL이 재현됐다) |

부수 관측: 저장소 내부에 중첩 클론을 만들면 nim이 상위 디렉터리 `config.nims`를
이중 적재해 ambiguous macro 오류가 난다 — 기등록 quirk
`docs/spec/nested_worktree_config_quirks.md`와 동일 기전(검증 클론은 저장소
밖 /tmp에서 수행).

## 후속

1. push-admissibility 태그 push 심사 경로 개정(§2.5 절차) — 개정 후 6개 태그를
   push하면 일반 클론이 git-fetch auto-follow로 태그를 자동 수신하고, 본 PR의
   skip 경로는 자연 소멸한다(단정은 처음부터 약화되지 않았으므로 별도 철거
   작업 불필요 — 부재 경로만 잠들한다).
2. freeze 태그 신규 생성 시 push 가능 여부를 epoch record에 실측 기록 권장.
