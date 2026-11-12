# LLBC Quirks (Charon 0.1.281 measured)

> AGENTS.md §0.5 **Quirk Mandate**: discovered language/compiler/toolchain quirks
> MUST be documented here and referenced from
> `docs/agents/constitution_details.md` §0.5b.

Quirks observed while parsing real Charon LLBC output (`charon_version 0.1.281`,
pinned `charon-pin 798016509139eb51f0d764645f76d068d34ba5f6`). All entries are
`[measured]` unless marked `[documented]`.

---

## Q1 — Type and constant interning use SEPARATE id spaces, and the definition appears at first use in document order [measured]

The LLBC JSON streams definitions: an id is introduced as
`{"Value": [id, payload]` at its first occurrence, and later references are
`{"Deduplicated": id}`. Two independent id spaces exist — **types** and
**constants** — so a type id and a constant id may collide numerically without
being the same object.

Consequence: a reader must track both tables independently and must reject a
`{"Deduplicated": n}` whose definition has not yet been seen. Silently treating
an undefined id as a default is a correctness bug, not a convenience.

Observed failure when this is wrong: `parseJson` on a fixture that referenced an
undefined interned id produced `rceMalformed "unresolved interned type id 4"` —
the parser's fail-closed behavior was correct and the fixture was at fault.

## Q2 — `is_zero`-shaped code lowers to `Switch` (v1.4: collapsed for the measured bool-expression shapes; other shapes rejected) [measured]

`fn is_zero(a: u8, b: u8) -> bool { a == 0 && b == 0 }` compiles to a `Switch`
statement over the comparison result. The v1 closed grammar was straight-line
only (see `docs/spec/rust_certified_subset.md` §2), so `Switch`/`SwitchInt` were
**rejected**, not lowered.

**Superseded by v1.4 (`feat/rust-escape-slice`).** `Switch` is no longer
rejected wholesale. The producer collapses the measured bool-expression
shapes into one expression tree (`collapseBody` —
`src/verification/llbc_to_canonical.nim:1410`): exactly one bool pattern per
`Switch` (the fallback is the other side), `ite(cond,true,e) → or(cond,e)`,
`ite(cond,e,false) → and(cond,e)`, `ite(cond,true,false) → cond`
(`iteNormalize` — `:1132-1143`). `is_zero` now yields
`and(eq(a,0), eq(b,0))`; `is_escape` yields
`or(eq(ch,34), or(eq(ch,92), and(inc, lt(ch,32))))`. The `not`-needing shape
`ite(cond,false,true)`, integer/enum patterns, a multi-pattern `Switch`,
`Panic`/other statement kinds inside a branch, and every other
`Switch`/control-flow shape still fail closed (`:1078-1098,:1303-1394`).
`SwitchInt` remains rejected.

This corrected an earlier measurement that listed "11 node kinds" without
`Assert` or `Switch`. The accurate split:

- straight-line accepted: `StorageLive`, `StorageDead`, `Assign`, `Return`,
  `Panic`, `Use`, `BinaryOp`, `AddChecked`, `Copy`, `Move`, `Constant`
- `Assert` is accepted **only** as part of the `AddChecked` collapse pattern
  (it is the checked-add overflow guard)
- `Switch` is collapsed **only** for the measured bool-expression shapes
  (above); `SwitchInt` / `Call` / `Goto` / `Cast` / `Len` / `Discriminant` are
  **rejected** (`rceUnsupportedGrammar`)

## Q3 — `AddChecked` is always followed by an `Assert` that must be consumed by the collapse, never dropped [measured]

A checked add in LLBC appears as `BinaryOp ["AddChecked", ...]` together with a
trailing `Assert` (the overflow check) and a `Panic` on failure. The three form
one lowering unit. Two failure modes must both be rejected:

- `AddChecked` without its `Assert` → `rceMalformed` (the collapse is incomplete)
- a free-standing `Assert` outside any `AddChecked` pattern → rejected
  (silently ignoring it would drop an overflow guard)

## Q4 — `on_unwind` is a full statement object, not a bare value [measured]

The `on_unwind` field carries a complete statement block
(`{span, id, statements: [...], comments_before}`) including `UnwindResume`
kinds. Readers that assume a scalar will mis-parse the document.

