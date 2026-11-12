# Decision Binding 워닝 만료·에스컬레이션 조사 — 2026-11-04

> **종류**: 읽기 전용 조사 증거 문서. binding 부여·정책 변경·waiver 수정은 **0건**이다 (§9 Non-claims).
> 조사 대상: d5 빌드에서 관측된 `[decision-binding] WARN: 50 function(s) missing {.axiomDecision.} pragma —
> escalation threshold 30 days not yet reached` (기록: `docs/evidence/serde_json_c7_adjudication_closure_2026-11-03.md:296`,
> 원문에 "범위 밖 — 팔로우업 노트"로 남겨진 항목 — **본 문서가 그 팔로우업**이다).
> 기준 트리: canonical main `2f9c21693b401fb040991561b820718b9be0046d` (PR #1249 merge) — 클린,
> 조사는 전용 throwaway worktree `/tmp/dbwarn_wt`(브랜치 `work/decision-binding-escalation-survey-2026-11-04`)에서 수행.
> 메인 클론은 무수정 (§10 Deviation 6 참조).

---

## §1. 요약 (결론 먼저)

| 항목 | 결과 |
|---|---|
| 워닝 원천 | `config.nims:588-596` — **모든 `nim c`마다** `bin/decision_binding_checker --escalation-threshold 30` 실행 (§3.1) |
| "50 function(s)"의 실체 | **위반 파일 50개**다. 실제 위반 **함수는 213개** (§3.2-§3.3). 게이트 스캐너(`make check-decision-binding`) 기준으로는 파일 66 / 함수 329 (§3.4) |
| 가장 이른 waiver 만료일 | **2026-12-31** — TOML 23건·JSON 259건 **전 항목 동일** (§5.1). 확장 이력 없음 (§5.2) |
| 에스컬레이션(빌드 FAIL) 진입일 | **2026-12-01** (KST 00:00 경계 직후부터; 기계 관측 + Nim 실험 + Context7 언어 사실로 고정, §5.3) |
| 추적 상태 | **미추적** — debt registry·CI·문서 어디에도 2026-12-01 FAIL 전환일의 기록이 없다 (§6). 운영 리스크 발견 (보고만, 수정 없음) |
| 카운트 증가 원인 | 46→50 = 파일 4개 신규 진입: 10-31 2건, 11-02 2건 — 전부 바인딩 없는 신규/수정 표면 파일 (§7) |
| 계약 정합성 | §0.10·프레임워크 문서 대비 **불일치 3건** 확인: 트리거 반전(문서: 만료 후 에스컬레이션 / 코드: 만료 30일 전부터 FAIL), WARN 단위 mislabel("function(s)"=파일), 문서 예시 로그 형식 불일치 (§8) |

---

## §2. 조사 방법 (실행 명령 원문)

```bash
# 0. 조사 전용 worktree (canonical main 고정)
git worktree add -b work/decision-binding-escalation-survey-2026-11-04 /tmp/dbwarn_wt \
    2f9c21693b401fb040991561b820718b9be0046d

# 1. 관측 워닝 재현 — config.nims가 매 nim c마다 실행하는 것과 동일한 바이너리·플래그
cd /tmp/dbwarn_wt
bin/decision_binding_checker --escalation-threshold 30        # → exit 0, WARN: 50 (§3.1 원문)

# 2. 게이트 스캐너 — make check-decision-binding이 실행하는 것과 동일한 컴파일·실행
nim c --hints:off -o:bin/hermetic_build tools/hermetic_build.nim   # Makefile:275과 동일
bin/hermetic_build --check-decision-bindings --escalation-threshold 30   # → exit 0, WARN: 66

# 3. FAIL 분기 노출 (에스컬레이션 경계의 기계 관측)
bin/decision_binding_checker --escalation-threshold 57        # → exit 1, "56 days remaining" ×259 (§5.3)

# 4. 집계 (스캐너 출력 파싱 — 파일별 함수 수, 디렉터리 분포, 두 스캐너 파일 집합 diff)
python3 (regex 파싱 — 산출물 문서 §A/§C 생성에 사용)

# 5. 날짜 산술 검증 — std/times 동작의 독립 실험 (리포 외부 /tmp/dbwarn_tztest.nim)
nim c ... /tmp/dbwarn_tztest.nim && /tmp/dbwarn_tztest        # §5.3 원문 결과
```

비고: 위 1·2는 각각 `config.nims:596`과 `Makefile:273-276`이 실행하는 명령과 동일하다.
`nim c` 자체가 `config.nims` hermeticPreBuild를 통해 worktree 내 `bin/*`·`src/generated/build_env.nim`을
재생성했다(throwaway 내부 — §10 Deviation 1).

## §3. 워닝 원천과 집계 방식

### §3.1 워닝은 어디서 나오는가

- **매 `nim c`마다**: `config.nims:588-596`이 `bin/decision_binding_checker`를 (미존재 시) 빌드하고
  `AXIOM_FAST_BUILD != "1"`이면 `exec dbBin & " --escalation-threshold 30"`을 실행한다. 주석은
  "(audit mode - warn only)"이지만 **`--audit-mode` 플래그는 넘기지 않는다** — 즉 FAIL(exit 1)이 가능하며,
  NimScript `exec`는 non-zero 종료에서 OSError를 raise해 컴파일 자체가 중단된다 (§8, Context7 확인).
- **게이트 경로**: `make check-decision-binding`(Makefile:273-276) = `hermetic_build --check-decision-bindings
  --escalation-threshold 30`. 이는 `GATES_STATIC`(Makefile:39-40)의 멤버로 `local-verify-static`(Makefile:410)과
  push-admissibility 세트에 편성된다.
- **인프로세스 게이트**: `src/gate/runners/decision_binding_gate.nim`은 `config/gates.manifest.toml:15`에
  등록돼 있으나 manifest.d에서 **`stages: ["manual"]`** — 자동 파이프라인 미편성. 만료 처리 방식도 다르다 (§5.4).
- d5 빌드 로그의 WARN(`make_build` 계열)은 위 1번 경로(config.nims→dbc)의 출력이다. 본 조사가
  동일 명령으로 동일 카운트(50)를 재현했다 → 산출물 문서 §A.

### §3.2 집계 로직 (코드 인약)

`tools/decision_binding_checker.nim` 풀스캔(:401-414): `src/` 아래 모든 `.nim`을 걷되, JSON waiver의
exempt file(:405)·exempt module(:408)에 걸리면 건너뛴다. `scanFile`(:179-309)은 행 기반 문자 스캔으로:
`proc `/`func ` 선언(최상위, **exported `*`만** — 중첩·비프리뷰 제외 :201-209)을 찾고, 시그니처+연속행+직후
pragma 블록(:237-256)에 `axiomDecision`이 없으면서 (a) 시그니처가 Result/Option 반환, (b) guard된 복수
return, (c) assert/check/guard 검증 로직 중 하나라도 있으면(:290-301) 위반으로 기록한다(함수당 1메시지).

### §3.3 WARN 카운트의 단위 — 파일이다, 함수가 아니다

```nim
# tools/decision_binding_checker.nim:404-414 (풀스캔 분기)
for f in walkSourceFiles(srcDir):
    ...
    let scanResult = scanFile(f, waiver)
    if scanResult.violations:
      inc violationCount              # ← 파일당 1회
      for v in scanResult.reasons: violations.add(v)   # ← 함수별 라인은 별도
```

`violationCount`는 **위반이 발견된 파일 수**이고, `Found N violation(s)`·`WARN: N function(s) ...`의 N은
이 값을 그대로 찍는다(:417, :451). 실측(§2-1):

- `Found 50 violation(s)` + 들여쓰기 위반 라인 **213행** (함수 213개, 파일 50개) — 산출물 문서 §A.
- 즉 관측 워닝의 "50 function(s)"는 **50개 파일**을 뜻하며, 실제 함수는 213개다.
- 부작용 확인: 파일 안 함수 수가 변해도 파일이 리스트에 남아 있으면 카운트는 불변이다 —
  실례로 `counterexample_replay.nim`는 #1206 창에서 함수 11→10으로 변했지만 카운트에는 영향 없음 (§7).

### §3.4 두 스캐너의 카운트 차이 (50 vs 66)

`tools/hermetic_build.nim`의 `scanFileForDecisionBinding`(:1550-1640)는 동일 판별식이지만
중첩·비프리뷰 함수도 스캔한다(exported 필터·들여쓰기 스킵 없음). 그 결과 같은 트리에서
**파일 66 / 함수 329** — dbc의 50파일 집합을 **완전 포함**하며 16파일만 추가된다
(산출물 문서 §C, 추가 파일 목록: admission_cli, evidence_cli, install_ax_cas, rust_lane_cli,
orchestrator_api, contract_synthesis, skreport_comparison, coverage_ratchet_gate,
evidence_truth_boundary_gate, readiness_start_gate, cert_writer, llbc_to_canonical,
obligation_types, post_satisfaction, rust_extraction_agreement, rust_replay_adapter).
두 출력의 WARN 문구는 동일 형식이라 어느 스캐너의 출력인지 로그만으로 구분되지 않는다 (§8.4).

### §3.5 50파일 집계 요약 (전체 목록 = 산출물 문서 §A)

디렉터리 분포 (파일 수 / 위반 함수 수):

| 영역 | 파일 | 함수 |
|---|---|---|
| `src/verification/**` | 30 | 139 |
| `src/core/**` | 11 | 19 |
| `src/cli/**` | 7 | 52 |
| `src/infrastructure/**` | 1 | 2 |
| `src/engine/**` | 1 | 1 |
| **합계** | **50** | **213** |

위반 함수 수 상위 파일: `src/verification/judgment_cas.nim`(30), `src/cli/merge_cli.nim`(19),
`src/cli/upstream_report_cli.nim`(15), `src/verification/ledger_side_ref.nim`(13),
`src/verification/evidence_cas.nim`(12), `src/verification/counterexample_replay.nim`(10),
`src/cli/axiom_engine.nim`(8), `src/core/types/candidate_identity.nim`(7),
`src/verification/semantic_set_derivation.nim`(7) — 전체 50파일의 파일별 함수 수는 산출물 §A에 수록.

## §4. 50파일 전수의 기계 산출

전체 목록은 스크립트 파싱이 아닌 **스캐너 자신의 출력 원문**으로 보존했다:
`docs/evidence/decision_binding_scan_output_2026-11-04.md` (본 커밋에 함께 수록).
§A = dbc 출력(50파일/213함수, 파일:라인+사유), §B = threshold-57 FAIL 분기 원문,
§C = hermetic 게이트 스캐너 출력(66파일/329함수).

## §5. waiver 만료 지도

### §5.1 현재 재단

| 파일 | 항목 수 | 만료일 분포 | 비고 |
|---|---|---|---|
| `config/decision_binding.waiver.toml` | 23 | 2026-12-31 ×23 | 2026-07-31 생성(5cbb7586f, "4-pillar 결정 바인딩 프레임워크 완결") 이후 **무변경** |
| `config/decision_binding.waiver.json` | 259 | 2026-12-31 ×259 | 07-31 생성 시 260건 → 08-08(b9f2175ae)에 1건 제거(`src/gate/runners/context7_evidence_gate.nim` — Context7 증거 체계 은퇴) → 이후 **무변경** |

- **TOML ⊂ JSON**이다(기계 확인: TOML 23건은 전부 JSON에 동일 경로로 존재; 유니크 경로 259).
- 사유 분포: "Grandfathered legacy code - pending rationale extraction" 236건, 사전존재 커널/게이트 3건,
  위반 상위 파일 사유(violation count 명시) 20건.
- **가장 이른 만료일 = 2026-12-31** (전 항목 동일 — 단일 만료일 구조).
- 확장(연장) 이력: **없다**. 만료일은 생성 시점의 2026-12-31 단일 값이며, 2026-08-08 이후 두 파일 모두
  손대지 않았다(`git log` 2커밋뿐).
- 소비 형상: dbc·게이트러너는 **JSON 전용·fail-closed**(`decision_binding_checker.nim:101, :371-374`),
  hermetic 빌드만 TOML+JSON 병합(dedup). TOML/JSON 발산 사실과 소비 형상은 프레임워크 문서 자체가
  2026-10-17 실측으로 기록해 둔 것과 일치한다(`docs/spec/decision_binding_framework.md:160, :172`).

### §5.2 만료 도래 동작 (코드 인약)

-dbc/hermetic 공통: `daysRemaining = (expiresDate - now).inDays; if daysRemaining < escalationThreshold
(30) → anyExpiringSoon` (dbc:435-451, hermetic:1854-1868). 만료 도래 시 "WAIVER EXPIRING SOON ... N days
remaining"을 전 항목 출력하고 **빌드 FAIL(exit 1)**.
- 로더의 만료 판정은 `expires < today`(문자열 비교, `today = utc(now())`의 **UTC 날짜**) —
  에스컬레이션 산술은 local TZ parse 기준으로 **혼합된 시간대 의미**를 가진다 (§5.3 각주).
  이 비교상 만료일 당일(2026-12-31)까지는 항목이 **활성**이고, UTC 날짜가 2027-01-01로 넘어가는
  순간(KST 09:00)부터 탈락한다.
- 만료 탈락 후: 해당 파일은 면제에서 빠지고("WAIVER EXPIRED" echo) 위반 풀에 259파일 전체가 복귀하며,
  전 항목 탈락 시 `waiverEntries.len == 0` → `FAIL: ... no active waivers` (dbc:431-433).
- `decision_binding_gate.nim`(manual 게이트)에는 에스컬레이션 임계치가 **없다**: `expires < today`면
  즉시 비면제 — 탈락 첫날부터 위반이면 곧바로 FAIL 판정 (다른 소비자와 또 다른 의미론, §8.4).

### §5.3 에스컬레이션(빌드 FAIL) 예정일 — **2026-12-01**

근거 사슬 (각 단계 기계 관측 또는 언어 사실 확인):

1. 코드: FAIL 조건은 `daysRemaining < 30`이며 `daysRemaining`은 **만료까지 남은 일수**다 —
   문서(§8.1)와 반대로 만료 **이전** 카운트다운이다.
2. 기계 관측(2026-11-04 10:39 KST): `--escalation-threshold 57` 실행 → 전 waiver에
   `(2026-12-31, 56 days remaining)` 출력 + `FAIL: ... waiver(s) expiring within 57 days`, exit 1
   (산출물 문서 §B). 즉 오늘 잔여 56일.
3. 언어 사실(Context7 Nim 공식 문서 + 로컬 실험): `times.parse("yyyy-MM-dd")`의 기본 시간대는
   **local**이며, `DateTime - DateTime`은 시간대 인식 차감이다. 실험 결과(원문):
   ```
   parsed instant UTC: 2026-12-30T15:00:00Z      # 2026-12-31T00:00 KST
   daysRemaining now: 56                          # dbc의 57-실행 출력과 교차 검증 일치
   daysRemaining==30 at (local): 2026-12-01T00:00:00+09:00
   daysRemaining==30 at (UTC): 2026-11-30T15:00:00Z
   ```
4. 결론: `daysRemaining`이 29로 떨어지는 첫 순간 = **2026-12-01T00:00:00 KST 직후**.
   경계 순간 자체는 정확히 30(미만 아님 → WARN)이므로, **2026-12-01 (KST) 00:00:01 이후 최초 빌드부터
   모든 `nim c`(dbc 경로)와 `make check-decision-binding`(게이트 경로)·push-admissibility가 FAIL로 전환된다.**
   오늘(2026-11-04)로부터 27일 뒤다.
5. 부수 진입점: 만료 판정은 `expires < today` 문자열 비교(`today = utc(now())`의 **UTC 날짜**)라
   만료일 당일(2026-12-31)까지는 항목이 **활성**이고, **2027-01-01T00:00Z(KST 09:00)부터** "WAIVER
   EXPIRED"로 면제 탈락이 시작된다 — 위 §5.2의 만료 폭증 경로가 그 시점에 겹쳐 진다. 즉 12-01 FAIL →
   (갱신 없으면) 2027-01-01부터 면제 상실·위반 급증 + "no active waivers" FAIL.

> 각주: 위 판정은 현재 코드 의미론의 예측일 뿐이며, 임계값 플래그·waiver 갱신·만료일 수정이 이뤄지면
> 달라진다. 본 조사는 어느 것도 수정하지 않았다 (§9).

## §6. 추적 상태 — **미추적 (운영 리스크 발견)**

2026-12-01 FAIL 전환일(및 2026-12-31 만료일 자체의 운영 처리 일정)을 담는 레코드가 존재하지 않는다:

- `data/debt_registry.json` / `docs/DEBT_REGISTRY.md`: decision-binding 관련 유일 항목은 **종결된**
  DEBT#479(TOML 폴백 파서 버그 — "2026-12-31"은 그 버그 재현 서술의 문자열)다. 만료·에스컬레이션
  일정 항목 없음. (검색: `decision`, `2026-12-31`, `2026-12-01`)
- `.github/`: 워크플로에서 decision-binding 관련 언급은 `merge-queue-rearm.yml`의 TRANSIENT 매처가
  `bin/decision_binding_checker`를 재링크 대상 이름으로 나열하는 것(:57, :732)뿐 — 일정 추적 아님.
  CI가 `AXIOM_FAST_BUILD`를 설정하지 않으므로(검색 0건) CI의 모든 `nim c`도 이 체크를 통과하며,
  2026-12-01부터 CI 빌드가 동일하게 FAIL로 전환된다.
- `docs/`: 프레임워크 문서(:186, :191, :378)에는 만료일 값 2026-12-31이 예시로 나오지만, 파생
  FAIL일(2026-12-01)의 언급은 0건이다. `docs/spec/ci_provider_december_unattended_fallback_acceptance_contract.md`의
  2026-12-01·`structural_enforcement_architecture.md:260`의 2026-12-01(nimtry 래칫)은 **무관한 별개 일정**이다.
- `experiments/`, `logs/`: 카운트 관측만 존재(§7), 일정 추적 없음.

운영 리스크 서술 (보고만 — 수정은 본 조사 범위 밖, §11): 12-01부터 저장소의 **모든 빌드 경로**가
일제히 FAIL로 바뀌는 일정이 소유자·캘린더·부채 항목 어디에도 등록돼 있지 않다. 등록 위치 후보의
판정(구독·캘린더·부채)은 정책 변경을 수반하므로 별도 계획의 몫이다.

## §7. 카운트 증가 원인 (3 → 50 → 50)

단위는 **파일**이다(§3.3). 관측 계열:

| 카운트 | 관측일(근거 커밋) | 원문 위치 |
|---|---|---|
| 3 | 2026-08-30 | `experiments/act3-o1-verified-warm-protocol/results/{cold,warm}_build_output.txt:55` |
| 43 | 2026-10-19 | `experiments/sidecar-adoption-e2e/runs/unsupported_tests.log:214` |
| 45 | 2026-10-22 | `experiments/nim-libp2p-bytesview-slice-e2e/discovery/14_loop_driver_carveout_fix.md:61` |
| 46–47 | 2026-10-31 | `experiments/serde-json-claim-2026-10-31/FREEZE.md:25` (freeze 재실행 47) |
| 48 | 2026-11-01 | `experiments/rust-skreport-relocation-2026-11-01/OBSERVATION.md:56` ("pre-existing WARN count, unchanged by this work") |
| 48 | 2026-11-02 | `experiments/u64-scalar-2026-11-02/artifacts/acceptance/make_build.txt:269` |
| 49 | 2026-11-02 | `experiments/u64-add-2026-11-02/artifacts/acceptance/make_build.txt:269` |
| 50 | 2026-11-03 | `docs/evidence/serde_json_c7_adjudication_closure_2026-11-03.md:296` (d5) |
| 50 (dbc) / 66 (hermetic) | 2026-11-04 | 본 조사 (canonical main에서 재현) |

46→50 창(+4 파일)의 1:1 귀속 — 전부 "binding 없는 함수를 새로 싣은 표면 파일"의 진입이다:

1. `src/cli/upstream_report_cli.nim` — 신규 파일, `a0ee745a3` (2026-10-31, "feat(report): ax report --upstream").
2. `src/verification/obligation/measured_digests.nim` — 신규 파일, `33d5e9e05` (2026-10-31,
   "refactor(verification): split measured content digests into their own module (LCOM repair)" —
   모듈 분할로 새 파일이 위반 리스트에 진입).
3. `src/core/trusted/private/ir_to_smt_chunk2.nim` — **기존 파일의 팁오버**, `9c081ed95` (2026-11-02,
   "feat(rust-subject): width-64 arithmetic …") — **PR #1206**(u64-add, 첫 병합 `ed9cab36d`, 04:02:44Z)이
   실어왔다. 증거: 부모 커밋(9c081ed95^1) 파일을 `dbc --scope`로 스캔 → 위반 0, 해당 커밋 버전 → 위반 1
   (파일 진입 = 카운트 +1). 동 PR은 `counterexample_replay.nim`을 11→10 함수로 줄였으나 파일이
   리스트에 남아 카운트에는 영향 없었다 — 단위=파일 판정의 교차 검증.
4. `src/cli/proposition_intake.nim` — 신규 파일, `e8ef5cf07` (2026-11-02, "feat(cli): BYO-Agent
   propositions intake — ax prove --proposals (Phase 1)") — **PR #1220**(byoa-phase1-intake,
   `aaba7fb36`, 13:36:51Z)이 실어왔다 (#1206에는 미포함 확인).

d5(11-03) 이후: 11-03 병합 12건(#1235-#1249)에서 신규 진입 파일 **0건** — canonical main의 dbc 카운트는
**50 유지** (오늘 재현). 46→50은 "특정 PR의 대규모 위반 유입"이 아니라, 하루 1-2건 규모로 새 표면
파일이 pragma 없이 landing되며 쌓인 누적이다. waiver 파일은 2026-08-08 이후 불변이므로 이 4파일은
grandfather로도 커버되지 않는다(의도적 회피 여부의 판정은 사유 검토 문제로 본 조사 범위 밖 — 사실만 기술).

## §8. 계약 정합성 평가 (§0.10 + docs/spec/decision_binding_framework.md 대비)

### §8.1 불일치 1 — 에스컬레이션 트리거 반전 (문서 ≠ 코드)

- 문서(`docs/spec/decision_binding_framework.md:420-486`): "Progressive Escalation (D-30 Soft Gate →
  D-Day Hard Fail)" — WARN = "**Waiver expired**, but within escalation threshold (default: 30 days
  **past expiry**)", FAIL = "Waiver expired + threshold exceeded"; 타임라인 표(:482-486)도
  "Post-deadline ≤ 30 days → WARN / Post-deadline > 30 days → FAIL"이다. 즉 문서 모델에서는
  **만료 후** 소프트 게이트 30일이고, 만료일(12-31)에는 여전히 빌드가 녹색이다.
- 코드(dbc:435-451, hermetic:1854-1871): FAIL = `daysRemaining < 30` — **만료 30일 전**부터 하드페일
  (12-01부터), 만료 후에는 WARN 상태 자체가 존재하지 않는다(만료 항목은 면제 탈락 → 위반 급증 →
  `no active waivers` FAIL). WARN 문구의 "escalation threshold 30 days not yet reached"는 이 코드
  의미론(잔여 일수)과는 자기정합이지만, 문서의 "days-since-expiry countdown"(:431)·예시 로그(:461-475:
  `WARN: src/... (waiver expired 15 days ago, threshold: 30 days)`)와는 **형식·의미 모두 불일치**다.
- 결과: 문서 계약대로라면 만료 탈락(2027-01-01, UTC 날짜 기준) 후 소프트 게이트가 열려 빌드 FAIL은
  2027-01-31경(만료+30일 초과부터)이 됐을 것이다. 실제 코드는 **2026-12-01**부터다 — 한 달 이상 앞당겨진
  하드페일이다. 어느 쪽이 의도인지의 판정(문서 개정 vs 코드 수정)은 정책 변경이라 본 조사가 판정하지 않는다 (§11).

### §8.2 불일치 2 — WARN 단위 mislabel

`WARN: N function(s) missing`의 N은 파일 수다 (§3.3). 문서의 예시 로그(:464: "1 function(s)")도 같은
문구를 쓰므로 독자는 함수 수로 오독하게 된다 — 실제 213함수가 50으로 표시되는 4.3배 과소 표기.

### §8.3 불일치 3 — 문서 예시 로그 형식 ≠ 실제 출력

문서 예시(:453-475)의 `Loaded 3 active waiver(s)`·`WARN: src/... — 1 function(s) ... (waiver expired
15 days ago, ...)`는 실제 출력 형식(`Loaded 259 active waiver(s) ...` + `WARN: 50 function(s) ...
escalation threshold 30 days not yet reached`)과 다르다. 문서의 예시는 구현과 동기화되지 않은 서술이다.

### §8.4 부수 관측 (불일치는 아니나 정합성 평가에 필요한 사실)

- **스캐너 3중 구현**: dbc(매 nim c) / hermetic_build 게이트(`--check-decision-bindings`) /
  `decision_binding_gate.nim`(manual 인프로세스)가 유사 로직의 3벌 복사본이며, exported·중첩 처리와
  만료 의미론이 서로 다르다(§3.4, §5.4). 같은 WARN 문구가 서로 다른 카운트(50/66)로 찍힌다.
- TOML/JSON 발산과 소비 형상은 프레임워크 문서가 이미 2026-10-17 실측으로 기록해 둔 것과
  오늘 재측정이 정확히 일치한다 (§5.1) — 해당 기록은 정합 유지 중.
- dbc는 JSON 로드 실패 시 fail-closed `quit(1)`(:371-374) — waiver 부재가 green이 되는 DEBT#479 버그의
  재발은 현재 코드에서 차단돼 있다 (원문 확인).
- CI는 `AXIOM_FAST_BUILD` 미설정 → 컴파일 타임 체크가 CI에서도 유효하다 — 12-01 FAIL 전환이
  로컬뿐 아니라 모든 CI `nim c`에 동시 적용된다 (§6).

### §8.5 외부 사실 확인 (Context7 — 내부 계약의 대체 아님)

- Nim `times.parse(input, f)`의 기본 시간대는 local (`tz` 파라미터 기본값) — 공식 문서 확인.
- NimScript `exec(command)`는 non-zero 종료에서 OSError를 raise — 공식 문서 확인.
  → config.nims의 dbc 실행은 dbc exit 1 시 컴파일이 실제로 중단됨을 의미.
- 본 조사의 날짜 산술은 위 사실 + §5.3의 로컬 실험 원문으로 고정했다. 내부 정책의 정본은
  AGENTS.md §0.10 + `docs/spec/decision_binding_framework.md` + repo 코드이며, 외부 문서는
  언어 동작 보강에만 사용했다.

## §9. Non-claims

- `{.axiomDecision.}` binding 부여·pragma 추가: **0건** (src/ 전체 무수정).
- 정책·계약 문서(AGENTS.md, docs/spec/**) 수정: **0건**.
- waiver(`config/decision_binding.waiver.{toml,json}`) 수정·연장·갱신: **0건** (읽기만).
- `src/gate/**`, Makefile, `.github/**`, §-1 파일: **0건** 수정 (FROZEN 존중).
- FAIL 전환일(2026-12-01)의 등록·추적 조치: **0건** (§6에서 권고만).
- 본 문서는 관측·예측만 담는다 — "12-01부터 반드시 FAIL"은 현 코드·현 waiver·현재 시간대(KST)에서의
  기계 예측이며, 그 전에 누군가 waiver를 갱신하면 무효가 된다.

## §10. Deviation 전수 등록

1. **worktree 내 빌드 부산물**: 조사 실행(nim c × 여러 회)에 따라 `/tmp/dbwarn_wt` 내 `bin/*`(hermetic_build,
   decision_binding_checker, sync_topology, feature_manifest_generator, sync_certs 등),
   `src/generated/build_env.nim`, `.axiom/cache/*`가 `config.nims` hermeticPreBuild의 **설계된 동작**으로
   재생성됐다. 과업 지시("src/generated/build_metadata.json 재생성은 throwaway 내에만") 준수 — 전부
   throwaway worktree 내부다. 빌드_metadata.json은 생성되지 않았다(재생성 요인 아님 확인).
2. **리포 외부 임시물**: `/tmp/dbwarn_tztest.nim`(Nim 날짜 실험), `/tmp/dbwarn_*.txt`(스캔 출력 캡처),
   `/tmp/wv_*.txt`(waiver 비교) — 리포 외부, 커밋 대상 아님.
3. **threshold-57 실행**: WARN(30) 재현 외에 FAIL 분기를 노출하기 위해 비기본 임계값으로 스캐너를
   실행했다 — 읽기 전용 실행이며 상태 변경 없음.
4. **컴파일 출력의 WARN 관측**: `nim c`의 tail-3에서 관측된 "WARN: 50"(§2-2 이전 실행)은 config.nims
   체인이 컴파일 중 dbc를 돌린 결과로, 조사 방법상 의도된 관측이다 (§3.1).
5. **merge-queue-rearm.yml 참조**: bin/decision_binding_checker가 CI 재시작 매처의 대상 이름에
   포함돼 있음을 확인했다 — 수정 없음.
6. **메인 클론 무변경 증명**: 조사 종료 시점 `git status --porcelain` = 사전과 동일하게
   `?? gh_env.txt` 1건만 존재 (본 조사 미접근·미수정).

## §11. 권고 — 전부 "별도 계획 필요" (본 조사에서 수행하지 않는다)

각 항목이 수정을 요구하는 이유와 권한 근거:

1. **만료·에스컬레이션 일정의 등록** (§6): 12-01 전환이 무추적 상태라 운영이 사전 인지할 수 없다.
   등록 위치(부채 레지스트리 항목, ops 캘린더, 문서)의 선택은 등록 스키마·권한(AGENTS.md §5 SSOT 위치)을
   건드리므로 별도 계획.
2. **waiver 만료 처리 계획** (2026-12-31까지): 259파일 grandfather의 정리(pragma 부여/사유 추출)는
   §0.10상 바인딩 부여 권한이 에이전트에게 없고(legislator 불변식·아키텍트 승인 체계), waiver 파일 수정은
   과업 지시상 금지 — 인간 아키텍트의 명시적 계획 필요.
3. **문서-코드 트리거 정합화** (§8.1): 프레임워크 문서(계약)와 코드 어느 쪽을 고정할지의 판정은
   문서 개정(계약 변경) 또는 src 수정 중 하나로, 둘 다 본 과업의 금지 대상이다.
4. **WARN 단위 문구·예시 로그 동기화** (§8.2-§8.3): 스캐너 메시지 문자열 변경은 tools/ 코드 수정이고
   문서 예시 수정은 docs/spec 수정이다 — 별도 계획.
5. **스캐너 3중 구현 수렴** (§8.4): 카운트 발산(50/66)의 근원 구조다. tools/·src/gate 코드 정리는
   §-1·§0.12 최소 변경 원칙 아래 별도 계획으로만 가능하다.

## §12. 참조 (원천 인덱스)

- 코드: `config.nims:588-596` · `tools/decision_binding_checker.nim:96-163,179-309,401-451` ·
  `tools/hermetic_build.nim:1503-1648,1656-1871,2001-2019` · `src/gate/runners/decision_binding_gate.nim`
  (manifest: `config/gates.manifest.toml:15`, `src/gate/manifest.d/decision-binding-gate.json`)
- 정책: AGENTS.md §0.10 · `docs/spec/decision_binding_framework.md:160,172,405-486`
- waiver: `config/decision_binding.waiver.toml`(23) · `config/decision_binding.waiver.json`(259)
- 관측 계열: §7 표 (experiments/**, docs/evidence/serde_json_c7_adjudication_closure_2026-11-03.md:296)
- 산출물: `docs/evidence/decision_binding_scan_output_2026-11-04.md` (§A dbc 원문 / §B FAIL 분기 / §C 게이트 스캐너 원문)
- 역사: `data/debt_registry.json` DEBT#479 (종결 — TOML 폴백 fail-open 버그), DEBT#417 관련
  `docs/spec/config_nims_hermetic_cache_quirk.md` (hermetic 캐시 의미론)
