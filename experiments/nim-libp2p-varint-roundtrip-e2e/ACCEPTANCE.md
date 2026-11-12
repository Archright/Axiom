# ACCEPTANCE — nim-libp2p `getUVarint(putUVarint(v)) == v` int64 positive-range roundtrip (SPEC-LIBP2P-VARINT-RT, C5-B adoption)

> **Status**: ADOPTED · MACHINE VERDICT **UNKNOWN** — the hash-bound adoption record landed and was registry-verified (`pin=verified`); the machine judgment of the proposition itself is honestly **UNKNOWN** because no engine lane currently dispatches this document (canonical target refusal, fail-closed). This file records exactly that, per the mission's recordable-verdict contract (VALID / INVALID / UNKNOWN).
> **Run date**: 2026-10-31 (d1 putUVarint 01:32:03Z → d1 getUVarint 01:33:11Z → d2 putUVarint 01:35:32Z, KST +9)
> **Adoption authority**: Explicit user approval 2026-10-31 ("권한이 필요한 부분은 전면 허가한다") for the C5-B adoption workstream; proposition CONTENT adopted verbatim from the committed C5 varint proposal — PR #1129, merge commit `9b87ce7ca6a33aacd9fc40209d358947d2dc1965`, `experiments/nim-libp2p-bytesview-slice-e2e/PROPOSAL_C5_VARINT.md` §4 (canonicalSpecIR 3-clause form) + §7 (adoption path, subject pin, candidate SpecID).
> **Adoption record**: [`config/spec/nim_libp2p_varint_roundtrip.json`](../../../config/spec/nim_libp2p_varint_roundtrip.json) — `specId=SPEC-LIBP2P-VARINT-RT`, Axiom-owned explicit overlay, Zero-Footprint (subject tree untouched).
> **Command under judgment** (each leg COLD in its own state/vault; scope lock seeded into `<state>/data/` before the run):
> `cd <user-home>/axwt/c5b && AXIOM_STATE_DIR="$PWD/experiments/nim-libp2p-varint-roundtrip-e2e/state_d1" AXIOM_PROVE_VAULT_DIR="$PWD/experiments/nim-libp2p-varint-roundtrip-e2e/vault_d1" timeout 300 bin/ax prove --project "<workspace>/nim-libp2p" --target "libp2p/varint.nim::putUVarint" --limit 1` (→ `runs/d1.log`, **exit 2**)
> same env, `--target "libp2p/varint.nim::getUVarint"` (→ `runs/d1_getuvarint.log`, **exit 2**, reuses `state_d1`)
> same env with `state_d2`/`vault_d2`, `--target "libp2p/varint.nim::putUVarint"` (→ `runs/d2.log`, **exit 2**)
> **Build identity**: worktree `<user-home>/axwt/c5b` branch `work/c5b-adoption` · HEAD `53e49e1139a35d854946f3d7d8d4a78b37a66e31` · `bin/ax` sha256 `e279e125483eb39f1d41fdf40260bbabf0f235761633bca61d9ba239856ce2ea` · Nim 2.2.10 · Z3 4.13.3 (src/ unmodified from HEAD — build byproduct `src/generated/build_metadata.json` reverted, not part of this change)
> **Subject**: `status-im/nim-libp2p` local READ-ONLY clone `<workspace>/nim-libp2p` @ `a130a7f32219909bdcda14b7f1e64d0804fc832c`, module `libp2p/varint.nim` content sha256 `cb534bcd3af603f46b319e8f60df6539a9714dad80ed4512d24a87260ee22845` — **re-verified 2026-10-31 at acceptance time** (HEAD rev-parse + file sha256 both match the overlay pins; module porcelain-clean).

## 1. Verdict table

