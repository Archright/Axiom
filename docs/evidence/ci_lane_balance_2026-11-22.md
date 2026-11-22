# GO-critical 2-lane rebalance decision — VS-CI-01 REJECTED (2026-11-22)

> **Status**: Measurement complete. This document adds the decision record only — no change to workflows, checks, required checks, or `max_entries_to_build`.
> **Metric contract**: `docs/spec/ci_critical_path_metric.md` (metric definition document)
> **Decision data**: `data/ci_optimization/vs_ci_01_lane_rebalance_decision_2026-11-22.json`
> **Sample**: 25 completed merge-group runs (2026-11-21/2026-11-22)
> **Lane composition**: `.github/workflows/admission-check.yml` `go-critical-lane` matrix — lane 0 = `s1a`; lane 1 = `proof_integrity` + `d2_golden` + `d2_persist`

## §0. Verdict

> **Verdict: REJECTED — benefit ~2–4 s (≈2%) is inside noise; no verification change**

| Item | Value | Note |
|---|---:|---|
| lane 0 wall p50 | **139 s** | 25 completed merge-group runs |
| lane 1 wall p50 | **152 s** | same cohort |
| lane gap p50 | **10 s** | p50 of the per-run difference between the two lanes |
| longest rebalanceable item after cache warm-up | **`s1a` 26 s** | the only measured rebalance candidate |
| fixed per-lane provisioning (sum) | **≈110 s** | dominant term in lane cost |
| — `setup-axiom-toolchain` | 47–48 s | provisioning component |
| — `evidenceId` | 36 s | provisioning component |
| maximum benefit of an optimal deterministic rebalance (derived value) | **≈2–4 s / 152 s lane (≈2%)** | no rebalance was implemented |

Conclusion: however the two GO-critical lanes are rebalanced, wall time does not change materially. The dominant cost term is not work imbalance but **fixed provisioning**.

> wall time is dominated by fixed per-lane provisioning, not by work imbalance.

## §1. Background

`go-critical-lane` splits the GO-critical admission-contract tests across two parallel lanes. The premise of proposal VS-CI-01 ("GO-critical lane rebalancing") was that changing the work split between the two lanes would shorten the slower lane and thus reduce merge-group wall time. This measurement measured the upper bound of that premise.

## §2. Measurement

The subject is 25 merge-group runs completed on 2026-11-21/22. Table values are the p50 of per-lane wall and the p50 of the per-run lane difference, and the sample includes only completed runs.

| Metric | Measured value |
|---|---:|
| lane 0 wall p50 | 139 s |
| lane 1 wall p50 | 152 s |
| lane gap p50 | 10 s |
| fixed per-lane provisioning | ≈110 s (`setup-axiom-toolchain` 47–48 s, `evidenceId` 36 s) |
| longest rebalanceable item after cache warm-up | `s1a` 26 s |
| maximum benefit of an optimal deterministic rebalance | ≈2–4 s (≈2% of the 152 s lane) |

## §3. Interpretation

- About 110 s of lane 1's 152 s is fixed provisioning. Only the remaining work segment can be reduced by rebalancing.
- After cache warm-up, the longest rebalanceable item is `s1a` at 26 s. Even an optimal distribution that includes this item yields a benefit of only **≈2–4 s**.
- That is **≈2%** of the 152 s lane and falls within the variation (noise) observed in the 25-run sample. Lane rebalancing therefore cannot materially change wall time.

## §4. Decision

- **Decision id**: VS-CI-01
- **Decision**: `REJECTED`
- **Reason code**: `INSUFFICIENT_BENEFIT_FIXED_PROVISIONING_DOMINATES`
- **Decision content**: Rebalancing the two GO-critical lanes is rejected as a CI optimization. No rebalance of any kind was implemented.
- **Invariant**: This decision removes no verification. No check is deleted or skipped, and no required check is changed. `max_entries_to_build=100` is also unchanged.

> this decision removes no verification and changes no required check

## §5. Revisit conditions

When fixed per-lane provisioning decreases and work imbalance becomes the dominant term in lane cost, re-measure under the same cohort protocol (`docs/spec/ci_critical_path_metric.md` §1·§5). This record fixes the decision until then.

## §6. References

- `docs/spec/ci_critical_path_metric.md` — metric definition document (cohort, wall, and step attribution conventions)
- `docs/evidence/ci_critical_path_baseline_2026-11-20.md` — prior critical-path baseline (observation that the provisioning family dominates)
- `docs/evidence/ci_provisioning_decomposition_2026-11-20.md` — component decomposition of `setup-axiom-toolchain`
- `data/ci_optimization/vs_ci_01_lane_rebalance_decision_2026-11-22.json` — machine-readable record of this decision

## §7. Limitations

- n=25 completed merge-group runs. Only p50 and the measured gap are recorded; no p95 is declared.
- ≈2–4 s is the upper bound of an optimal deterministic rebalance. No rebalance was executed, so it is not a measured after value.
- Of the ≈110 s provisioning sum, only `setup-axiom-toolchain` and `evidenceId` were measured individually; the remaining components are recorded only as a total.
- Per-lane values are per `go-critical-lane` matrix leg. The canonical definition of whole-run wall follows `docs/spec/ci_acceptance_contract.md` §6.