# Trust-surface ratification — `compliance/provenance/license-attribution.yml` (PR #366)

- **Status**: ratification record. This document changes no policy, workflow, or ruleset.
- **Created**: 2026-11-23
- **Resolves**: issue #375
- **Landed change**: `88ddb557a54dc8572062d638482c945b0731acfe`
- **Landing merge**: `9ec39694343f34431f251e84aaf75b4c3312bd3d` (PR #366, merged 2026-11-22T09:08:50Z)
- **Pinned main at ratification**: `2bcc357abc37e2e9afcac04ecb963d96b8e52f08`

## §1. The fact being ratified

`compliance/provenance/license-attribution.yml` is a member of the admission authority
dependency closure (`config/policy/merge_admission.json` → `trustSurface`, entry 25).
Commit `88ddb557` added 8 lines to that file (license path-token attribution for the
English inventory) and landed through the normal merge-queue path, not the audited
break-glass lane.

The change is live on `main`:

```
git merge-base --is-ancestor 88ddb557a54dc8572062d638482c945b0731acfe HEAD   -> rc=0
```

This record exists because that landing left no ratification entry. It does not
re-decide the change; it makes an already-landed state explicit.

## §2. Measured evidence — why the App did not block it

`axiom-admission-verifier` (App `5795152`) published `success` for the PR head:

```
venue=pull_request
head=88ddb557a54dc8572062d638482c945b0731acfe
base=1a6a0d0dfb60c4b29ed39db2ed983ae86dd8d519
run=45004659263 attempt=1 conclusion=success
trust_surface=PASS — venue=pull_request manifest_ref=1298691 touched=4 manifest_touched=0
reasons=none
```

`manifest_touched=0` is the operative field. The App's enforced manifest and the
in-repo 39-entry `merge_admission.trustSurface` array are **not the same set**: a
change to a `trustSurface` member that is absent from the App manifest passes
`admission-check`.

The same signature appears at the merge-group venue for PR #382, whose change also
touched a 39-entry member (`src/cli/merge_cli.nim`) and still reported
`manifest_touched=0`:

```
trust_surface=PASS — venue=merge_group manifest_ref=759b873 touched=18 reasons=none
```

Two independent landings, one conclusion: the enforced blocking set is the App's
manifest, not the 39-entry array. `ADM-01` below records this as an enforcement gap,
not as a repaired condition.

## §3. Why the change is not reverted

Reverting `88ddb557` is itself a `trustSurface` edit, and it would restore the
unattributed license path tokens that the commit added — turning the license-scan
dimension red for a state that is currently accounted. A revert would therefore
re-open the very attribution gap the commit closed, and re-enter the same unenforced
surface. Neither effect is a repair.

The ratified position is: the content is accepted; the enforcement question is
separate and remains open.

## §4. Open decision (not resolved by this record)

**ADM-01 — should the 39-entry `trustSurface` be enforced by the admission App?**

- The in-repo predicate (`src/cli/merge_cli.nim`, `loadTrustSurface`) evaluates the
  39-entry array, but it does not run on the GitHub merge path (UI merge, merge queue).
- The App enforces a different, narrower manifest.
- Consequence: every `trustSurface`-only entry is advisory with respect to auto-merge.

This is a policy decision, not an implementation defect that an agent may decide.
It needs a named owner for `axiom-admission-verifier`'s accepted manifest. No such
owner is recorded anywhere in this repository, so the owner is **UNKNOWN** here.

Until that decision exists, this record neither claims the gap is closed nor treats
future `trustSurface`-only landings as ratified by precedent. Each one needs its own
entry.

## §5. What this record does not claim

- It does not claim a second, independent human approver existed.
- It does not weaken, and does not strengthen, the App manifest or the rulesets.
- It does not assert that `manifest_touched=0` is correct behaviour.
- It does not ratify any other `trustSurface`-only landing.
- It does not close ADM-01.