| question | measured | verdict |
|---|---|---|
| SpecID adoption hash matches proposal? | `printf '%s' '0 <= v\|getUVarint(putUVarint(v)) == v\|v <= 9223372036854775807\|0\|1.0.0' \| sha256sum` → `ddf7eca1151d672f963b04716c4772940e5e59b69045428b5385151d764f0607` = overlay `adoption.adoptedSpecHash` = proposal candidate SpecID (§2 below) | **YES** |
| overlay registered by the live engine? | parity line names the new entry with `pin=verified` (§3, d1.log line 3; d2.log byte-identical); parity summary `entries=7` includes `SPEC-LIBP2P-VARINT-RT` | **YES** |
| machine judgment of the proposition? | both targets resolve to **no frontier nodes** → WP4-e canonical refusal, fail-closed (§4, verbatim); exit 2 on all three legs; no claim row, no certificate | **UNKNOWN** |
| certificates produced? | `vault_d1/` and `vault_d2/` both **empty (0 files)** — nothing to verify; `ax cert verify` N/A and recorded as such (§5) | **NONE** |
| d1/d2 deterministic? | run logs **byte-identical** (§6); analysis cache **byte-identical**; scope locks **byte-identical**; merkle root identical; trajectory differs only in `ts`/`elapsedMs` (§6) | **MATCH** |
| subject untouched? | Zero-Footprint overlay only; subject HEAD + module blob sha256 match pins at acceptance time; clone porcelain-clean for `libp2p/varint.nim` | **YES** |

**Recorded judgment: UNKNOWN — adopted, registry-verified, honestly unjudged.** None of the mission's stop conditions fired: SpecID matched (registered with the exact proposal hash), registration succeeded (`pin=verified` observed on a live engine run), and `ax prove` executed (it entered the pipeline, loaded the registry, analyzed the topology, and refused the canonical target with a structured fail-closed error — an observed machine outcome, not a tooling failure).

## 2. SpecID recomputation (adoption-time hash bound)

The loader-side spec identity per the documented formula `H(sorted canonicalSpecIR | origin ordinal | ruleVersion)`:

```
$ printf '%s' '0 <= v|getUVarint(putUVarint(v)) == v|v <= 9223372036854775807|0|1.0.0' | sha256sum
ddf7eca1151d672f963b04716c4772940e5e59b69045428b5385151d764f0607  -
```

(`soExplicit` ordinal `0`; `ruleVersion` `1.0.0`; clauses sorted: `"0 <= v"` < `"getUVarint(putUVarint(v)) == v"` < `"v <= 9223372036854775807"`.)

