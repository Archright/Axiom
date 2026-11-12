# 회전 핀 writer + 로컬 fail-fast 슬라이스 — 착지·수용 기록 (2026-10-25)

> **종류**: 실행 증거 + 사후 수용 기록.
> **대상**: 저장소 `Archright/Axiom`, PR #1101, 브랜치 `work/vs1-reanchor`, 작업 트리 `<user-home>/axwt/vs1pin`, head `2e4b7755cd9d8b2319002929248f08c8bd42ea6e`.
> **권위**: 본 문서는 **기록**이다. 병합 판정 권위는 GitHub ruleset·required checks·merge queue이며 본 문서는 그 판정을 대체하지 않는다 (AGENTS.md §2.3 Authority ≠ Adapter).
> **수치 규약**: 모든 수치는 재도출 명령과 함께 적는다. 재도출하지 못한 값은 **인용(출처 미확정)** 으로 표기한다.

---

## 1. 주장 (Claim)

1. `tools/ci/reanchor_pin.nim`은 `pin@ref` ↔ `derived(ref)` 판정을 **공유 술어**(`src/core/policy/rotation_closure_facts.nim`)로 수행하고, drift를 표적 치환으로 고쳐 쓴다. 판정을 재구현하지 않는다.
2. `.githooks/pre-push` Part 5는 **같은 술어**를 푸시 시점에 실행해 stale pin을 원격 CI 이전에 차단한다.
3. 두 도구(`reanchor_pin`, `derive_checker_closure`)의 신선도는 **내용 주소**로 강제된다 — mtime도, "존재하면 재사용"도 아니다.
4. 이 PR은 `trustedCheckerTreeClosure` 비멤버만 건드리므로 회전이 필요 없다.

### 명시적 비주장 (Non-claims)

- **회수 시간을 주장하지 않는다.** PR 1건의 착지는 경로가 작동한다는 증거이지 절감률의 증거가 아니다.
- **판정을 바꾸지 않는다.** 술어는 소비되며 재구현되지 않는다.
- **권위를 옮기지 않는다.** 착지 H2(`merge_cli` Pass 2.75)와 PR-head preflight(`admission-check`)가 계속 권위다. pre-push는 `--no-verify`로 우회 가능한 개발자측 어댑터다.
- **45.7%는 이 사유 코드가 아니다.** §2.

---

## 2. 동기 수치의 정정 (반증된 귀속)

계획 초기에는 "핀 실패가 비착지의 45.7%"라고 적었다. 데이터로 반증했다.

```bash
python3 - <<'PY'
import json
d=json.load(open('data/ci_optimization/pr_to_main_attribution_2026-10-20.json'))
for k,v in d['incidents']['contribution'].items():
    print(f"{k:24s} n={v['n']:4d}  share={v['share_of_data_complete_tot_pct']}%")
PY
```

| 클래스 | n | TOT 비중 |
|---|---:|---:|
| `venue_red` (전체) | 46 | **45.7%** |
| `human_idle` | 25 | 28.6% |
| `dequeued_failed_checks` | 7 | 14.8% |

`NOT_ADMIT_ROT_NEW_PIN`은 `venue_red`의 **부분집합**이며 규모가 다르다:

| 항목 | 값 | 재도출 |
|---|---:|---|
| 해당 사유로 dequeue된 PR | **6** / 419 (데이터 완전) | **재도출됨** — #812, #827, #838, #895, #919, #933 |
| 6건의 생성→main 합계 | **76,575 s (1,276 min)** | `sum(tot_s)` |
| 건당 평균 | **213 min** | 76,575 / 6 / 60 |
| 코호트 중앙값 TOT | **26 min** | `metrics.tot_data_complete.p50 = 1556 s` |
| 코호트 TOT 질량 비중 | **4.7%** | 76,575 / 1,622,397 |

