# axiom_rust_probe — in-repo Rust subject fixture

The Rust subject fixture for the gateway suites (`tests/gateway/
rust_subject_three_cases_test.nim`, `tests/gateway/
rust_subject_provenance_issuance_test.nim`). This tree is a byte-identical
copy of the measured probe crate (measured 2026-10-12) plus its committed
LLBC extraction — nothing here is invented; `src/lib.rs` carries the
positive/negative/out-of-scope trio exactly as measured.

## Contents

| file | role |
|---|---|
| `src/lib.rs` | the subject source (3 fns: `add_u8`, `add_u8_mutant`, `is_zero`) |
| `Cargo.toml` / `Cargo.lock` | the crate identity (name `axiom-rust-probe`, edition 2021, no dependencies) |
| `axiom_rust_probe.llbc` | the committed Charon extraction (28,818 B, JSON) |
| `axiom.specs.json` | the subject-owned spec declaration (see below) |

## Provenance

- **Measured**: 2026-10-12 (probe crate `/tmp/axiom-rust-probe/`, the
  measurement session of `feat/rust-subject-v1`).
- **Charon pin**: `0.1.281` (commit `798016509139eb51f0d764645f76d068d34ba5f6`)
  — the same pin as `PinnedCharonVersion` / `PinnedCharonPinCommit`
  (`src/verification/extraction_provenance.nim:65-70`).
- **Toolchain**: `nightly-2026-09-17` — selected by charon itself (charon
  drives rustup and caches its sysroot under
  `~/.cache/charon/miri-sysroot/nightly-2026-09-17`); the ambient default
  toolchain on PATH is irrelevant to the result.

## Fingerprints

- `src/lib.rs` sha256:
  `03f9d388111894466f3e939fe2bf3533f05a42d18662d57061ebb1aec1dce7c4`
- `axiom_rust_probe.llbc` sha256:
  `a387f2a35d18bdb7b916682556a644baacb68c221270456b66be930362508adf`
  (regenerated output verified BYTE-IDENTICAL to the measured probe LLBC —
  same sha256 — before being committed here)

## Exact regeneration command (first recorded here)

From a TEMP COPY of this crate directory (never run charon inside
`tests/fixtures/` — the run creates `target/` and would dirty the fixture
tree):

```sh
cp -r tests/fixtures/rust/axiom_rust_probe /tmp/fixture-regen && cd /tmp/fixture-regen
charon cargo        # pinned charon 0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)
```

That is the WHOLE command: `charon cargo` with no options, run from the
crate root. With all defaults it writes `./axiom_rust_probe.llbc`
(JSON serialization format, `ullbc=false`; the full recorded option set is
embedded in the file under `translated.options`). The output sha256 must
equal the LLBC fingerprint above; any divergence means the pin drifted and
the committed LLBC must be re-measured, not overwritten silently.

## axiom.specs.json — subject-owned spec declaration

`axiom.specs.json` is the subject-owned spec sidecar (what the CLI lane
reads): `post` + `conditions` per fully-qualified subject function. The
specs are stated width-uniformly over the Int domain — type-derived range
preconditions (`0 <= a`, `a < 256`, …) plus the caller overflow obligation
(`a + b < 256`) — per `docs/spec/rust_certified_subset.md` §1 (Axiom IR is
`irtBitVec64`-only; subject width is restored by range preconditions, never
by claims about 8/32-bit wraparound).

Note the mutant entry declares the SAME honest spec `result == a + b` —
that is the point of the negative control: the spec is true of `add_u8`
and VIOLATED by `add_u8_mutant` (`a + b + 1`).
