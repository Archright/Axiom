# Rust Toolchain Quirks (Charon/Aeneas measurement)

> AGENTS.md §0.5 Quirk Mandate — discovered toolchain quirks must live in
> `docs/spec/<topic>_quirks.md` and be referenced from the quirk list
> (`docs/agents/constitution_details.md` §0.5b).
>
> **Discovered**: 2026-10-12 (Rust subject workstream `feat/rust-subject-v1`,
> Charon build measurement)
> **Class**: external Rust toolchain behavior — rustup `rust-toolchain`
> pinning and its component model, cargo, and the Charon/Aeneas pin chain.
> For the analogous Lean toolchain binding class, see
> `docs/spec/lean_toolchain_binding_quirks.md`.
>
> Tagging: **[measured]** = observed live on the cited command/build.
> **[documented]** = verified against the toolchain's declared contract or
> rustup official documentation (pin file content / doc / CHANGELOG, quoted
> verbatim).

---

## Q1 — The pinned file alone does NOT determine the installed component set: the pin omits `rustfmt` and any `profile` key, so the ambient rustup profile decides whether `cargo fmt` can run

### Symptom [measured]

Building Charon via `make build-charon-rust` fails immediately, before any
compilation, with:

```
error: 'cargo-fmt' is not installed for the toolchain 'nightly-2026-09-17-x86_64-unknown-linux-gnu'.
```

while the pinned toolchain file (`charon/rust-toolchain`) declares:

```toml
[toolchain]
channel = "nightly-2026-09-17"
components = ["rustc-dev", "llvm-tools", "rust-src", "miri"]
```

`rustfmt` is absent from the declared `components` — `cargo fmt` is provided
by that component, and the build's own Makefile invokes it. Note what the pin
does **not** contain: there is no `profile` key. As shown below, that omission
is what makes the failure environment-dependent rather than a deterministic
property of the pinned file.

### Pinned identity chain [measured]

| Element | Value |
|---|---|
| Channel | `nightly-2026-09-17` |
| Declared components | `rustc-dev`, `llvm-tools`, `rust-src`, `miri` |
| Profile key | **absent** (not declared in the pin) |
| Charon pin | `charon-pin 798016509139eb51f0d764645f76d068d34ba5f6` |
| Charon version | `charon_version 0.1.281` |

### Root cause [documented ↔ measured] — environment-profile dependence, which rustup documents as intended behavior

The pinned file under-determines the environment in three documented steps:

1. **`components` is an explicit install list; rustup installs only what is
   declared** [documented]. Automatic installation's `ensure_installed` checks
   `components_exist()` and installs just the missing declared pieces — it
   does not anticipate what build steps will invoke, and it does not fall back
   to another installed toolchain for a missing component.
2. **Whether `rustfmt` is present at all is a property of the active
   *profile*, not of the component list** [documented]. Per rustup
   `concepts/profiles.md`: `minimal` = `rustc`, `rust-std`, `cargo` ONLY;
   `default` = minimal + `rust-docs`, **`rustfmt`**, `clippy`; `complete` =
   everything (documented as "should never be used"). `rustfmt` is therefore a
   `default`-profile component.
3. **An unspecified `profile` does NOT default to `default`** [documented].
   rustup `overrides.md` §profile: *"Note that if not specified, the `default`
   profile is not necessarily used, as a different default profile might have
   been set with `rustup set profile`."* rustup 1.28.2 CHANGELOG makes this an
   intentional behavior change: *"The logic of fetching the active toolchain's
   profile has been adjusted in automatic installation. Now, when the profile
   is not specified, the profile from `rustup override set profile` will be
   chosen instead of the profile named `default`. This aligns with the
   behavior of `rustup toolchain install`."* The active profile is an
   **ambient environment setting** (`rustup set profile` / install-time
   choice), and rustup itself recommends `minimal` for CI.

Putting the three together: the same pinned file yields different installed
component sets under different ambient profiles. On a `minimal`-profile
environment — the profile rustup recommends for CI — `rustfmt` is not
installed even though pin verification succeeds, and Charon's
`build-charon-rust` Makefile target, which runs `cargo fmt` unconditionally,
fails at the first build step [measured]. The failure surface is deliberately
NOT at pin verification: rustup's contract covers the declared list, and the
profile dimension is outside the file entirely.

### Consequence for Axiom

