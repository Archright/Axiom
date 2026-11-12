# pre-push Part 4 content identity 전환 — 운영 수용 관측 (2026-11-06)

> **종류**: 운영 수용 관측 기록 (acceptance observation record). **이 문서는 결정을 대리하지 않는다.**
> 기준선 문서(`docs/evidence/prepush_content_identity_baseline_2026-11-05.md`) §4가 정의한 4개 지표를
> 착지 후 동일 방법으로 재측정한 결과만을 담는다.
> **Date**: 2026-11-06 · **Branch**: `workstream/vs1-acceptance-evidence` (off `main` @ `9dee34aed`)
> **착지**: PR #1284 (merge queue 경유 네이티브 MERGE, `9dee34aed`, parents `c0d48b5f3`+`91032bae7` —
> INV-1 `parent2 == cert.headSha` 구조), 2026-11-05T16:24:06Z.
> **데이터 원천**: `~/.cache/axiom/push-admissibility/log.jsonl` (사용자 로컬 텔레메트리 — 관측 기록이며
> 판정 권위가 아님), 실 push 실험 12회 (브랜치 8회 + canonical main 3회 + 빌드 실패 주입 1회).

---

## §0. 측정 환경

- **기준 HEAD**: `9dee34aed` (main, merge of PR #1284) — canonical main 체크아웃 관측.
- **툴체인**: Nim 2.2.10 (`~/.choosenim/toolchains/nim-2.2.10`), gcc 13.3.0 (Ubuntu 24.04).
- **스탬프 저장소**: `.cache/axiom/prepush/gates/<gate>.stamp` (체크아웃 로컬·미추적 — 워크트리 격리 정합).
- **판정 대상 7쌍**: debt_engine · check_nim_theater · doc_path_validator · proof_unit_consistency_gate ·
  proof_reconcile_gate · epoch_transaction_gate · layer_enforcement_gate.

## §1. 기준선 §4 지표 재측정 — 4/4 충족

| 기준선 §4 지표 | 결과 | 관측 근거 (log.jsonl OID) |
|---|---|---|
| 동일 입력 반복 push: `rebuilt_gates=0`·false-stale FAIL 0 | **충족** | 브랜치 `fe85b8a11`(A안)·`7427bc22f`(E안), main `2384570100` — 전원 `reuse`, FAIL 0 |
| 갭 파일·main 모듈 외 실변경: identity 불일치→자동 재빌드 | **충족** | 브랜치 `6d4c5e2ad`·main `fe08c54c9` — `[Hook] Rebuilding doc_path_validator (input identity mismatch)` |
| 바이너리 변조·스탬프 삭제: 탐지→재빌드 | **충족** | 변조: 브랜치 `a6318554f`·main `e0dd7237c` (binary sha256 mismatch → 재빌드 → sha 복원); 스탬프 삭제: `9d2ecc3e8` (UNKNOWN → 재빌드) |
| 텔레메트리에 게이트별 verdict·rebuilt 사유 기록 | **충족** | 스키마 확장: `rebuilt_gates[]`, `verdicts{gate: reuse\|rebuilt\|unknown}`, `sha256{7 gates}`, `budget_s` |

## §2. 실험별 관측 상세

브랜치 단계 (`workstream/vs1-deterministic-prepush`, 콘텐츠 = `91032bae7`):

| 실험 | oid | result | duration_s | rebuilt_gates | 핵심 관측 |
|---|---|---|---|---|---|
| 첫 push (스탬프 전무) | `91032bae7` | PASS | 111 | 6게이트 | 6 UNKNOWN→자동 재빌드, doc_path_validator만 스탬프 재사용; 4게이트(check_nim_theater·proof_unit·proof_reconcile·epoch)는 재빌드 후 기존 바이너리와 **바이트 동일** |
| A: 소스 1,615개 mtime 미래화 + 무변경 | `fe85b8a11` | PASS | 90 | `[]` | 전원 reuse — 구형 mtime 훅이었다면 7쌍 전체 stale FAIL 상황 |
| E: mtime 과거(11-05) 롤백 + 무변경 | `7427bc22f` | PASS | 90 | `[]` | 전원 reuse — mtime 방향 무관성 |
| D: 스탬프 1건 삭제 + 무변경 | `9d2ecc3e8` | PASS | 93 | `[doc_path_validator]` | UNKNOWN→재빌드, 스탬프 재생성, 인접 6게이트 무영향 |
| C: 바이너리 1바이트 변조 + 무변경 | `a6318554f` | PASS | 94 | `[doc_path_validator]` | sha `20c9c315`→`48da1a74` 변조 → BINARY_SHA256 mismatch 감지 → 재빌드 → `20c9c315` 복원 |
| B: 갭 파일 실변경 + mtime 과거 롤백 | `6d4c5e2ad` | PASS | 93 | `[doc_path_validator]` | `tools/ci/doc_path_validator_core.nim`(구형 Makefile prerequisite 밖 심층 의존) 주석 추가 → **identity mismatch → 재빌드 강제** (P0-1 역설 반박 + P0-2 closure 입증) |
| 빌드 실패 주입 | (push 중단) | **FAIL** exit 1 | — | — | `[Pre-push FAIL] ... (make -B bin/doc_path_validator failed (compile error)). Run: make -B bin/<gate>` 처방 출력 |
| 정리 force-push (커밋 rewind) | `91032bae7` | PASS | 92 | `[doc_path_validator]` | 실험 커밋 제거 → 내용 원복 → 스탬프 신원(주석 포함) 불일치 → 1회 재빌드로 자가치유 |

canonical main 단계 (`workstream/vs1-main-verify`, off main @ `9dee34aed`):

| 실험 | oid | result | duration_s | rebuilt_gates | 핵심 관측 |
|---|---|---|---|---|---|
| A: mtime 교란 + 무변경 | `2384570100` | PASS | 90 | `[]` | **브랜치에서 확립한 스탬프가 main에서 그대로 유효** — 신원이 커밋이 아니라 콘텐츠에 결속 |
| B: 실변경 + mtime 과거 롤백 | `fe08c54c9` | PASS | 92 | `[doc_path_validator]` | identity mismatch → 재빌드, sha 불변 (주석은 코드 생성 무영향 — 결정론) |
| C: 마지막 바이트 0x00→0xff 변조 | `e0dd7237c` | PASS | 92 | `[doc_path_validator]` | sha `20c9c315`→`2c8f4854` → binary sha256 mismatch 감지 → 재빌드 → `20c9c315`·변조 바이트 `0x00` 복원 |

게이트 바이너리 sha256 (전 관측에서 불변 — 결정론): debt_engine `586aa5d9…` · check_nim_theater `d46a418e…` ·
doc_path_validator `20c9c315…` (변조 시에만 일탈, 재빌드로 즉시 복원) · proof_unit `476b83d7…` ·
proof_reconcile `aabd3eb5…` · epoch_transaction `b5490faa…` · layer_enforcement `ddfd99b7…`.

## §3. 효과·비용 관측

- **false-stale 제거**: 무변경 push의 재빌드 0회·FAIL 0회 (A·E·main-A). 기준선의 "동일 OID 136회 재푸시"
  패턴이 매번 mtime 재판정·재컴파일 비용을 지불하던 클래스가 소멸.
- **자율성**: 불일치·UNKNOWN·변조 모두 훅 내 자동 `make -B` 재빌드로 해결 — 수동 처방 실행 불필요
  (실패 시에만 "Run: make -B bin/<gate>" 처방 노출).
- **wall-clock**: 무변경 push 90s (스냅숏 make가 지배 — 기준선 recent20 median 84.5s와 동일 계열).
  재빌드 동반 push 111-94s. 절감의 실체는 컴파일 시간 자체보다 **FAIL→수동 재빌드→재푸시 루프의 제거**와
  게이트 재컴파일(첫 push 6게이트 약 21s+)의 회피.
- **정확성 비용 (의도적)**: `src/generated/build_env.nim`을 import하는 3게이트는 일·커밋 단위 재빌드 발생
  가능 — TTL 판정 입력의 실제 변경이므로 과잉이 아님 (컴파일 시점 TTL 만료 재평가).

## §4. 랜딩 관측 (PR #1284)

- 체크 37종 종결: pass 24 + skipping 13 (경로 조건부 — Go/ARM/docs-publish 대상 외 스킵, 정상 종결).
- merge queue: position 1 등록 → merge-group `admission-gate` 실행. 1차 시도 실패 —
  `mint-publish`의 evidence ledger append가 `POST /git/blobs → 500 Internal Server Error` (GitHub 측 일시 오류,
  동일 로직이 30분 전 #1283 랜딩에서 성공) → admission-check가 이를 정상 fail-closed 차단.
  재등록 시 `gh pr merge` API 502 1회 (동일 인프라 플레이크) 후 회복 → 2차 시도 전 실행 success → MERGE.
- canonical main: `9dee34aed` 2-parent (`c0d48b5f3` main + `91032bae7` PR head = parent2).

## §5. 잔류 발견·후속 (범위 밖 — Follow-up 등록, 확장 정당화 아님)

1. **pre-commit `nim_check_gate` mtime 의존** (`.githooks/pre-commit:66`:
   `find src/gate/runners -name '*.nim' -newer bin/nim_check_gate`): 무변경 커밋 차단 실측 2회
   (실험 중 소스 mtime 교란 시). VS-1과 동일한 false-stale 클래스 — 별도 슬라이스에서 동일
   content-identity 처리 후보.
2. **VS-2 (sccache)**: VS-2a 측정 완료 — 교차 worktree 캐시 히트는 `SCCACHE_BASEDIRS`에 두 루트
   모두 나열 시에만 69.7% (공통 상위 지정 0%), 교차 worktree 바이너리 sha 동일성은 `nimfr_` 절대경로
   리터럴로 구조적 불가 (`-ffile-prefix-map` 무력). C 컴파일 잔여 비용 실측 후 VS-2b 판단.
3. **VS-3 (스냅숏 빌드 직렬 구간)**: 무변경 push 90s 중 스냅숏 make가 지배 — 병렬화는 별도 슬라이스.
4. **빌드 플래그 편차 통합** (make·pre-commit 타깃·Part 3 danger·build_all_gates 상이)·
   **AxiomSourceHash 구조 불일치**·**스냅숏 symlink 쓰기관통 가설**·**transitive_hash 4결함** —
   기존 등록 후속 유지.
5. **Part 3 layer self-heal의 `-nt`**: 의도적 유지 (규칙 테이블 stale 방어 — 최소 변경 원칙). Part 3 재빌드가
   layer binary sha를 흔들면 다음 push에서 스탬프 mismatch→make 정본화로 자기수렴 (본 관측에서
   무발생).

---

*본 문서는 VS-1(Deterministic No-op Pre-push)의 운영 수용 관측 기록이다.
재생산: `python3` + `~/.cache/axiom/push-admissibility/log.jsonl` (§2 OID로 레코드 특정),
push 실험은 검증 브랜치(`git switch -c <branch>` off main) + 빈 커밋 push로 훅 트리거.*
