# axiom_u64_probe — in-repo Rust u64 boundary + width-64 `+` fixture

The Rust subject fixture for the ③ u64 boundary-type slice
(`work/u64-scalar-2026-11-02`), extended by the ① width-64 arithmetic
slice (`work/u64-add-2026-11-02`): a crate whose five functions pin the
`docs/spec/rust_certified_subset.md` §1 v1.2 row — u64 is
**boundary + discharged-obligation `+`**. Identity, params, returns and
constant operands at width 64 are certified across the full BV64 domain
(the IR literal domain is widened with an explicit two-part
representation: `litVal` int64 keeps the [−2^63, 2^63−1] canonical signed
reading; a separate u64 representation carries [2^63, 2^64−1] — values are
never silently reinterpreted), and plain width-64 `+` is admitted where
the no-overflow obligation is discharged (`lhs + rhs ≤ 18446744073709551615`,
the equivalent form of `lhs + rhs < 2^64`). This tree is a
byte-identical copy of the measured probe crate plus its committed Charon
extraction — nothing here is invented.

## Contents

| file | role |
|---|---|
| `src/lib.rs` | `u64_echo` (identity passthrough), `u64_seven` / `u64_seven_mutant` (u64 constant operands 7 / 8), `u64_add` (the width-64 `+` positive), `u64_add_mutant` (the `a + b + 1` negative control) |
| `Cargo.toml` / `Cargo.lock` | the crate identity (name `axiom_u64_probe`, edition 2021, no dependencies) |
| `axiom_u64_probe.llbc` | the committed Charon extraction (30,044 B, JSON; `u64_add` carries one AddChecked witness, `u64_add_mutant` two — `a + b + 1`) |
| `axiom.specs.json` | the declared specs: `axiom_u64_probe::u64_echo` post `result == x` (positive), `axiom_u64_probe::u64_seven_mutant` post `result == 7` (negative control — the mutant's 8 falsifies it), `axiom_u64_probe::u64_add` / `axiom_u64_probe::u64_add_mutant` post `result == a + b` (positive / negative control — the mutant's `+1` falsifies it); conditions carry the exact u64 domain and the discharged no-overflow obligation `0 <= a`, `a <= 18446744073709551615`, `0 <= b`, `b <= 18446744073709551615`, `a + b <= 18446744073709551615` |

## The five targets this fixture pins (measured in the LLBC)

- `axiom_u64_probe::u64_echo` — boundary passthrough at width 64 (span
  `src/lib.rs:1:0-3:1`); declared positive: the lane's declared path
  verifies `result == x` through the Lean kernel and mints the
  extraction-bounded certificate.
- `axiom_u64_probe::u64_seven` — a u64 constant operand (`7`); NOT
  declared in `vks_rust`: the undeclared guard attempt reports zero
  mechanical goals (a constant body has no guard obligation).
- `axiom_u64_probe::u64_seven_mutant` — the SAME shape returning `8`
  (span `src/lib.rs:9:0-11:1`); declared negative control: the falsified
  spec `result == 7` is declined by the kernel and the refuting model is
  replay-confirmed on the real rustc toolchain (status `failed`, exit 1) —
  the wire bytes differ from `u64_seven`'s (the 8-vs-7 constant operand).
- `axiom_u64_probe::u64_add` — width-64 `a + b` under the discharged
  no-overflow obligation: declared positive (v1.2). The producer's former
  fail-closed wall (the unrepresentable-obligation reason) is retired from
  the emission path — the named reason string is preserved in the source
  for regression tracking. The obligation is lowered through the existing
  overflow channel as a 65-bit zero-extend + unsigned `bvule` comparison
  (BV64-native comparison stays out: a wrapped `boAdd` cannot witness the
  mathematical overflow — the 65-bit widening is the soundness basis).
- `axiom_u64_probe::u64_add_mutant` — the SAME shape returning
  `a + b + 1` (two AddChecked witnesses in the LLBC); declared negative
  control: the spec `result == a + b` is falsified by every in-domain
  input pair (e.g. `(0,0) -> 1 != 0`), declined by the kernel, and the
  refuting model is replay-confirmed (status `failed`, exit 1).

