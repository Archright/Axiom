# FREEZE — Pre-Registration: serde_json Claim Campaign

- EXPERIMENT_ID: serde-json-claim-2026-10-31
- Written: 2026-10-31, run 2 (FREEZE pre-record), branch `docs/serde-json-claim-2026-10-31` (Axiom4). This run creates registration artifacts only: no `src/` modification, no commit; the subject is measured read-only in this run (the §7 lock protocol governs the bounded, reverted Cargo.lock placement during later prove runs).

## §0 Honesty preamble

This document is a pre-registration, not authority. Writing it grants no verification power. The authority chain: rustc/charon (extraction), Lean 4 KAA (proof admission), Z3+replay (counterexample confirmation), Axiom (artifact custody), GitHub merge queue (landing). Expected terminal: SCOPE_LIMIT_CONFIRMED (see §6) — an honest limit observation, not a failure disguised. "A failed proof is more valuable than a false Verified."

## §1 7-field identity

- PROJECT_UNDER_TEST: serde_json (Rust crate), v1.0.154, default features (no cfg override)
- REVISION: 8c535a260ce561eaab4111aafc29038eb9f77ff3 (subject HEAD, clean)
- AXIOM_REVISION: 1d94d5040da0ef96e621eae85eadba9f906d9b8c (branch base = origin/main at branch creation, "Merge pull request #1144 from Archright/work/ledger-update"); campaign branch docs/serde-json-claim-2026-10-31
- CONFIG: AXIOM_STATE_DIR / AXIOM_PROVE_VAULT_DIR per run (§7); CARGO_NET_OFFLINE=true; GITHUB_TOKEN procured via `gh auth token` (native client, §2.4)
- TOOLCHAIN_ID: Nim 2.2.10; Lean 4.33.0 (commit d8b18978322de05a8f3dba51ef03cf5461676c17); Z3 4.13.3 (64-bit); charon 0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6); rustc 1.95.0 (59807616e 2026-04-14); cargo 1.95.0 (f2d3ce0bd 2026-03-21); charon rust-toolchain nightly-2026-09-17
- SCOPE: one claim (C3 formalization on serde_json::number::<impl>::is_f64); one reception probe; judged run d1; cold reproduction d2; canonical reproduction d3 (post-landing, at the observed merge commit)
- EXPERIMENT_ID: serde-json-claim-2026-10-31

## §2 Build identity (Axiom engine)

- Build command: `make build` → `nim c --hints:off -d:allowMissingZ3 -o:bin/ax src/cli/main.nim` (measured 49 s at build time)
- `bin/ax` sha256 `6dcd7f96a89f55f4d3e0ce1b0d163cd149705891a51a59d1931d2ce5e04e483e` (git-untracked local artifact — recorded, not committed); re-verified at freeze time: match
- `bin/ax --check-provenance` → `AXIOM_PROVENANCE: OK — embedded BuildSourceHash == live src tree (-1171924972364171515)`, exit 0; re-verified at freeze time
- agent_preflight passed before/after branch switch (WARN: 46–47 functions missing {.axiomDecision.} pragma — below escalation threshold, recorded verbatim, not blocking); re-run at freeze time: exit 0, WARN 47 — verbatim: `[decision-binding] WARN: 47 function(s) missing {.axiomDecision.} pragma — escalation threshold 30 days not yet reached`
- Toolchain re-verification at freeze time: Nim 2.2.10; Lean 4.33.0 (d8b18978322de05a8f3dba51ef03cf5461676c17); `z3 --version` → `Z3 version 4.13.3 - 64 bit`; `rustc -vV` → 1.95.0, commit 59807616e1fa2540724bfbac14d7976d7e4a3860, 2026-04-14; `cargo -vV` → 1.95.0, commit f2d3ce0bd7f24a49f8f72d9000448f8838c4e850, 2026-03-21 — all match the pins above. charon measured via the `charon version` subcommand (the CLI has no `--version` flag): output `0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)`, exit 0 — matches pin. `rustup` lists installed toolchain `nightly-2026-09-17-x86_64-unknown-linux-gnu` (charon lane pin).

## §3 Subject pins (measured 2026-10-31 at freeze time)