Reproducibility requires the **conjunction of three**: (declared
`components`) × (`profile`) × (actually-installed components, **measured**).
Recording only the declared component list in provenance /
`RunnerPoolSpecDigest` (`config.nims:618-648`, fields
`os`/`arch`/`nim`/`lean`/`z3`/`system_deps`, and any future Rust extension of
it) is **insufficient**, because the same pinned file yields different builds
under different ambient profiles. This is the precise form of "the actual pin
is authoritative": the declaration is **necessary but not sufficient**. A
digest derived from the pin file alone under-reports build inputs — two
environments that both satisfy the pin but differ in profile or provisioned
components would share an identity while one builds and the other does not.
Whenever a build invocation is added to a measured composition, the component
it requires joins the recorded set (with the profile that materializes it) or
the composition fails closed.

### Resolution status

Not fixed here — the Charon repo is external. The reproducible path is to
make the environment deterministic at setup time and record the measured
result: provision the missing component for the pinned toolchain (`rustup
component add rustfmt`) **and** fix the profile explicitly (declare `profile`
where possible, or control `rustup set profile` at setup), then record the
actually-installed component set in the provenance composition. Patching the
upstream `charon/rust-toolchain` to declare `rustfmt` and a `profile` is an
upstream change, not an Axiom fix.

### Reproducible acquisition — recorded procedure (2026-10-14, feat/rust-lane-live-cli)

The Rust lane's pinned execution (`src/verification/charon_runner.nim`) makes
identity — not trust — the contract: the tool is executed only after
`charon version` matches BOTH pin components
(`PinnedCharonPinCommit`/`PinnedCharonVersion`,
`src/verification/extraction_provenance.nim:68,:73`), and the identity is
re-verified machine-side at ledger landing and at issuance re-compare. The
acquisition procedure this machine used (nightly-2026-09-17 with ALL pin
components **plus rustfmt** — the Q1 gap provisioned per the resolution
above):

1. Clone the Aeneas consumer repo (the pin authority, Q3); its `./charon-pin`
   carries `798016509139eb51f0d764645f76d068d34ba5f6`; the `charon/`
   submodule checks out at exactly that commit (`charon_version 0.1.281`).
2. `rustup toolchain install nightly-2026-09-17` + `rustup component add
   rustfmt --toolchain nightly-2026-09-17` (profile controlled at setup).
3. Build the charon binary from that checkout (upstream Makefile), then
   verify `charon version` prints `0.1.281
   (798016509139eb51f0d764645f76d068d34ba5f6)` — any other output is a
   pin mismatch and the runner refuses to run (fail-closed `crPinMismatch`).

