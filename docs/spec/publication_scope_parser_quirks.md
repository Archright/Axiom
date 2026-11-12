# publication_scope_gate Parser Quirks (job-level `if:` guard)

> AGENTS.md §0.5 Quirk Mandate — documented language/parser quirks must live in
> `docs/spec/` and be referenced from AGENTS.md. This file documents the
> known structural assumptions of the hand-rolled line parser in
> `src/gate/runners/publication_scope_gate.nim` (Phase 3+ of the
> execution-authority contract, ADR-0021).

## Scope

The gate parses `.github/workflows/*.yml` with a **minimal line parser (no
YAML library)**. It models only the top-level contract surface:

- the `on:` trigger block
- the `permissions:` block
- **new in Phase 3+:** job-level `if:` guard lines to enforce the
  execution-authority trigger-resolution fence (`job_if_guard`).

Everything else (job bodies, step bodies, expressions, `env:`, `concurrency:`,
...) is never interpreted — the parser only needs to *not misclassify* those
lines.

## Quirks

### Q1 — Indent-4 `if:` is a job attribute; indent-6 `if:` is a step condition

The parser tracks a `jobs:` top-level state: any line at **indent 4** inside
`jobs:` whose key is `if` is collected as a **job-level guard**. A line at
**indent >= 6** (a step body) with key `if` is a step condition and is
**intentionally skipped**.

This matches the canonical layout:

```yaml
jobs:                  # indent 0
  verify-candidate:    # indent 2  (job id)
    if: <expr>         # indent 4  ← job-level guard (collected)
    runs-on: ...       # indent 4
    steps:             # indent 4
      - name: s        # indent 6
        if: always()   # indent 8  ← step condition (skipped)
```

Consequence: **a job body must never contain an indent-4 `if:`**. YAML allows
a `steps:` mapping at indent 4 with keys at indent 6; if a workflow ever nests
a mapping directly under a job with `if` at indent 4 (e.g. a job-level
`strategy:` with an `if:` key... which Actions does not interpret anyway),
the parser would collect it as a job guard → false `guard-drift`. No current
workflow does this; the parser is a drift-prevention tool, not a YAML
semantics engine.

### Q2 — Guard matching is exact (space-collapsed), not expression-equivalent

`job_if_guard` values are compared **verbatim after stripping the value and
collapsing runs of spaces**. No expression rewriting is done — `&&` chains in
a different order, extra parentheses, or single-vs-double quotes never match.
The committed guard must be the exact string the workflow carries.

Consequence: renaming any token in the guard (e.g. `run_attempt` → `attempt`)
silently fails the gate — that is the desired fail-closed behavior for a
*policy drift* guard (ADR-0021: the gate is not a security boundary, it is a
policy-drift prevention device).

### Q3 — One-directional: only rules may demand a guard

`job_if_guard` is a REQUIRED-IF-PRESENT check: when a rule declares it, the
workflow must carry a matching job-level `if:`. The reverse (a workflow's
job-level `if:` must be declared in the contract) is NOT enforced — existing
workflows legally carry their own job guards (e.g. auto_merge.yml, ci.yml).

### Q4 — Trigger semantics reused for workflow_run keys

The `on:` indent-2 parser keys are validated with the same
`isValidTriggerId` grammar (`^[a-z][a-z0-9_-]*$`). `workflow_run:`,
`pull_request:`, etc. are just keys — their nested `workflows:` / `types:`
lists (indent 4) are never validated. A declared trigger that GitHub would
reject (nested-config malformation) still parses fine here; GitHub's own
manifest validation is the backstop.

## Testing

- Embedded golden mini-workflows: `bin/publication_scope_gate --selftest`
  (cases 6/6b/6c cover guard present / absent / tampered).
- Unit tests: `tests/gate/test_publication_scope_gate.nim` ("job-level if:
  guard (execution-authority)" suite) — indent-4-vs-6 distinction, present /
  absent / tampered, empty-string rejection.
- CI wiring risk: `runRealCheck` is not invoked from CI directly; the
  selftest + unit tests are the guaranteed guard coverage, per the plan's
  Phase 3+ CI-wiring risk note.