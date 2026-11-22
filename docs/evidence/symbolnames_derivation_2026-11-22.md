# VS-SYMBOLNAMES-DERIVE — one writer for one semantic state (2026-11-22)

> Scope: removing the persisted `symbolNames` duplicate from the topology Merkle
> cache by deriving it from `cachedSymbols[]` on load.
> Recorder is not approver: the author is an agent, the approver is the user (wintrover).
> This document records measurements and observations only. The verdict contract
> itself is owned by `docs/spec/productization_contract.md`.
> **These numbers were measured on a local 16 CPU host; they are not CI Merge Queue SLO measurements.**

## Section 0. What was duplicated

`MerkleCacheEntry` carried the same semantic state twice:

| Field | Written by | Read by |
|---|---|---|
| `cachedSymbols[i].functionName` | `topology_engine.nim:440-443` (from `syms`) | symbol reconstruction |
| `symbolNames[i]` | `topology_engine.nim:456-457` (same `syms`, same order) | `getSymbols` (`merkle_cache.nim:105`), `rebuildSymbolIndex` (`:117-122`) |

The reverse index `symbolToFiles` is built from `symbolNames`, so the duplicate
was the *read* path while `cachedSymbols` was the source. Two writers of one
semantic state can diverge; AGENTS.md section 1 forbids duplicate semantic state
("duplicate meaning state prohibited").

`getSymbols` has no caller outside the cache module and its own tests, so the
only in-product consumer of the duplicate is `rebuildSymbolIndex`.

## Section 1. Change inventory

| File | Change |
|---|---|
| `src/core/topology/merkle_cache.nim` | `entryToJson` stops writing `symbolNames`. `jsonToEntry` keeps the legacy field's shape check (reject on non-array / non-string, preserving the old corruption contract) but discards the value, then derives `entry.symbolNames` in `cachedSymbols` order |
| `tests/unit/merkle_cache_test.nim` | 4 tests: derivation equals legacy parse, legacy vs derived engine equality including `symbolToFiles`, zero-symbol files stay empty, save/load round-trip preserves order (including an overload with a repeated name) |
| `Makefile` | `TESTS_FAST_UNIT` registration |

No cache version bump: no reader requires the field, and legacy caches stay
readable. The writer no longer emits it, so a rewritten cache converges on the
new shape on the next save.

## Section 2. Order equivalence argument

`topology_engine.nim:456-457` appends `sym.functionName` for `sym in syms`, and
`cachedSymbols` is built from the same `syms` at `:440-443`. Deriving over
`cachedSymbols` therefore reproduces the exact sequence, including duplicate
names from overloads. `rebuildSymbolIndex` iterates `entry.symbolNames` and
appends the file path per occurrence, so overload duplicates produce two entries
in both shapes. The test pins this with `alpha, beta, alpha`.

## Section 3. Payload measurement (live repo cache)

Input: `.axiom/cache/topology_merkle.json`, 2,600 file entries, 16,842 symbols.

| Item | Bytes |
|---|---|
| original (with `symbolNames`) | 9,343,247 |
| rewritten through the new serializer | 8,997,325 |
| delta | **345,922 (3.70%)** |

Command: load the cache, re-save it through `saveCache`, compare `getFileSize`
(a one-off measurement harness, not committed).

## Section 4. Latency measurement (release build)

Two protocols were run on the same 9.34 MB file. Sequential single-variant
timing (best of 5, separate files) gave 197.5 ms with the field vs 217.1 ms
without: the sign flips against the expected direction, so that protocol does
not resolve a difference of this size and no claim is made from it.

The paired protocol alternates the two variants inside one process, which
cancels page-cache and allocator state:

| Batch | with `symbolNames` (median) | derived (median) | delta |
|---|---|---|---|
| n=11 | 291.03 ms | 278.74 ms | 12.29 ms |
| n=11 | 253.06 ms | 242.81 ms | 10.24 ms |
| n=15 | 260.19 ms | 251.37 ms | 8.81 ms |
| n=5 (sequential, first batch) | 236.85 ms | 231.58 ms | 5.27 ms |

