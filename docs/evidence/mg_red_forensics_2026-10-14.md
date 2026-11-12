# MG 적색 포렌식 요약 — GO-critical 4레인 병렬 스텝 최초 실행 실패 (2026-10-14)

> 2026-10-14 merge_group 4연속 failure(38578920996/38580760673/38583637985/38587538612,
> 14:15–15:14Z)의 근본 원인 요약. 판정은 당일 수행된 2건의 독립 포렌식(F1: 런 로그
> 계통 분석, F2: 코드·계약 계통 분석)에 기반하며 전문은 세션 증거로 보관된다.
> 소비처: `docs/evidence/emergency_evaluate_window_2026-10-14.md`.

## 판정 요약

**infra/resource 계통 — 비결정적, 페이로드 무관.** 콜드 캐시 상태에서 4레인이 공유
출력 경로의 도구를 동시 relink하는 경합(J4 계통 잔여)으로 레인 1~3/4가 27~64s에
사망한다. docs-only 페이로드(#828)이며 pull_request venue는 동일 바이트에서 전부
green이다. 실패 레인 조합이 동일 바이트에서 시도마다 달라졌다(3/4→1/4→3/4→2/4).

## 트리거 계통 (관측 표)

| run id | 큐 head | 개시(UTC) | 판정 | 사망 레인 |
|---|---|---|---|---|
| 38578920996 | cb9439fca | 14:15:39 | failure | s1a+d2g+d2p (3/4, 27.7–43.9s) |
| 38580760673 | 5f6af0ade | 14:28:02 | failure | s1a (1/4, 27.9s) |
| 38583637985 | 4cd02830f | 14:47:19 | failure | pi+s1a+d2g (3/4, 29.1s 일제) |
| 38587538612 | e2bb01266 | 15:14:09 | failure | s1a+d2p (2/4, 50.5s 일제) |

정상 신규 실행은 s1a 242–306s다 — 27–51s 사망은 컴파일·부트스트랩 초기 페이즈의
kill이지 assertion 실패가 아니다. 이후 mint/verdict/final 실패는 전부 fail-closed
연쇄(artifact 부재 → NO_CERT)다.

## (a) 4레인 스텝은 green MG에서 미시행 — REUSED 마스킹

병렬화는 #826(05:02:17Z 착지)이 도입했지만, 그 직후 유일한 MG였던 #827 run
38543329104(09:34:22Z)는 871세대 기록 재사용(REUSED)으로 레인 전체 SKIP 하에
green이었다. #827 착지(09:44:40Z)가 세대를 876으로 회전했고, #828의 MG가 병렬 레인의
**역사상 첫 merge_group 실행**이 됐다 — 즉 병렬 스텝은 착지 전 어떤 green MG로도
검증된 적이 없다.

## (b) J4 잔여 — 웜업 가드 밖 hermetic 3종

c2142ec37의 `[j4-cold-guard]` 직렬 웜업(`admission-check.yml:1142-1165`)은
무조건 재빌드 2종(`bin/feature_manifest_generator`, `bin/sync_certs`)만 앞서
예열한다. `config.nims:533-569`의 MISS/부재 게이트 3종(`sync_topology`,
`hermetic_build`, `decision_binding_checker` — 전부 git 미추적 바이너리)은 가드
밖이며, 자체 잔여 주석(`:1156-1161`)대로 **B-miss/신규 러너 경로에서는 무보호**다.
4레인이 동시에 같은 출력 경로를 relink하면 ETXTBSY형 즉사가 난다
(`data/ci_optimization/parallel_reland_cold_guard_2026-10-13.md` 실증 계통).

## (c) 구조적 콜드 첫실행 + fold-back 부재

테스트 nimcache 캐시 키는 base sha 기반이며 base 키는 "이전에 어떤 주체도 씨딩하지
않아 구조적으로 항상 콜드"다(`ci-cache-publisher.yml:18-20, 129-135`). 세대 회전
직후 첫 MG는 정의상 콜드에서 4레인을 전부 실행해야 하고, GO 스텝 실패 시
success-only fold-back 업로드(`admission-check.yml:1349-1358`)가 스킵되므로 재시도도
끝내 콜드로 남는다 — 콜드 경합 확률을 누적하는 구조다.

## (d) 레인 transcript 소실 (결함)

`lane_run()`은 레인 stdout/stderr를 `/tmp/go-critical-lanes/<slug>/run.log`로
리다이렉트하고 어디에도 echo·업로드하지 않는다. 4개 적색 런의 실제 레인 에러 텍스트는
러너와 함께 영구 소실됐다. 봉쇄 PR은 #830(open — transcript 공개·업로드 + j4 잔여
봉쇄 + 실패 nimcache 환류; 재범위 대기 중).

## (e) CAS "no record"는 benign — 단, 창출 순서 취약성은 실재