- `git -C <workspace>/json rev-parse HEAD` → `8c535a260ce561eaab4111aafc29038eb9f77ff3` (matches expected; `git status --porcelain` empty = clean; Cargo.lock absent at freeze time)
- `git -C … rev-parse 'HEAD^{tree}'` (tree merkle) → `d0c2d891838c3c188f084bdafa0442e063b04d62`
- `git -C … rev-parse HEAD:src/number.rs` (blob OID) → `a056f9912ed0dbcc24753a0f1ca18cdba64c41d6`
- `sha256sum …/src/number.rs` → `5cf1e7e46001fd46860c906d9c353d950632af742cbb7c154049ca22d3925073`
- `sha256sum …/Cargo.toml` → `51f085a96d8951975aeef57cfa97851325d30f854a559d57de5eb2632c826d34` (manifestDigest definition: raw bytes sha256)
- claim anchor: src/number.rs:113 `pub fn is_f64(&self) -> bool` — signatureHash = sha256 of the exact signature line `pub fn is_f64(&self) -> bool` (fixture convention: no brace, no indentation, no trailing newline) = `b37d4eac6f9f3f0b16584c8277f68294259eef5d66856100b81e3663de3a0c95` (recomputed at freeze time: match; the with-newline variant hashes differently and is NOT the convention). The anchor line and the doc comment carrying the documented invariant (src/number.rs:111-112) were verified verbatim in the subject.
- LLBC target: fun_decl `serde_json::number::<impl>::is_f64` (unique by full name; lastSegment `is_f64` alone is 2-way ambiguous with `serde_json::value::<impl>::is_f64` → target must be the full name, shell-quoted)

## §4 Dependency pins

