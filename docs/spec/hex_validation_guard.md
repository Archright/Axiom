# Hex Validation Guard

**Date:** 2026-07-10
**Module:** `src/infrastructure/gate_signing/proof_artifact_types.nim`
**Test:** `tests/cli/test_hex_validation.nim`

---

## 1. Problem

`hashValueFromHex()` in `src/core/gate/hash_types.nim` silently maps non-hex characters to `0`:

```nim
# hash_types.nim — line ~30
func hexVal(c: char): uint8 {.inline, raises: [].} =
  case c
  of '0'..'9': result = uint8(ord(c) - ord('0'))
  of 'a'..'f': result = uint8(ord(c) - ord('a') + 10)
  of 'A'..'F': result = uint8(ord(c) - ord('A') + 10)
  else: result = 0   # ← silent corruption
```

This means any invalid hex input (e.g., `"ZZZZ..."`) produces `H_VOID` (all zeros), which:

1. **Collides with `H_VOID`** — the null/unset sentinel hash for "no content"
2. **Masks data corruption** in logs and ledger state
3. **Could cause false "tree hash mismatch" or "tree hash void" errors** in prepare-commit-msg verification

### Attack Scenario

```
  git write-tree → "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
  But if git output is corrupted or badly parsed:
  → "ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ"
  → hashValueFromHex() → H_VOID (all zeros)
  → stagingTreeHash == H_VOID → false "void hash" error
  → OR: worse, collides with a legitimately-empty tree
```

---

## 2. Solution

Guard function in `src/infrastructure/gate_signing/proof_artifact_types.nim`
(`isValidHex*(s: string, expectedLen: int)`):

```nim
const HexDigits*: HexCharset = {'0'..'9', 'a'..'f'}

func isValidHex*(s: string, expectedLen: int): bool {.raises: [].} =
  ## Validate that `s` is exactly `expectedLen` lowercase hex chars.
  result = s.len == expectedLen and s.allCharsInSet(HexDigits)
```

Applied at the call site before `hashValueFromHex()`:

```nim
let stagingHash =
  if isValidHex(snap.treeHash, HashLen): hashValueFromHex(snap.treeHash)
  else: H_VOID  # safe fallback with warning log
```

### Design Rationale

| Property | Value | Reasoning |
|----------|-------|-----------|
| `{.inline.}` | Yes | Hot path in orchestrator — zero function-call overhead |
| `{.raises: [].}` | Yes | Matches hash_types.nim convention; no exceptions in hash logic |
| `s.len > 0` | First check | Empty string is the primary attack vector (produces H_VOID) |
| `all(s, isValidHexChar)` | Second check | C++ `std::all_of`-style — early exit on first non-hex char |

---

## 3. Defense Layers

```
  ┌─────────────────────────────────────────────────────────────────┐
  │ Layer 1: GitSnapshot.newGitSnapshot()                          │
  │   → strip() applied to git write-tree output                   │
  │   → Always produces valid hex from a healthy git installation  │
  ├─────────────────────────────────────────────────────────────────┤
  │ Layer 2: isValidHex guard ← THIS DOCUMENT                      │
  │   → Rejects non-hex before hashValueFromHex()                  │
  │   → Prevents silent corruption to H_VOID                       │
  ├─────────────────────────────────────────────────────────────────┤
  │ Layer 3: hashValueFromHex()                                    │
  │   → else: 0 for non-hex (unchanged, but guarded above)        │
  │   → No longer reachable with invalid input in normal flow      │
  └─────────────────────────────────────────────────────────────────┘
```

---

## 4. Test Coverage

| Test | File | What it validates |
|------|------|-------------------|
| `isValidHex` — valid strings | `tests/cli/test_hex_validation.nim` | SHA-1, SHA-256, mixed case, single chars |
| `isValidHex` — invalid strings | `tests/cli/test_hex_validation.nim` | Empty, non-hex, special chars, newlines, null bytes |
| Defense-in-depth demo | `tests/cli/test_hex_validation.nim` | Shows why `else: 0` in hashValueFromHex is dangerous |
| stagingTreeHash roundtrip | `tests/cli/test_staging_hash_record.nim` | Real git write-tree → ledger → NOT H_VOID |

---

## 5. Related Modules

| Module | Role |
|--------|------|
| `src/core/gate/hash_types.nim` | `hashValueFromHex()`, `H_VOID`, `HashValue` type |
| `src/infrastructure/gate_signing/proof_artifact_types.nim` | `isValidHex()` guard (production location) |
| `src/core/gate/state_ledger.nim` | `createLedger()` / `openLedger()` — consumes stagingTreeHash |
| `src/core/gate/state_ledger_types.nim` | `WorkspaceState.stagingTreeHash` field (v4 layout) |