`AXIOM_JUDGMENT_CAS: EXECUTED — no record for the current closure`
(`src/verification/judgment_cas.nim:1524-1526`)은 "캐시 판정 없음 → 신규 실행"의
정상 arming line이다. 다만 876 키 기록은 착지 MG의 attest+mint-publish 성공 후에만
append되고(유일 기록자: mint publish) MG만 레인을 실행하므로, "첫 착지 MG가 기록
창출자"인 설계가 신규 실행의 비결정 실패와 만나면 적색 루프가 자기영속된다 — 본
사건이 그 첫 재현이다.

## (f) 직렬 복원 판단 근거 — 검증된 regime으로의 회귀

- 직렬 regime의 신규(EXECUTED) 실행 실적은 최근에도 있다 — #826 랜딩 런 38512881300
  (04:43Z, pi 51s · s1a 306s · d2g 157s · d2p 33s 전 레인 pass)과 #827의 착지 시도
  4건(04:52–06:47Z, 직렬)이 세대 회전 직후의 콜드 신규 실행을 통과시켰다. 반면 병렬
  regime의 merge_group 실행 실적은 **green 0건**이다 — (a) 참조. 미검증 신규 경로를
  남겨 큐를 봉쇄하는 것보다 검증된 경로로의 회귀가 유일한 즉시 자구다.
- 리버트는 임시방편이 아닌 **사전등록된 회복 조항의 이행**이다:
  `docs/evidence/merge_latency_decision_prereg_2026-10-14.md` §5.1(원자 revert 1커밋
  + 표준 PR 수송 + org 핀 재회전 + golive, prereg-2026-10-13 (d)3 승계). 실행 차량은
  PR #829(head `a937f27f6`, 병합 `dc527994c` 16:14:46Z — evaluate 창 경유,
  전문: `emergency_evaluate_window_2026-10-14.md`).
