# Org Gate Handoff — `Archright/.github` merge-admission execution authority

- **Date**: 2026-10-04
- **Subject**: `Archright/Axiom` PR #457 (`chore(surface): v55 — re-authorise the 4 CI-authority paths`)
- **Authority in question**: `Archright/.github/.github/workflows/admission-gate.yml` (external org repo — **not owned by Axiom, not modified by this analysis**)
- **Status**: SPECIFICATION ONLY. No org-side or Axiom-side workflow file was modified. No git-mutating command was run.

---

## 0. TL;DR for the architect

Three things, in order of what actually blocks you:

1. **The `NO_CERT` ordering defect is real as a *design* defect but is no longer the *active* blocker.** As of run `37179209673` attempt 2 (head `4e29a03f`), `admission` **succeeds** — `verdict.result = mergeGo`, `reasonCode = GO`. The two-pass convergence described in the org gate's own comments worked. **Do not apply an ordering change on the strength of the attempt-1 log alone.**
2. **The live blocker is an artifact-identity collision across re-runs, and it is Axiom-side, not org-side.** `mint-prepare` fails closed with `expected exactly one artifact named 'admission-check-<headSha>', found 2`. See §5.
3. **Candidate (A) as posed is structurally invalid** — it creates a `needs` cycle in the current graph and GitHub rejects the whole workflow at plan time. Candidate (B) is the ADR-sanctioned reading but cannot be applied from the org file alone. See §4.

---

## 1. Provenance of this document — read vs. inferred

**Read directly** (GitHub API, read-only; base64-decoded):

```bash
gh api repos/Archright/.github/contents/.github/workflows/admission-gate.yml
```

- blob sha `14b26ba3fcf5cf21d9a5f7734704ce664f4e41bf`, ref `main`, size 16812, **255 lines**
- local copy verified at `/tmp/org_admission-gate.yml`, sha256 `c54c11e5b7a4a95e327f1a40538f62984f38490ad3ed1819747dce6726fc119e`

Also read directly:

- `Archright/.github` workflow inventory (2 files only): `admission-gate.yml`, `landing-integrity.yml`
- run/job/log payloads for runs `37177559181` and `37179209673`
- Axiom repo rulesets (`main` = 20303214)
- Axiom-side sources read locally (see §7)

**Nothing in §2–§5 is inferred.** Where behaviour could not be proved from text alone it was proved from an observed run, and the run id is cited inline.

---

## 2. Current job graph — measured, with line citations

All line numbers are in `Archright/.github/.github/workflows/admission-gate.yml` @ blob `14b26ba3`.

| Job | Line | `needs:` | `if:` | Notes |
|---|---|---|---|---|
| `admission` | 88 | **(none)** | **(none)** | `uses:` only, line 94 |
| `mint-prepare` | 114 | `[admission]` (line 115) | `!cancelled()` (line 131) | `uses:` line 136 |
| `mint-publish` | 164 | `[mint-prepare]` (line 165) | `!cancelled()` (line 169) | `uses:` line 174 |
| `gateway` | 196 | (none) | (none) | `uses:` line 199 |
| `admission-check` (verdict) | 231 | `[admission, mint-prepare, mint-publish, gateway]` (line 233) | `always()` (line 234) | `name: admission-check`, line 232 |

Shape:

```
gateway ────────────────────────────────┐
                                        │
admission ──> mint-prepare ──> mint-publish
                                        │
        └──────── all four ─────────────┴──> admission-check (verdict)
```

**Key structural fact**: the mint chain is *rooted at* `admission`. `admission` is the head of the DAG, not a leaf. Everything downstream of the certificate producer hangs off the certificate consumer.

Observed execution order, run `37179209673` (attempt 2, head `4e29a03f`) — matches the graph exactly:

```
admission / build-base-artifacts  success  05:12:25 → 05:16:21
gateway / select                  success  05:12:26 → 05:13:20
admission / admission-check       success  05:27:27 → 05:30:13
mint-prepare / prepare            failure  05:30:16 → 05:30:44
mint-publish / publish            failure  05:30:48 → 05:31:07
admission-check   (verdict)       failure  05:31:11 → 05:31:14
```

