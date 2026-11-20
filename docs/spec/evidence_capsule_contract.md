# Evidence Capsule Contract — portable replay tier (SSOT)

> **Status**: Normative contract (v1, 2026-11-20; Phase 0, #188). This document realizes the
> conditional tier declared in [productization_contract.md](productization_contract.md) §1c.
> **Creates no new verdict, gate, or authority**: `proofValidity` / `reproducibility` /
> `provenanceAuthenticity` are not a new verdict enum. They are assessment axes over the
> existing `PASS | FAIL | UNKNOWN` vocabulary; the verdict producers, gates, and admission
> authorities remain those of [authority_contract.md](authority_contract.md) and
> [productization_contract.md](productization_contract.md) §2–§3.
> **Related**: [adopted_model_observation_contract.md](adopted_model_observation_contract.md),
> [direct_proof_boundary.md](direct_proof_boundary.md), [lean_sorry_gate.md](lean_sorry_gate.md),
> [provenance_contract_v3.md](provenance_contract_v3.md),
> [replay_evidence_policy.md](replay_evidence_policy.md),
> [certification_continuity_contract.md](certification_continuity_contract.md),
> [head_binding_semantics.md](head_binding_semantics.md),
> [github_artifact_attempt_quirks.md](github_artifact_attempt_quirks.md)

---

## 1. Scope

### 1.1 What a capsule is

A **portable evidence capsule** is a digest-addressed packaging of a subject's claims and
their evidence. It is replayable when the following hold:

- the replay uses only **public, digest-addressed toolchain inputs**;
- the capsule carries every producer-local artifact needed to reconstruct the claims;
- the verifier does **not** need the producer's local state directory, vault, or journal.

A capsule is therefore **portable**, not **self-contained**. It may refer to public Lean,
lake, leanchecker, and Z3 binaries by digest and version instead of embedding them. If a
referenced public input is unavailable, or its digest does not match, the affected axis is
`UNKNOWN`/`FAIL` (§6); it is never `PASS`.

The existing **local replay-bound** promise of
[productization_contract.md](productization_contract.md) §1 — `(cert + trusted journal +
claims/solver + source repo)` — remains the default and is unchanged for every flow that does
not opt into the capsule tier. A capsule is an **additional packaging tier**, not a
replacement for that promise.

### 1.2 What this contract does not do

- It does not add or change a CLI surface, verdict producer, gate, or execution authority.
- It does not add a CI gate or admission check: the capsule verifier is a consumer-side
  procedure, and its output does not replace existing gates or authorities.
- It does not widen the certified subset, the direct-proof boundary, or any subject scope.
- It does not replace the certificate contract: certificate bodies retain their existing
  canonical bytes and identity under [provenance_contract_v3.md](provenance_contract_v3.md) §6.
- It does not define a parallel certificate-set producer. The admission evidence export
  contract (Archright/Axiom PR #234) defines `ax cert export` / `ax cert verify-export`, the
  `axiom.admission.vault-manifest.v3` inventory, and `certificateSetDigest`. A capsule
  consumes that export as its certificate-set member; it does not re-export certificate bytes
  through a second producer.
- It does not turn a capsule into a self-contained certification, an independent kernel, an
  independent solver, an authentication credential, or an audit ledger (§7).

---

## 2. Three separate axes

Every capsule assessment uses three axes. They are **not mergeable** into one score or one
boolean, and no axis substitutes for another:

| Axis | Question it answers | Primary evidence |
|---|---|---|
| `proofValidity` | Does the Lean kernel accept the claimed theorem, and does the theorem/olean/axiom observation match the claimed proposition? | Lean kernel acceptance; `leanchecker` replay (plain mandatory, `--fresh` deep mode); `#print axioms` observation; theorem identity; `modelBinding` |
| `reproducibility` | In a fresh process, with the same pinned inputs/toolchain/options, does the same verdict recur? | fresh-process replay records; pinned toolchain digests; canonical comparison |
| `provenanceAuthenticity` | Is the capsule bound to a trusted external GitHub admission run/artifact identity? | external anchor: repository id, `run_id`, `run_attempt`, workflow path, `head_sha`, artifact id/digest, `referenced_workflows[]` |

All three use the existing three-value vocabulary `PASS | FAIL | UNKNOWN`. The vocabulary is
not extended, and the axes do not produce a new run-level verdict.

### 2.1 `proofValidity`

`proofValidity` is the theorem-bearing axis. A claim that makes no theorem claim
(`replay_observation`, or a solver-only `adopted_model`) does not receive a `proofValidity`
`PASS`; its model-consistency or observation evidence stays under that claim's own
`evidenceRefs` and is not re-labelled as a proof. For a theorem-bearing claim,
`proofValidity` is `PASS` only when **all** of the following are positively observed:

1. **Kernel acceptance.** The pinned Lean kernel accepts the theorem. The accepted theorem
   identity (declaration name plus proposition digest) matches the claimed proposition.
2. **Kernel replay.** `leanchecker <Module>` replays the produced `.olean` declarations
   through the same Lean kernel in a fresh process and exits successfully. This plain mode is
   the **mandatory** gate. `leanchecker --fresh` additionally replays the whole import
   closure; it is an **opt-in deep mode**, not a default: on the pinned Lean 4.33.0 an
   `Init`-importing artifact costs 69–98 s and a `Std` artifact ~130 s, which exceeds the
   120 s kernel-reexecution budget and would turn valid artifacts into fail-closed
   rejections. The checker binary must be pinned by path **and** SHA-256, not resolved from
   `PATH` or an environment override: an unpinned resolution accepts `/bin/true` as a
   passing checker.
3. **Axiom observation.** A `#print axioms` observation is present and its parsed dependency
   set is a subset of the canonical primitive allowlist
   `{propext, Classical.choice, Quot.sound}`; `sorryAx` / `Lean.sorryAx` is absent.
   `funext` is **not** a primitive axiom: it is a theorem alias whose dependency is
   `Quot.sound` ([lean_sorry_gate.md](lean_sorry_gate.md) §4). A producer-side `funext`
   spelling is not accepted by the primitive-axiom check.
4. **Binding match.** The theorem identity and the `modelBinding` (when the claim is an
   adopted-model claim) exactly match the adopted proposition record. A `modelBinding`
   mismatch is not repaired by a valid kernel run.

`#print axioms` is an **observation**, not a proof, and `leanchecker` is a **fresh-process
replay of the same kernel**, not a second independent kernel. Both steps are required; neither
replaces the other. `--fresh` adds exactly one thing over the plain mode: kernel-invalid
declarations in *imported* modules are replayed too. Because the toolchain is digest-pinned in
this contract, that case is already an assumed precondition; `--fresh` adds no second trust
root ([leanchecker_source](https://github.com/leanprover/lean4checker)).

**Observation forgery is a real hazard, not a theoretical one.** A `#print axioms` line is
producer-side output and a hostile source can emit an arbitrary one: a source comment
containing `#print axioms` suppresses the appender, and `run_cmd` / `#eval` executes at
compile time and can print a fake `'thm' does not depend on any axioms` line for a `sorry`
proof. A decoy theorem earlier in the file can also absorb the observation while the claimed
theorem stays unproved. The observation is therefore never trusted on its own: the theorem it
is bound to must be the **explicitly requested declaration** (not “the first `theorem`/`def`
in the source”), the `.olean` must replay through the kernel, and the `modelBinding` must
match the adopted proposition. Compile-time effects (`run_cmd`, `#eval`) and
`debug.skipKernelTC` are rejected in capsule flows; `#print axioms` is blind to
`debug.skipKernelTC`, and `leanchecker` is the step that catches it.

An absent `#print axioms` observation is missing evidence in capsule flows: `proofValidity`
is `UNKNOWN`/`FAIL`, never `PASS`. This is stricter than the documented legacy fail-open of
non-capsule replay ([lean_sorry_gate.md](lean_sorry_gate.md) §3.1).

`proofValidity` does not imply `reproducibility` (a kernel-accepted artifact may fail to
reproduce) and does not imply `provenanceAuthenticity` (a mathematically valid capsule may be
un-anchored). It also does not establish the original body's correctness for an
adopted-model claim ([adopted_model_observation_contract.md](adopted_model_observation_contract.md) §3).

### 2.2 `reproducibility`

`reproducibility` is `PASS` only when a **fresh process**, using the same pinned inputs,
toolchain digests, and options, produces the same verdict and the same theorem/certificate
identity for the claim. The comparison unit is the claim's status plus its identity-bearing
evidence (theorem declaration and proposition digest, certificate `identityDigest`, and the
observation records that the claim cites); timestamps, run IDs, and physical paths are not
part of the comparison.

- **Z3 is reproducible, not independent.** Re-running the same pinned Z3 binary with the same
  options in a fresh process tests reproducibility of the solver result. It does **not**
  establish an independent semantic check: a Z3 result can reproduce consistently and still be
  wrong. There is no second, independent solver claim in this contract.
- **Lean replay is not a second kernel.** `leanchecker` reproduces kernel acceptance
  through the same Lean kernel in a fresh process. Its independence is process-level, not
  implementation-level.
- `reproducibility` is `FAIL` on a deterministic divergence (same pinned inputs, different
  verdict or identity), and `UNKNOWN` when the fresh replay, pinned toolchain, or required
  inputs are unavailable.

`reproducibility` does not imply `proofValidity`: an invalid or vacuous artifact can reproduce
exactly. It does not imply `provenanceAuthenticity`: a reproducibly built capsule can still be
un-anchored.

### 2.3 `provenanceAuthenticity`

`provenanceAuthenticity` is `PASS` only when the capsule is bound to an **external** trusted
GitHub admission run/artifact identity that confirms all of the following:

- repository **numeric id** and owner/name;
- `run_id`;
- `run_attempt` (a re-run is a different attempt; attempt identity is part of the binding);
- workflow path (and the workflow ref used by the run);
- `head_sha` (the merge candidate `G`; the certificate/git relation in §5.2 must hold);
- artifact id and artifact digest (SHA-256 of the uploaded artifact bytes);
- `referenced_workflows[]` with the certificate-mint workflow at its pinned SHA, and
  successful job-level conclusions for the mint jobs (§5.2).

The admission authority is the App check named by the merge ruleset; a same-named check run
from another app is an authority substitution (§5.3).

The anchor is external evidence, not a capsule field. The capsule may carry an `anchorRef`
with those values as a **claim**, but the verifier must resolve the run/artifact through
GitHub (or a pinned release/policy) and compare the values itself. A capsule that declares its
own trust basis — `"trusted": true`, an embedded “trusted run” block, or a self-issued
signature — has not established authenticity.

- **Ed25519 is integrity-only.** The existing attestation key is derived from the public seed
  `axiom-attestation-v1-sha256`; anyone can sign with the corresponding private key. A valid
  signature is evidence that the signed bytes were not accidentally corrupted, not evidence of
  who produced them. Signature validity never turns `provenanceAuthenticity` into `PASS` by
  itself.
- **Journal entries are internal history.** Including journal entries lets a verifier
  reconstruct the capsule's internal claim→attestation→certificate history. It does not prove
  that the original append-only journal was authentic or unmodified unless an external anchor
  binds the capsule to the trusted admission run. A self-contained journal is a narrative, not
  an authenticity proof.
- **Artifacts are transport, not a durable ledger.** GitHub Actions artifacts are immutable
  per upload while retained, but retention is finite (currently 1–90 days). An expired or
  deleted artifact yields `UNKNOWN`, never `PASS` by absence. A GitHub ruleset or required
  check is an admission authority, not an evidence verifier.

`provenanceAuthenticity` does not imply the other two axes: an authentic admission artifact can
contain an invalid proof or a non-reproducible result. Conversely, a valid proof can arrive
through an un-anchored capsule; that capsule simply cannot claim authenticity.

---

## 3. Capsule members and manifest

### 3.1 Members

A capsule contains the following members. All paths are capsule-relative; producer-local
absolute paths, vault paths, and state-root paths are excluded from identity-bearing fields.

| Member | Content | Role |
|---|---|---|
| Certificate bodies | Existing v3 canonical certificate bytes, unmodified | Claimed verdicts, identity, attestation references |
| Journal entries | Existing journal records needed to reconstruct the internal claim→attestation→certificate chain | Internal history; not authenticity by itself |
| Observations | Raw `#print axioms` output; `leanchecker` command/exit/stdout/stderr; replay harness observations; solver invocation/result records | Positive evidence for the axes |
| Lean project minimal files | `lakefile.lean`, `lean-toolchain`, `lake-manifest.json`, theorem/spec/model `.lean` sources, and the local imports required to rebuild | Kernel replay input |
| Policy / scope contents | Exact policy and scope file contents and their SHA-256 | Execution contract binding |
| Toolchain identity | Lean, lake, leanchecker, and Z3 versions plus binary SHA-256 and public acquisition source | Digest-addressed public inputs |
| Replay inputs | Exact commands, options, seeds, rlimit/timeout, input corpus, expected outputs, and public dependency pins | Fresh-process replay |
| Manifest | Exact inventory plus `capsuleDigest`, `certificateSetDigest`, and `modelBinding` | Capsule identity |

Toolchain binaries are **not required to be embedded**. They are public inputs referenced by
digest and version. If a binary cannot be acquired from the recorded public source, or its
digest differs, the affected axis is `UNKNOWN`/`FAIL` (§6). A capsule must not require a
producer-local cache, vault, or journal to be readable.

An `.olean` may be rebuilt from the Lean project files with the pinned Lean before
`leanchecker`. If the capsule instead includes a prebuilt `.olean`, that file must be
inventory-listed, digest-bound, and it must be the artifact actually replayed by
`leanchecker`; a prebuilt artifact that is not the replayed one is not evidence.

### 3.2 Manifest

The manifest is the single inventory and identity document:

```json
{
  "schemaVersion": "axiom.evidence-capsule.v1",
  "subject": {
    "repository": "owner/name",
    "commit": "<git commit>",
    "tree": "<git tree oid>",
    "sourceSetDigest": "sha256:..."
  },
  "claims": [
    {
      "kind": "direct_proof",
      "proposition": {"digest": "sha256:..."},
      "modelBinding": null,
      "requiredAxes": ["proofValidity", "reproducibility", "provenanceAuthenticity"],
      "evidenceRefs": ["obs/axioms.txt", "obs/leanchecker.json", "lean/Theorem.lean"]
    }
  ],
  "certificateSet": [
    {"identityDigest": "sha256:...", "bodySha256": "sha256:..."}
  ],
  "certificateSetDigest": "sha256:...",
  "inventory": [
    {"path": "lean/Theorem.lean", "role": "lean-source", "size": 1234, "sha256": "sha256:..."}
  ],
  "policyScope": {
    "policySha256": "sha256:...",
    "scopeSha256": "sha256:..."
  },
  "toolchainIdentity": [
    {"name": "lean", "version": "4.33.0", "binarySha256": "sha256:...", "publicSource": "..."}
  ],
  "replayInputs": {
    "commands": ["..."],
    "environment": {"workers": 1, "seed": 0},
    "inputCorpusDigest": "sha256:...",
    "expectedOutputDigest": "sha256:..."
  },
  "modelBinding": null,
  "nonClaims": ["..."],
  "capsuleDigest": "sha256:...",
  "signature": null
}
```

- `subject.sourceSetDigest` uses the existing D1 source-set digest definition
  ([productization_contract.md](productization_contract.md) §10.1); it does not introduce a
  second source identity.
- `certificateSet` is sorted by `identityDigest` and is bound by `certificateSetDigest` (§8.3).
- `inventory` lists every capsule file except `manifest.json` itself. The manifest is the only
  unlisted file; `capsuleDigest` binds it.
- `signature` is optional and integrity-only (§5.2). If present, it is excluded from
  `capsuleDigest`.

### 3.3 `modelBinding`

`modelBinding` is the exact binding to the adopted proposition/model/specification record:

```json
{
  "proposalDigest": "sha256:...",
  "propositionDigest": "sha256:...",
  "adoptedModelDigest": "sha256:...",
  "specSubsetDigest": "sha256:...",
  "adoptionRecordDigest": "sha256:...",
  "modelBindingDigest": "sha256:..."
}
```

- `proposalDigest` binds the input proposal identity; it is part of the D_capsule
  proposition/model/spec identity set ([productization_contract.md](productization_contract.md) §1c DC2).
- For `adopted_model` and `replay_observation` claims, `modelBinding` is required and must
  match the adopted proposition record exactly. A mismatch is `proofValidity` `FAIL` (for a
  theorem-bearing claim) and also invalidates the adopted-model/replay evidence.
- For `direct_proof` claims, `modelBinding` is `null`: a direct proof does not use an adopted
  model. `null` is honest, not missing evidence.
- A capsule must not mix claims with different `modelBindingDigest` values. If a subject has
  distinct adopted models, use separate capsules; a mixed capsule is structurally invalid.
- `modelBindingDigest` is computed with the `model-binding` domain tag (§8).
- Within `claims[]` (manifest declaration or verifier assessment), `modelBinding` may be the
  full object above or the reference object `{"modelBindingDigest": "sha256:..."}`. A reference
  resolves to the manifest-level `modelBinding`; an unresolvable reference is missing required
  evidence (`proofValidity = UNKNOWN` for an adopted-model/replay claim), and a reference whose
  digest disagrees with the resolved binding is a mismatch (`proofValidity = FAIL`).

---

## 4. Per-claim output

### 4.1 `claims[]` is mandatory

A subject may carry multiple claims. There are two separate documents, and they must not be
conflated:

1. **Manifest claim declarations** (`manifest.json`, inside the digest): what is claimed and
   which evidence the capsule carries. These fields are part of `capsuleDigest`.
2. **Verifier assessment** (outside the digest): the per-claim `axes` and projected `status`
   that a verifier computes from the capsule's evidence. A manifest-supplied status is not
   evidence.

Manifest claim declaration:

```json
{
  "kind": "direct_proof",
  "proposition": {"digest": "sha256:..."},
  "modelBinding": null,
  "requiredAxes": ["proofValidity", "reproducibility", "provenanceAuthenticity"],
  "evidenceRefs": ["obs/axioms.txt", "obs/leanchecker.json", "lean/Theorem.lean"]
}
```

Verifier assessment for the same claim (recomputed, never trusted from the manifest):

```json
{
  "subject": {"modulePath": "...", "functionName": "...", "sourceHash": "sha256:..."},
  "capsuleDigest": "sha256:...",
  "claims": [
    {
      "kind": "direct_proof",
      "proposition": {"digest": "sha256:..."},
      "modelBinding": null,
      "axes": {
        "proofValidity": {"status": "PASS", "evidence": ["kernel-accept", "leanchecker-fresh", "axioms-observation"]},
        "reproducibility": {"status": "PASS", "evidence": ["fresh-run-2"]},
        "provenanceAuthenticity": {"status": "UNKNOWN", "evidence": ["anchor-retention-expired"]}
      },
      "status": "UNKNOWN"
    },
    {
      "kind": "replay_observation",
      "proposition": {"digest": "sha256:..."},
      "modelBinding": {"modelBindingDigest": "sha256:..."},
      "axes": {
        "reproducibility": {"status": "PASS", "evidence": ["fresh-run-2"]},
        "provenanceAuthenticity": {"status": "UNKNOWN", "evidence": ["anchor-retention-expired"]}
      },
      "status": "UNKNOWN"
    }
  ]
}
```

Every `evidenceRefs` entry resolves to an inventory-listed capsule path (§8.4); a reference to
an unlisted path, a `..` escape, or a verifier-produced status block is structurally invalid.

### 4.2 Claim kinds and required axes

Exactly three claim kinds are defined. They are distinct claims, not three names for one
function-level result:

| Kind | Meaning | Required axes |
|---|---|---|
| `direct_proof` | The emitted Lean theorem for the subject's denotation is kernel-accepted and matches the proposition. | `proofValidity`, `reproducibility`, `provenanceAuthenticity` |
| `adopted_model` | The adopted model satisfies the adopted specification subset. This is **not** a proof of the original body. | `reproducibility`, `provenanceAuthenticity`; `proofValidity` is additionally required when the model-consistency result is backed by a Lean theorem |
| `replay_observation` | On the pinned original symbol, each input in the finite enumerated set `I` produces the model's expected value. This is **not** a universal theorem. | `reproducibility`, `provenanceAuthenticity`; the observation must satisfy the adopted-model observation conditions |

| Kind | Recorded as | Must not be reported as |
|---|---|---|
| `direct_proof` | The theorem claim itself | — |
| `adopted_model` | Its own claim entry, backed by solver/kernel model-consistency evidence | A `direct_proof` of the original body |
| `replay_observation` | Its own claim entry, backed by the stamped replay observation | A universal theorem |

**The required-axis set is a floor, not a producer choice.** `requiredAxes` must contain every
axis in the table row for its kind. It may add `proofValidity` for a kernel-backed
`adopted_model`, but it may not narrow the row; when an `adopted_model` or
`replay_observation` claim cites a Lean theorem, `proofValidity` is part of the floor. An empty
or reduced `requiredAxes` is a structural `FAIL`, because otherwise "every required axis is
`PASS`" could be satisfied vacuously and produce a `PASS` with no assessed evidence. A consumer
ignores a manifest-supplied `requiredAxes` that is narrower than the table and assesses the
kind's full row.

### 4.3 Status projection and the `claimClass` prohibition

For each claim:

- `status = PASS` iff every axis in `requiredAxes` is `PASS` and the kind-specific evidence is
  complete and consistent.
- `status = FAIL` iff any required axis is `FAIL`, or the kind-specific evidence contradicts
  the claim.
- `status = UNKNOWN` otherwise (missing, unavailable, ambiguous, or insufficient evidence).

`axes` remains the authoritative per-axis output; `status` is only a convenience projection for
consumers and does not erase the axis distinction. A consumer that must distinguish invalidity
from non-reproducibility from un-anchored provenance reads `axes`, not `status`.

A capsule or consumer **must not** replace `claims[]` with a single `claimClass` per function,
and must not collapse mixed claim statuses into one function-level `PASS`. A function may have
a `direct_proof` that passes while an `adopted_model` claim is `UNKNOWN`, or vice versa; that
mixed result is the honest output. The existing verdict authority may consume these statuses
only through its existing contracts; this document does not create a new aggregate verdict.

---

## 5. Trust anchor

### 5.1 The capsule cannot declare its own trust basis

The trust anchor is **external** to the capsule. The verifier must obtain it from GitHub or a
pinned release/policy and compare it with the manifest's `subject`, `certificateSetDigest`,
`capsuleDigest`, and artifacts. A manifest field that asserts trust — a boolean, a “trusted
run” block, a self-issued signature, or a self-declared public key — is untrusted input, not an
anchor.

The minimum external anchor for a GitHub admission run is the eight-field identity in §2.3.
For a pinned release, the anchor is the immutable release identity plus the release asset
digest and the pinned policy digest; the same principle applies: the verifier resolves it
externally.

| Anchor field | Externally resolved from | Why it is part of identity |
|---|---|---|
| `repository.id` (numeric) | `GET /repos/{owner}/{repo}` | Names can be renamed or recycled; the numeric id cannot. |
| `repository.full_name` | same | Human-readable cross-check only; insufficient alone. |
| `run.id` | `GET /repos/{owner}/{repo}/actions/runs/{run_id}` | Identifies exactly one workflow run. |
| `run.attempt` | same | A re-run is a different attempt with different artifacts. |
| `run.path` | same | The workflow file that produced the evidence. |
| `run.head_sha` | same | The merge candidate `G` (§5.2). |
| artifact `id` + `digest` | `GET .../actions/runs/{run_id}/artifacts` | `digest` is the SHA-256 of the stored zip; `id` disambiguates re-uploads of the same name. |
| `run.referenced_workflows[]` | same | The reusable workflows actually executed, by path **and** pinned SHA. |

A **run URL**, a **check-run conclusion**, or an artifact **name** is not an anchor field: each
is a pointer or a summary that a responder can reproduce without being the producer. Artifact
`digest` binds the stored bytes to the artifact record; it does not by itself prove the bytes
are a valid proof (§7).

### 5.2 Merge-queue identity relation

For a merge-group run, the certificate's subject binding and the run's `head_sha` are related
by a deterministic git identity. The verifier checks the relation instead of trusting an
asserted equality:

```
G = run.head_sha                    # merge-group synthetic merge commit
certificate.subject.baseSha  == G^1
certificate.subject.headSha  == G^2
certificate.subject.certTree == tree(G)
```

A verifier with the subject repository available recomputes `G^1`, `G^2`, and `tree(G)`. A
mismatch is `provenanceAuthenticity = FAIL`; an unavailable repository is `UNKNOWN`, never
`PASS`. This relation is what makes a certificate about the **merge candidate** rather than
about an arbitrary branch tip. A capsule whose subject commit is not the run's merge candidate
cannot claim admission provenance, even if every other field matches.

`run.referenced_workflows[]` must additionally contain the certificate-mint workflow at its
pinned SHA, and the mint jobs (`mint-prepare` / `prepare` and `mint-publish` / `publish`) must
have concluded successfully in that attempt. A run-level `success` conclusion does not imply
that the mint jobs ran: the verifier reads the job-level conclusions.

### 5.3 Admission authority vs. same-named checks

The admission authority is the GitHub App check that the merge ruleset requires. A check run
with the same **name** produced by a different app (for example, the Actions app) is an
authority substitution: it proves that some workflow reported that name, not that the
admission authority approved. The verifier resolves check runs with
`GET /repos/{owner}/{repo}/commits/{ref}/check-runs?per_page=100` and matches on
`check_run.app.id` **and** `check_run.name`; a name-only match is `UNKNOWN`.

Pagination is part of the procedure: a single commit can carry more than 100 check runs, so a
first-page-only lookup can miss the authority check and must not be read as “absent”.

### 5.4 Journal entries reconstruct history, not authenticity

Journal entries inside the capsule reconstruct the internal history of claims, attestations,
and certificates. They do not prove that the original append-only journal was authentic,
complete, or unmodified. That conclusion requires an external anchor binding the capsule to
the trusted admission run/artifact. Without such an anchor, `provenanceAuthenticity` is
`UNKNOWN`, even if every journal entry is internally consistent.

### 5.5 Signature is integrity-only

If the manifest declares a signature, it covers the domain-separated message

```
UTF8("axiom.evidence-capsule.v1") || 0x00 || UTF8(capsuleDigest)
```

and must verify against the existing public attestation key. The public seed
`axiom-attestation-v1-sha256` means the signing capability is public: a valid signature does
not authenticate a producer, a repository, or a run. An invalid signature is a structural
`FAIL`; a valid signature is never sufficient for `provenanceAuthenticity` `PASS`.

### 5.6 Retention and durability

GitHub Actions artifacts are immutable per upload while retained, but retention is finite.
The observed admission path keeps two artifacts with different lifetimes: the certificate-set
artifact (3-day retention) and the witness artifact (30-day retention). After both expire, only
**coordinate** evidence survives — run/artifact metadata a verifier can still resolve — and
that supports at most an `UNKNOWN` content binding. Absence never becomes `PASS`.

Artifacts are transport for the capsule, not a durable audit ledger. If the anchor's artifact
has expired or been deleted, the verifier reports `UNKNOWN`; it must not infer authenticity
from a cached copy, a run URL, or a ruleset status. A GitHub ruleset or required check is an
admission authority, not an evidence verifier.

### 5.7 This anchor is online and separate from the offline path

The §2.3/§5.1 anchor requires network access to GitHub. It is deliberately **separate** from
the local replay-bound path of [productization_contract.md](productization_contract.md) §1b,
which makes no network claim. A capsule verified offline can establish `proofValidity` and
`reproducibility`; it cannot establish `provenanceAuthenticity` without the external anchor,
and an offline verifier must report that axis `UNKNOWN` rather than skip it.

---

## 6. Fail-closed states

The following table is normative. `PASS` requires positive evidence for every required
condition; absence is not evidence; `UNKNOWN` is never promoted to `PASS`; and there is no
default `PASS`.

| # | Condition | Result |
|---|---|---|
| 1 | `capsuleDigest` mismatch, malformed manifest, or unrecognized `schemaVersion` | Structural `FAIL` |
| 2 | Inventory missing a file, listing an extra file, duplicating a path, or mismatching size/SHA-256 | Structural `FAIL` |
| 3 | Path escapes the capsule root, contains `..`, a backslash, a NUL, an empty segment, or is a symlink/non-regular file | Structural `FAIL` |
| 4 | `certificateSet` contains duplicate `identityDigest` values | Structural `FAIL` |
| 5 | Claim kind is not one of the three defined kinds | `UNKNOWN` (cannot assess), never `PASS` |
| 6 | Required evidence for a claim is missing | `UNKNOWN` (or `FAIL` if the evidence is present and contradictory) |
| 7 | `#print axioms` observation is absent in a capsule flow | `proofValidity = UNKNOWN`, never `PASS` |
| 8 | `sorryAx` / `Lean.sorryAx` appears, or a non-allowlisted axiom is observed | `proofValidity = FAIL` |
| 9 | Theorem identity or `modelBinding` does not match the adopted proposition | `proofValidity = FAIL` |
| 10 | `leanchecker` is absent, cannot start, or times out | `proofValidity = UNKNOWN` |
| 11 | `leanchecker` exits non-zero or reports a mismatch (any mode) | `proofValidity = FAIL` |
| 12 | Pinned toolchain binary digest differs | `proofValidity` / `reproducibility = FAIL` (identity mismatch); unavailable public input → `UNKNOWN` |
| 13 | Same pinned inputs/toolchain/options produce a different verdict or identity in a fresh process | `reproducibility = FAIL` |
| 14 | External anchor is missing, unreachable, ambiguous, or its artifact has expired | `provenanceAuthenticity = UNKNOWN` |
| 15 | External anchor resolves but repository, `run_id`, `run_attempt`, workflow path, `head_sha`, or artifact digest differs | `provenanceAuthenticity = FAIL` |
| 16 | A declared signature is invalid | `provenanceAuthenticity = FAIL` (integrity failure; it was never authenticity) |
| 17 | A ruleset or required-check success is the only “evidence” offered for a claim | No axis `PASS`; `UNKNOWN` (a ruleset is not an evidence verifier) |
| 18 | Source rejects capsule flow: `run_cmd`, `#eval`, `debug.skipKernelTC`, or another compile-time effect is present | `proofValidity = FAIL` (not `UNKNOWN`: the artifact is not acceptable evidence) |
| 19 | The observation is bound to a declaration other than the explicitly requested theorem, or the requested theorem is absent/ambiguous in the source | `proofValidity = FAIL` (a decoy observation is not evidence) |
| 20 | `leanchecker` binary is resolved from `PATH` or an environment override instead of a digest-pinned path | `proofValidity = UNKNOWN` (unpinned checker cannot establish kernel acceptance) |

A `FAIL` on one axis is not repaired by a `PASS` on another. A capsule with one `UNKNOWN`
required axis is reported with that axis `UNKNOWN`; it is not rounded up to `PASS`.

---

## 7. Non-claims

A capsule and this contract do **not** claim any of the following:

- **Whole-repository correctness.** The capsule covers only the subjects and claims it lists.
- **Universal input correctness.** `replay_observation` covers a finite enumerated input set;
  it is not a `∀x` theorem.
- **Original body formal proof.** An `adopted_model` claim proves a model-consistency
  proposition, not the original implementation body. The subject connection is the stamped
  replay observation only ([adopted_model_observation_contract.md](adopted_model_observation_contract.md) §3).
- **Independent second kernel.** `leanchecker` (plain or `--fresh`) replays through the same
  Lean kernel; it is a fresh process, not an independent kernel implementation.
- **Compile-time effect sandboxing.** The capsule flow rejects `run_cmd`, `#eval`, and
  `debug.skipKernelTC` in the theorem source, but rejection is a static source check plus the
  kernel replay — it is not a proof that no other compile-time effect exists.
- **Independent Z3.** Re-running the same pinned Z3 binary tests reproducibility only; it is
  not an independent solver or a semantic second opinion.
- **Signature as authenticity.** The Ed25519 attestation key derives from a public seed;
  signatures are integrity evidence, not producer authentication.
- **Artifact as a durable ledger.** GitHub Actions artifact retention is finite (1–90 days);
  artifacts are transport, not an append-only audit ledger.
- **Ruleset as evidence verifier.** A GitHub ruleset or required check is an admission
  authority; it does not verify the capsule's evidence.
- **Self-contained certification.** Toolchain and inputs are public and digest-addressed, not
  embedded. A capsule cannot be verified offline without those public inputs.
- **Capsule self-declared trust.** The capsule cannot declare its own trust basis; only an
  external anchor can establish `provenanceAuthenticity`.

---

## 8. Digest wire

### 8.1 Domain separation

The digest wire is a fixed Axiom encoding, **not** RFC 8785 JCS and not a JSON
canonicalization. Do not feed `jq -S` output or a pretty-printed manifest into these digests.

```
DOMAIN = "axiom.evidence-capsule.v1"
H(tag, payload) = SHA-256(UTF8(DOMAIN) || 0x00 || UTF8(tag) || 0x00 || payload)
digest(tag, payload) = "sha256:" + lowercaseHex(H(tag, payload))
```

`tag` is ASCII and must not contain NUL. The defined tags are `capsule`, `certificate-set`,
and `model-binding`. A new tag requires a contract amendment; tags are not reused across
contracts.

### 8.2 Fixed encoding

`enc(value)` uses the following type-tagged, length-framed encoding:

| Type | Encoding |
|---|---|
| null | `0x00` |
| bool | `0x01 || (0x00 for false, 0x01 for true)` |
| uint64 | `0x02 || LE64(value)` |
| string | `0x03 || LE64(byteLength) || UTF-8 bytes` |
| bytes | `0x04 || LE64(byteLength) || bytes` |
| array | `0x05 || LE64(count) || enc(element)…` |
| object | `0x06 || LE64(count) || (LE64(keyLength) || UTF-8 key || enc(value))…` |

- Object fields are encoded in the schema order defined by §3.2, not in key-sorted order.
  Nested objects (`subject`, `policyScope`, `replayInputs`, `modelBinding`, claim declarations,
  inventory entries, certificate entries, toolchain entries) use the field order shown in this
  document. Verifier assessment objects (§4.1) are not encoded into `capsuleDigest`.
- Arrays preserve document order except `inventory` (sorted by path) and `certificateSet`
  (sorted by `identityDigest`).
- Strings are exact UTF-8 bytes; no Unicode normalization, JSON escaping, or numeric
  rewriting is applied.
- `capsuleDigest = digest("capsule", enc(manifest fields in §3.2 order, excluding
  capsuleDigest, signature, and verifier output))`.
- `modelBindingDigest = digest("model-binding", enc(modelBinding fields excluding
  modelBindingDigest))`.

**Verifier output is not capsule identity.** The manifest's `claims[]` entries declare the
claim kind, proposition, and `modelBinding` reference. The per-axis `axes` and projected
`status` of §4 are verifier output computed from the capsule's evidence; they are excluded
from `capsuleDigest`, so re-verifying the same capsule cannot change its digest. A verifier
must recompute `axes`/`status`; it must not accept a manifest-supplied `status` as evidence.

The JSON examples in §3.2 and §4.1 show shape only. The digest input is the field-order
encoding above, never the example text or any JSON serialization of it.

### 8.3 Certificate set

`certificateSet` entries are `{identityDigest, bodySha256}` objects. The set is sorted ascending
by the raw UTF-8 bytes of `identityDigest` (not by numeric value or body hash), then encoded:

```
certificateSetDigest = digest("certificate-set", enc(sortedEntries))
```

- Duplicate `identityDigest` values are rejected; the set is **not** deduplicated.
- Two entries with the same identity but different body bytes are a structural `FAIL`.
- The empty set has a defined digest, but a claim that requires a certificate with an empty
  set is `UNKNOWN`.
- Certificate bodies themselves retain the canonical certificate bytes of
  [provenance_contract_v3.md](provenance_contract_v3.md) §6; the capsule does not re-serialize
  or normalize them.

### 8.4 Path normalization

Inventory paths are capsule-root-relative logical paths:

- POSIX `/` separators; no leading or trailing slash; no empty segment; no `.` or `..`.
- No backslash, NUL, or control characters.
- Regular files only; symlinks, hardlink aliases, device nodes, and directories are not
  inventory entries.
- Case-sensitive; exact UTF-8 bytes; no Unicode normalization is applied by the verifier.
  Producers must emit the normalized spelling they intend.
- Duplicate paths are rejected. Inventory is sorted by path bytes for determinism.
- Physical producer paths, vault paths, and state-root paths must not appear in inventory,
  identity-bearing claims, or replay command records; use capsule-relative paths or
  `<capsule-root>` placeholders.

### 8.5 Self-exclusion

- `capsuleDigest` excludes the top-level `capsuleDigest` and `signature` fields.
- `modelBindingDigest` excludes its own `modelBindingDigest` field.
- `certificateSetDigest` covers the certificate entries only, not the manifest or signature.
- `manifest.json` is not an inventory member; every other capsule file must be listed exactly
  once. No digest field hashes itself.

---

## 9. Changing this contract

- The conditional tier is declared in
  [productization_contract.md](productization_contract.md) §1c. Changing the tier or the
  `D_capsule` input set requires a productization-contract amendment first.
- Adding a claim kind, an axis, a digest tag, or a trust-anchor type is a contract amendment,
  not an implementation detail.
- This document creates no new verdict producer, gate, execution authority, or CLI surface.
  Code changes that implement capsule emission or verification are separate work and must not
  weaken the fail-closed rules in §6.
