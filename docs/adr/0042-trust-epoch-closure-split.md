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

### CI bootstrap: composite pin-H artifact (no dormant blob pin)

The admission orchestrator (`admission-gate-v2.yml`) runs from the PR/merge-group
commit, but its callee is pinned to `admission-check.yml@9b3d87c3a`. The
transition therefore does **not** edit `admission-check.yml` (editing it would
re-pin `trustedAdmissionWorkflowSha` + `manifest.productionExecutionPin` to a
blob that the pinned callee does not execute — a dormant pin).

Instead, the orchestrator's closure-deriver composes the `pin-H.json` artifact:
when `config/trusted_checker_closure.json` exists at H, it strips the JSONC
comments from the writer set, requires `pathSetDigest` present and
`trustedCheckerTreeClosure` absent, validates the closure-document schema, and
injects the closure records. `identity.pinHeadBlobSha` remains the original
writer-set blob. The B-pinned checker then consumes the split layout through its
existing line-set interface. The in-place fallback in the old callee has no
composite step, so an absent artifact fails closed rather than passing.

### Transition and acceptance

The transition rewrites the App-protected writer set, so it is exactly one
break-glass PR with a documented ruleset snapshot/restore. Acceptance: an
ordinary source-change PR (one existing closure member + the derived closure
document) lands through the normal Merge Queue with the App PASS and no
break-glass; independent negative controls (value-only vs path-set vs anchor
changes) are denied by their own authorities.

## Consequences

- Membership change (adding/removing a closure path) changes `pathSetDigest`,
  which changes the App-protected writer set → requires an epoch rotation.
  This cost is accepted and must be stated in rotation evidence.
- `config/trusted_checker_closure.json` joins the runtime policy input set
  (`PolicyDigestInputPaths`), so certificates bound to the previous policy
  digest must be re-minted. The transition evidence records this.
- The transition itself cannot use the normal lane: it rewrites the
  App-protected writer set. Exactly one break-glass PR performs the split and
  restores the ruleset immediately. No admission-workflow blob pin moves.
- `epoch_transaction_gate` classifies a legacy→split migration (digest appears
  with the same path set) as a trust-surface transition, not an engine-pin
  change; after the migration, a digest-only edit is again a pin change and
  requires G2a pairing.
- `epoch_transaction_gate` also treats a `trustedWriterWorkflow` change as a
  pin-value change: the writer identity is part of the same authority record,
  so a local preflight cannot silently re-bind the writer while the App still
  guards the blob.
- The scheduled `closure-watcher` consumes the split document when the writer
  set omits the inline key; a missing split document fails closed.
- After the transition, an ordinary source change rewrites only the closure
  document; the writer set stays byte-identical and the App passes without
  any exception.

## Non-goals

- App verifier changes (out-of-tree).
- Proof-language / IR semantics (#547, #551).
- New required contexts or a new trust server.