Honest boundary notes (measured, not assumed): accepted u64 literals now
span the full domain [0, 2^64−1] via the two-part IR representation (the
former 15-digit parse cap and the int64-only replay literal domain are
widened in the same slice — a u64-domain value is never carried by
reinterpreting an int64 `litVal`, and the round-trip test matrix
(−1, 2^63−1, 2^63, 2^64−1, 2^64-reject) machine-checks the split on both
codecs). Overflow-REACHABLE inputs (a + b > 2^64−1) remain OUT OF SUBSET
per §3 — build-profile discretion; the slice proves the mathematical sum
under the discharged obligation, never wraparound. Release-profile `+`
and `wrapping_*` share the Add(Wrap) encoding and stay unadmitted
(indistinguishable at extraction).

## Provenance

- **Measured**: 2026-11-02 (probe crate `/tmp/fixture-regen-u64-add/`;
  the five-function regeneration is byte-identical across 3 runs).
- **Charon pin**: `0.1.281` (commit `798016509139eb51f0d764645f76d068d34ba5f6`)
  — the same pin as `PinnedCharonVersion` / `PinnedCharonPinCommit`
  (`src/verification/extraction_provenance.nim`).
- **Extraction profile**: DEFAULT charon flags — `charon cargo` builds
  like `cargo build`: observed `Finished \`dev\` profile [unoptimized +
  debuginfo]` (overflow-checks on → the AddChecked witness; the extraction
  environment carries no RUSTFLAGS / CARGO_PROFILE_* / RUSTC_WRAPPER —
  scrubbed). The AddChecked witness is therefore DEFAULT-FLAGS-ONLY: a
  checks-off extraction lowers plain `Add` and is rejected out-of-grammar.
- **Toolchain**: selected by charon itself (charon drives rustup and caches
  its sysroot under `~/.cache/charon/miri-sysroot/`); the ambient default
  toolchain on PATH is irrelevant to the result.

## Fingerprints

- `src/lib.rs` sha256:
  `5352659d8016e7414416e413c45b89f434f22ea3d556231a0d8f7370669dfc06`
- `axiom_u64_probe.llbc` sha256:
  `0d5bb37e32339bb4d2346930033522091fa11d5a44883cf05cc5c546a693ce88`
- `axiom.specs.json` (schemaVersion 1; keys are the FULL symbols):
  `u64_echo` post `result == x`; `u64_seven` / `u64_seven_mutant` post
  `result == 7`; `u64_add` / `u64_add_mutant` post `result == a + b`.

## Scope-lock declaration (data/verification_scope.lock)

`rust_targets` for this fixture: `axiom_u64_probe::u64_echo` (positive,
signatureHash `7274af86685a396dd1d264224aa8f8a7d117f6c0721a9762d9883ca518594179`),
`axiom_u64_probe::u64_seven_mutant` (negative control, signatureHash
`3845d9523c59b2bf38d3d130e253756a7c362118fb1130ea7b2b6aed167a3dc5`),
`axiom_u64_probe::u64_add` (positive, signatureHash
`717a7d0fa33e1537a5dc5dc59ab439ce85b711e894f03658f34255b16bceec67`) and
`axiom_u64_probe::u64_add_mutant` (negative control, signatureHash
`69382d69ecf3b01a42eb3e862b3e146751e3c8464aede90b7c57dc3e58a57eb6`);
commit `27c396a6d0b3c7da134b2df4af741b3412ba36f3` (the fixture tree hash
over the crate artifacts — README excluded, per the ③ convention),
module `tests/fixtures/rust/axiom_u64_probe/src/lib.rs`, specRef fragments
are the FULL symbols (the lane's specEntryFor validation requires the
fragment to match the declared symbol). The signatureHash convention is
the sha256 of the exact signature line (`pub` included, trailing ` {`
and newline removed).

## Exact regeneration command

From a TEMP COPY of this crate directory (never run charon inside
`tests/fixtures/` — the run creates `target/` and would dirty the fixture
tree):

```sh
cp -r tests/fixtures/rust/axiom_u64_probe /tmp/fixture-regen-u64-add && cd /tmp/fixture-regen-u64-add
charon cargo        # pinned charon 0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)
sha256sum axiom_u64_probe.llbc   # must equal the fingerprint above
```
