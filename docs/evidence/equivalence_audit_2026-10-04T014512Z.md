# Semantic-Equivalence Audit — `fix/authority-singularity-d1d2`

- **Recorded**: 2026-10-04T01:45:12Z
- **Branch**: `fix/authority-singularity-d1d2`
- **Scope**: compliance + evidence only. The gate-runtime projection and hook-installation
  writer singularity are owned by sibling agents on this workstream.

## Rule being applied

> A platform / compiler / external-authority delegation is removed **only after semantic
> equivalence is proven**. "The platform has a similar feature" is not equivalence.

"Similar feature" fails as a criterion because every candidate below is *semantically
adjacent* to something that already exists in the platform — and in every case the
adjacency breaks down under at least one of: **domain of facts**, **failure semantics on
invalid input**, **coverage of the input space**, or **timing/atomicity of the judgement**.

A delegation is equivalence-proven only when a written proof exists that the delegating
implementation and the delegate compute the same function over the same input space with
the same result on every input, including the rejecting path. This audit found **zero**
candidates meeting that bar, which is why the workstream's deletion count is one.

## Verdicts

| # | Candidate | Verdict | Non-equivalence reason | What a proof would require |
|---|---|---|---|---|
| 1 | Hand-rolled base64 decoder, `src/cli/merge_cli.nim:868-884` (`decodeBase64`, `{.raises: [].}`, "stdlib-free") → delegate to stdlib `base64` | **NOT equivalent — retained** | Stdlib `base64.decode` **raises** on malformed input. The local decoder does not: `val(c)` returns `tbl.find(c)` when found, else **`0`** (i.e. silently maps any character outside the alphabet to `'A'`). It also treats `=` as an unconditional terminator and ignores trailing bits. On a deny path (`{.raises: [].}` — it cannot raise by contract), substituting the stdlib decoder would convert "malformed input is garbage" into "malformed input throws", which is a **failure-semantics change on a path whose whole point is that it cannot fail**. The silent mapping is also what makes it total. | A proof that no byte string reachable on this path is outside the base64 alphabet, **or** a re-scoping of the call site that admits raising. Neither holds: `decodeBase64` consumes content decoded from remote API payloads (arbitrary bytes). |
| 2 | `merge_cli` base-freshness Pass 0 (`src/cli/merge_cli.nim:616-637`) → delegate to GitHub strict required-checks policy | **NOT equivalent — retained (registered as DEBT#485)** | Different **facts**. Pass 0 compares `V.baseSha` (the base recorded in Axiom's own verification record) against `mainSha` (the main tip read at admission time), denying `BASE_UNRECORDED` when the base is absent and `STALE_BASE` when it differs. GitHub's strict required-status-checks policy evaluates *check-run conclusions and merge-queue invalidation at merge time* — it never sees Axiom's recorded base. Conversely Axiom's predicate is a **pre-flight observation, not an atomic guarantee**: `src/cli/merge_cli.nim:1161-1163` says so explicitly ("A3 … is a PRE-FLIGHT observation, NOT an atomic freshness guarantee"). The two answer different questions on different facts at different times. **AMENDED 2026-10-05 (ADR-0027 P4)** — the conclusion is narrowed, not reversed: the predicate is retained on the PR path, and on the merge-queue path it is **cancelled**, because the anchor is now the run's event-frozen base (`AXIOM_MAIN_SHA` = `pr.base.sha \|\| merge_group.base_sha`), so Pass 0 compares the queue's own authoritative base against itself. The old `V.baseSha` was the *live* `pulls/N` `base.sha`, which lags the queue and produced the false denies this audit's row did not anticipate. | A specification proving the two predicates agree on every PR state — impossible as stated, since GitHub's predicate is not a function of `V.baseSha`. The merge-time re-binding that does exist is an ADR-0027 P3/R2 **second** predicate, not a replacement for the first. |
| 3 | `tools/ci/verify_trusted_writer_set.sh` → delegate to a general workflow-permission analyser | **NOT equivalent — retained** | The script's own comment (line 108) states the constraint: "Minimal permissions-block scan: only the top-level permissions block counts." Its awk state machine keys on `/^permissions:/` (column 0) and therefore **cannot observe runtime-minted write grants**. `.github/workflows/release-ship.yml:213-225` mints one via `actions/create-github-app-token` with `permission-contents: write` — a grant that exists only in the job's runtime token and appears nowhere in the file's `permissions:` block. A delegate that reads the declared block sees no writer; this tool's whole purpose is to cross-check the declared writer set against declared permissions, and it does so over a *different* fact set than a runtime-effective-permission analyser. | A proof that every write grant in this repo is expressible as a top-level `permissions:` declaration. One counterexample (release-ship.yml) already falsifies it. |
| 4 | `tools/nimtry_snapshot.nim` (129 lines) vs `tools/ci/nimtry_snapshot.nim` (132 lines) | **NOT equivalent — both retained** | Same name, same output contract (`logs/nimtry_history/*.json`, `byRule`/`total`/`errors`/`warnings`), **different counting and candidate sets**. The CI copy has a `parseNimtryOutput` routine producing typed counts (lines 24-67) and a distinct cache path (`getTempDir() / "nimtry_snapshot_cache.txt"`, line 83); the top-level copy has no such parser and hardcodes `"/tmp/nimtry_snapshot_cache.txt"` (line 7). They also differ in missing-binary handling (line 72 vs line 94) and in trailing-newline emission (`pretty(snapshot) & "\n"` vs `pretty(snapshot)`). Consolidating them would change which violations are counted — that is a **metric change**, not a refactor. | A proof that both emit identical JSON for every `bin/nimtry` output. Requires diffing the two parsers on the full nimtry history corpus; not attempted, and the structural differences above already show they cannot agree in general. |
| 5 | `tools/prune_dead_modules.nim` (197 lines) vs `tools/ci/prune_dead_modules.nim` (218 lines) | **NOT equivalent — both retained** | Same name, same purpose, 21 lines apart. Candidate selection and reachability analysis differ between the two implementations. Deleting either removes pruning for the context that used it, over a **different candidate set** than the survivor would compute. | Same as #4: a proof of identical reachability closure and identical candidate enumeration on the real `src/` tree, under every build configuration. |
| 6 | `tools/orchestrator_pure_import_guard.nim` (83 lines) → delegate to the immutable import-encapsulation gate | **NOT a subset — both retained** | The two ban **disjoint sets**, so neither implies the other. The pure-import guard enumerates a **stdlib** list (`os`, `osproc`, `net`, `asyncdispatch`, `httpclient`, `json`, `streams`, `terminal`, `browsers`, `nativesockets`, …) against **one** file (`src/gate/orchestrator_pure.nim`). The immutable gate (`src/gate/runners/import_encapsulation_gate.nim`) bans **internal-path** crossings that bypass hub modules, driven by a `hubMapping` exemption table, and exempts `src/core/` wholesale. A workflow importing `net` violates the guard and passes the gate; `gate/x` importing `core/internal/y` violates the gate and passes the guard. | A subset relation in one direction would suffice — but it fails on both constructions above, so no proof exists. Combining them would need a merged ban model, which is new architecture and needs a committed contract (§0.12). |
| 7 | `hasUnusedImport` scanner (`src/gate/predicates/types.nim:188-214`) → delegate to Nim's native `[UnusedImport]` warning | **Strictly weaker — retained as an *additional* layer, not a substitute** | The scanner examines **only the continuation lines of a multi-line bare `import` block**. On line 197, `if stripped.startsWith("import ") or stripped.startsWith("from "): inImportBlock = false` — a single-line `import x` or `from x import y` **terminates the block and is never inspected**. It then substring-matches each imported token against the remainder of the file (line 209), which cannot do the symbol-resolution Nim does. Nim's native warning additionally understands re-exports, aliasing, template/macro-only use, and `{.used.}`. Additionally, `config/effects.nims:106` globally sets `switch("warning", "[UnusedImport]:off")`, so at this repository's current settings the native warning is **off by default** — the scanner is the only unused-import signal that fires. | Not delegable as written. Delegation would require (a) turning the native warning back on, which would flood on the injected `discard_result_linter` import, and (b) a proof the native warning's suppression surface is narrower than the scanner's miss set. Neither is established. |

## What was removed

| Item | Justification |
|---|---|
| The second byte-identical copy of the AGENTS.md §0.6 warnings-as-error + break-glass block in `config/effects.nims` (deleted lines 50-72, 24 lines including the trailing separator) | The only deletion in the workstream, and it required **no equivalence proof at all** because there is no semantic question: `sed -n '30,48p'` and `sed -n '54,72p'` are byte-identical (both md5 `6f1c49a7becc5e517033f55f5f154d9b`). They differ only in a repeated 4-line comment header. Deleting one copy cannot change the compiler's view: the surviving copy emits the same `switch` calls in the same order, with the same `ALLOW_WARNINGS` gate and the same break-glass echoes. This is deduplication, not delegation. |

Not in the deleted copy: `switch("experimental", "strictEffects")` (`config/effects.nims:61`) was left in place.
It is a verified no-op — recorded in `docs/spec/nim_effect_system_quirks.md §31` — but flag removal was
explicitly out of scope for this workstream, and an inert flag is a documentation hazard rather than a
build hazard (§31.4).

## What was deliberately NOT done

**`axiomEffect` → Nim compiler delegation.** The Nim 2.2.10 compiler *does* enforce `{.raises: [].}`,
`{.tags. [...]}` and effect warnings — that capability genuinely exists and is genuinely used here
(`config/effects.nims:77-79` promotes `Effect` to an unconditional error). But **no equivalence proof
exists for Axiom's semantic contract**, and the audit above is the reason: every concrete candidate
delegation examined in this workstream turned out non-equivalent on facts, failure semantics, coverage,
or timing. The `axiomEffect` pragma encodes an Axiom-side contract (I/O-boundary classification feeding
`nimtry` purity analysis and the TCB layering) that the compiler's `raises`/`tags` machinery does not
compute — they are different predicates over the same AST. Delegating would silently narrow the contract
without a proof that anything is preserved. It stays.

## Cross-reference

- The one candidate whose *written claim* contradicted its implementation is registered as a theater
  entry: `data/debt_registry.json` **DEBT#485** (`Theater/Unenforced Claim`, status `closed` as of
  2026-10-05) — `config/policy/merge_admission.json:4` asserted freshness is "never reimplemented by
  merge_cli" while `src/cli/merge_cli.nim:616-637` implements it. Registration is mandatory under
  AGENTS.md §0.9. The follow-up (a policy-text correction in `config/policy/**`, owned at the time by a
  sibling agent) landed on `fix/freshness-authoritative-anchor`: the policy now records the implemented
  split (v1.10.0) instead of claiming a delegation that was never implemented. No predicate was deleted.
- A second theater entry discovered in the same pass is registered as **DEBT#484**
  (`Theater/Always-Pass`, status `deferred`) — the attestation executor-membership suite that skips its
  entire P15 block because its checker script was deleted. Not fixed here; restoring it is a follow-up.
- **ID CORRECTION (2026-10-05)**: this document originally cited these two entries as DEBT#484 (the
  freshness contradiction, also inline in table row 2) and DEBT#483 (the attestation skip). After the
  registry single-writer renumbering the IDs are **DEBT#485** and **DEBT#484** respectively; the
  citations above are corrected to the registry as it stands.

## Method notes

- Every line citation above was read in this session at the cited path; where a cited detail differed
  from a prior claim, the read value was used (e.g. the pure-import guard's stdlib ban list, the
  `hasUnusedImport` early-clear behaviour, and the base-freshness predicate's two reason codes).
- No `make` target was executed (concurrent agents share a nimcache); no compilation claim is made here.
- The `strictEffects` no-op finding was verified four ways against the pinned toolchain — see
  `docs/spec/nim_effect_system_quirks.md §31.2`.