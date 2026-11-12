# pre-commit nim_check_gate freshness — mtime → content identity 전환 관측 (2026-11-06)

> **종류**: 착지 관측 기록 (landing observation record). 이 문서는 결정을 대리하지 않는다.
> VS-1(`docs/evidence/prepush_content_identity_acceptance_2026-11-06.md`, PR #1284)이 확립한
> content-identity 판정 패턴을 pre-commit의 `bin/nim_check_gate` freshness guard에 적용한 결과를
> 기계 검증 관측으로만 담는다.
> **Date**: 2026-11-06 · **Branch**: `workstream/precommit-nim-check-content-identity` (off `main` @ `af5905649`)
> **변경 파일**: `.githooks/pre-commit` Part 1 freshness guard(구현) + `docs/spec/nim_gendepend_quirks.md`
> (5번 퀴크 관측 추가 — §0.5 Quirk Mandate) + 본 문서. 게이트 코드·Makefile·src/·config 변경 0건.

---

## §0. 배경 — 전환 대상과 결함 클래스

- **대상**: `.githooks/pre-commit` Part 1의 nim_check_gate freshness guard. 개선 전 유일한 mtime 판정:
  `find src/gate/runners -name '*.nim' -newer bin/nim_check_gate` (파일 내 `-newer`/`-nt` 유일 사용처).
- **결함 1 (false-stale)**: 콘텐츠 무변경인데 소스 mtime이 바이너리보다 미래면 무변경 커밋이 차단 —
  실측 2회 (VS-1 실험 중 소스 mtime 교란 시 — `prepush_content_identity_acceptance_2026-11-06.md` §5.1).
- **결함 2 (P0-1)**: 소스 실변경 후 mtime을 바이너리보다 과거로 롤백하면 stale 바이너리가 신선으로 판정 —
  롤백·변조 불감지.
- **보존된 설계 의도**: "no JIT rebuild inside the hook — two-phase compiler dependency" — pre-commit은
  FAIL + 처방(`Run: bin/build_all_gates --release`)만 출력하고 재빌드하지 않는다. pre-push Part 4(자동
  재빌드)와는 의도적으로 다른, 문서화된 설계다. 빌드 권위: `tools/build_all_gates.nim`의 `discoverGates()`가
  `src/gate/runners/*.nim`을 전수 발견 → nim_check_gate 커버(Makefile 개별 타깃 부재 — 처방 문구 유효).

## §1. 판정 계약 (구현된 흐름)

입력 신원은 **항상** 계산된다(mtime으로 신원 계산을 건너뛰지 않는다 — P0-1 원칙).

1. **입력 집합** = `nim genDepend`의 `src/gate/runners/nim_check_gate.nim` transitive closure(174행
   `.deps`: 프로젝트 48 + nimble 4 + stdlib 122, 2회 실행 바이트 동일) ∪ `src/gate/runners/*.nim` 전체
   (구형 체크의 보수적 스코프 유지 — closure 밖 runner 변경도 포착) ∪ 빌더 `tools/build_all_gates.nim`.
   캡처는 VS-1 계약 그대로(임시 CWD+nimcache, `.deps` artifact 검증, `.dot` 자기생성분만 정리,
   PROBE 라인으로 `when fileExists` CWD 퀴크 보상). 캡처 플래그는 5번 퀴크 계약에 따라
   `--skipParentCfg --skipProjCfg` + 루트 재앵커 `--path` 3종 + `-d:release`.
2. **신원 성분**: 툴체인(nim 버전·nim 바이너리 sha·gcc·nim.cfg) + HOST + **빌더 신원**
   (`tools/build_all_gates.nim` sha256 + `-d:release` — Makefile 타깃 부재로 NIM_TOOL_FLAGS 슬롯 대체) +
   캡처 플래그 문자열 + manifest 해시 스트림(CLOSUE_SHA/MISSING + PROBE_SHA/ABSENT).
3. **스탬프** `SCHEMA=vs1-gate-stamp/1` (`.cache/axiom/prepush/gates/nim_check_gate.stamp`, 체크아웃
   로컬·미추적 — 워크트리 격리 정합, pre-push는 이 게이트를 다루지 않아 간섭 없음):
   - 스탬프 존재 + `INPUT_IDENTITY` 일치 + 현재 바이너리 sha256 == `BINARY_SHA256` → **PASS**(재사용).
   - 신원 일치 + 바이너리 sha 불일치 → **FAIL**(변조·비정준 재빌드 — 결정론 재빌드는 기록 sha를 재현하므로
     어떤 재스탬프 경로도 이 사례를 수용하지 않는다).
   - 신원 불일치(또는 스탬프 손상 — 손상은 부재가 아니라 불일치로 취급) → 재스탬프는 **관측 가능한 재빌드**
     하에서만: 바이너리가 스탬프 기록 이후 재작성(bin mtime > stamp mtime) && 모든 존재 입력보다 최신.
     그 외 **FAIL**(처방).
   - 스탬프 부재(부트스트랩) → mtime 신선(모든 존재 입력보다 바이너리가 최신)일 때만 신원+sha 스탬프를
     원자적(PID 고유 tmp + mv)으로 기록 후 PASS. mtime stale → **FAIL**(처방).
   - 정상 플로우(`bin/build_all_gates --release` → commit)은 부트스트랩과 재스탬프 경로를 그대로 통과
     — "빌드 후 커밋"이 매번 PASS함을 B2가 입증.
4. **pp_* 재사용**: `.githooks/pre-push`를 `PREPUSH_SOURCE_ONLY=1`로 source(소싱 가드 `pre-push:486-492`가
   Part 4a 함수 정의 후 `return 0`). 해싱 memo(`pp_file_sha`)·배치 해싱(`pp_hash_files_batch`)·manifest
   해시 스트림(`pp_manifest_hash_stream`)·genDepend 캡처(`pp_capture_manifest`)·스탬프 디렉터리·스키마를
   중복 구현 없이 재사용. 신원 스트림 조합(빌더 신원 성분으로 Makefile sha 대체)만 설계에 따라 로컬
   합성 — VS-1의 identity 함수는 Makefile sha를 무조건 결속하므로 그대로 쓰면 설계에 없는 입력을 묶는다.
5. **진단 라인**: FAIL 시 `[Hook] nim_check_gate freshness: <사유>` 1행 추가(관측성 — VS-1의
   "Rebuilding $gate ($trigger)" 관례). 처방 3행은 원문 그대로.

## §2. 기계 검증 관측 (실험 브랜치, 구현 커밋 위)

툴체인: Nim 2.2.10, gcc 13.3.0 (Ubuntu 24.04). 스테이징 프로브: `tools/nimtry/tcb_cast_audit.nim`
(입력 집합 밖 — 게이트 입력 무변경 커밋 재현). B안 스테이징: `src/gate/runners/anti_theater_gate.nim`
(nim_check_gate closure **밖** runner — runners-union 스코프 검증). 관측 = 훅 stdout + 스탬프 내용.

| 실험 | 조작 | 기대 | 관측 | 커밋 |
|---|---|---|---|---|
| S3 부트스트랩 | 스탬프 부재 + mtime 신선(처방 빌드 직후) + 무변경 | PASS + 스탬프 기록 | PASS — `[Hook] nim_check_gate stamp recorded (bootstrap — identity+sha bound).` 스탬프: 신원 `eeed5d2c…`, sha `711a6fab…`, CLOSUE 248 + PROBE 2. 3.7s | `df41fcac4` |
| A false-stale 제거 | runner 76개 `touch`(mtime 미래화) + 콘텐츠 무변경 | PASS(구형은 FAIL) | PASS — 신원+sha 재사용, **스탬프 미재기록**(mtime·내용 불변 실측). 구형 시뮬레이션: `find -newer` 매칭 → 구형 FAIL 상황 | `aaf2683fa` |
| B 실변경 감지 | closure 밖 runner 주석 추가 + 전 runner mtime 과거(2026-11-05) 롤백 | FAIL + 처방 | FAIL(rc=1) — `[Hook] … input identity mismatch` + 처방 3행 원문. 구형 시뮬레이션: `find -newer` 무매칭 → **구형은 이 실변경을 놓침(P0-1 실증)**. runners-union이 closure 밖 변경 포착 | (없음) |
| B2 회복(정상 플로우) | B 상태 그대로 + 처방 재빌드(`build_all_gates --release`) → 재커밋 | PASS + 재스탬프 | PASS — `[Hook] … stamp re-recorded (rebuild detected…)`. 신원 `eeed5d2c…`→`759d9b78…`(주석 반영), **바이너리 sha 불변 `711a6fab…`**(주석은 코드생성 무영향 — 결정론). 29.6s(src/ 스테이징으로 Part 5 nim check 동반) | `e96098a56` |
| C 변조 감지 | 스탬프 존재 + 바이너리 마지막 바이트 `0x00`→`0xff` XOR(sha `6eb230b7…`) | FAIL | FAIL(rc=1) — `[Hook] … binary sha256 mismatch with unchanged inputs` + 처방. **변조 바이너리 실행 전 차단**(가드가 Part 1 실행에 선행) | (없음) |
| C2 치유 | C 후 처방 재빌드 → 재커밋 | PASS(sha 복원) | PASS — sha `711a6fab…` 복원(재빌드 결정론). 재스탬프 경로 통과: 재빌드 중 `src/generated/build_env.nim` 재생성(빌드 시점 git 상태 `e96098a56` 각인) → PROBE 성분 변동 → 신원 `759d9b78…`→`4af1ef19…`. **재빌드 동반 입력 변동이 재스탬프 경로로 정확히 처리** — VS-1 §3의 "의도적 정확성 비용"과 동일 클래스(실빌드가 `when fileExists` 존재 분기에서 이 파일을 import하므로 결속은 정확) | `90db446d5` |
| D(a) 부트스트랩 재기록 | 스탬프 삭제 + mtime 신선 + 커밋 | PASS + 재기록 | PASS — `[Hook] … stamp recorded (bootstrap…)`. 신원 `4af1ef19…` = C2와 **동일**(동일 트리 상태에서 신원 재계산의 결정론 실증) | `7e1f7b0e2` |
| D(b) 부트스트랩 stale | 스탬프 삭제 + 입력 mtime이 바이너리보다 미래(`touch` runner) + 커밋 | FAIL | FAIL(rc=1) — `[Hook] … bootstrap: at least one input is newer than the binary (mtime)` + 처방. **스탬프 미기록**(FAIL 선행) | (없음) |

- 게이트 바이너리 sha256(전 관측 불변·결정론): `711a6fabb3b096e72e7e5d39d77568e1be3f2974be0d050268d4225d6110dd5f`
  (C 변조 시에만 `6eb230b7…`로 일탈, 처방 재빌드로 즉시 복원).
- 판정 비용: 가드 단독 ~1.7s/커밋(genDepend 캡처 1.4s가 지배; 해싱·신원 합성 수십 ms — VS-1과 동일 계열).
- 실험 커밋·파일 변경은 PR 전에 전부 정리(`git reset --hard` 구현 커밋 + 스탬프 삭제 후 정준 재빌드·재부트스트랩).
- 빌드 실패 주입 실험은 미실시 — pre-commit에는 재빌드 경로가 없어(two-phase) 빌드 실패가 훅의 한 상태가 되지 않음.

## §3. 잔여 위험 — 부트스트랩 1커밋 창 (반박 관점)

부트스트랩(스탬프 부재)과 재스탬프(재빌드 관측)만 mtime 신호를 사용한다:

- **P0-1(롤백)은 두 경로 모두를 속이지 못한다.** 부트스트랩: 입력 mtime 과거 롤백은 "바이너리가 최신"으로
  보이게 하지만 — 그 창에서 스탬프가 기록되는 조건 자체가 mtime 신선이므로 롤백은 기록을 *방해하지
  않을 뿐*이고, 기록된 신원은 실제 콘텐츠에 결속된다(B안: 스탬프 존재 상태 롤백 변조는 전부 차단).
  재스탬프: "스탬프 기록 **이후** 바이너리가 재작성"되어야 하는데, mtime 롤백만으로는 바이너리가 재작성되지
  않는다 — B안이 정확히 이 사례를 FAIL로 실증.
- **잔여 1커밋 창**: 신원이 변한 상태에서 스탬프 이후 바이너리가 재작성됐는데 그것이 재빌드가 아니라
  변조인 경우, 재스탬프가 이를 수용할 수 있다(sha만 보면 불일치, mtime은 재작성으로 신선). 이 조합은
  "실변경 + 변조"가 동시에 일어나야 하고, 수용되는 것은 그 1커밋뿐(재기록된 신원·sha에 이후 영구 결속).
  **현행(구형 mtime 전용)과의 비교**: 구형은 (i) 실변경+mtime 롤백, (ii) 무변경+mtime 미래(false-stale),
  (iii) 변조 전 부류를 조건 없이 통과/오차 처리했다. 신 설계는 (i)·(ii)를 전부 제거하고 (iii)을 "입력
  무변경 시 영구 차단(C안), 입력 변화 동반 시 1커밋 창"으로 축소한다 — 수용 집합의 순수 축소, 즉 현행보다
  엄격. 창의 폐쇄는 pre-push Part 4의 자동 재빌드(정준 `make -B`)와 push-admissibility OID 스냅숏이
  별도 계층에서 담당한다(동일 파일에 대해 pre-push는 7쌍만 다루므로 이 게이트는 pre-commit이 유일 판정점).
- 부트스트랩 재수행 시 창은 재발하지 않는다: 스탬프 기록 이후 같은 상태의 재커밋은 D(a)처럼 신원+sha
  재사용으로 통과하며, 어떤 경로도 mtime을 판정 입력으로 되돌리지 않는다.

## §4. 랜딩 관측

(착지 후 후속 관측 슬라이스에서 기록 — VS-1 선례: 구현 PR #1284 → 수용 관측 PR #1285.
본 PR 시점의 기록 한계: 실험 관측(§2)은 완결, 랜딩·CI·merge queue 관측은 착지 후 확정.)

---

*본 문서는 pre-commit nim_check_gate content-identity 전환(VS-1 후속 슬라이스)의 착지 관측 기록이다.
재생산: 검증 브랜치에서 `git commit` 관측(훅 stdout) + `.cache/axiom/prepush/gates/nim_check_gate.stamp`.*