Fixture LLBC regeneration (recorded for the first time anywhere — the
2026-10-12 probe's invocation was never committed): from a COPY of the crate
(never inside `tests/fixtures/`), `charon cargo --dest-file <abs>/subject.llbc
-- --target-dir <abs>/charon-target` with `workingDir` = crate root; output
byte-reproduced the measured probe LLBC (sha256
`a387f2a35d18bdb7b916682556a644baacb68c221270456b66be930362508adf`, 3×).
The product CLI additionally requires at runtime: `AXIOM_STATE_DIR`
(containing `data/verification_scope.lock`), `GITHUB_TOKEN` (provenance
ledger appends — content-addressed, idempotent), and `AXIOM_CHARON_BIN` when
the pinned binary is not on PATH. Binary-hash pinning of the charon
executable itself remains future hardening (not required by the pin-pair
identity mechanism).

---

## Q2 — `rust-toolchain` is a symlink to `charon/rust-toolchain`; the file name is `rust-toolchain`, and `rust-toolchain.template` does not exist

### Symptom [measured]

In the measurement checkout, the pin file is `rust-toolchain`, a symlink to
`charon/rust-toolchain` inside the Charon repo. No `rust-toolchain.template`
file exists anywhere in the chain.

### Consequence

Tooling and provenance records must reference the name `rust-toolchain` and
must follow the symlink to resolve the authoritative file content (Nim
`readFile` follows symlinks — same resolution property recorded in
`docs/spec/lean_toolchain_binding_quirks.md`). Any workflow or digest that
reads a `rust-toolchain.template` path is reading a nonexistent file; the
name to record is `rust-toolchain`.

---

## Q3 — Aeneas pins Charon via `./charon-pin` in the AENEAS repo, not in Charon itself

### Symptom [measured]

The Charon revision consumed by the measurement (`798016509139eb51f0d764645f76d068d34ba5f6`,
`charon_version 0.1.281`) is fixed by the `./charon-pin` mechanism residing
in the Aeneas repository; Charon does not carry its own consumer-facing pin
for Aeneas.

### Consequence

The authoritative Charon pin lives in the **consumer** repo (Aeneas).
Provenance chains must record `(charon-pin commit, charon_version)` as
resolved from the Aeneas side; pinning metadata read from the Charon repo
alone is not the authority for which Charon revision a build actually uses.

---

## Q4 — `findExe("rustc")` resolves the rustup shim, and executing that path runs the rustup CLI, not the compiler [measured]

`~/.cargo/bin/rustc` is a rustup **shim** (symlink to `rustup`), not the compiler
binary. Nim's `findExe` resolves it, and exec'ing the resolved path dispatches on
`argv[0]` — so the rustup CLI runs instead of `rustc`. Observed symptoms:
`rustc --version` prints the rustup banner, and a build invocation fails with
`unexpected argument '--edition'`.

**Resolution (adopted in `src/verification/rust_replay_adapter.nim`):**
- use `findExe` **only** for existence probing;
- execute and query by PATH name `rustc` (never the resolved absolute path);
- hash the **real** compiler at `<sysroot>/bin/rustc` for the toolchain
  fingerprint.

The distinction matters for provenance: the shim path is an environment artifact,
while `<sysroot>/bin/rustc` is the compiler whose identity the fingerprint must
record. Conflating them silently records a rustup invocation as a rustc identity.

See `src/verification/rust_replay_adapter.nim` (comment block near the
`rustToolchainFingerprint` implementation) and
`docs/spec/counterexample_replay_adapter.md` §3.

---

## Q5 — The replay compile profile is PINNED to the extraction profile by explicit `-C` flags; the LLBC `AddChecked`/`Assert` lowering is the structural witness, and the compiler-version difference between the two sides is recorded, not claimed absent [measured + documented]

### Discovered / implemented

2026-10-19 (`chore/rust-lane-hardening-2026-10-19`): before this change
`rustBuildCommand` compiled the replay harness with
`rustc --edition 2021 -Awarnings` and NO `-C` flags, so the match between
the replay's runtime arithmetic semantics and the extraction profile was
EMERGENT — recorded nowhere, guaranteed by nothing.

### The correspondence being pinned

The Rust counterexample lane has two rustc sides:

1. **Extraction** — Charon lowers the subject crate to LLBC under its pinned
   nightly (`nightly-2026-09-17`, Q1/Q3).
2. **Replay** — `src/verification/rust_replay_adapter.nim` compiles the
   synthesized harness with the ambient PATH rustc and executes it.

The replay's arithmetic semantics must match the extraction's: when the
extraction ran with overflow checks, an overflowing replay input must PANIC
at run time — not silently wrap into a fabricated value that masquerades as
the subject's observed result.

### Structural witness [measured]

The consumed LLBC carries `AddChecked` with
`Assert{check_kind: Overflow, on_failure: Panic}` for checked arithmetic.
That lowering is the STRUCTURAL WITNESS that the extraction rustc ran with
overflow checks enabled: an overflow-checks-off extraction lowers plain
`BinaryOp["Add"]` with no Assert, and `llbc_to_canonical.nim` rejects that
form as out-of-grammar (fail-closed). The witness is load-bearing in both
directions — the canonicalizer's grammar IS the overflow-checks-on profile
assertion, and the replay compile must now satisfy the same assertion
explicitly instead of inheriting it from ambient rustc defaults.

### Resolution — explicit profile pin [implemented 2026-10-19]

`rustBuildCommand` compiles the harness with:

```
rustc --edition 2021 -Awarnings -C overflow-checks=on -C debug-assertions=on -o <bin> <harness>
```

Edition and `-Awarnings` are unchanged; only the profile flags were added.
Why these flags remove the emergence: rustc derives `debug-assertions` from
opt-level when unset (`compiler/rustc_session/src/config.rs`:
`cg.debug_assertions.unwrap_or(opt_level == OptLevel::No)`) and overflow
checks from debug-assertions when unset — both were on only because this
invocation happens to be non-optimized. The pin makes the semantics
explicit, so future toolchain default changes or wrapper-level optimization
settings cannot silently change what the replay observes.

The replay record now folds the profile state alongside the identity:
`compileProfile` (the pinned `-C` flags), `compileCommand` (the exact
invocation), plus the toolchain identity measured by the ONE
`rustToolchainFingerprint` call that also supplies the build's rustc
dispatch token (version line, sysroot binary hash, measured component set,
channel, profile — never re-measured differently). These are internal
record fields; the PROPOSITION_DISPROVED payload surface is unchanged.

### Panic observation is classified, never confirming [implemented 2026-10-19]

A harness run that exits 101 with the Rust panic report marker
(`panicked at`) in its capture is classified as the DISTINCT lane outcome
`rroPanicked` with the verbatim report in `panicEvidence`. The
shared-vocabulary `verdict` folds to `rvUnavailable` (fail-closed for every
existing consumer), and `replayConfirmedRustDisproof` confirms a disproof
ONLY from the agree outcome — a panic NEVER confirms a disproof
(negative-control norm: counterexample evidence must be in-domain and
profile-independent). The classification is runtime-only by construction: a
compiler ICE also exits 101, but surfaces on the BUILD step as "harness
compile failed" before the panic projection can run.

### What is claimed — and what is only recorded [documented]

The CHECK-INSERTION correspondence between extraction and replay is claimed
at the PROFILE level only, and as such:

- The Rust Reference (`behavior-not-considered-unsafe.md`, "Integer
  overflow"): *"When the programmer has enabled `debug_assert!` assertions
  (for example, by enabling a non-optimized build), implementations must
  insert dynamic checks that `panic` on overflow. Other kinds of builds may
  result in `panics` or silently wrapped values on overflow, at the
  implementation's discretion."* — with *"See [RFC 560] for error
  conditions, rationale, and more details about integer overflow."* The
  operator-expressions section names the controlling flags directly:
  *"Integer operators will panic when they overflow when compiled in debug
  mode. The `-C debug-assertions` and `-C overflow-checks` compiler flags
  can be used to control this more directly."*
- The rustc book (`codegen-options/index.md`) documents the exact spellings
  used in the pin: `-C overflow-checks` and `-C debug-assertions` each
  accept `y`/`yes`/`on`/`true` (or no value) to enable, and each documents
  the default chain that made the old match emergent — overflow-checks:
  *"If not specified, overflow checks are enabled if debug-assertions are
  enabled, disabled otherwise"*; debug-assertions: *"If not specified, debug
  assertions are automatically enabled only if the opt-level is 0."*
- Extraction runs under Charon's pinned nightly; the replay executes the
  AMBIENT rustc (identity measured and recorded per run). The
  compiler-VERSION difference between the two sides is therefore RECORDED,
  NOT claimed absent: the pin asserts the check-insertion SEMANTICS at the
  profile level, not compiler equivalence.

---

## Q6 — `charon --version` is not a valid invocation; the documented version surface is the `charon version` subcommand, whose output is the semver plus the build commit hash [measured + documented]

### Discovered

2026-10-31 (serde_json claim campaign, `experiments/serde-json-claim-2026-10-31/`),
re-measured 2026-11-01. Version probing that assumes the common `--version`
flag convention fails to obtain the pin identity.

### Symptom [measured]

```
$ charon --version
error: unexpected argument '--version' found

Usage: charon <COMMAND>

For more information, try '--help'.
exit=2
$ charon version
0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)
exit=0
```

The campaign's own runs measured the same pinned identity through the
subcommand form — `charon pinned='0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)'
measured='0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)' ok=true`
(`docs/evidence/serde_json_claim_adjudication_2026-10-31.md` §5).

### Official documentation basis [documented]

Charon's `docs/versioning.md` documents ONLY the subcommand form and fixes
the output shape: *"Run `charon version` to display the current release
version and the git commit hash of the source code used to build the
binary"* — the semver (e.g. `0.1.259`) followed by the commit hash in
parentheses [retrieved via Context7 `/aeneasverif/charon`, 2026-11-01,
<https://github.com/aeneasverif/charon/blob/main/docs/versioning.md>].
What the official docs do NOT state is the absence of a `--version` flag —
that is a measured CLI property (exit 2, clap `unexpected argument` error
above), tagged [measured] here, not a documented statement.

### Operational implication

Version identity checks MUST use the subcommand form (`charon version`) and
parse `"<semver> (<40-hex commit>)"`. The pinned runner already does exactly
this (`src/verification/charon_runner.nim` — `charon version` matched against
`PinnedCharonPinCommit`/`PinnedCharonVersion`, fail-closed `crPinMismatch`;
see Q1's reproducible acquisition above and `docs/spec/rust_certified_subset.md`
§pin identity). Any new probe or digest tooling that shells `charon
--version` fails closed at exit 2 — the failure mode is loud, not silent.

---

## Registry linkage

No DEBT id is assigned for Q1–Q3: those quirks are documented-only — no code
marker or implementation site exists in this change, and the §0.5c
`QUIRK(DEBT#xxx)` + `{.axiomDebt.}` double binding attaches to code markers.
Precedent: `docs/spec/lean_toolchain_binding_quirks.md` Q1 (`staticRead`
artifacts) is a doc-only quirk without an id, while its code-bound sibling
carries `QUIRK(DEBT#427)`; `data/debt_registry.json` DEBT#435 shows the
empty-`files` pattern ("no implementation site exists, marker deferred until
implementation"). Q4 is code-adjacent (the resolution is implemented in
`src/verification/rust_replay_adapter.nim`) but carries no `axiomDebt` marker
yet; register a `Quirk/Toolchain` entry and bind the marker when a Rust
environment composition gains a dedicated implementation site (e.g. a `rust`
field in `RunnerPoolSpecDigest`). Q5 is code-adjacent like Q4 (implemented
in `src/verification/rust_replay_adapter.nim` — `RustReplayProfileFlags`,
`RustReplayOutcome`) but records a deliberate PROFILE PIN, not a defect:
no DEBT id is assigned; the same deferred `Quirk/Toolchain` registration
applies when a Rust environment composition site materializes.

---

## References

- `AGENTS.md` §0.5 (Quirk Mandate), §0.5c (debt/QUIRK marker policy)
- `docs/agents/constitution_details.md` §0.5b (quirk doc list), §0.5c (marker enforcement)
- rustup user-guide `overrides.md`, section "profile" [documented, retrieved via
  Context7 `/rust-lang/rustup`, 2026-10-12 — file `doc/user-guide` tree,
  overrides.md]: *"Note that if not specified, the `default` profile is not
  necessarily used, as a different default profile might have been set with
  `rustup set profile`."* — same guide's examples declare profile components
  explicitly, e.g. `components = [ "rustfmt", "rustc-dev" ]`
- rustup user-guide `concepts/profiles.md` [documented, same source]:
  `minimal` = `rustc`, `rust-std`, `cargo` ONLY; `default` = minimal +
  `rust-docs`, `rustfmt`, `clippy`; `complete` = everything ("should never be
  used"); `minimal` recommended for CI
- rustup CHANGELOG 1.28.2 [documented, same source]: *"The logic of fetching
  the active toolchain's profile has been adjusted in automatic installation.
  Now, when the profile is not specified, the profile from `rustup override
  set profile` will be chosen instead of the profile named `default`. This
  aligns with the behavior of `rustup toolchain install`."*
- `docs/spec/lean_toolchain_binding_quirks.md` — Lean toolchain binding precedent
- `config.nims:612-648` — `RunnerPoolSpecDigest` / `ObservedRunnerPoolDigest` canonical schema
- Rust Reference, `behavior-not-considered-unsafe.md` §"Integer overflow" +
  `expressions/operator-expr.md` §"Overflow" [documented, retrieved via
  Context7 `/rust-lang/reference`, 2026-10-19]: the debug-assertions MUST
  sentence and the `-C debug-assertions` / `-C overflow-checks` flag
  sentence quoted verbatim in Q5; RFC 560 cited there for error conditions
  and rationale
- rustc book, `codegen-options/index.md` — `-C overflow-checks` and
  `-C debug-assertions` entries [documented, retrieved via Context7
  `/rust-lang/rust`, 2026-10-19]: accepted values (`y`/`yes`/`on`/`true` or
  no value) and the emergent default chain quoted verbatim in Q5; compiler
  source `compiler/rustc_session/src/config.rs`
  (`cg.debug_assertions.unwrap_or(opt_level == OptLevel::No)`) [documented,
  same source]
- Charon `docs/versioning.md` — the `charon version` subcommand and the
  semver + commit-hash output contract (Q6) [documented, retrieved via
  Context7 `/aeneasverif/charon`, 2026-11-01,
  <https://github.com/aeneasverif/charon/blob/main/docs/versioning.md>]
- `experiments/serde-json-claim-2026-10-31/` +
  `docs/evidence/serde_json_claim_adjudication_2026-10-31.md` — the campaign
  that measured Q6 live (`charon pinned=… measured=… ok=true`)

---

| **Last update**: 2026-11-01
| **Registry**: none (doc-only; see Registry linkage above)