- 병렬화 재도입은 (b)(c)(d) 봉쇄 후 **새 날짜 사전등록 문서**로만 가능하다(prereg
  §5.2). 문서 관측 아이러니: #828의 큐 봉쇄 기록 자체가 `2026-10-13_pr814_pr815_
  direct_merge_audit.md` §5에 남아 있다.

## 참조

F1(런 로그 포렌식)/F2(코드·계약 포렌식) 전문 — 세션 증거 보관
(`~/.kimi-code/sessions/wd_axiom2_76e38107d214/session_317eac81-d58e-48fb-82af-f6b0eb5c49dd/agents/main/tasks/agent-5tmqnny7/output.log`,
`agent-61235rhg/output.log`) · `docs/evidence/merge_latency_decision_prereg_2026-10-14.md` ·
`docs/evidence/emergency_evaluate_window_2026-10-14.md` · PR #826/#828/#829/#830

## 수정 (2026-10-15) — PR #830 상태 정정 (CLOSED unmerged)

> 위 원문(2026-10-14 측정)은 시점 기록으로 그대로 유지된다. 본 절은 이후 확정된
> 사실을 덧붙이는 것이며 원문을 개정하지 않는다 — `docs/spec/github_ruleset_api_quirks.md`
> «수정 (2026-10-15)»(PR #841)과 같은 추기 스타일이다.

- 원문 §(d)의 "봉쇄 PR은 #830(open — transcript 공개·업로드 + j4 잔여 봉쇄 + 실패
  nimcache 환류; 재범위 대기 중)"은 **시점이 지난 서술**로 판정된다. 2026-10-15 실측:
  PR #830은 **CLOSED unmerged**다(병합 없이 종료 — 충돌로 병합 불가 상태).
  재현: `gh pr view 830 --repo Archright/Axiom --json state,mergedAt,mergeCommit,mergeable,closedAt`
  → `{"state":"CLOSED","mergedAt":null,"mergeCommit":null,"mergeable":"CONFLICTING","closedAt":"2026-10-14T17:14:20Z"}`.
  §(d)가 지적한 레인 transcript 소실 결함 자체의 후속 처리는 본 정정의 범위가 아니다.

## 추가 정정 (2026-10-24) — §(d) transcript 소실 결함의 해소

> 원문(2026-10-14)과 2026-10-15 정정은 시점 기록으로 그대로 유지한다. 2026-10-15
> 정정이 "PR #830 상태" 주장(open → CLOSED unmerged)을 정정하고 레인 transcript
> 결함 자체의 후속 처리를 범위 밖으로 명시했다면, 본 절은 그 **결함의 상태**를
> 정정한다 — 이후 착지한 구조 변경으로 §(d)의 전제(레인 출력이 공유 job 안의
> 미공개 /tmp 파일로 붕괴)가 더 이상 성립하지 않음을 기록한다. 본 사건 전체의
> 해소가 아니라 §(d)의 관측·소실 메커니즘 전제만을 다룬다.

- (사실) 레인은 이제 공유 job 안의 shell 함수가 아니라 **독립 Actions job**이다 —
  `go-critical-lane` job(`.github/workflows/admission-check.yml:2935`)이
  `fail-fast: false`(`:2946`)와 `matrix: lane: [0, 1]`(`:2947-2948`, include:
  lane-0 = s1a 단독 / lane-1 = proof_integrity+d2_golden+d2_persist,
  `:2950-2956`)로 정의된다. 각 레인의 transcript는 job의 GitHub 네이티브
  로그다 — 워크플로 자체 주석: "every lane runs to completion and leaves its
  full GitHub-native job log … each lane IS a job; its transcript is the job's
  native log."(`:2917-2921`; 참조 `:1050` "Lane stderr is GitHub-native per-job
  logs"). 레인 판정 파일도 `always()`로 아티팩트 업로드된다(`[lane] Upload
  judgment files (post-mortem reachability — always)` `:3674-3694`, 보존 30일;
  nimcache `:3703`, 3일). 당시 4레인 shell이 2-lane job matrix로 재분할된 점
  (레인 수 자체의 변경)도 함께 기록한다.
- (시점) §(d)가 관측한 `lane_run()` + `/tmp/go-critical-lanes` 리다이렉트는
  2c94c9914(2026-10-14 13:15:11 +0900, 4레인 병렬화 reland)가 도입했고
  a937f27f6(2026-10-15 00:55:24 +0900)의 원자 revert로 제거됐다. 이후 G2
  재병렬화 승격 0848662fb(2026-10-16 03:21:27 +0900, PR #861 — 커밋 메시지가
  "#830 패턴"을 명시)는 취지로는 job-matrix였으나 **job 정의 블록이 파일에서
  누락된 채 착지**했다(당시 커밋 트리에 `go-critical-lane:` job·`matrix:`·
  `fail-fast: false` 전략 부재 — attest 측 배선과 주석만 존재), 그리고 같은 날
  91a4aee7c(2026-10-16 04:34:49 +0900 = 2026-10-15 19:34:49Z, PR #863
  "누락된 레인 job 정의 복원 + 핀 값 정정 — 세대 복구 (긴급)")이 473행 job
  블록을 추가했다. 따라서 **레인 transcript가 job native log로 성립한 최초
  커밋은 91a4aee7c**다. 사전등록:
  `docs/evidence/go_matrix_parallelization_prereg_2026-10-16.md`(`merge_latency_
  decision_prereg_2026-10-14.md` §8 레인 stderr always-전사 조항의 이행), S1
  수용 기록: `docs/evidence/go_matrix_s1_validation_2026-10-16.md`.
- (관측) 2026-10-24 merge_group green 런(admission-gate 40094087660,
  12:28:45Z 생성)에서 레인별 job이 독립 결론·독립 구간으로 존재한다:
  `attest / go-critical-lane (0)`(job 120872858800, success,
  12:30:03→12:42:02)와 `attest / go-critical-lane (1)`(job 120872858765,
  success, 12:30:03→12:36:51). lane-0 job 로그 266,649바이트를 jobs API로
  전수 회수했다 — 네이티브 보존 실증. 같은 날 적색 런 40049469259(01:22Z)에서도
  레인 2개는 각각 success로 별개 결론을 남겼고(적색 원인은 하류
  `verdict / admission-check`), §(d)의 전제와 반대로 레인 건강도가 job 단위로
  분리 관측된다. 다만 스캔 창(최근 ~300건 merge_group)에 레인 자체가 적색인
  사례가 없어 "실패 레인 transcript 생존"은 직접 관측하지 못했다.
- (남는 것) 구조 보장의 유효 기한과 범위는 남는다: (i) job 로그·아티팩트는 보존
  기한 내에서만 조회 가능하다(judgment 아티팩트 30일, nimcache 3일, job 로그는
  저장소 로그 보존 기한 — 기한 경과분은 회수 불가); (ii) 보장은 job 경계의
  구조적 성질이므로, 레인 **내부** 코드가 자신의 stdout/stderr를 파일로
  리다이렉트하고 echo하지 않으면 네이티브 로그에도 해당 텍스트는 보이지 않는다.
- 재현 명령:
  `gh api repos/Archright/Axiom/actions/runs/40094087660/jobs --paginate --jq '.jobs[] | select(.name|contains("go-critical-lane")) | "\(.id) | \(.name) | \(.conclusion)"'`
  · `gh api --allow-escape-sequences repos/Archright/Axiom/actions/jobs/120872858800/logs | wc -c`
  · `git log --format='%H %ci %s' -1 91a4aee7c`
  · `git show 2c94c9914:.github/workflows/admission-check.yml | grep -nE 'lane_run|go-critical-lanes' | head -3`
  · `sed -n '1050p;2917,2921p;2946,2956p;3674,3694p' .github/workflows/admission-check.yml`