---

## 3. Finding: the NO_CERT premise is outdated

The task premise quoted run `37177559181` attempt 1. That run is **stale** — its head is `1171fd95`, while PR #457's current head is `4e29a03f`. Its re-run (attempt 2) and the current run both show `admission` **succeeding**.

Verbatim from the current run's `admission / admission-check` log:

```json
{"prNumber":457,"headSha":"4e29a03f86ad8a4ee9e107bf90f95fb1fc39cffe",
 "baseSha":"ce726fc9486fc67bdbc1499f8f724277ccae31cb",
 "verdict":{"result":"mergeGo","reasonCode":"GO",
   "reason":"admission passes cleared (base freshness bound to main ce726fc9486f; GitHub re-binds at merge time)"},
 "qualification":"UNSPECIFIED",
 "rotationCheck":null,
 "rotationNote":"closure inputs absent (AXIOM_DERIVED_H_PATH/AXIOM_DERIVED_B_PATH/AXIOM_PIN_H_PATH) — rotation Pass skipped"}
```

Consequences:

- **The side-ref ledger convergence works.** Attempt 1 minted + appended; attempt 2 found it. The org gate's own design note (lines 128–130, *"Convergence is two-pass — this run mints and publishes, the next run's predicate finds the ledger cert"*) is accurate as written.
- **`UNSPECIFIED` did not block.** See §7 — the documented "fail-closes on UNSPECIFIED" does not match implemented behaviour.
- **Any `needs:` change motivated by NO_CERT is now unjustified.** Reordering to fix a symptom that is no longer firing would be speculative mutation of a merge-admission control kernel.

---

## 4. Candidate (A) vs (B)

### (A) reorder — `admission: needs: [mint-publish]` → **INVALID, DO NOT APPLY**

Adding the edge creates:

```
admission ──> mint-prepare ──> mint-publish ──> admission
```

`admission` already has no `needs`, and `mint-prepare` declares `needs: [admission]` at line 115. `needs` must form a DAG; GitHub Actions rejects cyclic `needs` **at workflow-plan time**, before any job starts. The consequence is a **zero-job run** with no check run ever posted for `admission-check` — the required status check context never resolves, and PR #457 blocks indefinitely with no diagnosable job.

This is strictly worse than the current failure (which at least produces four diagnosable job conclusions).

### (B) pass the artifact — **ADR-sanctioned, but not applicable from the org file alone**

`ADR-0022` (`docs/adr/0022-admission-artifact-authority.md:494-498`) verbatim:

> **NO_CERT 의미 갱신**: `NO_CERT` = 평가 대상 head에 대해 유효한 certificate이 어느 source에도 없음. `--cert`가 있으면 artifact가, 없으면 side-ref ledger가 source다(bootstrap/recovery). ledger는 certificate의 존재를 확인하는 durable 장소이지 certificate 생성의 필수 입력이 아니다 — 순환 의존(admission ← ledger ← attest-append)이 제거된다.

So **(B) is the sanctioned reading**, and ADR-0022 explicitly names the cycle `admission ← ledger ← attest-append` as the thing to remove. The CLI half already exists: `src/cli/merge_cli.nim:1804-1808` parses `--cert <path>` and threads it into both the dry-run and the actuator paths (line 1815-1816).

But (B) **cannot be expressed in `admission-gate.yml` as things stand**, for two independent reasons:

1. **A `uses:` job cannot have `steps:`.** `admission` (line 88-94) is a reusable-workflow call. GitHub Actions rejects `steps` on a `uses` job outright. The org file therefore cannot download the artifact itself; at most it could forward a name via a `with:` input that the callee does not yet declare.
2. **Same-run artifact availability still requires the cycle.** The certificate artifact `subject-certificate-<run_attempt>` is uploaded by `mint-publish`, which is *downstream* of `admission`. Even with a callee input, the artifact does not exist when `admission` runs.

To make (B) work, the certificate *consumer* and the *witness producer* must be different jobs. Today they are the same callee job (`admission-check.yml:378`, `admission-check`, which both attests the witness at :787-827 and evaluates the predicate at :858-946). **Splitting that callee job is Axiom-side work**, not org-side.

