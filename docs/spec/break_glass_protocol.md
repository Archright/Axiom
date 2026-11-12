# Break-Glass Bypass Protocol

## Purpose

Emergency bypass for gate malfunction. When a gate (pre-commit hook or nimtry) is
blocking legitimate work due to a bug, infrastructure failure, or unexpected environment
condition, the Break-Glass protocol allows a human architect to bypass all gates with a
cryptographically signed authorization.

**This is a last resort.** Normal debugging and gate fixes should always be attempted first.

## Mechanism

Bypass requires a valid **Ed25519 signature over a TOTP-based time window**. The former
plain-env-token bypass mechanism accepted any non-empty value with no
audit trail and was **removed** (DEBT#289; see `docs/audit/theater_audit_2026-07-27.md` H5).
`AXIOM_EMERGENCY_NO_VERIFY=1` alone is **insufficient** for bypass — a valid signature is
always required (fail-closed).

Only a human architect holding the private key can authorize a bypass.

## Environment Variables

| Variable | Value | Effect |
|----------|-------|--------|
| `AXIOM_BYPASS_SIGNATURE` | 128-char hex | Ed25519 signature over `{window}\|{tree_hash}\|{reason}` |
| `AXIOM_BYPASS_PUBKEY` | 64-char hex | Ed25519 public key authorizing the bypass |
| `AXIOM_BYPASS_REASON` | string | Bypass reason (must match signing-time reason) |
| `AXIOM_EMERGENCY_NO_VERIFY` | `1`/`true` | Required flag; alone it is **not** sufficient |

### Usage

The human architect generates a signature on their own machine (private key never leaves
the architect's machine):

```bash
# 1. Generate a seed (architect, once)
ed25519 seed() > my_seed.hex

# 2. Derive public key and store separately as the AXIOM_BYPASS_PUBKEY value

# 3. Sign a reason
bin/bypass-sign "#EMERGENCY_FIX" my_seed.hex
```

Then set the output as a signature for the bypass command:

```bash
# Bypass gates (pre-commit / nimtry / hook) in the affected layer
AXIOM_EMERGENCY_NO_VERIFY=1 \
AXIOM_BYPASS_SIGNATURE=<sig> AXIOM_BYPASS_PUBKEY=<pubkey> AXIOM_BYPASS_REASON="fix: emergency hotfix" \
git commit -m "fix: emergency hotfix"
```

For agent-initiated sessions, `bin/agent-bypass-commit --reason "..." --message "..."`
handles signature wiring automatically.

## Verification

Verification lives in `src/core/trusted/bypass_verify.nim` (`verifyBypassSignature`).
It checks the signature against **both** the current and the previous 10-minute TOTP
window (`TOTPWindowSeconds = 600`) over the canonical payload
`{window}|{tree_hash}|{reason}`. The two-window check prevents boundary-condition replay
attacks.

If the signature is missing or invalid, the gate hook is **BLOCKED** (fail-closed) and
`quit(1)` is returned.

## Affected Layers

### Layer 1: Hook (pre-commit / pre-push / nimtry)

**File**: `src/gate/runners/gate_hook.nim`

When a valid signed bypass is present, the hook:
1. Skips ALL gate checks for the affected stage
2. Logs the bypass event to `.axiom/bypass_audit.jsonl`
3. Exits with code 0 (allowing the operation)

When the signature is missing or invalid, the hook logs the block reason and exits with
code 1.

## Audit Trail

All bypass events are logged to `.axiom/bypass_audit.jsonl` (JSONL format).

Each entry contains:
- `ts` — Unix timestamp of the bypass
- `reason` — bypass reason (from `AXIOM_BYPASS_REASON`)
- `pubkey` — prefix of the authorizing public key
- `window` — TOTP window in which the signature was valid
- `type` — bypass type (e.g. `"ephemeral"`)

The audit path is also consumed by downstream consumers: fail-secure reconciliation
(`gate_hook.nim` commit-msg stage), the coverage ratchet gate, and the reliability gate
(reliability score computed from bypass history).

**Reachability (2026-10-04, ADR-0028 residual ②):** the fail-secure reconciliation stage
(`src/gate/runners/gate_hook.nim:244-247`, dispatch `:463-465`) runs only for the `commit-msg`
hook, and no tracked hook installs that stage — its only would-be invoker was the
`hooks/commit-msg` stub written by the retired `nimble hooks` writer into a gitignored
directory. The canonical `.githooks` value does not change that: the tracked hook set is
`pre-commit` + `pre-push` only. Restoring the stage means adding `.githooks/commit-msg`,
which is a FROZEN surface — follow-up, not a defect introduced here.

## Security Warning

⚠️ **Bypassing gates removes integrity protections.**

- Bypass should be **rare** and **documented** — each event is recorded in the audit log.
- Only a human architect with the private key can authorize a bypass; the private key is
  never used on agent/CI machines.
- Every bypass MUST have a corresponding issue/ticket tracking the root cause.
- The bypass log should be reviewed periodically.
- A missing or invalid signature always results in a blocked (fail-closed) operation.

> Even in emergency or review-merging, the PR-checks-authoritative vs branch-push-CI-observation distinction from the [operations.md](../agents/operations.md) §Merge-Boundary Protocol still applies — bypass does not relax merge-boundary evidence rules.

## Failure of the Authorizing Key

If the architect's private key is compromised or rotated, the public key value used for
verification must be updated consistently with the signing key. Bypass authorizations
are time-windowed (10 minutes), so stale signatures cannot be replayed indefinitely.

## Restoration

After an emergency bypass:
1. Fix the root cause gate failure
2. Run `ax gate run --full-tree` to verify all gates pass
3. Review `.axiom/bypass_audit.jsonl` for the bypass event
