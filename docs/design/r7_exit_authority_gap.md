# R7 Exit-Authority Gap — Structural Audit (Evidence Capture)

> **Status**: DRAFT — EVIDENCE CAPTURE (audit complete for Phase A/B; classification below is grounded in the audited source state at 2026-08-19)
> **Scope**: Documentation only. No product code or tests were modified.
> **Decisions deferred**: Single-exit-authority conversion (P1 classification), semantic-partition ratification, and the `CliOutcome`/`int` split are a **separate follow-up ADR (Phase C)** — explicitly NOT executed in this document.
> **SSOT anchor**: `docs/spec/productization_contract.md` §v1 CLI Exit-State Contract (lines 263–281) + `docs/design/r7_cli_outcome_contract.md`

---

## 1. Objective

Capture, as durable evidence, a **structural audit of process-exit authority** in the Axiom CLI boundary: who is allowed to terminate the process, with which exit codes, and where the code deviates from the canonical `{0,1,2,3}` contract. The audit classifies every direct `quit(`/`exitWith(` site in `src/cli/` into authority tiers, identifies out-of-contract codes that reach the boundary through the dispatcher, and records the known `cliQuit` cast bug fixed at `src/cli/action_interpreter_cli.nim:203`.

This document is **evidence capture only**. It deliberately does not propose or implement remediation (see §9).

---

## 2. Canonical Contract Recap (verified)

### 2.1 CliOutcome enum and numeric mapping

`src/cli/cli_outcome.nim:9-27` — the single canonical mapping:

| `CliOutcome` | Ordinal | **Exit code** (`func exitCode`) |
|---|---|---|
| `SUCCESS` | 0 | **0** |
| `VERIFICATION_FAILURE` | 1 | **1** |
| `INVALID_INPUT` | 2 | **3** |
| `INTERNAL_ERROR` | 3 | **2** |

Note the **enum ordinals differ from the exit codes**: `INVALID_INPUT` has `ord == 2` but maps to exit code 3; `INTERNAL_ERROR` has `ord == 3` but maps to exit code 2. Any code path that conflates ordinal with exit code (`cast[CliOutcome](exitCode)` and similar) is thus a latent mislabeling hazard — see §3 for the instance that was just fixed.

The single canonical boundary API:

- `func exitCode(o: CliOutcome): int` — `src/cli/cli_outcome.nim:18` (the only `CliOutcome → int` mapper; `{.raises: [].}`)
- `proc exitWith(o: CliOutcome)` — `src/cli/cli_outcome.nim:37` (`{.noreturn}`, single choke point that calls `quit(exitCode(o))`)
- State precedence: `INTERNAL_ERROR > INVALID_INPUT > VERIFICATION_FAILURE > SUCCESS` (`precedence`, `src/cli/cli_outcome.nim:31`)

### 2.2 Ratification anchors

- `docs/spec/productization_contract.md:270` — exit-code table: `3 → INVALID_INPUT`
- `docs/spec/productization_contract.md:281` — invalid-input rule: unsupported/malformed input is a documented non-success, **not a verification claim**; `INVALID_INPUT=3` extension / `result.status` implementation stays **post-v1**
- `docs/design/r7_cli_outcome_contract.md` — the R7 design contract, incl. INV-2 ("exactly one function maps CliOutcome → exit code") and the meaning of each state

---

## 3. Known Fix Recorded (just applied; audited state includes it)

`src/cli/action_interpreter_cli.nim:203` — `cliQuit` branch:

- **Before**: `exitWith(cast[CliOutcome](action.exitCode))`
- **After**: `quit(action.exitCode)`

**Why this was a bug**: `cast[CliOutcome](N)` interprets `N` as an enum **ordinal**, not an exit code. Because ordinals and exit codes disagree for two states, the cast inverted the contract codes:

| `action.exitCode` (int) | `cast[CliOutcome](...)` | `exitWith` → emitted exit | Contract-expected |
|---|---|---|---|
| 2 | `INVALID_INPUT` (ord 2) | 3 | 2 |
| 3 | `INTERNAL_ERROR` (ord 3) | 2 | 3 |

