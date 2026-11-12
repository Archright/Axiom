# L3-GO 구현 착지 증거 — admission-independents 잡 분할 (2026-11-04)

> 사전등록: `docs/evidence/l3_go_prereg_2026-11-03.md` (§0–§11).
> 본 문서는 Phase C 구현의 기계 관측 증거를 기록한다. 선언·주장은 증거가
> 아니다 — 아래 모든 수치는 명령으로 재생산 가능하다 (§7).

## §1. 인간 승인 (MUST-T2 §8 — 원문)

- **승인 원문**: "승인한다" — 2026-11-04, 승인자 **wintrover** (인간 아키텍트).
  컨텍스트: Phase C/D 구현·세대 전환 진행 권한 요청에 대한 응답.
- **기록자 ≠ 승인자**: 본 문서의 작성자는 agent(wintrover의 대리 실행자)다.
  승인은 사용자 메시지로 수령했고 agent가 자가 승인하지 않았다.
- **MUST-T2a 위임 사슬** (수동 병합 대행의 근거): 사용자 원문
  "대행을 원해" (2026-11-04) + "권한이 필요한 부분은 전면 승인한다"
  (2026-11-04). 위임 병합 수행 주체는 agent under explicit per-PR
  delegation from wintrover로 기록한다.
- **per-PR 위임 기록**: **PR #1264** (implementation commit `cecc84ead`, 본 위임 기록
  커밋 포함) — 위임 병합 수행 주체: agent under explicit per-PR delegation
  from wintrover. 위임 시점 사용자 원문: "대행을 원해" + "권한이 필요한
  부분은 전면 승인한다" (2026-11-04).

## §2. 구현 결과 (관측)

