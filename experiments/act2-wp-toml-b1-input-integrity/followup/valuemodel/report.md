# valuemodel — deterministic map of the value-model equality semantics and the accessor/type crash boundary

Subject: `<workspace>/nim-toml-serialization` @ `4aa8e2223649fc0837c490a4acfca7b8b1e756f9` — READ-ONLY, byte-clean before and after every run (`raw/baseline_clean.txt` empty, `raw/final_clean.txt` empty, snapshots + `raw/subject_untouched.diff` empty).
Toolchain: Nim 2.2.10 (`~/.choosenim/toolchains/nim-2.2.10/bin/nim`), `--mm:orc --skipUserCfg --skipParentCfg --skipProjCfg`, `--path` to the subject clone + nimble `serialization-0.5.4-6a75be38…` / `faststreams-0.5.2-589a9cf0…` / `stew-0.5.0-db229429…`. All compiles/runs from `/tmp/valuemodel_build` (neutral cwd); binaries in `/tmp` only.
Provenance: `raw/env.txt`, `raw/subject_hashes.txt` vs `raw/subject_hashes.after.txt` (identical), `raw/runs.tsv` (564 recorded runs), `raw.tar.gz` (member hashes in the experiment-root `MANIFEST`; the `./repro.sh` regeneration driver was removed 2026-10-11).
Scope discipline: fact-finding only — no severity, no CVSS, no issue filed. Spec verdicts separated per followup/SPEC_BASELINE.md §7 in `SPEC_CLAIMS.md`.

---

## Task 1 — accessor/type boundary matrix (`accessors.tsv`, 250 observed rows)

`value_ops.nim` exposes **14 public accessors** (reachable only via `import toml_serialization/value_ops`; toml_serialization.nim does NOT re-export it):

| accessor | cite | receiver contract | one-line observed semantics |
|---|---|---|---|
| `len` | :70-77 | none | Array → seq len; Table → pairs len; **Tables/InlineTable → 0**; scalar → 0; nil → SIGSEGV |
| `node[k]` untyped | :79-84 | assert Table, assert non-nil | Table → value or **nil silently** (no KeyError despite doc comment); wrong kind / nil → AssertionDefect |
| `node[k, T]` typed | :86-87 (+innerValue :14) | assert via untyped | Table+present → converted value; **Table+absent → SIGSEGV**; wrong kind/nil → AssertionDefect; declares `raises:[KeyError]` which the compiler itself refutes (`XCannotRaiseY` hint at :86:77) and which never fires |
| `node[i]` untyped | :89-95 | assert Array, non-nil | Array+in-range → node; OOB → IndexDefect (clean, exit 1); wrong kind/nil → AssertionDefect |
| `node[i, T]` typed | :97-98 (+innerValue) | assert via untyped | same boundary as typed-table, array side |
| `hasKey` | :100-103 | assert Table | bool; wrong kind → AssertionDefect; nil → SIGSEGV (assert reads node.kind on nil) |
| `contains(key)` | :105-108 | assert Table | same boundary as hasKey |
| `contains(val)` | :110-113 | assert Array | Array → find(); wrong kind → AssertionDefect; nil → SIGSEGV |
| `node[k] = v` | :115-118 | assert Table | Table → insert/overwrite; wrong kind → AssertionDefect; nil → SIGSEGV |
| `node{keys}` | :120-128 | **guarded** | nil / non-Table / missing → nil (never raises) — the only fully defensive getter family |
| `getOrDefault` | :130-134 | **guarded** | same — nil everywhere on any mismatch incl. nil receiver |
| `node{keys} = v` | :136-144 | via hasKey (assert Table) | Table → creates missing intermediates (`emptyTable()`); wrong kind → AssertionDefect; nil → SIGSEGV |
| `delete` | :146-151 | assert Table | Table+present → delete; **Table+absent → IndexDefect** ("key not in object"); wrong kind → AssertionDefect; nil → SIGSEGV |
| `copy` | :153-196 | **no assert at all** | every real kind deep-copies; **nil receiver → SIGSEGV** (`case p.kind` on nil, both builds) |

**The SIGSEGV set (exact)** — debug AND `-d:release` produce identical outcomes for every row (asserts stay enabled at `-d:release`; only `-d:danger` would change the regime, not run here):

1. `doc["absent", T]` — **typed TABLE accessor × Table receiver × absent key** (value_ops.nim:87 → nil from `getOrDefault` → `case n.kind` at :16). This is the headline trigger: the nil flows *through* the untyped accessor's asserts untouched (they passed — node was a valid Table) and innerValue has no guard.
2. **Nil receiver** into: `len`, `hasKey`, `contains(key)`, `contains(val)`, `node[k] = v`, `node{keys} = v`, `delete`, `copy` — 8 accessor/receiver combinations. Mechanism: their `assert(...)` expressions themselves evaluate `node.kind` (or `p.kind`) on the nil ref, so the assert cannot fire; where `copy` is concerned there is no assert at all. (For `node[k]`/`node[k,T]`/`node[i]`/`node[i,T]` the FIRST `assert(not isNil(node))`/kind-check *does* fire → catchable AssertionDefect, exit 1.)