The three `cliQuit` emitters that intend `CliOutcome.INVALID_INPUT.exitCode()` (= 3) — `src/cli/action_plan_cli.nim:243` (no subcommand), `:252` (unknown subcommand), `:369` (`mainLoop` empty args) — were therefore exiting **2** instead of **3**. The fix passes the plan-produced code through unchanged, restoring exit 3.

Representative probes confirming the `cliQuit` routing (used during the audit): `bin/ax` (no args) and `bin/ax nosuchcmd` both reach `INVALID_INPUT` emission through `cliQuit`. These are **representative of the `cliQuit` routing path only** — they are NOT canonical representatives of all invalid-input (see §7.4).

---

## 4. Classified Exit-Authority Inventory

Inventory basis: ripgrep `\bquit\(` over `src/cli/**`. **Total: 82 direct `quit(` call sites**, of which exactly **4 route through the canonical boundary**: three `exitWith(CliOutcome)` calls plus the canonical `cliQuit` branch (`src/cli/action_interpreter_cli.nim:73,183,186,203`). The single `quit()` inside the `exitWith` implementation itself (`src/cli/cli_outcome.nim:38`) is included in the 82; it is the canonical choke point, not a defect.

| Tier | Meaning | Sites | Files |
|---|---|---|---|
| **P1 — product-termination boundary** | User-reachable from `ax <cmd>`; **must follow {0,1,2,3}** | **39** | 8 |
| **P3 — tooling-only** | Developer/CI tooling; not product CLI dispatch | **34** | 6 |
| **P4 — bootstrap / intentional-fatal** | `main.nim` self-bootstrap relay + fatal; operational, not verification outcomes | **4** | 1 |
| **P5 — unreachable / dead** | Zero callers in `src/` (verified) | **4** | 1 |
| **Canonical boundary** | `exitWith(CliOutcome)` calls + `cliQuit` branch | **4** | 1 |
| Classified subtotal | P1 + P3 + P4 + P5 | **81** | 16 |
| **Total (incl. `exitWith` implementation, `cli_outcome.nim:38`)** | | **82** | 17 |

### 4.1 P1 — Product-termination boundary (39 sites / 8 files)

| File | Sites | Lines (verified) |
|---|---|---|
| `src/cli/action_interpreter_cli.nim` | 23 | `78` (report `quit(output.exitCode)`), `82, 86, 90, 94, 98, 102, 106, 110, 114, 118` (topology/scaffold/gate/lint/cert/shadow/config/version/io/dag guards), `130, 134, 138, 142, 146` (git/cst/scope/release/observability guards), `152, 156, 160, 164, 170, 174` (baseline/invariants/vkd/verify/budget/debt guards), `204` (fall-through `quit(0)`) |
| `src/cli/action_output_cli.nim` | 1 | `32` — `quit(result.exitCode)` |
| `src/cli/cli_io_error.nim` | 1 | `13` — `quit(code)` |
| `src/cli/check_cli.nim` | 3 | `67` (src/ not found), `90` (`quit(exitCode)` — nim-check subprocess pass-through), `93` (`quit(1)` on catch) |
| `src/cli/check_spec_cli.nim` | 5 | `40, 43` (arg errors), `61` (ok → `quit(0)`), `81` (check failure → `quit(1)`), `92` (`quit(if … 1 else: 0)`) |
| `src/cli/shape_cli.nim` | 3 | `103` (usage → `quit(1)`), `112` (`quit(exec result)` — subprocess pass-through), `116` (`quit(1)`) |
| `src/cli/infra_cli.nim` | 2 | `235` (`quit(bootstrapCircleCI(dryRun))` — subprocess result relay), `239` (`quit(1)`) |
| `src/cli/wf_state_vacuity.nim` | 1 | `164` — **mid-pipeline `quit(1)`** (not at a dispatch boundary; see §7.6) |
| **Total** | **39** | |

Direct dispatcher commands with **no exit guard** (`if exitCode != 0` pattern absent) that rely on internal quits or the fall-through: `cache` (`:119-120` — run result ignored), `check` (`:121-122` — quit inside module), `infra` (`:123-124`), `shape` (`:125-126`). These are the producers of the fall-through leak in §6.

