# Act2-WP4b — External Proof Execution Anchor: Result & Blocking Localization

## Question

Can one non-vacuous ExternalSubject obligation be measured all the way
`Discovery → Admission → Obligation → Planning → UAP → Z3 → Lean/KAA → Canonical Result`
from a clean `nim-stew@c75502c` subject, without modifying Axiom `src/`?

## Context

- EXPERIMENT_ID: `act2-wp4b-proof-execution-anchor`
- PROJECT_UNDER_TEST: `nim-stew@c75502c` (`c75502ceedb5ed2a37b7b5e4744fc71313682859`)
  at `<workspace>/nim-stew-clean-c75502c` (working tree clean)
- AXIOM_REVISION: `Axiom@f7dd583ca (v1.0.0)` — HEAD `089251924`
- AXIOM_CONFIGURATION: `bin/ax prove`, external subject mode,
  `AXIOM_STATE_DIR=/tmp/wp4b_state` (fail-closed external mode),
  kernel scope lock from stateRoot (`verification_scope.lock` present)
- TOOLCHAIN: Nim 2.2.10 (choosenim `nim-2.2.10`)
- Phase 0–4 mandate: **no production `src/` code changes**. Probe + measurement only.

## Scope

- Subject: whole `stew/` tree (51 files, tests excluded), 458 unique candidate symbols.
- Measured: full candidate inventory (Phase 1) + 8-stage evidence ladder on selected
  anchors (Phase 3).
- Excluded: Axiom-support functions, self-run, `verification_scope.lock`/journal/VKD/
  certificate schema changes, any `nim-stew` modification, golden-symbol substitution.

---

## Phase 1 — Candidate Inventory (corrected)

After fixing a double-walk bug in the inventory probe (it walked both `subjectRoot/stew`
and `subjectRoot`, doubling every `definitionCount`), the corrected run:

```
nimFileCount          = 51
uniqueSymbols         = 458
fileParseFailures     = 0

FUNNEL
  total                          458
  uniqueDefinitionCount (def==1) 367
  obligationGreaterThan0          13
  eligibilityElProofCandidate     12
  materialized (moMaterialized)  358
  shortlistFinal                   6
```

Corrected artifact: `wp4b-inventory.json` (in this folder; the earlier
`wp4b-inventory.json` with `shortlist=0` was the double-walk bug version).

### 6 candidate shortlist

| module::function | tier | vacuous | symbolicDivisor | bodyNodes | admissibility |
|---|---|---|---|---|---|
| base36::decodedLength | vtSmtNative | no | no | 3 | ADMISSIBLE |
| base36::encodedLength | vtSmtNative | no | no | 5 | ADMISSIBLE |
| base32::decodedLength | vtSmtNative | no | no | 9 | ADMISSIBLE |
| base32::encodedLength | vtSmtNative | no | no | 5 | ADMISSIBLE |
| base58::encodedLength | vtSmtNative | no | no | 5 | ADMISSIBLE |
| bitops2::getBitsBE | vtStructural | no | **yes** | 31 | DEFER_TO_RUNTIME |

All 6 generate exactly one `okSafetyDiv` obligation, are `elProofCandidate`,
`inVerifiedFragmentV1`, and non-vacuous — but see Phase 3 for why the
constant-denominator `vtSmtNative` members are known A6-fail.

---

## Phase 3 — 8-Stage Evidence Ladder

### Anchor 1 — `stew/bitops2.nim::getBitsBE` (chosen)

Rationale per plan ranking: the only non-constant-divisor, single-definition candidate.
(Each `vtSmtNative` encoded/decodedLength divides by a constant literal denominator,
e.g. `(length*179) div 277`, and WP4-a established that `synthesizeContracts` injects a
`const != 0` premise that yields a Z3 **tautology REJECT**, so those are known A6-fail.)

**Result: crash at Planning/Selection stage (exit 2) — never reached Z3.**

```
[INFO] axiom_engine: topology: 86 files, 931 candidates
[INFO] frontier_selection: --target=stew/bitops2.nim::getBitsBE not found in frontier — using full frontier
...
[ERROR] action_interpreter_cli: [ERROR] value out of range: -1 notin 0 .. 9223372036854775807
[STACK] src/cli/axiom_engine.nim(755) runProofPipeline
        src/cli/frontier_selection.nim(93) selectFrontierNodes
        src/cli/axiom_engine.nim(719) :anonymous
        .../system/indices.nim(85) []
```

Full log: `/tmp/wp4b_getbitsbe.log`.

### Anchor 2 (control) — `stew/base36.nim::encodedLength`

`--target` was **found** in the frontier, so the fall-back full-frontier gate did not run
and the engine reached execution:

```
[INFO] loop_driver: verifying 1 nodes (primed=0)...
[ERROR] loop_driver:   [1/1] stew/base36.nim::encodedLength — skipped by theory
[WARN] loop_driver: Verification-Gate: UAP produced 0 results (requests=1)
[ERROR] axiom_engine: IR pipeline FAIL: encodedLength status=psError
        provenance=solverMethod=smNone,provenance=pkNone
...
[INFO] axiom_engine: cross-validation skipped (vacuous — no postconditions)
```

