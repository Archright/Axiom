# VS-1 PR-head 회전핀 프리플라이트 게이트의 사후 수용 및 MG ROT_NEW_PIN 프리플라이트 NO-GO 결정 (2026-10-24)

> **종류**: 사후 수용·결정 기록 (post-hoc acceptance + decision record). 목적은 **재소청 방지**다 — 이후 독자가 (a) 무엇이 제안되었는가 (b) 무엇이 관측되었는가 (c) 왜 기각되었는가 (d) 무엇이 재개하는가를 이 한 문서에서 보도록 한다.
> **권위**: 본 문서는 기록이다 — 병합 판정 권위는 GitHub ruleset·required checks·merge queue이며 본 문서는 그 어떤 판정도 대체하지 않는다(Authority ≠ Adapter, AGENTS.md §2.3). 착지 정판정 권위는 merge_group venue + org 게이트에 그대로 있다.
> **수치 표기 규약**: §3의 모든 행에는 출처가 붙는다. 독자가 명령으로 재도출할 수 있는 값은 명령을, 파일로 고정된 값은 `파일:행`을 출처로 쓴다. 재도출하지 못한 값은 **인용(출처 미확정)** 으로 표기하고 §5에 모아서 본 문서가 독립 재검증한 것이 아님을 명시한다.

---

## 1. 주장 (Claim)