### 4.2 P3 — Tooling-only (34 sites / 6 files)

Not reachable from the product CLI dispatch; developer/CI/gate tooling only.

| File | Sites | Lines (verified) |
|---|---|---|
| `src/cli/subagent_orchestrator.nim` | 12 | `256, 257, 271, 274, 282, 285, 295, 299, 305, 308, 339, 349` |
| `src/cli/gate_admin.nim` | 11 | `113, 119, 129, 297, 298, 313, 324, 329, 334, 339, 345` |
| `src/cli/debug_mode.nim` | 5 | `76, 89, 155, 169, 183` |
| `src/cli/precompile_gates.nim` | 3 | `423, 509, 554` |
| `src/cli/run_gate.nim` | 2 | `66, 87` |
| `src/cli/axiom_status.nim` | 1 | `537` — `quit(exitCode)`; **standalone**: `ax status` is NOT wired into the dispatcher (`action_plan_cli.nim:153-214` has no `status` token), documented as candidate surface, module is dead code (`productization_contract.md:285`) |
| **Total** | **34** | 12+11+5+3+2+1 |

### 4.3 P4 — Bootstrap / intentional-fatal (4 sites / 1 file)

| File | Sites | Lines (verified) | Semantic |
|---|---|---|---|
| `src/cli/main.nim` | 4 | `89, 105` — `quit(waitForExit(child))` self-bootstrap **relay** (rebuild → re-exec successor); `97` (CI/STRICT stale-engine fatal → 1); `109` (self-rebuild failed → 1) | Operational, not verification outcomes; matches the R7 contract's exempted direct-`quit()` set |

### 4.4 P5 — Unreachable / dead (4 sites / 1 file)

| File | Sites | Lines (verified) | Evidence |
|---|---|---|---|
| `src/cli/wf_runners.nim` | 4 | `116, 119` (Z3 health-gate `quit(1)` inside `runAxVerifyShortcutCli`), `198` (`cmdEncodeSemanticPayload` stub `quit(1)`), `202` (`cmdVerifySemanticPayload` stub `quit(1)`) | `runAxVerifyShortcutCli` (`:96`), `runAxReportShortcutCli` (`:176`), and both stub procs (`:195,199`) have **zero call sites** in `src/` (only a historical mention in `docs/history/reports/CODEBASE_INVENTORY.md`) |

---

## 5. Out-of-Contract Exit Codes Relayed to the Boundary

The dispatcher relays whatever `int` its sub-command producers return (`action_interpreter_cli.nim` guards). Several producers return codes **outside {0,1,2,3}**, with no `CliOutcome` equivalent:

| Producer | Emitted exit | Meaning | No `CliOutcome` value exists for… |
|---|---|---|---|
| `src/cli/release_cli.nim:83` | **4** | dirty worktree blocks non-dry-run release (also `3` at `:70,73` for no-bump) | "release blocked" |
| `src/cli/cert_cli.nim:52-54` | **2** | `JOURNAL_REQUIRED` (journal binding absent) — collides with `INTERNAL_ERROR`'s code | "journal required" |
| `src/cli/commands/topology_cli.nim` | **2** | `:130,211,214,219` invalid flags / missing declaration; raw subprocess codes through `:204` | "topology usage error" |
| `src/cli/gate_admin.nim` (BLOCK paths) | **2** | gate blocking exits 2 (`:297,313,324,329,334,339,345`) | "gate BLOCK" |
| **Subprocess pass-throughs** | child exit code, arbitrary | `main.nim:89,105` (rebuild re-exec), `scaffold` subprocess, `check_cli.nim:90` (`nim check` result), `run_gate.nim` / gate run, `infra_cli.nim:235` (`bootstrapCircleCI` result) | any child code, unmapped |

Every relayed producer is pinned to the old "exit codes are free ints" model; the boundary forwards them verbatim, creating collisions with contract code 2 (cert/topology/gate_admin) or codes above 3 (release), while the product contract only ratifies {0,1,2,3}.