- Cargo.lock (generated in the throwaway prewarm copy by the lane's own charon command; preserved as experiment input, never committed to upstream serde_json): inputs/Cargo.lock, sha256 `1bc62b1a4645e18c7856073376f0601348f874d47a854e55261955381061b2e4`, 47 lock entries; direct deps itoa 1.0.18, memchr 2.8.3, serde_core 1.0.229, serde 1.0.229, zmij 1.0.23
  - Pin adjudication record (architect, 2026-10-31, option (a)): the campaign brief originally pinned `1bc62b1a…854a552…61b2e4`; an exhaustive lock-file sweep found no artifact with that hash, while the measured value above matches run-1's own records (discovery_inventory.md §3/§6) and is byte-identically reproduced by a fresh `cargo fetch` regeneration — the measured value is canonical. inputs/Cargo.lock verified at freeze time: sha256 match, 10,807 bytes.
- Resolution identity: cargo gives highest priority to locked versions; new compatible releases do not update a satisfying lock; yanked releases already in the lock remain usable (Cargo official semantics — Context7 verification 2026-10-31)
- Content identity: `cargo fetch` pre-warm exit 0 (2.12 s, "Locking 46 packages") — lock checksums pin downloaded bytes; all judged/repro runs set CARGO_NET_OFFLINE=true
- dependency identity claim record: inputs/dependency_table.json (canonical projection of `cargo metadata --format-version 1 --locked`; raw metadata never enters identity — absolute paths); generated at freeze time in `/tmp/axexp/serde_json_prewarm` with CARGO_NET_OFFLINE=true, exit 0, 46 packages (the lock's 47 entries include serde_json twice — workspace member + registry copy; the metadata projection lists it once), jq-verified pins: serde_json 1.0.154, itoa 1.0.18, memchr 2.8.3, serde_core 1.0.229, zmij 1.0.23
- charon extraction measured (run 1): exit 0, wall 5.86 s (120 s lane budget — 24.6× margin), max RSS ~330 MB (338,328 KB, charon_time.txt); subject.llbc 27,695,318 B, sha256 `f6eff161420fe8fefc4b2e7c5986c8fad5f3b3050cb12dc33b2881d59566f569` (NOT preserved in-repo: 27 MB binary — LFS policy; deterministically regenerable by the frozen charon command in §7); has_errors false; charon_version 0.1.281 embedded
- discovery custody (verbatim copies under discovery/, originals re-hashed at freeze time, copies byte-identical):

  | file | bytes | sha256 |
  |---|---|---|
  | discovery_inventory.md | 10,334 | `09a46109e067aa96cca40ea9b9c7140587d7c089c2bbff06dfc6bb2878f69e0a` |
  | scan_results.json | 6,185 | `6dacb9cfb99b815809c1f59b11b5fdf21564dd1a101f0c056b562b757363edca` |
  | charon_run.log | 249 | `b1a51d8540b2dfed62e0c7bffe6c838fe538bdfb02c05b67febc8d713468a6aa` |
  | charon_time.txt | 36 | `b57789693985dd790c09e25f372d84e1a83a9ba427a050f938957a1c0510d56d` |

- Per-run lock protocol (mandatory, every run that invokes charon on the subject): pre-place `cp inputs/Cargo.lock <subject>/Cargo.lock` → record sha256 → run → record sha256 (in==out required) → remove → verify find-based manifest equals pre-state. Rationale: `rust_input_contract.nim:133-137` — Cargo.lock absent is fail-closed, so the first run of a lockless subject would generate the lock from the current registry state and a later cold run could regenerate it from a different one — lockfileDigest drift would break digest-equality reproduction. Porcelain is blind to a gitignored lock; the find-based manifest is the auditor.

## §5 Candidate registry (mined contradiction candidates — C1~C8) + selected claim

Registry (verbatim from the mining record):

- C1: trailing-input completeness (deserialization stops early, trailing input accepted)
- C2: recursion limit exactly 128 (default limit value)
- C3 (refutation candidate): `is_f64` iff-claim vs arbitrary_precision divergence — witness `18446744073709551616`, number.rs:111-127
- C4 (refutation candidate, pair): default-features f64 roundtrip failure — witness `51.248178375505404` (tests/test.rs:990) vs full roundtrip under `float_roundtrip` (Cargo.toml:72-73) — configuration mutual-exclusion pair
- C5: NaN/Inf serialization success (non-finite floats serialize as null)
- C6: Map order duality (preservation vs loss)
- C7: error column lower-bound pair
- C8: overflow handling feature-monotone pair

All eight are semantic-level propositions — predicted outside the v1 certified subset (u8/u32/bool scalars, straight-line bodies, Use/BinaryOp(AddChecked, Eq) rvalues, spec grammar `result == additive`).

Dry-run inventory (scanner-derived, recorded as discovery data — NOT a lane verdict; cross-checked against discovery/scan_results.json at freeze time: counts match): 2134 fun_decls (296 null, 675 Opaque, 1 Intrinsic, 1162 Structured); strict in-grammar scan admits 13 candidates, all zero-param consts (9× u8 escape-table consts ser.rs:2135-2143; 4× bool associated consts `should_early_return_if_failed` read.rs:426/692/784/857); rejection histogram: signature_types 1148 (first offender Ref 669, Adt 423, other-scalar 26, TypeVar 21, Array 6, other 3), Switch 1; no real `fn` with u8/u32/bool params exists in the subject.

Selected claim (C3 formalization):

- P (proposition): `is_f64(n) ↔ (is_i64(n) = false ∧ is_u64(n) = false)` — the documented invariant (number.rs doc comment: "Currently this function returns true if and only if both is_i64 and is_u64 return false … not a guarantee in the future")
- D (domain): serde_json::Number values parsed from JSON number literals, under both feature configurations (default vs arbitrary_precision)
- Mined contradiction: for the witness literal `18446744073709551616` (2^64 > u64::MAX), default features store N::Float → is_f64 = true; arbitrary_precision keeps the string → is_f64 = false. The documented invariant is feature-relative — the semantics of one public API silently diverge under a cargo feature flag.
- Closed-grammar expressibility: NOT EXPRESSIBLE — requires a &self receiver (Ref — out of subset at the signature gate) and a relational/quantified spec beyond `result == additive`. The registered sidecar spec (axiom.specs.json) records the formalization-intent, predicted unreachable behind the signature gate.
- Selection rule applied: {in-subset real functions} ∩ {mined candidates} = ∅ (the 13 in-subset symbols are trivial consts, not candidate-derived) → no artificial pass-fodder claim is constructed; the campaign proceeds on the C3 formalization with the machine expected to refuse the symbol at the signature gate (honest SCOPE_LIMIT observation).

## §6 Expected outcomes & judgment tables (PRE-REGISTERED — written before any bin/ax prove run)

Expected outcomes per run:

| run | setup | predicted exit | predicted targets[0] entry |
|---|---|---|---|
| probe | undeclared target, no token, state_probe | 0 | `unknown`, reason `out-of-subset grammar (fail-closed): <producer reason — predicted signature: Ref (&self)>` |
| d1 | declared target + token, state_d1/vault_d1 | 0 | same `unknown` + out-of-subset reason; log line `ledger transport armed (live)` |
| d2 | cold (new state/vault), same command | 0 | identical entry; canonicalRunDigest identical to d1 (key-exclusion projection) |
| d3 | pinned merge-commit branch, state_d3/vault_d3 | 0 | identical entry; identical digest |

Judgment table:

| observation | mapping |
|---|---|
| exit 0 + `unknown` + out-of-subset reason (as predicted) | terminal = SCOPE_LIMIT_CONFIRMED (C1~C8 recorded as grammar-gap, run rows preserved verbatim) |
| signature unexpectedly accepted (prediction wrong) | spec decode fail-closed expected (`spec 'post' decode failed (fail-closed): …`) — recorded verbatim; subset NOT extended; STOP and re-assess honestly |
| exit 3 INVALID_INPUT (target NotFound/Ambiguous) | mechanical target-string error — fix and re-run, recorded |
| charon timeout or offline fetch failure after one retry | BLOCKED (ToolchainFailure / InfrastructureFailure — subcategory mandatory) |
| lock sha256 in≠out after a run | determinism deviation — record verbatim, one retry; persistent → reproduction criterion fails, recorded honestly |
| token procurement refused | d1 cannot run as declared-lane contract — BLOCKED (ConfigurationError) |

Freeze-time self-check: the expected-outcomes table pre-registers all four runs (probe, d1, d2, d3) with predicted exit code and predicted targets[0] entry; the judgment table maps every deviant observation class to a terminal or a declared recovery. Both tables were written before any `bin/ax prove` execution.

## §7 Frozen command sequences

CWD = Axiom4 root; EXP=experiments/serde-json-claim-2026-10-31; JSON=<workspace>/json

- charon extraction (regenerates subject.llbc; run-1 command of record, verbatim from discovery_inventory.md §4) — rerun acceptance: exit 0 and sha256 == `f6eff161420fe8fefc4b2e7c5986c8fad5f3b3050cb12dc33b2881d59566f569` (timed budget 120 s):

```
cd /tmp/axexp/serde_json_prewarm && charon cargo --dest-file /tmp/axexp/subject.llbc -- --target-dir /tmp/axexp/charon-target
```

- pre/post subject manifest (find-based — the auditor; porcelain is blind to gitignored files):

```
find $JSON -path '*/.git' -prune -o -type f -print | sort | xargs sha256sum
```

- probe:

```
mkdir -p $EXP/state_probe/data && cp data/verification_scope.lock $EXP/state_probe/data/
cp $EXP/inputs/Cargo.lock $JSON/Cargo.lock && sha256sum $JSON/Cargo.lock
AXIOM_STATE_DIR=$PWD/$EXP/state_probe CARGO_NET_OFFLINE=true bin/ax prove --project $JSON --target 'serde_json::number::<impl>::is_f64'
sha256sum $JSON/Cargo.lock && rm $JSON/Cargo.lock
find $JSON -path '*/.git' -prune -o -type f -print | sort | xargs sha256sum
```

- d1 (corrected merge form: `.rust_targets += [$e[0]]` — array-wrapped; the brief's bare `.rust_targets += $e[0]` is a jq array–object addition error, exit 5 — refuted in sandbox, corrected form re-verified at freeze time: 3 targets, vksRust 3, no (module,symbol) duplicates, 64-hex signatureHashes, field order commit/module/symbol/signatureHash/specRef/conditions preserved, baseline 2 entries byte-untouched):

```
mkdir -p $EXP/state_d1/data $EXP/vault_d1
jq --slurpfile e $EXP/inputs/verification_scope.rust_targets.json '.rust_targets += [$e[0]] | .vksRust = 3' data/verification_scope.lock > $EXP/state_d1/data/verification_scope.lock
cp $EXP/inputs/Cargo.lock $JSON/Cargo.lock && sha256sum $JSON/Cargo.lock
AXIOM_STATE_DIR=$PWD/$EXP/state_d1 AXIOM_PROVE_VAULT_DIR=$PWD/$EXP/vault_d1 CARGO_NET_OFFLINE=true GITHUB_TOKEN=$(gh auth token) bin/ax prove --project $JSON --target 'serde_json::number::<impl>::is_f64'
sha256sum $JSON/Cargo.lock && rm $JSON/Cargo.lock
find $JSON -path '*/.git' -prune -o -type f -print | sort | xargs sha256sum
```

- d2: identical to d1 with state_d2/vault_d2 (cold — no reuse of state_d1/vault_d1 artifacts)
- d3: after landing, at `git switch -c repro/serde-json-claim-2026-10-31 <mergeCommit.oid>` (named branch; `ax git sync` FORBIDDEN on it — git_cli.nim:86 would rebase the pin away); identical command with state_d3/vault_d3
- reproduction comparison procedure (d2/d3 basis): durable observable = `$EXP/state_dN/logs/ax_prove_trajectory.jsonl` (skReport sink). The skReport payload is the lane report: schemaVersion · charon{pinned,measured,ok,reason} · targets[{name,status,reason}] · summary. It carries no timestamps or paths, so for each of d1/d2/d3 extract `extra` (= the report payload) from its trajectory JSONL line — the JSONL envelope (timestamps) is excluded from comparison — and canonicalize with `jq -S .`. Three-axis comparison per run pair: (1) exit code, (2) Cargo.lock sha256 in==out, (3) canonical skReport payload byte-identity.
- NOTE: `--target` uses the FULL LLBC name (lastSegment `is_f64` is ambiguous: value + number impls); the string contains `<` `>` — shell quoting mandatory

## §8 Pre-registered deviations & fallbacks

- Cargo.lock placement is a declared, bounded, reverted subject write (P4 honesty: the subject is recorded as "declared deviation, restored", NOT "untouched"); gitignored by the subject's own .gitignore
- offline failure → record fail-closed observation, retry once ONLINE with the lock still placed (resolution stays lock-dominated; attempt pre-registered here)
- charon timeout → retry once after pre-warm; persistent → BLOCKED(ToolchainFailure)
- GITHUB_TOKEN via `gh auth token` only (§2.4 native client); refusal → BLOCKED(ConfigurationError), no alternative sourcing
- Freeze-authoring record: registration attempt 1 (2026-10-31) aborted at the §4 Cargo.lock pin check on the brief's `…854a552…` string (exit 42, nothing persisted); architect adjudication option (a) fixed the pin to the measured `…854e552…` value (see §4). No other deviations from the brief except the three registered corrections: §7 d1/d2/d3 jq merge form array-wrapped, §7 reproduction comparison procedure added, §2 charon version measured via the `charon version` subcommand.

## §9 Amendment 1 (post-probe adjudication, pre-d1)

Written 2026-10-31T20:28+09:00, run 4, BEFORE any d1 execution — the only inputs are the probe (run 3) observations. §6's expected-outcomes table and §8's judgment table above are preserved verbatim (not modified, not deleted); where they conflict with this amendment, this amendment governs (campaign brief precedence rule).

### 9.1 Probe deviation record (machine output verbatim)

probe (run 3) exited **3 INVALID_INPUT(NotFound)** against §6's predicted `exit 0 + unknown` row. stdout, all 1 line, verbatim (never summarized, never paraphrased):

```
[ERROR] action_interpreter_cli: [ERROR] [AXIOM] --target serde_json::number::<impl>::is_f64 resolved to no extraction targets (NotFound or Ambiguous). The rust lane requires exactly one match; 0 matches = NotFound, >1 = Ambiguous. Refusing an implicit verification run on an unresolved target.
```

Mechanical cause: `enumerateFunDeclNames` (src/cli/rust_lane_cli.nim:134-161) registers only all-Ident name paths; a decl whose name path contains an `Impl` segment is outside the match space (unnameable, skipped). Measured from the probe's own extraction (subject.llbc sha256 `f6eff161420fe8fefc4b2e7c5986c8fad5f3b3050cb12dc33b2881d59566f569`, regenerated-identical to §4): 2,134 fun_decls, **152 nameable** (all-Ident), nameable decls named `is_f64` = **0**. Therefore no valid target string exists for `serde_json::number::<impl>::is_f64` — the symbol is structurally unaddressable and §8's `exit 3 INVALID_INPUT … fix and re-run` row **cannot cover the 'unfixable' case** (the fix search space is the 152 nameable paths and none is that symbol). Gap closure, pre-registered here before d1: **exit 3 NotFound unfixable → the symbol is structurally unaddressable → re-select the proposition (pre-registered in §9.2 below).**

Subject reception itself was confirmed by the probe: charon extraction succeeded (`state_probe/.axiom/rust-lane/1398235db249fc8b/subject.llbc` created), lock sha256 in==out, find-based post-manifest == pre-manifest (runs/probe/).

### 9.2 Proposition re-selection: C7 formalized at `serde_json::error::parse_line_col`

The C7 (error column lower-bound pair) formalization moves from `serde_json::number::<impl>::is_f64` to `serde_json::error::parse_line_col`. Reasons: (a) the C3 symbol is unaddressable (machine observation, §9.1); (b) C7's mined property attaches directly to this single free function's returned `(line, column)` pair; (c) it is addressable — exactly 1 full-name match and lastSegment `parse_line_col` is itself unique (measured, §9.1 method); (d) the signature is explicit, so the predicted refusal reason is precise.

- P (proposition): ∀ msg: String — parse_line_col(msg) = Some((line, column)) → line ≥ 1 ∧ column ≥ 1 (error-position lower-bound pair invariant)
- D (domain): arbitrary `&mut String` messages — the function re-parses self-generated and external messages without distinction
- Mined suspicion: the lower-bound pair property is input-relative — it holds for serde_json-generated messages (1-based positions) and is NOT guaranteed for arbitrary strings (witness class: " at line 0 column 0")
- Closed-grammar expressibility: NOT EXPRESSIBLE — signature `fn parse_line_col(msg: &mut String) -> Option<(usize, usize)>` (error.rs:494) is refused at the signature gate (LLBC-measured: input = Ref(Var, Ty, Mut), output = Adt(Option tuple)); a quantified/relational spec is outside `result == additive`
- NEW expected outcomes for d1/d2/d3 (pre-recorded here, before d1 executes): exit 0 + targets[0] = `unknown` + reason `out-of-subset grammar (fail-closed): <producer reason — predicted: signature Ref input / Adt output>`; d1 log line `ledger transport armed (live)`; d2/d3 the identical entry plus the §7 three-axis comparison (① exit code ② lock in==out ③ canonical skReport payload byte-identity). Deviation handling: signature unexpectedly accepted → §8 row verbatim (`spec 'post' decode failed (fail-closed): …` expected; STOP and re-assess); offline/timeout → §8 one-retry rows; machine `reason` strings are recorded verbatim in full, never summarized.

### 9.3 Amended frozen command sequences (d1/d2/d3)

The §7 forms with ONLY the `--target` value replaced by `'serde_json::error::parse_line_col'` (full name; shell quoting mandatory). d1 (declared target + token, state_d1/vault_d1):

```
mkdir -p $EXP/state_d1/data $EXP/vault_d1
jq --slurpfile e $EXP/inputs/verification_scope.rust_targets.json '.rust_targets += [$e[0]] | .vksRust = 3' data/verification_scope.lock > $EXP/state_d1/data/verification_scope.lock
cp $EXP/inputs/Cargo.lock $JSON/Cargo.lock && sha256sum $JSON/Cargo.lock
AXIOM_STATE_DIR=$PWD/$EXP/state_d1 AXIOM_PROVE_VAULT_DIR=$PWD/$EXP/vault_d1 CARGO_NET_OFFLINE=true GITHUB_TOKEN=$(gh auth token) bin/ax prove --project $JSON --target 'serde_json::error::parse_line_col'
sha256sum $JSON/Cargo.lock && rm $JSON/Cargo.lock
find $JSON -path '*/.git' -prune -o -type f -print | sort | xargs sha256sum
```

d2: identical with state_d2/vault_d2 (cold — no reuse of state_d1/vault_d1 artifacts). d3: post-landing at the pinned merge commit with state_d3/vault_d3 (§7 d3 form).

### 9.4 Registration-file facts recorded with this amendment (before d1)

- `inputs/verification_scope.rust_targets.json` content is REPLACED with the parse_line_col entry. The previous is_f64 entry was an unused template: written at run-2 registration but consumed by no run (probe/d1/d2/d3 take the target from the command line; the state lock receives the file's content only when d1/d2/d3 state is assembled). The replacement is recorded here BEFORE d1 executes.
- `axiom.specs.json` GAINS key `serde_json::error::parse_line_col`; the existing is_f64 entry is kept (C3 record).
- signatureHash = sha256 of the exact signature line `fn parse_line_col(msg: &mut String) -> Option<(usize, usize)>` (error.rs:494; convention: no brace, no indentation, no trailing newline) = `48c4dc5b55757f7c444e8a6d0bf5fdaadd10f48791a6dea9df39484db7367851` — recomputed at amendment time: match.
