# Verification Oracle Contract

> **Status update (2026-09-03):** Observed Audit Contract slice added — observation-only, verdict semantics unchanged. See Scope.

> P0 exact gate path as the permanent semantic oracle for the verification-auditor gate.
> Any optimized/reused result MUST cross-check against this path; mismatch → quarantine/fail-closed.

---

## Identity

**Exact command** (detached substrate, fresh execution, never reuses cached verdicts).

The oracle is invoked against a **clean detached worktree at the immutable SHA** using the
gate runner's direct-call form, which is byte-for-byte identical to the gate command the
P0 tool would execute against the substrate (same argv, same env, fresh execution):

```
git worktree add --detach <WT> <immutable SHA>
cd <WT>
AXIOM_CI=1 AXIOM_CI_PRESERVE_CACHE=1 nim c --hints:off -r \
  src/gate/runners/verification_auditor_gate.nim <WT> full 2
```

| Element | Value |
|---|---|
| Command | `nim c --hints:off -r src/gate/runners/verification_auditor_gate.nim <WT> full 2` |
| argv (`<repoRoot> <mode> <maxJobs>`) | `<WT>` `full` `2` |
| Env vars | `AXIOM_CI=1` `AXIOM_CI_PRESERVE_CACHE=1` (set verbatim) |
| Substrate | Clean detached worktree `<WT>` at immutable SHA (`git worktree add --detach <WT> <SHA>`) |
| Freshness | Always fresh execution; never reuses cached PASS/FAIL from gate_cache |
| Verdict | Gate log `=== Verification Auditor Gate Report ===` + final `PASS`/`FAIL`; exit `0` = PASS, `1` = FAIL |
| `--ref` resolution | `git rev-parse <ref>` → full 40-char SHA |

> **Tooling note (2026-09-03).** `bin/local_ci_gates --gate verification-auditor` is **not** currently
> usable as the oracle rig: `git worktree add --detach` returns before the worktree content is fully
> materialized, so the tool's subsequent gate-source `fileExists` check intermittently races the lazy
> checkout and reports `gate source not found` (`Error: gate binary/source preparation failed`, exit 2).
> A manual `git worktree add --detach` + `verify` succeeds deterministically. The tool bug is tracked
> as a separate follow-up (P0 recovery tooling); the oracle contract therefore uses the direct-call
> form above, which reproduces the identical gate computation deterministically. This decision does not
> change oracle semantics — only the invocation wrapper.

## Oracle Invariant

> Optimized/reused result MUST equal oracle verdict.

- **Dev phase**: 100% cross-check — every optimized path result compared against the P0 oracle for every execution.
- **Production**: sampled cross-check + periodic exhaustive comparison against the P0 oracle.
- **Mismatch → quarantine/fail-closed**: any divergence between an optimized verdict and the P0 oracle verdict triggers quarantine of the optimized artifact and a fail-closed response until root cause is resolved.

## Scope

- **Phase 2.5**: verification-auditor gate only.
- **Extensible per gate**: additional gates may be added to the oracle contract by appending entries with the same structure (command, argv, env, substrate, invariant).
- This contract does not modify gate source, memo/cache code, or verdict semantics. It adds observation-only model modules under `src/verification/` and standalone tools under `tools/ci/`, none of which alter the verdict. This PR is a *wiring/observation* slice: it reads/explains the existing verdict, it does not change it.

### Observed Audit Contract (Phase 2.5 wiring slice)