Paired median gain is **9-12 ms (3.4-4.2%)** of `loadCache`, consistent with
parsing 345,922 B less JSON. Any larger figure is noise. The dominant value of
the change is still the removed divergence class, not this delta.

## Section 5. Verdict

REMOVE (duplicate semantic state) — justified by single-source-of-truth
integrity, with a measured secondary effect of 9-12 ms load time.

| Candidate | Disposition |
|---|---|
| drop persisted `symbolNames`, derive on load | REMOVE — implemented, test-pinned |
| keep `getSymbols` API | KEEP — now a pure projection, zero behavioral change |
| cache version bump | NOT_WORTH_IT — no reader depends on the field |
| expect a large latency win | NOT_SUPPORTED — paired median 9-12 ms; sequential best-of-5 is inconclusive |

## Section 6. Landing shape (ROT_ALLOWLIST)

`src/core/topology/merkle_cache.nim` is inside the trusted checker closure and
inside the rotation allowlist. `tests/unit/merkle_cache_test.nim` is a new path
and `Makefile` is outside the closure, so the two classes cannot ride one
rotation commit (the same abort documented in
`docs/evidence/ir_precompute_scope_2026-11-21.md` Section 0).

| Step | Content | Path class |
|---|---|---|
| A | `merkle_cache.nim`, `architecture_debt.json` regen, closure pin re-anchor | ROTATION (allowlisted) |
| B | regression test, `Makefile` registration, this document | NORMAL |

## Section 7. Limitations

- Two workloads were not re-measured end to end: the change is on the cache
  load path, and the measured difference there is below noise.
- `symbolNames` remains a field on the in-memory type. Only its persistence was
  removed; making it a pure function would touch every construction site.
- The 3.70% figure is for this repository snapshot; it scales with the symbol
  count, not with file count.

## Section 8. Operational acceptance at HEAD `bd7175b4` (2026-11-22)

Whole operational path, same workload for every row:

```
AXIOM_STATE_DIR=<dir> AXIOM_CI=1 ./bin/ax prove --target normalizeMaxWorkers
AXIOM_STATE_DIR=<dir> ./bin/ax report --canonical-digest
```

| Run | State | wall | prove exit | `[VERIFIED]` | canonical digest |
|---|---|---|---|---|---|
| 1 | fresh `/tmp/axA` | 4,748 ms | 0 | 1 | `d125f917…2861` |
| 2 | warm `/tmp/axA` (rerun) | 2,408 ms | 0 | 1 | `d125f917…2861` |
| 3 | fresh `/tmp/axB` (independent) | 4,758 ms | 0 | 1 | `d125f917…2861` |
| 4 | `/tmp/axL` = warm A + poisoned legacy cache | 2,400 ms | 0 | 1 | `d125f917…2861` |

Run 4 is the derivation-equivalence probe. Before the run, every entry of
`.axiom/cache/topology_merkle.json` was given a legacy `symbolNames` array
holding the file's `cachedSymbols[].functionName` **in reverse order**;
1,721 of 2,600 entries carried a poisoned value that differs from the derived
order. `jsonToEntry` shape-checks the array and ignores its contents, so the
engine, verdict, and digest are unchanged. This is direct operational evidence
that the field is inert and the projection is derived from `cachedSymbols`,
not read.

IR execution accounting was identical in all four runs:

```
pool=4/231 requests=1 required=1 executed=1 (limit=1)
```

The regression test on the same HEAD: `make test-fast-one
T=tests/unit/merkle_cache_test.nim` → 4/4 `[OK]`.

Claim boundary: the digest is a whole-tree hash that transitively includes the
`src/` tree (see `z3_lane_attribution_2026-11-22.md` Section 3), so
`d125f917…` is not comparable to the digest recorded before these source
commits. Equality is asserted only *within* one binary, across cache shapes and
independent state directories — which is exactly the R3 question this slice
raises.