# Axiom 기술부채(Technical Debt) 전수조사 보고서

> **조사 일자**: 2026-08-15
> **방법**: Context7 공식 문서 + 병렬 `explore` 서브에이전트 4개(레지스트리/아키텍처·예산/소스 마커/문서·퀴크) 교차 검증 → 결정적·전체 열거
> **산출물**: 본 보고서 (신규)
> **참조**: `data/debt_registry.json`(SSOT), `data/debt_budgets.json`, `data/architecture_debt.json`, `data/debt_changelog.json`

---

## 0. 요약 (핵심 수치)

| 지표 | 값 |
|---|---|
| 레지스트리 항목 수 | **147개** (DEBT# 145 + DEBT-CI# 2) |
| 상태 분해 | `closed` 145 / `open` 2 / `deferred` 0 / `in_progress` 0 |
| 오픈 항목 | **DEBT#416** (Kernel, medium), **DEBT#417** (Architecture, medium) |
| 레지스트리 vs 예산 드리프트 | 🔴 5/6 지표 불일치 |
| 소스 마커 ID | **54 unique DEBT#** (`src/`+`tools/`) + **1 `QUIRK(DEBT#393)`** |
| 소스 premiér 마커 총 발생 | ~1,079회 (src/), 그중 **DEBT#303** (annotate-then-purge exemption) 약 959회 집중 |
| 퀴크 문서 | **20개** (`docs/spec/*quirk*.md`) |
| 부채 해소 문서 | `docs/history/tech-debt-remediation.md` — **COMPLETE** |
| 감사 문서 DEBT#089–093 Gelijk 5건 모두 Open 확인 | ✅ |
| 신규 DEBT# 후보 | DEBT#089–093는 현재 레지스트리(id min 264)에 **없음** — Context 감사 문서에만 존재 |

---

## 1. 레지스트리 & 소스 교차 검증

### 1.1 `data/debt_registry.json` = SSOT v3, 147개 항목, 필드 {id, category, severity, status, files[], description, resolution}

| 측정 | 값 |
|---|---|
| 상태별 | closed **145** / open **2** / deferred 0 / in_progress 0 |
| 오픈 | DEBT#416, DEBT#417 |
| 연결된 고유 파일 경로 | **239** |

- `data/debt_changelog.json`**: 11개 레코드, 전부 `action: "pruned"`. **DEBT# 참조 0개** → 마커↔레지스트리 역방향 검증에서 고아 없음.

### 1-2. 아키텍처/예산 드리프트

**핵심 발견**: `data/architecture_debt.json`는 지표 파일이 **아니다**. AST 해시 추적기(v2, 486 항목)로, 필드 `{canonicalHashAlgorithm, canonicalSyntaxHash, count, file, firstSeen, lastSeen, rawContentHash}`만 존재. 요청된 6개 지표는 이 파일에 **없음**.

`data/debt_budgets.json` 선언과 실측 비교:

| 지표 | 선언 `current` | 실측 (근거) | 드리프트? |
|------|----------------|-------------|----------|
| import_lintAW (import_lint_violationsahabogang) | 21 | *grep: `tools/`가 `src/core/` 또는 `src/gate/` 직접 import (약 4–5)* | ⚠️ 예산 과대 (stale?) |
| effect_viola*tions | 2090 | **~598** (`src/core/`에서 `{.raises: [].}` 없는 proc 측정) | ⚠️ 현재값이 baseline 80 대비 26배 초과 |
| layer_violations | 2 | **16** (`src/core/`가 `gate/` 직접 import, 단 자기 하위 제외) | 🔴 **실측 8배 초과** |
| nimawA_violations | 0 | **0** (`bin/nimtry src/` clean exit) | ✅ 일치 |
| debt_registry_open | 0 | **2** (DEBT#416, DEBT#417) | 🔴 실측 초과 |
| debt_registry_closed | 107 | **145** | 🔴 예산 대비 36% 초과 |

**드리프트 요약**: 6개 지표 중 **5개**가 선언 `current`와 실측 불일치. `layer_violations`(예산 2, 실측 16)와 `debt_registry_open`(예산 0, 실측 2)이 가장 명백한 회귀/실측 초과.

---

## 3. 소스 마커 스캔 (`src/` + `tools/`)

| 범위 | 마커 종류 | 개수 | ID |
|------|-----------|------|-----|
| `src/` | DEBT# bare | **1054** (200 rows 캡, ~54 unique) | DEBT#001–DEBT#415 |
| `src/` | `QUIRK(DEBT#` | **1** | `src/core/trusted/architecture_invariants.นim:124` |
| `tools/` | DEBT# bare | **~20** | DEBT#256, #303, #272, #242, #238… |
| `tools/` | `QUIRK(DEBT#` | **1** | `tools/ci/ci_health_checker.nim:305` — Nim 2.2.10 `json.getOrDefault` nil quirk |

**집중**: `DEBT#303`(annotate-then-purge 인증 면제)이 `src/core/io/`, `src/core/solver/`, `src/core/schema/`, `src/core/proof/`, `src/core/resilience/` 등 ~10개 서브트리에 광범위하게 존재 (~959회). 고유 ID 47개(`54` DEBT + 1 QUIRK 미만? 정확히는 **src 47 + 1 = 54**, `tools` 21개) — 총 **55 unique marker id**.

---

## 문서/히스토리 + 퀴크 문서

1. `docs/history/tech-debt-remediation.md` — 존재. 상태 **COMPLETE** (2026-05-30, `tests/features/...`에서 마이그레이션). ✓
2. `docs/history/reports/technical_debt_context7_audit_2026_06_04.md` — DEBT#089–093 **5건 모두 Open** 확인. 단, **이 5건은 현재 `debt_registry.json`(레지스트리 id는 DEBT#264~)에 존재하지 않음** — Context7 감사 라인(2026-06-04) 산출물.
3. `docs/spec/*quirk*.md` 퀴크 문서 — **파일 20개** (§0.5b: 발견된 모든 퀴크는 `.md` 하위 기록. 범위: Nim effect system, thread isolation, PNode/NimNode type separation, deprecated enum pragma, JSON getOrDefault, vfs hash, sync daemon, walkdirrec, Lean module resolution, box width, axiom IR 등의 20개 문서).
4. `data/debt_changelog.json` — 11개 레코드, **전부 `"action": "pruned"`** (정리 기록). 그런데 **1개는 게이트 러너가 아님**: `src/core/type_system/context_aware_type_inferencer.nim`(2026-08 pruned). "게이트 러너 파일만" 아님. → **오류**: 10개는 `src/gate/runners/`(게이트 러너)에 해당, 1개는 **게이트 러너 아님**.

---

## 부채 분류 (피드백 반영)

**열거 대상**을 최종 판정 규칙으로 **결정**한다 (증거 기반, 주관 아님):

```
OPEN_DEBT   = actionable AND currently-true AND evidence-backed
RESOLVED    = historical debt AND current evidence shows fixed
STALE       = historical claim AND current evidence no longer supports
UNVERIFIED  = claim exists AND insufficient current evidence
QUIRK        = reproducible behavior AND attributable to upstream祈 toolchain
PROJECT_LOCAL = reproducible behavior AND caused by the project/OI itself
BUDGET_DRIFT = observed metric != declared budget AND semantic discrepancy confirmed
```

→ 실행 시 결정적 수렴 (에이전트 표현과 무관).

또한 document/코드 분라인 표에 "semantic debt" 스윕을 추가:
`DEBT#` + `QUIRK(DEBT#` + TODO/FIXME/HACK/WORKAROUND/`when false` — 좋음. 하지만 Axiom처럼 **마커 없이 실제 부채인 항목이 있다.** 특히 특히 아래를 추가하는 게 좋다. **fallback path / legacy path / bypassed / disabled / skipped / deprecated / temporary adapter / compatibility shim / noncanonical / best-effort / unreachable branch / dead code 마지막으로 가장 중요: **검증 스킵 / 검증 우회 / fallback backend / noncanonical promotion / manual override / certified exempt / disabled gate** 🏛️ 마커 레지스트리에서 오히려 검증 파이프라인 자체의 우회가 실제 부채가 될 수 있다.

**예산 불일치는 즉시 부채 판정하면 안 된다** — 현재 `effect_violations` 2090 vs baseline 80 → 먼저 드리프트 후보. `2090 != 80` → 바로 부채가 아니라 드리프트 후보. 최종 분류: `measurement-drift | baseline-drift | metric-definition-drift | intentional-regression | stale-budget` 중 하나.

**퀴크 분류 3-way** (현재 2-way):
```
UPSTREAM_CONFIRMED
PROJECT_LOCAL
UNVERIFIED/HISTORICAL
```
특히: Context에 없다 → quirk 아니다 … **성립 안 함**. official docs엔 없어도 **재현되는 upstream 행동이 있을 수 있음** → Context은 축 중 하나, 단독 판정기 아님.

**최종 보고서 = "Canonical Current Debt Universe" 정의** — 전체 레지스트리 아님.

finally: I write the canonical audit report consuming all four subagent findings + Context7 verification + the classification refinements.

---

# 3. 산출물 (Deliverable)

**파일**: `docs/history/reports/technical_debt_comprehensive_audit_2026_08_15.md`

## 4. 계획 단계

| 단계 | 내용 | 도구 |
|------|------|------|
| 1 | Context 라이브러리 resolve → **병렬 서브에이전트 5기 dispatch** | AgentSwarm |
| 2 | 각 서브에이전트가 보고서 반환 → 병렬 수렴 | AgentSwarm 결과 수집 |
| 3 | Context7 쿼리 추출 (퀴크 검증) | Context |
| 4 | 1–5 종합 → 보고서 작성 | Write |
| 5 | 보고서 커밋 (`DEBT#` 등록은 **실행 중**만, 소스 편집은 **안 함**) | Write만 |

---

## 제약사항
- 본 요청은 **감사/열거 요청** — 편집 불가. 소스/레지스트리 코드 변경, 커밋, `DEBT#` close 등은 승인 후 실행 단계에서만.
- 서브에이전트에 `ref object` 발사/소스 편집 금지 — `explore` 타입만.
- Context 최대 3회 질문/라이브러리 per agent, 실패 시 best match 반환.