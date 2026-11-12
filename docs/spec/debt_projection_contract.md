# Debt Projection Contract (P1)

> **Status**: Normative contract — defines the single projection path for the debt registry.
> **SSOT**: `data/debt_registry.json` (see AGENTS.md §5 SSOT locations table).
> **Generator**: `tools/debt_engine.nim` compiled as `bin/debt_engine`.
> **Authority**: [ADR-0029](adr/0029-debt-projection-writer-authority.md) — writer/generator authority, role-sets, and the canonical mutation device.
> **Related**: DEBT#436 (dependency file drift / CI test-swallow fail-open remediation), DEBT#437 (dedicated `ax debt add/update/close` mutation path — not yet implemented; see §9 Rationale).

---

## Purpose

This document is the canonical **projection contract** for the debt registry. It defines:

- The single source of truth (`data/debt_registry.json`) and its two derived materializations.
- The purity and determinism requirements the generator must satisfy.
- The mutation protocol (validate → mutate SSOT → regenerate → validate).
- The read-side validation invariant used by CI.
- The versioning scheme for the projection format.

The contract lives under `docs/spec/` per the SSOT location convention (AGENTS.md §5: `docs/spec/` holds contracts). It is not a measurement, historical record, or generated artifact — it is the normative rule that all projection tooling must obey.

---

## 1. Source of Truth (SSOT)

`data/debt_registry.json` is the **sole authoritative source** for the debt registry. It is the only file developers edit to register, close, or reclassify a debt entry.

The two projections are **materialized views**, not sources of truth:

| Projection | File | Format |
|---|---|---|
| P1 Markdown | `docs/DEBT_REGISTRY.md` | Human-readable table |
| P1 Nim constants | `src/generated/debt_constants.nim` | Compile-time `const` + `static doAssert` gate |

Neither `docs/DEBT_REGISTRY.md` nor `src/generated/debt_constants.nim` may be hand-edited (see §8). To change the registry, edit `data/debt_registry.json`, then run the canonical generation command (see §4).