Everything else: Table+present returns the value; untyped missing key returns nil SILENTLY (no KeyError anywhere — `node["absent"]` isNil=true, exit 0); wrong-kind receivers uniformly raise AssertionDefect (exit 1); array OOB raises IndexDefect (exit 1).

Receiver-kind note: **`TomlKind` has no Date/Time members** (types.nim:59-68) — date-only and time-only values are `TomlKind.DateTime` with `Option` fields; the matrix covers all 9 real kinds + nil (the task's "Date"/"Time" receiver states cannot exist).

## Task 2 — innerValue type coverage (`innervalue.tsv`)

innerValue (:14-68) is instantiated per T by exactly two callers (:87 string-key, :98 int-key typed accessors; grep-verified — no other caller in the repo). Verdict:

- **Compiles and works** (10): `int`, `int32`, `int64`, `uint`, `uint64`, `float`, `float32`, `bool`, `string`, `TomlDateTime`.
- **Never compiles** (11): `TomlDate`/`TomlTime` (dateDimte + missing `std/options` — see dateDimte.md), `TomlValueRef`/`object`/`Option[int]`/`Option[TomlDate]` (`.error: "Failed to convert to unsupported type"` at :68 — there is NO Option branch at all), `seq[any]`/`array[any]` (the seq/array branches can never instantiate: Array needs `seq[TomlValueRef]`, Tables needs `seq[TomlTableRef]`, and no element type satisfies both — **dead branches for every T**), `enum` for EVERY enum type (`parseEnum` may raise ValueError, forbidden by `push raises: []` at :8 — **dead branch**).

Runtime semantics of the compiling Ts (all from `raw/q2r_*.out`, debug = release):
- matching kind → the value (`doc["i", int]` → 7; `doc["f", float]` → 1.5; `doc["s", string]` → "hi"; `doc["b", bool]` → true; TomlDateTime → full Options).
- mismatching kind → **silent default value** (never raises): numeric Ts convert Int↔Float (`float` of Int 7 → 7.0; `int` of Float 1.5 → 1, truncation); String/Bool mismatches → `""`/`false` (no truthiness, `Int 1 → false`); TomlDateTime mismatch → all-None.
- narrowing edge: `doc["big", int32]` with big=5000000000 raises **RangeDefect** at value_ops.nim:17 ("value out of range: 5000000000 notin -2147483648 .. 2147483647", exit 1) — not a silent truncation; `uint64` of `-1` wraps to 18446744073709551615 with no check.
- absent key → **SIGSEGV exit 139 for every compiled T, debug and release**; `except Defect` cannot run; KeyError never fires.

## Task 3 — equality semantics (`equality.md`, full numbers)

All from `raw/q3a_tolerance.out` / `raw/q3b_structural.out` / `raw/q3c_*.out` (one process per risky comparison):

- **1E-7 tolerance confirmed** (types.nim:198, `abs(a-b) < 1E-7`, strict): 8.99999998971168225e-08 → equal; 9.99999989481636931e-08 → equal; 1.00000000946565137e-07 → not equal.
- **Non-transitivity triple**: a=1.0, b=1.0000000899999999 (1+9e-8), c=1.0000001800000000 (1+1.8e-7): a==b **true**, b==c **true**, a==c **false** → `TRIPLE => true`.
- **Order-dependence (new, beyond the brief)**: the `classify(a)` gate reads only the left operand — `0.0 == 5e-8` **false** but `5e-8 == 0.0` **true**; likewise 1e-10. Propagates into arrays: `Array[F(0.0)] == Array[F(5e-8)]` false, reverse **true**.
- **Non-normal classes**: `NaN == NaN` **true**; `+0.0 == -0.0` **false** both ways; Inf==Inf true; Inf==-Inf false; two DIFFERENT subnormals (5e-324, 9.88e-324) compare **true** (class equality replaces the tolerance).
- **Table == InlineTable → true**, both directions (shared branch :214-215); differing content or length → false.
- **Tables vs Array → false** both directions, no content inspection (kind gate).
- **Cross-kind scalars all false, exact**: Int 1 vs Float 1.0 → false; String "1" vs Int 1 → false; Bool true vs Int 1 / Float 1.0 → false; strings byte-exact; DateTime exact incl. zone Options (Z vs no-zone unequal; `-05:00` decodes `positiveShift=false, hourShift=5`).
- **nil**: nil==nil true; nil==value false both directions for Int/Array; **`Table == nil` and `InlineTable == nil` SIGSEGV (exit 139, dbg+rel)** — `b.kind` dereferences nil at types.nim:187 after the `tableKind` gate; `nil == Table` is safe (false).
- **All other verdicts use exact comparison** (strings bytes, ints, bools, seq/table/tables structure with exact non-float elements; the Float branch is the ONLY tolerant comparison in the value model).

## Task 4 — dateDimte blast radius (`dateDimte.md`)

- Affected surface: exactly the two typed accessors (`[]` string-key :86-87, `[]` int-key :97-98) with T ∈ {TomlDate, TomlTime} — compile-time failure, verbatim `value_ops.nim(32,19)` / `(36,19) Error: undeclared field: 'dateDimte' for type types.TomlValueRef` (full text in dateDimte.md §5). Both-in-one compile reports only the :32 error (Nim stops at first).
- `TomlDateTime` NOT affected: its branch (:26-28) reads `n.dateTime` cleanly; runtime-verified for all four DateTime variants incl. `-05:00` offsets (`raw/q4d_tomldatetime_ok.out`).
- Direct typed decode NOT affected: `Toml.decode(..., TomlDate/TomlTime/TomlDateTime, "key")` works (reader path never instantiates innerValue; `raw/q4e_direct_decode.out`).
- Typo-only repair still fails: patched /tmp copy (`raw/q4_patched_copy.diff` = exactly two tokens) fails with `Error: type mismatch — get(n.dateTime.date): Option[types.TomlDate]` because `std/options` is neither imported by value_ops.nim nor re-exported by types.nim → the Date/Time accessor rows are unreachable at compile time either way.

## Surprises beyond the brief (observations only)

1. **`Table == nil` crashes** (asymmetric: `nil == Table` returns false) — types.nim:187.
2. **Order-dependent float equality**, and it propagates through Array elements.
3. **innerValue's seq, array AND enum branches are dead for every T** (dual-branch type conflict; parseEnum ValueError vs `raises: []`).
4. **The compiler itself flags the false contract**: `value_ops.nim(86,77) Hint: '[]' cannot raise 'KeyError' [XCannotRaiseY]` on every typed-accessor compile.
5. `int32` (and narrower) conversions raise RangeDefect instead of truncating; `uint64` of a negative Int wraps silently.
6. `len(Tables) == 0` and `len(InlineTable) == 0` (doc comment mentions only Array/Table).
7. `delete` raises **IndexDefect** (not KeyError) for a missing table key — "key not in object".
8. `-d:release` keeps all runtime checks incl. assertions in Nim 2.2.10 — the entire matrix is dbg≡release; only a `-d:danger` build could enter the UB/garbage regime (not run; the observable boundary documented here is the supported-build one).
9. `node{keys}` / `getOrDefault` are the only defensive accessors (nil on every mismatch, never raise); everything else is assert-gated or crash-prone on nil.

## Constraints honored

- Binaries and the patched subject copy live only in `/tmp/valuemodel_build`; nothing else written outside the deliverable directory.
- Subject repo byte-clean: verified before (`raw/baseline_clean.txt`), after (`raw/final_clean.txt`), plus hash-identical snapshots (`raw/subject_hashes.txt` == `raw/subject_hashes.after.txt`, `raw/subject_untouched.diff` empty).
- No severity/CVSS assessment; no issue filed anywhere; spec discipline in SPEC_CLAIMS.md ((A)/(B) separation, pinned 1.0.0 clauses, no severity).
- Probe convention: every `probes/*.nim` starts with `# nim-check: skip` + rationale (out-of-tree --path imports cannot resolve in repo context; convention of `experiments/bug-verdict-e2e/cout_probe.nim`).

## Files

```
accessors.tsv        Task 1 — 250-row accessor x kind x arg grid (generated from raw/runs.tsv)
innervalue.tsv       Task 2 — per-T compile/runtime verdicts with verbatim errors
equality.md          Task 3 — tolerance, non-transitivity, asymmetry, nil, cross-kind
dateDimte.md         Task 4 — blast radius with verbatim compile errors
SPEC_CLAIMS.md       pinned spec clauses implicated ((A)/(B) separated, no severity)
report.md            this file
raw.tar.gz           pinned observation bytes (driver removed 2026-10-11; method = probes/ + this report)
sha256sums.txt       hashes: inputs/, probes/, subject anchors
inputs/              TOML fixtures (doc_scalar, doc_temporal, doc_struct, doc_table_absent)
probes/              41 probe sources (q1_matrix, q2c_* x21, q2r_* x10, q3a-c, q4a-f)
raw/                 all run artifacts (env, compile outs, per-run out/err/exit, runs.tsv,
                     patched-copy diff, subject integrity snapshots, raw.SHA256SUMS)
```