**브랜치**: `work/l3-go-split-2026-11-04` (base `50d781e82f6a90058a610dc92db99453ea3fd676` = PR #1262 merge). 사전분할 원본은 `/tmp/pre_split_admission.yml`에 보존 (대비 검증용).

**잡 위상** (5잡): `build-base-artifacts` → {`admission-independents`, `go-critical-lane`} → `admission-check` → `go-critical-rollup`.

- `admission-check`: `needs: [build-base-artifacts, go-critical-lane, admission-independents]` — 잡 `if`는 `!cancelled()`로 교체(prereg §2.4: skipped=Success 플랫폼 시맨틱 대응). 잡 env 7종(B, H, HEAD_TREE_OID, MERGE_TREE_OID, SUBJECT_HEAD, SUBJECT_HEAD_TREE_OID, SUBJECT_ID)은 needs outputs 공급으로 전환(값 채널). `[guard] Every direct need must be success` 스텝이 [venue] 직후 배치 — needs 3종 전원 `success` 아니면 fail-closed.
- `admission-independents` (job2a): `needs: [build-base-artifacts]`, `if: !cancelled() && (PR|workflow_call|merge_group) && inputs.stage == 'attest'`, outputs 7종, timeout 45, 스텝 13개. 이동 스텝 4종 + preamble 재지불(B 체크아웃·슬라이스 엔진·H 체크아웃·아티팩트 다운로드·매니페스트 검증) + `[independents] Export identity values`(값 채널) + `[independents] Upload evidence chain`(파일 채널, success-only).

**이동 4스텝 바이트 동일성** (sha256(run) — 사전분할 원본 대비 EQ):

| 스텝 | sha256(run) |
|---|---|
| [check] Core purity gate | `c99c993ba78baaa78c0257c1aec7078b5daee6aaedd8e4457a3470147ee17974` |
| [check] Re-derive admission identity | `5627c901a314f5631c04a3b9fb00e56e22c35a8154e6722ced24be039d9bd411` |
| [check] Stage D9 evidence | `d158262c8a9740973c2f21eb1f2189b692517c7acc68f524d04a1f1fba50b309` |
| [check] Register subject | `f422b2e25960196a97304195173ed3e315e15a23a6d070bbb2d60dd65d7c599f` |

run/if/env 전부 EQ (수술 스크립트 `tmp/l3_split_surgery.py`). witness(`Attest witness-only`, `Upload admission records`의 always() 엣지 포함)는 GO 결과 뒤 admission-check 잔류 — prereg §2.5 준수.

**파일 채널**: 업로드 `[independents] Upload evidence chain`과 다운로드 `[check] Download admission-independents evidence`의 아티팩트명 양측 동일 — `admission-independents-${{ github.event.pull_request.head.sha || github.event.merge_group.head_sha || github.sha }}-${{ github.run_attempt }}` (run-scoped). upload는 `if-no-files-found: error`·`continue-on-error` 없음·성공시에만 업로드(극장 방지 — §0.9).

**카운트 실측** (python3 yaml — 테스트와 동일 추출):

- landing-gated 스텝: build-base 9 + admission-check 19 + job2a 6 = **34** (2잡 스캔 28).
- preamble 출현수: B 체크아웃/매니페스트 검증/아티팩트 다운로드 각 3회(admission-check·job2a·go-critical-lane), 슬라이스 엔진 4회(+build-base), H 체크아웃 2회(admission-check·job2a).

## §3. A2 원자 페어 회전 (동일 커밋 착지)

| 파일 | 위치 | 구핀 → 신핀 |
|---|---|---|
| `config/trusted_writer_set.json` | trustedAdmissionWorkflowSha | `f0bb8fb5b839770bf8e53639f3c2cb99997447d4` → `407b507cfea81e5c8fe3f38187e088bd9cbe18ca` |
| `config/policy/epoch_manifest.json` | productionExecutionPin | 동일 페어 |

`git hash-object .github/workflows/admission-check.yml` = `407b507cfea81e5c8fe3f38187e088bd9cbe18ca` (3-way 일치 — test_admission_venue_split.nim A2 suite가 자동 검증). 구핀 참조는 위 2파일 + data/ci_provider 감사 기록(수정 금지)뿐.

## §4. 부정시험 (a) — test_l3_guard_fail_closed.nim

`tests/ci/test_l3_guard_fail_closed.nim` — **16/16 통과** (Makefile test-unit :1092 등록).

- 구조 11: 가드 배치([venue] 직후)·이동 스텝 if 정확치·잡 env 매핑(needs outputs)·cut-not-copy(잔류 중복 없음)·바이트 해시 핀 4종·값/파일 채널·witness 잔류(admission-check)·Q4(보간 토큰 부재).
- 양면 oracle 4: GREEN 경로(정상 입력 합성 판정 로직 통과) + RED 격자(3잡 × 5 비정상 상태 {failure, cancelled, skipped, "", Success} 귀속 검증) + 전비정상 상태 + `set -u` 미공급 환경변수 폭발.
- 테스트가 복제한 가드 로직이 아니라 워크플로우의 실제 guard run 본문을 추출·실행한다 (재구현 아님).

## §5. 기존 구조 테스트 재핀 (소급 정정 포함)

| 테스트 | 결과 | 재핀 내용 |
|---|---|---|
| `test_admission_check_stages.nim` | 10/10 | 잡 가드 `always()` → `!cancelled()` 핀(prereg §2.4); preamble 3×/엔진 4×; H 체크아웃 2출현 per-occurrence 검사(stepIfs) |
| `test_admission_venue_split.nim` | 22/22 (freeze 대비 1건 [SKIPPED] — 태그 부재 결정적 강등) | AdmissionJobs 3잡 확장; [venue] 5잡; 카운트 핀 33→**34**; heavy-steps 스코프 재배치(이동 3종 job2a, 가드+핸드오프 다운로드 admission-check); identity·purity 잡 경로 변경; Admitted +2항 |
| `test_s5_build_skip.nim` | 18/18 (freeze 1건 [SKIPPED]) | build-mode 컨정크트 캐리어 스캔에 job2a 추가(캐리어 0건 핀 — job2a가 mode 컨정크트를 얻으면 red) |

**소급 정정 (b1659ef16 선례의 다섯 번째 사례)**: 카운트 핀은 33이었으나 50d781e82(사전분할 tip) 2잡 실측은 29였다 — 선존재 red. 33의 조성 산술은 실측과 대응되지 않는, 개정 의무가 누락된 값이었다. 실측 29를 기저로 재핀한다(29 −3 이동 +2 신규 = 28 2잡, +6 job2a = 34). 조성 항목 특정은 유추하지 않는다 — 실측이 정본.

`make test-unit` 전체 결과: **EXIT=0 — 399 [OK], 0 실패, 2 [SKIPPED]** (전부 freeze 태그 부재의 결정적 강등: ci-frozen-2026-10-09-venue-split 로컬 부재 — 로컬 전용 태그, 조용한 통과 아님). 로그: `/tmp/l3_test_unit.log` (2026-11-04 실행).

## §6. 착지 계획 (이후 단계 — 별도 진행)

### §6.0. 구현 PR CI의 세대 관측 (2026-11-04, 기계 관측)

PR #1264의 admission run `41791361212`의 `referenced_workflows` 전부가
`498c55704552291da926fae6eb34bc5c0c04ec1b` (구세대 callee)를 가리킨다 —
컨트롤러 admission-gate-v2.yml의 핀이 아직 회전 전이므로 본 PR의 CI green은
"구세대 검증자가 candidate를 PASS 판정"의 증거이지, 신규 5잡 구조의 실전
실행 증거가 **아니다**. 신규 구조의 실전 실행·음성 대조는 아래 (e) 컨트롤러
핀 회전 이후 차량에서 관측한다 (세대 전환 순서 — 선실행 증거 없는 성공
주장 금지, §0.9).

```bash
gh api repos/Archright/Axiom/actions/runs/41791361212 \
  --jq '[.referenced_workflows[] | {path, sha}]'
```

1. 커밋(agent_preflight 빌드 → `bin/axiom-gate commit`) — 워크플로우+핀+테스트+본 문서 동일 커밋.
2. `make push-admissibility` + [3a] 3파일 일치 재확인.
3. 구현 PR — Track 1(prereg §10) GitHub native auto-merge 시험 차량 병행.
4. per-PR 위임 기록 커밋(§1 [PR PENDING] 확정) 후 MUST-T2a 위임 병합.
5. 컨트롤러(Archright/.github) callee 핀 회전 → 양 org ruleset 재핀·readback.
6. 발산 테스트 E1 + 실전 음성 대조 (b)(b3) + 실행 버전 증명(referenced_workflows SHA).
7. production acceptance(merge_group 8/8·canonical main readback) → 신규 15배치 효과 판정(§4 동결 공식, 신규 관측만) + §5 비용 별도 보고·4분류 판정.

계획 1–6 수행 결과·판정은 §6.1–§6.6에 기계 관측으로 기록한다.
**요약 판정**: (b) PASS(§6.4)·E1 PASS(§6.3) — 그러나 신세대가 정상
candidate의 merge_group에서 witness 결함으로 미통과(§6.5)하여 §5.7에 따라
세대를 SHA 원복했다(§6.6). 7(production acceptance·효과 판정)은 결함
수정 재착지 이후로 이월한다.

### §6.1. 컨트롤러 callee 핀 회전 (2026-11-04, 기계 관측)

- Archright/.github PR #254 "ci: rotate admission-gate-v2 callee pins to
  8860e3 (L3 admission-independents job split, coherent 6-pin rotation)" —
  **MERGED** 2026-11-04T08:23:37Z, native MERGE 커밋
  `67c6c8312ae1236c4b651a73a533ba78e74e8a3d` = 컨트롤러 main tip.
- admission-gate-v2.yml의 callee 핀 6곳:
  `498c55704552291da926fae6eb34bc5c0c04ec1b` →
  `8860e320942a139b088d7afb81eff4345af3e79a`
  (`git grep -c 8860e320 origin/main -- '*.yml'` = 6, 구핀 잔존 0).

### §6.2. 양 org ruleset 재핀 (2026-11-04, 기계 관측)

빈 큐 확인 → repo ruleset 20303214 `max_entries_to_build` 2→0 동결 →
org ruleset 25218071(admission-gate-v2.yml)·23943917(landing-integrity.yml)
workflows `sha` `7eaa9624…` → `67c6c8312…` (문서화된 경로
`PUT /orgs/Archright/rulesets/{id}` 전체 본문) → GET readback
byte-consistency 일치 → 0→2 해제 + readback `[2]`.

### §6.3. 실행 버전 증명 — 발산 테스트 E1 (2026-11-04, 기계 관측)

| venue | run | referenced_workflows |
|---|---|---|
| pull_request (PR #1274) | `41803764514` | 3종 전부 `8860e320…` |
| merge_group (그룹 `3115a4c6`) | `41805047453` | 3종 전부 `8860e320…` |

callee 3종(admission-check·certificate-mint·runner-pool-acceptance) 전부
신세대 SHA — prereg §7-9의 E1 전환 관측이 양 venue에서 성립. 신규 잡
`attest / admission-independents`가 실제 dispatch되어 check-run으로
관측됨(아래 §6.4·§6.5 로그).

### §6.4. 실전 음성 대조 (b) — GO 고장 candidate 큐 거부 (이중 관측, PASS)

주입: `tests/unit/test_d2_persist.nim` 말미 `quit(1)` — 커밋
`7b6882fb103b629206852499fd421feb0b969fb6` "test(negative-control): deliberate
d2_persist GO failure — L3 guard live proof (scratch, not for landing)",
PR #1274(브랜치 `work/l3-negative-control-b-2026-11-04`, 착지 대상 아님).

| 그룹 | 구성 | run | 판정 |
|---|---|---|---|
| `3115a4c6` | main+PR#1273+PR#1274 (09:08:52Z) | `41805047453` | **failure** (09:19:32Z) |
| `e85bdb75` | main+PR#1274 재구축 (09:12:13Z) | `41805510595` | **failure** (09:26:47Z) |

- 그룹 공통: `attest / go-critical-lane (1)` failure → 가드 잡
  `attest / admission-check` 로그에 명시 판정
  **`[guard] FAIL — needs.go-critical-lane.result='failure' != success (a
  skipped, cancelled, or failed lane is never green) (fail-closed,
  ADR-0032 (f))`** — 관측된 needs: `build-base-artifacts=success
  go-critical-lane=failure admission-independents=success` — 가드가
  GO-independent(=success)를 판별하면서 GO 고장만으로 red 처리.
- 7잡 red(가드·rollup·mint-prepare/publish·verdict·required check
  `admission-check` = FAILURE).
- 결과: PR #1274 **dequeue**(isInMergeQueue=false, 큐 0 entries), main tip
  `23027523004382df4f20871c2208c6e7e31d4048` 불변, `7b6882fb1` 미착지
  (`git merge-base --is-ancestor` → not-in-main). PR close 완료.
- **판정: (b) PASS** — needs-result 명시 판정이 실전 merge_group에서
  fail-closed로 작동하고 큐가 고장 candidate를 착지 없이 거부했다.

### §6.5. 신세대 merge_group 미통과 — witness subject 저장소 핸드오프 결함 (실패 기록)

- 최초 정상 candidate 검증: PR #1273(docs-only) 그룹 `e02ae8572`
  (main `2302752` + PR#1273 head `5bdb3ebe`, 08:58:26Z) — admission-gate
  run `41803625558` **failure** (09:11:42Z), referenced_workflows 전부
  `8860e320`(신세대).
- 가드는 **PASS**(needs 3종 전부 success, 09:03:25Z 로그) — 이후
  witness 스텝 red:
  `[ERROR] cert_cli: attest --witness-only: no stored subject for ref
  5bdb3ebe4d6c0205c983f468caf9a411f234c91f (fail-closed)`.
- **원인**: L3 파일 채널이 `data/trusted/evidence/*.json`만 전달한다
  (`[independents] Upload evidence chain`의 path). 그러나
  `subject-register`가 기록하는 subject 저장소는
  `data/trusted/subjects/<subjectId>.json`
  (`src/verification/subject_store.nim:33` `SubjectStoreDir`)이며, 이
  디렉터리는 잡 경계를 넘지 못한다. 분할 전에는 register·witness가 동일
  워크스페이스에서 실행되어 로컬 저장소가 그대로 조회됐다. 잔여 잡의
  witness는 `findSubjectsByHeadSha`(`src/cli/cert_cli.nim:773`)로 로컬
  저장소를 스캔 → 0건 → fail-closed.
- **검출 경로의 공백**: PR venue는 witness가 landing-gated라 이 경로를
  실행하지 않고, 부정시험 (a)는 YAML 구조·가드 판정 로직을 검사하므로
  런타임 데이터 흐름(저장소 파일의 잡 간 이동)을 검증하지 못했다.
- **영향**: 신세대(`8860e320`) merge_group 통과 0건 — 모든 PR의 main
  착지 차단(merge freeze). 구세대(`498c5570`)의 마지막 통과는 그룹
  `2302752`(PR #1272, 08:29:48Z, 8/8 success, referenced_workflows
  `498c5570`) — 재핀 직전 마지막 구세대 검증.
- 참고: 이 관측은 (b) 차량의 그룹 재구축 과정(그룹 2건 실패 → #1273
  dequeue → #1274 단독 재구축)에서 자연 발생 정상 candidate가 신세대
  검증을 받으면서 포획되었다 — 병목·회귀 관측의 실효 사례.

### §6.6. 세대 원복 — §5.7 failure SHA 원복 (2026-11-04, 기계 관측)

절차(admission-generation §5 순서 준용):

1. 빈 큐 확인 — entries 0(PR #1274 dequeue·close 후).
2. repo ruleset 20303214 `max_entries_to_build` 2→0 (PUT, readback `[0]`).
3. org 25218071·23943917 workflows `sha` `67c6c8312…` →
   `7eaa9624d128b9f10e9e40d140d5c23367dabdad` (PUT 전체 본문, 동일 논리
   단위).
4. GET readback **byte-consistency MATCH** — sha 설정 + 그 외 전 규칙·조건
   무변경 대조(양측).
5. 해제 0→2 (readback `[2]`).

`ref: main` 복원이 아니다(SHA 값 원복 — §5.7 금지 조항 준수). 원복 세대 =
PR #1264·#1270–#1272 착지를 검증한 세대. **L3는 결함 수정 후
ROT_ALLOWLIST 전체 경로(브랜치→부정시험→PR→컨트롤러 회전→ruleset
재핀)로 재착지한다** — 수정 내용: job2a 업로드/잔여 잡 다운로드에
`data/trusted/subjects/` 포함 + 부정시험 (a)·venue_split 파일 채널 핀
갱신(이 결함 클래스의 로컬 검출 가능화).

### §6.7. 결함 수정 착지 — PR #1276 MUST-T2a 위임 병합 (2026-11-04, 기계 관측)

**병렬 세션 간섭(§6.6 원복 직후)**: 운영자의 병렬 세션(merge-authority
workstream)이 §6.6 원복(7eaa9624)을 드리프트로 오인, 10:20:04Z 양 org
ruleset을 67c6c8312(결함 세대)로 재PUT하고 자기 PR #1263을 큐 투입 →
#1263 그룹 admission-gate 실패(10:54:04Z, 실패 스텝 `[check] Attest
witness-only` — §6.5 결함의 재현 확증). 해당 세션은 10:51Z 이후 비활성.
/tmp 정리로 페이로드·클론 소실 → 재구성(`/tmp/l3fix_rb`,
`/tmp/archright_dotgithub`) 후 §6.6 절차 재수행(원복 7eaa9624,
readback ALL MATCH).

**PR #1276 BLOCKED 원인 규명**: PR 수준 admission-gate·landing-integrity
run이 구세대 핀(67c6c8312) 시절(10:27:55Z) 생성 — run 객체의 워크플로
SHA는 생성 시 고정되어 현재 핀과 불일치 → "required workflow not
satisfied". REST rerun(attempt 2)은 run 객체의 기록된 워크플로 SHA를
갱신하지 않아 무효(재실행 본문은 현재 핀 callee로 동작·success하나
병합 판정은 여전히 BLOCKED).

**해결 경로 — close/reopen**: `gh pr close 1276 && gh pr reopen 1276`
(동일 head 9b2d69b33, pull_request 이벤트 재발화) → 새 admission-gate
run 41857870495가 현재 핀의 callee `498c5570`로 생성
(referenced_workflows 확인) → 15:33:35Z success → GraphQL
mergeStateStatus **CLEAN**(autoMergeRequest null).

**gh arm 우회 정직 기록**: 14:15:15Z `gh pr merge 1276 --merge`가
"merge strategy is set by the merge queue" 안내와 함께 auto-merge arm로
우회 전환(AutoMergeRequest enabled) — MUST-T2a zero-arming 위반 소지로
14:46:49Z `gh pr merge 1276 --disable-auto`로 즉시 해제
(AutoMergeDisabledEvent). CLEAN 확보 후 재시도는 arm 없는 수동 레인
1회성 실행(#1264 패턴)으로 큐 진입.

**착지 관측**: 큐 position 1 AWAITING_CHECKS(auto-merge 이벤트 없음) →
그룹 `122ac8da`(15:36:29Z) merge_group **8/8 success** —
admission-gate(구세대 callee 498c5570가 그룹 head 검증, witness 포함
`attest / admission-check` PASS — PR venue에서도 candidate
`attest/admission-check`·`admission-independents` PASS, run 41814357495) →
native MERGE **16:15:10Z**, main tip `122ac8da`(parents 9869425c +
9b2d69b33, "Merge pull request #1276"). A2 3파일 readback MATCH:
workflow blob == TWS == epoch == `45a56971…`.

### §6.8. 운영 acceptance — 컨트롤러 회전·재핀·신세대 자기검증 (2026-11-04, 기계 관측)

**컨트롤러 callee 6핀 회전**: PR #255(Archright/.github,
`work/l3-subject-handoff-fix-rotation-2026-11-05`) —
admission-gate-v2.yml 6곳 `8860e320…` → `122ac8da…`
(setup-axiom-toolchain×1, admission-check×2, certificate-mint×2,
runner-pool-acceptance×1). `pin-promotion-gate (DEBT#473)` **SUCCESS** —
PREPARED(epoch==TWS==45a56971) + PINNED(122ac8da의 admission-check.yml
blob == 45a56971) 기계 검증. MERGE 16:37:21Z, .github main tip
`a7a96d7b`. admission-gate-v2가 .github repo pull_request에서 job 없이
failure하는 것은 #254 선례와 동일한 무해 패턴(required check 아님,
rollup 미등장). 게이트 러너 할당 지연(Ubicloud standard-2 큐 대기 약
13분) 후 통과.

**양 org ruleset 재핀**: 큐 drain 확인(entries 0) → 동결(20303214
max_entries_to_build 2→0, readback `[0]`) → PUT 양측 sha
`a7a96d7b…` → GET readback **ALL MATCH**(sha + conditions) → 해제
(readback `[2]`).

**acceptance — PR #1273(docs-only 자연 PR)**:

1. 1차 시도(close/reopen): admission-gate 41870764963에서
   `attest/admission-independents` FAILURE — ADM_IDENTITY
   `CANDIDATE_TREE_MISMATCH`: merge-tree(122ac8da, 5bdb3ebe) tree
   `820208a9` ≠ tested landing candidate tree `f1adb697`. 로컬 역추적:
   `f1adb697` == merge-tree(230275230, 5bdb3ebe) — PR 생성 시점
   base(230275230) 기준 merge ref가 close/reopen으로는 갱신되지 않는
   레이스. **identity 게이트가 이 불일치를 정확히 포착(fail-closed
   정상 작동 — 테스트한 tree ≠ 착지될 tree 상태의 병합 차단)**.
2. 해소: `gh pr update-branch 1273`(base→branch merge, head
   `e6273959`) → merge ref 재계산 → admission-gate 41873572104
   **SUCCESS**(17:08:01Z, callee 122ac8da — referenced_workflows 유니크
   {122ac8da}, admission-independents 포함 전 job green).
3. 최종: CLEAN → 위임 수동 병합(arm 없음) → 큐 진입(position 1) →
   그룹 `80c7ab85`(17:12:59Z) merge_group **8/8 success** —
   **referenced_workflows == 122ac8da: 신세대가 실제 병합 그룹을
   자기 자신(§6.5 수정 포함)의 검증기로 검증** → native MERGE
   **17:21:48Z** → main tip `80c7ab85`("Merge pull request #1273").

**착지 후 readback(전 MATCH)**: A2 3파일 workflow blob == TWS == epoch
== `45a56971…`; 양 org ruleset 핀 == `a7a96d7b…`. 세대 일관성:
ruleset(a7a96d7b) → 컨트롤러 callee 6핀(122ac8da) → admission-check
blob(45a56971) — 원자 회전 이후 첫 자연 PR의 전 과정이 신세대로
완결.

## §7. 재현 명령 (읽기 전용)

```bash
# 잡 위상·가드
python3 -c "import yaml; d=yaml.safe_load(open('.github/workflows/admission-check.yml')); [print(j, d['jobs'][j].get('if','')) for j in d['jobs']]"
# landing 카운트 (34 = 9+19+6)
python3 -c "
import yaml; d=yaml.safe_load(open('.github/workflows/admission-check.yml'))
L='steps.venue.outputs.venue == \'landing\''
print(sum(1 for j in ['build-base-artifacts','admission-check','admission-independents'] for s in d['jobs'][j]['steps'] if L in (s.get('if') or '')))"
# A2 3-way
git hash-object .github/workflows/admission-check.yml
python3 -c "import json,re; s='\n'.join(l for l in open('config/trusted_writer_set.json') if not re.match(r'\s*//',l)); print(json.loads(s)['trustedAdmissionWorkflowSha'])"
# 부정시험·구조 테스트
nim c -r tests/ci/test_l3_guard_fail_closed.nim
nim c -r tests/ci/test_admission_check_stages.nim
nim c -r tests/ci/test_admission_venue_split.nim
nim c -r tests/ci/test_s5_build_skip.nim
# §6.3 E1 — 양 venue referenced_workflows
gh api repos/Archright/Axiom/actions/runs/41803764514 --jq '[.referenced_workflows[] | .sha]'
gh api repos/Archright/Axiom/actions/runs/41805047453 --jq '[.referenced_workflows[] | .sha]'
# §6.4 (b) — 가드 명시 판정 로그(그룹 3115a4c6 run 41805047453)
curl -sL -H "Authorization: Bearer $(gh auth token)" \
  "https://api.github.com/repos/Archright/Axiom/actions/jobs/126494122658/logs" | grep "\[guard\]"
# §6.4 — 고장 head 미착지
git fetch origin main && git merge-base --is-ancestor 7b6882fb103b629206852499fd421feb0b969fb6 origin/main || echo "not-in-main"
# §6.5 — witness 결함 원 로그(그룹 e02ae857 run 41803625558)
curl -sL -H "Authorization: Bearer $(gh auth token)" \
  "https://api.github.com/repos/Archright/Axiom/actions/jobs/126487357257/logs" | grep "witness-only"
# §6.6 — 원복 readback
gh api /orgs/Archright/rulesets/25218071 --jq '[.rules[] | select(.type=="workflows") | .parameters.workflows[] | .sha]'
gh api /orgs/Archright/rulesets/23943917 --jq '[.rules[] | select(.type=="workflows") | .parameters.workflows[] | .sha]'
gh api repos/Archright/Axiom/rulesets/20303214 --jq '[.rules[] | select(.type=="merge_queue") | .parameters.max_entries_to_build]'
# §6.7 — PR #1276 착지(그룹 122ac8da, callee=498c5570 구세대가 그룹 검증)
gh api repos/Archright/Axiom/actions/runs/41859508412 --jq '{conclusion, callees: [.referenced_workflows[].sha] | unique}'
git show 122ac8dac0bbc2f505590a9a0294a99ddae1fe4f:.github/workflows/admission-check.yml | git hash-object --stdin
# §6.8 — 신세대 자기검증(그룹 80c7ab85, callee=122ac8da) + 컨트롤러 tip
gh api repos/Archright/Axiom/actions/runs/41875381784 --jq '{conclusion, callees: [.referenced_workflows[].sha] | unique}'
gh api repos/Archright/.github/commits/a7a96d7b8a5e05289c537921122e44cbad4d9ad0 --jq '.sha'
# §6.8 — 1차 시도 identity 레이스(f1adb697 == merge-tree(230275230, 5bdb3ebe))
git merge-tree --write-tree 23027523004382df4f20871c2208c6e7e31d4048 5bdb3ebe4d6c0205c983f468caf9a411f234c91f
```