## Q5 — The 1-element `NonEmptyVec` projects as an object, not an array [measured]

Fields documented as "non-empty vectors of length 1" serialize as a bare object
rather than a one-element JSON array. A reader that requires an array will
reject valid input.

## Q6 — `BinaryOp` operator spelling is a bare string, and the top-level `BinaryOp` rvalue admits only `Eq` [measured]

`{"BinaryOp": ["Eq", op1, op2]}` — the operator is a plain string, not a tagged
object. The top-level `BinaryOp` rvalue accepts `Eq` only; every other operator
is rejected there. `+` does NOT appear as `BinaryOp` at all — it appears as
`AddChecked`. v1.4 adds `Lt`/`And`/`Or` only inside the collapsed expression
tree (`RExpr.binaryOp` — Q13), never as a top-level `BinaryOp`.

## Q7 — `translated.files` embeds full source for the local crate and `null` for external crates, and the document carries no digest anywhere [measured]

Entries are `{id, name, crate_name, contents}` with `name` shaped
`{"Local": "src/lib.rs"}` for the local crate. Measured on the 0.1.281 probe:

- the local entry's `contents` is the **full source text**, and its sha256
  (`03f9d38811189446…`) is byte-identical to the on-disk `src/lib.rs` at
  extraction time;
- external crate entries (`core` in the probe) carry `contents: null`;
- a full-document scan finds **no hash/checksum/digest field** — not per
  file, not per crate, not document-level.

Consequence: any digest used for integrity or staleness must be computed by
Axiom itself; the document never supplies one.

Trust scope: `contents` is **self-reported** — the extractor quoting its own
input, with no authentication binding it to a workspace state — so it is
never consumed as trust-adjudication evidence in an equivalence check. Its
sanctioned use is narrower: an input to the **staleness gate** (does the
current disk file still hash to the recorded extraction input?).

Admission policy (fail-closed, applied before any set comparison): a `files`
table entry that violates the expected shape — an unknown `name` form, a
non-`null` `contents` on a non-local crate, a missing field, or a crate
entry outside the expected extraction set — rejects the whole document;
set-comparison consumers run only on documents that passed this admission.

## Q8 — The header is exactly three keys; the extraction environment is only partially recoverable from the document, and rustc identity is not in it at all [measured]

Top-level keys, measured: exactly `charon_version`, `has_errors`,
`translated`. This corrects an earlier assumption — in both directions:

- contrary to "no target/options embedded": the environment carriers exist
  one level down, under `translated`. `target_information` holds the
  concrete triple (`x86_64-unknown-linux-gnu` in the probe) with layout
  facts (`target_pointer_size`, `is_little_endian`,
  `c_enum_smallest_repr_ty`, `primitive_alignments`); `options` holds the
  resolved Charon option map (`ullbc`, `monomorphize`,
  `include`/`exclude`/`opaque`, …) including a `rustc_args` field (empty in
  the probe);
- still genuinely absent: the rustc version/identity and the cargo-derived
  rustc invocation (`--edition`, `--cfg`, externs, `-C` flags) —
  `options.rustc_args` records only Charon-passed extras, and no
  `rustc_version`-like field exists (string scan: 0 occurrences).

Consequence: the target triple is recoverable from the document, but rustc
identity and the full option surface are not — the extraction work record
(provenance) must record them; they cannot be read back from the LLBC.
`charon_version` is recorded provenance (`tcRecorded` grade): it identifies
which producer ran and is not a trust-adjudication root — the rustc→LLBC
channel stays the Qualified/assumption boundary of ADR-0030 D3
(`docs/adr/0030-rust-subject-semantic-authority.md`).

## Q9 — Output volatility is governed by Charon's own version contract, and the effective rustc identity is transitively the `charon-pin` [documented]

From Charon's `docs/versioning.md` + `CONTRIBUTING.md`:

- `charon version` prints the semver **plus the source commit hash**;
- any PR changing JSON serialization must bump the version in
  `charon/Cargo.toml`, and **both** the Rust and OCaml deserializers check
  the version on load;
- per-crate options live in `[package.metadata.charon]` in the crate's
  `Cargo.toml` (CLI flags win on conflict) — the same source can yield
  different LLBC under different option surfaces;
