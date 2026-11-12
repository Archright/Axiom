# Phase C2 — Identity Structure Design (Two-Identity Scheme)

**Status**: Design only — no product code changes. Implementation is gated on §5 (I3 waiver/revision) and the JCS semantic-evidence freeze (§2.3).
**Scope**: `data/readiness/evaluate.py` chain (independent readiness evaluator), `tools/readiness_evaluator.nim` chain (decision predicate SSOT), `data/readiness/readiness_history.json`, `data/readiness/snapshots/`.
**Governing**: AGENTS.md §0.10 (Decision Binding), §0.9 (Theater Prohibition); `docs/spec/continual_revalidation.md` §6(e) and §7; `docs/spec/canonical_contract_policy_layer.md` I1–I5.

**Grounding-document status**: `docs/design/phasec_boundaries.md` (C0) is **NOT present in the repository tree** and has no git history (verified: `git log --all -- docs/design/phasec_boundaries.md` returns nothing). B2, B3, and B4 below are therefore restated from the C2 task brief; the boundary document must be restored and committed before C2 implementation, since C0 is the normatively cited freeze. All C2 facts below were re-verified empirically against HEAD `2e31b258799d8ae25e173ba16c2eb3188f663977` on 2026-08-19.

---

## 1. The Two-Identity Scheme (B2)

**B2 core rule**: `EvaluationInputIdentity ≠ DecisionIdentity`, and **Identity ≠ Provenance**. Timestamps (`observedAt`, `createdAt`, `generatedAt`, `collectedAt`, `freshUntil`, `evaluationTime`) are provenance-only and are **never** re-merged into identity. This matches established repo precedent: `docs/spec/canonical_contract_policy_layer.md:71` (line numbers are NOT identity; `canonicalSyntaxHash` is the identity core) and `docs/spec/canonical_ast_identity.md:12-19` (source position, lexical form, parser transient metadata excluded from content identity).

### 1.1 EvaluationInputIdentity — "what was evaluated"

```
H(x)      := sha256hex(x)                     ; SHA-256 over UTF-8 bytes, 64 lowercase hex chars
JCS(x)    := RFC 8785 canonical serialization of JSON DOM x (see §2)
compID(x) := H(JCS(x))                        ; digest of a canonicalized component

EvaluationInputIdentity := H(
    compID(evidence) || compID(policy) || compID(evaluatorArtifactBytes)
    || ExecutionContractDigest || compID(schema) )
```

`||` is byte concatenation of fixed-length 64-hex component digests (never raw JCS bytes inline), which makes the concatenation unambiguous and keeps the potentially large `evaluatorArtifactBytes` payload out of the preimage. The mandate form `H(JCS(evidence) || JCS(policy) || EvaluatorArtifactBytes || ExecutionContractDigest || JCS(schema))` is the semantic contract; the fixed-length form is its faithful, unambiguous encoding.

Component mapping:

| Component | Source | Canonicalization |
|---|---|---|
| `evidence` | `data/readiness/evidence_manifest.json` (after §2.3 fix) | `JCS(schema-validated DOM)` |
| `policy` | `data/readiness/independent_policy.json` (`evaluate.py:10`, POLICY_PATH) | `JCS(schema-validated DOM)` |
| `evaluatorArtifactBytes` | `evaluate.py` — file BYTES via `Path(__file__).resolve()` (§3) | `H(raw bytes)` |
| `executionContractDigest` | §4 | `H(JCS(contract DOM))` |
| `schema` | §7 bundle: evidence + policy + decision schemas | `H(JCS(bundle DOM))` |

### 1.2 DecisionIdentity — "what was decided"

```
DecisionIdentity(verdict, outcome) := H( H(EvaluationInputIdentity) || compID({"verdict": verdict, "outcome": outcome}) )
```

- `verdict ∈ {GO, CONDITIONAL-GO, NO-GO}` (`evaluate.py:166-171`), `outcome ∈ {CONTINUE, BLOCK, UNRESOLVED}` (continual revalidation §4).
- The rendered `invariantResults` / `reasons` / `blockingReasons` / `nonCriticalIssues` blocks are derived deterministically from (evidence, policy, evaluator, contract), so they are covered transitively by `EvaluationInputIdentity` and are **not** re-hashed into identity — identity stays stable across presentation changes.
- The serialized decision record embeds `evaluationInputIdentity` but **excludes its own `decisionId`** when the identity is re-verified (cycle-freedom; same rule as snapshots, §2.4).
- Matches the locked mandate `docs/spec/continual_revalidation.md:89`: "parent = lineage metadata only; serialized record may be timestamp-varying (provenance) even though canonical identity is deterministic."

