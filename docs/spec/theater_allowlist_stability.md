# Theater Allowlist Stability

## Purpose

Document the allowlist identity contract for `tools/ci/nim_theater_allowlist.json` and the scanner (`tools/ci/check_nim_theater.nim`), and the migration path from line-number anchors to canonical symbol anchors.

## Canonical Anchor Contract (current)

Allowlist entries are anchored by **`file + symbol + rule`** (canonical anchor per `docs/spec/canonical_contract_policy_layer.md` — Anchor: repository-relative path + symbol + semantic kind). Matching order in `isAllowlisted()`:

1. **Symbol-first**: if an entry carries a non-empty `symbol`, the scanner resolves the enclosing top-level declaration of the finding line (via `resolveSymbol`/`extractDeclName` in `check_nim_theater.nim`) and matches symbol equality + rule.
2. **Legacy fallback** — entries with an empty `symbol` fall back to the old `file + line + rule` / directory-prefix matching (backward compatibility only; the allowlist has been migrated and carries symbols on every entry).

`line` is **derived evidence only** — never identity. Line numbers remain in each entry for visual reference and legacy compatibility, but a line shift no longer deactivates or mis-anchors an exemption.

## History: Line-Offset Drift (resolved)

Previously entries were anchored by exact line number; any source edit above an allowlisted violation shifted line offsets, causing false deactivation or missed detection. This fragility is eliminated by symbol-first matching.

## Migration & Semantic Equivalence

`tools/ci/migrate_theater_allowlist.nim` migrates legacy entries to canonical anchors deterministically:

- resolves the enclosing top-level symbol for each `(file, line)` entry;
- sorts output by `(file, line, rule)` — byte-identical on repeat;
- `--verify` mode runs the legacy matcher and the canonical matcher over the full scan (`src/`, `tests/`, `tools/`) and fails (exit 1) unless both produce identical finding sets (migration golden: legacy evaluation == canonical evaluation).

## Mitigations

1. **Rescan on every full run** — violations that would no longer match their anchor are re-detected as residual findings.
2. **Pre-change baseline** — before modifying source with allowlisted symbols, run the scanner to confirm zero residual findings.
3. **Determinism** — same repository state + same allowlist ⇒ same finding set (asserted by `--verify`).

## References

- `tools/ci/nim_theater_allowlist.json` — allowlist data file (canonical anchors)
- `tools/ci/check_nim_theater.nim` — scanner (symbol-first matching)
- `tools/ci/migrate_theater_allowlist.nim` — migration + equivalence tool
- `docs/spec/canonical_contract_policy_layer.md` — Anchor contract (path + symbol + semantic kind)
- AGENTS.md §0.9 — Theater Prohibition