### Verdict

| | (A) | (B) |
|---|---|---|
| Sanctioned by ADR-0022 | No | **Yes** |
| Expressible in the org file today | No (cycle → zero-job) | No (`uses:` job, plus cycle) |
| Needed *now* | **No** — `admission` already passes | **No** — ledger path converges |
| Needed ever | No | Yes, if the ledger path is ever retired, **and only after the callee split** |

**Recommendation: apply neither.** (B) is the correct long-term shape and is the one to build toward; (A) must never be applied in the current topology.

---

## 5. The live blocker: artifact identity collides across `run_attempt`

This is what is actually failing now, and it is **Axiom-side**.

### 5.1 Observed failure

`mint-prepare / prepare`, run `37179209673`:

```
MINT_ART: FAIL — expected exactly one artifact named
  'admission-check-4e29a03f86ad8a4ee9e107bf90f95fb1fc39cffe', found 2 (fail-closed)
```

`mint-publish / publish` (cascade — prepare never uploaded):

```
MINT_PUB_ART: FAIL — expected exactly one artifact named
  'subject-certificate-2', found 0 (trusted-name violation) (fail-closed)
```

The same collision occurred on the previous run (`37177559181`, head `1171fd95`, identical message).

### 5.2 Root cause

The witness artifact name is **not** attempt-scoped:

- `Archright/Axiom/.github/workflows/admission-check.yml:956`
  ```yaml
  name: admission-check-${{ github.event.pull_request.head.sha || github.event.merge_group.head_sha || github.sha }}
  ```
- Uploaded with `if: always()` at line 949, so it lands on every attempt including failed ones.
- Artifacts are scoped to `run_id`, and `run_attempt` shares the `run_id` — so attempt 2 accumulates a second artifact under the *same* name inside the same run.
- The mint's lookup asserts **exactly one** match (`certificate-mint.yml`, prepare step (3)) and fails closed on `found != 1`.

Contrast with the certificate artifact, which *is* attempt-scoped — `subject-certificate-${{ inputs.runAttempt }}` (`certificate-mint.yml:767`). The org gate already forwards the attempt (`admission-gate.yml:140` and `:178` pass `runAttempt: ${{ github.run_attempt }}`). The witness name is simply missing the same qualifier. That asymmetry is the whole bug.

### 5.3 Why this is a treadmill

Every re-run of a run whose admission fails once adds another `admission-check-<headSha>` artifact. From the second attempt onward, `mint-prepare` can *never* pass for that `run_id`. The mint is therefore only reachable on the **first** attempt of a run — i.e. precisely the attempt where `admission` has not yet appended the certificate. The two behaviours are mutually exclusive.

This is the concrete form the `NO_CERT` problem takes today: the certificate is needed after minting, but the artifact collision makes re-minting impossible after the first attempt.

### 5.4 Required fix (Axiom-side, then org-side pin advance)

**Axiom side** — make the witness artifact name attempt-scoped, symmetric with the certificate artifact:

```yaml
# .github/workflows/admission-check.yml:956  (BEFORE)
name: admission-check-${{ github.event.pull_request.head.sha || github.event.merge_group.head_sha || github.sha }}

# AFTER
name: admission-check-${{ github.event.pull_request.head.sha || github.event.merge_group.head_sha || github.sha }}-${{ github.run_attempt }}
```

and the matching lookup in `certificate-mint.yml`'s prepare step (3) must build `want_name` the same way from `inputs.runAttempt` (already forwarded by the org gate at `admission-gate.yml:140`).

> This touches `admission-check.yml`, which another agent is currently editing. It is stated here as a specification, **not applied**.

**Org side** — the only org-repo change this fix requires is advancing the callee pin at `admission-gate.yml:94`:

```yaml
# BEFORE
    uses: Archright/Axiom/.github/workflows/admission-check.yml@0a7ca6b4e2c23413dc309f4a94361ad0e95a3851

# AFTER   (placeholder — replace with the real landing SHA)
    uses: Archright/Axiom/.github/workflows/admission-check.yml@<NEW_AXIOM_SHA>
```

