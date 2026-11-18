# ADR-0042 — Trust Epoch closure split: immutable anchors vs mutable derived closure

- Status: Accepted (2026-11-18)
- Context: DEBT#558; `config/trusted_writer_set.json`; App 5795152 trust-surface
  `blob(G) == blob(B_mg)`; ruleset 27097366

## Context

`config/trusted_writer_set.json` carries two kinds of facts with different
change semantics:

1. **Immutable trust anchors** — `trustedWriterWorkflow`,
   `trustedAdmissionWorkflowSha` (3-way with
   `config/policy/epoch_manifest.json` `productionExecutionPin` and the
   `admission-check.yml` blob).
2. **Mutable derived closure** — `trustedCheckerTreeClosure`, the
   `{mode,type,sha}` records produced by `bin/derive_checker_closure`.

The App verifies the writer-set **blob** against the merge base for all 17
protected paths. Because a closure value change (any pinned source edit)
rewrites the same blob, every ordinary source PR fails the App check and can
only land through a break-glass. The epoch gate that could distinguish value
changes from anchor changes runs only locally (pre-push), not in CI. This is
DEBT#558.

## Decision

Split the document by change semantics, without adding a new authority:

| File | Facts | Change trigger | Enforced by |
|---|---|---|---|
| `config/trusted_writer_set.json` | anchors + `pathSetDigest` | epoch rotation only | App 5795152 (blob, 17-path manifest) |
| `config/trusted_checker_closure.json` | path → {mode,type,sha} | ordinary value re-anchor | base-built `rotation_pin_anchor_check` + `merge_cli` |

The closure document keeps the root key `trustedCheckerTreeClosure` so the
existing line-set parsers and `newAnchorVerdict` consume it unchanged.

### pathSetDigest byte contract

```
domain   = "axiom.trusted-checker-closure.path-set.v1"
preimage = domain "\n" p1 "\0" p2 "\0" ... pn "\0"
digest   = domain ":" sha256Hex(preimage)
```

Paths are repo-relative POSIX paths, unique, byte-sorted. Fail-closed:
empty set, malformed line, absolute path, empty/`.`/`..` segment, duplicate
path, unknown domain, malformed hex. The single implementation is
`src/core/policy/rotation_closure_facts.nim`; re-implementing it elsewhere is
forbidden.

### Layout resolution

`resolvePinClosure(pin, closureDoc)` is the single resolution order:

- pin carries the closure key → legacy layout;
- closure document carries it → split layout;
- both → equal sets accepted (composite document), differing sets fail closed;
- neither + `pathSetDigest` present → **missing closure document fails
  closed**, never reads as genesis;
- neither + no digest → genesis (ADR-0025 §7 one-time exception).

### Authority mapping (no duplicated judgment)

- closure@H == derived(H) and digest(closure@H) == `pathSetDigest`@H:
  base-built `rotation_pin_anchor_check` at PR preflight.
- pin@B/pin@H line-set equality and candidate-delta classification:
  `merge_cli` Pass 2.75 at Merge Queue landing.
- anchors + path-set blob invariance: App 5795152.
- `epoch_transaction_gate`: local pre-push consistency only; it is not a CI
  authority.

### Self-reference exclusion

`config/trusted_checker_closure.json` MUST NOT be a member of the derived
closure. The deriver has positive-only membership (seeds, workflow command
paths, `ci/checker.mk`, transitive imports, artifact aliases), so the
document is structurally excluded; the invariant is pinned by test, not by a
new exclusion list.

## Consequences

- Membership change (adding/removing a closure path) changes `pathSetDigest`,
  which changes the App-protected writer set → requires an epoch rotation.
  This cost is accepted and must be stated in rotation evidence.
- `config/trusted_checker_closure.json` joins the runtime policy input set
  (`PolicyDigestInputPaths`), so certificates bound to the previous policy
  digest must be re-minted. The transition evidence records this.
- The transition itself cannot use the normal lane: it rewrites the
  App-protected writer set. Exactly one break-glass PR performs the split,
  updates the 3-way pin atomically, and restores the ruleset immediately.
- After the transition, an ordinary source change rewrites only the closure
  document; the writer set stays byte-identical and the App passes without
  any exception.

## Non-goals

- App verifier changes (out-of-tree).
- Proof-language / IR semantics (#547, #551).
- New required contexts or a new trust server.