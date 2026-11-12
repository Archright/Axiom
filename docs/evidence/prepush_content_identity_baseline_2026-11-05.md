# pre-push Part 4 content identity 전환 — 기준선 관측 기록 (2026-11-05)

> **종류**: 기준선 관측 기록 (baseline observation record). **이 문서는 결정을 대리하지 않는다.**
> VS-1(Deterministic No-op Pre-push) 착지 전·후 비교를 위한 시점별 관측치의 나열만을 담는다.
> **Date**: 2026-11-05 · **Branch**: `workstream/vs1-deterministic-prepush` (off `main` @ `2b24d9285`)
> **Scope**: 본 문서 1건 — 게이트 코드·Makefile·`.githooks/**` 수정 0건 (Phase 1 이전 시점).
> **데이터 원천**: `~/.cache/axiom/push-admissibility/log.jsonl` (사용자 로컬 텔레메트리 — 관측 기록이며 판정 권위가 아님),
> `~/.cache/axiom/push-admissibility/PHASE0_FINDINGS.md` (2026-08-29 측정), 코드 정적 분석(아래 인용).

---

## §0. 측정 환경

- **기준 HEAD**: `2b24d9285` (main, merge of PR #1282) — 본 기준선은 이 시점의 main 체크아웃 관측.
- **툴체인**: Nim 2.2.10 (`~/.choosenim/toolchains/nim-2.2.10`), gcc 13.3.0 (Ubuntu 24.04), graphviz 미설치.
- **분석 방법**: `python3` JSONL 파싱 (2,307 레코드 — 1건 스킵 없음 전 수 파싱 성공).

## §1. 텔레메트리 통계 (전체·최근)

| 지표 | 값 |
|---|---|
| 총 push 관측 | 2,307건 (PASS 1,855 / FAIL 437 / 기타 상태 레코드 15) |
| duration 전체 (n=2,292) | mean 49.0s · median 46.0s · max 221.0s |
| duration 최근 100회 | mean 76.3s · median 72.0s · max 132.0s |
| duration 최근 20회 | **mean 87.3s · median 84.5s · max 128.0s** |
| 월별 mean | 2026-08: 7.7s → 09: 24.0s → 10: 63.2s → 11: 75.8s (게이트 수 확대 추세) |
| **동일 OID 재푸시** | **136개 OID가 2회 이상 push** (반복 push의 mtime/신선도 재판정 비용의 존재 증거) |

## §2. 반복 push·FAIL 패턴 관측

- 텔레메트리 스키마는 `ts/oid/ref/result/duration_s/sha256{debt_engine,check_nim_theater,doc_path_validator}/budget_s`
  — **FAIL 사유 필드가 없다** (Part 4 mtime FAIL인지 스냅숏 내 게이트 FAIL인지 기록상 구분 불가 → Phase 1 텔레메트리
  확장의 근거가 되는 갭 자체를 기록).
- 동일 OID 연속 FAIL 후 PASS 전이 다수 관측 (예: `19b0d1ab` FAIL×3→PASS, `d4259664` FAIL→PASS, `30fd016f` FAIL→PASS).
- 2026-11-05 `a874a600`(work/sal10-publication, 현 main 조상) 2연속 FAIL (18s·18s, duration 서명상 스냅숏 make 내부 실패 구간).
- FAIL 시 duration 서명 2종 관측: ~7-9s(초기 판정 실패 추정)·~35-41s(빌드 후 실패 추정) — 사유 미기록이므로 추정으로 명시.

## §3. 코드 수준 기준선 사실 (개선 전 상태 — 정적 분석 인용)

1. **Part 4의 7쌍 신선도 판정은 mtime `-nt`가 유일 관문**: `.githooks/pre-push:174-181`
   (`[ "$src" -nt "$bin" ]`, 주석 "mtime precondition — the sole FAIL basis"). content 검사 부재.
   `touch -d` mtime 롤백 시 stale 바이너리가 스냅숏에 symlink되어 실행됨(스냅숏 make는
   "prebuilt symlinks directly — no per-gate recompilation", `Makefile:462-464`).
2. **의존성 갭 실측** (closure 대비 Makefile prerequisite 밖 파일): debt_engine 47 / proof_unit_consistency 43 /
   layer_enforcement 33 / doc_path_validator 2(판정 코어 `tools/ci/doc_path_validator_core.nim` 포함) /
   check_nim_theater 1 / proof_reconcile 3 / epoch_transaction 3. 저장소 공인: `Makefile:157-158`
   "Nim lacks --depfile (verified) … accepted untracked gap".
3. **미추적 조건부 입력**: 3개 게이트(debt_engine·proof_unit_consistency·layer_enforcement)가
   `src/generated/build_env.nim`(자동생성·미추적, `when fileExists` 가드 `src/core/trusted/axiom_pragmas_types.nim:4`)
   를 import — 일 단위 TTL 판정 입력(`tools/hermetic_build.nim:866-868` BuildEnvBuildDate)이
   현재 신선도 체계에서 추적되지 않음.
4. **다중 작성 경로·플래그 편차**: 동일 `bin/<gate>`를 make(debug, NIM_TOOL_FLAGS)·pre-commit 타깃(-d:release,
   `Makefile:1252`)·Part 3(-d:danger, `.githooks/pre-push:36`)·build_all_gates(플래그 상이, debt_engine 미커버)
   가 각기 다른 옵션으로 작성 — 산출물 신원 미결속.
5. **기존 content-addressed 선례**: Part 5 `ensure_tool`(`.githooks/pre-push:79-126`)은 매 호출 sha256
   계산 + 스탬프(`.cache/axiom/prepush/<tool>.srchash`) + 자동 재빌드 — 7쌍에는 미적용.
   sha256 비용 실측: 소스 전체 610KB + 7 바이너리 6.85MB 합계 해시 7ms (판정층 도입 비용 무시 가능).

## §4. 개선후 판정 지표 (Phase 1 착지 후 동일 방법으로 재측정)

- 동일 OID 반복 push: `rebuilt_gates=0`·false-stale FAIL 0 (A안 실험)
- 갭 파일·main 모듈 외 실변경: identity 불일치→자동 재빌드 관측 (B안)
- 바이너리 변조·스탬프 삭제: 탐지→재빌드 (C·D안)
- 텔레메트리에 게이트별 verdict·rebuilt 사유 기록 (§2의 FAIL 사유 갭 폐쇄)

---

*본 문서는 VS-1 계획(`plans/jade-catwoman-hourman.md` v2 — 세션 산출물)의 Phase 0 산출물이다.
관측 수치의 재생산: `python3` + `~/.cache/axiom/push-admissibility/log.jsonl` (§0 방법).*