1. **PR-head VS-1 회전핀 프리플라이트 게이트는 수용되어 운영 중이다.** 착지 커밋 `af579664c`(2026-10-20 17:19:39 +0900, PR #971)로 required check `admission-check` 내부의 preflight venue 스텝으로 착지했으며, 현재 워크플로에서 같은 위치로 발화한다(§3 행 1–3). 수용 판정의 정의는 사전등록 `docs/evidence/rotation_preflight_prereg_2026-10-20.md` §7–§8(픽스처 하니스 + 실행 타임라인/스냅샷)을 따른다.
2. **동일 판정을 merge_group venue에 추가하는 MG ROT_NEW_PIN 프리플라이트 제안은 NO-GO다.** 제안은 사전등록 §1이 기록한 격차("부정합 회전 PR은 merge_group verdict에 도달해야만 적발", `rotation_preflight_prereg_2026-10-20.md:12`)를 MG 쪽에서도 조기 적발로 메려는 것이며, 전건 변형과 회전 경로 필터 변형이 검토되었다. 그러나 PR-head 게이트가 head-anchored라면 같은 헤드는 큐에서 같은 H2 술어로 실패할 수 없다(§3 도출). 즉 MG 프리플라이트는 **중복 판정**이고, 기대 절감(~60 job-min/월)이 비용(~880 job-min/월)을 크게 하회한다. 손익분기 실패율은 p > 5%인데 실측 p ≈ 0.41%(3/734)다.
3. 재개 조건은 §6에 고정한다 — 본 NO-GO는 현재 세대의 판정이며 영구 금지가 아니다.

## 2. 범위와 방법 (Scope & Method)

- **범위**: (a) PR-head 게이트의 착지·수용 기록, (b) MG 프리플라이트의 경제성 재판정. PR-head 게이트의 계약·판정 로직 변경은 대상이 아니다(그 대상은 사전등록 문서의 소관이며 착지 후 변경 금지).
- **방법**: 커밋·사전등록 문서·활성 워크플로·GitHub API 관측을 명령으로 재현했다(§7). 재도출에 성공한 수치만 사실로 서술했고, 그렇지 못한 수치는 인용(출처 미확정)으로 격리했다.
- **판정 구조 요지**: preflight의 H2 판정은 `line-set(pin@H) == set(derived H)`이며, 판정기는 `evaluatePinAnchorTexts` — 3개 파일 **내용**만의 순수 함수다(`tools/ci/rotation_pin_anchor_check.nim:85`). base 상태는 pin@B를 경유해 **실패 클래스 선택**(ROT_NEW_PIN vs ROT_GENESIS_INVALID)에만 개입하고 pass/fail 자체에는 개입하지 않는다.

## 3. 관측 (Observation)

| 지표 | 값 | 출처(파일:행 또는 명령) |
|---|---|---|
| PR-head 게이트 착지 커밋 | `af579664ce24fd95628370dd632d013a05e3be0c` — 2026-10-20 17:19:39 +0900 "feat(admission): VS-1 PR-head rotation-pin preflight (single judgment, artifact-only)" | `git log --format='%H %ci %s' -1 af579664c` |
| 착지 PR | #971, MERGED 2026-10-20T09:34:16Z, merge commit `4f19c7d37102ab5e29644b05b8ac43398e86fb13` | `gh pr view 971 --repo Archright/Axiom --json number,state,mergedAt,mergeCommit --jq '{number,state,mergedAt,mergeCommit:.mergeCommit.oid}'` |
| 게이트의 현재 운영 | preflight venue 스텝으로 발화 — L2 H2 judgment 체커 호출(`rotation-preflight` 스텝군) | `grep -n "rotation_pin_anchor_check" .github/workflows/admission-check.yml` (2220–2223 호출, 2235 PASS 로그) |
| H2 판정 단일 구현 | 체커와 landing predicate이 같은 리프 모듈 `newAnchorVerdict`를 소비 — 판정 드리프트 구조적으로 불가 | `tools/ci/rotation_pin_anchor_check.nim:36` · `src/cli/merge_cli.nim:97,101,726` · `src/core/policy/rotation_closure_facts.nim:141` |
| 판정의 순수성 | `evaluatePinAnchorTexts(derivedHText, pinHText, pinBText)` — 3파일 내용만의 순수 함수, exit 계약 0/1/2 fail-closed | `tools/ci/rotation_pin_anchor_check.nim:40-42,85` |
| 식별자 바인딩 (head-anchor) | 판정 키 = `identity.candidateHeadSha == 이벤트 PR head sha`(네트워크 접근 전 등식) + `pinHeadBlobSha == git rev-parse H:config/trusted_writer_set.json` — 판정 입력 전체가 헤드 커밋에 결속 | `docs/evidence/rotation_preflight_prereg_2026-10-20.md:25-31` |
| 최근 merge_group 실패 런 | run 40049469259 = `admission-gate` / `merge_group` / `failure` / 2026-10-24T01:22:10Z / head `d0d84e44022b49b48062b6e0045fe88e2adca5c3` — 분류 **`NOT_ADMIT_UNPARSED`**(verdict check-run 어노테이션 title; **ROT_NEW_PIN 아님**) | `gh api repos/Archright/Axiom/actions/runs/40049469259 --jq '{name,event,conclusion,created_at,head_sha,display_title}'` + `gh api repos/Archright/Axiom/check-runs/120742751568/annotations --jq '.[] | {title,message}'` (§7) |
| ROT_NEW_PIN 큐 실패(dequeue) 건수 | 30일 라이브 창 3건, 합계 ~71 job-min | **인용(출처 미확정)** — §5.1 |
| merge-group 큐 진입률 | 734건/25일 ≈ 29.4/day | **인용(출처 미확정)** — §5.1. 재도출 시도: `gh api "repos/Archright/Axiom/actions/runs?event=merge_group&created=2026-09-29..2026-10-24&per_page=1" --jq '.total_count'` → 2,500 — 이는 **워크플로 런 단위**라 '큐 진입' 단위와 다르다(측정 단위 불일치로 재도출 불가 판정) |
| 회전 경로 터치율 | 311/734 = 42.4% (경로 필터 변형에서도 판정 대상인 진입 비율) | 분자·분모는 위 행의 인용치에서 산출 — **인용(출처 미확정)**, 백분율 환산은 본 문서 재계산 |
| 별개 메트릭 (혼동 금지) | 2026-10-13→19 코호트의 `NOT_ADMIT_ROT_NEW_PIN` 6건 — 다른 창·다른 단위(런/사유코드 집계)다 | `docs/evidence/pr_to_main_attribution_decision_2026-10-20.md:67` |

**head-anchored 도출(행 4–6의 결합)**: H2 등식 `line-set(pin@H) == set(derived H)`의 양변은 모두 헤드 커밋만의 함수다 — pin@H는 `pinHeadBlobSha == blob@H` 등식으로 헤드에, derived-H는 `candidateHeadSha == PR head` 등식으로 헤드에 각각 결속된다(행 6). 따라서 "preflight PASS"는 **그 헤드에 대한 등식의 참**이고, merge_group이 같은 등식을 같은 컴파일 구현으로(`newAnchorVerdict`, 행 4) 평가하면 결과가 다를 수 없다. pin@B의 `trustedCheckerTreeClosure` 키 유무는 실패 시 클래스(ROT_NEW_PIN vs ROT_GENESIS_INVALID)를 고를 뿐(`docs/evidence/rotation_preflight_prereg_2026-10-20.md:47-53`), PASS를 실패로 뒤집지 못한다. **결론: PR-head 게이트를 통과한 헤드는 같은 H2 술어에서 merge_group 실패(ROT_NEW_PIN/ROT_GENESIS_INVALID)가 불가능하다.** MG 프리플라이트가 차단할 수 있는 실패는 PR venue에서 이미 차단된 것들뿐이다.

## 4. 결정 (Decision)

**NO-GO — MG ROT_NEW_PIN 프리플라이트를 도입하지 않는다.** 산술(전부 명시 재계산):

- **비용**: 신규 preflight 1 job-min/진입 × 진입률 29.4/day × 30일 = 882 ≈ **880 job-min/월**
- **절감**: 회피당 ~20 job-min × 실패 3건/30일 = **60 job-min/월**
- **손익분기**: 진입당 기대 절감 20p job-min vs 비용 1 job-min → 20p − 1 > 0 ⇔ **p > 5%**
- **실측**: p = 3/734 ≈ **0.41%** (0.4087%; 인용 표기 0.42%는 같은 몫의 반올림 차) — 임계의 약 1/12
- **순손실(전건 변형)**: 880 − 60 = **+820 job-min/월**
- **경로 필터 변형**: 비례 비용 880 × (311/734) = 880 × 0.4237 ≈ 373 → 373 − 60 ≈ **+313 job-min/월**(하한 ~310과 일치). 상한 ~690은 인용치다(§5.1) — 순손실 범위 **+310~690 job-min/월**.

판정 이유의 요지: §3 도출에 따라 PR-head 게이트가 이미 같은 헤드의 같은 H2를 판정하므로, MG 프리플라이트는 음의 기대수익을 가진 중복 판정이다. 극장 금지(AGENTS.md §0.9) 관점에서도, 차단할 것이 없는 곳에 차단 절차를 추가하는 것은 보장의 연출이지 보장이 아니다.

## 5. 이 문서가 주장하지 않는 것 (Non-claims)

1. **미재검증 수치 목록 (전부 인용, 출처 미확정)**: ① 30일 창 ROT_NEW_PIN dequeue 3건 ② 합계 ~71 job-min ③ 진입 734건/25일 ④ 회피당 ~20 job-min ⑤ 경로 필터 손실 상한 ~690 job-min/월. 저장소 내 정본 출처(파일:행)를 확보하지 못해 이 문서는 이들을 독립 재도출하지 않았다. §3의 인용 행과 §4의 산술은 이 값들을 전제로 하며, 출처가 확보되면 §6.4에 따라 재계산한다. **독립 재도출에 성공한 값**: 착지 커밋 시각·PR #971 병합·게이트의 현재 운영·단일 구현 위임·런 40049469259의 `NOT_ADMIT_UNPARSED` 분류·백분율 환산(3/734, 311/734)·손익분기 부등식.
2. `gh api .../runs?event=merge_group` 카운트(2,500)는 큐 진입 수가 아니다 — 워크플로 런 단위로서 734건과 단위가 다르다. 두 값을 혼용해서는 안 된다.
3. 코호트 수치(`NOT_ADMIT_ROT_NEW_PIN` 6건, 10-13→19)는 30일 창 3건과 다른 메트릭이다 — 서로 모순이 아니다.
4. 본 문서는 PR-head 게이트의 제거·완화를 주장하지 않는다 — 그 게이트는 수용된 상태이며 본 문서는 그 수용을 기록한다. 사전등록 §7–§8의 픽스처 수용 관측은 착지 시점에 수행·기록된 것이고 본 문서가 재실행하지 않았다.
5. 최근 실패 런이 `NOT_ADMIT_UNPARSED`라는 관측 1건은 PR-head 게이트의 무용 증거가 아니다 — `NOT_ADMIT_UNPARSED`(착지 계열, run-level err)와 `NOT_ADMIT_ROT_UNPARSED`(preflight 입력 계약 가드)는 별개 클래스다(`rotation_preflight_prereg_2026-10-20.md:91`).
6. 착지 admissibility의 정판정 권위는 merge_group venue + org 게이트에 있다 — 본 문서의 NO-GO는 어댑터 도입 여부의 결정이지 착지 판정의 변경이 아니다(§2.3).
7. NO-GO는 영구 금지가 아니다 — §6의 조건이 관측되면 새 사전등록 문서로 재개한다.

## 6. 재개 조건 (Reopen conditions)

다음 중 하나가 관측되면 **새 날짜의 사전등록 문서**로 재개한다(본 문서의 in-place 변경 금지):

1. **p의 실질 상승**: 같은 진입률 기준 30일 ROT_NEW_PIN 큐 실패가 **37건 이상**(0.05 × 734 = 36.7)으로 관측되어 20p − 1 > 0이 회복될 때.
2. **비용 붕괴**: 진입당 preflight 비용이 1 job-min을 실질적으로 하회(예: 판정 입력의 완전 캐시 재사용으로 초 단위 비용)할 때.
3. **방어선 상실**: PR-head 게이트의 제거·완화·우회 가능성(head-anchor 보장의 상실)이 생겨 merge_group 판정이 유일 방어선이 되는 세대 전환 시.
4. **측정 SSOT 확보**: §5.1의 인용치(3건·71 job-min·734건·20 job-min·690)의 정본 출처가 `data/` 또는 `docs/evidence/`에 확보되면 전체 산술을 재계산하고 본 문서의 후속 문서로 결정을 갱신한다.

## 7. 재현 명령 (Reproduction commands)

저장소 클론에서 그대로 실행 가능한 명령과 실측 출력(필요부 발췌):

```bash
# (1) 게이트 착지 커밋
git log --format='%H %ci %s' -1 af579664c
# af579664ce24fd95628370dd632d013a05e3be0c 2026-10-20 17:19:39 +0900 feat(admission): VS-1 PR-head rotation-pin preflight (single judgment, artifact-only)
git log --oneline --all | grep af579664c
# af579664c feat(admission): VS-1 PR-head rotation-pin preflight (single judgment, artifact-only)

# (2) 착지 PR
gh pr view 971 --repo Archright/Axiom --json number,state,mergedAt,mergeCommit --jq '{number,state,mergedAt,mergeCommit:.mergeCommit.oid}'
# {"mergeCommit":"4f19c7d37102ab5e29644b05b8ac43398e86fb13","mergedAt":"2026-10-20T09:34:16Z","number":971,"state":"MERGED"}

# (3) 단일 판정 구현 — 체커·landing predicate이 같은 리프 모듈을 소비
git show af579664c:tools/ci/rotation_pin_anchor_check.nim | sed -n '36p;40,42p;85p'
# 36:import core/policy/rotation_closure_facts
# 40:  ExitPass* = 0 / 41:  ExitH2Fail* = 1 / 42:  ExitInputViolation* = 2
# 85:proc evaluatePinAnchorTexts*(derivedHText, pinHText, pinBText: string): CheckOutcome {.
git show af579664c:src/cli/merge_cli.nim | sed -n '97p;101p;726p'
# 97:import core/policy/rotation_closure_facts
# 101:export rotation_closure_facts
# 726:  let v = newAnchorVerdict(derivedH, pinH, pinB)
git show af579664c:src/core/policy/rotation_closure_facts.nim | sed -n '141p'
# 141:func newAnchorVerdict*(derivedH: HashSet[string];

# (4) 게이트의 현재 운영 (preflight venue 스텝)
grep -n "rotation_pin_anchor_check" .github/workflows/admission-check.yml

# (5) 최근 merge_group 실패 런의 분류 — NOT_ADMIT_UNPARSED (ROT_NEW_PIN 아님)
gh api repos/Archright/Axiom/actions/runs/40049469259 --jq '{name,event,conclusion,created_at,head_sha,display_title}'
# {"conclusion":"failure","created_at":"2026-10-24T01:22:10Z","display_title":"admission-gate","event":"merge_group","head_sha":"d0d84e44022b49b48062b6e0045fe88e2adca5c3","name":"admission-gate"}
gh api repos/Archright/Axiom/commits/d0d84e44022b49b48062b6e0045fe88e2adca5c3/check-runs --jq '.check_runs[] | select(.conclusion=="failure") | .id'
# 120744092339
# 120742751568
gh api repos/Archright/Axiom/check-runs/120742751568/annotations --jq '.[] | {title, message}'
# {"message":"admission evaluation failed without a verdict JSON (run-level err) — evidence: admission-verdict artifact","title":"NOT_ADMIT_UNPARSED"}

# (6) 참고 — merge_group 워크플로 런 카운트 (큐 진입 단위와 다름 — §3/§5.2)
gh api "repos/Archright/Axiom/actions/runs?event=merge_group&created=2026-09-29..2026-10-24&per_page=1" --jq '.total_count'
# 2500
```

> **quirk 주의**: `gh run view 40049469259 --repo Archright/Axiom --log`는 stale workflow 참조로 `HTTP 404 .../workflows/386419787`를 낼 수 있다(2026-10-24 실측). 런 조회는 위 (5)의 REST API 경로를 사용한다.
