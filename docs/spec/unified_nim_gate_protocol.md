# Unified Nim Gate Protocol (v11)

## Overview

Stateless HMAC-signed process-tree bypass token replacing --no-verify and disk-state sentinels.

## Token Format

```
PROVED_{treeHash}_{hmacSig}
```

- `treeHash`: Output of `git write-tree` (deterministic from index state)
- `hmacSig`: HMAC-SHA256 signature using `.axiom/signing_key`

## Verification

All hooks verify via `verifyInternalBypass()`:
1. Extract treeHash and hmacSig from token
2. Run `git write-tree` to get current tree hash
3. Compare: exact match required
4. Verify HMAC signature using `hmacVerify()` from `sync_signing.nim`
5. On failure: fall through to normal gate execution (fail-open)

## Hook Architecture

| Hook | Source Binary | Stage Detection |
|------|-------------|-----------------|
| `hooks/pre-commit` | `orchestrator_hook.nim` | `argv[0]` = "pre-commit" |
| `hooks/pre-push` | `orchestrator_hook.nim` | `argv[0]` = "pre-push" |
| `hooks/prepare-commit-msg` | `prepare_commit_msg.nim` | Git hook name |
| `hooks/commit-msg` | `gate_hook.nim` | `argv[0]` = "commit-msg" |

## Security Model

- **HMAC Key**: `.axiom/signing_key` (32-byte CSPRNG, gitignored, per-machine)
- **Trust Boundary**: Process-tree env var inheritance (putEnv → execCmd)
- **Spoofing Resistance**: Attacker needs HMAC key + exact tree hash + process-tree access
- **Fail-open**: Verification failure → normal gate execution (no deadlock)
