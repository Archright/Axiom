# axiom_impl_probe — in-repo Rust impl-identity fixture

The Rust subject fixture for the impl-method identity slice
(`work/impl-identity-2026-11-02`): a crate whose LLBC name paths exercise
the `Impl{Ty{kind:"InherentImplBlock", skip_binder:<type ref>}}` element
(quirk Q11) and the cross-module same-last-segment pairs that pin the
DEBT#510 ambiguity closure. This tree is a byte-identical copy of the
measured probe crate plus its committed Charon extraction — nothing here
is invented.

## Contents

| file | role |
|---|---|
| `src/lib.rs` | `free_add_u8` (wrapping_add — an honest out-of-subset Call body) + `mod m1` / `mod m2` |
| `src/m1.rs` | `Dog` + inherent impl (`new`, `speak`) + **free `add_u8`** |
| `src/m2.rs` | `Cat` + inherent impl (`new`, `speak`) + **free `add_u8`** |
| `Cargo.toml` / `Cargo.lock` | the crate identity (name `axiom_impl_probe`, edition 2021, no dependencies) |
| `axiom_impl_probe.llbc` | the committed Charon extraction (44,946 B, JSON) |

## The identity pairs this fixture pins (measured in the LLBC)

- `axiom_impl_probe::m1::add_u8` / `axiom_impl_probe::m2::add_u8` — two
  free functions sharing the last segment `add_u8` (spans
  `src/m1.rs:12:0-14:1` / `src/m2.rs:12:0-14:1`); both extractable
  straight-line `a + b` bodies. A bare `add_u8` lookup is AMBIGUOUS
  (DEBT#510); the structured names bind m1/m2 exactly.
- `axiom_impl_probe::m1::Dog::speak` / `axiom_impl_probe::m2::Cat::speak`
  (and `Dog::new` / `Cat::new`) — impl methods whose owner resolves through
  the dedicated `item_names` owner map (Q11 — vid 1 → Adt 1 `Dog`,
  vid 2 → Adt 2 `Cat`; the general intern table conflates trait-space and
  layout ids, Q12). Their bodies are honestly out-of-subset in v1 — measured
  order: the `&self` anonymous region generic fails the monomorphic gate
  FIRST, before param decoding would name the `Ref` input / `Adt` return —
  so the slice's assertion is SELECTION and IDENTITY, never a verdict.
- `core::num::<impl u8>::wrapping_add` — a scalar-owner impl (type id 0 is
  the primitive u8, not an Adt): UNADDRESSABLE by structured name
  (Q11), and the extraction carries no body (prototype).

No `axiom.specs.json` is committed: nothing in this crate is declared in
`vks_rust` — the fixture's targets run the undeclared (guard-attempt /
out-of-subset) paths by design.

## Provenance

- **Measured**: 2026-11-02 (probe crate `/tmp/axiom-impl-probe/probe/`,
  extended with the m1/m2 `add_u8` pair; the extension is part of the
  measurement, not a post-hoc edit).
- **Charon pin**: `0.1.281` (commit `798016509139eb51f0d764645f76d068d34ba5f6`)
  — the same pin as `PinnedCharonVersion` / `PinnedCharonPinCommit`
  (`src/verification/extraction_provenance.nim`).
- **Toolchain**: `nightly-2026-09-17` — selected by charon itself (charon
  drives rustup and caches its sysroot under
  `~/.cache/charon/miri-sysroot/nightly-2026-09-17`); the ambient default
  toolchain on PATH is irrelevant to the result.

## Fingerprints

- `src/lib.rs` sha256:
  `ce67bd418246c87fcca742e35b43dda2b1677dc9ffc9fabbbc59aee215705dfb`
- `src/m1.rs` sha256:
  `9c5024ad6c489bc3eba852926b6d2a0aa70df968f084a016e6715f85536319b4`
- `src/m2.rs` sha256:
  `785a0442d617f386a981a744bafc92e909c2c85a1371118798504406888e88f1`
- `axiom_impl_probe.llbc` sha256:
  `b591592865d5d9ca45d656e84e01eee759dbe45af8408fb0f24454c9c3f4a9c1`
  (regeneration verified BYTE-IDENTICAL twice from two fresh copies —
  deterministic for the pin; see the command below)

## Exact regeneration command (first recorded here)

From a TEMP COPY of this crate directory (never run charon inside
`tests/fixtures/` — the run creates `target/` and would dirty the fixture
tree):

```sh
cp -r tests/fixtures/rust/axiom_impl_probe /tmp/fixture-regen-impl && cd /tmp/fixture-regen-impl
charon cargo        # pinned charon 0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)
sha256sum axiom_impl_probe.llbc   # must equal the fingerprint above
```