No `needs:`, `if:`, or `permissions:` change. The pin is sha-locked by the org ruleset named in the file's own header (lines 33–36: *"org ruleset 24041674(axiom-admission-gate)의 workflows 규칙이 이 파일을 sha pin하며"*), so this is an org-repo PR regardless.

---

## 6. Aggregate-job (`admission-check` verdict) safety analysis

Verified against the real file text (`admission-gate.yml:231-255`), not from memory.

### 6.1 Does the aggregate still fire?

**Yes.** Line 234 is `if: ${{ always() }}`, which replaces GitHub's implicit `success()` default. `always()` fires regardless of the `needs` results.

Empirically confirmed on run `37179209673`: `mint-prepare` and `mint-publish` both concluded `failure`, and the verdict job still started (05:31:11) and concluded `failure`. It did not skip.

### 6.2 Does a mint failure still block?

**Yes.** Lines 249-252:

```bash
[ "$RESULT_MINT_PREPARE" = "success" ] \
  || fail "needed job 'mint-prepare' result='$RESULT_MINT_PREPARE' (expected 'success' — skipped/cancelled/failed must block, never green)"
[ "$RESULT_MINT_PUBLISH" = "success" ] \
  || fail "needed job 'mint-publish' result='$RESULT_MINT_PUBLISH' (expected 'success' — skipped/cancelled/failed must block, never green)"
```

Only the literal string `success` passes. `skipped` — the value a job takes when its `if:` evaluates false — fails the assertion, so a `skipped` mint blocks. Confirmed: in run `37179209673`, `mint-prepare / publish` (a *different* job inside the same callee) shows `skipped`, and the verdict correctly failed closed rather than reading it as success.

### 6.3 If `admission` gained `needs: [mint-publish]`

Moot in practice — a cyclic graph never starts any job, so `needs.admission.result` is never evaluated. But for the record: the verdict would remain syntactically safe (`always()` still fires, and `result` would be `skipped` → assertion fails → fail-closed). The failure mode is upstream, not in the verdict.

### 6.4 One real asymmetry worth noting

`mint-prepare`/`mint-publish` carry `if: ${{ !cancelled() }}` (lines 131, 169), so they run even when `admission` **fails** — deliberate, per the comment at lines 116-130 (*"certificate minting is an evidence authority"*). The consequence: an `admission` failure does **not** short-circuit the mint, and the verdict's four-way `∧` is what ultimately enforces fail-closed. That structure is correct and should be preserved.

Do **not** "simplify" `always()` away, and do **not** replace the four assertions with a count-based check; the current form is what makes `skipped` blocking.

---

## 7. Second defect: `derived-closure` / `qualification: UNSPECIFIED`

### 7.1 What the contract says

`Archright/Axiom/.github/workflows/admission-check.yml:843-849`:

> Gate-era rotation closure inputs arrive as the SAME-RUN artifact `derived-closure` (uploaded by the org gate's closure job) — the only cross-runner channel; a repo var cannot carry per-run data.
> Pre-gate: artifact absent → rotation Pass skipped → qualification UNSPECIFIED (**the gate verdict fail-closes on UNSPECIFIED**).
> NO deriver runs in this workflow; the files come from the gate only.

and `src/gate/slice_catalog.nim:93`:

> "Rotation closure inputs only — no deriver runs inside admission-check.yml (pre-gate artifact absent → UNSPECIFIED, fail-closed at gate verdict)."

### 7.2 Reality: latent, not active

In the current passing run the verdict JSON carries `qualification: "UNSPECIFIED"` **and** `result: "mergeGo"` (quoted verbatim in §3). The documented fail-closed on UNSPECIFIED is **not** what the pinned callee does.

Code path (`src/cli/merge_cli.nim`): the rotation-Pass-skipped branches set `result.qualification = rqNone` (lines 515, 523, 529), `qualificationName(rqUnspecified) = "UNSPECIFIED"` (line 542), and the deny predicate at line 723 tests `rot.qualification == rqNone` — the skipped-pass path is not treated as a denial.

**This is a documentation/behaviour divergence, not a merge blocker.** It should be recorded as debt, not silently patched. It is worth deciding deliberately whether UNSPECIFIED should deny — that is a product/policy call for the architect, and `docs/spec/` is the place it belongs (§5 SSOT).

### 7.3 Ownership of the closure producer — nobody currently

Two independent gaps, **either one alone is sufficient to keep UNSPECIFIED permanent**:

1. **Org side — no producer exists.** `Archright/.github` contains exactly two workflow files (`admission-gate.yml`, `landing-integrity.yml`). Grepping both for `derived-closure` / `derived-H` / `AXIOM_DERIVED` yields matches only in *comments*. The `closure-deriver` job was explicitly decommissioned by the control-kernel cutover — `admission-gate.yml:43-45`:
   > `#   closure-deriver — SL-02 deriver 컴파일·실행 + closure 등식`
   > `#                     (callee 내부 derived-closure load도 scope_sl02 게이트로 NO-FIRE)`

   The only surviving mention of a producer is the aspirational "uploaded by the org gate's closure job" in the Axiom-side comment at :844 — a **dangling reference to a job that no longer exists**.

2. **Axiom side — the consumer is dead code.** The download step at `admission-check.yml:850-856` is gated `if: steps.slice-engine.outputs.scope_sl02 == 'true'`. `config/policy/epoch_manifest.json` `implementedSlices` is:

   ```json
   ["SL-08","SL-01","SL-03","SL-04","SL-12","SL-10","SL-0713","SL-05"]
   ```

   `SL-02` is **absent**. So `scope_sl02` is always `'false'` and the step never executes — even a correctly-supplied artifact would be ignored.

   (For contrast: `SL-0713` **is** implemented, which is why the ledger append in `certificate-mint.yml` publish `(P7)` does fire. My earlier hypothesis that the ledger append was gated off was wrong and is corrected here.)

### 7.4 Required action, stated separately

To move `qualification` off `UNSPECIFIED`, **two** landings are needed — this is **not** an org-file-only change:

- **Axiom repo**: land the SL-02 producer path in the callee and add `"SL-02"` to `implementedSlices` in `config/policy/epoch_manifest.json` (which is `main`-authority data — expect a decision-binding / epoch-cutover review per §2.5 and §2.6).
- **Org repo**: re-add a `derived-closure` **producer** job to `admission-gate.yml` that uploads the artifact named `derived-closure` containing exactly `derived-H.txt`, `derived-B.txt`, `pin-H.json` (the all-or-none set enforced at `admission-check.yml:877-888`), and give `admission` a `needs:` on it.

The artifact must be present **before** `admission` runs, so this producer job must be `needs:`-free or depend only on jobs upstream of `admission`. It consumes base-commit facts (B/H tree identities), not admission output, so a free-running producer job is structurally sound here.

---

## 8. Consolidated applyable change set

Ordered by what unblocks first. **Change 0 is the one that matters today.**

### Change 0 — artifact-name attempt scoping (Axiom) + pin advance (org)

Axiom-side before/after is in §5.4. Org-side before/after is the single `uses:` line at `admission-gate.yml:94`. **No `needs:` or `if:` change.** This is the change that turns the current red into green.

### Change 1 — `derived-closure` producer (org) + SL-02 landing (Axiom)

See §7.4. Independent of Change 0; only affects `qualification`, which does not currently gate.

### Change 2 — certificate via `--cert` artifact (both repos, **later**)

Only if the side-ref ledger path is ever retired. Requires, in order:

1. **Axiom**: split the `admission-check` callee job (`:378`) into a witness-producing job and a predicate-evaluating job, keeping the predicate job's name `admission-check` so the ruleset context at `Axiom` ruleset `main` (20303214, `required_status_checks: ["admission-check"]`, `strict: true`) is unchanged.
2. **Axiom**: declare a `workflow_call` input on the callee carrying the artifact name, and pass it to `ax merge --dry-run --json --cert <path>` (the CLI flag already exists at `merge_cli.nim:1804`).
3. **Org**: the predicate job gains `needs:` on `mint-publish` **and** the mint chain loses its root on the witness-producing job. Only then is the DAG acyclic.

> ⚠️ Applying any fragment of Change 2 alone — in particular the `needs:` from step 3 without step 1 — produces the zero-job cyclic-graph failure described in §4.

### Never apply

`admission: needs: [mint-publish]` against the current graph (§4).

---

## 9. Verification checklist for the architect

After applying Change 0:

1. **Confirm the Axiom landing exists and is green** on the Axiom repo — the witness artifact name carries `-${{ github.run_attempt }}` in `admission-check.yml`, and `certificate-mint.yml`'s prepare `want_name` matches.
2. **Open a PR to `Archright/.github`** bumping the `admission-check.yml@` pin at `admission-gate.yml:94` to that SHA. The org ruleset sha-pins this file; expect the ruleset PR to be the merge path.
3. **Trigger the gate on a fresh PR** (not a re-run — a re-run carries the colliding artifacts of §5). Use `gh workflow run` or a new push.
4. **Assert the artifact count is 1** in the `mint-prepare / prepare` log:
   ```bash
   gh api "repos/Archright/Axiom/actions/runs/<RUN_ID>/artifacts" \
     --jq '.artifacts[] | "\(.id)\t\(.name)\t\(.expired)"'
   ```
   Expect exactly one `admission-check-<head>-1` and exactly one `subject-certificate-1`.
5. **Assert the witness sha-pin matched** — the log line `MINT_ART: OK — witness sha-pinned + provenance (H/B/run/pr) fully matched` must appear (it does fire today, immediately before the `found 2` failure).
6. **Assert the four-way verdict** is green:
   ```bash
   gh api "repos/Archright/Axiom/actions/runs/<RUN_ID>/jobs?per_page=100" \
     --jq '.jobs[] | "\(.name)\t\(.conclusion)"'
   ```
   All four of `admission / admission-check`, `mint-prepare / prepare`, `mint-publish / publish`, `admission-check` must be `success`. **Any** non-`success` is a correct fail-closed, not a bug — read the `[verdict] ... (fail-closed)` line.
7. **Verify the merge-admission authority itself**, not just the jobs — the Axiom ruleset context is `admission-check`, so:
   ```bash
   gh api repos/Archright/Axiom/commits/<HEAD>/check-runs --jq '.check_runs[] | "\(.name)\t\(.conclusion)"'
   ```
   A green `admission-check` check run is the only observation that means "merge-admitted" (§2.3: authority is GitHub; job success alone does not substitute).
8. **Negative test** — deliberately break the mint (or use a stale base) and confirm the verdict still fails closed with the expected `ADMISSION_GATE: FAIL` line. This guards against a "the gate always passes" regression, which is the §0.9 theater failure mode.
9. **Only after 1–8 are green**, consider Change 1 (`derived-closure`) and Change 2 (`--cert`).

---

## 10. Open questions for the architect

1. **Should `UNSPECIFIED` deny?** Docs (`admission-check.yml:847-848`, `slice_catalog.nim:93`) say yes; the pinned callee says no. This divergence needs a deliberate decision and a `docs/spec/` landing — it is currently masking a real gate gap.
2. **Is the two-pass convergence acceptable long-term?** It requires a re-run after the first failure of every new head. That is acceptable for `pull_request` (ruleset `main` has no merge-queue rule, so nothing is wedged), but it is a poor fit if a merge-queue rule is ever added — a `merge_group` run has no re-run affordance.
3. **Who owns the SL-02 epoch landing?** §7.3 needs both a producer (org) and a manifest change (Axiom `main`-authority data). Neither is derivable from this analysis.

---

## 11. What this analysis did not do

- Did not modify, clone, or push anything in `Archright/.github`.
- Did not modify any `.github/workflows/**` in `Archright/Axiom` (including `admission-check.yml`, under concurrent edit by another agent — all Axiom-side citations are against working-tree state at commit `4e29a03f`, and `admission-check.yml` was clean at the time of reading).
- Did not run `git add`/`commit`/`stash`/`reset`/`checkout`/`switch`.
- Did not modify `src/`, `ci/`, `Makefile`, `config/`, `data/`, or `tests/`.
- This document is the only file created.