### 1.3 Worked example (component digests measured 2026-08-19)

```
compID(evidence)  = ff50d892f60cb890598c495d8ff12bc3bd3661e5d619863667825e81a0be8fb4    // JCS of the BEFORE snapshot
compID(evidence)  = af2c1bc2460f9443ef74b1af3817d49b6336f42bcd8afa8a4c7fb5c5ddb0c57f     // JCS of the AFTER snapshot; the current
                                         //   evidence_manifest.json is byte-identical to it (verified)
compID(policy)    = c9b59d7a91c43da7a72b80160815adc821e99455b0fa98253a61526291edad46          // JCS of independent_policy.json
compID(evaluator) = 440ffa2ae29c1c1414272605b2415ca0ae6cc6efb5bf841b7fdee8e948931504     // H of current evaluate.py bytes (§3)
executionContract = §4 — TBD until contract normalization lands
compID(schema)    = TBD — §7 schema files do not exist yet

EvaluationInputIdentity = H( <one of the two evidence compIDs> || c9b59d7a91c43da7a72b80160815adc821e99455b0fa98253a61526291edad46 || 440ffa2ae29c1c1414272605b2415ca0ae6cc6efb5bf841b7fdee8e948931504 || <contract> || <schema> )
```

## 2. Canonical JSON — RFC 8785 (JCS) Unification

### 2.1 The three ad-hoc canonicalizers in the repo today