- `ObservedAuditContract` models ONLY the inputs that actually participate in the verdict: SubjectSnapshot (walkDirRec("src") *.nim), Baseline (data/verification_auditor_baseline.json), GatePolicy (config/gates.json), GateImplementation (binary/source identity), Toolchain. Lock/mode/maxJobs are PROVENANCE, not semantic inputs.
- QueryID is **PROVISIONAL** — no production consumer; **reuse consumption prohibited** (the model logs/reports only; nothing reuses a cached verdict yet).
- Verdict invariant: `same QueryID → same verification semantics → same verdict`. Any runtime read not represented by the query identity = unresolved determinism gap → fail closed for reuse.
- Baseline authority rule: baseline EXISTS → authoritative oracle input; baseline ABSENT → non-authoritative self-calibrating oracle (the gate auto-calibrates by writing the baseline = self-feed coupling → coupling flag `selfCalibration`, result Unknown, reuse prohibited).
- Fail-closed: any Unknown / Unclassified / Incomplete dependency → reuse prohibited. `fcUnknown` FAIL must never be reused (DEBT#452 guard, regression-tested).
- MR (metamorphic) verification: MR-direct (dependency-analysis derived), MR-change (perturbation prediction), MR-observability (reuse=false on unclassified), MR-build (binary sha256 + source digest difference computed, verdict observed, NOT enforced), MR-baseline (authority condition), MR-negative (deliberate model perturbation MUST fail the cross-check — theater-prevention).
- The P0 exact path remains the reference oracle; the cross-check (oracle == model == independent reconstruction) is the semantic-identity proof. Any mismatch → fail-closed (nonzero exit, reuse prohibited). The independent reconstruction shares the category definition but implements its walk/parse separately.

### Semantic Shadow Gate (Phase 2.6) — shadow equivalence

- External shadow wrapper: `tools/ci/verification_shadow_gate.nim` (standalone tool, not a gate, not registered in gates.json/gates.manifest.toml, not wired into CI). The gate runner is invoked UNMODIFIED (P0 exact command: `nim c --hints:off -r src/gate/runners/verification_auditor_gate.nim <WT> full 2`, env `AXIOM_CI=1 AXIOM_CI_PRESERVE_CACHE=1`, workingDir inside a detached worktree) on an ORACLE substrate, and computes the ObservedAuditContract shadow model verdict on a SEPARATE MODEL substrate; both substrates are detached worktrees created from the SAME initial fixture SHA (`--ref`, default HEAD). PR#28 frozen files untouched.
- Substrate isolation: same initial fixture (SHA) → isolated Oracle/Model detached substrates → isolated build/runtime side effects; pre-flight verification mandatory (paths distinct + not live repo root, each `git rev-parse HEAD` == fixture SHA, start-of-run content 3-way match); live-repo direct execution OUT of scope.
- Equivalence invariant: fresh actual gate verdict == shadow semantic verdict; output 3-way separated (ActualVerdict | ModelVerdict | CrossCheckStatus); MISMATCH → fail-closed (exit≠0, reuse prohibited).
- Evidence-only (no decision): this PR does NOT compute CanReuse; `decideReuse()`/`StoredVerificationResult` NOT called; raw evidence only (queryId PROVISIONAL, per-dependency resolution, observationStatus, couplingFlags); no summary/decision booleans.
- QueryID status: shadow-validated but **PROVISIONAL** — conditional promotion (replay matrix passes + zero unclassified observations + observed input set unchanged; any new unclassified observation → re-validation fail-closed).
- GateImplDigest = observed producer/build identity; semantic-input classification PROVISIONAL (observation-based, not finalized).
- Risks observed only: baseline self-feed / binary identity (existence-only) / environment — recorded, behavior unchanged in this PR.
- Negative test matrix: bidirectional ≥2 each — model-side (N1 expectedCount corruption → MISMATCH; N2 adapter misclassification → fail-closed) and oracle-side (N3 verdict parse inversion → MISMATCH; N4 domainCount corruption → MISMATCH).

### Producer Boundary Contract (Phase 2.7)

- **Phase separation**: Separate the verification computation from the computation that PRODUCES the verifier:
  - **PRODUCER PHASE** (Source → Toolchain → Gate Binary → ProducerIdentity): builds the producer identity that characterizes *who/what produced the verifier*.
  - **VERIFICATION PHASE** (Subject + Baseline + Policy + Gate Binary → Verdict): runs the actual verification against the subject.
- **Final structure (PROVISIONAL)**:
  - `SemanticQuery` (SubjectSnapshot / Baseline / GatePolicy / SemanticDependencies) — the semantic inputs to verification.
  - `ProducerIdentity` (GateBinary / Compiler / Stdlib / BuildConfig) — the identity of the producer that built the verifier.
  - `VerificationIdentity = H(SemanticQuery, ProducerIdentity)` — the combined identity.
- **Adapter layer**: existing 15-value `ReadClass` (syscall facts, unchanged, no new enum values) gets a *second* classification layer `DependencyDomain` {ddSemantic, ddProducer, ddProvenance, ddInternal, ddOutput, ddUnknown}. Producer-phase observations → ddProducer; ddUnknown → fail-closed (no reuse).
- **Components of ProducerIdentity are NOT arbitrary**: determined by observation + E1–E5 stability/mutation experiments; any component without experimental backing stays PROVISIONAL.
- **Experimental contract**: same toolchain (read-set may vary) → same ProducerIdentity → same semantic result; compiler/stdlib/build-input mutation → ProducerIdentity changes.
- **E2-A vs E2-B separation** (identity detects mutation ≠ verdict preserved under neutral mutation — separate propositions, each observed/recorded):
  - E2-A: gate-source SUBSTANTIVE mutation → ProducerIdentity changes (identity detects producer mutation).
  - E2-B: comment/whitespace producer-NEUTRAL mutation → ProducerIdentity relation OBSERVED + verdict relation OBSERVED — "identity가 mutation을 감지한다"와 "그 mutation에서 verdict가 유지된다"는 별개의 명제이므로 각각 관측·기록하고 verdict 무변화를 단언하지 않음. A substantive-mutation verdict change is a NORMAL semantic change, not asserted.
- **CanReuse NOT connected in this phase.**
- `producer_identity.nim` is pure (no I/O); `producer_boundary_check.nim` is a standalone tool (NOT a gate, NOT registered, NOT wired into CI).

## References

- `tools/ci/local_ci_gates.nim` — P0 exact gate tool source.
- `data/benchmarks/verification_auditor_oracle_<YYYYMMDD>.json` — baseline measurement artifacts.
- `src/verification/observed_audit_contract.nim` — observation-only model of the verification-auditor verdict (PROVISIONAL).
- `tools/ci/verification_crosscheck.nim` — standalone cross-check runner (NOT a gate, NOT registered in gates.json, NOT wired into CI).
- `tools/ci/verification_shadow_gate.nim` — standalone shadow gate runner (NOT a gate, NOT registered, NOT wired into CI).
- `tools/ci/verification_probe.nim` — existing strace-based observer.
- `tests/unit/test_observed_audit_contract.nim` — 67 checks for the observed audit contract model.
- `tests/unit/test_gate_memo_fcunknown_regression.nim` — fcUnknown FAIL never reused (DEBT#452 soundness guard).
- `docs/design/final_query_identity.md` — PROVISIONAL status.
- `src/verification/producer_identity.nim` — PURE contract: `ProducerPhase`, `DependencyDomain`, `ProducerIdentity`, `producerIdentityDigest`, `provisionalVerificationIdentity` (PROVISIONAL).
- `tools/ci/producer_boundary_check.nim` — standalone tool with execve phase-boundary strace attribution + experiments E1–E5 (NOT a gate, NOT registered, NOT wired into CI).

### Persistent Verification Result Reuse (Phase 3.1 — transport/semantic two-layer contract)

- **Scope**: 게이트 실행 간(cross-run) verification-auditor 결과 재사용. 이 문서는 계약의 권위 정의로,
  실행 배선은 `Makefile`(`ci-gates`)에 있다. (원래 CI 측정 워크플로 `verification-reuse-measure.yml`와
  `.github/workflows/ci.yml` 배선은 CI=0 cutover, 2026-09-20으로 소멸)
- **2-계층 분리 (핵심 계약)**:
  - **transport**: GitHub Actions cache(`.axiom/cache` 복원) — `cache-matched-key = X`는 "가장 가까운
    최근 blob" 선택이며 **비결정적일 수 있다**(restore-keys prefix 매칭, branch 스코프, immutable key).
  - **semantic**: `(gateId, canonicalVerificationIdentity)` **exact lookup** — `canonical identity = Y`,
    `memo lookup(Y) = HIT`, 저장 결과 == PASS, validated closure clean.
  - **`X == Y`를 요구하거나 단언하지 않는다.** 두 값은 독립 네임스페이스. stale snapshot을 복원해도
    exact identity lookup이 HIT면 정상; 반대로 캐시가 복원돼도 semantic lookup이 MISS면 **exact gate가
    정답**. correctness는 전적으로 semantic 계층에 귀속.
- **fail-closed 유지**: identity 불일치 / unknown dependency / 저장 결과 != authoritative PASS 중
  하나라도 있으면 "HIT처럼 보여도" 재사용 금지 → exact gate (CI에서도 동일).
- **Dedup 불변식**: `ci-gates → bin/gate_hook ci → verification-auditor → trySkipGate`
  (HIT → fresh 0회 / MISS → fresh 1회). verification-auditor의 **fresh gate invocation count ≤ 1**.
  `verification-auditor`는 `alwaysRun = true`(filesPatternPruning 면제 — executor.nim:772의 유일한
  결합 지점; 의존성/순서/스케줄링 규칙 무영향)이며, Makefile의 직접 호출은 제거됐다. 빈 changedFiles에서도
  scheduled됨을 드라이런으로 검증한다.
- **put-if-absent**: 동시 저장은 CAS content-address 덕에 멱등(동일 identity+동일 결과); 캐시가
  transport이므로 분산 lock 없음. same-key-different-result 충돌은 기록하고 해당 identity는
  fail-closed(재계산) — silent race 금지.
- **측정 프로토콜**: fill(강제 miss → exact gate → store) → hit-check(신규 ephemeral 러너에서
  복원 → exact lookup → HIT → gate 0회). (원래 판정 evidence는 `verification-reuse-measure.yml`에서
  산출했으나 CI=0 cutover, 2026-09-20으로 해당 워크플로 소멸 — 로컬 `gate_hook ci` 드라이런으로 동일
  프로토콜 검증)
- **성능 기대치**: verification-auditor는 CI에서 ~6.6s×1 — verify-integration(warm 48.6m)의 일부일 뿐;
  이 계약의 1차 목표는 "동일 identity gate의 fresh 실행 제거 실증"이지 총 54분 제거가 아니다.