The budget ledger (`data/debt_ledger.json`, BUDGET#001–006) is **P2** — a live metric evaluation layer, not a P1 projection. P2 is reconciled via `bin/debt_engine --sync-budget` (see §4).

---

## 2. The Projection Equation

The projection is defined as a pure function:

```
Projection = Generate(Registry, GeneratorVersion)
```

Where:

- **Registry** = `data/debt_registry.json`. This is the **only** input that determines the output bytes. It carries hand-authored prose per entry, so it is an SSOT and not a derived projection (see [ADR-0029](adr/0029-debt-projection-writer-authority.md) — the `config/gates.json` projection model does not transfer to it).
- **GeneratorVersion** = `DebtProjectionVersion` const embedded in the generator (`tools/debt_engine.nim:108`: `DebtProjectionVersion = "2"`).
- **Projection** = the pair of output artifacts (`docs/DEBT_REGISTRY.md`, `src/generated/debt_constants.nim`).

#### `architecture_debt.json` is an existence precondition, not a semantic input

`data/architecture_debt.json` **does not contribute a single byte** to either projection. It is an
**existence and parse precondition only**: `--codegen` exits if the file is absent (the
`fileExists(ArchDebtPath)` guard in `cmdCodegen`) and `generateProjections` requires it to parse, but
no field of it reaches the output.

This was, until recently, expressed only as an undereferenced parameter: `aggregate` took
`(registry, archDebt)` while its body read only the registry entries. **That dead parameter has now
been removed** — `func aggregate*(registry: JsonNode)` takes only the registry — so the signature and
the assertion agree for the first time.

The signature agreeing is necessary but not sufficient, which is why the invariant is **measured**
rather than declared — see [ADR-0029](adr/0029-debt-projection-writer-authority.md) §4. A future
edit that adds a second read **inside** `aggregate` would change the projection bytes without
changing any declared type, and no signature-shaped check would notice. The machine check that
guards this is the counterfactual: **randomising the contents of a valid `architecture_debt.json`
must not change the output bytes.**

**Reading is not deriving.** Any statement that the Markdown projection "covers" architecture debt
is false. A prior revision of this document made exactly that claim; it is withdrawn. The distinction
is load-bearing: the "read" step (§3.3, §6) stays accurate, but "determines the output" does not.

`architecture_debt.json` **does** affect whether `--validate` passes — `--validate` validates it
structurally and cross-checks open critical references against it. That is a **validation** input,
not a **projection** input. Do not conflate the two.

A prior revision of the generator emitted a header naming **both** files as the source; that literal
now names only `data/debt_registry.json`. Worth recording either way: such a header is a **string
literal, not evidence of derivation**. The assertion above is the one that holds, and it is
establishable only by the counterfactual, not by reading a comment.

### P1 vs P2 boundary

| Layer | What it is | Command | Output |
|---|---|---|---|
| **P1** | Pure projection of the registry (deterministic, byte-checkable) | `bin/debt_engine --codegen` | MD + Nim constants |
| **P2** | Live metric evaluation (budget ledger reconciliation with disposition policy) | `bin/debt_engine --sync-budget` | Updated `data/debt_ledger.json` `current` values |
| **P1 validation** | Byte-identity check: regenerate P1 from SSOT and compare against checked-in artifacts | `bin/debt_engine --validate` (Part C, check [4.5/6]) | `ProjectionStatus: P1=pass` or `P1=fail` |

The `ProjectionStatus` (`P1=pass/fail`, `P2=complete/unavailable`) is reported on stdout/CI logs only. It is **not stored inside any generated artifact** — this prevents the projection from becoming a source of truth about itself.

---

## 3. Generator Purity & Determinism Requirements

The generator (`tools/debt_engine.nim`, `--codegen` path) MUST satisfy the following purity invariants:

### 3.1 No nondeterministic content

The generator MUST NOT embed any of the following in its output:

- **Timestamps** — no `generatedAt`, `lastUpdated`, or ISO date strings.
- **Machine paths** — no absolute file paths, no `$HOME`, no `os.getCurrentDir()`.
- **Random IDs** — no UUIDs, no nonce values.
- **Nondeterministic iteration** — the projection path sorts the **severity group list**, but never
  the entries. The ordering rule has two halves and both must hold:

  1. **Group order** is the total order produced by `func orderedSeverities*`
     (`tools/debt_engine.nim`): declared levels first in preference order
     (`critical`, `high`, `medium`, `low`), then any out-of-vocabulary severity in code-point
     order. An out-of-vocabulary severity therefore **gets its own section** rather than
     vanishing.
  2. **Within a group, `debt_registry.json` array order is preserved verbatim.** Entries are
     appended in iteration order and no comparator is applied to them.

  Ordering is therefore a function of the registry file's array order. Two registries with equal
  entry sets but different array order produce **different** projections. Determinism here means
  "same input bytes → same output bytes", not "same content → same bytes".

  A prior revision of this document stated that "registry entries are sorted by ID before
  projection". That claim was **false and is withdrawn** — no ID sort exists in the generator, and
  none is permitted by this contract.

### 3.2 GeneratorVersion embedding

The generator MUST embed `GeneratorVersion` in **BOTH** generated artifacts — not one:

- **Nim constants** (`src/generated/debt_constants.nim`): `# Projection contract: P1 vN` in the
  header comment **and** `DebtProjectionVersion* = "N"` as a `const` — both emitted by `genConstants`.
- **Markdown** (`docs/DEBT_REGISTRY.md`): `> Projection: P1 vN` in the header blockquote, emitted by
  `genMarkdown`.

Neither artifact may be produced without the marker. An artifact whose version marker does not match
`DebtProjectionVersion` is a **contract violation**, distinct from ordinary byte drift: a mismatch
means the artifact was produced by a generator of a different generation, so regenerating and
byte-comparing it would compare two different formats and report a misleading diff.

The version string is `DebtProjectionVersion = "2"` (`tools/debt_engine.nim:108`). Two identical
registries → byte-identical projections, regardless of when or where generated.

> **Observed divergence at the time of writing.** The generator const reads `"2"` (`:108`) while both
> checked-in artifacts still carry `v1` (`docs/DEBT_REGISTRY.md:4`, `src/generated/debt_constants.nim:3`
> and `:13`). The bump landed without a regeneration. Until `bin/debt_engine --codegen` is run, this
> artifact pair does not satisfy this subsection, and the §6 byte-identity guard should fail. This is
> recorded as observed state, not as an accepted condition.

**Bump obligation (binding on any change to the output format).** If a change alters the **output
format** of either artifact — adding or removing a Markdown column, changing the Nim constants
declaration style, adding or removing a `static doAssert` gate, or changing how an existing column's
value is rendered — the author of that change **MUST** bump `DebtProjectionVersion` from `"1"` to
`"2"` in the **same changeset** as the format change, and **MUST** regenerate both artifacts with
`bin/debt_engine --codegen` so both markers move together.

Rendering-only changes that change *which text appears in an existing column* are format changes
under this rule even though the column count is unchanged (for example: emitting every file
reference instead of only the first). This is deliberate — a consumer parsing the artifact must be
able to tell which generation it is looking at.

Do **not** bump the version for registry *data* changes (new entries, status transitions, severity
reclassifications, description edits). Those are registry mutations, not format changes, and the
version is the marker for format, not for content.

### 3.3 Pure computation

The `--codegen` path is a pure function of the registry JSON content:

1. Read `data/debt_registry.json` and `data/architecture_debt.json` (both reads occur; **only the
   first determines the output** — see §2, "existence precondition, not a semantic input").
2. Compute `SeverityStats` and `seq[DebtEntry]` in memory (the `aggregate` func,
   `tools/debt_engine.nim:414`).
3. Generate the Nim constants string (`genConstants`, `:442`) and the Markdown string
   (`genMarkdown`, `:483`) entirely in memory.
4. Write both files to disk (`idempotentWrite`, `:582`; called at `:617` and `:619`).

No side effects (no network calls, no random number generation, no clock reads) are permitted in the projection computation.

---

## 4. Canonical Generation Command Table

| Command | Artifact(s) Produced | Description |
|---|---|---|
| `bin/debt_engine --codegen` | `src/generated/debt_constants.nim` + `docs/DEBT_REGISTRY.md` | P1 projection: regenerates both artifacts from the SSOT. Prints `ProjectionStatus: P1=complete` on success. |
| `bin/debt_engine --sync-budget` | `data/debt_ledger.json` (updated `current`/`status`/`resolution` fields) | P2 reconciliation: evaluates metric evaluators and reconciles the ledger's `current` values against live counts. |
| `bin/debt_engine --validate` | Exit code 0 (pass) or 1 (fail) | Read-side invariant check: structural validation + cross-file consistency + P1 byte-identity guard + P2 metric evaluation + policy disposition resolution. |

The canonical build path compiles the generator from source:

```
nim c -d:release -o:bin/debt_engine tools/debt_engine.nim
```

This is also compiled by the `pre-commit` Makefile target (`make pre-commit`, `Makefile:935`;
compile at `Makefile:940`). Note that `pre-commit` runs `bin/debt_engine --validate`
(`Makefile:947`) — it **verifies** the projections, it does not regenerate them.

---

## 5. Atomic Materialization (Mutation Protocol)

Because `--codegen` computes both P1 projections fully in memory before writing either file, a failure never leaves the Markdown and Nim files mutually out of sync. The mutation protocol is:

```
1. validate   → bin/debt_engine --validate
               (confirms current projections match the SSOT)

2. mutate SSOT → edit data/debt_registry.json
               (only file developers may hand-edit)

3. regenerate → bin/debt_engine --codegen
               (computes both P1 projections in memory, writes both)

4. re-validate → bin/debt_engine --validate
               (confirms new projections are byte-identical to what was just written)

5. commit     → single changeset containing:
                 - data/debt_registry.json (SSOT mutation)
                 - docs/DEBT_REGISTRY.md (P1 projection)
                 - src/generated/debt_constants.nim (P1 projection)
                 - data/debt_ledger.json (only if BUDGET counts changed; run --sync-budget first)
```

If step 3 or step 4 fails, no commit is made. The mutation is all-or-nothing.

### When to run `--sync-budget`

Run `bin/debt_engine --sync-budget` **only** when the registry mutation changes the count of open/closed entries that map to BUDGET#005 (`debt_registry_open`) or BUDGET#006 (`debt_registry_closed`). For all other registry mutations (severity changes, description edits, new entries that don't change open/close counts), `--sync-budget` is not required.

---

## 6. Validation (Read-Side Invariant)

`make check-debt` executes `bin/debt_engine --validate` (CI job에서 실행되던 검증 명령 — CI=0 cutover, 2026-09-20 이후 로컬에서 직접 실행). The `--validate` command includes a **byte-identity guard** (check [4.5/6]) that:

1. Reads `data/debt_registry.json` and `data/architecture_debt.json`.
2. Regenerates both P1 projections in memory via `generateProjections`.
3. Compares the regenerated Nim constants string byte-for-byte against the checked-in `src/generated/debt_constants.nim`.
4. Compares the regenerated Markdown string byte-for-byte against the checked-in `docs/DEBT_REGISTRY.md`.
5. On any byte mismatch, prints `Byte mismatch — run: bin/debt_engine --codegen` and fails the check.

This is a **fail-closed** invariant: any drift — count drift, formatting drift, version marker drift, or ordering drift — causes a hard FAIL with exit code 1. The error message directs the developer to the canonical regeneration command.

The full `--validate` command also performs:

- **Part A**: Structural JSON validation of all three data files (`data/architecture_debt.json`, `data/debt_registry.json`, `data/debt_ledger.json`).
- **Part B**: Cross-file consistency (registry ↔ architecture debt file coverage, critical threshold gate).
- **Part C**: Full sync validation (registry structure, ledger structure, ledger↔registry budget sync, Markdown↔registry sync, P1 byte-identity guard, BUDGET count↔ledger sync).
- **Part D**: Budget metric evaluation (live evaluator output vs. ledger `current` values, with DRIFT disposition).
- **Part D.1**: Policy disposition resolution (INFO/WARN/ERROR from `config/policy/policy_dispositions.json`).
- **Part D.1.1**: Policy stability constraint validation.
- **Part D.2**: Policy freshness check.

Exit code 0 requires all checks to pass and no ERROR dispositions. Exit code 1 on any failure.

---

## 6.1 Lossless Projection Contract (Field Level)

### 6.1.0 Why artifact-level byte identity is not sufficient

The byte-identity guard in §6 is necessary but **not sufficient**, and the reason is structural: it
is blind to loss *by construction*. A generator that silently drops a field is byte-identical to
itself. Regenerate, compare bytes, pass — while the field is gone from the artifact. Byte identity
proves *reproducibility*; it does not prove *completeness*.

This section therefore declares the contract one level down: **field-level**.

### 6.1.1 Artifact set

The contract covers exactly the two artifacts named in §1:

- `docs/DEBT_REGISTRY.md` (P1 Markdown)
- `src/generated/debt_constants.nim` (P1 Nim constants)

### 6.1.2 Where the field contract lives

The normative field contract is the **projection-declaration table in `tools/debt_engine.nim`**:

| Element | Anchor in `tools/debt_engine.nim` | Role |
|---|---|---|
| `DebtRowFields: array[6, FieldDecl]` | `let DebtRowFields` | The **in-contract** field set: one `FieldDecl` per projected Markdown column, each naming its `column`, its `registryKey`, its rendering `kind`, and a `fidelity` flag. |
| `DebtRegistryFieldsOutOfContract: seq[string]` | `let DebtRegistryFieldsOutOfContract` | The **out-of-contract** set: registry keys deliberately not projected. |
| `declaredCellValue(decl, node)` | `func declaredCellValue` | Evaluates a declaration against a **registry JSON node**. |
| `cellFromEntry(decl, e)` | `func cellFromEntry` | Evaluates the same declaration against the **aggregated entry**. |

The two evaluation functions are kept separate **on purpose** (the comment above `cellFromEntry`
says so): the validator must compute its expectation independently of the writer. If both sides
called the same code path, a generator defect would move both at once and prove nothing. This is the
field-level analogue of the §6.1.3 multiset rule — a check that shares its implementation with the
thing it checks is not a check.

`--codegen` lays the Markdown table out from `DebtRowFields`; `--validate` derives its P3
expectations from the same table. **One declaration, one consumer** — the table is not duplicated
into a second hardcoded list on the validation side.

Exhaustiveness is enforced, not assumed: `--validate` fails closed when a registry key appears that
is in neither `DebtRowFields` nor `DebtRegistryFieldsOutOfContract` (the diagnostic reads *"undeclared
keys — add to DebtRowFields or DebtRegistryFieldsOutOfContract"*). A newly added registry field
therefore cannot silently escape the contract.

> **Citation hygiene.** `tools/debt_engine.nim` is under active concurrent change. Citations in this
> section are anchored to the **symbol names above**, which are stable; line numbers are a
> convenience as of 2026-10-04 and will drift. Prefer the anchor.

### 6.1.3 The completeness checks

`--validate` performs a field-level completeness pass, reported under the check label
`[4.7/7] Projection losslessness (P0 contract / P1 row set / P2 partition / P3 field fidelity)`,
consisting of a contract check plus three completeness checks. These are **in addition to**, not a
replacement for, the byte-identity guard of §6.

**P0 — Contract closure.** Every registry key is classified as in-contract or out-of-contract; an
undeclared key fails with the *"add to DebtRowFields or DebtRegistryFieldsOutOfContract"* diagnostic.

**P1 — Row-set equality, compared as a MULTISET.**

The set of entry rows in the Markdown projection must equal the set of entries in
`data/debt_registry.json`, compared **as a multiset**.

The multiset requirement is not incidental. A plain **set** comparison silently succeeds when the
projection contains a **duplicated** id and is **missing** a different id: `{A, B}` and `{A, A}` are
equal as sets but differ in cardinality. Counting multiplicity is what makes a duplicated row a
failure. Declared as a set, this check would certify a projection that both duplicates one entry and
drops another — the exact failure mode it exists to catch.

Implemented by counting occurrences on both sides and classifying the difference into three named
buckets — **missing**, **invented**, and **duplicated** — plus a second cardinality guard on the row
total. Both verdicts are emitted under the check label `"P1 rendered rows equal the registry id
multiset"`, and the source states the rationale in a comment directly above them:
*"Counted, not set-compared: a duplicated id would satisfy a set comparison."*

**P2 — Severity-partition closure against the ENTRY COUNT.**

Every entry in the registry must be accounted for by exactly one emitted severity partition, and the
partitions' sizes must sum to the total entry count.

The sum is checked against the **total entry count** — the guard reads
`partitionSum == entries.len` under the check label `"P2 severity partitions close over the registry
entry count"` — never against the Markdown's own header line. A header that reads
`> Total entries: 215` is a *projection of* the count and therefore cannot be the witness for it —
validating the partition sum against the header would let a generator that loses 5 rows and writes
the reduced number into its own header certify itself. The authority for the count is the registry;
the header is under test like any other output.

Each partition is additionally compared against the registry's own per-severity tally, so a
redistribution that preserves the total still fails.

**P3 — Per-field fidelity, one message PER FIELD.**

For each declared in-contract field, the value rendered in the projection is compared against the
value in the registry entry, and **each mismatching field produces its own diagnostic message** —
emitted as `checkQuiet("P3 " & id & " " & decl.column, ...)`, one per (entry, field) pair.

One aggregate "projection is stale" message is not acceptable. Aggregation destroys the only
information a human needs to act: *which* field broke, for *which* entry. The failure output must
localise every divergent field independently so a single run surfaces all of them. Row-shape errors
are reported separately as `P3 <id> row shape`.

`DebtRowFields` carries a per-field `fidelity` flag; P3 skips declarations with `fidelity: false`.
All six current declarations set it `true`.

### 6.1.4 In-contract and out-of-contract field sets

**In contract** — `DebtRowFields`, six projected columns:

| Column | Registry key | Kind |
|---|---|---|
| `ID` | `id` | text |
| `Severity` | `severity` | severity label |
| `Category` | `category` | text |
| `Title` | `description` | text |
| `Files` | `files` | file references |
| `Status` | `status` | status label |

**Out of contract** — `DebtRegistryFieldsOutOfContract`. These
registry keys are deliberately not projected, and their absence is **not** a validation failure. The
list is a declared, reviewable exemption set — not an accident. Adding a key here is a contract
change and must be justified in review, not done silently.

| Key | Why out of contract |
|---|---|
| `impact` | **DEPRECATED and no longer read.** The canonical severity is `severity`. `tools/debt_engine.nim:341-346` records that 45 of 215 registry entries carry an `impact` that **disagrees** with `severity`; admitting the stale field to the contract would first require reconciling those 45 conflicts. Reported as deprecated and left unread. |
| `title` | Deprecated title alias, superseded by `description` (`:363-364`). |
| `declName` | Same superseded alias (`:365`). |
| `file` | An accepted **spelling of** the `files` reference list, not a separate field (`:369-370`). |
| `resolution`, `resolvedAt`, `resolvedBy`, `resolutionNote` | Resolution bookkeeping; not projected. |
| `lastVerifiedAt` | Verification timestamp; not projected. |
| `symbol`, `contentHash`, `lineRange` | Code anchors; not projected. |
| `note`, `kind`, `historicalFiles`, `source` | Annotations; not projected. |

Two consequences of the in-contract table are worth stating explicitly, because both are easy to
misread from the artifact alone:

- The projected `Severity` derives from `severity`, **not** from `impact`. A registry entry whose
  two fields disagree is projected under `severity`; the disagreement is invisible in the artifact.
  This is deliberate and is the reason `impact` is out of contract rather than projected.
- The projected `Title` derives from `description`, **not** from `title`.

Field-presence counts in `data/debt_registry.json` are not reproduced here: they change as the
registry grows, and the exhaustive rule in §6.1.2 makes the declaration table — not any count in
this document — the authority on what is in contract.

### 6.1.5 Scope boundary

> **The contract in §6.1 covers `registry → debt_engine → declared projection` ONLY.**
>
> It makes **NO claim** about `projection → downstream consumer`. Producing a projection that is
> field-complete says nothing about whether any consumer reads it correctly.

Three downstream consumers are known to be broken. They are recorded here so they are not forgotten,
and they are **explicitly not** closed by this contract:

| Consumer | Measured breakage |
|---|---|
| (deleted 2026-10-04 — zero importers, never compiled; see DEBT#487) | Parses Markdown rows assuming **≥ 9** columns (`:122`: `if cols.len < 9:` → drop the row) and reads status at `cols[7]` (`:130`) and a due date at `cols[9]` (`:131`). The P1 Markdown is a **6**-column table, in both v1 and v2 — the v2 `Files` column joins references with `<br>` (`tools/debt_engine.nim:318`), which contains no pipe, so the column count is unchanged. Measured against the checked-in artifact: **210 of 213 rows are dropped** by the length filter. The remaining 3 survive only because their Title contains a backslash-escaped pipe (`\|`) that `split("|")` does not honour, yielding 10 fields — and those 3 are **mis-parsed**: `cols[7]` returns a Files value (`DEBT#295` → `.circleci/continue.yml`, `DEBT#436` → `Makefile`, `DEBT#431` → `Makefile`) instead of a status. |
| `src/gate/runners/debt_scan_gate.nim` | `isExempted` searches the Markdown for the marker `"### [Exemption APPROVED] "` (`:101`). `genMarkdown` **never emits any line of that form** — it emits severity headings and table rows only. Every `isExempted` lookup therefore returns `false`, so no exemption is ever honoured, silently. |
| `tools/hotspot_ranker.nim` | Reads the Status cell at `parts[7]` (`:30`) against a documented schema of `\| ID \| Severity \| Category \| Title \| File \| Line \| Status \| ...` (`:20`). The P1 Markdown has 6 columns, so `split("|")` yields **8** fields — `parts[7]` is the trailing empty field, not the status. The guard `if parts.len < 8: continue` (`:29`) therefore does **not** reject these rows; instead `("Open" in "")` is false at `:31` and **every row is skipped**, yielding an empty ranking. |

These are downstream-consumer defects. Fixing them is follow-up work outside this contract's scope;
listing them here is what keeps them from being lost when the projection side is signed off. Note
that the v1→v2 regeneration does **not** fix any of the three: the column count and the set of
emitted line shapes are unchanged in the ways these consumers depend on.

> **Scope discipline.** Adding a column to satisfy a broken consumer is *not* the remedy, and this
> contract does not license it. A consumer with a wrong expectation must be corrected to read the
> declared projection (§6.1.4), not accommodated by widening the projection. Doing the latter would
> change `DebtProjectionVersion` again and re-open every consumer at once.

---

## 7. Versioning

### GeneratorVersion ↔ Output Format Mapping

| GeneratorVersion | Output Format | Notes |
|---|---|---|
| `2` (current, generator) | Markdown table laid out from `DebtRowFields` (§6.1.4): `ID \| Severity \| Category \| Title \| Files \| Status`, with `> Projection: P1 v2` in the header blockquote; constants carrying `# Projection contract: P1 v2` and `DebtProjectionVersion* = "2"` | Both markers are emitted by the generators. **The checked-in artifacts still read `v1`** and still carry the v1 `File` column (see the divergence note in §3.2); regeneration is outstanding. |
| `1` (previous) | `ID \| Severity \| Category \| Title \| File \| Status` — first file reference only | Superseded. Retained in this table because the checked-in artifacts are still at this generation. |

The version marker is a property of **both** artifacts simultaneously; a generation where the two
artifacts carry different `DebtProjectionVersion` values is not a valid state of this contract.

### Version Bump Rules

Bump `DebtProjectionVersion` **only** when the output *format* changes — adding or removing a column
in the Markdown table, changing the Nim constants declaration style, adding a new `static doAssert`
gate, or changing how an existing column renders. Do **not** bump the version for registry data changes
(new entries, status transitions, severity reclassifications).

The normative obligation and its rationale are stated in §3.2, which governs; this table records the
mapping only. In short: **a format change without a version bump is a contract violation**, because
it makes an already-generated artifact indistinguishable from one produced by the previous format.
The mirror-image failure is equally real: **a version bump without a regeneration** leaves the
artifacts advertising a generation that does not describe their bytes.

The version is a single `const DebtProjectionVersion = "2"` at `tools/debt_engine.nim:108`, referenced
by both output generators. The const carries a comment recording **why** it was bumped — the `Title`
source moving from `title`/`declName` to `description`, and the single `File` cell becoming a `Files`
cell carrying every reference — and points back at this section.

---

## 8. Hand-Edit Prohibition & Enforcement

### Prohibition

Developers **must not** hand-edit `docs/DEBT_REGISTRY.md` or `src/generated/debt_constants.nim`. These are generated artifacts. The only legitimate edit path is:

1. Edit `data/debt_registry.json` (the SSOT).
2. Run `bin/debt_engine --codegen`.
3. Run `bin/debt_engine --validate` to confirm byte-identity.
4. Commit the resulting changeset.

### Enforcement

The byte-identity guard in `--validate` (check [4.5/6]) catches hand-edits automatically:

- If a developer modifies `docs/DEBT_REGISTRY.md` by hand, the next `--validate` run will regenerate the correct content from the SSOT, compare byte-for-byte, and fail with `Byte mismatch — run: bin/debt_engine --codegen`.
- If a developer modifies `src/generated/debt_constants.nim` by hand, the same guard catches it with `Byte mismatch — run: bin/debt_engine --codegen`.

This enforcement is **passive** (it catches drift at CI time) rather than **active** (it does not prevent hand-edits at authoring time). The fail-closed CI gate ensures that hand-edited projections cannot be committed.

### Competing generators (baseline — now closed)

The prohibition above binds humans. It does **not** describe the machine surface, and the machine
surface historically violated it. `docs/DEBT_REGISTRY.md` was written by **five** code paths, not
one, and they did not agree on the format.

**Status as of this revision: closed.** `tools/debt_engine.nim` is the only remaining writer of
`docs/DEBT_REGISTRY.md`; a search for any other `writeFile`/`idempotentWrite` targeting that path
under `src/` and `tools/` returns nothing. The four removed writers are recorded below as the
measured baseline the removal was made against — those citations are historical and **no longer
resolve**.

| Writer | Historical shape | Status |
|---|---|---|
| `tools/debt_engine.nim` — **canonical** | Table laid out from `DebtRowFields` (§6.1.4); `> Projection: P1 vN` marker emitted by `genMarkdown` | present — sole writer |
| `tools/debt_codegen.nim` | Same 6-column table but **no version marker** — its header omitted `> Projection: P1 v1`. Self-marked `DEPRECATED`. | deleted |
| `tools/debt_registry_gen.nim` | **7 columns** (`ID \| Impact \| Category \| Title \| File \| Line \| Status`); different H1; entries sorted | deleted |
| `tools/debt_registry_sync.nim` | Independent `generatedMd` construction | deleted |
| `tools/ast_refine.nim` | 6 columns of a **different schema** (`ID \| File \| Line \| Category \| Severity \| TTL`) and an embedded **UTC timestamp** — a direct §3.1 violation | writer removed; the file remains and now carries a comment stating the projection is not its output (`tools/ast_refine.nim:808`) |

> **Unverified.** I did not execute any of these tools, did not confirm the removed writers produced
> byte-identical output before deletion, and did not check whether any build rule or config still
> references them by name. What is verified is that none of the four writes
> `docs/DEBT_REGISTRY.md` any more, and that `tools/ast_refine.nim` no longer writes it.

The remaining enforcement gap is the one §8 Enforcement describes: the check is **passive**. It
catches a competing writer's damage after the fact and names only the canonical generator, so a
developer clobbered by another tool is not told which tool did it. The sink-level check that closes
this is declared in [ADR-0029](adr/0029-debt-projection-writer-authority.md) §2.

---

## 9. Rationale

### DEBT#436 — Dependency File Drift / CI Test-Swallow Fail-Open Remediation

The projection contract addresses DEBT#436 by ensuring that derived files are **pure projections, materialized at mutation time and re-derived at CI time**. The byte-identity guard (`--validate` check [4.5/6]) closes the fail-open path that allowed CI to swallow drift between the registry and its materializations. Before this contract, there was no systematic check that `docs/DEBT_REGISTRY.md` and `src/generated/debt_constants.nim` were in sync with `data/debt_registry.json` at CI time; the `--validate` byte-identity guard makes this invariant explicit and fail-closed.

### DEBT#437 — Dedicated Mutation Path (Not Yet Implemented)

This document is the contract that a future `ax debt add/update/close` CLI path will implement. Today, mutation is manual: edit `data/debt_registry.json` + run `bin/debt_engine --codegen` + run `bin/debt_engine --validate`. A dedicated `ax debt` subcommand would automate the mutation protocol (§5) — validate → mutate SSOT → regenerate all P1 → validate outputs → single changeset — but that path does not yet exist. This spec defines the invariants that such a path must satisfy.

### Single Source of Truth & Idempotent Deterministic Codegen

The principle that derived files must be pure projections, materialized at mutation time and re-derived at CI time, follows the general design philosophy of the Axiom project (see AGENTS.md §0.2 First-Principles: deterministic, no hidden state). The debt projection contract applies this principle to the debt registry: one SSOT, one generator, two projections, byte-identity validation. See also the `vendor/ed25519` dependency (deterministic signature verification) and the codegen determinism ADRs for related patterns in the project.

---

## Appendix: Real Commands & Paths Reference

| Item | Real Path/Command | Source |
|---|---|---|
| SSOT | `data/debt_registry.json` | `tools/debt_engine.nim:94` (`RegistryPath`) |
| Architecture debt | `data/architecture_debt.json` | `tools/debt_engine.nim:95` (`ArchDebtPath`) |
| Budget ledger | `data/debt_ledger.json` | `tools/debt_engine.nim:96` (`LedgerPath`) |
| Budget definitions | `data/debt_budgets.json` | `tools/debt_engine.nim:100` (`BudgetsPath`) |
| Markdown projection | `docs/DEBT_REGISTRY.md` | `tools/debt_engine.nim:97,99` (`MarkdownOut`) |
| Nim constants projection | `src/generated/debt_constants.nim` | `tools/debt_engine.nim:98` (`ConstantsOut`) |
| Generator source | `tools/debt_engine.nim` | — |
| Compiled binary | `bin/debt_engine` | `Makefile:137` (build rule), `Makefile:940` (pre-commit compile) |
| Codegen command | `bin/debt_engine --codegen` | `case` dispatch in `main` → `cmdCodegen` (`tools/debt_engine.nim`) |
| Validate command | `bin/debt_engine --validate` | `case` dispatch in `main` → `cmdValidate` (`tools/debt_engine.nim`) |
| Sync-budget command | `bin/debt_engine --sync-budget` | `case` dispatch in `main` → `cmdSyncBudget` (`tools/debt_engine.nim`) |
| GeneratorVersion | `DebtProjectionVersion = "2"` | `tools/debt_engine.nim:108` |
| Critical threshold | `CriticalThreshold = 30` | `tools/debt_engine.nim:102` |
| Projection declaration table (field contract) | `DebtRowFields` / `DebtRegistryFieldsOutOfContract` | `tools/debt_engine.nim` — see §6.1.2 |
| Field-level completeness checks | `[4.7/7]` P0/P1/P2/P3 | `tools/debt_engine.nim` — see §6.1.3 |
| CI check-debt (local) | `make check-debt` → `bin/debt_engine --validate` | `Makefile:166-168` (CI job retired with CI=0 cutover, 2026-09-20) |
| Budget metrics (BUDGET#001–006) | `import_lint_violations`, `layer_violations`, `effect_violations`, `nimtry_violations`, `debt_registry_open`, `debt_registry_closed` | `data/debt_ledger.json` |