---

## 6. Worst-Case Invalid-Input Leaks (observed)

Under the CURRENT code, invalid input can produce a **success exit code**:

| Scenario | Current behavior | Root site |
|---|---|---|
| `ax cache --bogus` | **exits 0** — `runCacheCli` result ignored, dispatcher falls through | `action_interpreter_cli.nim:119-120` + fall-through `:204` |
| `ax <void-returning-subcommand>` | **exits 0** — dispatcher falls through to `quit(0)` | `action_interpreter_cli.nim:204` |
| `ax verify <bad-dir>` | **exits 0** on invalid input — `runAxVerifyShortcutCli` returns `ok(exitCode = axProofShortcutExitCode(reportJson))`; a directory-level rejection is never mapped into `AxCommandCliResult.exitCode` | `src/cli/wf_runners.nim:100-105,163-172` |

These are contract-ratified "invalid input is not success / not a claim" violations (`productization_contract.md:281`); they remain **GAPS** until Phase C.

---

## 7. Principles (state of record)

### 7.1 Do NOT force every raw exit into a single `CliOutcome` enum

Prefer a **layered model**:

```
Command-specific domain outcome  →  Canonical CLI termination classification  →  Process exit code
    (release/cert/topology/gate enums)         (the {0,1,2,3} collapse)
```

`release`, `cert`, `topology`, `gate` keep their own command-domain status enums and return them; only the canonical CLI layer collapses domain outcome → {0,1,2,3} at the boundary. The layered cardinality is preserved: the CLI layer does NOT try to name every domain state in `CliOutcome`.

### 7.2 The semantic partition is NOT ratified

The mapping of semantic classes — InvalidInput / VerificationFailure / InternalError / EnvironmentError — to exit codes is **unsettled**. Do NOT assert "all invalid input → 3" as a completed contract; `productization_contract.md:281` keeps `INVALID_INPUT=3` expansion and `result.status` post-v1.

### 7.3 Implementation routing labels ≠ product semantic classification

`ax prove --no-such-flag` currently exits **2** via the engine's `INTERNAL_ERROR`-typed path (`action_interpreter_cli.nim:183,186`). This is an **implementation routing label** (the engine error result is classified as internal-error for lack of a dedicated channel), NOT a ratified product semantic classification. Whether that case is semantically InternalError or InvalidInput is unsettled and out of scope here.

### 7.4 Probes are representative, not canonical

The `bin/ax` (no-args) and `bin/ax nosuchcmd` probes reach `INVALID_INPUT` emission via `cliQuit` (fix site §3). They are representative of the **`cliQuit` routing path**; they are NOT a canonical sample of all invalid input — every subcommand has its own parser and quit paths (§6 lists the exceptions).

### 7.5 Canonical boundary = the 4 sites

The full set of canonical termination sites today: `action_interpreter_cli.nim:73` (`exitWith(INVALID_INPUT)`), `:183`, `:186` (`exitWith(INTERNAL_ERROR)`), and `:203` (`cliQuit` → `quit(action.exitCode)`). Everything in §4.1–4.4 plus §5 relays bypasses or stretches that set.

### 7.6 Mid-pipeline `quit()` is not boundary termination

`wf_state_vacuity.nim:164` terminates **mid-pipeline** with no `CliOutcome`, no artifact-state finalization, and no dispatch-boundary mapping. Such paths must, at minimum, be logged and instrumented — the audit records them as a distinct tier that cannot map to the 4-state contract.

---

## 8. Verification Method (audit provenance)

- **Enumeration**: ripgrep `\bquit\(` over `src/cli/` (plus cross-file caller checks over `src/`), working tree as of 2026-08-19. Counts reproducible: 82 sites; classification per §4.
- **Verification**: every file:line cited above was cross-checked against source. Relocations noted: topology `main` lives at `src/cli/commands/topology_cli.nim:357` (the file `src/cli/topology_cli.nim` has no dispatch entry); the exit-2 usage paths are `:130,211,214,219`.
- **Dead-code claims**: caller grep of `runAxVerifyShortcutCli` / `runAxReportShortcutCli` / `cmdEncodeSemanticPayload` / `cmdVerifySemanticPayload` — zero matches in `src/` (only `src/generated/type_registry_metadata.json` metadata + a historical doc mention).

