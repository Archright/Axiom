# Supply Policy Registration - Pinned Charon (2026-11-24)

> Status: Policy registration and supply provenance record for `Makefile` `provision-charon-pinned`.
> Created: 2026-11-24
> Base: `9f1915daf7566a98d48d8bd0876967bba42aab77` (`origin/main`)
> Precedent: `docs/evidence/supply_policy_registration_2026-11-19.md` (`supply-pins-libpcre3-8.39-15build1`)

## 1. Registered Supply Anchor

```yaml
tool: charon
version: "0.1.281"
commit: "798016509139eb51f0d764645f76d068d34ba5f6"
identity_string: "0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)"
rust_toolchain: "nightly-2026-09-17"
architecture: "linux-x86_64"
os_abi: "Ubuntu 24.04 (GLIBC 2.39)"
release_tag: "supply-pins-charon-0.1.281-79801650"
asset_name: "charon-0.1.281-79801650-linux-x86_64.tar.gz"
asset_bytes: 10729854
sha256: "ff5054ce03d8ad8a93f05ca2ca8971ed8968b3ce3e6d3ec4b3bdf21013d7176c"
contents: ["charon", "charon-driver"]
fallback: "source build from https://github.com/AeneasVerif/charon at 798016509139eb51f0d764645f76d068d34ba5f6"
```

## 2. Provenance & Build Recipe

The archive was produced on Ubuntu 24.04 (`GLIBC 2.39`) directly from `Makefile`'s
source recipe (`RUSTUP_TOOLCHAIN=nightly-2026-09-17 cargo build --release --locked`
against commit `798016509139eb51f0d764645f76d068d34ba5f6`), verified via
`make verify-rust-lane-live` (`guardAttempted=2 verified=0 unknown=2 error=0`,
`exit=1`), and packaged deterministically (`tar --sort=name --mtime=@1763942400 --owner=0 --group=0 --numeric-owner`)
before upload to `https://github.com/Archright/Axiom/releases/tag/supply-pins-charon-0.1.281-79801650` (10,729,854 bytes / 10.2 MiB).

Because `Archright/Axiom` has GitHub Immutable Releases enabled, the published
asset cannot be modified or overwritten after release creation. The `Makefile`
constant `CHARON_ASSET_SHA256` remains the sole trust anchor; the release URL is
a transport source, not an authority.

## 3. Why Not `actions/cache`

1. `actions/cache` shares a 10 GiB repository pool already at 8.054 GiB / 226
   entries (with ~2 GiB/day one-shot `axiom-b-*` churn).
2. Adding cache steps to `.github/workflows/axiom-operational-slice.yml` or
   `.github/actions/setup-axiom-toolchain/action.yml` alters paths inside
   `config/policy/trust_surface_manifest.json`, which App `5795152` rejects on
   `pull_request`/`merge_group` unless merged via owner break-glass.
3. Because `cargo build` output bytes are build-path dependent
   (`docs/spec/rust_toolchain_quirks.md` Q7), dynamic cache entries cannot carry
   a static SHA-256 pin in-repo; a fixed immutable asset can.

## 4. Failure & Fallback Semantics

- The `rustup` `nightly-2026-09-17` runtime toolchain (`rustc-dev`, `llvm-tools`,
  `rust-src`) is always verified/installed before fast-path or skip.
- If OS/arch != `Linux x86_64`, `CHARON_PIN_*`/`CHARON_RUST_TOOLCHAIN` diverge
  from `CHARON_ASSET_*`, download fails, `sha256sum` mismatches, extraction
  fails, or `charon version` != `CHARON_PIN_IDENTITY`, `Makefile` purges the
  asset binaries and executes the full pinned source `cargo build --release --locked`
  fallback, ending with the fail-closed `charon version` assertion.

## 5. Re-approval Triggers

Changing `CHARON_PIN_VERSION`, `CHARON_PIN_COMMIT`, `CHARON_RUST_TOOLCHAIN`, or
`CHARON_ASSET_SHA256` requires publishing a new immutable tag and updating this
registration record alongside `Makefile`.
