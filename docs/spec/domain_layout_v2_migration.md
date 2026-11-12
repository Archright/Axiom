# Domain Layout v4.1 SCR Migration Guide

> Migration policy for adding SCR metadata to existing domain_layout.json registry.

---

## 1. Hybrid State Policy

During the migration period, `src/gate/nimtry/nimtry_cli.nim` operates in **Legacy Mode** by default:

- Domains without SCR metadata (`owner`, `priority_score`) are classified as "Observe"
- Warning-only output, no process termination
- Migration progress is reported via `--impact-report`

### Strict Mode

Use `--strict` flag to enforce full SCR compliance:

```bash
src/gate/nimtry/nimtry_cli.nim --strict
```

This mode fails immediately on any domain missing SCR metadata. **Do not use in CI until migration is 100% complete.**

---

## 2. Migration Steps

### Phase A: Infrastructure (1 domain)

Start with the `gate` domain (already done in v4.1.0):

```json
"gate": {
  "owner": "gate-infrastructure-team",
  "priority_score": 95,
  "dependency_mask": ["core/*", "gate/*"]
}
```

Rationale: `gate` is the enforcement layer. If SCR metadata is invalid here, the entire system fails safely.

### Phase B: Core Domains (5-10 domains)

Add metadata to core business domains in order of stability:
1. `domain_types` / `types` (foundation)
2. `bmc`, `proof`, `encoding` (engine)
3. `verification`, `judge` (pipeline)
4. `gateway`, `boundary` (interface)

### Phase C: Remaining Domains (all)

Backfill all remaining domains with appropriate `owner` and `priority_score`.

### Phase D: Completion Criteria

Migration is complete when:
- `src/gate/nimtry/nimtry_cli.nim --strict` returns exit code 0
- All domains have `owner` and `priority_score`
- `--impact-report` shows `legacy_domains: 0`

---

## 3. Auto-Remediation Path

When `nimtry` detects violations, it proposes remediation:

| Violation Type | Remediation Action | Tool |
|----------------|-------------------|------|
| Missing SCR metadata | Add `owner` + `priority_score` to domain | Manual edit |
| Import path violation | Fix relative imports to absolute | [DEPRECATED] (deleted 2026-07-07) |
| Unregistered module | Add prefix to appropriate domain | [DEPRECATED] (deleted 2026-07-07) |
| Layer boundary violation | Refactor to correct layer | Manual (with `docs/spec/layered_decoupling_spec.md`) |

---

## 4. SSOT Change Safety

Before modifying `domain_layout.json`, always run impact simulation:

```bash
src/gate/nimtry/nimtry_cli.nim --impact-report > /tmp/impact_before.json
# ... edit domain_layout.json ...
src/gate/nimtry/nimtry_cli.nim --impact-report > /tmp/impact_after.json
diff /tmp/impact_before.json /tmp/impact_after.json
```

This ensures SSOT changes are **safe and predictable**.

---

## 5. Timeline

| Phase | Target Date | Domains | Gate Mode |
|-------|-------------|---------|-----------|
| A (Pilot) | 2026-06-10 | 1 (gate) | Legacy |
| B (Core) | 2026-06-17 | 10 | Legacy |
| C (Backfill) | 2026-06-24 | All | Legacy |
| D (Complete) | 2026-07-01 | All | **Strict** |
