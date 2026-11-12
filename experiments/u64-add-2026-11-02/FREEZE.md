# FREEZE — Pre-Registration: ① width-64 arithmetic slice (u64 plain `+` admission)

- EXPERIMENT_ID: u64-add-2026-11-02
- Written: 2026-11-02 (pre-implementation: no `src/` change has landed on this branch yet — only fixture extension + scope-lock declaration + the three contract-document revisions). Branch `work/u64-add-2026-11-02`, base `ad8f6723830aeb569d1d779b75fca9fa546acf0a` (origin/main, merge of PR #1179).
- Approval basis: the approved plan `spectre-quasar-starman.md` (R1~R13 + Approach steps 1-7) doubles as the §0.12 contract-revision approval for the `rust_certified_subset.md` §1 v1.2 row.

## §0 Honesty preamble

This document is a pre-registration, not authority. Writing it grants no
verification power. The authority chain: rustc (Rust semantics), Charon
(extraction), Lean 4 KAA (proof admission), Z3 + rustc replay
(counterexample confirmation), Axiom (artifact custody), GitHub merge
queue (landing). A negative control that stays green is a slice failure;
a `verified` without the mutant's `failed` counterpart is not acceptance.

## §1 7-field identity

- PROJECT_UNDER_TEST: `axiom_u64_probe` (in-repo Rust fixture crate,
  `tests/fixtures/rust/axiom_u64_probe/`), 5 functions: `u64_echo`,
  `u64_seven`, `u64_seven_mutant`, `u64_add`, `u64_add_mutant`.
- REVISION (fixture, measured 2026-11-02): artifact tree (README excluded,
  the ③ convention) `27c396a6d0b3c7da134b2df4af741b3412ba36f3`;
  `src/lib.rs` blob `d154957b745ea8fbbdaffbde459f2bf4c1c21d38`,
  sha256 `5352659d8016e7414416e413c45b89f434f22ea3d556231a0d8f7370669dfc06`;
  `axiom_u64_probe.llbc` (30,044 B) sha256
  `0d5bb37e32339bb4d2346930033522091fa11d5a44883cf05cc5c546a693ce88`
  (regenerated in `/tmp/fixture-regen-u64-add/`, byte-identical across 3
  runs); `Cargo.toml` sha256
  `fbcca31e3977f705000430c7419ad6154cc8d3a4b0cdcfb083d9559bb38fb1ce`;
  `Cargo.lock` sha256
  `ebeac7d45e119dbbb4d6c6853298417c031f004f0117c1e4fc90ceca1f99dc09`
  (no dependencies).
- AXIOM_REVISION: branch `work/u64-add-2026-11-02` (this slice);
  base = origin/main `ad8f6723830aeb569d1d779b75fca9fa546acf0a`.
- CONFIG: `AXIOM_STATE_DIR` per run (state seeded with
  `cp data/verification_scope.lock $AXIOM_STATE_DIR/data/`);
  `AXIOM_PROVE_VAULT_DIR` per run; `AXIOM_CHARON_BIN=<user-home>/.cargo/bin/charon`;
  `CARGO_NET_OFFLINE=true` on judged/repro runs; GITHUB_TOKEN procured via
  `gh auth token` (native client). Z3 pin: seed 0, rlimit (lane defaults).
- TOOLCHAIN_ID (measured at freeze time, all match pins): Nim 2.2.10;
  Lean 4.33.0 (Lake 5.0.0-src+d8b1897); Z3 4.13.3 - 64 bit
  (`<user-home>/.local/bin/z3`); charon `0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)`
  (`charon version` subcommand); rustc 1.95.0 (59807616e 2026-04-14);
  cargo 1.95.0 (f2d3ce0bd 2026-03-21); charon-driving rustup toolchain
  `nightly-2026-09-17-x86_64-unknown-linux-gnu` (installed).
- SCOPE: one positive (`axiom_u64_probe::u64_add` — the width-64 `+`
  admission), one negative control (`axiom_u64_probe::u64_add_mutant`),
  plus the four pre-existing fixture targets as regression legs
  (`u64_echo` declared-positive, `u64_seven` undeclared, `u64_seven_mutant`
  declared-negative). Judged run d1 (pre-merge), cold reproduction
  (post-merge, at the observed merge commit), evidence closure PR.
- EXPERIMENT_ID: u64-add-2026-11-02.

## §2 R11 profile pins (the three freeze-added fields)

1. **Extraction cargo profile — DEFAULT DEV, observed**: the LLBC was
   produced by `charon cargo` (no profile flags), observed output
   `Finished `dev` profile [unoptimized + debuginfo]` — i.e. opt-level 0,
   debug-assertions on, overflow-checks on (the AddChecked witness).
   Subject `Cargo.toml` has **no `[profile]` section** (measured — the
   profile is the toolchain default, not a subject override);
   `Cargo.toml`/`Cargo.lock` digests pinned in §1. The AddChecked witness
   is therefore DEFAULT-FLAGS-ONLY: a checks-off extraction lowers plain
   `Add` and is rejected out-of-grammar (the consumption-side defense).
2. **Extraction environment — scrubbed, observed**: `RUSTFLAGS`,
   `CARGO_ENCODED_RUSTFLAGS`, `CARGO_PROFILE_*`, `RUSTC_WRAPPER` all
   ABSENT from the extraction environment (measured at freeze time:
   `env | grep -E '^(RUST|CARGO)'` empty). The contract is scrub-or-pin:
   any future run carrying any of these variables must pin and record
   them before extraction counts.
3. **Witness-producing compiler identity**: the LLBC producer is charon
   0.1.281 driving `nightly-2026-09-17` (rustup-installed, verified).
   The obligation's rustc anchor is the `checked_add` None-condition
   (std: None iff `self + rhs > u64::MAX`) — `unchecked_add`'s UB
   condition is the documented equivalent but NOT a whole-profile
   justification for plain `+`. The ambient rustc fingerprint used by
   replay (1.95.0, binary hash, channel, profile) is recorded on the
   replay record by the adapter; toolchain-identity EQUALITY is not
   claimed (the difference is recorded, never assumed away).

Already-pinned (re-recorded): charon version+commit, the CLI shape
(`charon cargo`), `translated.options` (measured: ullbc=false,
precise_drops=false, mir=null, rustc_args=[], …), the rustup toolchain,
and the replay profile flags
(`-C overflow-checks=on -C debug-assertions=on`).

## §3 Expected verdicts (pre-registered — deviations recorded verbatim, never patched)

| target | declaration | expected (post-implementation, judged run) |
|---|---|---|
| `axiom_u64_probe::u64_add` | declared (positive) | **`verified` 1/1 + certPath + irHash, exit 0** — theorem over Int with premises {type-derived full-range `0 ≤ a ≤ 2^64−1`, `0 ≤ b ≤ 2^64−1`; caller no-overflow `a + b ≤ 18446744073709551615`} proving `result == a + b` |
| `axiom_u64_probe::u64_add_mutant` | declared (negative control) | **`failed` + counterexample CONFIRMED + replay `rvDisagree`, exit 1** (in-domain refutation, e.g. the `(0,0) -> 1 ≠ 0` class; the G2 declared-lane grade) |
| `axiom_u64_probe::u64_echo` | declared (positive, regression) | `verified` + certificate (unchanged behavior; re-issued theorem now carries the full-range premise — the v1.1 "stronger theorem" caveat retires) |
| `axiom_u64_probe::u64_seven_mutant` | declared (negative control, regression) | `failed` + CONFIRMED, exit 1 (unchanged) |
| `axiom_u64_probe::u64_seven` | undeclared (regression) | `unknown`, "no derivable guard obligation" (unchanged) |
| overflow-REACHABLE input (`a + b > 2^64−1`) | — | **out-of-subset per §3** (profile discretion) — observed only as the G1/non-claiming class if reached via guard paths; NEVER a wraparound claim |
| `u64_add` pre-implementation baseline | declared, BEFORE the wall removal | `unknown` with the byte-exact wall reason (the named unrepresentable-obligation string) — the honest interim state; the string stays in source for regression tracking after the flip |

Lean gates: the positive theorem proves via `omega` on the Int domain;
`#print axioms` allowlist = {propext, Quot.sound, Classical.choice} —
`sorryAx`/native/trustCompiler must be absent.

## §4 SMT encoding (pre-registered, R13-corrected)

Width-64 overflow obligations lower through the existing overflow channel
(`annotateOverflow` → `collectOverflowGoals` → negated-query conjunct) as:
**65-bit zero-extend + unsigned `bvule`** against width-accurate constants
— `2^64−1` = `(_ bv18446744073709551615 65)`, `2^64` =
`(_ bv18446744073709551616 65)`. There is **no hex notation for 65-bit
values** (SMT-LIB hex width = 4×hex-digit count; 17 hex digits = 68 bits
= 2^65−1 — sort mismatch, Z3-verified). The signed comparison policy
(`bvslt`) does NOT apply to these goals: at p ≥ 2^63 the signed reading
falsifies the premises → vacuous emission (§0.9 hazard); the goals encode
`bvule` directly (precedent: the `bvsle`→`bvule` substitution at
`src/core/trusted/private/ir_loop_to_horn.nim:138-139`). u8/u32 encoding
is unchanged. The vacuity control: a naive BV64-native comparison NEVER
witnesses a violation (wrapped sums pass) — the negative-control mutant
must produce a refuting model and a replay-confirmed disagreement, which
the BV64-native encoding could never emit.

## §5 Round-trip test matrix (R10 — the invariant's machine check, both codecs)

| input | expected representation |
|---|---|
| −1 | signed int64 `litVal` (canonical signed reading) — round-trips as −1 |
| 2^63−1 | positive int64 `litVal` |
| 2^63 | u64-domain representation (`litU64`) — never a negative `litVal` reinterpretation |
| 2^64−1 | u64-domain maximum |
| 2^64 | **rejected** — domain violation, fail-closed |

Run on the Nim binary codec AND the Lean independent decoder (the INV-4
two-leg discipline); agreement alone is not soundness — the matrix is.

## §6 Out of scope (frozen)

`wrapping_add`/`checked_add` admission (Add(Wrap) indistinguishable;
Result/Option Certified absent), release-profile `+`,
`--reconstruct-fallible-operations` extraction contracts, `CaseBranch.pattern`
widening (stays int64 — explicit decision), spec-grammar quantifier/body
extensions, ② Ref/Adt, serde_json candidate adjudication.
