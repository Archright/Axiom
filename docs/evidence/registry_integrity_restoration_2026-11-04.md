# Registry Integrity Restoration — 사전 증거 (2026-11-04)

> Workstream: `work/registry-integrity-restoration-2026-11-04` · BASE `76efe1fcc` (origin/main, PR #1257 병합본)
> 목적: 부채 원장(`data/debt_registry.json` · `data/debt_ledger.json`)을 실제 증거(Git 객체 · Part D 측정)와
> 일치시키고, 발견된 극장 2건을 등록·수정하며(§0.9 — 등록과 수정이 동일 PR, 조용한 패치 아님), 동일 검증이
> 기존 필수 게이트(debt-registry-gate)에서 지속 집행되도록 한다. 인간 결정 대기 항목은 확정하지 않고
> UNKNOWN으로 보존한다.
> 본 문서는 PR 생성 시점까지의 **사전 증거만** 기록한다. MERGE · required checks · merge queue 결과의
> 정본은 GitHub PR/커밋 기록이며, 본 문서에 사후 복제하지 않는다(방법 1 — GitHub가 권위자).

## 1. 변경 범위 (6경로)

| 파일 | 변경 |
|---|---|
| `tools/debt_engine.nim` | parseLedger fail-closed 재구성 (DEBT#515) · validateLedgerSemantic literal-true 폐쇄 (DEBT#514) |
| `data/debt_registry.json` | DEBT#463 five-field 복원 · #493/#495/#471 재검증·정정 기록 · #514/#515 신규 등록 |
| `data/debt_ledger.json` | BUDGET#004 current 0→2 · BUDGET#006 current 196→198 (+lastVerifiedAt) |
| `docs/DEBT_REGISTRY.md` | `--codegen` 재생성 (244→246 entries, closed 196→198) |
| `src/generated/debt_constants.nim` | `--codegen` 재생성 |
| `docs/evidence/registry_integrity_restoration_2026-11-04.md` | 본 문서 |

무변경 경계: `.github/**` · `config/` · `tests/` · `AGENTS.md` · `src/`(`src/generated/debt_constants.nim` 제외) —
신규 CI 잡·체크·게이트·스키마 개정 0건.

## 2. 극장 등록 2건 (§0.9)

### DEBT#514 — Theater/Vacuous Check (medium)

`validateLedgerSemantic`의 closed-resolution 검사가 조건 인자로 **literal `true`** 를 전달:
`check(rec.id & " closed record has resolution", true, "resolution=" & $rec.resolution)` —
판정은 필드를 읽기 전에 결정됐다. 수정은 두 후보를 검토했다:

- `rec.resolution in {rkFIXED, rkWONT_FIX}` — **기각**: `ResolutionKind`는 2값 enum이라 멤버십 검사가
  자명명제(tautology)다. literal-true를 또 다른 항상-참으로 바꾸는 것은 극장을 교체할 뿐이다.
- raw JSON 노드에서 `resolution` 필드를 직접 읽어 `status=closed`인 모든 레코드에
  `resolution ∈ {FIXED, WONT_FIX}` 요구 — **채택**: 검사가 이름이 말하는 증거(기록된 필드)를 읽는다.
  파서 회귀로 불량 레코드 유입이 생기면 이 층에서 FAIL로 드러난다(DEBT#515의 방어 심층).

### DEBT#515 — Theater/Fail-Open Parse (high)

`parseLedger`의 per-record 가드가 `echo ❌; return`으로 종료 — **첫 불량 레코드 이후 전체가 잘려나가고**,
잘린 원장이 PASS할 수 있었다. 루프 밖 가드 2종(버전 필드·records 배열 누락)도 `return`(빈 원장 →
0 체크 → exit 0)이라, 버전 불일치 분기(`quit(1)`)보다 **엄격히 관대한** 역전 상태였다. 수정:
전 레코드를 읽고 모든 결함을 보고한 뒤 `quit(1)`; ledger-수준 가드 2종도 `quit(1)`.

## 3. 부정 입력 실험 (pre-fix E1-E9 → post-fix D1-D5)

사전 실험은 pre-fix 바이너리 @ `76efe1fcc`(작업트리 clean 상태)에서, 사후 드릴은 수정·데이터 편집
이후에 실행했다. 각 드릴 후 `git checkout -- data/debt_ledger.json`으로 복원.

| 드릴 | 변이 | pre-fix 관측 | post-fix 관측 |
|---|---|---|---|
| E1 | 없음(청정 대조군) | `Loaded: 6 budget records` · PASS | PASS (1550/1550) |
| E2 | BUDGET#003 status 'accepted' | ❌ 출력 후 **`Loaded: 2 budget records`** — #003부터 뒤 전체(#003-#006) 버림 → 동기화 체크 우발 FAIL | — |
| E3 | BUDGET#003 resolution 'MAYBE' | FAIL (동일 잘림 부수효과) | — |
| E4/D2 | BUDGET#006 resolution '' | FAIL (〃) | ❌ `unknown resolution ''` + **exit 1** |
| E5 | BUDGET#006 status 'accepted' | FAIL (〃 · Loaded: 5) | — |
| E8/D1 | BUDGET#007 status 'accepted' **추가** | ❌ 출력에도 **exit 0 PASS** — #007은 존재검사 대상이 아니어서 잘려도 아무 체크가 못 잡음 | ❌ + **exit 1** (침묵 PASS 소멸) |
| D3 | version 키 삭제 | 미실행 | ❌ + exit 1 |
| D4 | records 키 삭제 | 미실행 | ❌ + exit 1 |
| D5 | #001 severity 'urgent' + #006 status 'accepted' (2결함) | — | **둘 다 보고** + exit 1 (전체 읽기 실증) |
| E7 | files[]에 죽은 경로 추가 | Projection sync/P3 FAIL | — (본 변경과 무관) |
| E9 | DEBT#493(closed) 참조 파일 실제 삭제 | **PASS** — closed 죽은 참조는 설계상 허용 | — |

핵심 대조: pre-fix의 FAIL은 레코드 드롭의 **우발적 부수효과**(동기화 불일치)였고, 결함 자체가
exit를 결정하지 않았다(E8 참조). post-fix는 결함 존재가 직접 exit 1이며, 하나의 원장에 여러 결함이
있어도 전부 보고된다(D5). 로그: `/tmp/e*.log`, `/tmp/drill_*.log`(세션 로컬 — 표의 명령으로 재현 가능).

## 4. Part D 6메트릭 실측 (평가자 빌드 후, BASE 76efe1fcc)

| 메트릭 | 평가자 실측 | 원장(편집 전) | 판정 | 조치 |
|---|---|---|---|---|
| import_lint | 0 | 0 | PASS | — |
| layer | 0 | 0 | PASS | — |
| effect | 89 | 89 | PASS — BUDGET#003 정합, 정정 불필요 | — |
| nimtry | 2 | 0 | **DRIFT** | current 0→2 |
| debt_registry_open | 48 | 48 | PASS | — |
| debt_registry_closed | 196 (편집 전) | 196 | PASS (편집 전 기준) | 신규 closed 2건 등록으로 196→**198** |

- nimtry 측정 의미: 평가자는 **baseline 대비 신규 위반**(구성: 신규 위반 1건 ax_engine.nim:4729 warning +
  에러 배너 라인 1줄 = 2, exit-code gated). evaluator docstring 원문: "data/nimtry_baseline.json is NOT
  the live measurement — it is an archived anchor snapshot and must not be used as the metric source."
- 편집·codegen 후 최종 관측: `✅ nimtry_violations PASS (projection=2 == ledger 2)` ·
  `budget BUDGET#006 expected=198 committed=198 delta=0` · **`Metric evaluation: 6 PASS, 0 DRIFT`** ·
  `Checks: 1550 total, 1550 passed, 0 failed` · validate exit 0.

## 5. 원장 정정 상세 (기계적으로 증명된 것만)

### DEBT#463 — five-field 복원 (§0.9a/DEBT#357 폐쇠 엔트리 필드 계약)

- description 내 "RESOLVED 2026-09-12: …" 서술을 `resolution`으로 이동(FIXED 접두), 원 서술 보존.
- `symbol` · `contentHash` · `lineRange` · `lastVerifiedAt` 신규 결속.
- `contentHash = sha256:7a2eef45…` — 폐쇠 커밋 `2a6b229cf` 시점 `collectCertificateContinuityFacts`
  **구현 본체**(:1036-1090)의 extractProcText 해시. 주의: 해당 스냅샷에 동명의 **본체 없는 전방선언**(:671)이
  있어 `computeProcHash` 기본 동작은 전방선언을 잡는다(hash `sha256:37832027…`, 미사용) — 폐쇠의 대상은
  구현이므로 본체 텍스트에 결속했다. 추출은 computeProcHash의 `extractProcText`를 복제(파이썬)했고,
  `tools/debt_engine.nim parseLedger` 해시(`sha256:e636bd4c…`) probe 대조로 복제 정확성을 교차검증했다.
- 폐쇠 기록이 인용한 :1036-1084는 실측 :1036-1090로 lineRange에 정정 기록(원 서술은 보존).

### DEBT#493 — 재검증 + 허위 후속 주장 정정

- `lineRange` 갱신: 현 body `:106-248`(폐쇠 시 :106-224 이후 drift), 재계산 해시
  `sha256:ebaea3f1…` 기록. 원 `contentHash`(`sha256:efd85478…`)는 폐쇠 스냅샷으로 **보존**(스냅샷 의미).
- resolutionNote 후속 (1) "process_selector … has no importers"는 **허위로 확인**:
  `src/gate/resource_guard.nim:43`이 `import ./process_selector` (git grep 실측). 정정 기록을 추가했고
  소스·원 주장 텍스트는 수정하지 않았다(역사 기록 보존 + 정정 부기).

### DEBT#495 — 재검증 기록 (재현 불가, 성공 전환 금지)

- 재계산 `extractProcText` `sha256:23110445…` ≠ 기록 폐쇠 해시 `sha256:c421cf3a…` — 폐쇠 후 소스 drift
  (스냅샷 의미상 정상). 정확한 폐쇠 상태 재현은 재시도하지 않았다. status/resolution 불변.

### DEBT#471 — 상태 기록만 (소스 무변경, §0.5c)

- `src/gate/orchestrator/hook/memo.nim:37`에 `const debtMarker471 {.axiomDebt: "DEBT#471".} = true`
  프라그마 결속 존재(kind 필드 없음). `QUIRK(DEBT#471)` 주석 마커는 소스 전체에 부재.
- lineRange의 executor.nim:831-846은 폐쇠 후 drift(gate state ledger/filterDeferredGates — 무관 코드).
  추적된 마커·소스는 수정하지 않았다(§0.5c).

### BUDGET#004 current 0→2 · BUDGET#006 current 196→198

- #004: nimtry 평가자 실측값 그대로. status closed·resolution FIXED는 **인간 판단 영역이라 불변**
  (current=2와 폐쇠 주장의 긴장은 §8로 넘긴다).
- #006: DEBT#514/#515가 closed로 등록되어 closed 수 196→198 — ledger↔registry 동기화 체크의 필수 갱신.

## 6. 설계 판정 — 철회한 확장 2건 (신규 정책 = 스펙 반전)

- **contentHash drift FAIL 검사 확장 — 철회**: contentHash는 스냅샷 의미다(스키마는 계산법·형식만 규정;
  DEBT#511 기록 원문 "the 0-token skip will correctly stop matching once the fix lands"가 skip-정지
  semantics를 명시; §0.9a theater_skip은 file+symbol+contentHash 일치 → 0-token skip). open 엔트리의
  현 소스 대조 FAIL은 문서화되지 않은 새 정책이다 — 폐쇠 해시 보존 원칙과 정면 충돌.
- **files[] 존재검사 closed 확장 — 철회**: `data/debt_schema.json` files 정의 원문 — "existence is
  enforced by debt_engine --validate **for open/deferred entries**"(historicalFiles: "existence exempt").
  도입 설계(258건 historical 이관)와 현 게이트 green(closed 50엔트리·죽은 참조 60개, E9 PASS 관측)이
  이를 확인한다. closed 확장은 50엔트리 이관을 수반하는 신규 정책 — 인간 결정 대기(§8).

## 7. 이전 조사 주장 철회·정정 (4건)

1. "closed 죽은 참조 60개 = 무결성 위반" → E9 실측: 참조 파일 삭제에도 PASS. 명시적 계약상 허용(§6).
2. "BUDGET#005 open=48 불일치" → 실측 48==48 정합.
3. "nimtry 실측 4,259" → 오독. evaluator 측정은 baseline 대비 신규 위반(=2). 4,259/4,261은 래칫 정본
   4종 보존 값(nimtry_baseline vs debt_reduction_baseline 발산 — 인간 결정 대기).
4. "#493 note (1) process_selector 무참조" → 허위(resource_guard.nim:43 import 실측). §5 정정 등록 완료.

## 8. 인간 결정 대기 (UNKNOWN — 본 PR에서 확정하지 않음)

- BUDGET#004: current=2 vs status closed/FIXED — 래칫 재평가 시점·기준(정책).
- nimtry 래칫 4-정본 발산(D1/D2: 4,259 vs 4,261).
- closed 엔트리 죽은 참조 60개(50엔트리) historical 이관 — files[] 정책 개정 필요(§6).
- `debt_schema.json` 스키마-현실 drift(DebtLedgerFile/ArchitectureDebt 브랜치 — 현행 유효 원장과 불일치).
- STALE 10 · gzip 5건 처분 · G1/G10-13 정본 · waiver 정본 — 기존 대기 항목 무변경.
- #515 잔여 구조 개선(quit 대신 오류 수집 API 반환) — 필요 시 후속 슬라이스.

## 9. 사전 증거 재현 명령

```bash
# worktree: <user-home>/worktrees/registry-integrity @ work/registry-integrity-restoration-2026-11-04
make bin/debt_engine
bin/debt_engine --codegen        # 투영 재생성 — 246 entries / closed 198
bin/debt_engine --validate       # → 1550/1550 PASS · Part D 6 PASS 0 DRIFT · exit 0
python3 tests/ci/test_debt_schema_theater_rule.py   # → PASS (실제 원장 clean)
# 부정 드릴 D1-D5: §3 표의 변이로 data/debt_ledger.json을 변경해 실행 — 전부 ❌ + exit 1,
# 실행 후 git checkout -- data/debt_ledger.json
# pre-fix 해시 probe: /tmp/hashprobe.nim(computeProcHash 재사용) — #514 pre-fix 98afb91e… ·
# #515 pre-fix e636bd4c… · #493 현 body ebaea3f1… 재확인 완료
```

## 10. 완료 판정 (Terminal Outcome — 별도 acceptance)

PR → 필수 5 checks → merge queue(merge_group) → GitHub MERGE → canonical main에서
`bin/debt_engine --validate` PASS + `git merge-base --is-ancestor "$MERGE" origin/main` —
완료는 기계 관측으로만 판정한다. MERGE·CI 결과의 정본은 GitHub다(본 문서 미기록, §서두).
