# axiom_guard_probe — declaration-free guard-obligation probe fixture

The Rust fixture for guard-obligation proof attempts **without any subject-
owned spec declarations** (no `axiom.specs.json` — every obligation is
derived from the code guards alone, unlike `axiom_rust_probe` which carries
a spec sidecar). This tree is a byte-identical copy of the measured probe
crate (measured 2026-10-18) plus its committed LLBC extraction — nothing
here is invented; `src/lib.rs` carries the u8 straight-line family plus one
branching out-of-grammar case exactly as measured.

## Contents

| file | role |
|---|---|
| `src/lib.rs` | the subject source (4 fns: `offset`, `bump0`, `echo`, `tri`) |
| `Cargo.toml` / `Cargo.lock` | the crate identity (name `axiom_guard_probe`, edition 2021, no dependencies) |
| `axiom_guard_probe.llbc` | the committed Charon extraction (28,482 B, JSON) |

## Provenance

- **Measured**: 2026-10-18 (scratch crate `/tmp/guard-fixture/run1/`).
- **Charon pin**: `0.1.281` (commit `798016509139eb51f0d764645f76d068d34ba5f6`)
  — the same pin as `PinnedCharonVersion` / `PinnedCharonPinCommit`
  (`src/verification/extraction_provenance.nim:65-70`); verified with
  `charon version` immediately before measurement.
- **Toolchain**: `nightly-2026-09-17` — selected by charon itself (charon
  drives rustup and caches its sysroot under
  `~/.cache/charon/miri-sysroot/nightly-2026-09-17`); the ambient default
  toolchain on PATH is irrelevant to the result.

## Fingerprints

- `src/lib.rs` sha256:
  `2e83d7d47d27c6119d732ee098d289d901d2b1b2373e1123823f4780143cd445`
- `axiom_guard_probe.llbc` sha256:
  `01cb57d6c53de569100eef0d07d09e38513ce710fd9eb5cd85fd8da33ce96b41`
  (regenerated output verified BYTE-IDENTICAL across 3 fresh scratch runs —
  same sha256 — before being committed here)

## Exact regeneration command (first recorded here)

From a TEMP COPY of this crate directory (never run charon inside
`tests/fixtures/` — the run creates `target/` and would dirty the fixture
tree):

```sh
cp -r tests/fixtures/rust/axiom_guard_probe /tmp/guard-fixture-run && cd /tmp/guard-fixture-run
cargo generate-lockfile --offline   # no dependencies: resolves offline, no registry/index fetch
charon cargo                        # pinned charon 0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)
```

That is the WHOLE charon command: `charon cargo` with no options, run from
the crate root. With all defaults it writes `./axiom_guard_probe.llbc`
(JSON serialization format, `ullbc=false`; the full recorded option set is
embedded in the file under `translated.options`). The output sha256 must
equal the LLBC fingerprint above; any divergence means the pin drifted and
the committed LLBC must be re-measured, not overwritten silently.

## The four functions — expected grammar classification

| fn | source body | LLBC evidence (measured) | classification |
|---|---|---|---|
| `offset` | `a + b` | `BinaryOp ["AddChecked", Copy a, Copy b]` + `Assert {check_kind: Overflow [Add Wrap, Move a, Move b], on_failure: Panic}` | **in-grammar** — straight-line, 1 caller overflow obligation |
| `bump0` | `a + 0` | `BinaryOp ["AddChecked", Copy a, Const (U8 0)]` + same `Assert`/`Overflow`/`on_failure: Panic` shape | **in-grammar** — rustc's built MIR does NOT fold `a + 0`: the Const-0 operand and the overflow Assert both survive, so `bump0` keeps a (trivially provable) guard obligation |
| `echo` | `a` | `StorageLive` / `Assign (Copy a)` / `Return` — zero arithmetic, no `AddChecked`, no `Assert` | **in-grammar** — no obligation (no-arithmetic control) |
| `tri` | `if a == b { a } else { b }` | `BinaryOp ["Eq", Move a, Move b]` + `Switch {scrutinee: Bool, branches: [[false → 1]], fallback: 0}` | **OUT of grammar** — branching control (`Switch` terminator), no arithmetic |

Header blocks recorded from the LLBC (identical to `axiom_rust_probe`):
`charon_version: 0.1.281`, `translated.options.ullbc: false`,
`translated.options.mir: null`, `translated.options.rustc_args: []`,
`translated.target_information`: `x86_64-unknown-linux-gnu`
(pointer size 8, little-endian), `has_errors: false`.
