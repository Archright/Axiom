# Gate Memoization Cache Policy

## Architecture

The gate memoization system uses **Epoch-Based Cache Isolation** to manage cache lifecycle.
Instead of destructive purge (`rm -rf`), the system increments a monotonic epoch counter,
making old caches invisible through namespace isolation.

### Components

| Component | Location | Purpose |
|-----------|----------|---------|
| Epoch counter | `.axiom/cache/gate_memo/.epoch` | Monotonic integer, atomically incremented |
| Cache files | `.axiom/cache/gate_memo/epoch_{N}/{gateId}.json` | Epoch-scoped cache entries |
| Singleton cache | `gate_memo.nim` module vars | In-memory epoch value (1 file read per process) |
| Migration lock | `.axiom/cache/gate_memo/.migration_lock` | PID\|TIMESTAMP lock for flat→epoch migration |

### Cache Key Formula

```
SHA-256(Merkle(inputFiles) + SHA-256(gateSource) + SHA-256(repoRoot))
```

The epoch is NOT embedded in the hash — it determines the **namespace** (subdirectory),
not the key content. This preserves the content-addressed property while enabling
epoch-based isolation.

## Epoch Management

### Advancement

```bash
bin/gate_hook --purge-cache
# Output: [GATE] Cache epoch advanced to 1
```

This atomically increments the epoch in `.axiom/cache/gate_memo/.epoch` using
write-to-tmp + POSIX rename (crash-safe).

### Rollback

```bash
# Manually edit epoch to lower value
echo 0 > .axiom/cache/gate_memo/.epoch
```

Old epoch directories are preserved until garbage collection.

## Garbage Collection

| Parameter | Default | Location |
|-----------|---------|----------|
| `maxRetainedEpochs` | 3 | `axiom.toml` `[gate.cache]` section |

GC runs lazily after each gate batch completion. Epoch directories older than
`current_epoch - maxRetainedEpochs` are removed.

### Foreign directory guard

The memo layer can only create `epoch_<int>` directories at the current epoch
(`advanceCacheEpoch` moves the counter forward by exactly +1, and every
write goes through `saveGateMemo` with that epoch). `garbageCollectOldEpochs`
therefore enforces two additional invariants over `epoch_*` entries:

| Directory state | GC behavior |
|---|---|
| non-numeric suffix (`epoch_*` not parseable as int) | **reclaimed** — foreign garbage; the memo layer cannot produce it |
| numeric epoch **above** the current epoch | **kept + ERROR log** — foreign or the documented manual-rollback state below; removal would race a concurrent process's legitimate epoch advance |

Recurrence history: `tests/unit/gate_memo_depsdirs_test.nim` once wrote
`cast[int](epochTime())` bit-pattern epochs (see
[nim_2_2_10_stdlib_quirks.md Q-010](nim_2_2_10_stdlib_quirks.md)) leaving a
garbage epoch dir in the real cache; the test is now sandboxed and the guard
above detects the class.

Manual cleanup:
```bash
# Future: bin/axiom-cleaner --cache-gc
# Current: manual removal
rm -rf .axiom/cache/gate_memo/epoch_0/
```

## Migration from Flat Cache

On first run after upgrade, existing flat cache files (`.axiom/cache/gate_memo/{gateId}.json`)
are automatically migrated to `.axiom/cache/gate_memo/epoch_0/`.

### Migration Lock

- Lock file: `.axiom/cache/gate_memo/.migrating`
- Format: `PID|TIMESTAMP` (e.g., `12345|1718567890`)
- Stale detection: age > 60s or dead PID → force release
- Malformed lock → force release

### Migration Flow

1. Check if `epoch_0/` exists → skip if already migrated
2. Acquire lock with stale detection
3. Create `epoch_0/` subdirectory
4. Move all `{gateId}.json` files into `epoch_0/`
5. Write `.epoch` file with value `0`
6. Release lock in `finally` block

## Race Safety

| Scenario | Behavior |
|----------|----------|
| L2 parallel gates during epoch advance | Old epoch dir stays readable; new gates use new epoch |
| Multiple migration attempts | Lock serializes; second waits up to 5s |
| Lock owner crashes | Stale detection (60s TTL + PID check) → force release |
| Concurrent `--purge-cache` | Atomic moveFile ensures single-writer |

## Configuration

```toml
# axiom.toml
[gate.cache]
maxRetainedEpochs = 3
```

## Environment Variables

| Variable | Purpose |
|----------|---------|
| `AXIOM_TIMEOUT_SLA` | Gate timeout override (orthogonal to cache) |

## Related Documentation

- [docs/agents/architecture.md](../agents/architecture.md) — Gate architecture
- [docs/agents/rules_workflow.md](../agents/rules_workflow.md) — §2.8 Worktree cache behavior
- [docs/spec/nim_effect_system_quirks.md](nim_effect_system_quirks.md) — I/O boundary pragmas