6건 PR 목록(#812 #827 #838 #895 #919 #933)은 인용이 아니라 **재도출됨**이다. 위와 같은 데이터셋에서 `reason_code = NOT_ADMIT_ROT_NEW_PIN`인 행은 정확히 6건이고 `sum(tot_s) = 76575.0`이다(2026-10-25 팩트체크 재도출; 도출 명령은 본 절 상단의 파이썬 블록).

---

## 3. 이미 존재하던 것 (재구현 금지)

| 구성요소 | 위치 | 역할 |
|---|---|---|
| 공유 술어 | `src/core/policy/rotation_closure_facts.nim` | `parseDerivedSet` / `pinClosureLineSet` / `newAnchorVerdict` |
| 착지 판정 | `src/cli/merge_cli.nim` Pass 2.75 | merge 결과의 H2 판정 |
| PR-head preflight | `.github/workflows/admission-check.yml` (PR #971) | head에서 같은 술어 실행 |
| preflight 체커 | `tools/ci/rotation_pin_anchor_check.nim` | 위 워크플로가 B에서 컴파일해 실행 |

이 슬라이스가 새로 만든 것은 **판정이 아니라 세 가지**다: (a) 앵커를 생산하는 writer, (b) 같은 술어의 로컬 실행 지점, (c) 도구 신선도의 내용 주소화.

---

## 4. 관측 (명령 + 출력)

작업 트리: `<user-home>/axwt/vs1pin` (PR #1101, `work/vs1-reanchor`, head `2e4b7755cd9d8b2319002929248f08c8bd42ea6e`), 생성 시점 base `ed832e9a7e8901f69c0f42f6513fa581eea4965d`.

| # | 명령 | 관측 | 시각 |
|---|---|---|---:|
| 1 | `bin/reanchor_pin --ref HEAD` | `OK no-drift — pin@HEAD anchors derived(HEAD)`, exit 0 | 6.0 s |
| 2 | `bin/derive_checker_closure --ref HEAD \| wc -l` | `881` | 5.94 s |
| 3 | `bin/reanchor_pin --ref HEAD --derived /tmp/member_added.txt` | `missing-from-pin tools/ci/hourly_probe.nim …` + `REFUSED … No file written`, exit **3**, pin 무변경 (주입한 derived 목록은 **합성 입력**이다 — `tools/ci/hourly_probe.nim`는 트리에 존재하지 않는 경로다) | <0.1 s |
| 4 | 단일 blob sha 변경 + `--write` | exit 1 → `--write` → exit 0, diff **1 insertion / 1 deletion**, 재실행 멱등 | — |
| 5 | `nim c -r tests/ci/test_reanchor_pin.nim` | 18 tests 통과 | 11.6 s |
| 6 | 음성 푸시 A: `git push --dry-run tmporigin HEAD` | Part 5: `changed tools/ci/derive_checker_closure.nim 73a0028… -> 7401a33…`, exit **1** | 40 s (도구 빌드 포함) |
| 7 | 음성 푸시 B: `git push --dry-run tmporigin refs/heads/tmp/pinneg:refs/heads/tmp/pinneg` | 동일 drift 검출, exit **1** | 6 s |
| 8 | 양성 푸시: `git push --dry-run tmporigin HEAD` | `[PASS] Pre-push checks passed`, exit **0** | 125 s |
| 9 | 실제 푸시: `git push origin HEAD` | `* [new branch] HEAD -> work/vs1-reanchor`, exit 0 | 105 s |
| 10 | 메시지 정정 후 force-push | `+ 564985c84...2e4b7755c … (forced update)`, exit 0 | 107 s |

> #10의 force-push는 **내용 변경이 아니다**: `git diff 564985c84 2e4b7755c` → 출력 없음(트리 동일). 바뀐 것은 커밋 메시지뿐이다.

### 4.1 푸시 1회 비용의 분해

| 구간 | 시간 | 근거 |
|---|---:|---|
| Part 5 (회전 핀) | **6.0 s** | #1, #2 — `derive_checker_closure` 지배(5.94 s / 881 파일) |
| Part 4 (기존 push-admissibility 스냅샷) | **≈ 95–120 s** | #8~#10 총시간 − Part 5 |
| 합계 | 105–125 s | #8, #9, #10 |

(위는 착지 시점 관측값이다. 스테디스테이트 재실측 96.4 s와 `Makefile:60` 문서값의 불일치는 §6.6과 F3.)

### 4.2 `derive_checker_closure` 5.9초의 정확한 원인 (실측)

`strace -f -c` → **877 `clone3` + 1,755 `execve`**. `tools/ci/derive_checker_closure.nim:472`의 `fileContent`가 경로마다 `git show`를 spawn하고, `execCmdEx`가 `/bin/sh -c`를 경유하므로 호출당 2회 exec가 발생한다. (§4 표 #2의 `881`은 클로저 **멤버 수**이고, 아래 표의 `~872`는 그중 `git show` 호출 **spawn 추정치**다 — 별개의 수치다.)

| 연산 | 횟수 | 호출당 | 합계 |
|---|---:|---:|---:|
| `git show <ref>:<path>` (sh 경유) | ~872 | 6.3 ms | **~5.5 s (92%)** |
| `git ls-tree -r --full-tree` | 1 | 12 ms | 12 ms |
| in-process 파싱/정렬 | — | — | ~0.4 s |

단일 `git show` 6.3 ms vs `git cat-file --batch` 0.06 ms/object → **동일 집합을 유지하면서 ~10× 단축 가능**(§7 후속 F2).

---

## 5. 외부 공식 문서 대조 (반증 결과)

### 5.1 pre-push 계약 (githooks(5) · git-push(1))

| # | 가정 | 판정 | 근거 |
|---|---|---|---|
| C1 | stdin은 `<local ref> <local oid> <remote ref> <remote oid>` 4필드, ref당 1줄 | 지지 | "lines of the form: `<local ref> SP <local object name> SP <remote ref> SP <remote object name> LF`" |
| C2 | 첫 필드는 `refs/heads/*`로 신뢰할 수 없다 | **지지** | "If the local commit was specified by something other than a name which could be expanded (such as HEAD~, or an object name) it will be supplied as it was originally given." |
| C3 | `--dry-run`은 훅을 실행하고 `--no-verify`는 우회한다 | 지지 | "Do everything except actually send the updates." / "With --no-verify, the hook is bypassed completely." |
| C4 | 삭제는 all-zero OID로 신호된다 | 지지(주의) | "the `<local object name>` will be the all-zeroes object name" — 자릿수는 해시에 따라 40 또는 64 |
| C5 | 훅은 푸시당 1회, 커밋 수와 무관 | 지지 | 스크래치 저장소 실측: 2-커밋 push → 1줄 |
| C6 | `git cat-file -e <oid>^{commit}`은 commit-ness 판정 | 지지(뉘앙스) | "is or peels to a commit" — 주석 태그도 0으로 통과 |

**C2가 이 슬라이스의 설계 근거다**: 로컬 ref를 필터로 쓰지 않고 commit-ness를 구조적으로 판정한다(`.githooks/pre-push:123`).

### 5.2 merge queue (docs.github.com)

| # | 가정 | 판정 |
|---|---|---|
| M1 | merge_group에서 필수 검사가 다시 실행된다 | 지지 — "pull request와 **다른 sha**를 포함합니다" |
| M2 | merge_group 실패는 큐에서 제거된다 | 지지 |
| M3 | ruleset이 merge queue를 "요구"한다 | 부분 — 문서상 merge queue는 **branch protection 설정**이고, ruleset 규칙 카탈로그에는 없다 |
| M4 | PR-head 결과를 큐에서 재사용할 수 있다 | **반박** — 그런 설정은 존재하지 않는다 |
| M5 | auto-merge는 저장소 설정이 선행돼야 한다 | 지지(+큐 필수 브랜치에는 예외) |
| M6 | 필수 검사가 아닌 워크플로는 병합을 막을 수 없다 | 부분 — ruleset의 code scanning/coverage/deployment 규칙은 막을 수 있다 |

**M4 반박의 함의**: 큐의 재실행은 "낭비"가 아니라 설계상 본질이다. 단축 수단은 build concurrency(1–100), merge limits(그룹 크기), 필수 검사 집합뿐이며 마지막은 정책 변경이다.

### 5.3 Nim stdlib (nim-lang.org, 2.2.x)

| # | 가정 | 판정 |
|---|---|---|
| N1 | `execCmdEx`는 raise 가능 → `{.raises: [].}`에는 try/except 필요 | 지지 |
| N2 | `moveFile`은 OSError를 던진다 | 지지(원자성은 **문서화되지 않음** — §7 F4) |
| N3 | `parseJson`은 raise → `func` 불가 | 지지 |
| N4 | `execCmdEx`는 stderr를 포함하지 않는다 | **반박** — 기본 옵션에 `poStdErrToStdOut`이 포함된다 (`lib/pure/osproc.nim:78`) |
| N5 | effect 추론은 전이적이고 위반은 컴파일 오류 | 지지 |
| N6 | `execCmdEx`는 항상 `/bin/sh -c`를 경유한다 | 지지(stdlib 소스 `osproc.nim:1559` — `options + {poEvalCommand}` 무조건 추가, Nim 2.2.10) |

**N4의 함의**: `runGit`/`readDerived`는 stderr 유입 시 판정 텍스트가 오염될 수 있다. 방향은 **fail-closed**(파싱 실패 → exit 2, 판정 없음)이므로 수용 잔여로 둔다(§7 F5). 대안(`poStdErrToStdOut` 제거)은 읽지 않는 파이프를 만들어 버퍼 포화 위험을 만든다.

---

## 6. 한계 (fail-closed 정직성)

1. **`test-unit`은 CI에서 실행되지 않는다.** `tests/ci/test_reanchor_pin.nim`을 `make test-unit`에 등록했지만 CI는 `make test-fast-one`으로 GO-critical subject만 실행한다. 그 등록은 **저장소 관례**이며 CI 강제가 아니다. 사실의 CI 강제는 H2와 PR-head preflight가 담당한다.
2. **pre-push는 우회 가능하다** (`--no-verify`). 그래서 권위가 아니다.
3. **한 건의 착지는 시간 회수의 증거가 아니다.**
4. **이 PR은 closure 비멤버만 건드린다** — `bin/reanchor_pin --ref HEAD` → `OK no-drift`.
5. **빌드 출처(BuildSourceHash)는 `tools/ci` 변경을 커버하지 않는다.** PR의 6개 신규 파일이 트리에 있어도 `bin/ax --check-provenance`는 OK를 반환한다 → 그 파일들은 BuildSourceHash 입력 집합이 아니다. 그래서 도구 신선도는 빌드 출처가 아니라 내용 주소 스탬프 `bin/<tool>.srchash`가 **별도로** 담당한다(§1 주장 3).
6. **사전 푸시 비용의 스테디스테이트 실측(2026-10-25): 96.4 s.** 이 중 신규 Part 5 핀 검사는 6.0 s이고 나머지는 기존 Part 4 스냅샷이다(89 s user CPU). `Makefile:60`은 "warm 22–27 s"로 문서화해 기존 불일치가 스탠딩으로 존재한다 — 이미 F3으로 추적된다.
7. **main HEAD에는 check run이 없다.** `gh api .../commits/4a03678.../check-runs` → `[]`. 수용 판정은 병합 후 push가 아니라 `pull_request` / `merge_group` 컨텍스트에서 평가되기 때문이다. 수용 기록은 PR/merge-group 위에 존재하며 main HEAD 위에 존재하지 않는다(§9.1).
8. **계약 밖 입력은 판정 대신 거부다 (fail-closed).** 비(非)Axiom 저장소(nim-libp2p)에서 `./bin/reanchor_pin --repo <nim-libp2p> --ref HEAD` → stderr `reanchor_pin: input contract violation: deriver missing: .../bin/derive_checker_closure (build: ...)`, exit 2, 출력 없음, 파일 미작성.

---

## 7. 후속 (발견 ≠ 권한 — 이 PR에서 고치지 않음)

| # | 발견 | 근거 | 제안 |
|---|---|---|---|
| F1 | 삭제 판정이 **40자리 0** 고정 (`.githooks/pre-push:53`) — SHA-256 저장소는 64자리이므로 삭제가 PUSH_OIDS로 유입되어 Part 4가 오해를 낳는 메시지로 실패 | githooks(5) "all-zeroes object name"; 이 저장소는 SHA-1(`git rev-parse --show-object-format` → `sha1`)이라 **오늘은 도달 불가** | `[[ "$lo" =~ ^0+$ ]] \|\| [ "$lr" = "(delete)" ]`로 교체 |
| F2 | `derive_checker_closure`가 877 `git show` spawn → 5.9 s의 92% | §4.2 | `git cat-file --batch` 상주 프로세스로 ~10× 단축(집합 불변) |
| F3 | Part 4 스냅샷이 문서상 "warm 22–27 s, 재컴파일 없음"(`Makefile:60`)이나 실측 95–120 s | §4.1 | 스냅샷에 필요한 바이너리(`effect_contract_projection`, `nimtry`, `surface_guard`)를 심볼릭 링크하거나 1회 빌드 캐시 공유 |
| F4 | `writePinAtomically`의 "원자적"은 문서 보장이 아니다 | osfiles.html은 원자성을 명시하지 않고, 구현은 EXDEV에서 copy+remove로 폴백 | tmp를 대상과 **같은 디렉터리**에 두는 현 구현이 rename 경로를 타므로 실질 원자적 — 주석에 근거 명시 |
| F5 | `execCmdEx`가 stderr를 stdout에 병합 | N4 | 현 상태는 fail-closed. 제거 시 파이프 미독취 위험 → 명시적 옵션+별도 캡처로 재설계할 때 함께 처리 |
| F6 | `test-unit` 미실행 | §6.1 | DEBT/정책 결정 사안 — 별도 슬라이스 |
| F7 | `tests/ci/test_reanchor_pin.nim`의 18개 테스트는 도구의 판정/재작성/멱등성/인자 로직만 커버한다 — **훅의 `.srchash` 스탬프 무효화와 stdin local-ref 처리는 미커버**다 | §4 #5, #6 | 훅 통합 테스트(스탬프 무효화 경로·local-ref 주입 경로) 추가 |

---

## 8. 로컬 수용 레시피 (Acceptance Recipe) — 원격 수용 런의 로컬 재현

원격 수용과 같은 타깃을 로컬에서 재현한다. CI가 이미 같은 타깃을 수용 런으로 실행했다: workflow `axiom-operational-slice.yml`, run id `40143020602`, event `pull_request`, 생성 `2026-10-24T23:30:33Z` → 갱신 `2026-10-24T23:36:44Z`, conclusion `success` (6m11s). 그 잡이 실행하는 명령이 `make verify-contract-release-e2e-full`이다 (`.github/workflows/axiom-operational-slice.yml:79`).

1. **ircheck 바이너리가 존재해야 한다.** `proofs/.lake/build/bin/ircheck`. 빌드: `cd proofs && lake build ircheck` → 6.3 s, 10 jobs, 외부 의존 제로(lakefile에 `require` 없음, `lake-manifest.json`의 packages가 비어 있음).
2. **타깃 실행.** `make verify-contract-release-e2e-full` → 76.6 s:

   ```
   [Depth 1/1] Checking: orchestrator_api.nim::normalizeMaxWorkers... [VERIFIED]
   [cert] Verify: PASS (kernel re-execution — lean=re-executed, z3=unsat, leanchecker=passed)
   INFO: G7 pass (tier=dual-verified status=verified cert=data/trusted/certificates/e57ee9394d16b8dcb8a859eb205f59a55dc3926227dc2250a21448c8d5ebf200.json)
   ✅ verify-contract-release-e2e-full PASSED
   ```

   exit 0.

3. **ircheck 부재 = 같은 타깃의 FAIL (fail-closed 강등 — 거짓 PASS가 아닌 속성).** ircheck 없이 같은 타깃을 실행하면 노드가 `NOT_VERIFIABLE`로 강등되고 `verified=0/40`, verdict `INCONCLUSIVE`, gate `FAIL`이 된다. 이때 `report --json`은 exit 0을 반환하고 타깃은 1을 기대하므로 타깃이 실패한다: `FAIL: report exit 0 inconsistent with verdict (verdict=INCONCLUSIVE gate=FAIL v=0 f=0 to=0, expect 1)` (`Makefile:906-908`). 검증 근거가 사라지면 수용 판정도 사라진다 — 이 강등이 레시피의 fail-closed 속성이다.
4. **대조군(통제).** 위 3의 실패는 순수 `origin/main`(`4a036781c7cade891157077d3202b6f6fb7a7284`)에서 같은 바이너리(ircheck 부재)로 동일 재현된다 → ircheck 부재 실패는 PR #1101이 유발한 것이 아니라 **사전 존재·환경적** 조건이다. `bin/ax --check-provenance`는 브랜치 트리와 main 트리 양쪽에서 `OK — embedded BuildSourceHash == live src tree (-1042989347148869567)`를 반환한다(커버리지 한계는 §6.5).

---

## 9. 착지 및 canonical main 수용

### 9.1 병합 전 수용 상태 (관측 — 병합 아님)

- **PR**: `Archright/Axiom` #1101, 브랜치 `work/vs1-reanchor`, head `2e4b7755cd9d8b2319002929248f08c8bd42ea6e`, 커밋 2개(`c6728635e` tools, `2e4b7755c` hook+Makefile), 6 files, **+848/−0**.
- **base 이동**: 생성 시점 base `ed832e9a7e8901f69c0f42f6513fa581eea4965d` → GitHub가 base를 `4a036781c7cade891157077d3202b6f6fb7a7284`로 진보시켰다(origin/main이 3커밋 이동: `.github/workflows/ci-cache-publisher.yml`, `docs/evidence/ci_epoch_record_2026-10-25-publisher-job-if.md`, `tools/ci/e4e5_collect.sh` — PR의 6개 파일과 제로 중복). `git merge-tree --write-tree origin/main HEAD` exit 0 = 충돌 없음.
- **필수 검사 컨텍스트**: `admission-check`, `bsec-integrity`, `debt-registry-gate`, `generation-acceptance`, `axiom-operational-slice`. `mergeStateStatus: CLEAN`. head의 check run 30건이 전부 success/skipped.
- **수용 경로는 merge queue 하나뿐이다**: 브랜치 ruleset id 20303214 "main"이 `merge_queue` 규칙(`merge_method: MERGE`, `grouping_strategy: ALLGREEN`, `max_entries_to_build: 2`)을 포함하고 `bypass_actors: []` — 직접 병합은 불가능하다.

### 9.2 착지 값 (POST-MERGE)

<!-- POST-MERGE -->

| 항목 | 값 |
|---|---|
| merge commit OID | `4923d0ffbe351227d0928dd9e968a6cedfa473bb` — parents `dc711eddc7846c201b005fb655b1b2608b65dc40` + `2e4b7755cd9d8b2319002929248f08c8bd42ea6e` (2 parents = MERGE 커밋), 현재 `main` head와 동일 |
| mergedAt | `2026-10-25T00:59:56Z` |
| merge queue run id | `40147665855` (workflow `axiom-operational-slice`, event `merge_group`, conclusion `success`) · admission-gate `40147665987` (`success`) — 8개 merge_group 워크플로 전건 success |
| main 수용 실행 결과 | push run `40148870354` (event `push`, head `4923d0ffb`) — §9.3 |
| main에서 pin no-drift | `OK no-drift — pin@HEAD anchors derived(HEAD)`, exit 0 (`bin/reanchor_pin --ref HEAD`, HEAD = `4923d0ffb`, deriver `bin/derive_checker_closure` 선빌드 필요) |

출처 명령:

```bash
gh api repos/Archright/Axiom/pulls/1101 --jq '{merged,merged_at,merge_commit_sha}'
gh api repos/Archright/Axiom/commits/4923d0ffb --jq '{sha,parents:[.parents[].sha]}'
gh api repos/Archright/Axiom/branches/main --jq '.commit.sha'
gh api repos/Archright/Axiom/actions/runs/40147665855 --jq '{status,conclusion,event,head_sha}'
gh api repos/Archright/Axiom/actions/runs/40147665987 --jq '{status,conclusion,event,head_sha}'
```

이 값들은 merge queue가 PR을 착지시킨 뒤의 **관측된 출력**으로만 채운다 — 병합 전 시점에는 어떤 값도 추정하거나 선언하지 않는다.

**관측 중 발견한 별건(이 슬라이스에서 고치지 않음)**: 착지 직전 구간에서 `landing_observe.sh`의 L2 판정이 `UNKNOWN`으로 떨어졌다 — admission-gate 런은 `completed/success`인데 큐 엔트리가 아직 남아 있는(= GitHub가 merge를 진행 중인) 상태다. 같은 PR이 큐 진입 중에는 `PROGRESSING`, 랜딩 직전에는 `UNKNOWN`으로 불렸다. 수정은 관측 슬라이스(`work/obs-read`)에서 했고, 본 문서는 그 관측을 기록한다.

### 9.3 canonical main 수용 (L4 관측)

`main` head `4923d0ffb`의 push 실행을 관측한 값이다. **관측 시점의 상태를 그대로 적는다** — 진행 중이면 진행 중이라고 쓴다.

| 관측 시점 (UTC) | L4 판정 | 근거 |
|---|---|---|
| 2026-10-25T01:02Z | `PENDING` (exit 3) | run `40148870354` `status=in_progress`, `head_sha=4923d0ffb` |
| 2026-10-25T01:08Z | **`OBSERVED_SUCCESS`** (exit 0) | run `40148870354` `status=completed conclusion=success`; artifact 매니페스트 `sourceTree.gitHead=4923d0ffb`, digest 일치, `report.verdict=PASS`, `certificate.verificationTier=dual-verified`, `binary.sha256=1605522f02ae50b3994f3eb8504ad26747e98b350bd85ef90543748e3cc568a3` |

`PENDING`은 실패도 성공도 아니다 — 아직 완료되지 않았다는 사실이다. 완료 후의 판정은 같은 명령의 재실행으로만 얻었고(§10), 위 두 행이 그 전이다. 수용 판정은 **결속된 push 실행**에 대한 것이며 다른 커밋에 대한 주장이 아니다. `engineBuild=unmeasured`는 이 트리에서 `VerifierBuildId`가 측정되지 않아 워크플로가 그대로 기록한 값이다(결함 아님, 관측 슬라이스 문서 §5.4).

---

## 10. 재현 (Reproduce)

```bash
# 0) 수용 계약: §8 레시피 (ircheck + verify-contract-release-e2e-full)

# 1) 판정 (읽기 전용)
cd <worktree>
bin/reanchor_pin --ref HEAD                                   # 기대: OK no-drift, exit 0

# 2) 멤버십 거부
bin/reanchor_pin --ref HEAD --derived /tmp/member_added.txt   # 기대: REFUSED, exit 3, 파일 무변경 (입력은 트리에 없는 경로를 담은 합성 파일)

# 3) 단위 테스트
nim c -r tests/ci/test_reanchor_pin.nim                       # 기대: 18 tests

# 4) 훅 경유 (음성)
git push --dry-run <remote> refs/heads/<branch>:refs/heads/<branch>   # 기대: stale pin이면 exit 1
```
