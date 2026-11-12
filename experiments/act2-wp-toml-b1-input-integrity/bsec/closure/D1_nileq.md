# Closure — D1 (typed-accessor SIGSEGV) & D-NIL (`Table == nil` / `InlineTable == nil`) — SCOPE-BOUNDED

**Nature of this record**: FACT-BINDING, not investigation. All execution evidence was collected
2026-10-11 and lives in the cited artifacts; nothing here was re-run. This record activates the
`DEFERRED.md` item "D1 — typed-accessor SIGSEGV + `Table == nil` / `InlineTable == nil` crash".
**Subject**: `status-im/nim-toml-serialization` @ `4aa8e2223649fc0837c490a4acfca7b8b1e756f9`
(READ-ONLY, byte-clean). **Closure recorded**: 2026-10-12.

**No existing verdict is changed.** The campaign's `B-SEC-02` triples
(`B-SEC-02|nph|attacker-controls-loaded-.toml`, `B-SEC-02|imthemes|attacker-controls-loaded-.toml`,
both UNKNOWN) remain exactly as recorded in `verdicts_recorded.tsv` / `JUDGMENT.md`. This closure
adds NEW triples under the deferred-ledger defect ids `D1` and `D-NIL` with their own artifacts.
No severity or CVSS assessment; no issue filed anywhere.

---

## 0. The two levels of this record (binding discipline)

This record holds TWO DISTINCT levels and never lets one substitute for the other:

1. **Per-consumer verdicts** — one rule-table triple per (defect × enumerated consumer ×
   attacker model): 36 consumers × 2 defects = **72 triples, all N/A**, each bound to its
   call-site artifact. Rule citation: **R1** (`rules/rule_table.tsv`: `present | not_used | * | * |
   present → N/A — "consumer does not execute the defective path; artifact mandatory"`). R9
   (`N/A without artifact is FORBIDDEN`) is not triggered: every row carries
   `callsite_artifact=present`.
2. **Set-level summary** (§3) — a REPORT statement over the enumerated consumer set. **It is
   not a rule-table row**: the rule table is total only over enumerated (defect × consumer ×
   attacker-model) triples; no observation tuple exists for "the ecosystem", so nothing outside
   the enumerated set is derivable and it stays UNKNOWN (DEFAULT row, fail-closed). A set-level
   summary MUST NOT be read as an ecosystem safety claim.

**Encoding note (defect_live semantics for the new triples).** In `triples_facts.tsv` the new
rows record `defect_present_recorded=yes`, meaning: the D1 / D-NIL mechanism is live at the
campaign subject `4aa8e22`, where it was executed and observed (defects3 Defect 2;
valuemodel accessors/equality). This is the same subject-level encoding the rule table defines
for `defect_live` ("LIVE run ... derived" at the subject — exactly how `B-SEC-01` is derived by
`replay.sh run`), with consumer-side linkage carried entirely by `consumer_path` + artifact. It
does NOT contradict the `B-SEC-02` rows' pin-level `no` ("SIGSEGV shape absent at the recorded
pin `b5b387e6`"): those rows record a different referent (the pin), recorded before the exposure
survey existed. Where a new triple's pin ALSO lacks the shape (D1 at any pre-`71ed1393`
resolution), that second, independent unreachability ground is stated in the row's evidence
cell. Consumer-path facts are the load-bearing claim of every N/A here.

---

## 1. The two defects (bound from recorded evidence — not re-proven here)

### 1.1 D1 — typed-accessor SIGSEGV on absent key

- **Code site**: `toml_serialization/value_ops.nim:86-87` —
  `proc `[]`*(node: TomlValueRef, name: string, T: type): T {.inline, raises: [KeyError].}` =
  `node[name].innerValue(T)`. The untyped accessor `value_ops.nim:79-84` feeds it
  `node.tableVal.getOrDefault(name)` → **nil on absent key** (line 84; doc comment claims
  KeyError, none is raised). `innerValue` (`value_ops.nim:14-16`) executes `case n.kind` on the
  nil ref at line 16.
- **Minimal repro** (probe `followup/defects3/probes/p2a_missing_key_typed_raw.nim`):
  decode a TOML document into `TomlValueRef` (a `Table`), then evaluate
  `doc["absent", int]` (any compiled T — all 10 compiling Ts crash identically,
  `followup/valuemodel/innervalue.tsv`).