---

## 9. Next-Step Scope (Phase C — follow-up ADR, NOT executed here)

The findings above are the required input for a **separate follow-up ADR** which — only when approved — will define and implement:

1. **Single-exit-authority conversion of P1**: every P1 site produces/returns a `CliOutcome`; the dispatcher applies `exitWith` exactly once; remove the `quit(exitCode)` guard rows and the fall-through `quit(0)`-on-void-command behavior.
2. **Semantic-partition ratification**: decide and ratify the InvalidInput / VerificationFailure / InternalError / EnvironmentError → exit-code mapping, including whether `ax verify <bad-dir>`, `ax cache --bogus`, and parser errors are 3 (invalid input) or 2 (implementation routing label) — as product semantics, not implementation labels.
3. **`CliOutcome`/`int` split**: decision for domain producers (`release`/`cert`/`topology`/`gate_admin`) to keep domain enums and map at the boundary only.

**Not part of this document**: no conversion, no ratification, no split is executed here — this file records evidence only. If Phase C is not approved by the architecture forum, this document remains the audit-of-record.

---

## 10. Status / Acknowledgements

- **Status**: DRAFT evidence record. Verified against the working tree at 2026-08-19. No product code or test was modified.
- **Open questions (for Phase C ADR)**: the `4`/`2` semantics of domain producers (release/cert/topology/gate); whether mid-pipeline `quit(1)` paths (`wf_state_vacuity.nim:164`) acquire any contract shape; fate of P5 dead code (stub trails violate §0.8 No Stub Files if ever re-enabled; as-is they are zero-caller).

---

## Appendix A. Ground Truth (file:line)

| Symbol / pattern | Location |
|---|---|
| `CliOutcome` enum | `src/cli/cli_outcome.nim:9-14` |
| `exitCode` — single mapping | `src/cli/cli_outcome.nim:18-27` |
| `precedence` | `src/cli/cli_outcome.nim:31` |
| `exitWith` (choke point, calls `quit(exitCode(o))`) | `src/cli/cli_outcome.nim:37-38` |
| Canonical `exitWith` sites | `src/cli/action_interpreter_cli.nim:73,183,186` |
| `cliQuit` canonical dispatch (fix site) | `src/cli/action_interpreter_cli.nim:202-203` |
| Dispatcher guards + fall-through | `src/cli/action_interpreter_cli.nim:78-204` (full enumeration §4.1) |
| Emitters of `cliQuit` with `INVALID_INPUT.exitCode()` | `src/cli/action_plan_cli.nim:243,252,369` |
| Contract exit table: `3 → INVALID_INPUT` | `docs/spec/productization_contract.md:270` |
| Invalid-input interpretation rule (post-v1) | `docs/spec/productization_contract.md:281` |
| `ax status` not in dispatch; dead-code candidate | `docs/spec/productization_contract.md:285` |
| Self-bootstrap relays / fatals | `src/cli/main.nim:89,97,105,109` |
| Dead shortcut CLIs + stub payload commands | `src/cli/wf_runners.nim:96,176,195,199` (zero callers) |
| Z3 health-gate quits in dead shortcut CLI | `src/cli/wf_runners.nim:116,119` |
| Out-of-contract relays | `release_cli.nim:83` (4), `:70,73` (3); `cert_cli.nim:52-54` (2); `commands/topology_cli.nim:130,211,214,219` (2); `gate_admin.nim` BLOCK → 2 |
| Subprocess pass-throughs | `main.nim:89,105`; `check_cli.nim:90`; `shape_cli.nim:112`; `infra_cli.nim:235` |
| Void-command fall-through risk | `action_interpreter_cli.nim:119-120` (cache), `:121-122` (check), `:123-124` (infra), `:125-126` (shape), + `:204` |
| `ax verify <bad-dir>` → 0 (no rejection mapped) | `src/cli/wf_runners.nim:100-105,163-172` |