So `encodedLength` reaches A4 (planned=1) / A5 (UAP request=1) and fails at
A6 (`skipped by theory`) — the known constant-denominator `synthesizeContracts`
tautology limitation. **No crash.** Full log: `/tmp/wp4b_encode.log`.

---

## Blocker — Exact Drop-Site & Root Cause

### Stage reached before crash

- A1 discovery: PASS (86 files, 931 topology candidates)
- Selection/Planning: **FAIL — engine crashes** before any node is selected.

### Root cause (two compounding defects, one external, one Axiom)

**(1) External topology scanner mangles backtick operator + export marker.**
Axiom's **text**-based topology scanner (`topology_parser.nim` →
`scanTopologySource`) parses the nim-stew operator overrides:

```nim
func `*`*[P,S](iv, jv: Interval[P,S]): IntervalRc[P,S] =
```

(the backtick-quoted operator `` `*` `` followed by the postfix export marker `*`)
as `functionName = "*"`. Four such nodes are produced in `stew/interval_set.nim`
(exported `func`, `declaration lines 945, 957, 963, 969`), each with
`nodeId = stew/interval_set.nim::*`. Evidence: `topology_merkle.json` cachedSymbols
→ exactly 4 symbols with `functionName == "*"` among the 931-candidate frontier.

**(2) Axiom eligibility gate slices the `"*"` name unsafely.**
In the external-candidate eligibility lambda (`src/cli/axiom_engine.nim:715-719`):

```nim
var bare = fnName
if bare.endsWith("*"):
  bare = bare[0 ..< bare.len - 2]   # line 719
```

When `fnName == "*"`, `bare.len == 1`, so `bare[0 ..< 1 - 2]` = `bare[0 ..< -1]`
raises `value out of range: -1`. The `-2` is also semantically wrong even for a
legitimate `"name*"` — it should strip exactly one trailing `*` (`-1`), not two.

### Trigger condition

The crash only fires when the eligibility gate iterates the **full frontier**: i.e.
when `--target` is NOT found and the engine logs `"using full frontier"`
(`frontier_selection.nim:64`). When `--target` IS found (control `encodedLength`),
the gate iterates only the matched node → no `"*"` node → no crash.

### Why `getBitsBE` was "not found in frontier"

`computeVerifiedFrontier` (`verified_frontier.nim:40-96`) emits only the leading
dependency-satisfied wave from `analysis.verificationQueue`; `getBitsBE` is not in
that initial wave because its dependencies are not yet all verified. So the
`--target` exact-match fails and the full-frontier fallback runs → crash. This is a
**secondary** targeting/frontier-wave limitation, not the primary crash cause.

---

## Classification

| Anchor | Stage ladder | Classification |
|---|---|---|
| getBitsBE | A1 only → crash at selection | **InfrastructureFailure** (engine crash on `"*"` operator node in full-frontier eligibility gate) |
| encodedLength | A1,A2,A3,A4,A5 → A6 fail | **Incomplete** (constant-denominator div → `synthesizeContracts` tautology REJECT; known WP4-a limitation) |

Neither anchor produced a Z3 or Lean/KAA invocation; there is **no `Verified`** claim.

---

## Proposed minimal fix (NEXT work package — not applied in this WP)

Phase 0–4 forbid `src/` changes, so only the localization + proposal are produced here.

**Generic fix (Axiom-owned, not nim-stew-specific):**

1. `src/cli/axiom_engine.nim:719`: guard the slice and fix the width.
   ```nim
   if bare.endsWith("*") and bare.len > 1:
     bare = bare[0 ..< bare.len - 1]
   ```
   This both (a) removes the `-1` range crash and (b) corrects `-2 → -1` so a real
   `"name*"` yields `"name"`.

2. (Optional, same WP) Teach the topology text scanner
   (`topology_parser.nim` `parseIdentifierAt` / `detectKeywordDeclaration`) to consume
   a backtick-quoted operator name followed by the postfix `*`, so exported operator
   overrides get `functionName = "*"` (the operator) instead of `"*"` (just the marker).
   This is a class-level fix: any external Nim repo with exported operator overrides
   (`` `+`* ``, `` `==`* ``, etc.) hits the same crash.

**Do not** special-case nim-stew, and do not weaken eligibility. This is a generic
external-subject correctness fix.

---

## Non-Conclusions

- Does NOT prove nim-stew's `getBitsBE` or `encodedLength` are verifiable.
- Does NOT claim any obligation reached Z3/Lean/KAA.
- The `encodedLength` A6 failure is the same known `synthesizeContracts` constant-denominator
  limitation; it is a separate follow-up, not this WP's blocker.
- The crash is measured on this subject revision / this Axiom state; it is a generic
  operator-override parsing+guarding bug and would recur on any external subject with
  exported operator overrides and a full-frontier gate pass.

## Next experiment

- Apply the 2-line `axiom_engine.nim:719` guard as a generic fix (Axiom-side), rerun
  `getBitsBE`. If it then admits a node, re-run the ladder. Independently, add a
  regression covering an exported operator override (`interval_set.nim::*`) in the
  frontier eligibility path so the full-frontier gate never crashes.
- `getBitsBE` admission is still gated by `computeVerifiedFrontier` dependency order;
  confirm whether `--target` must also bypass the leading-wave restriction.