- **Observed outcome** (defects3 report §Defect 2, subject `4aa8e22`, Nim 2.2.10):
  - debug: traceback pins `value_ops.nim(87) []` → `value_ops.nim(16) innerValue` →
    `SIGSEGV: Illegal storage access. (Attempt to read from nil?)`, shell exit **139**.
  - `-d:release`: same `SIGSEGV`, same exit **139** (no traceback). Debug ≡ release.
  - `except Defect` handler never runs (instrumented probe `p2b` died by SIGSEGV before any
    handler); the declared `raises: [KeyError]` can never fire — the compiler itself refutes it
    (`value_ops.nim(86,77) Hint: '[]' cannot raise 'KeyError' [XCannotRaiseY]`, valuemodel
    surprise #4).
  - Contrast: the array typed accessor on an out-of-range index raises a clean `IndexDefect`,
    exit 1 (`p2c`); the untyped accessor silently returns nil, exit 0 (`p2d`).
- **Reachability precondition**: the accessors live in `toml_serialization/value_ops.nim`, which
  `toml_serialization.nim` does NOT re-export — a consumer must deliberately
  `import toml_serialization/value_ops` (defects3 surprise #2; exposure report Task 1).
- **Evidence**: `followup/defects3/report.md` (execution), `followup/valuemodel/report.md`
  Task 1–2 + `accessors.tsv` (250-row matrix: the SIGSEGV set is exactly the typed table
  accessor with an absent key, PLUS a nil receiver into `len`/`hasKey`/`contains`/`[]=`/`{}=`/
  `delete`/`copy`; everything else is catchable AssertionDefect, clean IndexDefect, or silent nil),
  `followup/exposure/report.md` (survey).

### 1.2 D-NIL — `Table == nil` / `InlineTable == nil` equality crash

- **Code site**: `toml_serialization/types.nim:178-188` — `func `==`*(a, b: TomlValueRef)`.
  After the left-operand nil gate (`a.isNil → false`, line 182-184), line 186 enters on
  `b.isNil`, and line 187 evaluates `b.kind` **on the nil `b`** whenever the receiver `a.kind`
  is `Table` or `InlineTable` → SIGSEGV. Scalar receivers return false safely (their kind fails
  the `tableKind` test before `b.kind` is read).
- **Minimal repro** (valuemodel probes, `equality.md` / `report.md` Task 3, one process per
  risky comparison): with `a` a decoded `Table` (or `InlineTable`) node, evaluate `a == nil`.
- **Observed outcome**: **SIGSEGV, exit 139, debug AND `-d:release`** — asymmetric:
  `nil == Table` is safe (returns false via the `a.isNil` gate). `Table == InlineTable` is fine
  (shared branch); the crash is specifically a table-kind left operand against a nil right
  operand.
- **Evidence**: `followup/valuemodel/report.md` Task 3 + surprises #1;
  `followup/valuemodel/equality.md`; raw runs in `followup/valuemodel/raw.tar.gz` (564 recorded
  runs).

---

## 2. Per-consumer verdicts — 72 triples, all N/A (R1)

**Attacker model** (same class as the campaign's B-SEC-02 rows): `attacker-controls-loaded-.toml`
— the attacker controls a TOML file the consumer loads (config/theme/workspace file).

**Call-site artifact** (uniform for every row, per the closure discipline): the consumer's row in
`followup/exposure/consumers.tsv` — call form `file:line` + decode form + input origin + resolved
dependency commit — backed by `followup/exposure/report.md` (Task 1: **zero** third-party
`value_ops` imports found at any revision, survey covering public GitHub default branches as of
2026-10-11; Task 4: the D1 conjunction — (a) resolved rev ≥ `71ed1393`, (b) explicit
`import toml_serialization/value_ops`, (c) typed accessor on a possibly-absent key — has zero
observed instances) and the reproducible queries in `followup/exposure/queries.md` (§A). For
D-NIL the additional mechanism artifact is `followup/valuemodel/equality.md` (shape), and the
per-consumer ground is the recorded call form.

### 2.1 D1 × 36 consumers

| # | consumer | call form (`consumers.tsv:L`) | resolved dep | D1 unreachability ground |
|---|---|---|---|---|
| 1 | nimbus-eth1 | `execution_chain/conf.nim:18-25` confutils typed reader (+ nim-eth enr/nat toml) | `73529768` (vendor submodule; postdates `71ed139`) | typed-reader path; repo-scoped searches: zero `value_ops`/`TomlValueRef` usage (queries.md A7) |
| 2 | nimbus-eth2 | `beacon_chain/nimbus_binary_common.nim:242` confutils addConfigFile | `b5b387e6` (vendor submodule) | typed-reader path; no value_ops usage; dep predates `71ed139` → shape absent at pin (second ground) |
| 3 | nim-confutils | `confutils/toml/defs.nim:15-21` adapter re-export only, no direct decode | floating (tag `b5b387e6`) | transitive adapter; no decode call, no value_ops import; tag predates `71ed139` |
| 4 | nim-eth | `eth/enr/enr_toml.nim:19-24`, `eth/net/nat_toml.nim` TomlReader readValue | floating (tag `b5b387e6`) | typed-reader path; no value_ops import; tag predates `71ed139` |
| 5 | nim-graphql | `graphql/test_common.nim:232,288` `Toml.loadFile(TestCase)` | pkg/ alias, rev unresolved | typed test-fixture decode; no TomlValueRef in recorded call form → not_used regardless of rev (dep unrecorded → freshness caveat) |
| 6 | imthemes | `src/browseview.nim:193` `loadFile(..., TomlValueRef)["themes"].getTables()` | `b5b387e6` (nimble.lock) | value-tree path via untyped `[]` + `getTables`; no typed two-arg accessor, no value_ops import; dep predates `71ed139` |
| 7 | nide | `src/nide/helpers/tomlstore.nim:10` loadFile/decode | `b5b387e6` (nimble.lock) | typed record decode; no value_ops import; dep predates `71ed139` |
| 8 | nph | `src/nph.nim` `Toml.loadFile(configFile, NphConfig)` | `b5b387e6` (nixpkgs lock.json; tag-resolve) | typed record decode (no TomlValueRef usage, grep 0 matches); dep predates `71ed139` |
| 9 | logos-delivery | nimble.lock; confutils config load | `b5b387e6` (nimble.lock) | typed-reader path; no value_ops import; dep predates `71ed139` |
| 10 | nimbos | `logos_chain/conf.nim` confutils | `b5b387e6` (vendor submodule) | typed-reader path; no value_ops import; dep predates `71ed139` |
| 11 | logos-storage-nim | `storage/conf.nim:30`; tests decode-only | `b5b387e6` (vendor submodule) | typed-reader path; no value_ops import; dep predates `71ed139` |
| 12 | archivist-node | `archivist/conf.nim:23` confutils | `b5b387e6` (vendor/nimble submodule) | typed-reader path; no value_ops import; dep predates `71ed139` |
| 13 | nim-promethei-node | `promethei/conf.nim:23` confutils | `b5b387e6` (vendor/nimble submodule) | typed-reader path; no value_ops import; dep predates `71ed139` |
| 14 | reprobuild | `libs/repro_workspace_manifests/.../reader.nim` decode | vendored copy byte-identical to `b5b387e6` (value_ops.nim, types.nim) | vendored `value_ops.nim` = pre-`71ed139` bytes → shape absent at pin |
| 15 | reprobuild-llm-agent-packages | `tools/coverage_report.nim:90` decode(Inventory) | floating (tag `b5b387e6`) | typed record decode; no value_ops import; tag predates `71ed139` |
| 16 | arpm | `src/libarpm/package_format/package_info.nim:28,40` decode(RawPackageInfo) | floating (tag `b5b387e6`) | typed record decode; no value_ops import; tag predates `71ed139` |
| 17 | libarpm | same as arpm | floating (tag `b5b387e6`) | same |
| 18 | enu | atlas.lock; toml decode of user project files | `b5b387e6` (atlas.lock) | typed decode; no value_ops import; dep predates `71ed139` |
| 19 | imclocks | `main.nim:601,618` `Toml.decode(..., TomlValueRef)` + untyped `[]` + getData | floating (tag `b5b387e6`) | value-tree path, untyped accessor only (exposure report Task 1: "all use the untyped accessor or hasKey"); no value_ops import; tag predates `71ed139` |
| 20 | imdemo | `main.nim`; resourcesdata.nim decode | floating (tag `b5b387e6`) | typed/value-tree decode, no typed two-arg accessor; no value_ops import; tag predates `71ed139` |
| 21 | impasswordgen | `main.nim` decode | floating (tag `b5b387e6`) | typed decode; no value_ops import; tag predates `71ed139` |
| 22 | sidebard | `src/core/config.nim:96,107,119` loadFile(RawConfig/PluginConfig/InstanceConfig) | floating (tag `b5b387e6`) | typed record decode; no value_ops import; tag predates `71ed139` |
| 23 | goodwm | `src/goodwm/configs.nim:192` decode(readFile, Config) | floating (tag `b5b387e6`) | typed record decode; no value_ops import; tag predates `71ed139` |
| 24 | scoopx | `src/scoopx/settings.nim:124` decode(TomlValueRef) + hasKey + untyped `[]` | floating (tag `b5b387e6`) | value-tree path, untyped accessor only; no value_ops import; tag predates `71ed139` |
| 25 | gdgw-maverick-bot | `src/nimcordbot/config.nim:22-27` decode(ConfigBase) | floating (tag `b5b387e6`) | typed record decode; no value_ops import; tag predates `71ed139` |
| 26 | click | `src/compile.nim:40-41` decode(readFile(click.toml), ClickConfig) | floating (tag `b5b387e6`) | typed record decode; no value_ops import; tag predates `71ed139` |
| 27 | feko | `src/config.nim:51` decode(Config) | floating (tag `b5b387e6`) | typed record decode; no value_ops import; tag predates `71ed139` |
| 28 | stickyshell | `src/sth.nim:8,12` decode(/etc or CWD conf) | floating (tag `b5b387e6`) | typed record decode; no value_ops import; tag predates `71ed139` |
| 29 | trayfetch | `src/config.nim` decode | floating (tag `b5b387e6`) | typed record decode; no value_ops import; tag predates `71ed139` |
| 30 | districity | `src/schemas.nim:62-74` decode(data, T, "section", TomlCaseNim) | floating (tag `b5b387e6`) | typed record decode; no value_ops import; tag predates `71ed139` |
| 31 | neo | `src/routines/project.nim` — **parsetoml**, NOT toml_serialization | n/a | classified out: consumes a different library (parsetoml); no toml_serialization decode at all |
| 32 | nim-systemverilog-dpic | `toml_to_struct/libdpi.nim:17` decode(readFile, T) | floating (tag `b5b387e6`) | typed record decode; no value_ops import; tag predates `71ed139` |
| 33 | everything | `everything.nimble` requires-only meta-package | floating | no decode call anywhere in the repo (aggregator only) |
| 34 | atlas-tests | `wsIntegration.nim:116` — none (URL list for resolver tests) | n/a | not a decode consumer: no toml_serialization decode call |
| 35 | forky | archived nimbus-eth2 copy (`forky-eth2/nimbus-23.5.1/.../el_conf.nim`) | 2023-era vendored rev (predates all pins) | archived typed-reader sources; rev predates `71ed139` → shape absent at pin |
| 36 | asisbusinessecigroup | copied nimbus-eth2 typed-reader sources (`beacon_chain/el/el_conf.nim` et al.) | copied files, no lock, rev unclear | copied typed-reader sources; no value_ops usage recorded; resolution unrecorded (freshness caveat) |

Rows 3, 31–34 note: `consumers.tsv` includes classification-only rows (transitive libs,
parsetoml consumers, meta-packages, non-consumers). They are carried as triples for completeness
of the enumerated set; their `not_used` ground is the recorded classification itself.

### 2.2 D-NIL × 36 consumers

Per-consumer ground for D-NIL: the recorded call form (same artifact rows as §2.1) contains **no
`TomlValueRef`/`InlineTable` vs-nil equality comparison** — typed-reader consumers never hold a
`TomlValueRef`; value-tree consumers (imthemes, imclocks, scoopx) use untyped `[]`/`hasKey`/
`getTables`/`getData`, not `==`; the classified-out rows have no decode call at all. Pin-level
presence of the `types.nim:187` shape at each consumer's resolved dep is NOT separately
established (valuemodel measured subject HEAD `4aa8e22` only) — this is recorded per row and in
§4 (R-O-5).

| # | consumer | recorded call form holds a TomlValueRef? | vs-nil comparison in call form |
|---|---|---|---|
| 1 | nimbus-eth1 | no (typed reader) | none |
| 2 | nimbus-eth2 | no (typed reader) | none |
| 3 | nim-confutils | no (adapter) | none |
| 4 | nim-eth | no (typed reader) | none |
| 5 | nim-graphql | no (typed TestCase fixture) | none |
| 6 | imthemes | yes (value-tree: untyped `[]`, `getTables`) | none |
| 7 | nide | no (typed record decode) | none |
| 8 | nph | no (typed NphConfig) | none |
| 9 | logos-delivery | no (typed reader) | none |
| 10 | nimbos | no (typed reader) | none |
| 11 | logos-storage-nim | no (typed reader; tests decode) | none |
| 12 | archivist-node | no (typed reader) | none |
| 13 | nim-promethei-node | no (typed reader) | none |
| 14 | reprobuild | no (typed decode, vendored) | none |
| 15 | reprobuild-llm-agent-packages | no (typed Inventory) | none |
| 16 | arpm | no (typed RawPackageInfo) | none |
| 17 | libarpm | no (typed decode) | none |
| 18 | enu | no (typed decode) | none |
| 19 | imclocks | yes (value-tree: untyped `[]`, getData) | none |
| 20 | imdemo | no (typed decode) | none |
| 21 | impasswordgen | no (typed decode) | none |
| 22 | sidebard | no (typed RawConfig/PluginConfig/InstanceConfig) | none |
| 23 | goodwm | no (typed Config) | none |
| 24 | scoopx | yes (value-tree: hasKey + untyped `[]`) | none |
| 25 | gdgw-maverick-bot | no (typed ConfigBase) | none |
| 26 | click | no (typed ClickConfig) | none |
| 27 | feko | no (typed Config) | none |
| 28 | stickyshell | no (typed decode) | none |
| 29 | trayfetch | no (typed decode) | none |
| 30 | districity | no (typed decode) | none |
| 31 | neo | no (parsetoml — different library) | none |
| 32 | nim-systemverilog-dpic | no (typed decode) | none |
| 33 | everything | no (meta-package, no decode) | none |
| 34 | atlas-tests | no (no decode call) | none |
| 35 | forky | no (archived typed-reader copy) | none |
| 36 | asisbusinessecigroup | no (copied typed-reader sources) | none |

**Rule citation for every row in §2.1/§2.2**: R1 — `present | not_used | * | * | present → N/A`.
`valid_config_contrast=unknown` and `protection_boundary=unknown` are honest values: no path
executes, so no contrast or boundary term was measured, and R1 does not read them. The
machine derivation is reproduced by `bash bsec/replay.sh judge` over
`bsec/offline/consumers/triples_facts.tsv`, cross-checked against `bsec/verdicts_recorded.tsv`.

---

## 3. Set-level summary — SCOPE-BOUNDED (a report, NOT a rule-table row)

**Summary wording**: No exposure was found within the enumerated consumer set — the 36
repositories of `followup/exposure/consumers.tsv` — under the surveyed attacker model class
(attacker-controls-loaded-`.toml`), as of the observation date 2026-10-11: for **D1**, no
enumerated consumer imports `toml_serialization/value_ops` or calls the typed two-arg accessor
on a possibly-absent key at its recorded resolution (zero `value_ops` import instances at any
revision, public GitHub default branches); for **D-NIL**, no recorded consumer call form contains
a `Table`/`InlineTable`-vs-nil comparison. All 72 per-consumer triples are N/A (R1, artifact on
record). **This is not a proof that the ecosystem is safe.**

**Enumerated consumer set**: the 36 rows of `followup/exposure/consumers.tsv` (§2 tables list
them). 13 hard pins (locks / submodules / vendored copies) were individually enumerated in
`followup/exposure/report.md` Task 2; the remainder are "floating" consumers classified as
tag-resolving to `b5b387e6` (absent a lock, plain nimble resolution lands on the tag, not HEAD).

**Coverage of the set-level result** (all from the exposure survey, `report.md` + `queries.md`):
public GitHub; **default branches only** (GitHub code search limitation); GitHub-indexed (legacy
REST code-search index — demonstrably incomplete: `repo:status-im/nim-graphql toml_serialization`
returned 0 despite a known import, and quoted-phrase queries return 0 despite known matches, so
negative query results are weaker than positive ones); submodule/vendor contents were found via
`.gitmodules` + submodule-SHA enumeration, not code search; **as of 2026-10-11** (~12:06–13:00
UTC survey window).

**NOT surveyed — the unsurveyed remainder stays UNKNOWN**: non-GitHub forges (GitLab, Codeberg,
self-hosted); non-default branches; forks (excluded by the index); private, deleted, or
unindexed repos; dependency versions other than the recorded resolutions — in particular
untagged post-`b5b387e6` commits reachable by a build-time source checkout that floats to the
default branch (HEAD `4aa8e22`, where both mechanisms are live); submodule/vendor trees other
than the six submodules + reprobuild vendored copy actually enumerated; any consumer outside the
GitHub index. For all of these, no triple exists — they are neither GO, NO-GO, nor N/A; they are
**UNKNOWN** (unenumerated = unadjudicated, `JUDGMENT.md` §3).

**The set-level summary is a report, not a rule-table row.** `rules/rule_table.tsv` derives
verdicts only over enumerated (defect × consumer × attacker-model) triples; there is no
observation tuple whose rule match produces "the set". Nothing in `verdicts_recorded.tsv` or
`triples_facts.tsv` encodes §3 — by construction it cannot be derived, only read, and it must
not be quoted as a derived verdict.

---

## 4. REOPEN — exact conditions that reopen this closure

- **R-O-1 (D1, per consumer)**: any consumer — inside or outside the enumerated set — is
  observed importing `toml_serialization/value_ops`, or calling the typed two-arg accessor
  `["key", T]` / `[i, T]` on a possibly-absent key/index. That consumer's D1 triple reopens
  immediately (the N/A's load-bearing fact is contradicted).
- **R-O-2 (D1, per consumer, resolution movement)**: any consumer's dependency resolution moves
  to a revision ≥ `71ed1393` — lock/submodule/vendored bump, or a floating consumer building
  from a source checkout of the default branch instead of the tag `b5b387e6`. The recorded
  pin-level ground ("shape absent at the pin") evaporates; only the value_ops-import ground
  would remain, and it must then be re-established at the new resolution. (`replay.sh
  freshness` fires on the same movement for recorded terms.)
- **R-O-3 (D1, set level)**: a library revision makes a nil-producing path reachable WITHOUT the
  deliberate `value_ops` import — e.g. `toml_serialization.nim` begins re-exporting
  `value_ops`, or the silent-nil untyped `[]` / guarded `{}` / `getOrDefault` results feed any
  proc reachable through the default export set that dereferences `.kind`. The zero-import
  barrier is load-bearing for the whole set-level summary; removing it reopens every row.
- **R-O-4 (D-NIL, per consumer)**: any consumer call form is observed comparing a table-kind
  `TomlValueRef` (`Table`/`InlineTable`) against nil — including any code path that constructs
  a nil `TomlValueRef` and compares it (e.g. `tbl == nil` after a failed lookup). That
  consumer's D-NIL triple reopens.
- **R-O-5 (D-NIL, per pin)**: pin-level establishment of the `types.nim:187` shape at any
  recorded consumer resolution reopens that resolution's row (the shape was verified only at
  subject HEAD `4aa8e22`; its presence or absence at `b5b387e6`-era pins is currently
  UNDETERMINED and was not needed for the N/A, which rests on the call-form ground).
- **R-O-6 (both, mechanism change)**: subject moves past `4aa8e22`; or `innerValue` gains a nil
  guard; or `types.nim `==`` gains a nil guard; or any mechanism-adjacent change lands. Verdicts
  do not survive mechanism changes — all 72 triples re-observe.
- **R-O-7 (set level, index)**: discovery that the GitHub-index negative results were incomplete
  beyond the gaps already recorded in `followup/exposure/queries.md` §"Known index gaps" —
  the §3 set-level summary is recomputed over the corrected index view.
- **R-O-8 (freshness, standing)**: unrecorded consumer commits (e.g. ImThemes repo commit,
  nim-graphql resolution) and temp-path clones make `replay.sh freshness` fail closed by design;
  any future pinning or re-resolution observed there reopens the affected triples' freshness
  terms.

---

## 5. What this record does not do

- It does NOT change any existing verdict (`B-SEC-01` NO-GO, `B-SEC-02` UNKNOWNs, `B-SEC-03`
  N/A/UNKNOWN, `B-SEC-03|nimbus-eth1` UNKNOWN all stand untouched).
- It contains NO severity, CVSS, or prioritization assessment. No issue was filed upstream.
- It does NOT claim ecosystem safety (§3, explicit sentence above). UNKNOWN means undetermined,
  never safe; N/A is bounded to this exact consumer AND recorded version.
- It is a fact-binding record over evidence collected 2026-10-11; per-consumer resolutions are
  point-in-time observations, not guarantees about the world.