- Charon builds the translated crate with the Rust **nightly pinned in its
  own `rust-toolchain.template`**, not the ambient toolchain.

Consequence: (a) the option surface that shaped an LLBC document is part of
its provenance — record `[package.metadata.charon]` + CLI flags next to
`charon_version`; (b) rustc identity is **transitively** a function of the
`charon-pin`: the nightly Charon's template pins at that revision is the
rustc that actually produced the artifact. Pin authority is the Aeneas
consumer side (`docs/spec/rust_toolchain_quirks.md:141-155`, Q3); a rustc
version read from the ambient environment can describe a compiler that
never ran on this input.

## Q10 — Build-script-generated files enter `translated.files` with an ABSOLUTE `OUT_DIR` path, and the subject-relative pre-validation rejects the document [measured]

Observed 2026-10-31 (serde_json v1.0.154 claim campaign — a `build.rs`-bearing
subject). The extraction's `files` table had 151 entries; exactly one —
`files[1]` — carried an absolute path: the build-script output module
`out/private.rs` under the state-owned charon-target build directory, while
`files[0]` and `files[2]`+ were subject-relative (`src/lib.rs`, `src/error.rs`,
…). The lane's pre-validation (subject-relative POSIX path required) rejected
the document fail-closed, BEFORE the signature gate:

```
producer: LLBC files table pre-validation failed: files[1]: absolute path '.4/experiments/serde-json-claim-2026-10-31/state_d1/.axiom/rust-lane/1398235db249fc8b/charon-target/x86_64-unknown-linux-gnu/debug/build/serde_json/211aa9d180883da9/out/private.rs' (subject-relative POSIX path required)
```

Reproduction conditions: the subject crate ships a build script that
generates a Rust module into `OUT_DIR` (serde_json's build.rs emits
`private.rs`), and the crate is extracted via `charon cargo` with a target
dir outside the subject tree. The campaign reproduced the same rejection
class three times — cold d2 and the post-landing pinned d3 rerun differ from
d1 only in the run-local path substrings (state dir name + build-hash segment
`211aa9d180883da9` / `8b65d3d27583c0f0` / `4bceeb2bfd3e9415`) — a
re-run-invariant observation, and one of the bases for the campaign's
terminal SCOPE_LIMIT_CONFIRMED.

Official documentation basis [documented — the Cargo side only]: The Cargo
Book fixes where build-script outputs live and that the directory is
absolute:

- `OUT_DIR` — "the folder in which all output and intermediate artifacts
  should be placed. This folder is inside the build directory for the package
  being built, and it is unique for the package in question"
  (<https://doc.rust-lang.org/cargo/reference/environment-variables.html>);
- "Build scripts may save any output files or intermediate artifacts in the
  directory specified in the `OUT_DIR` environment variable"
  (<https://doc.rust-lang.org/cargo/reference/build-scripts.html>);
- build-script output lives under `<build-dir>/debug/build/`, a layout
  "considered internal to Cargo, and is subject to change"
  (<https://doc.rust-lang.org/cargo/reference/build-cache.html>) — the
  observed `build/serde_json/<hash>/out/` shape and its per-run hash segment
  are that internal layout, recorded as observation, not contract;
- the external-tools JSON interface documents `out_dir` as "An absolute
  path" (<https://doc.rust-lang.org/cargo/reference/external-tools.html>).

What official docs do NOT state: that Charon records those OUT_DIR files in
the LLBC `translated.files` table (Q7) serialized with absolute host paths.
That producer behavior is [measured] only.

Consequence: a `build.rs`-bearing subject is outside the v1 lane input
contract — the files-table pre-validation (Q7 admission policy) fails closed
before the signature gate, and the rejection `reason` embeds run-specific
absolute paths (state dir + build-hash), which also breaks byte-equality
comparison of skReport payloads for this reason class. Evolution of the
files-table path contract (subject-relative or a declared path class for
generated files) is a SEPARATE planned task — authority, state transition,
and failure semantics must be defined first (변경 불변조건 프로토콜); this
record documents the observation only.

Campaign evidence: `experiments/serde-json-claim-2026-10-31/`
(probe/d1/d2/d3 runs) +
`docs/evidence/serde_json_claim_adjudication_2026-10-31.md` §5/§7/§8 (verbatim
reasons, 151-entry table, three-run reproduction).

---

## Q11 — Inherent-impl methods name-path as `[Ident(crate), Ident(module), Impl{Ty{kind:"InherentImplBlock", skip_binder:<type ref>}}, Ident(method)]`; the owner is a TYPE REFERENCE resolved through a DEDICATED owner map collected from `translated.item_names` [measured]

Observed 2026-11-02 (`axiom_impl_probe` — the impl-identity fixture crate,
measured with the pin-exact charon 0.1.281 over `impl Dog { fn speak … }` /
`impl Cat { fn speak … }` in modules m1/m2). The `item_meta.name` path of an
inherent-impl method carries the impl block as a path ELEMENT:

```json
[{"Ident": ["axiom_impl_probe", 0]}, {"Ident": ["m1", 0]},
 {"Impl": {"Ty": {"params": {…}, "skip_binder": {"Deduplicated": 1},
                  "kind": "InherentImplBlock"}}},
 {"Ident": ["speak", 0]}]
```

The `skip_binder` type reference resolves through a DEDICATED owner map, NOT
the general document-order intern table: `{"Deduplicated": vid}` → the map's
`{"Value": [vid, payload]}` definition → payload `{"Adt": {"id": N, …}}` →
`type_decls[N].item_meta.name` (the owner's nominal Ident path — measured
vid 1 → `axiom_impl_probe::m1::Dog`, vid 2 → `axiom_impl_probe::m2::Cat`).
The general table is unusable for owner resolution because it conflates two
ADDITIONAL colliding id spaces beyond the Q12 layout collision: an Adt's
`generics.trait_refs[*]` carry `{"Value": [id, {"kind": "BuiltinOrAuto", …}]}`
pairs in the TRAIT space whose ids numerically collide with type-space ids
(measured: the pair under
`fun_decls[1]/body/Structured/locals/locals[5]/ty/Value[1]/Adt/generics/trait_refs[0]/Value`
shadows Adt ids 1/2 — the owners would misresolve). The owner map is
collected from `translated.item_names` ONLY: that name-path intern list
precedes `type_decls`/`fun_decls` in the fixed key order, carries the first
serialization of every owner type, and contains no trait_refs or layout
payloads — collision-free by construction.

Consequences (all measured on the same document):

- A **scalar owner** exists: `core::num::<impl u8>::wrapping_add` carries
  `skip_binder: {"Deduplicated": 0}` where type id 0 is `{"Scalar": {"Integer":
  {"Unsigned": "U8"}}}` — a primitive, NOT an Adt, so it has NO nominal owner
  path. Such a decl is UNADDRESSABLE by structured name: the enumeration
  skips it (honest `--target wrapping_add` → NotFound), and no invented
  `<impl u8>` spelling is fabricated.
- `type_decls[N].def_id == N` (array index) held on every measured document;
  the resolver cross-checks it and fails closed on divergence.
- Rust's one-definition rule makes (owner nominal path, method name) unique
  per crate, which is what the structured match key relies on; the impl
  block's own module (the Ident segments before the `Impl` element — equal to
  the owner's module in every measured case) is what the CANONICAL records as
  `modulePath` (the decl's measured module), never the match key.

Resolution in code: `funDeclStructuredName` / `llbcFunDeclNamePaths` /
`decodeNamePath` in `src/verification/llbc_to_canonical.nim` (the Impl
element is accepted ONLY as a single `InherentImplBlock`; trait impl blocks
and any other Impl kind → unsupported, honest out-of-subset). The owner map
is `LlbcDeclCtx.ownerTypes` (`Table[int, JsonNode]`), filled by collecting
interns from `translated.item_names` alone in both `buildDeclCtx` and
`llbcFunDeclNamePaths`; `implOwnerNominalPath` resolves `Deduplicated` owner
ids against it and fails closed with "no item_names definition" when an id
is absent.

## Q12 — Layout expressions reuse the `{"Value": [id, payload]}` form with ids that COLLIDE with the type intern space, and appear only under the `layout` key of `type_decls` entries [measured]

Observed 2026-11-02 (`axiom_impl_probe`, same document). Charon interns layout
expressions in a SEPARATE id space that overlaps numerically with the type
space, and serializes them in the same `{"Value": [id, payload]}` /
`{"Deduplicated": id}` streaming form. On the measured document the type
table's id 0 (u8, first defined in `item_names` — see Q11) is shadowed by
Dog's layout `size.chosen` — `{"Value": [0, {"Constant": …}]}` under
`type_decls[1].layout` — and ids 1/2 (the Adt owners) are likewise shadowed by
`AtLeast`/`AlignTo` layout payloads. A conflated document-order collector that
descends into `layout` therefore misresolves type references: the u8
parameters of m1/m2 `add_u8` (`{"Deduplicated": 0}`) would decode against the
layout `Constant` payload and be rejected with a WRONG reason — a misattributed
fail-closed, not an honest one.

Consequence: the intern collector NEVER descends into a `layout` key (the only
measured location of layout expressions; the key name is the discriminator).
A second colliding space exists even without `layout`: Adt
`generics.trait_refs` pairs occupy the TRAIT space with overlapping numeric
ids (measured shadowing of Adt ids 1/2 in a fun_decl body — see Q11), which
is why owner resolution uses the dedicated `item_names` map rather than the
general table. A collision misresolution can only misattribute a REASON
(the shadowing payloads fall outside the closed type set, so decoding still
rejects), never fabricate a pass — but a misattributed reason is itself a
honesty defect, so any newly measured collision site gets the same
dedicated-map resolution.
The earlier axiom_rust_probe document masked this by redefining its
type-space ids (4/5/6) inside `fun_decls` AFTER `type_decls`, so the latest
definition at reference time was the type-space one — healing by accident of
document order, which the impl-probe document (struct decls + impl methods)
does not reproduce.

Resolution in code: `collectInterns` in `src/verification/llbc_to_canonical.nim`
skips the `layout` key during collection; the regression is pinned by the
fixture test that extracts m1/m2 `add_u8` with correctly-resolved u8 params.

## Q13 — `Switch` serializes branch blocks that FALL THROUGH to the parent's next statement; bool patterns are interned constants (`341` = `false`), and `&&`/`||` are `Switch`es, not `BinaryOp` [measured]

Observed 2026-11-12 (charon 0.1.281, `serde_json::read::is_escape`). A boolean
`if`/`&&`/`||` lowers to a `Switch` statement with this exact JSON shape
(`src/verification/llbc_to_canonical.nim:1066-1076`):

```json
{"kind": {"Switch": {
  "data": {"scrutinee": <operand>,
           "branches": [[<pattern>, <targetIdx>]],
           "fallback": <fallbackIdx>},
  "branches": [{"statements": [...]}, ...]}}}
```

Measured consequences:

- the `branches` inside `data` are `[pattern, targetIdx]` PAIRS; the
  top-level `branches` is the block table indexed by those targets — two
  different arrays with the same name;
- a branch block that ends without `Return` falls through to the statement
  AFTER the `Switch` in the parent block, so `Switch` is not a
  value-producing terminator;
- `Return` is a bare statement string (`"kind": "Return"`), not a
  value-producing terminator;
- bool patterns arrive as an interned constant — `{"Deduplicated": id}` or an
  inline `{"Value": [id, [{"Bool": …}, ty]]}` (the measured probe carries the
  inline form); the measured serde_json pattern id `341` is `false` (the
  `true` side is the fallback). Integer/enum pattern shapes are outside the
  closed subset;
- `&&`/`||` lower to nested `Switch`es, NEVER to `BinaryOp` — the collapse is
  the only carrier of their meaning (`:1071-1073`).

Resolution: the v1.4 collapse (`collapseBody` / `evalCollapseBlock` —
`src/verification/llbc_to_canonical.nim:1230-1430`) evaluates a block to ONE
expression, threading the fall-through continuation; a `Return` with no
return-place assignment is a POISON value that is an error only when a
reachable branch uses it. End-of-block rule: a block that assigned the return
place and then falls through to a NIL continuation returns that value; a
non-nil continuation makes the fall-through ambiguous → fail closed
(`:1388-1394`).

## Q14 — `Ty` and `TraitRef` SHARE one `Value`/`Deduplicated` id space, so a type id can be overwritten by a `TraitRef` payload; type interning registers only single-key Ty-variant payloads [measured]

Observed 2026-11-12 (charon 0.1.281, serde_json extraction). Unlike the
separate type/constant spaces of Q1 and the layout collision of Q12, `Ty` and
`TraitRef` payloads occupy the SAME `{"Value": [id, payload]}` /
`{"Deduplicated": id}` space. Measured: Ty id 83 = `Bool` and TraitRef id 83
both serialize as `{"Value": [83, …]}`. A document-order "latest definition
wins" table that does not discriminate by payload shape can register the
TraitRef payload as the type and then decode a later type reference against
the wrong definition.

Resolution: `looksLikeTyPayload` (`src/verification/llbc_to_canonical.nim:295-309`)
registers a type intern ONLY from a payload whose SINGLE key is a Ty variant —
`Scalar`, `Adt`, `TypeVar`, `Literal`, `Never`, `Ref`, `RawPtr`, `TraitType`,
`DynTrait`, `Arrow`, `Error`. TraitRef/Span/other entity payloads are never
registered as types, so "latest wins" is safe only WITHIN the Ty space.

Consequence: the same document-order intern table can carry numerically
colliding ids across entity kinds; the payload-shape discriminator — not the
id, not the traversal order — is the authority for "is this a type
definition".

---

## Registry linkage

No DEBT id is assigned: these quirks are documented-only. The parser that
encounters them is `src/verification/llbc_to_canonical.nim`, which already
carries the resolutions in code comments; the §0.5c `QUIRK(DEBT#xxx)` +
`{.axiomDebt.}` double binding attaches to code markers, and no code marker is
introduced by this change. Precedent: `docs/spec/lean_toolchain_binding_quirks.md`
Q1 is a doc-only quirk without an id. If a dedicated LLBC implementation site
gains a marker, register a `Quirk/Llbc` entry and bind it at that point.

---

## References

- `src/verification/llbc_to_canonical.nim` — the parser that resolves these quirks
- `tests/unit/test_llbc_to_canonical.nim` — real-probe + rejection-matrix coverage
- `docs/spec/rust_certified_subset.md` §2 — the closed grammar
- `docs/spec/rust_toolchain_quirks.md` — toolchain-side quirks (pin/profile/rustup shim)
- `docs/spec/rust_toolchain_quirks.md:141-155` (Q3) — Charon pin authority
  lives on the Aeneas consumer side (Q9 cross-reference)
- `docs/adr/0030-rust-subject-semantic-authority.md` D3 — rustc→LLBC is the
  Qualified/assumption boundary (Q8 cross-reference)
- Charon `docs/versioning.md` + `CONTRIBUTING.md` — the version-bump /
  dual-deserializer-check contract (Q9)
- `/tmp/axiom-rust-probe/axiom_rust_probe.llbc` — the measured 0.1.281 probe
  document behind Q7/Q8 (ephemeral workspace artifact)
- Charon manual — <https://aeneasverif.github.io/charon/manual/>
- The Cargo Book — build-script output location and absolute-path contract
  behind Q10 [documented, retrieved 2026-11-01]:
  <https://doc.rust-lang.org/cargo/reference/environment-variables.html>
  (`OUT_DIR` — "inside the build directory… unique for the package"),
  <https://doc.rust-lang.org/cargo/reference/build-scripts.html> ("Build
  scripts may save any output files or intermediate artifacts in the
  directory specified in the `OUT_DIR` environment variable"),
  <https://doc.rust-lang.org/cargo/reference/build-cache.html>
  (`<build-dir>/debug/build/` layout "internal to Cargo, and is subject to
  change"), <https://doc.rust-lang.org/cargo/reference/external-tools.html>
  (`out_dir` — "An absolute path")
- `experiments/serde-json-claim-2026-10-31/` +
  `docs/evidence/serde_json_claim_adjudication_2026-10-31.md` — the campaign
  behind Q10 (verbatim reasons, 151-entry files table, three-run
  reproduction, SCOPE_LIMIT_CONFIRMED basis)

---

| **Last update**: 2026-11-12 (Q2 superseded by the v1.4 `Switch` collapse;
Q13 measured `Switch` JSON shape; Q14 Ty/TraitRef shared id space — measured on
the serde_json `is_escape` slice)
| **Registry**: none (doc-only; see Registry linkage above)
