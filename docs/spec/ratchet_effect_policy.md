# Ratchet Effect Policy

> **SSOT**: This document is the canonical reference for the Ratchet Effect technical debt management strategy.
> **Created**: 2026-06-12
> **Authority**: AGENTS.md §2.6 Incremental Principle + SonarQube "Clean as You Code" model

## Philosophy

**"과거는 격리(Lock)하고, 미래는 차단(Block)한다"**

The Ratchet Effect is a structural mechanism that ensures the codebase can only move forward, never backward. It has three phases:

| Phase | Korean | Action | Human Judgment |
|-------|--------|--------|----------------|
| **Quarantine** | 격리 | 기존 위반사항을 lock 파일에 등록하여 통과시키되 추적함 | Required (one-time) |
| **Block** | 차단 | nimtry와 pre-commit이 신규 위반을 커밋 단계에서 차단 | None needed |
| **Evaporate** | 소멸 | 코드를 수정할 때마다 자동으로 가드레일이 좁혀져 부채가 자연 소멸 | None needed |

## Mechanisms

### 1. Legacy Violations Registry

**File**: `src/gate/architecture_policy.lock` → `[legacy_violations]` section
**Violation List**: `data/legacy_violations.txt` (504 files, 1232 violations)

Files listed here have pre-existing violations that are **tolerated**. When a listed file is **MODIFIED**, it MUST comply with ALL rules (forced evolution). New files MUST NOT create violations.

### 2. Gate Exceptions with Expiry

**File**: `data/gate_exceptions.json`

Time-boxed exceptions for specific gate checks. Each exception has:
- `expires` date — mandatory review
- `review_action` — what to check at expiry
- Expired exceptions become blockers automatically

### 3. Touched-File Ratchet (nimtry)

**Script**: `tools/ci/ratchet_check.sh`

When a file in `data/legacy_violations.txt` is modified (detected by pre-commit), the ratchet check triggers:
- **Default**: Block the commit with a clear error message
- **Hotfix Override**: `AXIOM_ALLOW_LEGACY_TEMP=1` — temporary bypass with audit log

### 4. Dead Module Pruner

**Script**: `tools/ci/prune_dead_modules.sh`
**CI (RETIRED)**: `.github/workflows/prune-dead-modules.yml` — CI=0 cutover, 2026-09-20로 워크플로 삭제; 현재는 수동/로컬 실행.

Automated 3중 검증 (triple verification):
1. **rg 참조 카운트** — zero importers in src/ and tests/
2. **Forwarding Stub 검출** — stub이 import하는 모듈은 보호
3. **Export 심볼 보유** — 공개 API가 있는 모듈은 보호

Default mode: `--dry-run` (audit only). Enforce mode: `--enforce` (quarantine with 3-day grace period).

### 5. Hub Pattern (Import Encapsulation)

**File**: `src/verification/hub.nim`

All `core/` → `verification/` access must go through Hub modules. nimtry enforces this via `[forbidden_call_patterns]` in `architecture_policy.lock`.

**Strict Hub Policy**: Import additions to Hub files require architect approval.

### 6. Raises Coverage Tracker

**Script**: `tools/ci/track_raises_coverage.sh`

Tracks `{.raises: [].}` annotation coverage per layer. Target progression: 17% → 50% → 80% → 100%.

## Hotfix Override Protocol

When development urgency requires bypassing the Ratchet:

```bash
AXIOM_ALLOW_LEGACY_TEMP=1 git commit -m "hotfix: ..."
```

**Consequences**:
1. CI log records `AUDIT LOG` entry in `logs/bypass_audit.jsonl`
2. DEBT_REGISTRY automatically updated with override reason
3. Architect reviews overrides at next sprint review
4. **No permanent exceptions** — all overrides expire

## Enforcement Chain

```
Developer modifies file
       ↓
pre-commit hook
       ↓
ratchet_check.sh ──→ file in legacy_violations.txt?
       │                        │
       │ NO                     │ YES
       ↓                        ↓
  nimtry check            AXIOM_ALLOW_LEGACY_TEMP=1?
       │                        │
       │ PASS                   │ NO → BLOCK
       ↓                        │ YES → PASS (audit log)
  debt_blocker_gate
       │
       ↓
  Commit succeeds
```

## References

- AGENTS.md §2.6 — Incremental Principle
- SonarQube "Clean as You Code" — quality gate on new code only
- Nim Manual — export statement, symbol forwarding, `{.used.}` pragma
- `src/gate/architecture_policy.lock` — `[legacy_violations]` section
- `data/gate_exceptions.json` — time-boxed exceptions
- `data/legacy_violations.txt` — pre-existing violation list

## 7. Code Health Baseline (`data/code_health_baseline.json`)

Per-metric baseline for `hotspot-gate` and `debt-scan-gate`. Generated from current counts. Pre-commit ratchet compares new/changed files against this baseline; increases block the commit. Decreases are encouraged and automatically locked at next baseline refresh.

### Baseline schema

```json
{
  "version": "1.0.0",
  "generatedAt": "YYYY-MM-DD",
  "metrics": {
    "hotspot": { "total": N, "byFile": { "path": {"category": count} } },
    "debt": { "total": N, "byFile": { "path": {"category": count} } }
  }
}
```

Only files with non-zero counts appear under `byFile`.

### Refresh procedure

1. Run `nim c -r -o:bin/hotspot_gate src/gate/runners/hotspot_gate.nim . exhaustive 4`
2. Run `nim c -r -o:bin/debt_scan_gate src/gate/runners/debt_scan_gate.nim . exhaustive 4`
3. Update `data/code_health_baseline.json` with aggregated counts.
4. Open PR; architect reviews any metric increase.
