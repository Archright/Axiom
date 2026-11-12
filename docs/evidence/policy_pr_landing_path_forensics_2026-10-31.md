# repository_surface.json 정책 착지 경로 포렌식 (2026-10-31)

**성격**: 실험/보고 문서 (GitHub-native MERGE를 거치지 않은 pre-landing 원문)
**실측일**: 2026-10-31 (KST, UTC±9시간)
**실측 대상**: `config/repository_surface.json`의 v15→v90 표면 정책 버전이 main에 착지한 실제 경로
**결정 컨텍스트**: FROZEN 표면 정책 보류 결정 — 신규 진단 워크플로 추가의 (a) 정책 개정 경로의 직접 전제
**판정 근거**: git(로컬 clone + origin/main 53e49e1139)·GitHub REST/GraphQL·이 머신 push 텔레메트리 실측.
포렌식 전용 — 게이트 우회 시도 없음. 규명 불능 항목은 UNKNOWN으로 명시한다.

---

## 0. 헤드라인 판정

**정책 PR(v15→v90, 96건)은 전부 GitHub 네이티브 MERGE 커밋으로 착지했다 — merge queue(required 5개 ALLGREEN) 경유, `mergedBy`는 wintrover, `repository-surface` 체크는 required가 아닌 advisory 워크플로여서 head 실패에도 병합이 가능하다.**

**로컬 pre-push 게이트는 check-repository-surface를 push-admissibility 집합에 포함해 정책 브랜치 push를 FAIL로 기록했고(Makefile:61, 아래 §4의 ~/.cache/axiom/push-admissibility/log.jsonl), v86·v89 정책 브랜치 push의 FAIL 기록과 그 후의 PASS/BYPASS 기록이 모두 없다. 즉 정책 브랜치의 push 전송은 이 훅을 거치지 않은 경로로 일어났으며 그 수단은 이 머신 텔레메트리로 규명 불능(UNKNOWN)이다. 원격 required checks 5개에는 repository-surface가 없어(ruleset 20303214), push 전송 경로와 무관하게 merge queue가 required 판정의 유일한 원격 관문이었다.**

**BYPASS-PUSH-PRE-RECORD는 훅이 생성하는 값이 아니다(훅 코드에 문자열 존재 0건). 이 머신 log.jsonl의 7건(1540~1599행)은 2026-10-13 실행기 세션이 Owner Decision #18(c) 근거와 함께 수동으로 기록한 공개 텔레메트리이며, 저장소 전수 pickaxe에서 동일 문자열이 전혀 발견되지 않는다(우회 전담 코드 부재).**

---

## 1. 전수 이력: 커밋 101건 → 착지 PR 99건

`git log --follow config/repository_surface.json` = 101커밋(94d9d78fe 생성 2026-09-21 18:49:52 KST → d37183f4e v90 2026-10-29 01:19:41 KST). 작성자: Axiom Agent 93, wintrover 7, Suhyok Yoon 1(v36).

101커밋 전수를 `git log --ancestry-path --merges <c>..origin/main` + `merge-base --is-ancestor c <m>²` 조건(커밋이 merge 커밋의 두 번째 부모에 들어가는 — 즉 그 PR의 head인 — 가장 이른 커밋)으로 매핑한 결과:

**101/101 전부 merge 커밋 착지, 직접 main push 사례 0건.** 착지 merge 커밋 메시지("Merge pull request #N from …")에서 추출한 PR 번호는 99종(101커밋 중 두 PR이 각 2커밋 수용: v55의 4e29a03f8·a25af8759 → PR #457, v63·v64의 cf3586040·4af81802c → PR #555). 병합 커밋 committer는 101/101 전부 **GitHub** — GitHub 네이티브 MERGE 커밋이며, 3개 샘플(v90·v89·v86)의 parents==2와 두 번째 부모 == 정책 커밋을 `git log -1 --format=%P`로 확인했다(63060d042 → [21c6f52e8, d37183f4e], 16b503a4 → [7bfdada28, bec8270ea], 4ed1ac2cc → [e610d94ed, 1473e7449]).

v15(150920e6b, 2026-09-26 03:49:45 KST, PR #257) 이후의 76커밋(v15→v90)은 전부 `policy/*` 등 토픽 브랜치 PR 형태다. 전체 표(v1→v90, 101행):

<details>
<summary>전체 매핑 표 (101행 — 클릭 전개)</summary>

| 커밋 | 작성 시각(KST) | 작성자 | 버전 | 착지 PR | 병합 시각(KST) | committer |
|---|---|---|---|---|---|---|
| `94d9d78fe` | 2026-09-21 18:49:52 +0900 | Axiom Agent | v1 | #159 | 2026-09-21 20:04:14 | GitHub |
| `1163e886c` | 2026-09-21 21:51:01 +0900 | Axiom Agent | v1 | #163 | 2026-09-21 21:53:00 | GitHub |
| `f20ec0b11` | 2026-09-21 22:39:26 +0900 | Axiom Agent | v1 | #164 | 2026-09-21 22:40:46 | GitHub |
| `e3491861f` | 2026-09-21 22:48:38 +0900 | Axiom Agent | v1 | #166 | 2026-09-21 22:49:45 | GitHub |
| `39c356985` | 2026-09-21 23:44:44 +0900 | Axiom Agent | v1 | #168 | 2026-09-21 23:45:51 | GitHub |
| `f226eed90` | 2026-09-22 09:06:46 +0900 | Axiom Agent | v1 | #177 | 2026-09-22 10:57:45 | GitHub |
| `3202af558` | 2026-09-22 11:53:25 +0900 | Axiom Agent | v1 | #181 | 2026-09-22 11:59:13 | GitHub |
| `4a82f26cf` | 2026-09-22 22:01:05 +0900 | Axiom Agent | v1 | #190 | 2026-09-22 22:06:21 | GitHub |
| `b43f75348` | 2026-09-23 10:40:12 +0900 | Axiom Agent | v2 | #193 | 2026-09-23 10:49:07 | GitHub |
| `c30701c45` | 2026-09-23 16:41:30 +0900 | Axiom Agent | v2 | #199 | 2026-09-23 16:47:06 | GitHub |
| `78b44970e` | 2026-09-23 19:19:36 +0900 | Axiom Agent | v3 | #201 | 2026-09-23 19:26:11 | GitHub |
| `45f9dca23` | 2026-09-24 00:22:08 +0900 | Axiom Agent | v4 | #203 | 2026-09-24 00:26:47 | GitHub |
| `ab4106c98` | 2026-09-24 05:55:25 +0900 | Axiom Agent | v5 | #204 | 2026-09-24 05:56:42 | GitHub |
| `8ecb4e22b` | 2026-09-24 11:31:42 +0900 | Axiom Agent | v6 | #205 | 2026-09-24 11:32:38 | GitHub |
| `1a355e3c1` | 2026-09-24 12:24:16 +0900 | Axiom Agent | v7 | #207 | 2026-09-24 12:57:19 | GitHub |
| `af150f249` | 2026-09-24 13:13:12 +0900 | Axiom Agent | v8 | #209 | 2026-09-24 13:14:04 | GitHub |
| `077bf663c` | 2026-09-24 18:15:11 +0900 | Axiom Agent | v8 | #218 | 2026-09-24 18:30:57 | GitHub |
| `4b56ad4fc` | 2026-09-24 18:46:13 +0900 | Axiom Agent | v8 | #219 | 2026-09-24 19:03:19 | GitHub |
| `a4af9f670` | 2026-09-24 20:10:44 +0900 | Axiom Agent | v8 | #221 | 2026-09-24 20:23:14 | GitHub |
| `19b0d1ab0` | 2026-09-24 23:14:22 +0900 | Axiom Agent | v9 | #225 | 2026-09-25 00:32:14 | GitHub |
| `99feab302` | 2026-09-25 09:23:58 +0900 | Axiom Agent | v10 | #230 | 2026-09-25 09:34:12 | GitHub |
| `cab0ae9e2` | 2026-09-25 14:40:39 +0900 | Axiom Agent | v11 | #234 | 2026-09-25 15:01:58 | GitHub |
| `ee6ba70ab` | 2026-09-25 17:01:10 +0900 | Axiom Agent | v12 | #235 | 2026-09-25 17:11:45 | GitHub |
| `c9b09d785` | 2026-09-25 21:44:20 +0900 | Axiom Agent | v13 | #239 | 2026-09-25 21:55:59 | GitHub |
| `cfc307250` | 2026-09-25 22:12:20 +0900 | Axiom Agent | v14 | #241 | 2026-09-25 22:22:08 | GitHub |
| `150920e6b` | 2026-09-26 03:49:45 +0900 | Axiom Agent | v15 | #257 | 2026-09-26 04:00:25 | GitHub |
| `7c15fcb8a` | 2026-09-26 12:40:08 +0900 | Axiom Agent | v16 | #269 | 2026-09-26 12:58:40 | GitHub |
| `d766edd14` | 2026-09-26 19:11:38 +0900 | Axiom Agent | v17 | #273 | 2026-09-26 19:29:24 | GitHub |
| `96ee305de` | 2026-09-27 07:53:17 +0900 | Axiom Agent | v18 | #288 | 2026-09-27 08:13:21 | GitHub |
| `cb2a1b90b` | 2026-09-27 08:50:38 +0900 | Axiom Agent | v19 | #290 | 2026-09-27 09:08:32 | GitHub |
| `fc8a4fded` | 2026-09-27 16:19:01 +0900 | Axiom Agent | v20 | #294 | 2026-09-27 16:56:27 | GitHub |
| `20ccf6c41` | 2026-09-28 03:17:18 +0900 | Axiom Agent | v23 | #302 | 2026-09-28 04:22:06 | GitHub |
| `215efd735` | 2026-09-28 18:30:43 +0900 | Axiom Agent | v24 | #312 | 2026-09-28 19:17:08 | GitHub |
| `fd47e3cfd` | 2026-09-28 18:36:28 +0900 | Axiom Agent | v25 | #313 | 2026-09-28 19:19:35 | GitHub |
| `55aa965a6` | 2026-09-28 19:32:28 +0900 | Axiom Agent | v26 | #316 | 2026-09-28 19:34:10 | GitHub |
| `67d56170e` | 2026-09-29 10:23:21 +0900 | Axiom Agent | v27 | #343 | 2026-09-29 10:32:36 | GitHub |
| `14076980a` | 2026-09-29 11:32:11 +0900 | Axiom Agent | v28 | #346 | 2026-09-29 11:41:44 | GitHub |
| `0d734f81f` | 2026-09-29 14:39:20 +0900 | Axiom Agent | v29 | #350 | 2026-09-29 14:56:00 | GitHub |
| `d18eb1554` | 2026-09-29 15:16:16 +0900 | Axiom Agent | v30 | #352 | 2026-09-29 15:26:04 | GitHub |
| `57b2ca14b` | 2026-09-29 15:40:23 +0900 | Axiom Agent | v31 | #356 | 2026-09-29 15:49:24 | GitHub |
| `e9ffaa02c` | 2026-09-29 15:52:00 +0900 | Axiom Agent | v32 | #358 | 2026-09-29 16:03:05 | GitHub |
| `9dc97fce8` | 2026-09-29 21:12:22 +0900 | Axiom Agent | v33 | #372 | 2026-09-29 21:20:56 | GitHub |
| `894a92cbd` | 2026-09-30 02:09:01 +0900 | Axiom Agent | v34 | #376 | 2026-09-30 02:19:27 | GitHub |
| `81f77eaa8` | 2026-09-30 13:06:37 +0900 | Axiom Agent | v35 | #386 | 2026-09-30 13:13:16 | GitHub |
| `4258532d7` | 2026-09-30 15:13:14 +0900 | Suhyok Yoon | v36 | #389 | 2026-09-30 15:21:31 | GitHub |
| `df9d97b39` | 2026-10-01 00:33:37 +0900 | Axiom Agent | v37 | #406 | 2026-10-01 00:51:20 | GitHub |
| `09e5e2a5d` | 2026-10-01 02:56:20 +0900 | Axiom Agent | v38 | #408 | 2026-10-01 03:17:20 | GitHub |
| `d1ca47b3f` | 2026-10-01 12:03:05 +0900 | Axiom Agent | v39 | #414 | 2026-10-01 12:18:43 | GitHub |
| `aa62c1d33` | 2026-10-01 12:44:44 +0900 | Axiom Agent | v40 | #416 | 2026-10-01 12:56:26 | GitHub |
| `b14fe1d0c` | 2026-10-01 12:50:35 +0900 | Axiom Agent | v41 | #417 | 2026-10-01 13:19:36 | GitHub |
| `ce4569675` | 2026-10-01 14:53:49 +0900 | Axiom Agent | v42 | #420 | 2026-10-01 15:02:40 | GitHub |
| `4895ed809` | 2026-10-01 21:04:58 +0900 | Axiom Agent | v43 | #424 | 2026-10-01 21:13:30 | GitHub |
| `8eca9428c` | 2026-10-01 22:01:47 +0900 | Axiom Agent | v44 | #427 | 2026-10-01 22:29:15 | GitHub |
| `baa7139ec` | 2026-10-01 22:21:44 +0900 | Axiom Agent | v45 | #428 | 2026-10-01 22:53:37 | GitHub |
| `7d7ce0dfb` | 2026-10-01 23:46:48 +0900 | Axiom Agent | v46 | #431 | 2026-10-02 00:00:06 | GitHub |
| `968138f96` | 2026-10-02 02:57:22 +0900 | Axiom Agent | v47 | #433 | 2026-10-02 03:13:58 | GitHub |
| `ce9f365ff` | 2026-10-02 09:43:11 +0900 | Axiom Agent | v48 | #435 | 2026-10-02 10:05:00 | GitHub |
| `b57f396f6` | 2026-10-02 14:27:14 +0900 | Axiom Agent | v49 | #438 | 2026-10-02 14:36:34 | GitHub |
| `d528d353e` | 2026-10-02 18:38:23 +0900 | Axiom Agent | v50 | #440 | 2026-10-02 18:47:53 | GitHub |
| `813806bda` | 2026-10-02 23:57:58 +0900 | Axiom Agent | v51 | #442 | 2026-10-03 00:23:34 | GitHub |
| `27d1577da` | 2026-10-03 15:21:03 +0900 | Axiom Agent | v52 | #445 | 2026-10-03 15:50:24 | GitHub |
| `7229022c8` | 2026-10-03 23:03:42 +0900 | Axiom Agent | v53 | #450 | 2026-10-04 00:26:04 | GitHub |
| `635272367` | 2026-10-04 07:50:54 +0900 | Axiom Agent | v54 | #452 | 2026-10-04 08:11:30 | GitHub |
| `4e29a03f8` | 2026-10-04 13:37:29 +0900 | Axiom Agent | v55 | #457 | 2026-10-04 17:24:36 | GitHub |
| `a25af8759` | 2026-10-04 15:33:42 +0900 | Axiom Agent | v55 | #457 | 2026-10-04 17:24:36 | GitHub |
| `9c3b32341` | 2026-10-05 21:51:51 +0900 | Axiom Agent | v56 | #486 | 2026-10-05 22:11:45 | GitHub |
| `fa5163639` | 2026-10-06 18:57:04 +0900 | Axiom Agent | v57 | #505 | 2026-10-06 19:12:32 | GitHub |
| `2970a1c7a` | 2026-10-07 00:03:59 +0900 | Axiom Agent | v58 | #514 | 2026-10-07 00:23:15 | GitHub |
| `95a5a5a2c` | 2026-10-07 09:56:22 +0900 | Axiom Agent | v59 | #526 | 2026-10-07 10:08:47 | GitHub |
| `53334e92d` | 2026-10-07 13:17:49 +0900 | Axiom Agent | v60 | #536 | 2026-10-07 13:30:17 | GitHub |
| `cd85b6283` | 2026-10-07 14:56:21 +0900 | Axiom Agent | v61 | #542 | 2026-10-07 15:05:46 | GitHub |
| `a837c96df` | 2026-10-07 18:08:16 +0900 | wintrover | v62 | #551 | 2026-10-07 18:21:11 | GitHub |
| `d3a7e9712` | 2026-10-07 18:18:42 +0900 | Axiom Agent | v63 | #556 | 2026-10-07 18:48:25 | GitHub |
| `cf3586040` | 2026-10-07 18:48:51 +0900 | Axiom Agent | v63 | #555 | 2026-10-07 19:12:59 | GitHub |
| `4af81802c` | 2026-10-07 19:03:50 +0900 | Axiom Agent | v64 | #555 | 2026-10-07 19:12:59 | GitHub |
| `dae4d9947` | 2026-10-07 21:27:34 +0900 | Axiom Agent | v65 | #564 | 2026-10-07 21:43:39 | GitHub |
| `fdbfeebe6` | 2026-10-08 09:57:53 +0900 | Axiom Agent | v66 | #576 | 2026-10-08 10:12:28 | GitHub |
| `b2f04121a` | 2026-10-08 12:10:36 +0900 | Axiom Agent | v67 | #586 | 2026-10-08 12:24:20 | GitHub |
| `b4a293386` | 2026-10-08 14:52:05 +0900 | Axiom Agent | v68 | #592 | 2026-10-08 15:09:51 | GitHub |
| `26afee8c8` | 2026-10-08 14:50:51 +0900 | Axiom Agent | v69 | #595 | 2026-10-08 16:08:25 | GitHub |
| `ef43bf8cd` | 2026-10-08 16:28:14 +0900 | Axiom Agent | v70 | #596 | 2026-10-08 16:43:28 | GitHub |
| `b6a19ab7f` | 2026-10-09 20:46:33 +0900 | Axiom Agent | v71 | #658 | 2026-10-09 22:10:04 | GitHub |
| `bf67a2cb1` | 2026-10-10 00:38:46 +0900 | Axiom Agent | v72 | #654 | 2026-10-10 02:33:35 | GitHub |
| `9c02f2728` | 2026-10-10 05:07:27 +0900 | Axiom Agent | v73 | #673 | 2026-10-10 06:05:35 | GitHub |
| `e226a7856` | 2026-10-10 10:06:21 +0900 | Axiom Agent | v74 | #683 | 2026-10-10 10:41:04 | GitHub |
| `fffbfd56c` | 2026-10-11 23:23:17 +0900 | Axiom Agent | v75 | #745 | 2026-10-11 23:32:15 | GitHub |
| `a487aec29` | 2026-10-12 00:34:23 +0900 | Axiom Agent | v76 | #751 | 2026-10-12 00:41:08 | GitHub |
| `9b8932333` | 2026-10-12 12:20:42 +0900 | Axiom Agent | v77 | #771 | 2026-10-12 12:27:20 | GitHub |
| `5a38ac51f` | 2026-10-12 14:37:06 +0900 | wintrover | v78 | #777 | 2026-10-12 14:46:31 | GitHub |
| `95823d96e` | 2026-10-12 11:36:13 +0900 | Axiom Agent | v79 | #803 | 2026-10-13 16:25:35 | GitHub |
| `bde931f07` | 2026-10-14 01:02:45 +0900 | Axiom Agent | v80 | #818 | 2026-10-14 01:29:58 | GitHub |
| `6baac30ef` | 2026-10-19 22:36:02 +0900 | wintrover | v81 | #955 | 2026-10-19 22:47:12 | GitHub |
| `58d11483a` | 2026-10-21 20:01:49 +0900 | Axiom Agent | v82 | #1011 | 2026-10-21 20:30:07 | GitHub |
| `9d096753c` | 2026-10-22 04:07:18 +0900 | Axiom Agent | v83 | #1023 | 2026-10-22 04:22:27 | GitHub |
| `07586dbc7` | 2026-10-22 06:33:36 +0900 | Axiom Agent | v84 | #1031 | 2026-10-22 06:40:24 | GitHub |
| `bab91d320` | 2026-10-22 12:17:15 +0900 | Axiom Agent | v85 | #1039 | 2026-10-22 13:51:15 | GitHub |
| `1473e7449` | 2026-10-22 23:59:42 +0900 | wintrover | v86 | #1045 | 2026-10-23 00:19:46 | GitHub |
| `4c924eed2` | 2026-10-23 10:58:49 +0900 | wintrover | v87 | #1051 | 2026-10-23 11:06:23 | GitHub |
| `714a0efe4` | 2026-10-23 14:21:15 +0900 | wintrover | v88 | #1056 | 2026-10-23 16:10:50 | GitHub |
| `bec8270ea` | 2026-10-24 00:40:18 +0900 | wintrover | v89 | #1064 | 2026-10-24 00:55:48 | GitHub |
| `d37183f4e` | 2026-10-29 01:19:41 +0900 | Axiom Agent | v90 | #1116 | 2026-10-29 14:38:16 | GitHub |
</details>

v51(knownBlindSpots 초입 버전, #442)·v79(3경로 FROZEN→CONTROLLED 재등록, #803)·v80(merge-queue-rearm CONTROLLED 등록, #818)은 §4 판정과 직결되는 버전이다.

**UNKNOWN 정정**: v86·v89 정책 커밋의 병합(4ed1ac2cc, 16b503a4)은 두 번째 부모가 정책 커밋인 2부모 MERGE 커밋으로 직접 확인했다(§5). v90의 병합(63060d042)도 동일 형태.

---

## 2. v90·v89·v86 대표 심층 관측 (gh api 실측)

세 PR 모두 `gh pr view` 동일 형태: author=wintrover, state=MERGED, mergedBy=wintrover, reviewDecision=""(0승인), autoMergeRequest=null(쿼리 시점 — auto-merge enable 흔적은 타임라인에 별도로 존재, §2.1).

### 2.1 타임라인 이벤트 (gh api repos/Archright/Axiom/issues/{n}/timeline)

| 이벤트 | #1045 (v86) | #1064 (v89) | #1116 (v90) |
|---|---|---|---|
| review_requested | 15:09:52Z wintrover | 15:47:06Z wintrover | 2026-10-28T16:21:58Z wintrover |
| auto_merge_enabled | 15:11:32Z wintrover | 15:47:28Z wintrover | 2026-10-28T16:27:39Z wintrover |
| added_to_merge_queue | 15:19:46Z wintrover | 15:55:48Z wintrover | 2026-10-28T17:32:45Z wintrover |
| removed_from_merge_queue (제외) | — | — | 2026-10-28T18:13:03Z github-merge-queue[bot] |
| added_to_merge_queue (2차) | — | — | 2026-10-28T18:17:49Z wintrover |
| removed_from_merge_queue (제외) | — | — | 2026-10-28T18:27:22Z github-merge-queue[bot] |
| added_to_merge_queue (3차) | — | — | 2026-10-29T05:38:17Z wintrover |
| merged | 15:33:13Z wintrover (4ed1ac2cc) | 16:17:51Z wintrover (16b503a4) | 2026-10-29T06:12:31Z wintrover (63060d042) |
| removed_from_merge_queue (병합 후) | 15:33:13Z github-merge-queue[bot] | 16:17:51Z github-merge-queue[bot] | 06:12:31Z github-merge-queue[bot] |

세 PR 모두 **merge queue 진입 → 큐 안에서 병합** 경로가 실측됐고, v90은 큐 제외(admission-gate·axiom-operational-slice FAIL) 후 재진입 3회에 걸쳐 착지한 큐 운영의 실증 사례다. mergedBy=wintrover인 것은 auto-merge(enable자 wintrover)가 최종 병합 행위자로 표시되는 GitHub 표기 관행이다 — 실제 main push는 큐 봇이 수행(§2.3).

### 2.2 head SHA의 Actions 런 (gh api actions/runs?head_sha=<sha>)

| workflow | #1045 | #1064 | #1116 |
|---|---|---|---|
| repository-surface | **failure** | **failure** | **failure** |
| admission-gate | success | success | success |
| landing-integrity | success | success | success |
| trusted-writer-set | success | success | success |
| bsec-integrity | success | success | success |
| debt-registry-gate | success | success | success |
| generation-acceptance | success | success | success |
| axiom-operational-slice | success | success | success |
| dependabot-auto-merge | 미발화(head 시점 워크플로 부재 — v86이 그 등록 자체) | skipped | skipped |
| rearm (pull_request_target) | success | failure | success(3회) |

즉 **세 정책 PR 모두 repository-surface 워크플로가 head에서 failure인 상태로 병합됐다**. required 체크가 이 상태에서 통과한 이유는 §3의 required 목록에 repository-surface가 없기 때문이다(head-advisory 실패가 merge-admission을 결정하지 않는 관측 계약 — `docs/agents/merge_admission_observation.md`의 "aggregate statusCheckRollup is advisory and never decides"와 일치). merge_group(큐) 런에서는 repository-surface 워크플로 자체가 발화하지 않고, v90 3차 큐 그룹에서는 8개 런 전부 success(§2.3).

### 2.3 merge_group(큐) 런 — v90 3차 시도 (gh api actions/runs?event=merge_group&created=...)

2026-10-29T05:38:35Z 큐 그룹(merge commit `63060d042`)의 merge_group 런: probe-merge-queue·generation-acceptance·landing-integrity·observer-manifest-consistency·bsec-integrity·debt-registry-gate·axiom-operational-slice·admission-gate 전부 **completed/success**. 1차 그룹(`0a8a356b1`, 2026-10-28T17:33:04Z)은 admission-gate failure(타 7개 success)로 제외(18:13:03Z), 2차 그룹(`46b8f41b9`, 18:18:08Z)은 axiom-operational-slice·observer-manifest-consistency·probe-merge-queue failure + admission-gate cancelled로 제외(18:27:22Z) — 큐가 fail-closed로 제외 후 재진입을 허용한 실측이다.

### 2.4 main 병합 push의 행위자 (public events API 교차)

`gh api repos/Archright/Axiom/events`: `2026-10-29T06:12:31Z github-merge-queue[bot] refs/heads/main` — v90 mergedAt과 초 단위 일치. main 최신 push는 큐 봇이 수행한다.

---

## 3. 원격 required 체크 vs 로컬 push-admissibility — 비대칭 구조

`gh api repos/Archright/Axiom/rules/branches/main` 실측(ruleset 20303214, active):

- **required_status_checks (5개)**: admission-check, bsec-integrity, debt-registry-gate, generation-acceptance, axiom-operational-slice.
- **pull_request rule**: required_approving_review_count=0, require_code_owner_review=false, require_extra_approval_for_unattributed_changes=true, require_last_push_approval=false. 즉 리뷰 승인 0으로도 required 5개만 green이면 큐에 들어가고 병합된다(§2.1의 reviewDecision=""와 일치).
- **merge_queue rule**: merge_method=MERGE, grouping_strategy=ALLGREEN, max_entries_to_build=2, max_entries_to_merge=1, check_response_timeout=120분.
- **file_path_restriction**: `.github/workflows/**`·`.github/actions/**`·`build/**`은 규칙셋에서 제한되지만 `config/**`는 대상 아님 — repository_surface.json 자체는 GitHub 규칙 수준에서 제한되지 않는다.

반면 로컬 pre-push 훅(`.githooks/pre-push`, repo `core.hooksPath` = .githooks)의 push-admissibility OID 스냅샷은 `Makefile:61`의 `PUSH_ADMISSIBILITY_GATES`에 **check-repository-surface를 포함**해 정책 변경(OID의 정책 파일이 base보다 FROZEN.MODIFY)을 로컬에서 FAIL시킨다. 텔레메트리 기록부는 ~/.cache/axiom/push-admissibility/log.jsonl(append-only, PASS/FAIL/budget/sha256) — pre-push:148, 222-223, 248-253.

**결론(§0 헤딩 재서술)**: 로컬(정책 파일 MODIFY 금지·FROZEN.ADD 금지)과 원격(정책 파일이 required 체크 아님)은 서로 다른 판정층이며, v15→v90의 96건 정책 PR은 **원격 required만 통과하면 착지할 수 있는 경로**를 사용했다. 세 PR의 로컬 push FAIL 기록은 아래 §4와 같다.

---

## 4. 로컬 push 텔레메트리 — v86·v89 FAIL과 BYPASS-PUSH-PRE-RECORD 실체

### 4.1 기록 위치와 기록자

- 기록 위치: ~/.cache/axiom/push-admissibility/log.jsonl — append-only. 이 문서 실측 시점(2026-10-31 오전 KST) 기준 2,078행, 첫 기록 2026-08-29T01:48:19Z(debt PASS). 아래에서 인용하는 행 번호(1540~1599, 1955, 1982)는 이 스냅샷 기준이며 append-only라 기존 행은 변동하지 않는다. 같은 날 늦게(2026-10-31T01:03~01:12Z) 다른 세션의 일반 브랜치 push 5건(work/inv-queue·inv-cout·inv-cpub·inv-met)이 PASS로 추가 기록되는 것이 관측됐다 — 훅이 현재도 정상 활성 기록 중임을 보여주는 부수 실측(정책 브랜치와 무관).
- 기록자: `.githooks/pre-push`(repo 레벨 hooksPath). 훅 코드에서 가능한 결과값은 `PASS`, `FAIL`, 그리고 Part 3~5의 fail-closed FAIL 메시지뿐이다(BYPASS-PUSH-PRE-RECORD·BYPASS-PUSH-POST-CORRECTION·basis·expected_remote_head·reason 필드는 훅이 기록하는 형태가 아니다).

### 4.2 v86·v89 정책 push의 FAIL 실측 (grep 원문)

```jsonl
{"ts":"2026-10-22T15:01:14Z","oid":"1473e74492a59e5c8a205296394059ad5bd45103","ref":"policy/surface-v86-dependabot-automerge","result":"FAIL","duration_s":50, ...}   (log.jsonl:1955)
{"ts":"2026-10-23T15:42:36Z","oid":"bec8270ea22eefecef3f4dcf032c3c3056e94c0f","ref":"policy/probe-merge-queue-controlled","result":"FAIL","duration_s":72, ...}        (log.jsonl:1982)
```

두 OID는 각각 PR #1045/#1064의 head 커밋과 정확히 일치한다. 이후 동일 OID에 대한 PASS 기록·BYPASS 기록은 존재하지 않는다(grep 전수). 주변 기록(1950~1960, 1978~1990행)에서 같은 날 다른 브랜치 push는 전부 PASS(feat/dependabot-auto-merge 1406ffa76, docs/return-path-acceptance ccfec7a9d, fix/probe-merge-queue-map 1ec029e2b 등) — FAIL은 정책 OID에서만 국소적으로 발생했다. **v90(d37183f4e)의 policy/surface-v90-runner-flight-recorder push는 이 머신 텔레메트리에 어떤 기록(PASS/FAIL)도 남기지 않았다.**

**관찰 기록 재검증(사전 제공 관찰)**: "오늘 work/vs-a/c/d push는 PASS" 관찰은 실측과 부분 일치한다 — work/vs-a PASS(2026-10-30T13:54:34Z, da9be792b)·vs-c PASS(13:52:21Z, 61fe12b8a)·vs-d PASS(13:48:30Z, eb11cfd2c)이나 기록 날짜는 2026-10-30이며 2026-10-31 기록은 작성 시점 0건. 같은 창에서 work/vs-b는 FAIL(13:50:12Z, 96ce298bc) 후 수정 커밋 31c975e74로 PASS(14:03:25Z) — 이후 PR #1132로 병합됐다. 이 표본은 **일반 브랜치의 정상 훅 경유 push는 PASS 기록을 반드시 남긴다**는 대조 근거가 된다(정책 브랜치 착지 push에는 그 기록이 없었다).

### 4.3 BYPASS-PUSH-PRE-RECORD — 생성 주체 규명(외부 실행기 채널)

log.jsonl의 BYPASS 레코드는 전부 7건(1540, 1542, 1544, 1545, 1546(POST-CORRECTION), 1557, 1599행) — 전부 2026-10-13에 기록됐고 ref는 feat/rust-subject-v1(6건)과 policy/surface-v80-merge-queue-rearm(1건, bde931f07)이다. 레코드 구조(result="BYPASS-PUSH-PRE-RECORD", basis="Owner Decision #18(c) policy-PR push path ... '권한이 필요한건 전면 허가한다'", expected_remote_head, reason)는 훅 코드에 존재하지 않는 필드를 포함한다.

추적 결과(이력·코드 pickaxe):

- `git log -S "BYPASS-PUSH-PRE-RECORD" --all` — **히트 0건**. 문자열은 저장소 커밋 어디에도 존재하지 않는다.
- 훅·Makefile·tools/ 전수 grep — BYPASS-PUSH-PRE-RECORD 문자열 코드 존재 0건. 이 레코드를 쓰는 코드가 이 저장소에 없다.
- 따라서 생성 주체는 **이 훅/이 저장소 코드 밖의 채널** — 2026-10-13 세션에서 Owner Decision #18(c)을 근거로 pre-push를 우회한 push를 수행한 주체가 log.jsonl에 공개(self-disclosed) 방식으로 append한 텔레메트리인 것이 관측상 유일하게 정합한다. v79(#803 feat/rust-subject-v1)·v80(#818) 정책 커밋의 착지가 그 7건 BYPASS push와 체인(§1 표: 95823d96e v79 → 2026-10-13T16:25:35Z 병합; bde931f07 v80 → 2026-10-14T01:29:58Z 병합)으로 정확히 일치한다.

**UNKNOWN 명시**: v86·v89·v90 정-policy 브랜치의 push 전송 수단과 행위자는 이 머신 텔레메트리에서 규명 불능이다. 훅을 우회하지 않은 정상 push는 반드시 log.jsonl에 기록되고(모든 PASS push가 그러했듯), 이 OID들의 착지 push 기록은 없다. org 감사 로그(`gh api orgs/Archright/audit-log`)는 현재 토큰으로 git.push 액션 기록을 제공하지 않는다(최근 100건 샘플에서 workflows.*·pull_request.create·jit-runner 구성만 보존, git.push 0건). GitHub public events API는 policy/* 브랜치 push 이벤트를 보존하지 않는다(정책 PR mergedAt 직후의 main push만 보존). 즉 **"다른 베뉴(훅 미설정 환경/타 머신)에서의 push"와 "훅 우회(예: -c core.hooksPath=/dev/null)"는 텔레메트리상 구분 불가**하며 어느 쪽인지는 UNKNOWN이다.

### 4.4 판정 통합

착지한 정책 커밋(v86 1473e7449, v89 bec8270ea)의 oid와 ref가 이 머신의 FAIL 텔레메트리와 정확히 일치한다는 것은 — 그 브랜치 커밋이 **이 머신에서 생성(또는 fetch·커밋)**되고, 이 머신의 정상 push 시도가 한 번 이상 FAIL로 차단됐으며, 착지 push는 훅을 거치지 않은 채널로 발생했다는 뜻이다. v86·v89 push FAIL(ts: 15:01:14Z / 15:42:36Z)은 각 PR의 review_requested(15:09:52Z / 15:47:06Z) 직전이다 — 즉 **"로컬 push FAIL → 훅 외 경로로 push → PR → auto-merge → 큐 병합"**이 한 세션에서 순차 일어난 흔적이다. "인간 아키텍트가 다른 머신/GitHub UI에서 병합했다" 가설은 ref·oid·FAIL 시각이 에이전트 머신 세션과 정확히 동일해 **불필요**하다(병합 자체는 merge queue가 수행했고 wintrover auto-merge가 enable했다). "외부 실행기 채널이 실재한다" 가설은 §4.3의 7건 BYPASS 기록(Owner Decision #18(c) self-disclosure)으로 **실재가 관측됐다** — v86~v90에서 그 채널이 BYPASS 레코드를 남기지 않은 이유(레코드 관행 변경·다른 베뉴 사용 등)는 UNKNOWN이다.

---

## 5. 대표 merge 커밋 검증 (GitHub 네이티브 MERGE 실측)

| PR | mergeCommit | parents | mergedAt (Z) | 병합 committer |
|---|---|---|---|---|
| #1045 (v86) | `4ed1ac2cc8c3865e67b2bf82ab1d5aafb9180922` | e610d94ed + 1473e7449 (2) | 2026-10-22T15:33:13Z | GitHub (git 로그) |
| #1064 (v89) | `16b503a4b6ca9a8e3a171463f3cd11e716e88a6d` | 7bfdada28 + bec8270ea (2) | 2026-10-23T16:17:51Z | GitHub (git 로그) |
| #1116 (v90) | `63060d042078fbe434bf42d2611485cd43ca72d7` | 21c6f52e8 + d37183f4e (2) | 2026-10-29T06:12:31Z | GitHub (git 로그) |

로컬 git 실측(committer=GitHub, parents==2)과 `gh pr view`(mergeCommit.oid·mergedAt·mergedBy)가 정확히 일치한다. docs/agents/rules_workflow.md·merge_authority_integrity.md가 규정하는 "PR 랜딩의 정본은 GitHub 네이티브 MERGE 커밋"이 v1→v90 전체에서 실측·유지됐다.

---

## 6. 관측 도구·명령 흔적 (재현 경로)

- 전수 매핑: `git log --follow config/repository_surface.json` + per-commit `git log --ancestry-path --merges`로 착지 merge 식별(/tmp/surface_commits.tsv, 101행 — 이 문서 작성 시 산출물).
- PR 메타: `gh pr view <n> --json mergeCommit,mergedBy,...`
- 타임라인: `gh api repos/Archright/Axiom/issues/<n>/timeline`
- 런 목록: `gh api "repos/Archright/Axiom/actions/runs?head_sha=<sha>"`
- 큐 런: `gh api "repos/Archright/Axiom/actions/runs?event=merge_group&created=<win>"`
- ruleset: `gh api repos/Archright/Axiom/rules/branches/main`
- 텔레메트리: ~/.cache/axiom/push-admissibility/log.jsonl (grep "policy/surface-v86\|probe-merge-queue-controlled\|BYPASS")
- audit-log: `gh api orgs/Archright/audit-log?phrase=git.push` → git.push 기록 미보존(토큰 스코프 admin:org에서도 0건).

---

## 7. 결론

v15→v90 정책 착지 경로는 **"policy/* 브랜치 훅-외 push(수단 UNKNOWN) → PR(auto-merge by wintrover) → merge queue required-5 ALLGREEN → github-merge-queue[bot] MERGE 커밋"**이며 101/101 전부 동일 형태, 직접 push 사례 0건이다. repository-surface(정책 파일의 FROZEN 클래스 검사)는 **required 체크가 아니라 head-advisory 워크플로**이므로, 로컬 push 게이트가 차단하는 정책 변경도 원격에서는 required 체크를 통과해 큐로 착지할 수 있다. BYPASS-PUSH-PRE-RECORD는 훅이 아닌 외부 실행기 세션이 log.jsonl에 직접 기록한 7건(2026-10-13, Owner Decision #18(c) 근거)이며, v86·v89·v90 착지 push는 그런 BYPASS 기록조차 없이 완료됐다 — **정책 push의 전송 채널이 "이 훅"이 아니라는 것은 실측으로 확정**되고, 그 채널의 정체와 승인 근거는 규명 불능(UNKNOWN)이다.