- Overlay `adoption.adoptedSpecHash` = `ddf7eca1151d672f963b04716c4772940e5e59b69045428b5385151d764f0607` — **byte-match**.
- Proposal candidate SpecID (PR #1129, PROPOSAL_C5_VARINT.md §7, probe RUN1 SpecID row) — **byte-match**.
- Any post-adoption mutation of a clause, the ruleVersion, or the subject bytes mechanically invalidates the adoption (fail-closed, per the overlay's `adoption.provenance`).

## 3. Registry observation — registration succeeded on a live run (verbatim)

`runs/d1.log` line 3 (d2.log byte-identical, §6):

```
[WARN] axiom_engine: external subject registry parity: nim_libp2p_varint_roundtrip.json capability=body-carry precedence=10 presence=optional specId=SPEC-LIBP2P-VARINT-RT pin=verified registry-decision != chain-decision (parity finding, reported as-is)
```

- `pin=verified` is the direct observation that the engine loaded the overlay **and** verified both subject pins (commit `a130a7f3…`, module blob `cb534bcd…`) against the live subject tree — i.e. registration succeeded.
- `registry-decision != chain-decision` is the expected observation-only parity WARN for a brand-new body-carry entry with no installed chain adapter: the registry layer accepts the document, no chain lane dispatches it yet (§4). Reported as-is by the engine; not masked.
- Parity summary (d1.log line 10): `entries=7 specIds=[SPEC-LIBP2P-VARINT-RT, SPEC-B36-SIDECAR, SPEC-B36-COUT, SPEC-B36-RELATIONAL, SPEC-B32-REM-RANGE, SPEC-TOML-D2-AGENT, SPEC-LIBP2P-BV-SLICE] mismatches=1` — the single mismatch is this new entry, for the reason above.

## 4. Machine judgment — canonical refusal, fail-closed (verbatim)

`runs/d1.log` lines 14–15 (putUVarint; `runs/d1_getuvarint.log` lines 14–15 identical for getUVarint):

```
[INFO] frontier_selection: --target=libp2p/varint.nim::putUVarint not found in frontier — canonical target: NotFound (fail-closed, empty selection)
[ERROR] action_interpreter_cli: [ERROR] --target libp2p/varint.nim::putUVarint resolved to no frontier nodes (NotFound or Ambiguous). Canonical targets require exactly one match; 0 matches = NotFound, >1 = Ambiguous. Refuse to run an implicit full-frontier verification on a canonical target.
```

- Exit code **2** on all three legs (d1 putUVarint, d1 getUVarint, d2 putUVarint) — the structured refusal outcome, not a crash.
- Why the targets are not in the frontier (code-level cause, pre-established and re-confirmed here): `putUVarint`/`getUVarint` are generic (`[T: PB|LP]`) with `var` out-parameters and internal `let` bindings — the D1 β-composite synthesis scope guard (`synthesizeBase36RelationalCandidate`: exactly one referenced value parameter, no recorded bindings) declines them, and the sidecar grammar is additive-only (cannot express a roundtrip clause `getUVarint(putUVarint(v)) == v`). No engine lane dispatches this document (no installed capability adapter for its `specRelPath`), hence the symbols carry no claims and the frontier contains no such nodes.
- **This is exactly the outcome the adopted proposal predicted**: PROPOSAL_C5_VARINT.md §4/§7 state the varint lane wiring (validate+load adapter for the roundtrip grammar) is a separate implementation slice, deliberately NOT part of this adoption. The honest machine verdict for the proposition is therefore **UNKNOWN** — adoption registers the hash-bound proposition as a verification input; it does not judge it.
- Anti-theater note (§0.9): the refusal is a fail-closed *documented* path (`frontier_selection` NotFound → `action_interpreter_cli` refusal), logged at runtime, exit 2 surfaced to the caller. Nothing was forced to pass; no gate was bypassed.

## 5. Certificates — none produced (honest record)

- `vault_d1/` and `vault_d2/` are both **empty (0 files)** — the refusal happened before any claim/obligation/certificate stage.
- Therefore the existing kernel command `bin/ax cert verify [--kernel] [--project <dir>] <path>` has **nothing to verify (N/A)** and is recorded as N/A rather than simulated. No certificate digest exists for this run; the determinism evidence (§6) is the run digest record instead.

## 6. Determinism — d1 vs d2 (cold putUVarint pair)

| artifact | d1 | d2 | match |
|---|---|---|---|
| `runs/d1.log` / `runs/d2.log` | sha256 `a2700b6d409ea0f95586462a8904fd62da4bb880e47053622b50e47744c08d13` | sha256 `a2700b6d409ea0f95586462a8904fd62da4bb880e47053622b50e47744c08d13` | **byte-identical** |
| `data/verification_scope.lock` | sha256 `6d3cc33c19e8bf5aa4168cbb2ace753257d941eafbaf783dbff5f67be2abd88f` | same | **byte-identical** |
| `.axiom/cache/topology_analysis_cache.json` | sha256 `119655fbfbec60d2e9deb79e1f7a207a7782179a3cb0161751c557d75a3e2cf8` | same | **byte-identical** |
| topology merkle root | `b703c23de290fb17aa083d2afd3b9e680dfc83c945848b6b7c6bc487aa2c8568` (`sourceFileCount=473`, `totalSourceFunctions=230`) | same root, same counts | **identical** |
| topology candidates | `473 files, 4440 candidates` (log line 13) | identical (byte-identical log) | **identical** |
| exit code | 2 | 2 | **identical** |
| `logs/ax_prove_trajectory.jsonl` | 2 records (putUVarint leg + getUVarint leg sharing `state_d1`) | 1 record (putUVarint leg) | putUVarint-leg vs putUVarint-leg: **identical except `ts` (`01:32:03.509Z` vs `01:35:32.513Z`) and `elapsedMs` (`6287` vs `6411`)**; `phase`/`nodeId`/`detail`/`status` equal |

Notes.
- d1's trajectory carries a second record because the getUVarint leg re-used `state_d1` per the command contract above; the determinism comparison is putUVarint-leg vs putUVarint-leg.
- `topology_merkle.json` is not byte-equal across states (per-file `lastModified` fields) while its `merkleRoot` field is identical — expected; the content-derived analysis cache IS byte-identical.
- `topology_cli` reports `473 changed` on both cold legs (d1, d2) and `94 changed` on the warm getUVarint leg (incremental against d1's written `git_file_list.json`, which therefore exists only under `state_d1`).

## 7. File hashes (acceptance-time)

| file | sha256 |
|---|---|
| `config/spec/nim_libp2p_varint_roundtrip.json` | `7adc4aef0e59a8af316fab62df1c9780bd0e712a47b0ca40877413ea6545defb` |
| `runs/d1.log` | `a2700b6d409ea0f95586462a8904fd62da4bb880e47053622b50e47744c08d13` |
| `runs/d1_getuvarint.log` | `4361b96f1eb74fad397ceccecc3255c5eb3e520928f44cc1c3a5fd44abf00a90` |
| `runs/d2.log` | `a2700b6d409ea0f95586462a8904fd62da4bb880e47053622b50e47744c08d13` |
| `state_d1/data/verification_scope.lock` | `6d3cc33c19e8bf5aa4168cbb2ace753257d941eafbaf783dbff5f67be2abd88f` |
| `state_d2/data/verification_scope.lock` | `6d3cc33c19e8bf5aa4168cbb2ace753257d941eafbaf783dbff5f67be2abd88f` |
| `bin/ax` (judged build) | `e279e125483eb39f1d41fdf40260bbabf0f235761633bca61d9ba239856ce2ea` |

State caches (`state_d*/.axiom/`) and vaults are gitignored (local `.gitignore`: `state*/`, `vault*/`, `!runs/*.log`) and preserved on disk for inspection; the tables above pin their acceptance-time content.

## 8. Scope — what this adoption is and is not

- **Adopted**: C5-B-BASELINE only — proposition (b), the int64 positive-range (63-bit) value roundtrip `getUVarint(putUVarint(v)) == v` for `0 <= v <= 9223372036854775807`, LP dialect instance, hash-bound as SPEC-LIBP2P-VARINT-RT.
- **NOT adopted** (remain NOT_ADOPTED, per the proposal): C5-HIGH-UINT64 (defect domain `[2^63, 2^64)` — inexpressible today: int64-exceeding literals fail-closed in the grammar, proposal RUN2/RUN3/RUN4), C5-CANONICALITY (byte-range canonicality — the roundtrip clause shape would coerce `b` to an integer domain, proposal RUN7), and defect proposition (c). **C5 as a whole is NOT resolved by this record.**
- **NOT a proof**: the machine verdict is UNKNOWN (§4). Adoption records the proposition as a verification INPUT; the proposal's code-observation evidence grade is unchanged.
- **NOT a lane**: the varint validate+load wiring (capability adapter for the roundtrip grammar) is a separate follow-up implementation slice (proposal §4 capability list, §7 item 3).
- **NOT a subject modification**: Zero-Footprint — the only change is this Axiom-owned overlay + evidence; the subject clone is read-only and verified untouched (§1).