| # | Site | Mechanism | Divergences from RFC 8785 |
|---|---|---|---|
| A | `data/readiness/evaluate.py:150-151` | `json.dumps(x, sort_keys=True)` for `policy_digest` and `manifest_digest` | default separators `(', ', ': ')` — space-padded bytes are hashed; `ensure_ascii=True` escapes non-ASCII as `\uXXXX` (JCS keeps UTF-8); no number normalization (`1` vs `1.0`, `-0.0`, exponent case as-given) |
| B | `tools/readiness_evaluator.nim:112-141` (`canonicalJson`) | sorted keys, compact, `escapeJson` (std/json), `$n.getInt()` / `$n.getFloat()` | compact separators agree with JCS, but numbers via `$` (no `1.0`→`1`, no exponent-case normalization) and escape bytes differ |
| C | `tools/canonical_json.nim:57-127` | fixed alphabetical key list (`canonicalObjectKeys`, lines 57-59), 2-space pretty print, entries sorted by numeric `DEBT#` (`sortEntries`, 116-121) | pretty-printed, not compact — different digest bytes; `escapeJsonStringPretty` (lines 53-55) emits **no escaping** (latent bug for strings containing `"` or `\`); `escapeJsonString` is used only for `files` |

Three different byte outputs for the same logical document — three different digests by construction. None implements RFC 8785.

### 2.2 Unification decision

- **Primary (SSOT)**: new pure-Nim module `tools/jcs.nim` — `func` plus `{.raises: [].}`, implementing RFC 8785: lexicographic key order by Unicode code point; shortest escapes, lowercase hex, only `"`, `\`, U+0000–U+001F; ECMAScript number normalization (`-0`→`0`, no leading `+`, exponent form per RFC, NaN/Infinity rejected); UTF-8 output; no whitespace. Tested against golden fixtures derived from the RFC 8785 §3 examples.
- **Python side**: `evaluate.py:150-151` digests come from a pinned exact-JCS reference implementation (replay oracle only; the Nim implementation stays canonical).
- **Legacy**: `tools/readiness_evaluator.nim:105-141` is replaced by `tools/jcs.nim`; `tools/canonical_json.nim` keeps its debt-serialization purpose, re-based on the same string escaping (staged separately with the debt-registry digest snapshots).
- **Fail-closed**: any JSON not serializable under JCS (NaN, unsupported value) aborts evaluation — never falls back to an ad-hoc serializer.

### 2.3 BEFORE JCS: fix the "semantic evidence" definition (blocking precondition)

Under JCS, `{"x": null}` and `{}` are **distinct byte streams**, and an absent key differs from a key present with its default value. Today `makeObs` (`tools/readiness_evaluator.nim:150-156`) always emits `key`, `value`, `scope`, `subject` (empty-string defaults for `scope` / `subject`), while the Python manifest observations have inconsistent optional-key presence. Before any JCS digest is computed:

1. **Field presence per schema** (§7): each field is REQUIRED or OPTIONAL-with-default; DOM normalization drops an optional field whose value equals its schema default (`""`, `[]`, `false`) **before** JCS serialization, so `{"scope": ""}` canonicalizes identically to `{}` when the schema defaults `scope` to `""`.
2. **Null vs absent**: `null` is a *value* (R4 `proofDigest: null` means "observed as null"); an absent key is a *different* state. Enforced by the schema plus a unit test asserting `JCS({}) ≠ JCS({"x": null})`.
3. **Array order is semantic**: `reasons[]`, `collectionRunIds[]`, `observations[]` order is preserved; only object key order is canonicalized.
4. **String semantics**: no trimming; code points preserved; escapes only per RFC 8785.

### 2.4 Snapshot identity is cycle-free (mandated)

```
snapshotDigest := H( JCS(snapshot payload EXCLUDING the snapshotDigest field) )
```

- **Current state (verified)**: snapshot files contain no self-referential digest field — top-level keys are `schemaVersion`, `manifestId`, `generatedAt`, `repoIdentity`, `toolchain`, `policyDigest`, `collection`, `observations`; `evidenceManifestSnapshotDigest` = `H(snapshot file bytes)`. Cycle-free by construction today.
- **Rule**: if a `snapshotDigest` field is ever embedded, it MUST be stripped (parse → drop key → `JCS`) before hashing, and may appear only as the last field of the object.

## 3. Fix `evaluatorBinaryDigest` — Fault Confirmed Empirically

### 3.1 The fault (`evaluate.py:173-175`)

```python
evaluator_src = open(os.path.basename(__file__)).read() if os.path.basename(__file__) and os.path.exists(os.path.basename(__file__)) else __file__
evaluator_digest = sha(evaluator_src)
```

Run as `python3 data/readiness/evaluate.py` from the repo root, the CWD contains no `./evaluate.py`, so the `else` branch binds `evaluator_src = __file__` — the **absolute path string**. Reproduced on 2026-08-19:

- recorded `evaluatorBinaryDigest` `a8ad5b82ece8ec5670f53f80e8ef0702d2b37e2d70e54d515ed0545934da53fd` == `H("<user-home>/…/Axiom/data/readiness/evaluate.py")` — **exact match**;
- true content digest of the current file = `440ffa2ae29c1c1414272605b2415ca0ae6cc6efb5bf841b7fdee8e948931504`.

The recorded digest therefore varies by machine and checkout path: relocating the repo changes it while the evaluator bytes stay identical.

### 3.2 Required change

1. **Resolve and hash bytes**: `evaluator_src = Path(__file__).resolve().read_bytes()`. The `os.path.exists` fallback is removed — fail closed: if the file cannot be opened, abort with a non-zero exit; never hash a path string.
2. **Trackability**: `evaluate.py` is untracked and gitignored (`git ls-files` returns nothing; `.gitignore:121` is `*.py` under the "Python / Shell — Language Ban structural friction" block; carve-out precedent at `.gitignore:124-125`: `!tools/mutation_harness.sh`, `!tools/ci/runner/bootstrap_runner.sh`). Options (architect decision; neither is itself a policy change):
   - **P1 (preferred)**: narrow carve-out `!data/readiness/evaluate.py` + `git add data/readiness/evaluate.py` — tracked, pinned artifact.
   - **P2**: keep the `*.py` ban; mirror a pinned copy `data/readiness/operations/evaluate.pin` with a published `sha256sum`; hash the mirror.
3. **Record the pin in the decision record** (v2 payload): `evaluatorBinaryDigest` (bytes hash, `440ffa2ae29c1c1414272605b2415ca0ae6cc6efb5bf841b7fdee8e948931504` today), `evaluatorPin: "<tracked path or mirror>@<ref>"`, `evaluatorPinned: true`.

## 4. `ExecutionContractDigest` — First-Class Identity Input (B4)

- **B4 (Normative Artifact ≠ Execution Contract)**: `evaluatorArtifactBytes` (what code runs) and `executionContractDigest` (how it runs) are SEPARATE components of the same identity and are never merged — today `evaluate.py:173` conflates them (script digest only; interpreter, CWD, environment unpinned).
- Capture (canonicalized at run time):

```json
{
  "schemaVersion": 1,
  "interpreter": { "name": "cpython", "version": "<python --version, normalized, e.g. 3.12.5>" },
  "invocation": ["python3", "data/readiness/evaluate.py"],
  "workdir": "repo-root",
  "inputs": ["data/readiness/evidence_manifest.json", "<every file READ, JCS-sorted relative paths>"],
  "subprocessContract": [],
  "environmentNormalization": {
    "LC_ALL": "C.UTF-8", "LANG": "C.UTF-8",
    "PYTHONHASHSEED": "0", "PYTHONPATH": "", "PYTHONHOME": "", "TZ": "UTC"
  },
  "networkAccess": false
}
```

`ExecutionContractDigest := H(JCS(contract DOM))`.

- Capture rules: the contract DOM is copied into the decision record as `provenance.executionContract` and digested into `EvaluationInputIdentity` (§1.1). Deviations fail closed with `INFRA_FAIL` → `UNRESOLVED` (never a silent digest): non-repo-root CWD, `LC_ALL` ≠ `C.UTF-8`, `PYTHONHASHSEED` unset, env keys outside the normalization allowlist, any subprocess spawn, any network access.
- A changed contract is a changed identity: replay under a different environment must produce a different `EvaluationInputIdentity` — that is the intended provenance semantics for replay across venues.

## 5. I3 Conflict — Waiver or Policy Revision Required (AGENTS.md §0.10)

- `docs/spec/canonical_contract_policy_layer.md:91` (I3) commits: `decisionId` is the deterministic hash of `observationId + bindingId + timestamp` — **timestamp-including**, hence not content-based — which conflicts with:
- `docs/spec/continual_revalidation.md:89` (§6(e)) locked mandate: "Content-based deterministic decision identity: `H(policyDigest + evidenceDigest + executionContractDigest + verdict + outcome)`. Serialized record may be timestamp-varying (provenance) even though canonical identity is deterministic."
- Per AGENTS.md §0.10 (Decision Binding), the change is bound by the committed I3; resolve via **policy revision** of `docs/spec/canonical_contract_policy_layer.md:91` or a documented **waiver** in `config/decision_binding.waiver.toml` — **never silent divergence**. C2 implementation is gated on this decision.
- Recommended I3 revision: "`decisionId` is the content-based `DecisionIdentity` (C2 §1.2); timestamps are provenance-only and are recorded inside the decision payload". Companion I4 edit: minimal input set = evidence + policy + evaluator bytes + execution contract + schema. A waiver, if used, must be time-bounded and expire no later than the revision landing.

## 6. Replace the Timestamp `decisionId` and Output Name

- `evaluate.py:179` — `decisionId = "axiom-independent-readiness-" + utcnow()` → `decisionId = DecisionIdentity` (hex, §1.2) computed over the v2 payload with the `decisionId` field excluded. Reproducible and idempotent: identical (evidence, policy, evaluator bytes, contract, schema) ⇒ identical ID.
- `evaluate.py:195` — output file name from `utcnow()` → `decision.independent.<decisionId[:16]>.json` (full id inside the record). A deterministic re-run overwrites its own identical artifact (safe); the same ID with different content is a true collision → abort.
- Timestamps stay in the payload as a `provenance` object: `observedAt` (formerly `utcnow()`), `generatedAt` (from `manifest.collection`), `collectionRunIds`, the evaluator pin (§3.2.3), and `executionContract` (§4). The flat `provenance` string at `evaluate.py:193` is replaced by this object.
- Nim chain: `tools/readiness_evaluator.nim:820-942` takes `--eval-time`; `evaluationTime` (`EvaluationContext`) gates only the freshness check (`:280-281`), never the verdict — already compliant. BUT the Nim `decisionDigest` is currently incomplete: `sub` (lines 749-755) covers only `verdict`, `conditions`, `invariantStates`; `policyHash`, `bundleDigest`, `outcome`, `failureCategory` are outside the digest (line 769). C2 unifies it on the §1.2 formula over the full payload — a digest-integrity fix, not a semantics change.

## 7. JSON Schemas — So That `JCS(schema)` Is Defined

Three draft-07 schemas (none exists today; only `config/policy/contract_layer.schema.json`, `config/policy/policy_layer.schema.json`, and `src/gate/gate_manifest.schema.json` are present):

| Schema | Planned location | Role in identity |
|---|---|---|
| evidence | `data/readiness/evidence_manifest.schema.json` | REQUIRED / OPTIONAL-with-default (§2.3), null-vs-absent semantics, obs `key`/`value`/`scope`/`subject` shapes |
| policy | `data/readiness/policy.schema.json` | mirrors `independent_policy.json` keys: `policyId`, `invariants[].criticality`, `observationKeys`, `r1`/`r4`/`r5`/`r7`/`r8`, `freshness`, `tierCountsContract`, `semanticMapping` |
| decision | `data/readiness/decision.schema.json` | v2 record: `schemaVersion: 2`, `decisionId` (64 hex), `evaluationInputIdentity`, identity components, `invariantResults`, `finalVerdict`, `outcome`, `provenance`; `additionalProperties: false` |

```
compID(schema) := H( JCS({"evidence": <evidence schema>, "policy": <policy schema>, "decision": <decision schema>}) )
```

- Versioning follows the `canonical_contract_policy_layer.md` §버전 table (patch/minor/major); an unknown schema version fails closed.
- `JCS(schema)` hashes the schema **DOM** (formatting-insensitive), mirroring `JCS(evidence)`; only semantic schema changes flip identity.

## 8. Re-Derive the Faulty History Digests

`data/readiness/readiness_history.json` today holds `evidenceManifestCanonicalDigest` `d6a8abc5990739e1de7dd929ad0abcf06a2b0aae3db23a25449242f9c6958854` (BEFORE) and `b1c21216e7554681811953e6783a3e6f99639b3777fffdaedda7d96b0812be05` (AFTER) — computed by the ad-hoc `json.dumps(sort_keys)` method (verified by re-computation) — and the decision artifacts carry `policyDigest 617f6e7e04a3d405cfe293dc456a995e30f7701295b9e4337134e06aefa70769` plus the broken evaluator digest `a8ad5b82ece8ec5670f53f80e8ef0702d2b37e2d70e54d515ed0545934da53fd` (§3). All must be recomputed under the new method; the raw content-addressed snapshots survive unchanged.

### 8.1 Replace table (measured values)

| Artifact | Old (ad-hoc / broken) | New (RFC 8785 / pinned bytes) |
|---|---|---|
| evidence manifest — BEFORE snapshot | `d6a8abc5990739e1de7dd929ad0abcf06a2b0aae3db23a25449242f9c6958854` | `ff50d892f60cb890598c495d8ff12bc3bd3661e5d619863667825e81a0be8fb4` |
| evidence manifest — AFTER snapshot (== current `evidence_manifest.json`) | `b1c21216e7554681811953e6783a3e6f99639b3777fffdaedda7d96b0812be05` | `af2c1bc2460f9443ef74b1af3817d49b6336f42bcd8afa8a4c7fb5c5ddb0c57f` |
| policy `independent_policy.json` | `617f6e7e04a3d405cfe293dc456a995e30f7701295b9e4337134e06aefa70769` | `c9b59d7a91c43da7a72b80160815adc821e99455b0fa98253a61526291edad46` |
| evaluator `evaluate.py` | `a8ad5b82ece8ec5670f53f80e8ef0702d2b37e2d70e54d515ed0545934da53fd` (hash of the absolute path STRING — invalid) | `440ffa2ae29c1c1414272605b2415ca0ae6cc6efb5bf841b7fdee8e948931504` (file bytes) |
| snapshots (raw bytes address) | 273c7d1d97d51ed8ead72befaccf85a92a65f3735992acbd6ea06da359fc1ef5 / 2f2299ae857578329de5e6220f7320953019cdb85b9574b30b70c6216e2af984 | **unchanged** (content-addressed; no re-hash) |

### 8.2 Migration procedure (execution gated on §5 and §2.3)

1. Implement `tools/jcs.nim`, apply the §2.3 semantic norms, and recompute all digests from the two snapshots, `independent_policy.json`, and `evaluate.py` bytes.
2. In `readiness_history.json`: keep `evidenceManifestSnapshotDigest` (bytes, sound) **unchanged**; add the new JCS columns/rows; keep legacy values as historical provenance (`method: "python-json.dumps-sort-keys"`).
3. Re-issue the two independent decision artifacts under §6 content-based `decisionId`s with the corrected evaluator pin; the old files remain historical evidence (`migration: true`).
4. `data/readiness/snapshots/` stays read-only — content addresses survive unchanged.

_Note_: the tabulated JCS values were computed with the exact-JCS equivalent for these documents (compact separators, UTF-8; no control characters, floats, or `1.0`-style numbers present). Before C2 execution they must be re-issued by the golden-tested `tools/jcs.nim`; only the numbers change, not the direction of the migration.

## 9. Evaluator Relationship (B3) — Do Not Blanket-Align

Two sanctioned modes:

- **(a) Same normative evaluator (single identity)**: only when both evaluators implement the *same identity schema* — same rule-for-rule semantics, same JCS, same component list, same schemas. Only then are their `EvaluationInputIdentity` values directly comparable. Identity-schema agreement is a precondition, never a default.
- **(b) Independent evaluators (repo state today — the default)**: the Python independent chain (`evaluate.py` + `evidence_manifest.json` + `independent_policy.json`) and the Nim chain (`tools/readiness_evaluator.nim` + `data/readiness/evidence/R1..R8.json` + `config/readiness_policy.json`) are DIFFERENT evaluators — different artifacts, different input paths, potentially different rule interpretations — so they hold SEPARATE identities (`evaluatorArtifactBytes` and `executionContractDigest` differ by construction). Therefore:
  - **Never** compare `decisionId` strings across chains — equality of IDs across different evaluators is a meaningless statement;
  - cross-eval comparison happens ONLY at the output boundary — `finalVerdict` / `outcome` / `failureCategory` and per-invariant states — recorded as a `crossCheck` row in `readiness_history.json` (§8);
  - **no "alignment digest"** is created that would merge or equalize the two identities (Theater Prohibition, AGENTS.md §0.9); only the comparison artifacts align.

Current file layout: two active pipelines (Python decisions `decision.independent.20260819T093022Z.json` and `decision.independent.20260819T122137Z.json`; Nim CLI plus `decision.2026-08-1*.json`). This design keeps them independent (mode b) and adds the `crossCheck` record.

---

## Gap-Close Table

| Gap | Where | Change | Status |
|---|---|---|---|
| Timestamp `decisionId`; Identity/Provenance conflation | `evaluate.py:179,195,193`; Nim `decisionDigest` (`tools/readiness_evaluator.nim:749-769`) | §1 formulas; structured `provenance` object; content identity everywhere | planned — gated on §5 |
| I3 conflict (timestamp in decision identity) | `docs/spec/canonical_contract_policy_layer.md:91` vs `docs/spec/continual_revalidation.md:89` | policy revision of I3/I4 or time-bounded waiver (AGENTS §0.10); no silent divergence | planned (architect decision) |
| Three ad-hoc canonicalizers | `evaluate.py:150-151`; `tools/readiness_evaluator.nim:112-141`; `tools/canonical_json.nim:57-127` | new `tools/jcs.nim` (RFC 8785) SSOT + §2.3 semantic rules | planned |
| Evaluator digest is a path hash | `evaluate.py:173-175` (recorded `a8ad5b82ece8ec5670f53f80e8ef0702d2b37e2d70e54d515ed0545934da53fd`) | `Path(__file__).resolve().read_bytes()`; fail closed; P1/P2 pin + carve-out | planned (architect decision) |
| Execution contract not captured (B4) | evaluator runtime; decision payload | §4 contract DOM + identity component; drift → UNRESOLVED | planned |
| Ad-hoc digests in history | `data/readiness/readiness_history.json` | §8 recompute (JCS columns; legacy provenance; snapshots untouched) | planned (post JCS) |
| Nim `decisionDigest` incomplete | `tools/readiness_evaluator.nim:749-769` | §1.2 full-payload identity | planned (with G1) |
| `JCS(schema)` undefined — no schemas exist | new files | §7 schemas + versioned bundle | planned |
| Evaluator relationship unstated (B3) | — | §9 crossCheck contract; no blanket-align | stated in this design |

---

**Deliverable**: this document only. No product code, evaluator, policy, manifest, or schema file was modified.
